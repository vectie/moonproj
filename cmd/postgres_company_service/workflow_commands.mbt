///|
/// Local workflow-instance commands.
///
/// These commands provide a durable, signed, command-owned workflow boundary
/// while imported `wf_*` rows remain read-only. They intentionally do not
/// synchronize business records, send notifications, call providers, or post
/// cash/accounting/tax effects.

///|
async fn workflow_command_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "workflow_instance" &&
    aggregate_type != "workflow_action" {
    raise fail("unsupported workflow projection type")
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
        _ => raise fail("invalid workflow command projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("workflow command projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn workflow_latest_projection(
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
    _ => raise fail("invalid workflow projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn workflow_body_text(body : Json, key : String, alternate : String) -> String {
  let primary = json_text(body, key, "")
  if !primary.is_empty() {
    primary
  } else {
    json_text(body, alternate, "")
  }
}

///|
fn workflow_nonempty(value : String, fallback : String) -> String {
  if value.is_empty() {
    fallback
  } else {
    value
  }
}

///|
async fn workflow_actor_context(
  actor_id : String,
) -> (String, String, String) raise CompanyServiceError {
  let profile = auth_current_user(actor_id)
  match profile {
    Some(value) => {
      let data = json_field(value, "data").unwrap_or(Json::null())
      if !json_bool(data, "enabled", false) {
        raise reject(403, "user not found or disabled")
      }
      (
        json_text(data, "userId", actor_id),
        json_text(data, "buGuid", ""),
        json_text(data, "empName", actor_id),
      )
    }
    None => raise reject(403, "user not found or disabled")
  }
}

///|
fn workflow_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/source/workflow/instances" ||
      path == "/api/company/workflow/instances"
    ) {
    return Some(("start", None))
  }
  let prefixes = [
    "/api/company/source/workflow/instances/", "/api/company/workflow/instances/",
  ]
  for prefix in prefixes {
    if path.has_prefix(prefix) {
      let rest = path[prefix.length():].to_owned().split("/").to_array()
      if rest.length() == 2 &&
        valid_identifier(rest[0].to_owned()) &&
        request_method is @http.Post {
        let command_type = if rest[1] == "approve" {
          "approve"
        } else if rest[1] == "reject" {
          "reject"
        } else if rest[1] == "cosigners" {
          "cosign"
        } else if rest[1] == "transfer" {
          "transfer"
        } else {
          ""
        }
        if !command_type.is_empty() {
          return Some((command_type, Some(rest[0].to_owned())))
        }
      }
    }
  }
  None
}

///|
fn workflow_instance_payload(
  instance_id : String,
  process_key : String,
  process_name : String,
  biz_type : String,
  biz_data_guid : String,
  initiator_id : String,
  bu_guid : String,
  initiated_at : String,
  event_id : String,
) -> Json {
  Json::object({
    "process_instance_guid": Json::string(instance_id),
    "process_guid": Json::string("moonproj:workflow:" + process_key),
    "process_name": Json::string(process_name),
    "process_key": Json::string(process_key),
    "biz_type": Json::string(biz_type),
    "biz_data_guid": Json::string(biz_data_guid),
    "status": Json::string("Running"),
    "initiator_guid": Json::string(initiator_id),
    "bu_guid": Json::string(bu_guid),
    "initiated_at": Json::string(initiated_at),
    "completed_at": Json::string(""),
    "current_step_order": Json::number(1),
    "source_kind": Json::string("command"),
    "workflow_definition": Json::string("local_unbound"),
    "event_id": Json::string(event_id),
    "updated_by": Json::string(initiator_id),
  })
}

///|
fn workflow_action_payload(
  action_id : String,
  instance_id : String,
  step_order : Int,
  step_name : String,
  assignee_id : String,
  assignee_name : String,
  decision : String,
  comment : String,
  action_time : String,
  event_id : String,
) -> Json {
  Json::object({
    "action_guid": Json::string(action_id),
    "process_instance_guid": Json::string(instance_id),
    "step_order": Json::number(step_order.to_double()),
    "step_name": Json::string(step_name),
    "assignee_guid": Json::string(assignee_id),
    "assignee_emp_name": Json::string(assignee_name),
    "decision": Json::string(decision),
    "comment": Json::string(comment),
    "action_time": Json::string(action_time),
    "source_kind": Json::string("command"),
    "event_id": Json::string(event_id),
  })
}

///|
fn workflow_command_result(
  instance_id : String,
  status : String,
  current_step_order : Int,
  decision : String,
  event_id : String,
  audit_id : String,
  actor_id : String,
  action_id : String,
) -> Json {
  Json::object({
    "processInstanceGuid": Json::string(instance_id),
    "piGuid": Json::string(instance_id),
    "status": Json::string(status),
    "currentStepOrder": Json::number(current_step_order.to_double()),
    "decision": Json::string(decision),
    "actionGuid": Json::string(action_id),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "sourceKind": Json::string("command"),
    "authorizing": Json::boolean(true),
    "persisted": Json::boolean(true),
    "workflow_effect": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn workflow_command(
  command_type : String,
  instance_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["start", "approve", "reject", "cosign", "transfer"].contains(
      command_type,
    ) {
    raise reject(404, "unsupported workflow command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (actor_user_id, actor_bu_guid, actor_name) = workflow_actor_context(
    actor_id,
  )
  let resolved_instance_id = match command_type {
    "start" => {
      let candidate = "wf-" + idempotency_key
      if !valid_identifier(candidate) {
        raise reject(422, "workflow instance identity is invalid")
      }
      candidate
    }
    _ =>
      match instance_id {
        Some(value) if valid_identifier(value) => value
        _ => raise reject(422, "process instance identity is required")
      }
  }
  let request = Json::object({
    "command_type": Json::string(command_type),
    "instance_id": Json::string(resolved_instance_id),
    "actor_id": Json::string(actor_id),
    "body": body,
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
          "workflow": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let now = @env.now().to_string()
  let (current_payload, current_revision) = match command_type {
    "start" => (Json::null(), 0)
    _ =>
      match
        workflow_latest_projection("workflow_instance", resolved_instance_id) {
        Some(value) => value
        None =>
          raise reject(
            409, "imported workflow rows are read-only; start a local command-owned instance",
          )
      }
  }
  let current_status = json_text(current_payload, "status", "")
  if command_type != "start" &&
    current_status != "Running" &&
    current_status != "Approving" &&
    current_status != "running" {
    raise reject(409, "workflow instance is not awaiting an action")
  }
  if command_type != "start" &&
    json_text(current_payload, "initiator_guid", "") != actor_user_id {
    raise reject(403, "signed actor is not the local workflow owner")
  }
  let process_key = if command_type == "start" {
    workflow_body_text(body, "processKey", "process_key")
  } else {
    json_text(current_payload, "process_key", "")
  }
  let biz_type = if command_type == "start" {
    workflow_body_text(body, "bizType", "biz_type")
  } else {
    json_text(current_payload, "biz_type", "")
  }
  let biz_data_guid = if command_type == "start" {
    workflow_body_text(body, "bizDataGuid", "biz_data_guid")
  } else {
    json_text(current_payload, "biz_data_guid", "")
  }
  if command_type == "start" &&
    (
      !valid_identifier(process_key) ||
      !valid_identifier(biz_type) ||
      !valid_identifier(biz_data_guid)
    ) {
    raise reject(400, "processKey/bizType/bizDataGuid are required")
  }
  let event_id = "workflow:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let action_id = "wf-action-" + idempotency_key
  let step_order = if command_type == "start" {
    1
  } else {
    json_int(current_payload, "current_step_order", 1)
  }
  let comment = workflow_body_text(body, "comment", "note")
  let decision = if command_type == "start" {
    "INITIATED"
  } else if command_type == "approve" {
    "APPROVED"
  } else if command_type == "reject" {
    "REJECTED"
  } else if command_type == "cosign" {
    "COSIGNED"
  } else {
    "TRANSFERRED"
  }
  let next_status = if command_type == "start" ||
    command_type == "cosign" ||
    command_type == "transfer" {
    if command_type == "start" {
      "Running"
    } else {
      current_status
    }
  } else if command_type == "approve" {
    "Completed"
  } else {
    "Rejected"
  }
  let next_revision = current_revision + 1
  let next_payload = if command_type == "start" {
    workflow_instance_payload(
      resolved_instance_id,
      process_key,
      workflow_nonempty(
        workflow_body_text(body, "processName", "process_name"),
        process_key,
      ),
      biz_type,
      biz_data_guid,
      actor_user_id,
      workflow_nonempty(
        workflow_body_text(body, "buGuid", "bu_guid"),
        actor_bu_guid,
      ),
      now,
      event_id,
    )
  } else {
    let fields : Map[String, Json] = match current_payload {
      Object(values) => values
      _ => {}
    }
    fields.set("status", Json::string(next_status))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    if next_status == "Completed" || next_status == "Rejected" {
      fields.set("completed_at", Json::string(now))
    }
    Json::object(fields)
  }
  let action_payload = workflow_action_payload(
    action_id,
    resolved_instance_id,
    step_order,
    json_text(current_payload, "step_name", "local workflow"),
    actor_user_id,
    actor_name,
    decision,
    comment,
    now,
    event_id,
  )
  let result = workflow_command_result(
    resolved_instance_id, next_status, step_order, decision, event_id, audit_id,
    actor_id, action_id,
  )
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("workflow"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("workflow_instance"),
    "aggregate_id": Json::string(resolved_instance_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("workflow." + command_type),
    "aggregate_type": Json::string("workflow_instance"),
    "aggregate_id": Json::string(resolved_instance_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "decision": Json::string(decision),
    "status": Json::string(next_status),
    "revision": Json::number(next_revision.to_double()),
    "authorizing": Json::boolean(true),
    "workflow_effect": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let action_event = event_id + ":action"
  let action_insert = " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('workflow_action', " +
    @postgres.sql_literal(action_id) +
    ", 1, " +
    @postgres.sql_literal(action_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(action_event) +
    ") ON CONFLICT DO NOTHING;"
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('workflow_instance', " +
    @postgres.sql_literal(resolved_instance_id) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING;" +
    action_insert +
    " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "start" {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "workflow": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
