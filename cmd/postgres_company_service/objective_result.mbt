///|
// An objective accepts a specific integrated delivery, not the fact that a
// collection of task records has been closed. Reuse a saved task report; the
// founder's objective acceptance is the decision, not a second review gate.
fn objective_result_binding(
  objective : Json,
  selection : Json,
  work : Json,
  report : Json,
) -> Json raise CompanyServiceError {
  let task_id = json_text(selection, "task_id", "")
  let report_id = json_text(selection, "report_id", "")
  if json_text(objective, "task_type", "") != "key_node" ||
    task_id.is_empty() ||
    report_id.is_empty() ||
    json_text(work, "task_id", "") != task_id ||
    json_text(work, "project_id", "") != json_text(objective, "project_id", "") ||
    json_text(work, "parent_task_id", "") != json_text(objective, "task_id", "") ||
    json_text(report, "report_id", "") != report_id ||
    json_text(report, "task_id", "") != task_id ||
    json_text(report, "project_id", "") !=
    json_text(objective, "project_id", "") {
    raise reject(
      422, "choose a saved report from this objective's delegated work",
    )
  }
  {
    "task_id": task_id,
    "report_id": report_id,
    "delivery_source": json_field(report, "delivery_source").unwrap_or(
      Json::null(),
    ),
  }
}
