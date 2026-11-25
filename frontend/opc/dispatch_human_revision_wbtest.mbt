///|
fn human_revision_proj_record(id? : String = "H1") -> Json {
  {
    "schema": "moonproj.human-revision.v1",
    "capture_scope": "immutable_human_revision",
    "revision_id": id,
    "task_id": "task-1",
    "original_run_id": "run-1",
    "session_id": "session-1",
    "original_command_id": "command-1",
    "workspace": "/workspace/book",
    "workspace_id": "workspace-1",
    "output": { "command_id": "C1", "path": "C1.txt", "evidence_id": "file-C1" },
    "author_type": "human",
    "base": {
      "scope": "current_workspace_bytes_at_edit",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
    "content": {
      "path": ".moonsuite/products/moonproj/human-revisions/" +
      id +
      "/content.txt",
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "size_bytes": 12,
    },
    "state": "saved",
    "created_at": "2026-10-05T08:00:00Z",
  }
}

///|
fn human_revision_proj_source(id? : String = "H1") -> Json {
  { "type": "human_revision", "revision_id": id, "original_run_id": "run-1" }
}

///|
fn human_revision_proj_model() -> Model {
  let model = continuation_proj_model()
  {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      preview_revision: "H1",
      human_revision_candidate: human_revision_proj_record(),
      human_revision_content: "edited bytes",
      human_revisions: [human_revision_proj_record()],
    },
  }
}

///|
fn human_revision_proj_envelope(
  model : Model,
  source : Json,
  candidate? : Json = human_revision_proj_record(),
  content? : Json = Json::string("edited bytes"),
) -> String {
  let json = @json.parse(
    continuation_proj_envelope(model, source, Json::null()),
  ) catch {
    _ => Json::null()
  }
  if json is Object(fields) {
    fields["human_revisions"] = ToJson::to_json(model.dispatch_continuation.human_revisions)
    fields["human_revision_candidate"] = candidate
    fields["human_revision_content"] = content
  }
  json.stringify()
}

///|
test "human revision return hint reads exact ID without command run or selection authority" {
  assert_eq(
    dispatch_human_revision_return_hint(
      "https://proj.example/?task=task-1&human_revision_id=H+1", "task-1",
    ),
    "H 1",
  )
  assert_eq(
    dispatch_human_revision_return_hint(
      "https://proj.example/?task=other&human_revision_id=H1", "task-1",
    ),
    "",
  )
  let page = "https://proj.example/?task=task-1&human_revision_id=H1&source_run=stale&continuation_id=K2&continuation_command=C2"
  assert_true(
    anchor_test_browser(page, () => {
      let emitted : Array[Msg] = []
      let emit : @rabbita.Emit[Msg] = msg => {
        emitted.push(msg)
        none
      }
      let original = continuation_proj_model()
      let (read, loading) = dispatch_continuation_update(
        emit,
        Refresh,
        original,
      )
      drafts_test_execute(read)
      anchor_test_respond(human_revision_proj_envelope(loading, Json::null()))
      let (_, ready) = update(emit, emitted[0], loading)
      ready.dispatch_continuation.preview_revision == "H1" &&
      ready.dispatch_continuation.preview_command == "" &&
      dispatch_json_text(
        ready.dispatch_continuation.human_revision_candidate,
        "revision_id",
      ) ==
      "H1" &&
      ready.dispatch_continuation.selected is Null &&
      ready.dispatch_continuation.operation is Null &&
      ready.dispatch_task_report_id == original.dispatch_task_report_id &&
      ready.dispatch_run == original.dispatch_run &&
      anchor_test_requests() ==
      "GET /api/company/tasks/task-1/continuations?human_revision_id=H1"
    }),
  )
}

