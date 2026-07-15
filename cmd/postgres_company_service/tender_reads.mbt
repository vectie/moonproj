///|
/// Read the latest PostgreSQL-owned tender projection in the same shape as the
/// ERP bridge.  Imported tender candidates are deliberately kept distinguishable
/// through `source_kind`; this endpoint does not authorize procurement effects.
async fn tender_projection_items(
  tender_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let filters = if tender_id is Some(value) {
    if !valid_identifier(value) {
      raise fail("invalid tender_id")
    }
    " AND latest.aggregate_id = " + @postgres.sql_literal(value)
  } else {
    ""
  }
  let output = run_sql(
    "WITH latest AS (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'tender' " +
    "ORDER BY aggregate_id, revision DESC) SELECT " +
    "encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'name', latest.payload->>'name', latest.aggregate_id), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'project_scope', latest.payload->>'project_scope', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'category', latest.payload->>'category', ''), 'UTF8'), 'hex'), " +
    "coalesce(latest.payload->'candidate'->>'estimated_amount_minor', latest.payload->>'estimated_amount_minor', '0'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'currency', latest.payload->>'currency', 'CNY'), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'state', latest.payload->>'state', 'planning'), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'awarded_supplier_id', latest.payload->>'awarded_supplier_id', ''), 'UTF8'), 'hex'), " +
    "coalesce(latest.payload->'candidate'->>'awarded_amount_minor', latest.payload->>'awarded_amount_minor', '0'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->>'commitment_id', latest.payload->>'commitment_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->'candidate'->'bids', latest.payload->'bids', '[]'::jsonb)::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'tender_code', latest.payload->'candidate'->>'tender_code', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'plan_publish_date', latest.payload->'candidate'->>'plan_publish_date', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'plan_award_date', latest.payload->'candidate'->>'plan_award_date', ''), 'UTF8'), 'hex') " +
    "FROM latest WHERE coalesce(latest.payload->>'state', '') <> 'deleted'" +
    filters +
    " ORDER BY latest.aggregate_id LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 17)
    let bids = @json.parse(decode_hex(row[10])) catch {
      _ => raise fail("invalid tender bids projection JSON")
    }
    result.push(
      Json::object({
        "tender_id": Json::string(decode_hex(row[0])),
        "name": Json::string(decode_hex(row[1])),
        "project_scope": Json::string(decode_hex(row[2])),
        "category": Json::string(decode_hex(row[3])),
        "estimated_amount_minor": Json::number(
          parse_decimal(row[4]).to_double(),
        ),
        "currency": Json::string(decode_hex(row[5])),
        "state": Json::string(decode_hex(row[6])),
        "awarded_supplier_id": Json::string(decode_hex(row[7])),
        "awarded_amount_minor": Json::number(parse_decimal(row[8]).to_double()),
        "commitment_id": Json::string(decode_hex(row[9])),
        "bids": bids,
        "source_kind": Json::string(decode_hex(row[11])),
        "source_snapshot_id": Json::string(decode_hex(row[12])),
        "mapping_version": Json::string(decode_hex(row[13])),
        "tender_code": Json::string(decode_hex(row[14])),
        "plan_publish_date": Json::string(decode_hex(row[15])),
        "plan_award_date": Json::string(decode_hex(row[16])),
        "estimated_amount_display": Json::string(
          invoice_money_display(parse_decimal(row[4]).to_double() / 100.0),
        ),
        "awarded_amount_display": Json::string(
          if parse_decimal(row[8]) == 0 {
            "—"
          } else {
            invoice_money_display(parse_decimal(row[8]).to_double() / 100.0)
          },
        ),
      }),
    )
  }
  result
}

///|
async fn tender_read_response(
  tender_id : String?,
) -> Json raise CompanyServiceError {
  Json::object({ "items": Json::array(tender_projection_items(tender_id)) })
}

///|
async fn tender_detail_response(
  tender_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let items = tender_projection_items(Some(tender_id))
  if items.is_empty() {
    (404, Json::object({ "error": Json::string("tender not found") }))
  } else {
    (200, items[0])
  }
}

///|
async fn tender_split_projection_items(
  split_id : String?,
  parent_contract_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let mut filters = ""
  if split_id is Some(value) {
    if !valid_identifier(value) {
      raise fail("invalid split_id")
    }
    filters += " AND latest.aggregate_id = " + @postgres.sql_literal(value)
  }
  if parent_contract_id is Some(value) {
    if !valid_identifier(value) {
      raise fail("invalid parent_contract_id")
    }
    let literal = @postgres.sql_literal(value)
    filters += " AND coalesce(latest.payload->>'parent_contract_id', latest.payload->'candidate'->>'parent_contract_id', '') = " +
      literal
  }
  let output = run_sql(
    "WITH latest AS (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'contract_split' " +
    "ORDER BY aggregate_id, revision DESC) SELECT " +
    "encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'parent_contract_id', latest.payload->'candidate'->>'parent_contract_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'split_name', latest.payload->'candidate'->>'split_name', ''), 'UTF8'), 'hex'), " +
    "coalesce(latest.payload->>'split_amount_minor', latest.payload->'candidate'->>'split_amount_minor', '0'), " +
    "coalesce(latest.payload->>'split_pct_bps', latest.payload->'candidate'->>'split_pct_bps', '0'), " +
    "encode(convert_to(coalesce(latest.payload->>'scope', latest.payload->'candidate'->>'scope', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'state', latest.payload->'candidate'->>'state', 'planned'), 'UTF8'), 'hex'), " +
    "encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'), " +
    "encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex') " +
    "FROM latest WHERE coalesce(latest.payload->>'state', '') <> 'deleted'" +
    filters +
    " ORDER BY latest.aggregate_id LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 10)
    let amount_minor = parse_decimal(row[3])
    let pct_bps = parse_decimal(row[4])
    let pct_negative = pct_bps < 0
    let pct_abs = if pct_negative { -pct_bps } else { pct_bps }
    let pct_fraction = pct_abs % 100
    let pct_fraction_text = if pct_fraction < 10 {
      "0" + pct_fraction.to_string()
    } else {
      pct_fraction.to_string()
    }
    result.push(
      Json::object({
        "split_id": Json::string(decode_hex(row[0])),
        "parent_contract_id": Json::string(decode_hex(row[1])),
        "split_name": Json::string(decode_hex(row[2])),
        "split_amount_minor": Json::number(amount_minor.to_double()),
        "split_pct_bps": Json::number(pct_bps.to_double()),
        "scope": Json::string(decode_hex(row[5])),
        "state": Json::string(decode_hex(row[6])),
        "source_kind": Json::string(decode_hex(row[7])),
        "source_snapshot_id": Json::string(decode_hex(row[8])),
        "mapping_version": Json::string(decode_hex(row[9])),
        "split_amount_display": Json::string(
          invoice_money_display(amount_minor.to_double() / 100.0),
        ),
        "split_pct_display": Json::string(
          (if pct_negative { "-" } else { "" }) +
          (pct_abs / 100).to_string() +
          "." +
          pct_fraction_text +
          "%",
        ),
      }),
    )
  }
  result
}

///|
async fn tender_split_read_response(
  split_id : String?,
  parent_contract_id : String?,
) -> Json raise CompanyServiceError {
  Json::object({
    "items": Json::array(
      tender_split_projection_items(split_id, parent_contract_id),
    ),
  })
}

///|
async fn tender_split_detail_response(
  split_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let items = tender_split_projection_items(Some(split_id), None)
  if items.is_empty() {
    (404, Json::object({ "error": Json::string("contract split not found") }))
  } else {
    (200, items[0])
  }
}
