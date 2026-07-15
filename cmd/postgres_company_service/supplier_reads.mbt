///|
/// Canonical supplier projections mirror the frozen ERP bridge.  These are
/// observations of the local projection only; they do not qualify or mutate a
/// provider and never imply external supplier execution.
async fn supplier_projection_items(
  supplier_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let filter = match supplier_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid supplier_id")
      }
      " AND latest.aggregate_id = " + @postgres.sql_literal(value)
    }
    None => ""
  }
  let output = run_sql(
    "WITH latest AS (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'supplier' " +
    "ORDER BY aggregate_id, revision DESC) SELECT " +
    "encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'supplier_code', latest.payload->>'supplier_code', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'name', latest.payload->>'name', latest.aggregate_id), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'category_code', latest.payload->>'category_code', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'evaluation', latest.payload->>'evaluation', 'unrated'), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'state', latest.payload->>'state', 'draft'), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'scope', latest.payload->>'scope', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'principal_id', latest.payload->>'principal_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'short_name', latest.payload->>'short_name', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'legal_person', latest.payload->>'legal_person', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'register_capital', latest.payload->>'register_capital', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'business_scope', latest.payload->>'business_scope', latest.payload->'candidate'->>'scope', latest.payload->>'scope', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'source', latest.payload->>'source', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'contact_person', latest.payload->>'contact_person', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'contact_phone', latest.payload->>'contact_phone', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'address', latest.payload->>'address', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'enabled', latest.payload->>'enabled', 'true'), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'risk_rating', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'risk_tags', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'risk_score', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'risk_updated_at', ''), 'UTF8'), 'hex') " +
    "FROM latest WHERE true" +
    filter +
    " ORDER BY latest.aggregate_id LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 24)
    let enabled = decode_hex(row[19]).to_lower() == "true"
    result.push(
      Json::object({
        "supplier_id": Json::string(decode_hex(row[0])),
        "supplier_code": Json::string(decode_hex(row[1])),
        "name": Json::string(decode_hex(row[2])),
        "category_code": Json::string(decode_hex(row[3])),
        "evaluation": Json::string(decode_hex(row[4])),
        "state": Json::string(decode_hex(row[5])),
        "scope": Json::string(decode_hex(row[6])),
        "principal_id": Json::string(decode_hex(row[7])),
        "source_kind": Json::string(decode_hex(row[8])),
        "source_snapshot_id": Json::string(decode_hex(row[9])),
        "mapping_version": Json::string(decode_hex(row[10])),
        "short_name": Json::string(decode_hex(row[11])),
        "legal_person": Json::string(decode_hex(row[12])),
        "register_capital": Json::string(decode_hex(row[13])),
        "business_scope": Json::string(decode_hex(row[14])),
        "source": Json::string(decode_hex(row[15])),
        "contact_person": Json::string(decode_hex(row[16])),
        "contact_phone": Json::string(decode_hex(row[17])),
        "address": Json::string(decode_hex(row[18])),
        "enabled": Json::boolean(enabled),
        "riskRating": Json::string(decode_hex(row[20])),
        "riskTags": Json::string(decode_hex(row[21])),
        "riskScore": Json::string(decode_hex(row[22])),
        "riskUpdatedAt": Json::string(decode_hex(row[23])),
      }),
    )
  }
  result
}

///|
async fn supplier_direct_read_response(
  supplier_id : String?,
) -> Json raise CompanyServiceError {
  Json::object({ "items": Json::array(supplier_projection_items(supplier_id)) })
}

///|
async fn supplier_direct_detail_response(
  supplier_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let items = supplier_projection_items(Some(supplier_id))
  if items.is_empty() {
    (404, Json::object({ "error": Json::string("supplier not found") }))
  } else {
    (200, items[0])
  }
}

///|
fn supplier_risk_tags(state : String, evaluation : String) -> Array[Json] {
  let tags : Array[Json] = []
  if state == "pending_review" {
    tags.push(Json::string("pending_review"))
  }
  if state == "suspended" {
    tags.push(Json::string("suspended"))
  }
  if state == "blacklisted" {
    tags.push(Json::string("blacklist"))
  }
  if evaluation == "unqualified" {
    tags.push(Json::string("unqualified"))
  }
  tags
}

///|
async fn supplier_direct_risk_response(
  supplier_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let items = supplier_projection_items(Some(supplier_id))
  if items.is_empty() {
    return (404, Json::object({ "error": Json::string("supplier not found") }))
  }
  let supplier = items[0]
  let state = json_text(supplier, "state", "")
  let evaluation = json_text(supplier, "evaluation", "")
  let (score, rating) = if state == "voided" ||
    state == "blacklisted" ||
    evaluation == "unqualified" {
    (0, "E")
  } else if state == "active" && evaluation == "strategic" {
    (95, "A")
  } else if state == "active" && evaluation == "qualified" {
    (85, "B")
  } else if state == "pending_review" {
    (60, "C")
  } else if state == "suspended" {
    (35, "D")
  } else {
    (50, "C")
  }
  let persisted_rating = json_text(supplier, "riskRating", "")
  let persisted_score = json_text(supplier, "riskScore", "")
  let parsed_score = @json.parse(persisted_score) catch { _ => Json::null() }
  let response_score = if !persisted_score.is_empty() {
    match parsed_score {
      Number(value, ..) => value
      _ => score.to_double()
    }
  } else {
    score.to_double()
  }
  let response_rating = if persisted_rating.is_empty() {
    rating
  } else {
    persisted_rating
  }
  let tags = if json_text(supplier, "riskTags", "").is_empty() {
    supplier_risk_tags(state, evaluation)
  } else {
    json_text(supplier, "riskTags", "")
    .split(",")
    .to_array()
    .map(fn(tag) { Json::string(tag.to_owned()) })
  }
  (
    200,
    Json::object({
      "supplier_id": Json::string(json_text(supplier, "supplier_id", "")),
      "score": Json::number(response_score),
      "rating": Json::string(response_rating),
      "tags": Json::array(tags),
      "state": Json::string(state),
      "evaluation": Json::string(evaluation),
      "source_kind": Json::string(json_text(supplier, "source_kind", "")),
    }),
  )
}