///|
test "human revision preview rejects wrong ID attribution malformed bytes and synthetic execution fields" {
  let model = human_revision_proj_model()
  let wrong = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    human_revision_proj_envelope(
      model,
      Json::null(),
      candidate=human_revision_proj_record(id="H2"),
    ),
  ).unwrap()
  assert_true(wrong.human_revision_candidate is Null)
  assert_true(wrong.selected is Null)
  assert_true(wrong.error.contains("准确人工修订"))
  for
    (key, value) in [
      ("task_id", "other"),
      ("original_run_id", "other"),
      ("session_id", "other"),
      ("original_command_id", "other"),
      ("workspace", "/other"),
      ("author_type", "model"),
      ("capture_scope", "workspace_replacement"),
      ("state", "completed"),
      ("command_id", "synthetic"),
      ("model", "invented-model"),
      ("receipt", "invented-receipt"),
    ] {
    let record = human_revision_proj_record()
    if record is Object(fields) {
      fields[key] = Json::string(value)
    }
    assert_false(dispatch_human_revision_valid(model, record), msg=key)
  }
  for size in [-1.0, 0.5, 262145.0] {
    let record = human_revision_proj_record()
    if dispatch_json_field(record, "content") is Object(fields) {
      fields["size_bytes"] = Json::number(size)
    }
    assert_false(dispatch_human_revision_valid(model, record))
  }
  let record = human_revision_proj_record()
  if dispatch_json_field(record, "base") is Object(fields) {
    fields["scope"] = "captured_original_command_bytes"
  }
  assert_false(dispatch_human_revision_valid(model, record))
}

///|
test "human revision canonical path safe ID normalized root and empty content validate exactly" {
  let model = human_revision_proj_model()
  let normalized = {
    ..model,
    dispatch_run: Some({
      ..model.dispatch_run.unwrap(),
      workspace: "/workspace//temporary/../book/",
    }),
  }
  let empty = human_revision_proj_record()
  if dispatch_json_field(empty, "content") is Object(fields) {
    fields["size_bytes"] = 0
  }
  assert_true(dispatch_human_revision_valid(normalized, empty))
  for id in ["", "../H1", "H/1", "H 1", "H%31", "H:1", "书"] {
    assert_false(
      dispatch_human_revision_valid(model, human_revision_proj_record(id~)),
      msg=id,
    )
  }
  assert_false(dispatch_human_revision_id_valid("a".repeat(129)))
  assert_true(dispatch_human_revision_id_valid("a".repeat(128)))
  for
    path in [
      "another.txt", ".moonsuite/products/moonproj/human-revisions/H2/content.txt",
      ".moonsuite/products/moonproj/human-revisions/H1/../H1/content.txt",
    ] {
    let record = human_revision_proj_record()
    if dispatch_json_field(record, "content") is Object(fields) {
      fields["path"] = Json::string(path)
    }
    assert_false(dispatch_human_revision_valid(model, record), msg=path)
  }
}

///|
test "human revision selection stores exact bounded request before POST and retries one identity" {
  let page = "https://proj.example/?task=task-1"
  assert_true(
    anchor_test_browser(page, () => {
      let emitted : Array[Msg] = []
      let emit : @rabbita.Emit[Msg] = msg => {
        emitted.push(msg)
        none
      }
      let model = human_revision_proj_model()
      let (store, saving) = dispatch_continuation_update(
        emit,
        SelectHumanRevision,
        model,
      )
      let body = saving.dispatch_continuation.operation
      if saving.dispatch_continuation.phase != "saving" ||
        anchor_test_requests() != "" ||
        dispatch_json_text(body, "human_revision_id") != "H1" ||
        !(dispatch_json_field(body, "command_id") is Null) ||
        !(dispatch_json_field(body, "continuation_id") is Null) ||
        dispatch_selection_target(body) != human_revision_proj_source() {
        return false
      }
      drafts_test_execute(store)
      let restored = dispatch_json_field(
        dispatch_selection_restore(model),
        "body",
      )
      let (post, attaching) = update(emit, emitted[0], saving)
      drafts_test_execute(post)
      let (_, retrying) = dispatch_continuation_update(
        emit,
        SelectHumanRevision,
        {
          ..attaching,
          dispatch_continuation: {
            ..attaching.dispatch_continuation,
            phase: "ready",
          },
        },
      )
      restored == body &&
      retrying.dispatch_continuation.operation == body &&
      retrying.dispatch_run == model.dispatch_run &&
      retrying.dispatch_continuation.records ==
      model.dispatch_continuation.records &&
      anchor_test_requests() ==
      "POST /api/company/plan/tasks/task-1/continuations"
    }),
  )
}

///|
test "human revision acknowledgement and readback retire lost response without new execution" {
  let model = human_revision_proj_model()
  let (_, saving) = dispatch_continuation_update(
    _ => none,
    SelectHumanRevision,
    model,
  )
  let json = @json.parse(anchor_test_ack(saving))
  if json is Object(fields) {
    fields["operation_source"] = human_revision_proj_source()
    fields["selected_delivery_source"] = human_revision_proj_source()
    fields["human_revisions"] = [human_revision_proj_record()]
  }
  let acknowledged = dispatch_selection_ack_state(saving, json.stringify()).unwrap()
  assert_false(acknowledged.operation_pending)
  assert_eq(acknowledged.selected, human_revision_proj_source())
  assert_eq(
    acknowledged.human_revision_candidate,
    model.dispatch_continuation.human_revision_candidate,
  )
  let recovered = dispatch_continuation_decode(
    saving,
    saving.dispatch_continuation,
    human_revision_proj_envelope(saving, human_revision_proj_source()),
  ).unwrap()
  assert_false(recovered.operation_pending)
  assert_eq(recovered.selected, human_revision_proj_source())
  assert_eq(recovered.records, model.dispatch_continuation.records)
}

