///|
fn outcome_test_source() -> Json {
  let task : Json = {
    "task_id": "task-fixture",
    "title": "Synthetic unit task <&>",
  }
  let report : Json = {
    "report": { "task_id": "task-fixture", "summary": "Synthetic unit report" },
  }
  let mut source = lesson_receipt_test_payload()
  for
    (key, snapshot) in [
      ("task", task.stringify()),
      ("report", report.stringify()),
    ] {
    let reference = lesson_receipt_test_set(
      dispatch_json_field(source, key),
      "record_digest",
      Json::string("sha256:" + outcome_test_hash(snapshot)),
    )
    source = lesson_receipt_test_set(source, key, reference)
    source = lesson_receipt_test_set(
      source,
      key + "_snapshot",
      Json::string(snapshot),
    )
  }
  source
}

///|
fn outcome_test_source_model() -> Model {
  let model = lesson_receipt_test_model()
  {
    ..model,
    dispatch_lesson_handoff: {
      ..model.dispatch_lesson_handoff,
      payload: Some(outcome_test_source()),
    },
  }
}

///|
test "outcome actor switch and logout clear prior notes prepared bytes and pending handoff" {
  let model = outcome_test_model()
  let source = outcome_test_source()
  let draft = dispatch_outcome_draft(model, source)
  let old = dispatch_outcome_store(
    {
      ..model,
      dispatch_task_actor_id: "actor-a",
      dispatch_outcome_sequence: 17,
      dispatch_lesson_handoff: {
        ..model.dispatch_lesson_handoff,
        pending: true,
      },
    },
    { ..draft, prepared: Some(outcome_test_response(draft)), pending: true, },
  )
  for actor in ["actor-b", ""] {
    let (_, reset) = update(_ => none, DispatchSessionLoaded(actor), old)
    assert_true(reset.dispatch_outcome_drafts.is_empty())
    assert_eq(reset.dispatch_outcome_sequence, 18)
    assert_false(reset.dispatch_lesson_handoff.pending)
    assert_true(reset.dispatch_lesson_handoff.payload is None)
    let reopened = {
      ..reset,
      page: Dispatch,
      dispatch_task_id: "task-fixture",
      dispatch_task_report_id: "report-fixture",
      dispatch_task_stage: "accepted",
      dispatch_lesson_handoff: {
        ..empty_dispatch_lesson_handoff(),
        task_id: "task-fixture",
        selection: reset.dispatch_task_selection,
        payload: Some(source),
      },
    }
    let html = opc_render_cell(
      @rabbita.static_cell(dispatch_lesson_handoff_view(_ => none, reopened)),
    )
    assert_false(html.contains(draft.outcome_summary))
    assert_false(html.contains("下载完整结果"))
    assert_true(dispatch_outcome_draft(reopened, source).prepared is None)
  }
  let (_, same_actor) = update(_ => none, DispatchSessionLoaded("actor-a"), old)
  assert_eq(same_actor.dispatch_outcome_sequence, 17)
  assert_eq(
    dispatch_outcome_draft(same_actor, source).prepared,
    dispatch_outcome_draft(old, source).prepared,
  )
  let (_, initial_login) = update(_ => none, DispatchSessionLoaded("actor-b"), {
    ..old,
    dispatch_task_actor_id: "",
  })
  assert_true(initial_login.dispatch_outcome_drafts.is_empty())
  assert_true(initial_login.dispatch_lesson_handoff.payload is None)
  assert_true(
    initial_login.dispatch_lesson_handoff.request >
    old.dispatch_lesson_handoff.request,
  )
  assert_eq(initial_login.dispatch_outcome_sequence, 18)
}

///|
test "outcome owner route captures actual mounted task page without credentials unrelated query or fragment" {
  let actual = dispatch_outcome_owner_route(
    "https://person:secret@proj.example.test/apps/proj/?session=private&task=old&page=products#private",
    "task:actual",
  )
  assert_eq(
    actual, "https://proj.example.test/apps/proj/?page=dispatch&task=task%3Aactual",
  )
  for page in ["", "file:///apps/proj", "javascript:alert(1)", "about:blank"] {
    assert_eq(dispatch_outcome_owner_route(page, "task-fixture"), "")
  }
  let models = [outcome_test_source_model()]
  outcome_serialized_page(
    "https://proj.example.test/apps/proj/?session=private#fragment",
    () => {
      models[0] = outcome_test_edit(
        models[0],
        Edit("summary", "Actual observation"),
      )
    },
  )
  let frozen = dispatch_outcome_draft(models[0], outcome_test_source()).owner_route
  assert_eq(
    frozen, "https://proj.example.test/apps/proj/?page=dispatch&task=task-fixture",
  )
  outcome_serialized_page(
    "https://proj.example.test/other-mount/?page=dispatch",
    () => {
      models[0] = outcome_test_edit(
        models[0],
        Edit("summary", "Further observed detail"),
      )
    },
  )
  assert_eq(
    dispatch_outcome_draft(models[0], outcome_test_source()).owner_route,
    frozen,
  )
}

