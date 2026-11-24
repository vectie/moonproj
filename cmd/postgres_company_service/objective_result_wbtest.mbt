///|
test "objective pins accepted integrated delivery without completing other work" {
  let objective : Json = {
    "task_id": "G",
    "project_id": "P",
    "task_type": "key_node",
  }
  let work : Json = {
    "task_id": "W",
    "project_id": "P",
    "parent_task_id": "G",
    "state": "done",
    "accepted_report_id": "R",
    "accepted_delivery_source": { "type": "native", "command_id": "C" },
  }
  let selection : Json = { "task_id": "W", "report_id": "R" }
  let report : Json = {
    "report_id": "R",
    "task_id": "W",
    "project_id": "P",
    "delivery_source": { "type": "native", "command_id": "C" },
  }
  let result = objective_result_binding(objective, selection, work, report)
  assert_eq(json_text(result, "task_id", ""), "W")
  assert_eq(json_text(result, "report_id", ""), "R")
  assert_eq(
    json_field(result, "delivery_source"),
    json_field(report, "delivery_source"),
  )
  for
    invalid in [
      continuation_test_changed(work, "parent_task_id", Json::string("other")),
      continuation_test_changed(work, "project_id", Json::string("other")),
      continuation_test_changed(work, "task_id", Json::string("other")),
    ] {
    try objective_result_binding(objective, selection, invalid, report) catch {
      _ => ()
    } noraise {
      _ =>
        assert_true(
          false,
          msg="unrelated or unaccepted work is not objective success",
        )
    }
  }
  try
    objective_result_binding(
      objective,
      { "task_id": "W", "report_id": "" },
      work,
      report,
    )
  catch {
    _ => ()
  } noraise {
    _ => assert_true(false, msg="closed records alone are not accepted reports")
  }
  let open_work = continuation_test_changed(
    work,
    "state",
    Json::string("in_progress"),
  )
  assert_eq(
    objective_result_binding(objective, selection, open_work, report),
    result,
  )
  for field in ["report_id", "task_id", "project_id"] {
    try
      objective_result_binding(
        objective,
        selection,
        work,
        continuation_test_changed(report, field, Json::string("other")),
      )
    catch {
      _ => ()
    } noraise {
      _ =>
        assert_true(
          false,
          msg="report must belong to this exact delegated work",
        )
    }
  }
}
