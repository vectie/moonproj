///|
/// Native source-backed workflow-definition reads.
///
/// Definitions, steps, and assignee metadata are imported observations. An
/// empty process-instance or step-action table is reported as empty; this
/// boundary never approves, assigns, or synchronizes a workflow.
fn workflow_definition_tables() -> Array[String] {
  [
    "wf_process_def", "wf_step_def", "wf_step_assignee", "sys_user", "wf_process_instance",
    "wf_step_action",
  ]
}

///|
fn workflow_definition_coverage(
  rows : Map[String, Array[SourceRow]],
) -> Map[String, Int] {
  let coverage : Map[String, Int] = {}
  for table in workflow_definition_tables() {
    coverage.set(table, rows.get_or_default(table, []).length())
  }
  coverage
}

///|
fn workflow_definition_missing(coverage : Map[String, Int]) -> Array[Json] {
  let missing : Array[String] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(table)
    }
  }
  missing.sort_by(fn(left, right) { left.compare(right) })
  missing.map(fn(value) { Json::string(value) })
}

///|
fn workflow_definition_user_value(
  users : Map[String, Json],
  user_id : String,
  key : String,
) -> String {
  match users.get(user_id) {
    Some(value) => json_text(value, key, "")
    None => ""
  }
}

///|
fn workflow_definition_rows(
  rows : Map[String, Array[SourceRow]],
  process_key : String?,
) -> Array[Json] {
  let users : Map[String, Json] = {}
  for row in rows.get_or_default("sys_user", []) {
    users.set(json_text(row.payload, "user_id", row.record_id), row.payload)
  }
  let assignees_by_step : Map[String, Array[Json]] = {}
  for row in rows.get_or_default("wf_step_assignee", []) {
    let payload = row.payload
    let step_guid = json_text(payload, "step_guid", "")
    if !step_guid.is_empty() {
      let user_guid = json_text(payload, "assignee_user_guid", "")
      let values = assignees_by_step.get_or_default(step_guid, [])
      values.push(
        Json::object({
          "assignee_guid": Json::string(
            json_text(payload, "assignee_guid", row.record_id),
          ),
          "user_guid": Json::string(user_guid),
          "user_code": Json::string(
            workflow_definition_user_value(users, user_guid, "user_code"),
          ),
          "user_name": Json::string(
            workflow_definition_user_value(users, user_guid, "emp_name"),
          ),
          "weight": Json::number(json_number(payload, "weight", 1.0)),
          "source_kind": Json::string("imported"),
        }),
      )
      assignees_by_step.set(step_guid, values)
    }
  }
  let steps_by_process : Map[String, Array[Json]] = {}
  for row in rows.get_or_default("wf_step_def", []) {
    let payload = row.payload
    let process_guid = json_text(payload, "process_guid", "")
    if !process_guid.is_empty() {
      let step_guid = json_text(payload, "step_guid", row.record_id)
      let values = steps_by_process.get_or_default(process_guid, [])
      values.push(
        Json::object({
          "step_guid": Json::string(step_guid),
          "step_key": Json::string(json_text(payload, "step_key", "")),
          "step_order": Json::number(json_number(payload, "step_order", 0.0)),
          "step_type": Json::number(json_number(payload, "step_type", 0.0)),
          "step_name": Json::string(json_text(payload, "step_name", "")),
          "threshold": Json::number(json_number(payload, "threshold", 1.0)),
          "remind_days": json_field(payload, "remind_days").unwrap_or(
            Json::null(),
          ),
          "warn_days": json_field(payload, "warn_days").unwrap_or(Json::null()),
          "assignees": Json::array(
            assignees_by_step.get_or_default(step_guid, []),
          ),
          "source_kind": Json::string("imported"),
        }),
      )
      steps_by_process.set(process_guid, values)
    }
  }
  let items : Array[Json] = []
  for row in rows.get_or_default("wf_process_def", []) {
    let payload = row.payload
    let key = json_text(payload, "process_key", "")
    match process_key {
      Some(filter) if key != filter => continue
      _ => ()
    }
    let process_guid = json_text(payload, "process_guid", row.record_id)
    let steps = steps_by_process.get_or_default(process_guid, [])
    steps.sort_by(fn(left, right) {
      json_number(left, "step_order", 0.0).compare(
        json_number(right, "step_order", 0.0),
      )
    })
    items.push(
      Json::object({
        "process_guid": Json::string(process_guid),
        "process_key": Json::string(key),
        "process_name": Json::string(json_text(payload, "process_name", key)),
        "biz_type": Json::string(json_text(payload, "biz_type", "")),
        "is_active": Json::boolean(json_bool(payload, "is_active", false)),
        "is_mandatory": Json::boolean(json_bool(payload, "is_mandatory", false)),
        "step_count": Json::number(steps.length().to_double()),
        "steps": Json::array(steps),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  items.sort_by(fn(left, right) {
    let key_compare = json_text(left, "process_key", "").compare(
      json_text(right, "process_key", ""),
    )
    if key_compare == 0 {
      json_text(left, "process_guid", "").compare(
        json_text(right, "process_guid", ""),
      )
    } else {
      key_compare
    }
  })
  items
}

///|
async fn workflow_process_defs_response(
  process_key : String?,
) -> Json raise CompanyServiceError {
  match process_key {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid process_key")
    _ => ()
  }
  let rows : Map[String, Array[SourceRow]] = {}
  for table in workflow_definition_tables() {
    rows.set(table, raw_source_rows(table, 5000))
  }
  let coverage = workflow_definition_coverage(rows)
  let missing = workflow_definition_missing(coverage)
  let items = workflow_definition_rows(rows, process_key)
  Json::object({
    "items": Json::array(items),
    "source_kind": Json::string("imported"),
    "source_coverage": report_coverage(coverage),
    "missing_source_tables": Json::array(missing),
    "missing_or_empty_source_tables": Json::array(missing),
    "instances_available": Json::number(
      coverage.get_or_default("wf_process_instance", 0).to_double(),
    ),
    "actions_available": Json::number(
      coverage.get_or_default("wf_step_action", 0).to_double(),
    ),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
async fn workflow_process_preview_response(
  process_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let response = workflow_process_defs_response(Some(process_key))
  let items = json_field(response, "items").unwrap_or(Json::array([]))
  match items {
    Array(values) if !values.is_empty() => {
      let item = values[0]
      (
        200,
        Json::object({
          "process_key": json_field(item, "process_key").unwrap_or(
            Json::string(""),
          ),
          "process_name": json_field(item, "process_name").unwrap_or(
            Json::string(""),
          ),
          "biz_type": json_field(item, "biz_type").unwrap_or(Json::string("")),
          "steps": json_field(item, "steps").unwrap_or(Json::array([])),
          "source_kind": Json::string("imported"),
          "instances_available": json_field(response, "instances_available").unwrap_or(
            Json::number(0),
          ),
          "actions_available": json_field(response, "actions_available").unwrap_or(
            Json::number(0),
          ),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(false),
        }),
      )
    }
    _ =>
      (
        404,
        Json::object({
          "error": Json::string("workflow process definition not found"),
        }),
      )
  }
}
