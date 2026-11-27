///|
/// Execution is task metadata. It does not confer delivery acceptance.
fn plan_task_execution_public(task : Json) -> Json {
  match json_field(task, "execution") {
    Some(Object(fields)) => {
      let public_fields : Map[String, Json] = Map([])
      for
        key in [
          "run_id", "task_id", "session_id", "command_id", "state", "summary", "error",
          "evidence_ids", "output_urls", "receipt", "workspace", "model", "artifact_refs",
          "dispatched", "control_state", "control_error", "control_receipt", "workers",
          "revision_request", "worker_error",
        ] {
        match fields.get(key) {
          Some(value) => public_fields.set(key, value)
          None => ()
        }
      }
      public_fields.set(
        "product_context",
        plan_task_product_context_public(Json::object(fields)),
      )
      if fields.get("book_guidance") is Some(selection) {
        public_fields.set(
          "book_guidance",
          @task_evidence.guidance_summary(
            selection,
            sha256=json_text(Json::object(fields), "book_guidance_sha256", ""),
          ),
        )
      }
      public_fields.set(
        "acceptance",
        Json::string(
          if json_text(task, "state", "") == "done" {
            "accepted"
          } else {
            "pending"
          },
        ),
      )
      Json::object(public_fields)
    }
    _ => Json::null()
  }
}

///|
fn plan_task_execution_terminal(state : String) -> Bool {
  ["completed", "failed", "cancelled"].contains(state)
}

///|
fn plan_task_execution_merge(
  current : Json,
  observation : Json,
) -> Json raise CompanyServiceError {
  for key in ["run_id", "task_id", "session_id", "command_id"] {
    if json_text(current, key, "").is_empty() ||
      json_text(current, key, "") != json_text(observation, key, "") {
      raise reject(
        409, "native observation does not belong to this exact task execution",
      )
    }
  }
  let state = json_text(observation, "state", "unknown")
  if ![
      "queued", "running", "waiting_approval", "completed", "failed", "cancelled",
      "interrupted", "unknown", "runtime_unavailable",
    ].contains(state) {
    raise reject(422, "unsupported native execution state")
  }
  // A late admission/poll response cannot erase the settled command result.
  if plan_task_execution_terminal(json_text(current, "state", "")) &&
    json_text(current, "state", "") != state {
    let fields = match current {
      Object(fields) => fields.copy()
      _ => Map([])
    }
    for
      key in [
        "control_state", "control_error", "control_receipt", "revision_request",
      ] {
      if json_field(observation, key) is Some(value) {
        fields[key] = value
      }
    }
    return Json::object(fields)
  }
  if state == "queued" &&
    ["running", "waiting_approval", "interrupted"].contains(
      json_text(current, "state", ""),
    ) {
    return current
  }
  let fields = match current {
    Object(values) => values.copy()
    _ => Map([])
  }
  for
    key in [
      "state", "error", "receipt", "dispatched", "control_state", "control_error",
      "control_receipt", "workers", "revision_request", "worker_error",
    ] {
    match json_field(observation, key) {
      Some(value) => fields.set(key, value)
      None => ()
    }
  }
  match json_field(observation, "product_context_artifact") {
    Some(Object(artifact)) if json_field(current, "product_context")
      is Some(Object(_)) => {
      let state = json_text(Json::object(artifact), "state", "")
      if ["pending", "available", "missing", "conflict", "unavailable"].contains(
          state,
        ) {
        fields.set(
          "product_context_artifact",
          Json::object({
            "state": Json::string(state),
            "error": Json::string(
              json_text(Json::object(artifact), "error", ""),
            ),
          }),
        )
      }
    }
    _ => ()
  }
  if !json_text(observation, "summary", "").is_empty() {
    fields.set("summary", Json::string(json_text(observation, "summary", "")))
  }
  // Overlapping completed polls may return out of order. Evidence only grows.
  for key in ["evidence_ids", "output_urls", "artifact_refs"] {
    let combined : Array[Json] = match json_field(current, key) {
      Some(Array(items)) => items.copy()
      _ => []
    }
    match json_field(observation, key) {
      Some(Array(items)) =>
        for item in items {
          if !combined.any(existing => json_equal(existing, item)) {
            combined.push(item)
          }
        }
      _ => ()
    }
    fields.set(key, Json::array(combined))
  }
  Json::object(fields)
}

///|
fn plan_task_execution_route(path : String) -> (String, String)? {
  let prefix = "/api/company/internal/plan/tasks/"
  if !path.has_prefix(prefix) {
    return None
  }
  let pieces = path[prefix.length():].to_owned().split("/").to_array()
  if pieces.length() == 3 &&
    valid_identifier(pieces[0].to_owned()) &&
    pieces[1] == "execution" &&
    ["reserve", "observe", "control"].contains(pieces[2].to_owned()) {
    Some((pieces[0].to_owned(), pieces[2].to_owned()))
  } else {
    None
  }
}

