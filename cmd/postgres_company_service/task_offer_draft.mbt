///|
// A proposal is an optional planning document on an ordinary company task.
// It grants no execution, contracting, customer-acceptance or cash authority.
fn plan_task_offer_normalize(value : Json) -> Json raise CompanyServiceError {
  @task_evidence.normalize_offer_draft(value) catch {
    @task_evidence.InvalidOfferDraft(message) => raise reject(422, message)
  }
}

///|
fn plan_task_offer_on_create(
  request : Json,
  body : Json,
) -> Json raise CompanyServiceError {
  if json_field(body, "offer_base_revision") is Some(_) {
    raise reject(
      422, "offer_base_revision is only valid for an existing proposal task",
    )
  }
  match json_field(body, "offer_draft") {
    None => request
    Some(value) => {
      if json_text(request, "task_type", "task") != "task" {
        raise reject(422, "proposal drafts require an ordinary planning task")
      }
      let normalized = plan_task_offer_normalize(value)
      let fields = match request {
        Object(fields) => fields.copy()
        _ => Map([])
      }
      fields["offer_draft"] = normalized
      Json::object(fields)
    }
  }
}

///|
fn plan_task_offer_eligible(task : Json) -> Bool {
  if json_text(task, "state", "") != "pending" ||
    json_text(task, "task_type", "task") != "task" ||
    json_text(task, "source_kind", "") != "command" {
    return false
  }
  for
    key in ["execution", "selected_delivery_source", "accepted_delivery_source"] {
    if !(json_field(task, key).unwrap_or(Json::null()) is Null) {
      return false
    }
  }
  for key in ["continuations", "human_revisions"] {
    match json_field(task, key) {
      None | Some(Null) => ()
      Some(Array(items)) if items.is_empty() => ()
      _ => return false
    }
  }
  json_text(task, "accepted_report_id", "").is_empty()
}

///|
fn plan_task_offer_request(
  task_id : String,
  project_id : String,
  body : Json,
  actor : String,
) -> Json raise CompanyServiceError {
  let fields = match body {
    Object(fields) => fields
    _ => raise reject(422, "proposal save must be an object")
  }
  for key, _ in fields {
    if !["idempotency_key", "authority", "offer_base_revision", "offer_draft"].contains(
        key,
      ) {
      raise reject(422, "proposal save cannot change task fields: " + key)
    }
  }
  let revision = match json_field(body, "offer_base_revision") {
    Some(Number(value, ..)) if value > 0.0 &&
      value <= 2147483646.0 &&
      value == value.to_int().to_double() => value.to_int()
    _ =>
      raise reject(
        422, "offer_base_revision must be the positive task revision you read",
      )
  }
  let offer = plan_task_offer_normalize(
    json_field(body, "offer_draft").unwrap_or(Json::null()),
  )
  let authority = plan_task_authority(
    body, actor, project_id, "project:task:update",
  )
  {
    "command_type": "update",
    "task_id": task_id,
    "project_id": project_id,
    "actor_id": actor,
    "offer_base_revision": revision,
    "changes": { "offer_draft": offer },
    "authority": authority,
  }
}

