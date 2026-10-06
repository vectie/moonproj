///|
/// Continuations are sibling observations. Never merge them into execution.
fn plan_task_continuations(task : Json) -> Array[Json] {
  match json_field(task, "continuations") {
    Some(Array(items)) => items.copy()
    _ => []
  }
}

///|
fn plan_task_continuation_public(value : Json) -> Json {
  let fields : Map[String, Json] = {}
  for
    key in [
      "continuation_id", "original_run_id", "task_id", "session_id", "original_command_id",
      "prior_result_command_id", "command_id", "client_turn_id", "workspace", "model",
      "input", "state", "summary", "error", "receipt", "evidence_ids", "output_urls",
      "artifact_refs",
    ] {
    match json_field(value, key) {
      Some(item) => fields.set(key, item)
      None => ()
    }
  }
  Json::object(fields)
}

///|
fn plan_task_continuations_public(task : Json) -> Json {
  Json::array(plan_task_continuations(task).map(plan_task_continuation_public))
}

///|
fn plan_task_delivery_source(task : Json) -> Json {
  json_field(task, "selected_delivery_source").unwrap_or(Json::null())
}

///|
fn plan_task_original_source(execution : Json) -> Json {
  {
    "type": "original",
    "original_run_id": json_text(execution, "run_id", ""),
    "command_id": json_text(execution, "command_id", ""),
  }
}

///|
fn plan_task_continuation_source(value : Json) -> Json {
  {
    "type": "continuation",
    "continuation_id": json_text(value, "continuation_id", ""),
    "original_run_id": json_text(value, "original_run_id", ""),
    "command_id": json_text(value, "command_id", ""),
  }
}

///|
fn plan_task_continuation_identity(value : Json) -> Json {
  let fields : Map[String, Json] = {}
  for
    key in [
      "continuation_id", "original_run_id", "task_id", "session_id", "original_command_id",
      "prior_result_command_id", "command_id", "client_turn_id", "workspace", "model",
      "input",
    ] {
    fields.set(key, json_field(value, key).unwrap_or(Json::null()))
  }
  Json::object(fields)
}

///|
fn plan_task_continuation_validate(
  task : Json,
  observation : Json,
) -> Unit raise CompanyServiceError {
  let original = json_field(task, "execution").unwrap_or(Json::null())
  if json_text(original, "task_id", "") != json_text(task, "task_id", "") {
    raise reject(409, "original execution does not belong to this task")
  }
  for
    key in [
      "continuation_id", "original_run_id", "task_id", "session_id", "original_command_id",
      "prior_result_command_id", "command_id", "client_turn_id", "workspace", "model",
      "state",
    ] {
    if !(json_field(observation, key) is Some(String(_))) {
      raise reject(422, "continuation field must be text: " + key)
    }
  }
  for
    (key, original_key) in [
      ("original_run_id", "run_id"),
      ("task_id", "task_id"),
      ("session_id", "session_id"),
      ("original_command_id", "command_id"),
      ("workspace", "workspace"),
    ] {
    if json_text(original, original_key, "").is_empty() ||
      json_text(observation, key, "") != json_text(original, original_key, "") {
      raise reject(
        409, "continuation does not belong to this exact original execution",
      )
    }
  }
  for
    key in [
      "continuation_id", "client_turn_id", "command_id", "prior_result_command_id",
    ] {
    if !valid_identifier(json_text(observation, key, "")) {
      raise reject(422, "invalid continuation identity: " + key)
    }
  }
  let command = json_text(observation, "command_id", "")
  if command == json_text(original, "command_id", "") ||
    command == json_text(observation, "prior_result_command_id", "") ||
    json_text(observation, "model", "").is_empty() {
    raise reject(
      422, "continuation requires a distinct native command and captured model",
    )
  }
  let input = json_field(observation, "input").unwrap_or(Json::null())
  if !(json_field(input, "path") is Some(String(_))) ||
    !(json_field(input, "sha256") is Some(String(_))) {
    raise reject(422, "continuation input reference must be text")
  }
  let path = json_text(input, "path", "")
  let digest = json_text(input, "sha256", "")
  if path.is_empty() ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.split("/").any(part => part == ".." || part == "." || part.is_empty()) ||
    digest.length() != 64 ||
    !digest.iter().all(c => c is ('0'..='9' | 'a'..='f' | 'A'..='F')) {
    raise reject(
      422, "continuation requires an immutable relative input path and SHA-256 digest",
    )
  }
  let state = json_text(observation, "state", "")
  if ![
      "queued", "running", "waiting_approval", "completed", "failed", "cancelled",
      "interrupted", "unknown", "runtime_unavailable",
    ].contains(state) {
    raise reject(422, "unsupported continuation state")
  }
  let receipt = json_field(observation, "receipt").unwrap_or(Json::null())
  if receipt is Object(_) {
    if json_text(receipt, "command_id", "") != command ||
      json_text(receipt, "session_id", "") !=
      json_text(original, "session_id", "") {
      raise reject(
        409, "continuation receipt belongs to another command or session",
      )
    }
  }
  if state == "completed" &&
    json_text(receipt, "status", "") != "runtime-completed" {
    raise reject(
      409, "completed continuation requires an exact native runtime completion receipt",
    )
  }
  for
    artifact in (match json_field(observation, "artifact_refs") {
      Some(Array(items)) => items
      _ => []
    }) {
    let attributed = json_text(artifact, "command_id", "")
    if !attributed.is_empty() && attributed != command {
      raise reject(409, "continuation artifact belongs to another command")
    }
  }
}

