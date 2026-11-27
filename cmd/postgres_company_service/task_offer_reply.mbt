///|
// An already-arrived reply is a human-recorded observation on a saved proposal.
// The recorder's signed company command is not the customer's authentication,
// a delivery acceptance, a contract, a demand decision, or a financial event.
fn plan_task_reply_request(
  task_id : String,
  project_id : String,
  body : Json,
  actor : String,
) -> Json raise CompanyServiceError {
  let fields = match body {
    Object(fields) => fields
    _ => raise reject(422, "proposal reply must be an object")
  }
  for key, _ in fields {
    if !["idempotency_key", "authority", "reply_base_revision", "offer_reply"].contains(
        key,
      ) {
      raise reject(422, "proposal reply cannot change task fields: " + key)
    }
  }
  let revision = match json_field(body, "reply_base_revision") {
    Some(Number(value, ..)) if value > 0.0 &&
      value <= 2147483646.0 &&
      value == value.to_int().to_double() => value.to_int()
    _ =>
      raise reject(
        422, "reply_base_revision must be the positive task revision you read",
      )
  }
  let reply = @task_evidence.normalize_offer_reply(
    json_field(body, "offer_reply").unwrap_or(Json::null()),
  ) catch {
    @task_evidence.InvalidOfferReply(message) => raise reject(422, message)
  }
  guard json_field(reply, "offer_revision") is Some(Number(target, ..)) &&
    target <= revision.to_double() else {
    raise reject(
      422, "offer_revision must identify a proposal saved at or before the task revision you read",
    )
  }
  let authority = plan_task_authority(
    body, actor, project_id, "project:task:update",
  )
  {
    "command_type": "update",
    "task_id": task_id,
    "project_id": project_id,
    "actor_id": actor,
    "reply_base_revision": revision,
    "changes": { "offer_reply": reply },
    "authority": authority,
  }
}

///|
fn plan_task_reply_replay(
  existing : Json,
  task_id : String,
  body : Json,
  actor : String,
) -> Json raise CompanyServiceError {
  let previous = json_field(existing, "request").unwrap_or(Json::null())
  if json_text(existing, "command_family", "") != "plan_task" ||
    json_text(existing, "command_type", "") != "update" ||
    json_text(existing, "aggregate_id", "") != task_id ||
    json_text(existing, "actor_id", "") != actor ||
    json_text(previous, "task_id", "") != task_id ||
    !valid_identifier(json_text(previous, "project_id", "")) {
    raise reject(409, "Idempotency-Key belongs to another task or actor")
  }
  let request = plan_task_reply_request(
    task_id,
    json_text(previous, "project_id", ""),
    body,
    actor,
  )
  if !json_equal(previous, request) {
    raise reject(409, "Idempotency-Key was already used for another request")
  }
  {
    "command": existing,
    "task": json_field(existing, "result").unwrap_or(Json::null()),
    "idempotent_replay": true,
  }
}

///|
fn plan_task_reply_validate_history(
  task_id : String,
  history : Json,
  reply : Json,
) -> Unit raise CompanyServiceError {
  if json_text(history, "task_id", "") != task_id {
    raise reject(409, "proposal history belongs to another task")
  }
  let target = json_int(reply, "offer_revision", 0)
  let offers = match json_field(history, "offer_history") {
    Some(Array(items)) => items
    _ => []
  }
  let matches = offers.filter(item => json_int(item, "revision", 0) == target)
  if matches.length() != 1 ||
    json_text(matches[0], "audit_state", "") != "available" {
    raise reject(
      409, "reply must identify one saved proposal revision with its recording receipt",
    )
  }
  let previous = json_text(reply, "supersedes_reply_id", "")
  if previous.is_empty() {
    return
  }
  let replies = match json_field(history, "offer_reply_history") {
    Some(Array(items)) => items
    _ => []
  }
  let replaced = replies.filter(item => {
    json_text(item, "reply_id", "") == previous
  })
  if replaced.length() != 1 ||
    json_text(replaced[0], "audit_state", "") != "available" ||
    json_int(
      json_field(replaced[0], "offer_reply").unwrap_or(Json::null()),
      "offer_revision",
      0,
    ) !=
    target {
    raise reject(
      409, "correction must identify a recorded reply to this exact proposal revision",
    )
  }
  if replies.any(item => {
      json_text(
        json_field(item, "offer_reply").unwrap_or(Json::null()),
        "supersedes_reply_id",
        "",
      ) ==
      previous
    }) {
    raise reject(
      409, "reply already has a correction; read and correct the latest recorded reply",
    )
  }
}

