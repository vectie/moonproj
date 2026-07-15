///|
/// Signed local sales-customer commands.
///
/// Imported `sale_customer` rows remain read-only.  These projections provide
/// the ERP customer create/update loop without deleting source data or
/// triggering contracts, receivables, providers, cash, accounting, or tax.

///|
fn sales_customer_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/sales/customers" ||
      path == "/api/company/source/sales/customers"
    ) {
    return Some(("create", None))
  }
  let prefixes = [
    "/api/company/sales/customers/", "/api/company/source/sales/customers/",
  ]
  for prefix in prefixes {
    if request_method is @http.Put && path.has_prefix(prefix) {
      let id = path[prefix.length():].to_owned()
      if valid_identifier(id) {
        return Some(("update", Some(id)))
      }
    }
  }
  None
}

///|
fn sales_customer_text(
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
fn sales_customer_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let customer_id = {
    let value = sales_customer_text(
      body, "customer_guid", "customerGuid", true, false,
    )
    if value.is_empty() {
      "customer-" + idempotency_key
    } else {
      value
    }
  }
  let customer_code = {
    let value = sales_customer_text(
      body, "customer_code", "customerCode", true, false,
    )
    if value.is_empty() {
      "CUS-" + customer_id
    } else {
      value
    }
  }
  if !valid_identifier(customer_id) || !valid_identifier(customer_code) {
    raise reject(422, "customer identity contains unsupported characters")
  }
  Json::object({
    "command_type": Json::string("create"),
    "customer_guid": Json::string(customer_id),
    "customer_code": Json::string(customer_code),
    "customer_name": Json::string(
      sales_customer_text(body, "customer_name", "customerName", false, true),
    ),
    "id_card_no": Json::string(
      sales_customer_text(body, "id_card_no", "idCardNo", false, false),
    ),
    "phone": Json::string(
      sales_customer_text(body, "phone", "phone", false, true),
    ),
    "proj_guid": Json::string(
      sales_customer_text(body, "proj_guid", "projGuid", true, false),
    ),
    "bu_guid": Json::string(
      sales_customer_text(body, "bu_guid", "buGuid", true, false),
    ),
    "source": Json::string(
      sales_customer_text(body, "source", "source", false, false),
    ),
    "remark": Json::string(
      sales_customer_text(body, "remark", "remark", false, false),
    ),
    "state": Json::string("active"),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn sales_customer_update_request(
  customer_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(customer_id) {
    raise reject(422, "customer_guid is required")
  }
  let changes : Map[String, Json] = {}
  let mut changed = false
  let add_text = fn(
    primary : String,
    fallback : String,
  ) raise CompanyServiceError {
    if json_field(body, primary) is Some(_) ||
      json_field(body, fallback) is Some(_) {
      changes.set(
        primary,
        Json::string(sales_customer_text(body, primary, fallback, false, false)),
      )
      changed = true
    }
  }
  add_text("customer_name", "customerName")
  add_text("id_card_no", "idCardNo")
  add_text("phone", "phone")
  add_text("source", "source")
  add_text("remark", "remark")
  if !changed {
    raise reject(422, "update requires at least one mutable customer field")
  }
  Json::object({
    "command_type": Json::string("update"),
    "customer_guid": Json::string(customer_id),
    "changes": Json::object(changes),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_sales_customer_payload(
  customer_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'customer' AND aggregate_id = " +
    @postgres.sql_literal(customer_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid sales customer projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn sales_customer_imported_exists(
  customer_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("sale_customer", 500) {
    if json_text(row.payload, "customer_guid", row.record_id) == customer_id {
      return true
    }
  }
  false
}

///|
async fn sales_customer_command(
  command_type : String,
  customer_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "create" && command_type != "update" {
    raise reject(404, "unsupported sales customer command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = if command_type == "create" {
    sales_customer_create_request(body, actor_id, idempotency_key)
  } else {
    let id = match customer_id {
      Some(value) => value
      None => raise reject(422, "customer_guid is required")
    }
    sales_customer_update_request(id, body, actor_id)
  }
  let id = json_text(request, "customer_guid", "")
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
          "customer": json_field(existing, "result").unwrap_or(Json::null()),
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
  let current = latest_sales_customer_payload(id)
  let imported = sales_customer_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "customer already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported customer is read-only; create a local customer first",
          )
        }
        raise reject(404, "customer not found")
      }
      Some((payload, _)) if json_text(payload, "source_kind", "") != "command" =>
        raise reject(
          409, "imported customer is read-only; create a local customer first",
        )
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
  let event_id = "sales_customer:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'state','active')"
  } else {
    @postgres.sql_literal(current_payload.stringify()) +
    "::jsonb || " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb - 'actor_id' - 'command_type' || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ") || coalesce(" +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb->'changes','{}'::jsonb)"
  }
  let result = Json::object({
    "customerGuid": Json::string(id),
    "customerCode": Json::string(
      if command_type == "create" {
        json_text(request, "customer_code", "CUS-" + id)
      } else {
        json_text(current_payload, "customer_code", "CUS-" + id)
      },
    ),
    "aggregate_id": Json::string(id),
    "state": Json::string("active"),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("sales_customer"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("customer"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("sales_customer." + command_type),
    "aggregate_type": Json::string("customer"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('customer'," +
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
      "customer": result,
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
async fn sales_customer_command_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id,'UTF8'),'hex'), encode(convert_to(source_event_id,'UTF8'),'hex'), encode(convert_to(payload::text,'UTF8'),'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,source_event_id,payload FROM company_aggregate_projection WHERE aggregate_type='customer' AND payload->>'source_kind'='command' ORDER BY aggregate_id,revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid sales customer projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("sales customer projection payload is not an object")
      }
    }
  }
  result
}
