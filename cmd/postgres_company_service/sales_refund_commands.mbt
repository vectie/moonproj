///|
/// Signed local sales-refund lifecycle commands.
///
/// Approval records refund intent and pending reconciliation markers. It does
/// not alter contracts, revenue, cash, accounting, tax, or a payment provider.

///|
fn sales_refund_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/sales/refunds" ||
      path == "/api/company/source/sales/refunds"
    ) {
    return Some(("create", None))
  }
  let prefixes = [
    "/api/company/sales/refunds/", "/api/company/source/sales/refunds/",
  ]
  for prefix in prefixes {
    if request_method is @http.Post && path.has_prefix(prefix) {
      let rest = path[prefix.length():].to_owned().split("/").to_array()
      if rest.length() == 2 &&
        rest[1].to_owned() == "approve" &&
        valid_identifier(rest[0].to_owned()) {
        return Some(("approve", Some(rest[0].to_owned())))
      }
    }
  }
  None
}

///|
fn sales_refund_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
  required : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::null())
  }
  let text = match value {
    Null => ""
    String(value) => value.trim().to_owned()
    Number(value, ..) => value.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if required && text.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !text.is_empty() && !valid_identifier(text) {
    raise reject(422, primary + " contains unsupported characters")
  }
  text
}

///|
fn sales_refund_amount(body : Json) -> Json raise CompanyServiceError {
  let value = json_field(body, "refund_amount").unwrap_or(
    json_field(body, "refundAmount").unwrap_or(Json::number(0.0)),
  )
  let amount = match value {
    Null => 0.0
    Number(value, ..) => value
    String(value) => parse_number(value.trim().to_owned())
    _ => raise reject(422, "refundAmount must be a number")
  }
  if amount < 0.0 {
    raise reject(422, "refundAmount must be non-negative")
  }
  Json::number(amount)
}

///|
fn sales_refund_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let id = {
    let value = sales_refund_text(
      body, "refund_guid", "refundGuid", true, false,
    )
    if value.is_empty() {
      "refund-" + idempotency_key
    } else {
      value
    }
  }
  let code = {
    let value = sales_refund_text(
      body, "refund_code", "refundCode", true, false,
    )
    if value.is_empty() {
      "RF-" + id
    } else {
      value
    }
  }
  if !valid_identifier(id) || !valid_identifier(code) {
    raise reject(422, "refund identity contains unsupported characters")
  }
  Json::object({
    "command_type": Json::string("create"),
    "refund_guid": Json::string(id),
    "refund_code": Json::string(code),
    "scontract_guid": Json::string(
      sales_refund_text(body, "scontract_guid", "scontractGuid", true, true),
    ),
    "customer_guid": Json::string(
      sales_refund_text(body, "customer_guid", "customerGuid", true, false),
    ),
    "reason": Json::string(
      sales_refund_text(body, "reason", "reason", false, true),
    ),
    "refund_amount": sales_refund_amount(body),
    "refund_date": Json::string(
      sales_refund_text(body, "refund_date", "refundDate", false, false),
    ),
    "state": Json::string("applying"),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn sales_refund_approve_request(
  refund_id : String,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(refund_id) {
    raise reject(422, "refund_guid is required")
  }
  Json::object({
    "command_type": Json::string("approve"),
    "refund_guid": Json::string(refund_id),
    "state": Json::string("approved"),
    "contract_pending": Json::boolean(true),
    "revenue_pending": Json::boolean(true),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_sales_refund_payload(
  refund_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'refund' AND aggregate_id = " +
    @postgres.sql_literal(refund_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid sales refund projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn sales_refund_imported_exists(
  refund_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("sale_refund", 500) {
    if json_text(row.payload, "refund_guid", row.record_id) == refund_id {
      return true
    }
  }
  false
}

///|
async fn sales_refund_command(
  command_type : String,
  refund_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "create" && command_type != "approve" {
    raise reject(404, "unsupported sales refund command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = if command_type == "create" {
    sales_refund_create_request(body, actor_id, idempotency_key)
  } else {
    let id = match refund_id {
      Some(value) => value
      None => raise reject(422, "refund_guid is required")
    }
    sales_refund_approve_request(id, actor_id)
  }
  let id = json_text(request, "refund_guid", "")
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": json_field(existing, "result").unwrap_or(Json::null()),
          "refund": json_field(existing, "result").unwrap_or(Json::null()),
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_sales_refund_payload(id)
  let imported = sales_refund_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "refund already exists")
    }
  } else {
    let current_state = match current {
      None => {
        if imported {
          raise reject(
            409, "imported refund is read-only; create a local refund first",
          )
        }
        raise reject(404, "refund not found")
      }
      Some((payload, _)) if json_text(payload, "source_kind", "") != "command" =>
        raise reject(
          409, "imported refund is read-only; create a local refund first",
        )
      Some((payload, _)) => json_text(payload, "state", "")
    }
    if current_state != "applying" {
      raise reject(409, "refund cannot approve from its current state")
    }
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let next_state = if command_type == "create" {
    "applying"
  } else {
    "approved"
  }
  let event_id = "sales_refund:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'state','applying')"
  } else {
    @postgres.sql_literal(current_payload.stringify()) +
    "::jsonb || " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ")"
  }
  let result = Json::object({
    "refundGuid": Json::string(id),
    "refundCode": Json::string(
      json_text(
        current_payload,
        "refund_code",
        json_text(request, "refund_code", "RF-" + id),
      ),
    ),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "contract_pending": Json::boolean(command_type == "approve"),
    "revenue_pending": Json::boolean(command_type == "approve"),
    "contract_updated": Json::boolean(false),
    "revenue_updated": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("sales_refund"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("refund"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("sales_refund." + command_type),
    "aggregate_type": Json::string("refund"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(next_revision.to_double()),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('refund'," +
    @postgres.sql_literal(id) +
    "," +
    next_revision.to_string() +
    "," +
    next_payload +
    "," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": result,
      "refund": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "provider_execution": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
async fn sales_refund_command_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id,'UTF8'),'hex'), encode(convert_to(source_event_id,'UTF8'),'hex'), encode(convert_to(payload::text,'UTF8'),'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,source_event_id,payload FROM company_aggregate_projection WHERE aggregate_type='refund' AND payload->>'source_kind'='command' ORDER BY aggregate_id,revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid sales refund projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("sales refund projection payload is not an object")
      }
    }
  }
  result
}
