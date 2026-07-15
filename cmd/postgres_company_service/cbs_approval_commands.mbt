///|
/// Local approval-rule configuration commands.
///
/// These are reviewed configuration candidates only. They never authorize a
/// request by themselves and never start or advance a workflow.

///|
fn cbs_approval_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if path == "/api/company/cbs/approval-rules" && request_method is @http.Post {
    return Some(("create", None))
  }
  let prefix = "/api/company/cbs/approval-rules/"
  if path.has_prefix(prefix) {
    let rule_guid = path[prefix.length():].to_owned()
    if valid_identifier(rule_guid) {
      if request_method is @http.Put {
        return Some(("update", Some(rule_guid)))
      }
      if request_method is @http.Delete {
        return Some(("delete", Some(rule_guid)))
      }
    }
  }
  None
}

///|
fn cbs_approval_text(
  body : Json,
  primary : String,
  alternate : String,
) -> String {
  let value = json_text(body, primary, "").trim().to_owned()
  if value.is_empty() {
    json_text(body, alternate, "").trim().to_owned()
  } else {
    value
  }
}

///|
fn cbs_approval_threshold(
  body : Json,
  primary : String,
  fallback : Double,
) -> Double raise CompanyServiceError {
  match json_field(body, primary) {
    Some(Number(number, ..)) if number >= 0.0 => number
    Some(String(text)) => {
      let value = parse_number(text)
      if value < 0.0 {
        raise reject(422, "threshold must be non-negative")
      }
      value
    }
    Some(_) => raise reject(422, "threshold must be a decimal number")
    None => fallback
  }
}

