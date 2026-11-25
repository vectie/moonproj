///|
test "signed dispatch actor is loaded rather than guessed as admin" {
  assert_eq(initial_model().dispatch_task_actor_id, "")
}

///|
#warnings("-alert_unstable")
test "submitted result reference remains visible for acceptance" {
  let model = {
    ..initial_model(),
    dispatch_task_id: "task-1",
    dispatch_task_stage: "submitted",
    dispatch_task_evidence_id: "https://example.test/output-1.txt",
    dispatch_task_report_id: "report-1",
  }
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => dispatch_durable_task_card(msg => emit(msg), model))
  let html = opc_render_cell(page)
  assert_true(html.contains("https://example.test/output-1.txt"))
}

///|
fn dispatch_test_run(state : String) -> DispatchRun {
  {
    run_id: "run-1",
    task_id: "task-1",
    session_id: "session-1",
    command_id: "command-1",
    workspace: "/workspace/book",
    state,
    summary: "Actual result",
    error: "",
    evidence_ids: ["/workspace/output.txt"],
    output_urls: ["https://example.test/output.txt"],
    artifacts: [],
    product_context: Unbound,
    book_guidance: Json::null(),
  }
}

///|
fn dispatch_test_snapshot(state : String) -> DispatchSnapshot {
  {
    offer_task: Json::null(),
    source_context: Json::null(),
    commitment: Json::null(),
    continuation_records: [],
    human_revision_records: [],
    delivery_source: Json::null(),
    report_records: [],
    revision: 0.0,
    accepted_report_id: "",
    accepted_delivery_source: Json::null(),
    product_id: "",
    report_product_id: "",
    task_id: "task-1",
    project_id: "native-project",
    title: "Task result",
    acceptance: "Check output",
    owner_id: "owner",
    begin_date: "2026-10-01",
    end_date: "2026-10-02",
    workspace: "/workspace/book",
    model: "",
    state: "in_progress",
    report_id: "",
    report_summary: "",
    evidence_ids: [],
    run: Some(dispatch_test_run(state)),
  }
}

///|
test "repeated Start waits for one canonical handoff receipt" {
  let model = {
    ..initial_model(),
    dispatch_task_id: "task-1",
    dispatch_task_stage: "pending",
  }
  let (_, pending) = update(_ => none, StartDispatchTask, model)
  assert_eq(pending.dispatch_task_pending_action, "start")
  assert_eq(pending.dispatch_task_stage, "pending")
  assert_eq(pending.dispatch_run, None)
  assert_false(dispatch_can_start(pending))
  let (_, repeated) = update(_ => none, StartDispatchTask, pending)
  assert_eq(repeated.dispatch_task_pending_action, "start")
  assert_eq(repeated.dispatch_run, None)
}

///|
test "unknown handoff reload and missing runtime retry preserve run identity" {
  let (_, restoring) = update(
    _ => none,
    RestoreDispatchTask("task-1"),
    initial_model(),
  )
  assert_eq(restoring.page, Dispatch)
  assert_eq(restoring.dispatch_task_pending_action, "load")
  for state in ["unknown", "runtime_unavailable", "interrupted"] {
    let snapshot = dispatch_test_snapshot(state)
    let (_, loaded) = update(
      _ => none,
      DispatchTaskLoaded("task-1", restoring.dispatch_task_selection, snapshot),
      restoring,
    )
    assert_eq(loaded.dispatch_task_stage, "in_progress")
    assert_true(dispatch_can_start(loaded))
    let (_, retrying) = update(_ => none, StartDispatchTask, loaded)
    assert_eq(retrying.dispatch_run, snapshot.run)
    assert_eq(retrying.dispatch_task_stage, "in_progress")
    assert_eq(retrying.dispatch_task_pending_action, "start")
  }
}