///|
test "outcome pending preview remains retryable when source refresh discards its response" {
  let source = outcome_test_source()
  let model = outcome_test_model()
  let (_, pending) = dispatch_outcome_update(_ => none, model, source, Preview)
  let old = dispatch_outcome_draft(pending, source)
  let (_, refreshing) = dispatch_lesson_handoff_update(
    _ => none,
    pending,
    Prepare,
  )
  let (_, ignored) = dispatch_outcome_update(
    _ => none,
    refreshing,
    source,
    Loaded(
      "task-fixture",
      4,
      old.request,
      dispatch_outcome_draft_json(old),
      Ok(outcome_test_response(old).stringify()),
    ),
  )
  let (_, returned) = dispatch_lesson_handoff_update(
    _ => none,
    ignored,
    Loaded(
      "task-fixture",
      4,
      refreshing.dispatch_lesson_handoff.request,
      Ok(source.stringify()),
    ),
  )
  assert_false(dispatch_outcome_draft(returned, source).pending)
  assert_eq(
    dispatch_outcome_draft_json(dispatch_outcome_draft(returned, source)),
    dispatch_outcome_draft_json(old),
  )
  let (_, retry) = dispatch_outcome_update(_ => none, returned, source, Preview)
  let retried = dispatch_outcome_draft(retry, source)
  assert_true(retried.pending)
  assert_true(retried.request > old.request)
  assert_eq(retried.recorded_at, old.recorded_at)
}

///|
test "outcome matching preview is independent of pending Book connection on same exact source" {
  let source = outcome_test_source()
  let (_, pending) = dispatch_outcome_update(
    _ => none,
    outcome_test_model(),
    source,
    Preview,
  )
  let old = dispatch_outcome_draft(pending, source)
  let (_, connecting) = dispatch_lesson_handoff_update(
    _ => none,
    pending,
    OpenBook,
  )
  assert_true(connecting.dispatch_lesson_handoff.pending)
  let (_, returned) = dispatch_outcome_update(
    _ => none,
    connecting,
    source,
    Loaded(
      "task-fixture",
      4,
      old.request,
      dispatch_outcome_draft_json(old),
      Ok(outcome_test_response(old).stringify()),
    ),
  )
  assert_true(dispatch_outcome_draft(returned, source).prepared is Some(_))
  assert_false(dispatch_outcome_draft(returned, source).pending)
}

///|
test "accepted task lesson preparation offers a plain language outcome composer" {
  let model = outcome_test_source_model()
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_lesson_handoff_view(_ => none, model)),
  )
  assert_true(html.contains("记录实际结果"))
  assert_true(html.contains("信息缺口"))
  assert_true(html.contains("识别缺口"))
  assert_true(html.contains("决断缺口"))
  assert_true(html.contains("尚未选择"))
  assert_false(html.contains("客户已接受"))
}

///|
fn outcome_test_draft() -> DispatchOutcomeDraft {
  {
    ..dispatch_outcome_empty(outcome_test_source()),
    outcome_summary: "Observed output matched the local criterion; customer response remains unknown.",
    observed_at: "2026-10-05T04:00:00",
    recorded_at: 1791176400,
    owner_route: "https://proj.example.test/apps/proj/?page=dispatch&task=task-fixture",
    gaps: Array::makei(3, index => {
      choice: "absent",
      summary: "I checked the captured report for gap " +
      index.to_string() +
      " and did not observe it.",
      severity: "",
      evidence_refs: ["report-fixture"],
    }),
  }
}

///|
fn outcome_test_model() -> Model {
  dispatch_outcome_store(outcome_test_source_model(), outcome_test_draft())
}

