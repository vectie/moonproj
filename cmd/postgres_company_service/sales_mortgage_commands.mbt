///|
/// Signed local mortgage lifecycle commands.
///
/// Mortgage release is a financing observation.  The native boundary records
/// its state and an explicit revenue-pending marker; it never updates revenue,
/// cash, accounting, tax, or a bank provider implicitly.

///|
fn sales_mortgage_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/sales/mortgages" ||
      path == "/api/company/source/sales/mortgages"
    ) {
    return Some(("create", None))
  }
  let prefixes = [
    "/api/company/sales/mortgages/", "/api/company/source/sales/mortgages/",
  ]
  for prefix in prefixes {
    if request_method is @http.Post && path.has_prefix(prefix) {
      let rest = path[prefix.length():].to_owned().split("/").to_array()
      if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
        let action = match rest[1].to_owned() {
          "approve" => "approve"
          "release" => "release"
          _ => ""
        }
        if !action.is_empty() {
          return Some((action, Some(rest[0].to_owned())))
        }
      }
    }
  }
  None
}

///|
fn sales_mortgage_text(
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
fn sales_mortgage_number(
  body : Json,
  primary : String,
  fallback : String,
  default : Double,
  positive : Bool,
) -> Json raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::number(default))
  }
  let number = match value {
    Null => default
    Number(value, ..) => value
    String(value) => parse_number(value.trim().to_owned())
    _ => raise reject(422, primary + " must be a number")
  }
  if (positive && number <= 0.0) || (!positive && number < 0.0) {
    raise reject(422, primary + " must be positive")
  }
  Json::number(number)
}

///|
fn sales_mortgage_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let id = {
    let value = sales_mortgage_text(
      body, "mortgage_guid", "mortgageGuid", true, false,
    )
    if value.is_empty() {
      "mortgage-" + idempotency_key
    } else {
      value
    }
  }
  let code = {
    let value = sales_mortgage_text(
      body, "mortgage_code", "mortgageCode", true, false,
    )
    if value.is_empty() {
      "MTG-" + id
    } else {
      value
    }
  }
  if !valid_identifier(id) || !valid_identifier(code) {
    raise reject(422, "mortgage identity contains unsupported characters")
  }
  Json::object({
    "command_type": Json::string("create"),
    "mortgage_guid": Json::string(id),
    "mortgage_code": Json::string(code),
    "scontract_guid": Json::string(
      sales_mortgage_text(body, "scontract_guid", "scontractGuid", true, true),
    ),
    "customer_guid": Json::string(
      sales_mortgage_text(body, "customer_guid", "customerGuid", true, false),
    ),
    "bank_name": Json::string(
      sales_mortgage_text(body, "bank_name", "bankName", false, true),
    ),
    "loan_amount": sales_mortgage_number(
      body, "loan_amount", "loanAmount", 0.0, true,
    ),
    "loan_years": sales_mortgage_number(
      body, "loan_years", "loanYears", 30.0, true,
    ),
    "rate": sales_mortgage_number(body, "rate", "rate", 0.0485, false),
    "apply_date": Json::string(
      sales_mortgage_text(body, "apply_date", "applyDate", false, false),
    ),
    "remark": Json::string(
      sales_mortgage_text(body, "remark", "remark", false, false),
    ),
    "state": Json::string("applying"),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn sales_mortgage_transition_request(
  mortgage_id : String,
  command_type : String,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(mortgage_id) {
    raise reject(422, "mortgage_guid is required")
  }
  Json::object({
    "command_type": Json::string(command_type),
    "mortgage_guid": Json::string(mortgage_id),
    "state": Json::string(
      if command_type == "approve" {
        "approved"
      } else {
        "released"
      },
    ),
    "revenue_pending": Json::boolean(command_type == "release"),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_sales_mortgage_payload(
  mortgage_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'mortgage' AND aggregate_id = " +
    @postgres.sql_literal(mortgage_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid sales mortgage projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn sales_mortgage_imported_exists(
  mortgage_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("sale_mortgage", 500) {
    if json_text(row.payload, "mortgage_guid", row.record_id) == mortgage_id {
      return true
    }
  }
  false
}

///|
async fn sales_mortgage_command(
  command_type : String,
  mortgage_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "create" &&
    command_type != "approve" &&
    command_type != "release" {
    raise reject(404, "unsupported sales mortgage command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = if command_type == "create" {
    sales_mortgage_create_request(body, actor_id, idempotency_key)
  } else {
    let id = match mortgage_id {
      Some(value) => value
      None => raise reject(422, "mortgage_guid is required")
    }
    sales_mortgage_transition_request(id, command_type, actor_id)
  }
  let id = json_text(request, "mortgage_guid", "")
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
          "mortgage": json_field(existing, "result").unwrap_or(Json::null()),
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
  let current = latest_sales_mortgage_payload(id)
  let imported = sales_mortgage_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "mortgage already exists")
    }
  } else {
    let current_state = match current {
      None => {
        if imported {
          raise reject(
            409, "imported mortgage is read-only; create a local mortgage first",
          )
        }
        raise reject(404, "mortgage not found")
      }
      Some((payload, _)) if json_text(payload, "source_kind", "") != "command" =>
        raise reject(
          409, "imported mortgage is read-only; create a local mortgage first",
        )
      Some((payload, _)) => json_text(payload, "state", "")
    }
    let allowed = (command_type == "approve" && current_state == "applying") ||
      (command_type == "release" && current_state == "approved")
    if !allowed {
      raise reject(
        409,
        "mortgage transition is not allowed from " + current_state,
      )
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
  } else if command_type == "approve" {
    "approved"
  } else {
    "released"
  }
  let event_id = "sales_mortgage:" + command_type + ":" + idempotency_key
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
    "mortgageGuid": Json::string(id),
    "mortgageCode": Json::string(
      json_text(
        current_payload,
        "mortgage_code",
        json_text(request, "mortgage_code", "MTG-" + id),
      ),
    ),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "revenue_pending": Json::boolean(command_type == "release"),
    "revenue_updated": Json::boolean(false),
    "cash_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("sales_mortgage"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("mortgage"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("sales_mortgage." + command_type),
    "aggregate_type": Json::string("mortgage"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('mortgage'," +
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
      "mortgage": result,
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
async fn sales_mortgage_command_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id,'UTF8'),'hex'), encode(convert_to(source_event_id,'UTF8'),'hex'), encode(convert_to(payload::text,'UTF8'),'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,source_event_id,payload FROM company_aggregate_projection WHERE aggregate_type='mortgage' AND payload->>'source_kind'='command' ORDER BY aggregate_id,revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid sales mortgage projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("sales mortgage projection payload is not an object")
      }
    }
  }
  result
}