///|
fn plan_task_continuation_merge(
  current : Json,
  observation : Json,
) -> Json raise CompanyServiceError {
  if !json_equal(
      plan_task_continuation_identity(current),
      plan_task_continuation_identity(observation),
    ) {
    raise reject(409, "continuation lineage and input identity are immutable")
  }
  // Reuse exact-command terminal monotonicity and evidence union, with a local
  // run_id solely for that helper. The public sibling DTO never gains run_id.
  let current_fields = match current {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  let observed_fields = match observation {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  current_fields.set(
    "run_id",
    json_field(current, "original_run_id").unwrap_or(Json::null()),
  )
  observed_fields.set(
    "run_id",
    json_field(observation, "original_run_id").unwrap_or(Json::null()),
  )
  plan_task_continuation_public(
    plan_task_execution_merge(
      Json::object(current_fields),
      Json::object(observed_fields),
    ),
  )
}

///|
fn plan_task_completed_source(
  task : Json,
  source : Json,
) -> Json raise CompanyServiceError {
  let execution = json_field(task, "execution").unwrap_or(Json::null())
  if json_text(execution, "task_id", "").is_empty() ||
    json_text(execution, "task_id", "") != json_text(task, "task_id", "") ||
    !valid_identifier(json_text(execution, "run_id", "")) ||
    !valid_identifier(json_text(execution, "command_id", "")) {
    raise reject(409, "delivery source original identity must match this task")
  }
  if json_text(source, "type", "") == "human_revision" {
    let matches = plan_task_human_revisions(task).filter(item => {
      json_equal(plan_task_human_revision_source(item), source)
    })
    if matches.length() != 1 {
      raise reject(
        409, "delivery source must identify one attached human revision",
      )
    }
    plan_task_human_revision_validate(task, matches[0])
    return matches[0]
  }
  let value = if json_text(source, "type", "") == "original" {
    if !json_equal(source, plan_task_original_source(execution)) {
      raise reject(409, "delivery source does not match the original execution")
    }
    plan_task_execution_public(task)
  } else if json_text(source, "type", "") == "continuation" {
    let matches = plan_task_continuations(task).filter(item => {
      json_equal(plan_task_continuation_source(item), source)
    })
    if matches.length() != 1 {
      raise reject(
        409, "delivery source must identify one attached continuation",
      )
    }
    plan_task_continuation_validate(task, matches[0])
    plan_task_continuation_public(matches[0])
  } else {
    raise reject(
      422, "delivery source type must be original, continuation or human_revision",
    )
  }
  let receipt = json_field(value, "receipt").unwrap_or(Json::null())
  if json_text(value, "state", "") != "completed" ||
    json_text(receipt, "status", "") != "runtime-completed" ||
    json_text(receipt, "command_id", "") != json_text(value, "command_id", "") ||
    json_text(receipt, "session_id", "") != json_text(value, "session_id", "") {
    raise reject(
      409, "only an exact completed native result can be selected for delivery",
    )
  }
  value
}

///|
fn plan_task_continuation_request(
  task : Json,
  body : Json,
  actor : String,
) -> Json raise CompanyServiceError {
  if json_text(task, "created_by", "") != actor {
    raise reject(403, "only the task creator may change this local task")
  }
  let authority = plan_task_authority(
    body,
    actor,
    json_text(task, "project_id", ""),
    "project:task:update",
  )
  let observation = json_field(body, "continuation").unwrap_or(Json::null())
  let select = json_bool(body, "select_for_delivery", false)
  let human_revision = json_field(body, "human_revision").unwrap_or(
    Json::null(),
  )
  if !(human_revision is Null) {
    if !(observation is Null) ||
      !(json_field(body, "selected_delivery_source").unwrap_or(Json::null())
      is Null) {
      raise reject(422, "select only one exact delivery source")
    }
    plan_task_human_revision_validate(task, human_revision)
    return {
      "command_type": "continuation_observe",
      "task_id": json_text(task, "task_id", ""),
      "actor_id": actor,
      "authority": authority,
      "human_revision": human_revision,
      "source": plan_task_human_revision_source(human_revision),
      "select_for_delivery": select,
    }
  }
  let source = if observation is Object(_) {
    plan_task_continuation_validate(task, observation)
    plan_task_continuation_source(observation)
  } else {
    let source = json_field(body, "selected_delivery_source").unwrap_or(
      Json::null(),
    )
    if !select ||
      !json_equal(
        source,
        plan_task_original_source(
          json_field(task, "execution").unwrap_or(Json::null()),
        ),
      ) {
      raise reject(422, "original selection requires the exact original source")
    }
    source
  }
  {
    "command_type": "continuation_observe",
    "task_id": json_text(task, "task_id", ""),
    "actor_id": actor,
    "authority": authority,
    "continuation": if observation is Object(_) {
      plan_task_continuation_identity(observation)
    } else {
      Json::null()
    },
    "source": source,
    "select_for_delivery": select,
  }
}

///|
fn plan_task_continuation_apply(
  task : Json,
  body : Json,
) -> Json raise CompanyServiceError {
  if ["done", "deleted"].contains(json_text(task, "state", "")) {
    return task
  }
  let human_revision = json_field(body, "human_revision").unwrap_or(
    Json::null(),
  )
  if !(human_revision is Null) {
    if !(json_field(body, "continuation").unwrap_or(Json::null()) is Null) ||
      !(json_field(body, "selected_delivery_source").unwrap_or(Json::null())
      is Null) {
      raise reject(422, "select only one exact delivery source")
    }
    let next = plan_task_human_revision_apply(task, human_revision)
    if json_bool(body, "select_for_delivery", false) && next is Object(fields) {
      fields.set(
        "selected_delivery_source",
        plan_task_human_revision_source(human_revision),
      )
    }
    return next
  }
  let fields = match task {
    Object(values) => values.copy()
    _ => Map::new()
  }
  let observation = json_field(body, "continuation").unwrap_or(Json::null())
  let mut source = json_field(body, "selected_delivery_source").unwrap_or(
    Json::null(),
  )
  if observation is Object(_) {
    plan_task_continuation_validate(task, observation)
    let items = plan_task_continuations(task)
    let mut found = false
    for index in 0..<items.length() {
      let current = items[index]
      if json_text(current, "continuation_id", "") ==
        json_text(observation, "continuation_id", "") {
        items[index] = plan_task_continuation_merge(current, observation)
        found = true
      } else if json_text(current, "command_id", "") ==
        json_text(observation, "command_id", "") ||
        json_text(current, "client_turn_id", "") ==
        json_text(observation, "client_turn_id", "") {
        raise reject(
          409, "native command and client turn already belong to another continuation",
        )
      }
    }
    if !found {
      items.push(plan_task_continuation_public(observation))
    }
    fields.set("continuations", Json::array(items))
    source = plan_task_continuation_source(observation)
  }
  if json_bool(body, "select_for_delivery", false) {
    ignore(plan_task_completed_source(Json::object(fields), source))
    fields.set("selected_delivery_source", source)
  }
  Json::object(fields)
}

///|
fn plan_task_continuation_response(
  task : Json,
  replay : Bool,
  revision? : Int = 0,
) -> Json {
  let fields = match task {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields.set("__revision", Json::number(revision.to_double()))
  {
    "schema": "moonproj.task-continuations.v1",
    "task_id": json_text(task, "task_id", ""),
    "state": json_text(task, "state", ""),
    "acceptance": if json_text(task, "state", "") == "done" {
      "accepted"
    } else {
      "pending"
    },
    "inspection_only": json_text(task, "state", "") == "done",
    "continuations": plan_task_continuations_public(task),
    "human_revisions": plan_task_human_revisions(task),
    "selected_delivery_source": plan_task_delivery_source(task),
    "idempotent_replay": replay,
    "revision": revision,
    "task": project_plan_task_item(
      {
        record_id: json_text(task, "task_id", ""),
        source_id: "",
        payload: Json::object(fields),
      },
      true,
      [],
    ),
  }
}

///|
fn plan_task_continuation_operation_response(
  task : Json,
  replay : Bool,
  key : String,
  request : Json,
  applied : Bool,
  revision : Int,
) -> Json {
  let response = plan_task_continuation_response(task, replay, revision~)
  let fields = match response {
    Object(fields) => fields
    _ => Map::new()
  }
  fields.set("operation_idempotency_key", Json::string(key))
  fields.set(
    "operation_source",
    json_field(request, "source").unwrap_or(Json::null()),
  )
  fields.set("operation_applied", Json::boolean(applied))
  Json::object(fields)
}

///|
fn plan_task_continuation_atomic_sql(
  task_id : String,
  revision : Int,
  command_source : String,
  sql : String,
) -> String {
  let guarded = "IF coalesce((SELECT payload->>'state' FROM company_aggregate_projection WHERE aggregate_type='plan_task' AND aggregate_id=" +
    @postgres.sql_literal(task_id) +
    " ORDER BY revision DESC LIMIT 1), '') NOT IN ('done', 'deleted') THEN " +
    sql +
    " END IF;"
  plan_task_atomic_command_sql(task_id, revision, command_source, guarded)
}

///|
fn plan_task_continuation_sql(
  task_id : String,
  revision : Int,
  next : Json,
  request : Json,
  actor : String,
  key : String,
) -> String {
  let event = "plan_task:continuation:" + key
  let command_source = "moonproj:command:" + key
  let result = plan_task_continuation_operation_response(
    next,
    false,
    key,
    request,
    true,
    revision + 1,
  )
  let command : Json = {
    "kind": "company_command",
    "command_family": "plan_task",
    "command_type": "continuation_observe",
    "idempotency_key": key,
    "aggregate_type": "plan_task",
    "aggregate_id": task_id,
    "actor_id": actor,
    "request": request,
    "result": result,
  }
  let audit : Json = {
    "action": "plan.task.continuation",
    "task_id": task_id,
    "actor_id": actor,
    "event_id": event,
    "revision": revision + 1,
  }
  let sql = "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(command_source) +
    "); " +
    "INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('plan_task'," +
    @postgres.sql_literal(task_id) +
    "," +
    (revision + 1).to_string() +
    "," +
    @postgres.sql_literal(next.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(event) +
    "); " +
    "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(event + ":audit") +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event) +
    ");"
  plan_task_continuation_atomic_sql(task_id, revision, command_source, sql)
}

///|
async fn plan_task_continuation_command(
  task_id : String,
  body : Json,
  actor : String,
  key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (task, revision) = match plan_task_latest(task_id) {
    Some(value) => value
    None => raise reject(404, "native planning task not found")
  }
  if json_text(task, "state", "") == "deleted" {
    raise reject(409, "task is deleted")
  }
  let request = plan_task_continuation_request(task, body, actor)
  if json_text(task, "state", "") == "done" {
    return (
      200,
      plan_task_continuation_operation_response(
        task, false, key, request, false, revision,
      ),
    )
  }
  match existing_company_command(key) {
    Some(command) => {
      ignore(plan_task_applied_command(Some(command), request))
      return (
        200,
        plan_task_continuation_operation_response(
          task, true, key, request, true, revision,
        ),
      )
    }
    None => ()
  }
  let next = plan_task_continuation_apply(task, body)
  ignore(
    run_sql(
      plan_task_continuation_sql(task_id, revision, next, request, actor, key),
    ),
  )
  let (latest, latest_revision) = match plan_task_latest(task_id) {
    Some(value) => value
    None => raise reject(404, "task no longer exists")
  }
  let persisted = existing_company_command(key)
  if json_text(latest, "state", "") == "done" {
    let applied = match persisted {
      Some(command) => {
        ignore(plan_task_applied_command(Some(command), request))
        true
      }
      None => false
    }
    return (
      200,
      plan_task_continuation_operation_response(
        latest, false, key, request, applied, latest_revision,
      ),
    )
  }
  ignore(plan_task_applied_command(persisted, request))
  (
    200,
    plan_task_continuation_operation_response(
      latest, false, key, request, true, latest_revision,
    ),
  )
}

///|
fn plan_task_continuation_route(path : String) -> String? {
  let prefix = "/api/company/internal/plan/tasks/"
  if !path.has_prefix(prefix) {
    return None
  }
  let parts = path[prefix.length():].to_owned().split("/").to_array()
  if parts.length() == 3 &&
    valid_identifier(parts[0].to_owned()) &&
    parts[1] == "continuations" &&
    parts[2] == "observe" {
    Some(parts[0].to_owned())
  } else {
    None
  }
}
