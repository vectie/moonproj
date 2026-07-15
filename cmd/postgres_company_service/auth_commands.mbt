///|
/// Signed local auth lifecycle commands.
///
/// Profile edits and logout are persisted as command-owned projections. They
/// do not pretend to issue bearer tokens or replace the production password
/// store; login and password change remain separate identity gates.

///|
fn auth_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post && path == "/api/company/auth/logout" {
    return Some("logout")
  }
  if request_method is @http.Put && path == "/api/company/auth/profile" {
    return Some("profile")
  }
  None
}

///|
async fn auth_latest_projection(
  aggregate_type : String,
  aggregate_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(aggregate_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid auth projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn auth_profile_overlay(
  payload : Json,
  user_code : String,
) -> Json raise CompanyServiceError {
  match auth_latest_projection("auth_profile", user_code) {
    None => payload
    Some((profile, _)) => {
      let values : Map[String, Json] = match payload {
        Object(fields) => fields
        _ => {}
      }
      match json_field(profile, "emp_name") {
        Some(value) => values.set("emp_name", value)
        None => ()
      }
      match json_field(profile, "user_name") {
        Some(value) => values.set("user_name", value)
        None => ()
      }
      Json::object(values)
    }
  }
}

///|
fn auth_command_request(
  command_type : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if command_type == "logout" {
    return Json::object({
      "command_type": Json::string(command_type),
      "user_code": Json::string(actor_id),
      "actor_id": Json::string(actor_id),
    })
  }
  let emp_name = json_text(body, "empName", json_text(body, "emp_name", ""))
    .trim()
    .to_owned()
  if emp_name.is_empty() || emp_name.length() > 256 {
    raise reject(400, "empName is required and must be at most 256 characters")
  }
  let user_name = json_text(body, "userName", json_text(body, "user_name", ""))
    .trim()
    .to_owned()
  Json::object({
    "command_type": Json::string(command_type),
    "user_code": Json::string(actor_id),
    "actor_id": Json::string(actor_id),
    "emp_name": Json::string(emp_name),
    "user_name": Json::string(user_name),
  })
}

///|
async fn auth_command(
  command_type : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "logout" && command_type != "profile" {
    raise reject(404, "unsupported auth command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let profile = match auth_current_user(actor_id) {
    Some(value) => value
    None => raise reject(403, "user not found or disabled")
  }
  let profile_data = json_field(profile, "data").unwrap_or(Json::null())
  if !json_bool(profile_data, "enabled", false) {
    raise reject(403, "user not found or disabled")
  }
  let request = auth_command_request(command_type, body, actor_id)
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
          "command": existing,
          "auth": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let aggregate_type = if command_type == "logout" {
    "auth_session"
  } else {
    "auth_profile"
  }
  let aggregate_id = actor_id
  let current = auth_latest_projection(aggregate_type, aggregate_id)
  let next_revision = match current {
    Some((_, revision)) => revision + 1
    None => 1
  }
  let event_id = "auth:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + idempotency_key
  let next_payload = if command_type == "logout" {
    Json::object({
      "command_type": Json::string(command_type),
      "user_code": Json::string(actor_id),
      "state": Json::string("revoked"),
      "session_revoked": Json::boolean(true),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
      "updated_by": Json::string(actor_id),
    })
  } else {
    let emp_name = json_text(request, "emp_name", "")
    let user_name = json_text(request, "user_name", "")
    let values : Map[String, Json] = {
      "command_type": Json::string(command_type),
      "user_code": Json::string(actor_id),
      "emp_name": Json::string(emp_name),
      "state": Json::string("active"),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
      "updated_by": Json::string(actor_id),
    }
    if !user_name.is_empty() {
      values.set("user_name", Json::string(user_name))
    }
    Json::object(values)
  }
  let result = if command_type == "logout" {
    Json::object({
      "userCode": Json::string(actor_id),
      "sessionRevoked": Json::boolean(true),
      "state": Json::string("revoked"),
      "revision": Json::number(next_revision.to_double()),
      "sourceKind": Json::string("command"),
      "persisted": Json::boolean(true),
      "authorizing": Json::boolean(false),
    })
  } else {
    Json::object({
      "userCode": Json::string(actor_id),
      "empName": Json::string(json_text(next_payload, "emp_name", "")),
      "userName": Json::string(json_text(next_payload, "user_name", "")),
      "revision": Json::number(next_revision.to_double()),
      "sourceKind": Json::string("command"),
      "persisted": Json::boolean(true),
      "authorizing": Json::boolean(false),
    })
  }
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("auth"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("auth." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(next_revision.to_double()),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(aggregate_type) +
    ", " +
    @postgres.sql_literal(aggregate_id) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "command": command_payload,
      "auth": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
