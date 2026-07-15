///|
/// Signed local sales-subscription commands.
///
/// A subscription is a reservation state, not a contract, receivable, or
/// revenue posting. Conversion records the local state transition and an
/// explicit downstream-contract pending marker; it does not create financial
/// or contract rows implicitly.

///|
fn sales_subscription_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/sales/subscriptions" ||
      path == "/api/company/source/sales/subscriptions"
    ) {
    return Some(("create", None))
  }
  let prefixes = [
    "/api/company/sales/subscriptions/", "/api/company/source/sales/subscriptions/",
  ]
  for prefix in prefixes {
    if request_method is @http.Post &&
      path.has_prefix(prefix) &&
      path.has_suffix("/convert-to-contract") {
      let id = path[prefix.length():path.length() -
      "/convert-to-contract".length()].to_owned()
      if valid_identifier(id) {
        return Some(("convert_to_contract", Some(id)))
      }
    }
  }
  None
}

///|
fn sales_subscription_text(
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
fn sales_subscription_decimal(
  body : Json,
  primary : String,
  fallback : String,
) -> Json raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::number(0.0))
  }
  match value {
    Null => Json::number(0.0)
    Number(value, ..) if value >= 0.0 => Json::number(value)
    String(value) => {
      let parsed = parse_number(value.trim().to_owned())
      if parsed < 0.0 {
        raise reject(422, primary + " must be non-negative")
      }
      Json::number(parsed)
    }
    _ => raise reject(422, primary + " must be a number")
  }
}

///|
fn sales_subscription_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let id = {
    let value = sales_subscription_text(
      body, "sub_guid", "subGuid", true, false,
    )
    if value.is_empty() {
      "subscription-" + idempotency_key
    } else {
      value
    }
  }
  let code = {
    let value = sales_subscription_text(
      body, "sub_code", "subCode", true, false,
    )
    if value.is_empty() {
      "SUB-" + id
    } else {
      value
    }
  }
  if !valid_identifier(id) || !valid_identifier(code) {
    raise reject(422, "subscription identity contains unsupported characters")
  }
  Json::object({
    "command_type": Json::string("create"),
    "sub_guid": Json::string(id),
    "subscription_guid": Json::string(id),
    "sub_code": Json::string(code),
    "customer_guid": Json::string(
      sales_subscription_text(body, "customer_guid", "customerGuid", true, true),
    ),
    "proj_guid": Json::string(
      sales_subscription_text(body, "proj_guid", "projGuid", true, true),
    ),
    "bu_guid": Json::string(
      sales_subscription_text(body, "bu_guid", "buGuid", true, false),
    ),
    "building_no": Json::string(
      sales_subscription_text(body, "building_no", "buildingNo", false, true),
    ),
    "unit_no": Json::string(
      sales_subscription_text(body, "unit_no", "unitNo", false, true),
    ),
    "area": sales_subscription_decimal(body, "area", "area"),
    "unit_price": sales_subscription_decimal(body, "unit_price", "unitPrice"),
    "total_price": sales_subscription_decimal(body, "total_price", "totalPrice"),
    "sub_amount": sales_subscription_decimal(body, "sub_amount", "subAmount"),
    "sub_date": Json::string(
      sales_subscription_text(body, "sub_date", "subDate", false, false),
    ),
    "state": Json::string("subscribed"),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn sales_subscription_convert_request(
  subscription_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(subscription_id) {
    raise reject(422, "sub_guid is required")
  }
  Json::object({
    "command_type": Json::string("convert_to_contract"),
    "sub_guid": Json::string(subscription_id),
    "payment_type": Json::string(
      sales_subscription_text(body, "payment_type", "paymentType", false, false),
    ),
    "signed_date": Json::string(
      sales_subscription_text(body, "signed_date", "signedDate", false, false),
    ),
    "state": Json::string("converted"),
    "contract_pending": Json::boolean(true),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_sales_subscription_payload(
  subscription_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'subscription' AND aggregate_id = " +
    @postgres.sql_literal(subscription_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid sales subscription projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn sales_subscription_imported_exists(
  subscription_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("sale_subscription", 500) {
    if json_text(row.payload, "sub_guid", row.record_id) == subscription_id {
      return true
    }
  }
  false
}

///|
async fn sales_subscription_command(
  command_type : String,
  subscription_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "create" && command_type != "convert_to_contract" {
    raise reject(404, "unsupported sales subscription command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = if command_type == "create" {
    sales_subscription_create_request(body, actor_id, idempotency_key)
  } else {
    let id = match subscription_id {
      Some(value) => value
      None => raise reject(422, "sub_guid is required")
    }
    sales_subscription_convert_request(id, body, actor_id)
  }
  let id = json_text(request, "sub_guid", "")
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
          "subscription": json_field(existing, "result").unwrap_or(Json::null()),
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
  let current = latest_sales_subscription_payload(id)
  let imported = sales_subscription_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "subscription already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported subscription is read-only; create a local subscription first",
          )
        }
        raise reject(404, "subscription not found")
      }
      Some((payload, _)) if json_text(payload, "source_kind", "") != "command" =>
        raise reject(
          409, "imported subscription is read-only; create a local subscription first",
        )
      Some((payload, _)) if json_text(payload, "state", "") != "subscribed" =>
        raise reject(409, "subscription cannot convert from its current state")
      Some(_) => ()
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
    "subscribed"
  } else {
    "converted"
  }
  let event_id = "sales_subscription:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'state','subscribed')"
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
    "subGuid": Json::string(id),
    "subCode": Json::string(
      json_text(
        current_payload,
        "sub_code",
        json_text(request, "sub_code", "SUB-" + id),
      ),
    ),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "contract_created": Json::boolean(false),
    "revenue_created": Json::boolean(false),
    "contract_pending": Json::boolean(command_type == "convert_to_contract"),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("sales_subscription"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("subscription"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("sales_subscription." + command_type),
    "aggregate_type": Json::string("subscription"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('subscription'," +
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
      "subscription": result,
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
async fn sales_subscription_command_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id,'UTF8'),'hex'), encode(convert_to(source_event_id,'UTF8'),'hex'), encode(convert_to(payload::text,'UTF8'),'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,source_event_id,payload FROM company_aggregate_projection WHERE aggregate_type='subscription' AND payload->>'source_kind'='command' ORDER BY aggregate_id,revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid sales subscription projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ =>
          raise fail("sales subscription projection payload is not an object")
      }
    }
  }
  result
}
