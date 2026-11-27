///|
fn handoff_proj_fixture(
  state~ : String = "ready",
  task~ : String = "task-1",
  origin~ : String = "https://desk.example:8443",
) -> String {
  (
    {
      "schema": "moonproj.desk-handoff.v1",
      "state": state,
      "desk_origin": origin,
      "mode": "inspect",
      "task_accepted": true,
      "work": {
        "task_id": task,
        "run_id": "run & 1",
        "session_id": "会话/1",
        "original_command_id": "command?0",
        "book_root": "/书 with spaces/",
        "model": "captured-model",
      },
      "product_context": Json::null(),
    } : Json).stringify()
}

///|
test "handoff URL uses only explicit destination and escaped captured identity" {
  let url = dispatch_desk_handoff_url(
    handoff_proj_fixture(),
    "task-1",
    "https://proj.example/dispatch?task=task-1&keep=1#result",
  ).unwrap()
  assert_true(url.has_prefix("https://desk.example:8443/?"))
  assert_true(url.contains("session=%E4%BC%9A%E8%AF%9D%2F1"))
  assert_true(url.contains("command=command%3F0"))
  assert_true(url.contains("book_root=%2F%E4%B9%A6+with+spaces%2F"))
  assert_true(url.contains("work_mode=inspect"))
  assert_true(url.contains("keep%3D1%23result"))
  assert_false(url.contains("workspace="))
}

///|
test "handoff works for accepted legacy execution without product context or current model" {
  assert_true(
    dispatch_desk_handoff_url(
      handoff_proj_fixture(),
      "task-1",
      "https://proj.example/?task=task-1",
    )
    is Ok(_),
  )
}

///|
test "unconfigured invalid empty and upstream handoffs remain retryable" {
  for
    state in [
      "destination_unconfigured", "destination_invalid", "no_execution", "execution_unavailable",
      "upstream_unavailable",
    ] {
    assert_true(
      dispatch_desk_handoff_url(
        handoff_proj_fixture(state~),
        "task-1",
        "https://proj.example/?task=task-1",
      )
      is Err(_),
    )
  }
  assert_true(
    dispatch_desk_handoff_url(
      "{}", "task-1", "https://proj.example/?task=task-1",
    )
    is Err(_),
  )
}

///|
test "handoff rejects mismatched task dangerous destinations and wrong return task" {
  assert_true(
    dispatch_desk_handoff_url(
      handoff_proj_fixture(task="other"),
      "task-1",
      "https://proj.example/?task=task-1",
    )
    is Err(_),
  )
  for
    origin in [
      "", "javascript:alert(1)", "https://desk.example/base", "https://user:pass@desk.example",
      "https://desk.example/?other=1",
    ] {
    assert_true(
      dispatch_desk_handoff_url(
        handoff_proj_fixture(origin~),
        "task-1",
        "https://proj.example/?task=task-1",
      )
      is Err(_),
    )
  }
  assert_true(
    dispatch_desk_handoff_url(
      handoff_proj_fixture(),
      "task-1",
      "https://proj.example/?task=other",
    )
    is Err(_),
  )
}

///|
test "task return URL preserves unrelated navigation and replaces exact task" {
  assert_eq(
    dispatch_handoff_task_url(
      "https://proj.example/custom?task=old&x=%2F#run", "T &/书",
    ),
    "https://proj.example/custom?task=T+%26%2F%E4%B9%A6&x=%2F#run",
  )
}

///|
test "handoff ignores late callbacks after task selection navigation or a newer request" {
  let state : DispatchDeskHandoff = {
    output: Json::null(),
    follow_up: false,
    task_id: "task-1",
    selection: 2,
    request: 3,
    pending: true,
    error: "",
  }
  let model = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-1",
    dispatch_task_selection: 2,
    dispatch_desk_handoff: state,
  }
  let stale = DeskHandoffAction(Loaded("task-1", 2, 2, "", "", Err("late")))
  let (_, next) = update(_ => none, stale, model)
  assert_true(next.dispatch_desk_handoff.pending)
  let (_, other) = update(
    _ => none,
    DeskHandoffAction(Loaded("task-1", 1, 3, "", "", Err("late"))),
    model,
  )
  assert_eq(other.dispatch_desk_handoff.error, "")
  let (_, away) = update(_ => none, Navigate(Overview), model)
  let (_, back) = update(_ => none, Navigate(Dispatch), away)
  let (_, ignored) = update(
    _ => none,
    DeskHandoffAction(Loaded("task-1", 2, 3, "", "", Err("late"))),
    back,
  )
  assert_eq(ignored.dispatch_desk_handoff.error, "")
}

///|
test "failed handoff clears loading and next click creates a fresh request" {
  let state : DispatchDeskHandoff = {
    output: Json::null(),
    follow_up: false,
    task_id: "task-1",
    selection: 2,
    request: 3,
    pending: true,
    error: "",
  }
  let model = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-1",
    dispatch_task_selection: 2,
    dispatch_desk_handoff: state,
  }
  let (_, next) = update(
    _ => none,
    DeskHandoffAction(Loaded("task-1", 2, 3, "", "", Err("offline"))),
    model,
  )
  assert_false(next.dispatch_desk_handoff.pending)
  assert_true(next.dispatch_desk_handoff.error.contains("offline"))
  let (_, retry) = update(_ => none, DeskHandoffAction(Open), next)
  assert_eq(retry.dispatch_desk_handoff.request, 4)
  assert_true(retry.dispatch_desk_handoff.pending)
}

///|
extern "js" fn handoff_test_navigation(
  newer : Bool,
  callback : () -> Unit,
) -> String =
  #| (newer, callback) => {
  #|   const previous = globalThis.location; let assigned = '';
  #|   globalThis.location = {href: newer ? 'https://proj.example/?task=newer' : 'https://proj.example/?task=task-1', assign: url => {assigned = url;}};
  #|   try { callback(); return assigned; } finally { if (previous === undefined) delete globalThis.location; else globalThis.location = previous; }
  #| }

///|
test "late navigation effect cannot overwrite a newer browser URL" {
  let run = fn() {
    dispatch_navigate_desk(
      "https://proj.example/?task=task-1", "https://desk.example/?session=S",
    )
  }
  assert_eq(
    handoff_test_navigation(false, run),
    "https://desk.example/?session=S",
  )
  assert_eq(handoff_test_navigation(true, run), "")
}
