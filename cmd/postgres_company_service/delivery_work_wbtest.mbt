///|
test "delivery permissions are explicit and captured workspace scope is stable" {
  let task : Json = {
    "task_id": "T",
    "execution_workspace": "/selected",
    "delivery_mode": "coordinated",
    "delivery_limits": "draft only",
  }
  assert_eq(plan_task_execution_workspace(task), "/selected")
  assert_eq(
    plan_task_execution_workspace({ "execution_workspace": "/legacy" }),
    "/legacy",
  )
  assert_eq(
    plan_task_delivery_changes(Json::null(), { "delivery_mode": "coordinated" }),
    { "delivery_mode": "coordinated" },
  )
  let invalid : Array[Json] = [
    { "delivery_mode": "autonomous-company" },
    { "delivery_mode": true },
  ]
  for body in invalid {
    try plan_task_delivery_changes(task, body) catch {
      _ => ()
    } noraise {
      _ => assert_true(false)
    }
  }
  let running = continuation_test_changed(task, "execution", {})
  try
    plan_task_delivery_changes(running, { "delivery_limits": "wider" })
  catch {
    _ => ()
  } noraise {
    _ => assert_true(false)
  }
}

///|
test "runtime tree control does not manufacture a terminal execution outcome" {
  let current : Json = {
    "task_id": "T",
    "run_id": "R",
    "session_id": "S",
    "command_id": "C",
    "state": "completed",
    "summary": "Original output",
  }
  let request = continuation_test_changed(
    current,
    "control_state",
    Json::string("stopping"),
  )
  let stopping = plan_task_execution_merge(current, request)
  assert_eq(json_text(stopping, "state", ""), "completed")
  assert_eq(json_text(stopping, "control_state", ""), "stopping")
  let stopped = plan_task_execution_merge(
    stopping,
    continuation_test_changed(request, "control_state", Json::string("stopped")),
  )
  assert_eq(json_text(stopped, "summary", ""), "Original output")
  assert_eq(json_text(stopped, "control_state", ""), "stopped")
  let stale = continuation_test_changed(
    request,
    "state",
    Json::string("running"),
  )
  let raced = plan_task_execution_merge(current, stale)
  assert_eq(json_text(raced, "state", ""), "completed")
  assert_eq(json_text(raced, "summary", ""), "Original output")
  assert_eq(json_text(raced, "control_state", ""), "stopping")
}