///|
test "late human revision preview cannot replace newer exact preview or another actor" {
  let model = human_revision_proj_model()
  let (_, first) = dispatch_continuation_update(
    _ => none,
    PreviewHumanRevision("H1"),
    model,
  )
  let (_, second) = dispatch_continuation_update(
    _ => none,
    PreviewHumanRevision("H2"),
    first,
  )
  let (_, ignored) = dispatch_continuation_update(
    _ => none,
    Loaded(
      "task-1",
      3,
      first.dispatch_continuation.request,
      "",
      "",
      Ok(human_revision_proj_envelope(first, Json::null())),
    ),
    second,
  )
  assert_eq(ignored.dispatch_continuation.preview_revision, "H2")
  assert_true(ignored.dispatch_continuation.human_revision_candidate is Null)
  assert_eq(ignored.dispatch_continuation.human_revision_content, "")
  assert_true(ignored.dispatch_continuation.selected is Null)
  let (_, switched) = dispatch_continuation_update(
    _ => none,
    Loaded(
      "task-1",
      3,
      second.dispatch_continuation.request,
      "",
      "",
      Ok(human_revision_proj_envelope(second, human_revision_proj_source())),
    ),
    { ..second, dispatch_task_actor_id: "other-actor", },
  )
  assert_true(switched.dispatch_continuation.selected is Null)
}

///|
#warnings("-alert_unstable")
test "exact human revision content is escaped transient text and empty snapshots remain selectable" {
  let model = human_revision_proj_model()
  let text = "<script>alert('x')</script>\n<img src=x onerror=alert(1)> & 书"
  let record = human_revision_proj_record()
  if dispatch_json_field(record, "content") is Object(fields) {
    fields["size_bytes"] = Json::number(
      dispatch_human_revision_utf8_size(text).to_double(),
    )
  }
  let decoded = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    human_revision_proj_envelope(
      model,
      Json::null(),
      candidate=record,
      content=Json::string(text),
    ),
  ).unwrap()
  assert_eq(decoded.human_revision_content, text)
  let previewed = { ..model, dispatch_continuation: decoded, }
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_human_revision_view(_ => none, previewed)),
  )
  assert_true(html.contains("&lt;script&gt;"))
  assert_false(html.contains("<script>"))
  assert_false(html.contains("<img src=x"))
  let (_, saving) = dispatch_continuation_update(
    _ => none,
    SelectHumanRevision,
    previewed,
  )
  assert_eq(saving.dispatch_continuation.phase, "saving")
  assert_false(
    saving.dispatch_continuation.operation.stringify().contains("<script>"),
  )
  let (_, next) = dispatch_continuation_update(
    _ => none,
    PreviewHumanRevision("H2"),
    previewed,
  )
  assert_eq(next.dispatch_continuation.human_revision_content, "")
  assert_true(next.dispatch_continuation.human_revision_candidate is Null)
  let empty = human_revision_proj_record()
  if dispatch_json_field(empty, "content") is Object(fields) {
    fields["size_bytes"] = 0
  }
  let empty_state = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    human_revision_proj_envelope(
      model,
      Json::null(),
      candidate=empty,
      content=Json::string(""),
    ),
  ).unwrap()
  assert_false(empty_state.human_revision_candidate is Null)
  let empty_model = { ..model, dispatch_continuation: empty_state, }
  let (_, saving_empty) = dispatch_continuation_update(
    _ => none,
    SelectHumanRevision,
    empty_model,
  )
  assert_eq(saving_empty.dispatch_continuation.phase, "saving")
  let empty_html = opc_render_cell(
    @rabbita.static_cell(dispatch_human_revision_view(_ => none, empty_model)),
  )
  assert_true(empty_html.contains("空文本（0 字节）"))
  let absent = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    human_revision_proj_envelope(model, Json::null(), content=Json::null()),
  ).unwrap()
  assert_true(absent.human_revision_candidate is Null)
  assert_eq(absent.human_revision_content, "")
  let mismatched = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    human_revision_proj_envelope(
      model,
      Json::null(),
      content=Json::string("wrong"),
    ),
  ).unwrap()
  assert_true(mismatched.human_revision_candidate is Null)
}