///|
async fn plan_task_execution_command(
  task_id : String,
  action : String,
  body : Json,
  actor : String,
) -> (Int32, Json) raise CompanyServiceError {
  let (task, revision) = match plan_task_latest(task_id) {
    Some(value) => value
    None => raise reject(404, "native planning task not found")
  }
  if json_text(task, "state", "") == "deleted" {
    raise reject(409, "task is deleted")
  }
  let existing = json_field(task, "execution").unwrap_or(Json::null())
  if action == "control" {
    if json_text(task, "created_by", "") != actor {
      raise reject(403, "only the task creator may control this delivery")
    }
    ignore(
      plan_task_authority(
        body,
        actor,
        json_text(task, "project_id", ""),
        "project:task:update",
      ),
    )
    let requested = json_field(body, "execution").unwrap_or(Json::null())
    if json_text(requested, "control_state", "") == "revising" &&
      json_text(existing, "control_state", "") == "revising" &&
      json_field(requested, "revision_request") !=
      json_field(existing, "revision_request") {
      raise reject(
        409, "recover the existing delivery revision before replacing its intent",
      )
    }
    if !["stopping", "resuming", "revising"].contains(
        json_text(requested, "control_state", ""),
      ) {
      raise reject(422, "explicit stop or resume intent is required")
    }
  }
  if action == "reserve" {
    if json_text(task, "created_by", "") != actor {
      raise reject(403, "only the task creator may dispatch this local task")
    }
    ignore(
      plan_task_authority(
        body,
        actor,
        json_text(task, "project_id", ""),
        "project:task:update",
      ),
    )
    if existing is Object(_) {
      return (200, Json::object({ "execution": existing }))
    }
    if json_text(task, "state", "") == "done" {
      raise reject(409, "accepted task cannot start a new native execution")
    }
    let execution = json_field(body, "execution").unwrap_or(Json::null())
    if json_int(body, "source_revision", -1) != revision {
      raise reject(409, "task changed; reload before dispatch")
    }
    let snapshot = json_text(execution, "request_body", "")
    let native = @json.parse(snapshot) catch {
      _ => raise reject(422, "native request snapshot is invalid")
    }
    let packet = json_field(native, "packet").unwrap_or(Json::null())
    if json_text(execution, "task_id", "") != task_id ||
      json_text(execution, "session_id", "") !=
      json_text(native, "session_id", "") ||
      json_text(execution, "command_id", "") !=
      json_text(packet, "command_id", "") ||
      json_text(execution, "workspace", "") !=
      plan_task_execution_workspace(task) ||
      json_text(native, "book_root", "") != plan_task_execution_workspace(task) ||
      json_text(native, "model", "") != json_text(execution, "model", "") ||
      (
        !json_text(task, "execution_model", "").is_empty() &&
        json_text(native, "model", "") != json_text(task, "execution_model", "")
      ) ||
      json_text(execution, "state", "") != "queued" {
      raise reject(422, "native request snapshot must match the persisted task")
    }
    for key in ["run_id", "session_id", "command_id"] {
      if !valid_identifier(json_text(execution, key, "")) {
        raise reject(422, "invalid native execution identity")
      }
    }
    // Select the latest row *under* the lock. Concurrent Starts reserve once.
    let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; " +
      "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) " +
      "SELECT 'plan_task', aggregate_id, revision + 1, payload || jsonb_build_object('execution', " +
      @postgres.sql_literal(execution.stringify()) +
      "::jsonb), " +
      @postgres.sql_literal(
        "plan_task:dispatch:" + json_text(execution, "run_id", ""),
      ) +
      " FROM (SELECT * FROM company_aggregate_projection WHERE aggregate_type='plan_task' AND aggregate_id=" +
      @postgres.sql_literal(task_id) +
      " ORDER BY revision DESC LIMIT 1) latest " +
      "WHERE NOT (payload ? 'execution') AND revision=" +
      revision.to_string() +
      "; COMMIT;"
    ignore(run_sql(sql))
  } else {
    if !(existing is Object(_)) {
      raise reject(409, "task has no reserved native execution")
    }
    let observation = json_field(body, "execution").unwrap_or(Json::null())
    let merged = plan_task_execution_merge(existing, observation)
    if merged.stringify() != existing.stringify() {
      let control_only = json_field(observation, "control_state") is Some(_)
      let control_patch : Map[String, Json] = Map([])
      for
        key in [
          "control_state", "control_error", "control_receipt", "revision_request",
        ] {
        if json_field(observation, key) is Some(value) {
          control_patch[key] = value
        }
      }
      let control_guard = (if action == "control" {
          if json_text(observation, "control_state", "") == "revising" {
            " AND (coalesce(payload->'execution'->>'control_state','') <> 'revising' OR payload->'execution'->'revision_request'=" +
            @postgres.sql_literal(
              json_field(observation, "revision_request")
              .unwrap_or(Json::null())
              .stringify(),
            ) +
            "::jsonb)"
          } else {
            ""
          }
        } else {
          " AND payload->'execution'->>'control_state' IN (" +
          (if json_text(observation, "control_state", "") == "stopped" {
            "'stopping','stopped'"
          } else if json_text(observation, "control_state", "") == "active" {
            "'revising'"
          } else {
            @postgres.sql_literal(json_text(observation, "control_state", ""))
          }) +
          ")"
        }) +
        (if action != "control" &&
          json_field(observation, "revision_request") is Some(request) &&
          ["active", "revising"].contains(
            json_text(observation, "control_state", ""),
          ) {
          " AND payload->'execution'->'revision_request'=" +
          @postgres.sql_literal(request.stringify()) +
          "::jsonb"
        } else {
          ""
        })
      let state = json_text(merged, "state", "unknown")
      let task_state = if ["queued", "runtime_unavailable", "unknown"].contains(
          state,
        ) &&
        json_field(merged, "dispatched") != Some(Json::boolean(true)) {
        json_text(task, "state", "pending")
      } else if json_text(task, "state", "pending") == "pending" {
        "in_progress"
      } else {
        json_text(task, "state", "pending")
      }
      let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; " +
        "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) " +
        "SELECT 'plan_task', aggregate_id, revision + 1, payload || jsonb_build_object('execution', " +
        (if control_only {
          "coalesce(payload->'execution','{}'::jsonb) || " +
          @postgres.sql_literal(Json::object(control_patch).stringify())
        } else {
          @postgres.sql_literal(merged.stringify())
        }) +
        "::jsonb, 'state', " +
        (if control_only {
          "payload->>'state'"
        } else {
          @postgres.sql_literal(task_state)
        }) +
        "), " +
        @postgres.sql_literal(
          "plan_task:execution:" +
          json_text(merged, "run_id", "") +
          ":" +
          state +
          ":",
        ) +
        " || (revision + 1)::text" +
        " FROM (SELECT * FROM company_aggregate_projection WHERE aggregate_type='plan_task' AND aggregate_id=" +
        @postgres.sql_literal(task_id) +
        " ORDER BY revision DESC LIMIT 1) latest WHERE " +
        (if control_only {
          "payload->'execution'->>'run_id'=" +
          @postgres.sql_literal(json_text(existing, "run_id", "")) +
          control_guard
        } else {
          "revision=" + revision.to_string()
        }) +
        "; COMMIT;"
      ignore(run_sql(sql))
    }
  }
  let latest = match plan_task_latest(task_id) {
    Some((value, _)) => value
    None => raise reject(404, "task no longer exists")
  }
  match json_field(latest, "execution") {
    Some(execution) => (200, Json::object({ "execution": execution }))
    None => raise reject(409, "task changed; reload before dispatch")
  }
}

