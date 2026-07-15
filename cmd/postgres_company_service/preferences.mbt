///|
/// Signed-user-scoped preference commands.
/// Preferences are local command projections only; they have no authority,
/// provider, accounting, cash, or tax effect.

///|
async fn latest_preference_payload(
  aggregate_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'user_preference' AND aggregate_id = " +
    @postgres.sql_literal(aggregate_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid preference projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn preference_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String)? {
  let prefix = "/api/company/source/auth/prefs/"
  if path.has_prefix(prefix) {
    let key = path[prefix.length():].to_owned()
    if valid_identifier(key) {
      if request_method is @http.Put {
        return Some(("set", key))
      }
      if request_method is @http.Delete {
        return Some(("delete", key))
      }
    }
  }
  None
}

///|
async fn preference_command(
  command_type : String,
  user_code : String,
  pref_key : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "set" && command_type != "delete" {
    raise reject(404, "unsupported preference command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  if !valid_identifier(user_code) || actor_id != user_code {
    raise reject(403, "preference writes must be scoped to the signed user")
  }
  if !valid_identifier(pref_key) {
    raise reject(422, "preference key contains unsupported characters")
  }
  let profile = auth_current_user(user_code)
  match profile {
    Some(value) if json_bool(
        json_field(value, "data").unwrap_or(Json::null()),
        "enabled",
        false,
      ) => ()
    _ => raise reject(403, "user not found or disabled")
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      let request_value = match json_field(body, "value") {
        Some(value) => value
        None => Json::null()
      }
      let expected = Json::object({
        "command_type": Json::string(command_type),
        "user_code": Json::string(user_code),
        "pref_key": Json::string(pref_key),
        "actor_id": Json::string(actor_id),
        "value": request_value,
      })
      if !json_equal(stored_request, expected) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "preference": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let value = json_field(body, "value").unwrap_or(Json::null())
  if value.stringify().length() > 64 * 1024 {
    raise reject(422, "preference value is too large")
  }
  let aggregate_id = user_code + ":" + pref_key
  let current = latest_preference_payload(aggregate_id)
  if command_type == "delete" && current is None {
    raise reject(404, "preference not found")
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "set" { "active" } else { "deleted" }
  let next_revision = current_revision + 1
  let event_id = "preference:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + idempotency_key
  let request = Json::object({
    "command_type": Json::string(command_type),
    "user_code": Json::string(user_code),
    "pref_key": Json::string(pref_key),
    "actor_id": Json::string(actor_id),
    "value": value,
  })
  let result = Json::object({
    "user_code": Json::string(user_code),
    "pref_key": Json::string(pref_key),
    "value": if command_type == "set" {
      value
    } else {
      json_field(current_payload, "value").unwrap_or(Json::null())
    },
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("preference"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("user_preference"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let next_payload = if command_type == "set" {
    Json::object({
      "command_type": Json::string(command_type),
      "user_code": Json::string(user_code),
      "pref_key": Json::string(pref_key),
      "actor_id": Json::string(actor_id),
      "value": value,
      "state": Json::string(next_state),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
      "updated_by": Json::string(actor_id),
    })
  } else {
    let fields : Map[String, Json] = match current_payload {
      Object(values) => values
      _ => {}
    }
    fields.set("state", Json::string(next_state))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  }
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("preference." + command_type),
    "aggregate_type": Json::string("user_preference"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(next_state),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('user_preference', " +
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
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "command": command_payload,
      "preference": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
