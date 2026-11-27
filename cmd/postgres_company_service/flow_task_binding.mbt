///|
fn flow_task_route(path : String) -> (String, String)? {
  match path.split("/").map(part => part.to_owned()).collect() {
    ["", "api", "company", "plan", "tasks", task, action] if valid_identifier(
        task,
      ) &&
      ["flow-snapshot", "flow-bindings"].contains(action) =>
      Some((task, action))
    _ => None
  }
}

///|
fn flow_report_read_route(path : String) -> (String, String)? {
  match path.split("/").map(part => part.to_owned()).collect() {
    [
      "",
      "api",
      "company",
      "internal",
      "plan",
      "tasks",
      task,
      "flow-report-receipts",
      key,
    ] if valid_identifier(task) && valid_identifier(key) => Some((task, key))
    _ => None
  }
}

///|
async fn flow_report_read(
  task : String,
  key : String,
  actor : String,
) -> Json raise CompanyServiceError {
  let command = match existing_company_command(key) {
    Some(value) => value
    None => raise reject(404, "persisted Flow report was not found")
  }
  let request = json_field(command, "request").unwrap_or(Json::null())
  if json_text(command, "kind", "") != "company_command" ||
    json_text(command, "command_family", "") != "delivery" ||
    json_text(command, "family", "") != "task_report" ||
    json_text(command, "command_type", "") != "report" ||
    json_text(command, "idempotency_key", "") != key ||
    json_text(request, "task_id", "") != task ||
    json_text(command, "actor_id", "") != actor {
    raise reject(
      403, "persisted Flow report belongs to another task, command or actor",
    )
  }
  let approval = flow_approval_read(
    task,
    json_text(request, "flow_approval_key", ""),
    actor,
  )
  @company_flow.validate_approval(
    json_field(request, "flow_binding").unwrap_or(Json::null()),
    json_field(approval, "command").unwrap_or(Json::null()),
  ) catch {
    _ => raise reject(409, "persisted report does not match its approval")
  }
  { "command": command }
}

///|
fn flow_approval_read_route(path : String) -> (String, String)? {
  match path.split("/").map(part => part.to_owned()).collect() {
    [
      "",
      "api",
      "company",
      "internal",
      "plan",
      "tasks",
      task,
      "flow-approvals",
      key,
    ] if valid_identifier(task) && valid_identifier(key) => Some((task, key))
    _ => None
  }
}

///|
async fn flow_approval_read(
  task : String,
  key : String,
  actor : String,
) -> Json raise CompanyServiceError {
  let command = match existing_company_command(key) {
    Some(value) => value
    None => raise reject(404, "persisted Flow approval was not found")
  }
  let binding = json_field(
    json_field(command, "request").unwrap_or(Json::null()),
    "binding",
  ).unwrap_or(Json::null())
  if json_text(binding, "task_id", "") != task ||
    json_text(command, "actor_id", "") != actor {
    raise reject(
      403, "persisted Flow approval belongs to another task or actor",
    )
  }
  @company_flow.validate_approval(binding, command) catch {
    _ => raise reject(409, "persisted Flow approval is incomplete")
  }
  { "command": command }
}

///|
fn flow_binding_request(
  task : Json,
  revision : Int32,
  body : Json,
  actor : String,
) -> Json raise CompanyServiceError {
  let binding = json_field(body, "binding").unwrap_or(Json::null())
  if json_text(task, "created_by", "") != actor {
    raise reject(403, "only the task creator may approve this Flow binding")
  }
  @company_flow.require_current(binding, @company_flow.snapshot(task, revision)) catch {
    _ =>
      raise reject(
        409, "task snapshot or Flow binding changed; capture and approve a new attempt",
      )
  }
  let authority = plan_task_authority(
    body,
    actor,
    json_text(task, "project_id", ""),
    "project:task:update",
  )
  {
    "command_type": "approve",
    "actor_id": actor,
    "binding": binding,
    "authority": authority,
  }
}

///|
fn flow_binding_command(request : Json, key : String) -> Json {
  let binding = json_field(request, "binding").unwrap_or(Json::null())
  let actor = json_text(request, "actor_id", "")
  let event = "flow_task_binding:approve:" + key
  {
    "kind": "company_command",
    "command_family": "flow_task_binding",
    "command_type": "approve",
    "aggregate_type": "plan_task",
    "aggregate_id": json_text(binding, "task_id", ""),
    "actor_id": actor,
    "idempotency_key": key,
    "request": request,
    "result": {
      "task_id": json_text(binding, "task_id", ""),
      "actor_id": actor,
      "state": "approved",
      "source_revision": json_field(binding, "source_revision").unwrap_or(
        Json::null(),
      ),
      "event_id": event,
      "audit_id": event + ":audit",
      "execution_effect": false,
      "acceptance_effect": false,
    },
  }
}

///|
/// A different approval key cannot repurpose an already recorded Flow attempt.
/// The existing company-record lock makes this guard atomic with its insert.
fn flow_binding_atomic_sql(
  task_id : String,
  revision : Int32,
  source : String,
  binding : Json,
  sql : String,
) -> String {
  let guarded = "IF NOT EXISTS (SELECT 1 FROM company_record WHERE record_type='company_command' AND payload->>'command_family'='flow_task_binding' AND payload->'request'->'binding'->>'attempt_id'=" +
    @postgres.sql_literal(json_text(binding, "attempt_id", "")) +
    " AND payload->'request'->'binding'->>'run_id'=" +
    @postgres.sql_literal(json_text(binding, "run_id", "")) +
    ") THEN " +
    sql +
    " END IF;"
  plan_task_atomic_command_sql(task_id, revision, source, guarded)
}