///|
test "human revision report recovery preserves captured identity source and bytes reference" {
  let previous = continuation_proj_storage_setup()
  let model = human_revision_proj_model()
  let selected = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      selected: human_revision_proj_source(),
    },
  }
  let body = dispatch_new_report_body(selected)
  assert_true(
    dispatch_selection_store(
      dispatch_report_operation_key(selected),
      body.stringify(),
      true,
    ),
  )
  assert_eq(
    dispatch_report_operation_body(selected, dispatch_new_report_body(selected)).unwrap(),
    body,
  )
  assert_eq(dispatch_json_field(body, "evidence_ids"), [
    ".moonsuite/products/moonproj/human-revisions/H1/content.txt",
  ])
  let switched = {
    ..selected,
    dispatch_continuation: {
      ..selected.dispatch_continuation,
      selected: continuation_proj_source(),
    },
  }
  assert_true(
    dispatch_report_operation_body(switched, dispatch_new_report_body(switched))
    is Err(_),
  )
  assert_eq(dispatch_report_evidence(switched), ["evidence-C1"])
  continuation_proj_storage_cleanup(previous)
}

///|
test "human revision task snapshot restores offline reportability and immutable evidence" {
  let model = human_revision_proj_model()
  let old_report : Json = {
    "reportGuid": "C0-report",
    "summary": "Original report",
    "delivery_source": Json::null(),
    "evidence_ids": ["original-only"],
  }
  let snapshot = {
    ..dispatch_test_snapshot("failed"),
    report_id: "C0-report",
    report_records: [old_report],
    human_revision_records: [human_revision_proj_record()],
    continuation_records: model.dispatch_continuation.records,
    delivery_source: human_revision_proj_source(),
  }
  let restored = apply_dispatch_snapshot(
    { ..model, dispatch_continuation: empty_dispatch_continuation(), },
    snapshot,
  )
  assert_true(restored.dispatch_continuation.source_verified)
  assert_true(dispatch_can_submit(restored))
  assert_false(dispatch_can_accept_report(restored))
  assert_eq(restored.dispatch_run.unwrap().state, "failed")
  assert_eq(dispatch_report_evidence(restored), [
    ".moonsuite/products/moonproj/human-revisions/H1/content.txt",
  ])
  assert_eq(
    dispatch_json_field(dispatch_new_report_body(restored), "delivery_source"),
    human_revision_proj_source(),
  )
  assert_true(dispatch_report_summary(restored).contains("人工修订 H1"))
  assert_false(dispatch_report_summary(restored).contains("原生执行"))
  assert_eq(restored.dispatch_continuation.report_records[0], old_report)
  let offline = {
    ..restored,
    dispatch_continuation: {
      ..restored.dispatch_continuation,
      phase: "unavailable",
    },
  }
  assert_true(dispatch_can_submit(offline))
  let missing = apply_dispatch_snapshot(
    { ..model, dispatch_continuation: empty_dispatch_continuation(), },
    { ..snapshot, human_revision_records: [], },
  )
  assert_false(missing.dispatch_continuation.source_verified)
  assert_false(dispatch_can_submit(missing))
  assert_eq(dispatch_report_evidence(missing), [])
}

///|
test "human revision reports require exact source before acceptance and preserve older reports" {
  let model = human_revision_proj_model()
  let old_report : Json = {
    "reportGuid": "C1-report",
    "delivery_source": continuation_proj_source(),
  }
  let report : Json = {
    "reportGuid": "H1-report",
    "delivery_source": human_revision_proj_source(),
  }
  let model = {
    ..model,
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "C1-report",
    dispatch_continuation: {
      ..model.dispatch_continuation,
      selected: human_revision_proj_source(),
      report_source: continuation_proj_source(),
      report_records: [old_report, report],
    },
  }
  assert_false(dispatch_can_accept_report(model))
  let (_, chosen) = dispatch_continuation_update(
    _ => none,
    SelectReport("H1-report"),
    model,
  )
  assert_true(dispatch_can_accept_report(chosen))
  assert_eq(
    dispatch_json_field(
      dispatch_accept_report_body(chosen, "accept-human"),
      "delivery_source",
    ),
    human_revision_proj_source(),
  )
  assert_eq(chosen.dispatch_continuation.report_records[0], old_report)
  let changed = {
    ..chosen,
    dispatch_continuation: {
      ..chosen.dispatch_continuation,
      human_revisions: [
        human_revision_proj_record(),
        human_revision_proj_record(id="H2"),
      ],
      selected: human_revision_proj_source(id="H2"),
    },
  }
  assert_false(dispatch_can_accept_report(changed))
  assert_true(dispatch_can_submit(changed))
}