///|
fn cbs_approval_envelope(data : Json, command : Json, replay : Bool) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "command": command,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("imported_or_command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "approval_configuration_effect": Json::boolean(true),
    "authorization_effect": Json::boolean(false),
    "workflow_effect": Json::boolean(false),
    "budget_consumption": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn cbs_approval_command(
  command_type : String,
  rule_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user_id = cbs_require_user(actor_id)
  let (aggregate_id, request, result_data) = if command_type == "create" {
    let biz_type = cbs_approval_text(body, "bizType", "biz_type")
    if biz_type.is_empty() || !valid_identifier(biz_type) {
      raise reject(400, "bizType is required")
    }
    let configured_actor = cbs_approval_text(
      body, "actorUserId", "actor_user_id",
    )
    if configured_actor.is_empty() || !valid_identifier(configured_actor) {
      raise reject(400, "actorUserId is required")
    }
    let threshold = cbs_approval_threshold(body, "threshold", 0.0)
    let requested = cbs_approval_text(body, "ruleGuid", "rule_guid")
    let id = if requested.is_empty() {
      "cbs-approval-" + idempotency_key
    } else {
      requested
    }
    if !valid_identifier(id) {
      raise reject(422, "ruleGuid contains unsupported characters")
    }
    (
      id,
      Json::object({
        "command_type": Json::string(command_type),
        "rule_guid": Json::string(id),
        "biz_type": Json::string(biz_type),
        "threshold": Json::number(threshold),
        "actor_user_id": Json::string(configured_actor),
        "description": Json::string(cbs_approval_text(body, "description", "")),
        "actor_id": Json::string(actor_id),
        "actor_user_id_command": Json::string(actor_user_id),
      }),
      Json::object({
        "ruleGuid": Json::string(id),
        "bizType": Json::string(biz_type),
        "threshold": Json::number(threshold),
      }),
    )
  } else {
    let id = match rule_guid {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "ruleGuid is required")
    }
    let current = match cbs_latest_projection("cbs_approval_rule", id) {
      Some((value, _)) => value
      None => {
        let imported = raw_source_rows("wf_approval_rule", 1000)
        if imported.any(fn(row) {
            report_text(row.payload, "rule_guid", row.record_id) == id &&
            json_field(row.payload, "deleted_at") is None
          }) {
          raise reject(409, "imported approval rules are read-only")
        }
        raise reject(404, "approval rule not found")
      }
    }
    if command_type == "update" {
      let changes : Map[String, Json] = {}
      match json_field(body, "threshold") {
        Some(_) =>
          changes.set(
            "threshold",
            Json::number(
              cbs_approval_threshold(
                body,
                "threshold",
                json_number(current, "threshold", 0.0),
              ),
            ),
          )
        None => ()
      }
      match json_field(body, "actorUserId") {
        Some(String(value)) if !value.trim().is_empty() &&
          valid_identifier(value) =>
          changes.set("actor_user_id", Json::string(value.trim().to_owned()))
        Some(_) =>
          raise reject(422, "actorUserId contains unsupported characters")
        None => ()
      }
      match json_field(body, "description") {
        Some(String(value)) => changes.set("description", Json::string(value))
        Some(_) => raise reject(422, "description must be text")
        None => ()
      }
      if changes.is_empty() {
        raise reject(422, "approval rule update requires a mutable field")
      }
      (
        id,
        Json::object({
          "command_type": Json::string(command_type),
          "rule_guid": Json::string(id),
          "changes": Json::object(changes),
          "actor_id": Json::string(actor_id),
          "actor_user_id_command": Json::string(actor_user_id),
        }),
        Json::object({ "ruleGuid": Json::string(id) }),
      )
    } else {
      (
        id,
        Json::object({
          "command_type": Json::string(command_type),
          "rule_guid": Json::string(id),
          "actor_id": Json::string(actor_id),
          "actor_user_id_command": Json::string(actor_user_id),
        }),
        Json::object({ "ruleGuid": Json::string(id) }),
      )
    }
  }
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
        cbs_approval_envelope(
          json_field(existing, "result").unwrap_or(result_data),
          existing,
          true,
        ),
      )
    }
    None => ()
  }
  let imported = raw_source_rows("wf_approval_rule", 1000)
  if command_type == "create" &&
    (
      cbs_latest_projection("cbs_approval_rule", aggregate_id) is Some(_) ||
      imported.any(fn(row) {
        report_text(row.payload, "rule_guid", row.record_id) == aggregate_id &&
        json_field(row.payload, "deleted_at") is None
      })
    ) {
    raise reject(409, "approval rule already exists")
  }
  let current = cbs_latest_projection("cbs_approval_rule", aggregate_id)
  let current_payload = match current {
    Some((value, _)) => value
    None => Json::null()
  }
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "cbs-approval:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    let fields = cbs_copy_fields(request)
    fields.set("display_order", Json::number(1.0))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("created_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "update" {
    let fields = cbs_copy_fields(current_payload)
    match json_field(request, "changes") {
      Some(Object(changes)) =>
        changes.each((key, value) => fields.set(key, value))
      _ => ()
    }
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else {
    let fields = cbs_copy_fields(current_payload)
    fields.set("state", Json::string("deleted"))
    fields.set("deleted_at", Json::string(event_id))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  }
  let result = Json::object({
    "ruleGuid": Json::string(aggregate_id),
    "bizType": Json::string(json_text(next_payload, "biz_type", "")),
    "threshold": Json::number(json_number(next_payload, "threshold", 0.0)),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "approval_configuration_effect": Json::boolean(true),
    "authorization_effect": Json::boolean(false),
    "workflow_effect": Json::boolean(false),
    "authorizing": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_approval_rule"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_approval_rule"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs_approval_rule." + command_type),
    "aggregate_type": Json::string("cbs_approval_rule"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(revision.to_double()),
    "approval_configuration_effect": Json::boolean(true),
    "authorization_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_approval_rule'," +
    @postgres.sql_literal(aggregate_id) +
    "," +
    revision.to_string() +
    "," +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb," +
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
    if command_type == "create" {
      201
    } else {
      200
    },
    cbs_approval_envelope(result, command, false),
  )
}