///|
fn outcome_test_edit(model : Model, action : DispatchOutcomeMsg) -> Model {
  let (_, next) = dispatch_outcome_update(
    _ => none,
    model,
    outcome_test_source(),
    action,
  )
  next
}

///|
test "outcome starts unassessed and every gap needs an explicit choice explanation and captured evidence" {
  let blank = dispatch_outcome_empty(outcome_test_source())
  assert_true(blank.gaps.all(gap => gap.choice.is_empty()))
  assert_false(dispatch_outcome_validation(blank).is_empty())
  let valid = outcome_test_draft()
  assert_eq(dispatch_outcome_validation(valid), "")
  for index in 0..<3 {
    for
      gap in [
        { ..valid.gaps[index], choice: "", },
        { ..valid.gaps[index], summary: " \n ", },
        { ..valid.gaps[index], evidence_refs: [], },
        { ..valid.gaps[index], evidence_refs: ["uncaptured-record"], },
        { ..valid.gaps[index], choice: "present", severity: "0", },
        { ..valid.gaps[index], choice: "present", severity: "6", },
      ] {
      let gaps = valid.gaps.copy()
      gaps[index] = gap
      assert_false(dispatch_outcome_validation({ ..valid, gaps, }).is_empty())
    }
  }
  for value in ["", "2026-02-30T04:00", "invalid", "2026-10-05T04:00Z"] {
    assert_false(
      dispatch_outcome_validation({ ..valid, observed_at: value, }).is_empty(),
    )
  }
}

///|
test "all absent outcome sends authored reasons zero severity and null capability" {
  let draft = {
    ..outcome_test_draft(),
    capability_id: "retained-hidden-id",
    capability_version: "retained-hidden-version",
    capability_summary: "Retained hidden capability description",
    change_text: "Retained hidden change",
  }
  let value = dispatch_outcome_draft_json(draft)
  assert_eq(dispatch_json_field(value, "capability"), Json::null())
  for index, name in ["information_gap", "recognition_gap", "decisiveness_gap"] {
    let gap = dispatch_json_field(value, name)
    assert_eq(dispatch_json_field(gap, "present"), Json::boolean(false))
    assert_eq(dispatch_json_field(gap, "severity"), Json::number(0))
    assert_eq(dispatch_json_text(gap, "summary"), draft.gaps[index].summary)
  }
  assert_eq(dispatch_json_field(value, "observed_at"), Json::number(1791172800))
}

///|
test "present outcome requires real authored capability fields and preserves hidden inputs" {
  let mut model = outcome_test_edit(
    outcome_test_model(),
    GapEdit(0, "choice", "present"),
  )
  model = outcome_test_edit(model, GapEdit(0, "severity", "3"))
  let missing = dispatch_outcome_draft(model, outcome_test_source())
  assert_true(dispatch_outcome_validation(missing).contains("真实能力"))
  for
    (field, value) in [
      ("capability_id", "capability.actual"),
      ("capability_version", "2.1"),
      ("capability_summary", "Actual capability description"),
      ("change_text", "Proposed capability change based on this observed gap"),
    ] {
    model = outcome_test_edit(model, Edit(field, value))
  }
  let complete = dispatch_outcome_draft(model, outcome_test_source())
  assert_eq(dispatch_outcome_validation(complete), "")
  assert_eq(
    dispatch_json_text(
      dispatch_json_field(dispatch_outcome_draft_json(complete), "capability"),
      "id",
    ),
    "capability.actual",
  )
  let hidden = outcome_test_edit(model, GapEdit(0, "choice", "absent"))
  assert_eq(
    dispatch_json_field(
      dispatch_outcome_draft_json(
        dispatch_outcome_draft(hidden, outcome_test_source()),
      ),
      "capability",
    ),
    Json::null(),
  )
  let restored = outcome_test_edit(hidden, GapEdit(0, "choice", "present"))
  let draft = dispatch_outcome_draft(restored, outcome_test_source())
  assert_eq(draft.capability_id, complete.capability_id)
  assert_eq(draft.change_text, complete.change_text)
  assert_eq(draft.gaps[0].severity, "3")
  assert_eq(draft.gaps[0].summary, complete.gaps[0].summary)
}