///|
test "accepted and done human revisions remain inspection only" {
  for stage in ["accepted", "done"] {
    let model = { ..human_revision_proj_model(), dispatch_task_stage: stage, }
    for action in [SelectHumanRevision, Select, SelectOriginal] {
      let (_, unchanged) = dispatch_continuation_update(
        _ => none,
        action,
        model,
      )
      assert_true(unchanged.dispatch_continuation.operation is Null)
      assert_eq(unchanged.dispatch_run, model.dispatch_run)
    }
    assert_false(dispatch_can_submit(model))
    assert_false(dispatch_can_accept_report(model))
    let (_, preview) = dispatch_continuation_update(
      _ => none,
      PreviewHumanRevision("H1"),
      model,
    )
    assert_eq(preview.dispatch_continuation.preview_revision, "H1")
  }
}

///|
test "task decode retains human revisions without replacing native execution" {
  let response : Json = {
    "data": {
      "task": {
        "taskGuid": "task-1",
        "status": "in_progress",
        "execution": {
          "task_id": "task-1",
          "run_id": "run-1",
          "session_id": "session-1",
          "command_id": "command-1",
          "workspace": "/workspace/book",
          "state": "failed",
        },
        "human_revisions": [human_revision_proj_record()],
        "continuations": [continuation_proj_record()],
        "selected_delivery_source": human_revision_proj_source(),
      },
      "reports": [],
    },
  }
  let snapshot = dispatch_decode_snapshot(response.stringify(), "task-1").unwrap()
  assert_eq(snapshot.human_revision_records, [human_revision_proj_record()])
  assert_eq(snapshot.continuation_records, [continuation_proj_record()])
  assert_eq(snapshot.run.unwrap().command_id, "command-1")
  assert_eq(snapshot.run.unwrap().state, "failed")
}

///|
#warnings("-alert_unstable")
test "human revision preview and report labels expose honest baseline and immutable identity" {
  let model = human_revision_proj_model()
  let model = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      selected: human_revision_proj_source(),
      accepted_report_id: "H1-report",
      accepted_delivery_source: human_revision_proj_source(),
      report_records: [
        {
          "reportGuid": "H1-report",
          "delivery_source": human_revision_proj_source(),
        },
      ],
    },
  }
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_continuation_view(_ => none, model)),
  )
  for
    text in [
      "人工修订 / H1", "编辑开始时工作区的当前文件字节", "内容 SHA-256",
      "不可变内容快照", "明确选择此人工修订用于报告", "返回链接只打开预览",
    ] {
    assert_true(html.contains(text), msg=text)
  }
  let accepted = opc_render_cell(
    @rabbita.static_cell(
      dispatch_human_revision_view(_ => none, {
        ..model,
        dispatch_task_stage: "accepted",
      }),
    ),
  )
  assert_false(accepted.contains("明确选择此人工修订用于报告"))
  assert_true(accepted.contains("没有新的模型执行"))
}

///|
test "canonical accepted hint survives ordinary and output inspection URLs" {
  for accepted in [true, false] {
    let json = @json.parse(handoff_proj_fixture())
    if json is Object(fields) {
      fields["task_accepted"] = Json::boolean(accepted)
    }
    let base = dispatch_desk_handoff_url(
      json.stringify(),
      "task-1",
      "https://proj.example/?task=task-1",
    ).unwrap()
    let hint = "work_accepted=" + (if accepted { "true" } else { "false" })
    assert_true(base.contains(hint))
    let output = dispatch_desk_output_url(
      base,
      dispatch_json_field(human_revision_proj_record(), "output"),
    )
    assert_true(output.contains(hint))
    assert_true(output.contains("work_mode=inspect"))
  }
  let unknown = @json.parse(handoff_proj_fixture())
  if unknown is Object(fields) {
    fields["task_accepted"] = Json::null()
  }
  let inspection = dispatch_desk_handoff_url(
    unknown.stringify(),
    "task-1",
    "https://proj.example/?task=task-1",
  ).unwrap()
  assert_false(inspection.contains("work_accepted="))
}
