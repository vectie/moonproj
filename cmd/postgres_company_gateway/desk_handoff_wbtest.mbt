///|
test "desk handoff configuration is explicit and CLI has precedence" {
  assert_eq(desk_handoff_config(None, None), "")
  assert_eq(
    desk_handoff_config(None, Some("https://desk.example")),
    "https://desk.example",
  )
  assert_eq(
    desk_handoff_config(
      Some("http://localhost:52731"),
      Some("https://desk.example"),
    ),
    "http://localhost:52731",
  )
  assert_eq(desk_handoff_config(Some(""), Some("https://desk.example")), "")
  assert_eq(
    desk_handoff_origin("http://localhost:52731/"),
    Some("http://localhost:52731"),
  )
  assert_eq(
    desk_handoff_origin("https://desk.example"),
    Some("https://desk.example"),
  )
  assert_eq(
    desk_handoff_origin("http://[::1]:52731"),
    Some("http://[::1]:52731"),
  )
}

///|
test "desk handoff never invents or truncates an unsupported destination" {
  for
    value in [
      "", "moondesk://open", "javascript:alert(1)", "https://", "https://user:secret@desk.example",
      "https://desk.example/subpath", "https://desk.example/?token=x", "https://desk.example#fragment",
      "https://desk.example:0", "https://desk.example:65536", "https://desk.example:",
      "https://desk.example\\evil", "https://desk.example\n.evil", "https://bad%2fhost",
    ] {
    assert_eq(desk_handoff_origin(value), None, msg=value)
  }
}

///|
fn desk_handoff_test_task() -> Json {
  {
    "taskGuid": "T",
    "status": "in_progress",
    "execution_workspace": "/new/current/workspace",
    "execution_model": "current/model",
    "product_id": "current-product",
    "execution": {
      "task_id": "T",
      "run_id": "R",
      "session_id": "S",
      "command_id": "C0",
      "workspace": "/captured/书 with spaces",
      "model": "moongate/captured",
      "request_body": "private serialized original requirements",
      "product_context": {
        "product_id": "captured-product",
        "context_path": ".moonsuite/captured.md",
        "sha256": "digest",
        "coverage": "partial",
        "text": "private PRD",
      },
    },
  }
}

///|
test "desk handoff projects captured execution without mutable settings or private bodies" {
  let descriptor = desk_handoff_projection(
    desk_handoff_test_task(),
    "https://desk.example",
  )
  assert_eq(native_text(descriptor, "state"), "ready")
  let work = native_field(descriptor, "work")
  assert_eq(native_text(work, "book_root"), "/captured/书 with spaces")
  assert_eq(native_text(work, "model"), "moongate/captured")
  assert_eq(native_text(work, "original_command_id"), "C0")
  assert_eq(
    native_text(native_field(descriptor, "product_context"), "product_id"),
    "captured-product",
  )
  assert_false(descriptor.stringify().contains("private"))
  assert_false(descriptor.stringify().contains("current"))
  assert_eq(native_text(descriptor, "mode"), "inspect")
  assert_false(native_bool(descriptor, "task_accepted"))
}

///|
test "desk handoff keeps exact work for configuration recovery and accepted inspection" {
  let task = desk_handoff_test_task()
  guard task is Object(fields) else { abort("task") }
  fields.set("status", "done")
  let pending = desk_handoff_projection(task, "")
  assert_eq(native_text(pending, "state"), "destination_unconfigured")
  assert_eq(native_field(pending, "desk_origin"), Json::null())
  assert_eq(
    native_text(native_field(pending, "work"), "original_command_id"),
    "C0",
  )
  assert_true(native_bool(pending, "task_accepted"))
  assert_eq(native_text(pending, "mode"), "inspect")
  assert_eq(
    native_text(
      desk_handoff_projection(task, "https://desk.example/subpath"),
      "state",
    ),
    "destination_invalid",
  )
}

///|
test "desk handoff supports legacy captures and distinguishes absent or incomplete execution" {
  let task = desk_handoff_test_task()
  guard native_field(task, "execution") is Object(execution) else {
    abort("execution")
  }
  execution.remove("product_context")
  let descriptor = desk_handoff_projection(task, "https://desk.example")
  assert_eq(native_text(descriptor, "state"), "ready")
  assert_eq(native_field(descriptor, "product_context"), Json::null())
  execution.remove("command_id")
  assert_eq(
    native_text(desk_handoff_projection(task, "https://desk.example"), "state"),
    "execution_unavailable",
  )
  let absent = desk_handoff_projection(
    { "taskGuid": "T", "execution": null },
    "https://desk.example",
  )
  assert_eq(native_text(absent, "state"), "no_execution")
  assert_eq(native_field(absent, "work"), Json::null())
}

///|
test "desk handoff route is exact and does not replace native detail route" {
  assert_eq(
    desk_handoff_task_id("/api/company/tasks/T/desk-handoff"),
    Some("T"),
  )
  assert_eq(desk_handoff_task_id("/api/company/tasks/T"), None)
  assert_eq(
    desk_handoff_task_id("/api/company/tasks/T/extra/desk-handoff"),
    None,
  )
  assert_eq(native_detail_id("/api/company/tasks/T/desk-handoff"), None)
  assert_eq(native_detail_id("/api/company/tasks/T"), Some("T"))
}
