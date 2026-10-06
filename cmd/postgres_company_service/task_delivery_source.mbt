///|
/// A report pins one explicitly selected command. Request replay uses the saved
/// snapshot, even if today's task selects a later continuation or is accepted.
fn delivery_task_source_metadata(
  body : Json,
  task_or_report : Json,
) -> Json raise CompanyServiceError {
  let supplied = json_field(body, "delivery_source").unwrap_or(Json::null())
  if json_text(task_or_report, "command_type", "") == "report" {
    let stored = json_field(task_or_report, "delivery_source").unwrap_or(
      Json::null(),
    )
    let implicit_original = json_bool(
      task_or_report, "delivery_source_implicit", false,
    )
    if !(implicit_original && supplied is Null) && !json_equal(supplied, stored) {
      raise reject(409, "report replay must preserve the exact delivery source")
    }
    let fields : Map[String, Json] = {}
    for
      key in [
        "delivery_source", "delivery_source_snapshot", "delivery_source_revision",
        "delivery_source_implicit",
      ] {
      match json_field(task_or_report, key) {
        Some(value) => fields.set(key, value)
        None => ()
      }
    }
    return Json::object(fields)
  }
  let execution = json_field(task_or_report, "execution").unwrap_or(
    Json::null(),
  )
  let selected = plan_task_delivery_source(task_or_report)
  // The general/manual report API is independent of native delivery. Without
  // an explicit source or selection, retain its existing progress-report
  // behavior and do not invent completed-command attribution.
  if supplied is Null && selected is Null {
    return Json::object({})
  }
  if !(execution is Object(_)) {
    if !(supplied is Null) {
      raise reject(409, "task has no native delivery source")
    }
    return Json::object({})
  }
  if ["done", "deleted"].contains(json_text(task_or_report, "state", "")) {
    raise reject(409, "accepted or deleted native work is inspection-only")
  }
  let source = if selected is Object(_) {
    if !json_equal(supplied, selected) {
      raise reject(
        409, "report source must equal the explicitly selected delivery source",
      )
    }
    selected
  } else {
    if !json_equal(supplied, plan_task_original_source(execution)) {
      raise reject(
        409, "continuation must be explicitly selected before reporting",
      )
    }
    supplied
  }
  let snapshot = plan_task_completed_source(task_or_report, source)
  {
    "delivery_source": source,
    "delivery_source_snapshot": snapshot,
    "delivery_source_revision": json_int(
      task_or_report, "__delivery_task_revision", 0,
    ),
    "delivery_source_implicit": false,
  }
}

///|
/// Validate the observed task revision and report identity under the same lock
/// as source selection/Accept. A lost race never records a successful command.
fn delivery_task_source_atomic_sql(
  request : Json,
  command_source : String,
  command_sql : String,
) -> String {
  let guarded = "IF NOT EXISTS (SELECT 1 FROM company_aggregate_projection WHERE aggregate_type='task_report' AND aggregate_id=" +
    @postgres.sql_literal(json_text(request, "report_id", "")) +
    ") THEN " +
    command_sql +
    " END IF;"
  plan_task_continuation_atomic_sql(
    json_text(request, "task_id", ""),
    json_int(request, "delivery_source_revision", 0),
    command_source,
    guarded,
  )
}

///|
fn plan_task_acceptance_needs_binding(task : Json, body : Json) -> Bool {
  plan_task_delivery_source(task) is Object(_) ||
  json_field(body, "report_id") is Some(_) ||
  json_field(body, "delivery_source") is Some(_)
}

///|
/// This is the existing human Accept with exact report attribution, not a new
/// runtime/evidence gate. Only the new selected-source flow requires binding.
fn plan_task_acceptance_binding(
  task : Json,
  body : Json,
  report : Json,
) -> Json raise CompanyServiceError {
  if !plan_task_acceptance_needs_binding(task, body) {
    return Json::object({})
  }
  let report_id = json_text(body, "report_id", "")
  let source = json_field(body, "delivery_source").unwrap_or(Json::null())
  let selected = plan_task_delivery_source(task)
  let intended = if selected is Object(_) {
    selected
  } else {
    plan_task_original_source(
      json_field(task, "execution").unwrap_or(Json::null()),
    )
  }
  if !valid_identifier(report_id) ||
    !json_equal(source, intended) ||
    json_text(report, "report_id", "") != report_id ||
    json_text(report, "task_id", "") != json_text(task, "task_id", "") ||
    json_text(report, "project_id", "") != json_text(task, "project_id", "") ||
    !json_equal(
      json_field(report, "delivery_source").unwrap_or(Json::null()),
      source,
    ) {
    raise reject(
      409, "Accept requires the displayed report for this exact selected source; reload current work",
    )
  }
  { "accepted_report_id": report_id, "accepted_delivery_source": source }
}

///|
fn plan_task_acceptance_atomic_sql(
  task_id : String,
  revision : Int,
  command_source : String,
  request : Json,
  command_sql : String,
) -> String {
  let changes = json_field(request, "changes").unwrap_or(Json::null())
  let report_id = json_text(changes, "accepted_report_id", "")
  if report_id.is_empty() {
    return plan_task_atomic_command_sql(
      task_id, revision, command_source, command_sql,
    )
  }
  let source = json_field(changes, "accepted_delivery_source").unwrap_or(
    Json::null(),
  )
  let guarded = "IF EXISTS (SELECT 1 FROM (SELECT payload FROM company_aggregate_projection WHERE aggregate_type='task_report' AND aggregate_id=" +
    @postgres.sql_literal(report_id) +
    " ORDER BY revision DESC LIMIT 1) report WHERE payload->>'task_id'=" +
    @postgres.sql_literal(task_id) +
    " AND payload->>'report_id'=" +
    @postgres.sql_literal(report_id) +
    " AND payload->'project_id'=(SELECT payload->'project_id' FROM company_aggregate_projection WHERE aggregate_type='plan_task' AND aggregate_id=" +
    @postgres.sql_literal(task_id) +
    " ORDER BY revision DESC LIMIT 1) AND payload->'delivery_source'=" +
    @postgres.sql_literal(source.stringify()) +
    "::jsonb) THEN " +
    command_sql +
    " END IF;"
  plan_task_continuation_atomic_sql(task_id, revision, command_source, guarded)
}

///|
async fn plan_task_acceptance_error_response(
  task_id : String?,
  body : Json,
  error : CompanyServiceError,
) -> (Int, Json) {
  let response = service_error_response(error)
  if response.0 != 409 || json_text(body, "status", "") != "done" {
    return response
  }
  match task_id {
    Some(id) => {
      let current = plan_task_latest(id) catch { _ => None }
      match current {
        Some((task, revision)) if plan_task_acceptance_needs_binding(task, body) => {
          let public = project_plan_task_item(
            { record_id: id, source_id: "", payload: task, },
            true,
            [],
          )
          let fields = match response.1 {
            Object(fields) => fields.copy()
            _ => Map::new()
          }
          fields.set("task", public)
          fields.set("revision", Json::number(revision.to_double()))
          fields.set("acceptance_conflict", Json::boolean(true))
          fields.set(
            "selected_delivery_source",
            plan_task_delivery_source(task),
          )
          (409, Json::object(fields))
        }
        _ => response
      }
    }
    None => response
  }
}