///|
fn plan_task_offer_replay(
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
  let request = plan_task_offer_request(
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
fn plan_task_offer_apply(
  current : Json,
  request : Json,
  actor : String,
  event_id : String,
) -> Json {
  let fields = match current {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  let changes = json_field(request, "changes").unwrap_or(Json::null())
  fields["offer_draft"] = json_field(changes, "offer_draft").unwrap_or(
    Json::null(),
  )
  fields["event_id"] = event_id.to_json()
  fields["updated_by"] = actor.to_json()
  fields["source_kind"] = "command".to_json()
  Json::object(fields)
}

///|
fn plan_task_offer_payloads(
  task_id : String,
  current : Json,
  revision : Int,
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
    "action": "plan.task.update",
    "aggregate_type": "plan_task",
    "aggregate_id": task_id,
    "actor_id": actor,
    "event_id": event_id,
    "state": "pending",
    "revision": revision + 1,
  }
  (command, audit, plan_task_offer_apply(current, request, actor, event_id))
}

///|
fn plan_task_offer_sql(
  task_id : String,
  current : Json,
  revision : Int,
  request : Json,
  actor : String,
  key : String,
) -> String {
  let (command, audit, next) = plan_task_offer_payloads(
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
// Shared by proposal content and its reply-only observation update. Both use
// the established pending/unexecuted planning boundary and one task revision.
fn plan_task_offer_guarded_sql(
  task_id : String,
  revision : Int,
  request : Json,
  actor : String,
  key : String,
  command_sql : String,
) -> String {
  let source = "moonproj:command:" + key
  // Eligibility is checked under the same lock as revision and all inserts.
  // A report or native reservation cannot race this planning-only save.
  let guarded = "IF EXISTS (SELECT 1 FROM (SELECT payload FROM company_aggregate_projection WHERE aggregate_type='plan_task' AND aggregate_id=" +
    @postgres.sql_literal(task_id) +
    " ORDER BY revision DESC LIMIT 1) current WHERE payload->>'state'='pending' AND coalesce(payload->>'task_type','task')='task' AND payload->>'source_kind'='command'" +
    " AND payload->>'created_by'=" +
    @postgres.sql_literal(actor) +
    " AND payload->>'project_id'=" +
    @postgres.sql_literal(json_text(request, "project_id", "")) +
    " AND coalesce(payload->'execution','null'::jsonb)='null'::jsonb" +
    " AND coalesce(payload->'selected_delivery_source','null'::jsonb)='null'::jsonb" +
    " AND coalesce(payload->'accepted_delivery_source','null'::jsonb)='null'::jsonb" +
    " AND coalesce(payload->'continuations','null'::jsonb) IN ('null'::jsonb,'[]'::jsonb)" +
    " AND coalesce(payload->'human_revisions','null'::jsonb) IN ('null'::jsonb,'[]'::jsonb)" +
    " AND coalesce(payload->>'accepted_report_id','')='')" +
    " AND NOT EXISTS (SELECT 1 FROM company_aggregate_projection WHERE aggregate_type='task_report' AND payload->>'task_id'=" +
    @postgres.sql_literal(task_id) +
    ") THEN " +
    command_sql +
    " END IF;"
  plan_task_atomic_command_sql(task_id, revision, source, guarded)
}

///|
async fn plan_task_offer_update_command(
  aggregate_id : String?,
  body : Json,
  actor : String,
  key : String,
) -> (Int, Json) raise CompanyServiceError {
  let id = match aggregate_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "task_id is required")
  }
  match json_field(body, "idempotency_key") {
    None => ()
    Some(String(value)) if value == key => ()
    _ => raise reject(422, "proposal body and header idempotency keys differ")
  }
  // An exact signed retry resolves its retained receipt before consulting the
  // later task state, creator, or revision. It can never replay another actor.
  match existing_company_command(key) {
    Some(existing) =>
      return (200, plan_task_offer_replay(existing, id, body, actor))
    None => ()
  }
  let (current, revision) = match plan_task_latest(id) {
    Some(value) => value
    None => raise reject(404, "proposal task does not exist")
  }
  if json_text(current, "created_by", "") != actor {
    raise reject(403, "only the task creator may edit this proposal")
  }
  if !plan_task_offer_eligible(current) {
    raise reject(
      409, "proposal editing requires a pending unexecuted task; prepare a separate planning item",
    )
  }
  let request = plan_task_offer_request(
    id,
    json_text(current, "project_id", ""),
    body,
    actor,
  )
  if json_int(request, "offer_base_revision", 0) != revision {
    raise reject(
      409, "proposal base revision changed; keep your draft and read the current task",
    )
  }
  let sql = plan_task_offer_sql(id, current, revision, request, actor, key)
  // On a lost SQL response, reread only this exact operation before deciding
  // whether anything was saved. No replacement key or second mutation follows.
  let _ = run_sql(sql) catch {
    error => {
      let recovered = existing_company_command(key) catch { _ => None }
      match recovered {
        Some(existing) =>
          return (200, plan_task_offer_replay(existing, id, body, actor))
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

///|
fn plan_task_offer_public(
  item : Json,
  payload : Json,
  include_offer : Bool,
) -> Json {
  let fields = match item {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  // The editor needs the existing creator identity even before a first offer.
  // Company lists do not gain this identity or the full proposal body.
  if include_offer {
    fields["created_by"] = match json_field(payload, "created_by") {
      Some(String(actor)) => actor.to_json()
      _ => Json::null()
    }
  }
  let offer = match json_field(payload, "offer_draft") {
    None => return if include_offer { Json::object(fields) } else { item }
    Some(value) => value
  }
  fields["offer_summary"] = @task_evidence.offer_draft_summary(offer) catch {
    _ =>
      {
        "schema": "moonproj.offer-draft-summary.v1",
        "state": "invalid",
        "demand_state": "unproven",
      }
  }
  if include_offer {
    fields["offer_draft"] = offer
  }
  Json::object(fields)
}