///|
test "late dispatch readback and failures cannot replace selected task" {
  let first = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-1",
    dispatch_task_selection: 2,
    dispatch_task_stage: "pending",
    dispatch_task_pending_action: "start",
    dispatch_task_open_id: "task-2",
  }
  let (_, second) = update(_ => none, OpenDispatchTask, first)
  assert_eq(second.dispatch_task_id, "task-2")
  assert_eq(second.dispatch_task_selection, 3)
  let (_, late) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 2, dispatch_test_snapshot("completed")),
    second,
  )
  assert_eq(late.dispatch_task_id, "task-2")
  assert_eq(late.dispatch_run, None)
  let (_, failed) = update(
    _ => none,
    DispatchTaskCommandFailed("task-1", 2, "原生执行", "late error"),
    late,
  )
  assert_eq(failed.dispatch_task_note, second.dispatch_task_note)
  assert_eq(failed.dispatch_task_pending_action, "load")
  let (_, old_report) = update(
    _ => none,
    DispatchTaskSubmitted("task-1", 2, "old-report", "event", "audit"),
    failed,
  )
  assert_eq(old_report.dispatch_task_report_id, "")
}

///|
test "late reads do not repopulate Next Task draft" {
  let accepted = {
    ..initial_model(),
    dispatch_task_id: "task-1",
    dispatch_task_selection: 7,
    dispatch_task_stage: "accepted",
    dispatch_run: Some(dispatch_test_run("completed")),
  }
  let (_, next) = update(_ => none, OpenDispatchTaskForm, accepted)
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 7, dispatch_test_snapshot("completed")),
    next,
  )
  assert_eq(stale.dispatch_task_id, "task-1")
  assert_eq(stale.dispatch_run, Some(dispatch_test_run("completed")))
  assert_eq(stale.dispatch_task_stage, "in_progress")
  assert_eq(stale.dispatch_drafts, next.dispatch_drafts)
  assert_true(stale.dispatch_task_form_open)
}

///|
test "waiting cancellation failure interruption and completion never imply acceptance" {
  for
    state in [
      "queued", "running", "waiting_approval", "failed", "cancelled", "completed",
    ] {
    let model = apply_dispatch_snapshot(
      initial_model(),
      dispatch_test_snapshot(state),
    )
    assert_eq(model.dispatch_task_stage, "in_progress")
    assert_false(dispatch_can_start(model))
    assert_eq(dispatch_can_submit(model), state == "completed")
    let (_, accepted) = update(_ => none, AcceptDispatchTask, model)
    assert_eq(accepted.dispatch_task_stage, "in_progress")
    assert_eq(accepted.dispatch_task_pending_action, "")
  }
}

///|
test "failed report submission retains completed execution and canonical in-progress task" {
  let model = apply_dispatch_snapshot(
    initial_model(),
    dispatch_test_snapshot("completed"),
  )
  let (_, pending) = update(_ => none, SubmitDispatchTask, model)
  assert_eq(pending.dispatch_task_pending_action, "submit")
  let (_, failed) = update(
    _ => none,
    DispatchTaskCommandFailed("task-1", 0, "提交验收", "report rejected"),
    pending,
  )
  assert_eq(failed.dispatch_task_stage, "in_progress")
  assert_eq(failed.dispatch_run, model.dispatch_run)
  assert_eq(failed.dispatch_task_report_id, "")
  assert_true(dispatch_can_submit(failed))
  let (_, restored) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 0, dispatch_test_snapshot("completed")),
    failed,
  )
  assert_eq(restored.dispatch_task_stage, "in_progress")
}

///|
test "canonical decoder rejects wrong task and wrong execution identity" {
  let base = "{\"data\":{\"task\":{\"taskGuid\":\"task-1\",\"status\":\"in_progress\",\"execution\":{\"run_id\":\"run-1\",\"task_id\":\"task-2\",\"session_id\":\"session-1\",\"command_id\":\"command-1\",\"state\":\"completed\"}},\"reports\":[]}}"
  assert_eq(dispatch_decode_snapshot(base, "task-1"), None)
  assert_eq(dispatch_decode_snapshot(base, "task-2"), None)
  assert_eq(
    dispatch_decode_snapshot("{\"error\":\"runtime missing\"}", "task-1"),
    None,
  )
  assert_eq(
    dispatch_response_error("{\"error\":\"runtime missing\"}"),
    "runtime missing",
  )
}