///|
async fn flow_task_handle(
  task_id : String,
  action : String,
  body : Json,
  actor : String,
  key : String,
) -> (Int32, Json) raise CompanyServiceError {
  if action == "flow-snapshot" {
    let (task, revision) = match plan_task_latest(task_id) {
      Some(value) => value
      None => raise reject(404, "local task not found")
    }
    if json_text(task, "created_by", "") != actor {
      raise reject(403, "task owner required")
    }
    let snapshot = @company_flow.snapshot(task, revision) catch {
      _ => raise reject(409, "task is not an active local digital-plan task")
    }
    return (200, snapshot)
  }
  if !valid_identifier(key) {
    raise reject(422, "a valid approval Idempotency-Key is required")
  }
  let existing = existing_company_command(key)
  // A lost acknowledgement recovers the same approved history, not fresh authority.
  if existing is Some(command) {
    let saved = json_field(command, "request").unwrap_or(Json::null())
    let binding = json_field(saved, "binding").unwrap_or(Json::null())
    let snapshot = json_field(binding, "snapshot").unwrap_or(Json::null())
    let request = flow_binding_request(
      json_field(snapshot, "task").unwrap_or(Json::null()),
      json_int(snapshot, "source_revision", 0),
      body,
      actor,
    )
    if json_text(binding, "task_id", "") != task_id ||
      json_text(command, "command_family", "") != "flow_task_binding" ||
      !json_equal(saved, request) {
      raise reject(409, "approval key already belongs to another exact request")
    }
    return (200, { "command": command, "idempotent_replay": true })
  }
  let (task, revision) = match plan_task_latest(task_id) {
    Some(value) => value
    None => raise reject(404, "local task not found")
  }
  let request = flow_binding_request(task, revision, body, actor)
  let command = flow_binding_command(request, key)
  let result = json_field(command, "result").unwrap_or(Json::null())
  let event = json_text(result, "event_id", "")
  let source = "moonproj:command:" + key
  let sql = "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(event + ":audit") +
    ",4," +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event) +
    ") ON CONFLICT (source_id) DO NOTHING;"
  ignore(
    run_sql(
      flow_binding_atomic_sql(
        task_id,
        revision,
        source,
        json_field(request, "binding").unwrap_or(Json::null()),
        sql,
      ),
    ),
  )
  let persisted = plan_task_applied_command(
    existing_company_command(key),
    request,
  )
  (201, { "command": persisted, "idempotent_replay": false })
}

///|
fn flow_report_request(
  body : Json,
  request : Json,
  approval : Json,
  snapshot : Json?,
  replay : Json?,
  actor : String,
) -> Json raise CompanyServiceError {
  let binding = json_field(body, "flow_binding").unwrap_or(Json::null())
  let key = json_text(body, "flow_approval_key", "")
  if key != json_text(approval, "idempotency_key", "") ||
    actor != json_text(approval, "actor_id", "") ||
    json_text(binding, "task_id", "") != json_text(body, "task_id", "") ||
    json_text(binding, "project_id", "") != json_text(body, "project_id", "") {
    raise reject(
      403, "report must use its exact approval and signed task owner",
    )
  }
  @company_flow.validate_approval(binding, approval) catch {
    _ => raise reject(409, "report Flow approval does not match")
  }
  match replay {
    Some(stored) =>
      if json_field(stored, "flow_binding") != Some(binding) ||
        json_text(stored, "flow_approval_key", "") != key {
        raise reject(409, "report replay must preserve the exact Flow binding")
      }
    None =>
      match snapshot {
        Some(current) =>
          @company_flow.require_current(binding, current) catch {
            _ => raise reject(409, "task revision changed before report return")
          }
        None => raise reject(409, "current task snapshot is required")
      }
  }
  let fields = match request {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields["flow_binding"] = binding
  fields["flow_approval_key"] = Json::string(key)
  fields["flow_source_revision"] = json_field(binding, "source_revision").unwrap_or(
    Json::null(),
  )
  Json::object(fields)
}

///|
async fn authorize_flow_report(
  body : Json,
  request : Json,
  actor : String,
  replay : Json?,
) -> Json raise CompanyServiceError {
  let key = json_text(body, "flow_approval_key", "")
  if key.is_empty() && json_field(body, "flow_binding") is None {
    if replay is Some(stored) && json_field(stored, "flow_binding") is Some(_) {
      raise reject(409, "Flow report replay cannot omit its approval")
    }
    return request
  }
  let approval = match existing_company_command(key) {
    Some(command) => command
    None => raise reject(409, "Flow approval command was not found")
  }
  let snapshot = if replay is Some(_) {
    None
  } else {
    let (task, revision) = match
      plan_task_latest(json_text(body, "task_id", "")) {
      Some(value) => value
      None => raise reject(404, "Flow report task was not found")
    }
    Some(
      @company_flow.snapshot(task, revision) catch {
        _ => raise reject(409, "Flow task is no longer reportable")
      },
    )
  }
  flow_report_request(body, request, approval, snapshot, replay, actor)
}

///|
fn flow_report_atomic_sql(
  request : Json,
  source : String,
  command_sql : String,
) -> String {
  let guarded = "IF NOT EXISTS (SELECT 1 FROM company_aggregate_projection WHERE aggregate_type='task_report' AND aggregate_id=" +
    @postgres.sql_literal(json_text(request, "report_id", "")) +
    ") THEN " +
    command_sql +
    " END IF;"
  plan_task_atomic_command_sql(
    json_text(request, "task_id", ""),
    json_int(request, "flow_source_revision", 0),
    source,
    guarded,
  )
}