///|
fn plan_task_reply_apply(
  current : Json,
  actor : String,
  event_id : String,
) -> Json {
  let fields = match current {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  // Private reply content lives in immutable command history only. Lists and
  // existing proposal exports see no reply body or new business-state claim.
  fields["event_id"] = Json::string(event_id)
  fields["updated_by"] = Json::string(actor)
  fields["source_kind"] = Json::string("command")
  Json::object(fields)
}

///|
fn plan_task_reply_payloads(
  task_id : String,
  current : Json,
  revision : Int32,
  request : Json,
  actor : String,
  key : String,
) -> (Json, Json, Json) {
  let event_id = "plan_task:update:" + key
  let audit_id = event_id + ":audit"
  let result : Json = {
    "taskGuid": task_id,
    "task_id": task_id,
    "state": "pending",
    "revision": revision + 1,
    "reply_id": event_id,
    "event_id": event_id,
    "audit_id": audit_id,
    "actor_id": actor,
    "sourceKind": "command",
    "cash_effect": false,
    "accounting_effect": false,
    "tax_effect": false,
  }
  let command : Json = {
    "kind": "company_command",
    "command_family": "plan_task",
    "command_type": "update",
    "idempotency_key": key,
    "aggregate_type": "plan_task",
    "aggregate_id": task_id,
    "actor_id": actor,
    "request": request,
    "result": result,
  }
  let audit : Json = {
    "audit_id": audit_id,
    "action": "plan.task.offer_reply",
    "aggregate_type": "plan_task",
    "aggregate_id": task_id,
    "actor_id": actor,
    "event_id": event_id,
    "state": "pending",
    "revision": revision + 1,
  }
  (command, audit, plan_task_reply_apply(current, actor, event_id))
}

///|
fn plan_task_reply_sql(
  task_id : String,
  current : Json,
  revision : Int32,
  request : Json,
  actor : String,
  key : String,
) -> String {
  let (command, audit, next) = plan_task_reply_payloads(
    task_id, current, revision, request, actor, key,
  )
  let event = "plan_task:update:" + key
  let source = "moonproj:command:" + key
  let command_sql = "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(source) +
    "); INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('plan_task'," +
    @postgres.sql_literal(task_id) +
    "," +
    (revision + 1).to_string() +
    "," +
    @postgres.sql_literal(next.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(event) +
    "); INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(event + ":audit") +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event) +
    ");"
  plan_task_offer_guarded_sql(
    task_id, revision, request, actor, key, command_sql,
  )
}

///|
async fn plan_task_reply_update_command(
  aggregate_id : String?,
  body : Json,
  actor : String,
  key : String,
) -> (Int32, Json) raise CompanyServiceError {
  let id = match aggregate_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "task_id is required")
  }
  match json_field(body, "idempotency_key") {
    None => ()
    Some(String(value)) if value == key => ()
    _ => raise reject(422, "reply body and header idempotency keys differ")
  }
  // Exact replay resolves before later eligibility and revision checks.
  match existing_company_command(key) {
    Some(existing) =>
      return (200, plan_task_reply_replay(existing, id, body, actor))
    None => ()
  }
  let (current, revision) = match plan_task_latest(id) {
    Some(value) => value
    None => raise reject(404, "proposal task does not exist")
  }
  if json_text(current, "created_by", "") != actor {
    raise reject(
      403, "only the task creator may record replies on this proposal",
    )
  }
  if !plan_task_offer_eligible(current) {
    raise reject(409, "proposal replies require a pending unexecuted task")
  }
  let request = plan_task_reply_request(
    id,
    json_text(current, "project_id", ""),
    body,
    actor,
  )
  if json_int(request, "reply_base_revision", 0) != revision {
    raise reject(
      409, "task revision changed; keep your reply draft and read the current task",
    )
  }
  let reply = json_field(json_field(request, "changes").unwrap(), "offer_reply").unwrap()
  plan_task_reply_validate_history(id, plan_task_receipt_history(id), reply)
  let sql = plan_task_reply_sql(id, current, revision, request, actor, key)
  let _ = run_sql(sql) catch {
    error => {
      let recovered = existing_company_command(key) catch { _ => None }
      match recovered {
        Some(existing) =>
          return (200, plan_task_reply_replay(existing, id, body, actor))
        None => raise error
      }
    }
  }
  let persisted = plan_task_applied_command(
    existing_company_command(key),
    request,
  )
  (
    200,
    {
      "command": persisted,
      "task": json_field(persisted, "result").unwrap_or(Json::null()),
      "idempotent_replay": false,
    },
  )
}