///|
test "reload restores submitted evidence and accepted state independently of execution" {
  let json = "{\"data\":{\"task\":{\"taskGuid\":\"task-1\",\"projGuid\":\"native-project\",\"taskName\":\"Result\",\"status\":\"in_progress\",\"execution_workspace\":\"/book\",\"execution\":null},\"reports\":[{\"reportGuid\":\"report-1\",\"summary\":\"Actual report\",\"evidence_ids\":[\"/book/output.txt\"]}]}}"
  let snapshot = dispatch_decode_snapshot(json, "task-1").unwrap()
  let loaded = apply_dispatch_snapshot(initial_model(), snapshot)
  assert_eq(loaded.dispatch_task_stage, "submitted")
  assert_eq(loaded.dispatch_task_report_id, "report-1")
  assert_eq(loaded.dispatch_task_report_summary, "Actual report")
  assert_eq(loaded.dispatch_task_evidence_id, "/book/output.txt")
  let accepted = apply_dispatch_snapshot(initial_model(), {
    ..snapshot,
    state: "done",
  })
  assert_eq(accepted.dispatch_task_stage, "accepted")
  assert_eq(accepted.dispatch_task_evidence_id, "/book/output.txt")
}

///|
#warnings("-alert_unstable")
test "real output links open while local paths remain literal references" {
  let model = apply_dispatch_snapshot(
    initial_model(),
    dispatch_test_snapshot("completed"),
  )
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    _,
    model,
  ) => dispatch_native_result(model))
  let html = opc_render_cell(page)
  assert_true(html.contains("href=\"https://example.test/output.txt\""))
  assert_true(html.contains("/workspace/output.txt"))
  assert_false(html.contains("href=\"/workspace/output.txt\""))
  assert_false(dispatch_safe_link("javascript:alert(1)"))
  assert_false(dispatch_safe_link("file:///workspace/output.txt"))
  assert_true(html.contains("Actual result"))
}

///|
test "native handoff request uses same task key and signed session actor across retry" {
  let model = {
    ..initial_model(),
    dispatch_task_id: "task-1",
    dispatch_task_project_id: "native-project",
    dispatch_task_actor_id: "desktop-owner",
  }
  let first = dispatch_start_body(model)
  let retry = dispatch_start_body({
    ..model,
    dispatch_run: Some(dispatch_test_run("runtime_unavailable")),
  })
  assert_eq(first, retry)
  assert_eq(
    dispatch_json_text(first, "idempotency_key"),
    "opc-dispatch-start-task-1",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(first, "authority"), "actor_id"),
    "desktop-owner",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(first, "authority"), "scope"),
    "project:native-project",
  )
  assert_eq(dispatch_json_field(first, "status"), Json::null())
}

///|
test "canonical newest-first reports preserve selected report evidence pairing" {
  let json = "{\"data\":{\"task\":{\"taskGuid\":\"task-1\",\"status\":\"in_progress\",\"remarks\":\"验收标准：Check output\"},\"reports\":[{\"reportGuid\":\"new-report\",\"summary\":\"New result\",\"evidence_ids\":[\"new-output\"]},{\"reportGuid\":\"old-report\",\"summary\":\"Old result\",\"evidence_ids\":[\"old-output\"]}]}}"
  let snapshot = dispatch_decode_snapshot(json, "task-1").unwrap()
  assert_eq(snapshot.report_id, "new-report")
  assert_eq(snapshot.report_summary, "New result")
  assert_eq(snapshot.evidence_ids, ["new-output"])
  assert_eq(snapshot.acceptance, "Check output")
}