///|
test "tab local outcome drafts survive task switches failed source refresh and changed exact sources" {
  let source = outcome_test_source()
  let original = outcome_test_edit(
    outcome_test_model(),
    Edit("summary", "My actual observation"),
  )
  let switched = {
    ..original,
    dispatch_task_id: "another-task",
    dispatch_task_selection: 5,
  }
  let ignored = outcome_test_edit(switched, Edit("summary", "late input"))
  assert_eq(
    dispatch_outcome_draft(ignored, source).outcome_summary,
    "My actual observation",
  )
  let (_, refreshing) = dispatch_lesson_handoff_update(
    _ => none,
    original,
    Prepare,
  )
  let (_, failed) = dispatch_lesson_handoff_update(
    _ => none,
    refreshing,
    Loaded(
      "task-fixture",
      4,
      refreshing.dispatch_lesson_handoff.request,
      Err("offline"),
    ),
  )
  assert_eq(
    dispatch_outcome_draft(failed, source).outcome_summary,
    "My actual observation",
  )
  let failed_html = opc_render_cell(
    @rabbita.static_cell(dispatch_lesson_handoff_view(_ => none, failed)),
  )
  assert_true(failed_html.contains("My actual observation"))
  assert_true(failed_html.contains("查看此前捕获来源的笔记"))
  assert_false(failed_html.contains("下载完整结果"))
  assert_false(failed_html.contains("id=\"dispatch-outcome-composer\""))
  let changed = lesson_receipt_test_set(
    source,
    "report_snapshot",
    Json::string("different exact bytes"),
  )
  let new_source = {
    ..original,
    dispatch_lesson_handoff: {
      ..original.dispatch_lesson_handoff,
      payload: Some(changed),
    },
  }
  assert_eq(dispatch_outcome_draft(new_source, changed).outcome_summary, "")
  let (_, edited_new) = dispatch_outcome_update(
    _ => none,
    new_source,
    changed,
    Edit("summary", "New-source observation"),
  )
  assert_eq(
    dispatch_outcome_draft(edited_new, source).outcome_summary,
    "My actual observation",
  )
  assert_eq(
    dispatch_outcome_draft(edited_new, changed).outcome_summary,
    "New-source observation",
  )
  assert_eq(edited_new.dispatch_outcome_drafts.length(), 2)
}

///|
test "unchanged input preserves recorded time while actual edits invalidate prepared bytes" {
  let model = outcome_test_model()
  let source = outcome_test_source()
  let original = dispatch_outcome_draft(model, source)
  let unchanged = outcome_test_edit(
    model,
    Edit("summary", original.outcome_summary),
  )
  assert_eq(
    dispatch_outcome_draft(unchanged, source).recorded_at,
    original.recorded_at,
  )
  let changed = outcome_test_edit(
    model,
    Edit("summary", original.outcome_summary + " Additional observation."),
  )
  assert_eq(dispatch_outcome_draft(changed, source).recorded_at, 0)
  assert_true(dispatch_outcome_draft(changed, source).prepared is None)
  assert_false(dispatch_outcome_draft(changed, source).pending)
}

///|
test "changed outcome source keeps old authored notes readable without rebinding or stale export" {
  let source = outcome_test_source()
  let old = {
    ..outcome_test_draft(),
    outcome_summary: "Earlier real observation <script>unsafe</script>",
    capability_id: "actual-old-capability",
    capability_version: "2",
    capability_summary: "Earlier proposed change",
    change_text: "Earlier detailed improvement",
  }
  let original = dispatch_outcome_store(outcome_test_source_model(), old)
  let changed = lesson_receipt_test_set(
    source,
    "report",
    lesson_receipt_test_ref("replacement-report"),
  )
  let refreshed = {
    ..original,
    dispatch_task_report_id: "replacement-report",
    dispatch_lesson_handoff: {
      ..original.dispatch_lesson_handoff,
      payload: Some(changed),
    },
  }
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_lesson_handoff_view(_ => none, refreshed)),
  )
  for
    text in [
      "查看此前捕获来源的笔记",
      "Earlier real observation",
      "Earlier proposed change",
      "Earlier detailed improvement",
      "actual-old-capability",
      "report-fixture",
      old.gaps[0].summary,
    ] {
    assert_true(html.contains(text), msg=text)
  }
  assert_false(html.contains("<script>unsafe</script>"))
  assert_false(html.contains("下载完整结果"))
  assert_eq(dispatch_outcome_draft(refreshed, changed).outcome_summary, "")
  assert_eq(
    dispatch_outcome_draft(refreshed, source).outcome_summary,
    old.outcome_summary,
  )
}
