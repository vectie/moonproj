///|
/// Local RBAC command overlays.
///
/// Imported users, roles, and assignments remain read-only. These commands
/// persist reviewed local authority candidates and never change the service's
/// authentication or authorization decisions.

///|
async fn rbac_projection_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "rbac_role" && aggregate_type != "rbac_user_roles" {
    raise fail("unsupported RBAC projection type")
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload, source_event_id FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid RBAC projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("RBAC projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn rbac_latest_projection(
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
    _ => raise fail("invalid RBAC projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn rbac_body_text(body : Json, key : String, alternate : String) -> String {
  let value = json_text(body, key, "")
  if value.is_empty() {
    json_text(body, alternate, "")
  } else {
    value
  }
}

///|
fn rbac_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/rbac/roles" {
    return Some(("role_upsert", None))
  }
  let role_prefix = "/api/company/rbac/roles/"
  if request_method is @http.Delete && path.has_prefix(role_prefix) {
    let role_code = path[role_prefix.length():].to_owned()
    if valid_identifier(role_code) {
      return Some(("role_delete", Some(role_code)))
    }
  }
  let assignment_prefix = "/api/company/rbac/users/"
  if request_method is @http.Post && path.has_prefix(assignment_prefix) {
    let rest = path[assignment_prefix.length():]
      .to_owned()
      .split("/")
      .to_array()
    if rest.length() == 2 &&
      rest[1] == "roles" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("user_roles", Some(rest[0].to_owned())))
    }
  }
  None
}

///|
async fn rbac_require_super(
  actor_id : String,
) -> String raise CompanyServiceError {
  let profile = auth_current_user(actor_id)
  match profile {
    Some(value) => {
      let data = json_field(value, "data").unwrap_or(Json::null())
      if !json_bool(data, "enabled", false) {
        raise reject(403, "user not found or disabled")
      }
      if !json_bool(data, "isSuperUser", false) {
        raise reject(403, "RBAC management requires an enabled super-user")
      }
      json_text(data, "userId", actor_id)
    }
    None => raise reject(403, "user not found or disabled")
  }
}

///|
fn rbac_permission_values(body : Json) -> Array[Json] raise CompanyServiceError {
  match json_field(body, "permissions") {
    None => []
    Some(Array(values)) => {
      let result : Array[Json] = []
      for value in values {
        match value {
          String(text) if valid_identifier(text) =>
            result.push(Json::string(text))
          _ => raise reject(422, "permissions must contain valid identifiers")
        }
      }
      result
    }
    Some(_) => raise reject(422, "permissions must be an array")
  }
}

///|
fn rbac_role_codes(body : Json) -> Array[Json] raise CompanyServiceError {
  let value = match json_field(body, "roleCodes") {
    Some(value) => value
    None =>
      match json_field(body, "role_codes") {
        Some(value) => value
        None => Json::array([])
      }
  }
  match value {
    Array(values) => {
      let result : Array[Json] = []
      for item in values {
        match item {
          String(text) if valid_identifier(text) =>
            result.push(Json::string(text))
          _ => raise reject(422, "roleCodes must contain valid identifiers")
        }
      }
      result
    }
    _ => raise reject(422, "roleCodes must be an array")
  }
}

///|
async fn rbac_role_exists(role_code : String) -> Bool raise CompanyServiceError {
  let local_projection = rbac_latest_projection("rbac_role", role_code)
  match local_projection {
    Some((payload, _)) => json_text(payload, "state", "active") != "deleted"
    None => {
      let rows = raw_source_rows("sys_role", 500)
      rows.any(fn(row) {
        json_text(row.payload, "role_code", row.record_id) == role_code
      })
    }
  }
}

