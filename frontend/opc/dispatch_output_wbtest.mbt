///|
fn output_proj_model() -> Model {
  let model = continuation_proj_model()
  {
    ..model,
    dispatch_run: Some({
      ..model.dispatch_run.unwrap(),
      artifacts: [{ path: "results/report 书.md", evidence_id: "E0", }],
    }),
  }
}

///|
test "output original and continuation open retain exact source without selecting or submitting" {
  let model = output_proj_model()
  for
    (command, path, evidence) in [
      ("command-1", "results/report 书.md", "E0"),
      ("C1", "C1.txt", "file-C1"),
    ] {
    let (_, next) = dispatch_desk_handoff_update(
      _ => none,
      Output(command, path, evidence),
      model,
    )
    assert_true(next.dispatch_desk_handoff.pending)
    assert_false(next.dispatch_desk_handoff.follow_up)
    assert_eq(
      dispatch_json_text(next.dispatch_desk_handoff.output, "command_id"),
      command,
    )
    assert_eq(
      next.dispatch_continuation.selected,
      model.dispatch_continuation.selected,
    )
    assert_eq(next.dispatch_task_report_id, model.dispatch_task_report_id)
    assert_eq(next.dispatch_run, model.dispatch_run)
    let (_, repeated) = dispatch_desk_handoff_update(
      _ => none,
      Output(command, path, evidence),
      next,
    )
    assert_eq(
      repeated.dispatch_desk_handoff.request,
      next.dispatch_desk_handoff.request,
    )
  }
}

///|
test "output refuses wrong command evidence task and escaped path" {
  let model = output_proj_model()
  for
    (command, path, evidence) in [
      ("C2", "C1.txt", "file-C1"),
      ("C1", "C1.txt", "E0"),
      ("command-1", "../report.md", "E0"),
      ("command-1", "/report.md", "E0"),
      ("command-1", "a\\b", "E0"),
      ("command-1", "a//b", "E0"),
    ] {
    let (_, next) = dispatch_desk_handoff_update(
      _ => none,
      Output(command, path, evidence),
      model,
    )
    assert_false(next.dispatch_desk_handoff.pending)
  }
  assert_false(
    dispatch_output_is_current({ ..model, dispatch_task_id: "other", }, {
      "command_id": "command-1",
      "path": "results/report 书.md",
      "evidence_id": "E0",
    }),
  )
}

///|
test "output navigation hints encode exact reference and preserve original and return identity" {
  let base = dispatch_desk_handoff_url(
    handoff_proj_fixture(),
    "task-1",
    "https://proj.example/?task=task-1",
  ).unwrap()
  let url = dispatch_desk_output_url(base, {
    "command_id": "C1",
    "path": "reports/a & 书.md",
    "evidence_id": "E?1",
  })
  assert_true(url.contains("command=command%3F0"))
  assert_true(url.contains("work_output_command=C1"))
  assert_true(url.contains("work_output_path=reports%2Fa+%26+%E4%B9%A6.md"))
  assert_true(url.contains("work_output_evidence=E%3F1"))
  assert_true(url.contains("work_mode=inspect"))
  assert_true(url.contains("return_to="))
}

///|
test "output pending response cannot navigate after another task or page selection" {
  let (_, pending) = dispatch_desk_handoff_update(
    _ => none,
    Output("C1", "C1.txt", "file-C1"),
    output_proj_model(),
  )
  let state = pending.dispatch_desk_handoff
  let (_, stale) = dispatch_desk_handoff_update(
    _ => none,
    Loaded(state.task_id, state.selection, state.request, "", "", Err("late")),
    { ..pending, dispatch_task_selection: state.selection + 1, },
  )
  assert_eq(stale.dispatch_desk_handoff.error, "")
  let (_, away) = dispatch_desk_handoff_update(
    _ => none,
    Loaded(state.task_id, state.selection, state.request, "", "", Err("late")),
    { ..pending, page: Products, },
  )
  assert_eq(away.dispatch_desk_handoff.error, "")
}

///|
#warnings("-alert_unstable")
test "output buttons render for original and precise continuation" {
  let model = output_proj_model()
  let original = @rabbita.render_to_string(
    @rabbita.static_cell(dispatch_native_result(model)),
  )
  let continuation = @rabbita.render_to_string(
    @rabbita.static_cell(dispatch_continuation_view(_ => none, model)),
  )
  assert_true(original.contains("在 MoonDesk 打开此输出"))
  assert_true(continuation.contains("在 MoonDesk 打开此输出"))
  assert_true(original.contains("当前文件"))
}