///|
test "interrupted execution resumes the same run and remains pollable" {
  let model = apply_dispatch_snapshot(
    initial_model(),
    dispatch_test_snapshot("interrupted"),
  )
  assert_true(dispatch_run_pollable(model.dispatch_run))
  assert_eq(dispatch_resume_label(model), "Resume · 继续原生执行")
  assert_true(dispatch_can_start(model))
  let (_, resumed) = update(_ => none, StartDispatchTask, model)
  assert_eq(resumed.dispatch_run, model.dispatch_run)
  assert_eq(dispatch_start_body(resumed), dispatch_start_body(model))
  assert_false(dispatch_can_submit(resumed))
}

///|
test "artifact output paths remain bound to exact native command" {
  let json = "{\"data\":{\"task\":{\"taskGuid\":\"task-1\",\"status\":\"in_progress\",\"execution\":{\"run_id\":\"run-1\",\"task_id\":\"task-1\",\"session_id\":\"session-1\",\"command_id\":\"command-1\",\"state\":\"completed\",\"summary\":\"Real native answer\",\"artifact_refs\":[{\"path\":\"finding.txt\",\"command_id\":\"command-1\",\"evidence_id\":\"event-1\"},{\"path\":\"unrelated.txt\",\"command_id\":\"command-2\",\"evidence_id\":\"event-2\"}]}},\"reports\":[]}}"
  let snapshot = dispatch_decode_snapshot(json, "task-1").unwrap()
  let run = snapshot.run.unwrap()
  assert_eq(run.artifacts, [{ path: "finding.txt", evidence_id: "event-1", }])
  let model = apply_dispatch_snapshot(initial_model(), snapshot)
  assert_true(dispatch_report_summary(model).contains("Real native answer"))
  assert_true(dispatch_report_summary(model).contains("run-1"))
}

///|
#cfg(target="js")
extern "js" fn dispatch_test_window(url : String, saved : String) =
  #| (url, saved) => {
  #|   globalThis.__dispatchPriorWindow = globalThis.window;
  #|   const data = new Map(saved ? [["moonproj.dispatch.task", saved]] : []);
  #|   globalThis.window = {
  #|     location: { href: url },
  #|     localStorage: { getItem: key => data.get(key) || null, setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key) },
  #|     history: { replaceState: (_, __, next) => { globalThis.window.location.href = String(next); } }
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn dispatch_test_window_cleanup() =
  #| () => {
  #|   if (globalThis.__dispatchPriorWindow === undefined) delete globalThis.window;
  #|   else globalThis.window = globalThis.__dispatchPriorWindow;
  #|   delete globalThis.__dispatchPriorWindow;
  #| }

///|
test "reload helper prioritizes exact URL and preserves legacy exact task recovery" {
  // A minimal window stub verifies FFI storage behavior, not a browser walkthrough.
  dispatch_test_window("https://example.test/?task=url-task", "older-task")
  assert_eq(dispatch_saved_task(), "url-task")
  dispatch_store_task("task-1", false)
  assert_eq(dispatch_saved_task(), "task-1")
  dispatch_store_task("", false)
  assert_eq(dispatch_saved_task(), "")
  dispatch_test_window_cleanup()
  dispatch_test_window("https://example.test/", "stored-task")
  assert_eq(dispatch_saved_task(), "stored-task")
  dispatch_test_window_cleanup()
}

///|
#warnings("-alert_unstable")
test "completed result renders exact artifact paths and manual settling refresh guidance" {
  let run = {
    ..dispatch_test_run("completed"),
    artifacts: [{ path: "Results/Review.MD", evidence_id: "event-write", }],
  }
  let model = apply_dispatch_snapshot(initial_model(), {
    ..dispatch_test_snapshot("completed"),
    run: Some(run),
  })
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    _,
    model,
  ) => dispatch_native_result(model))
  let html = opc_render_cell(page)
  assert_true(html.contains("Results/Review.MD"))
  assert_true(html.contains("event-write"))
  assert_true(html.contains("/workspace/book"))
  assert_true(html.contains("刷新状态"))
  assert_false(html.contains("href=\"Results/Review.MD\""))
}