///|
async fn rbac_command(
  command_type : String,
  target_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["role_upsert", "role_delete", "user_roles"].contains(command_type) {
    raise reject(404, "unsupported RBAC command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user_id = rbac_require_super(actor_id)
  let (aggregate_type, aggregate_id, request) = if command_type == "role_upsert" {
    let role_code = rbac_body_text(body, "roleCode", "role_code")
    let role_name = rbac_body_text(body, "roleName", "role_name")
    if !valid_identifier(role_code) || role_name.is_empty() {
      raise reject(400, "roleCode/roleName are required")
    }
    let data_scope = rbac_body_text(body, "dataScope", "data_scope")
    let scope = if data_scope.is_empty() { "self" } else { data_scope }
    if scope != "self" && scope != "bu" && scope != "group" {
      raise reject(422, "dataScope is invalid")
    }
    let permissions = rbac_permission_values(body)
    (
      "rbac_role",
      role_code,
      Json::object({
        "role_code": Json::string(role_code),
        "role_name": Json::string(role_name),
        "description": Json::string(rbac_body_text(body, "description", "")),
        "data_scope": Json::string(scope),
        "permissions": Json::array(permissions),
        "is_system": Json::boolean(false),
        "state": Json::string("active"),
        "actor_id": Json::string(actor_id),
      }),
    )
  } else if command_type == "role_delete" {
    let role_code = match target_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "role code is required")
    }
    (
      "rbac_role",
      role_code,
      Json::object({
        "role_code": Json::string(role_code),
        "state": Json::string("deleted"),
        "actor_id": Json::string(actor_id),
      }),
    )
  } else {
    let user_id = match target_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "user id is required")
    }
    let users = raw_source_rows("sys_user", 500)
    if !users.any(fn(row) {
        json_text(row.payload, "user_id", row.record_id) == user_id
      }) {
      raise reject(404, "user not found; local user creation remains gated")
    }
    let role_codes = rbac_role_codes(body)
    for role_json in role_codes {
      let role_code = match role_json {
        String(text) => text
        _ => ""
      }
      if !rbac_role_exists(role_code) {
        raise reject(422, "role does not exist: " + role_code)
      }
    }
    (
      "rbac_user_roles",
      user_id,
      Json::object({
        "user_id": Json::string(user_id),
        "role_codes": Json::array(role_codes),
        "state": Json::string("active"),
        "actor_id": Json::string(actor_id),
      }),
    )
  }
  let request = Json::object({
    "command_type": Json::string(command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "actor_user_id": Json::string(actor_user_id),
    "changes": request,
  })
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
          "rbac": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = rbac_latest_projection(aggregate_type, aggregate_id)
  if command_type == "role_upsert" {
    let imported = raw_source_rows("sys_role", 500).any(fn(row) {
      json_text(row.payload, "role_code", row.record_id) == aggregate_id
    })
    if imported && current is None {
      raise reject(409, "imported roles are read-only; use a local role code")
    }
  } else if command_type == "role_delete" {
    match current {
      None => {
        if raw_source_rows("sys_role", 500).any(fn(row) {
            json_text(row.payload, "role_code", row.record_id) == aggregate_id
          }) {
          raise reject(409, "imported roles are read-only")
        }
        raise reject(404, "local role not found")
      }
      Some((payload, _)) if json_text(payload, "state", "active") == "deleted" =>
        raise reject(409, "role is already deleted")
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
  let next_revision = current_revision + 1
  let event_id = "rbac:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload : Json = if command_type == "role_delete" {
    let fields : Map[String, Json] = match current_payload {
      Object(values) => values
      _ => {}
    }
    fields.set("state", Json::string("deleted"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "role_upsert" {
    let changes = match request {
      Object(fields) => fields.get("changes").unwrap_or(Json::null())
      _ => Json::null()
    }
    let fields : Map[String, Json] = {}
    match changes {
      Object(values) => values.each((key, value) => fields.set(key, value))
      _ => ()
    }
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else {
    let changes : Json = match request {
      Object(fields) => fields.get("changes").unwrap_or(Json::null())
      _ => Json::null()
    }
    Json::object({
      "user_id": Json::string(aggregate_id),
      "role_codes": json_field(changes, "role_codes").unwrap_or(Json::array([])),
      "state": Json::string("active"),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
      "updated_by": Json::string(actor_id),
    })
  }
  let result = Json::object({
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "state": json_field(next_payload, "state").unwrap_or(Json::string("active")),
    "role_codes": if command_type == "user_roles" {
      json_field(next_payload, "role_codes").unwrap_or(Json::array([]))
    } else {
      Json::array([])
    },
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "authorization_candidate": Json::boolean(true),
    "security_effect": Json::boolean(true),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("rbac"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("rbac." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": json_text(next_payload, "state", "active"),
    "revision": Json::number(next_revision.to_double()),
    "authorization_candidate": Json::boolean(true),
    "security_effect": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
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
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "role_upsert" && current is None {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "rbac": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
async fn rbac_active_role_payloads() -> Array[Json] raise CompanyServiceError {
  rbac_projection_payloads("rbac_role").filter(fn(payload) {
    json_text(payload, "state", "active") != "deleted"
  })
}

///|
async fn rbac_active_assignment_payloads() -> Array[Json] raise CompanyServiceError {
  rbac_projection_payloads("rbac_user_roles").filter(fn(payload) {
    json_text(payload, "state", "active") != "deleted"
  })
}

///|
fn rbac_permissions(payload : Json) -> Json {
  match json_field(payload, "permissions") {
    Some(Array(values)) => Json::array(values)
    Some(String(text)) => @json.parse(text) catch { _ => Json::array([]) }
    _ => Json::array([])
  }
}