///|
/// The payload and revision were validated together. A later reservation or
/// native observation must force a retry rather than be overwritten.
fn plan_task_atomic_command_sql(
  task_id : String,
  expected_revision : Int32,
  command_source : String,
  command_sql : String,
) -> String {
  let body = "BEGIN IF coalesce((SELECT max(revision) FROM company_aggregate_projection WHERE aggregate_type = 'plan_task' AND aggregate_id = " +
    @postgres.sql_literal(task_id) +
    "), 0) = " +
    expected_revision.to_string() +
    " AND NOT EXISTS (SELECT 1 FROM company_record WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    ") THEN " +
    command_sql +
    " END IF; END;"
  "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; LOCK TABLE company_record IN SHARE ROW EXCLUSIVE MODE; DO " +
  @postgres.sql_literal(body) +
  "; COMMIT;"
}

///|
fn plan_task_applied_command(
  persisted : Json?,
  request : Json,
) -> Json raise CompanyServiceError {
  match persisted {
    Some(value) if json_equal(
        json_field(value, "request").unwrap_or(Json::null()),
        request,
      ) => value
    Some(_) =>
      raise reject(409, "Idempotency-Key was already used for another request")
    None =>
      raise reject(409, "task changed during this command; reload and retry")
  }
}

///|
/// Deliberate summary projection: the captured source text is private metadata.
fn plan_task_product_context_public(execution : Json) -> Json {
  match json_field(execution, "product_context") {
    Some(Object(context)) => {
      let summary : Map[String, Json] = Map([])
      for
        key in [
          "schema", "product_id", "product_name", "coverage", "issues", "context_path",
          "sha256", "size_bytes",
        ] {
        match context.get(key) {
          Some(value) => summary.set(key, value)
          None => ()
        }
      }
      let prd = match context.get("prd") {
        Some(Object(fields)) => {
          let result : Map[String, Json] = Map([])
          for
            key in [
              "document_id", "source_sha256", "source_size_bytes", "version", "coverage",
              "text_sha256", "text_size_bytes", "extraction_version", "limitations",
              "text_path",
            ] {
            match fields.get(key) {
              Some(value) => result.set(key, value)
              None => ()
            }
          }
          Json::object(result)
        }
        _ => Json::null()
      }
      summary.set("prd", prd)
      let artifact = json_field(execution, "product_context_artifact").unwrap_or(
        Json::null(),
      )
      summary.set(
        "artifact_state",
        Json::string(json_text(artifact, "state", "pending")),
      )
      summary.set(
        "artifact_error",
        Json::string(json_text(artifact, "error", "")),
      )
      Json::object(summary)
    }
    _ => Json::null()
  }
}
