///|
fn accepted_human_test_model(
  text? : String = "edited bytes",
  task? : String = "task-1",
) -> Model {
  let model = human_revision_proj_model()
  let record = human_revision_proj_record()
  let content = dispatch_json_field(record, "content")
  let content = lesson_receipt_test_set(
    content,
    "sha256",
    Json::string(outcome_test_hash(text)),
  )
  let content = lesson_receipt_test_set(
    content,
    "size_bytes",
    Json::number(dispatch_human_revision_utf8_size(text).to_double()),
  )
  let record = lesson_receipt_test_set(record, "content", content)
  let record = lesson_receipt_test_set(record, "task_id", Json::string(task))
  {
    ..model,
    dispatch_task_id: task,
    dispatch_task_stage: "accepted",
    dispatch_task_report_id: "report-H1",
    dispatch_task_commitment: {
      "task_id": task,
      "receipts": [
        { "action": "report", "report_id": "report-H1", "revision": 1 },
      ],
    },
    dispatch_continuation: {
      ..model.dispatch_continuation,
      task_id: task,
      accepted: true,
      revision: 7.0,
      accepted_report_id: "report-H1",
      accepted_delivery_source: human_revision_proj_source(),
      selected: human_revision_proj_source(),
      report_source: human_revision_proj_source(),
      human_revisions: [record],
      report_records: [
        {
          "reportGuid": "report-H1",
          "delivery_source": human_revision_proj_source(),
        },
        { "reportGuid": "older-report", "delivery_source": Json::null() },
      ],
    },
  }
}

///|
extern "js" fn accepted_human_test_base64(text : String) -> String =
  #| text => Buffer.from(text,'utf8').toString('base64')

///|
fn accepted_human_test_payload(
  text? : String = "edited bytes",
  task? : String = "task-1",
) -> Json {
  {
    "contract_version": "moonproj.accepted-human-result.v1",
    "source_product": "moonproj",
    "provenance_scope": "captured_accepted_human_revision",
    "authenticity": "unsigned_source_observation",
    "authorizing": false,
    "task": {
      "record_id": task,
      "record_version": "7",
      "record_digest": "sha256:" + outcome_test_hash("task"),
    },
    "report": {
      "record_id": "report-H1",
      "record_version": "1",
      "record_digest": "sha256:" + outcome_test_hash("report"),
    },
    "revision": {
      "revision_id": "H1",
      "original_run_id": "run-1",
      "session_id": "session-1",
      "original_command_id": "command-1",
      "output_command_id": "C1",
      "output_evidence_id": "file-C1",
      "revision_snapshot_digest": "sha256:" + outcome_test_hash("revision"),
    },
    "content": {
      "encoding": "base64",
      "media_type": "text/plain;charset=utf-8",
      "size_bytes": dispatch_human_revision_utf8_size(text),
      "sha256": "sha256:" + outcome_test_hash(text),
      "data": accepted_human_test_base64(text),
    },
  }
}

///|
// Reuse the established in-memory fetch/Blob/download fixture. No live browser,
// network, workspace write, provider or cross-product transport is involved.
test "accepted human export actual GET downloads exact response bytes once with empty and Unicode content" {
  for
    (text, task) in [
      ("", "task-1"),
      ("edited bytes", "task-1"),
      ("你好\r\nline two\n", "task:1.v2"),
    ] {
    let model = accepted_human_test_model(text~, task~)
    let response = " \n" +
      accepted_human_test_payload(text~, task~).stringify(indent=2) +
      "\n"
    let emitted : Array[Msg] = []
    let emit : @rabbita.Emit[Msg] = message => {
      emitted.push(message)
      none
    }
    let captures : Array[String] = []
    let states : Array[Model] = []
    outcome_test_browser(() => {
      let (get, waiting) = update(
        emit,
        AcceptedHumanExportAction(Download),
        model,
      )
      lesson_receipt_test_run(get)
      let (repeat, repeated) = update(
        emit,
        AcceptedHumanExportAction(Download),
        waiting,
      )
      lesson_receipt_test_run(repeat)
      states.push(repeated)
      outcome_test_respond(response)
      let (download, done) = update(emit, emitted[0], repeated)
      lesson_receipt_test_run(download)
      let (duplicate, settled) = update(emit, emitted[0], done)
      lesson_receipt_test_run(duplicate)
      states.push(settled)
      captures.push(outcome_test_browser_state())
    })
    assert_eq(states[0].dispatch_accepted_human_export.request, 1)
    assert_false(states[1].dispatch_accepted_human_export.pending)
    assert_true(
      states[1].dispatch_accepted_human_export.notice.contains("未签名"),
    )
    let captured = @json.parse(captures[0])
    let requests = dispatch_continuation_array(captured, "requests")
    assert_eq(requests.length(), 1)
    assert_eq(
      dispatch_json_text(requests[0], "url"),
      "/api/company/tasks/" + task + "/accepted-human-result",
    )
    assert_eq(dispatch_json_text(requests[0], "method"), "GET")
    assert_eq(dispatch_json_field(requests[0], "body"), Json::null())
    let downloads = dispatch_continuation_array(captured, "downloads")
    assert_eq(downloads.length(), 1)
    assert_eq(dispatch_json_text(downloads[0], "text"), response)
    assert_eq(
      dispatch_json_text(downloads[0], "filename"),
      if task == "task-1" {
        "moonproj-accepted-human-task-1-H1.json"
      } else {
        "moonproj-accepted-human-task_1_v2-H1.json"
      },
    )
    assert_eq(dispatch_json_field(captured, "storage"), Json::number(0))
    let done = states[1]
    assert_eq(done.dispatch_task_stage, model.dispatch_task_stage)
    assert_eq(done.dispatch_task_report_id, model.dispatch_task_report_id)
    assert_eq(
      done.dispatch_continuation.accepted_delivery_source,
      model.dispatch_continuation.accepted_delivery_source,
    )
    assert_eq(
      done.dispatch_continuation.report_records,
      model.dispatch_continuation.report_records,
    )
    assert_eq(
      done.dispatch_continuation.selected,
      model.dispatch_continuation.selected,
    )
    assert_eq(done.dispatch_lesson_handoff.payload, None)
    assert_false(done.dispatch_lesson_handoff.pending)
    assert_false(done.dispatch_desk_handoff.pending)
  }
}

///|
test "accepted human export rejects contract identity metadata shape and malformed content" {
  let model = accepted_human_test_model()
  let payload = accepted_human_test_payload()
  assert_true(dispatch_accepted_human_payload(model, payload.stringify()))
  let invalid : Array[Json] = []
  for
    (key, value) in [
      ("contract_version", Json::string("other")),
      ("source_product", Json::string("moondesk")),
      ("provenance_scope", Json::string("live_workspace")),
      ("authenticity", Json::string("signed")),
      ("authorizing", Json::boolean(true)),
      ("path", Json::string("/private/workspace")),
    ] {
    invalid.push(lesson_receipt_test_set(payload, key, value))
  }
  for kind in ["task", "report"] {
    let reference = dispatch_json_field(payload, kind)
    for
      (key, value) in [
        ("record_id", "other"),
        ("record_version", ""),
        ("record_version", "01"),
        ("record_version", "0"),
        ("record_version", "2147483648"),
        ("record_digest", "not-a-digest"),
        ("path", "../private.json"),
      ] {
      invalid.push(
        lesson_receipt_test_set(
          payload,
          kind,
          lesson_receipt_test_set(reference, key, Json::string(value)),
        ),
      )
    }
  }
  let revision = dispatch_json_field(payload, "revision")
  for (kind, version) in [("task", "6"), ("task", "8"), ("report", "2")] {
    invalid.push(
      lesson_receipt_test_set(
        payload,
        kind,
        lesson_receipt_test_set(
          dispatch_json_field(payload, kind),
          "record_version",
          Json::string(version),
        ),
      ),
    )
  }
  for
    key in [
      "revision_id", "original_run_id", "session_id", "original_command_id", "output_command_id",
      "output_evidence_id", "revision_snapshot_digest", "workspace",
    ] {
    invalid.push(
      lesson_receipt_test_set(
        payload,
        "revision",
        lesson_receipt_test_set(revision, key, Json::string("other")),
      ),
    )
  }
  let content = dispatch_json_field(payload, "content")
  for
    (key, value) in [
      ("encoding", Json::string("utf8")),
      ("media_type", Json::string("text/html")),
      ("size_bytes", Json::number(0)),
      ("size_bytes", Json::number(-1)),
      ("size_bytes", Json::number(262145)),
      ("size_bytes", Json::number(12.5)),
      ("data", Json::string("")),
      ("data", Json::string("invalid")),
      ("data", Json::null()),
      ("sha256", Json::string("sha256:" + outcome_test_hash("other"))),
      ("path", Json::string("/private/file.txt")),
    ] {
    invalid.push(
      lesson_receipt_test_set(
        payload,
        "content",
        lesson_receipt_test_set(content, key, value),
      ),
    )
  }
  for value in invalid {
    assert_false(
      dispatch_accepted_human_payload(model, value.stringify()),
      msg=value.stringify(),
    )
  }
  assert_false(dispatch_accepted_human_payload(model, "not json"))
  assert_false(dispatch_accepted_human_payload(model, " ".repeat(524289)))
  assert_true(dispatch_accepted_human_base64_valid("", 0.0))
  assert_false(dispatch_accepted_human_base64_valid("Zh==", 1.0))
  assert_false(dispatch_accepted_human_base64_valid(" Zg=", 1.0))
  let uncaptured_versions = {
    ..model,
    dispatch_task_commitment: Json::null(),
    dispatch_continuation: { ..model.dispatch_continuation, revision: 0.0, },
  }
  assert_true(
    dispatch_accepted_human_payload(uncaptured_versions, payload.stringify()),
  )
  let receipt : Json = {
    "action": "report",
    "report_id": "report-H1",
    "revision": 1,
  }
  for
    receipts in [
      [receipt, receipt],
      [{ "action": "report", "report_id": "report-H1", "revision": 0 }],
    ] {
    assert_false(
      dispatch_accepted_human_payload(
        {
          ..model,
          dispatch_task_commitment: {
            "task_id": "task-1",
            "receipts": ToJson::to_json(receipts),
          },
        },
        payload.stringify(),
      ),
    )
  }
}

///|
test "accepted human export transport failure identity mismatch and retry never download stale callback" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let states : Array[Model] = []
  let captures : Array[String] = []
  outcome_test_browser(() => {
    let (get, waiting) = update(
      emit,
      AcceptedHumanExportAction(Download),
      accepted_human_test_model(),
    )
    lesson_receipt_test_run(get)
    outcome_test_fail()
    let (none1, failed) = update(emit, emitted[0], waiting)
    lesson_receipt_test_run(none1)
    states.push(failed)
    let (retry, retrying) = update(
      emit,
      AcceptedHumanExportAction(Download),
      failed,
    )
    lesson_receipt_test_run(retry)
    let (late, _) = update(emit, emitted[0], retrying)
    lesson_receipt_test_run(late)
    let wrong = lesson_receipt_test_set(
      accepted_human_test_payload(),
      "report",
      {
        "record_id": "wrong",
        "record_version": "1",
        "record_digest": "sha256:" + outcome_test_hash("report"),
      },
    )
    outcome_test_respond(wrong.stringify())
    let (rejected, rejected_model) = update(emit, emitted[1], retrying)
    lesson_receipt_test_run(rejected)
    states.push(rejected_model)
    captures.push(outcome_test_browser_state())
    let (again, final_wait) = update(
      emit,
      AcceptedHumanExportAction(Download),
      rejected_model,
    )
    lesson_receipt_test_run(again)
    outcome_test_respond(accepted_human_test_payload().stringify())
    let (download, settled) = update(emit, emitted[2], final_wait)
    lesson_receipt_test_run(download)
    states.push(settled)
    captures.push(outcome_test_browser_state())
  })
  let before = @json.parse(captures[0])
  let after = @json.parse(captures[1])
  assert_eq(dispatch_continuation_array(before, "downloads").length(), 0)
  assert_eq(dispatch_continuation_array(after, "downloads").length(), 1)
  assert_eq(dispatch_continuation_array(after, "requests").length(), 3)
  for state in states {
    assert_false(state.dispatch_accepted_human_export.pending)
  }
  assert_true(
    states[0].dispatch_accepted_human_export.notice.has_prefix("未下载"),
  )
  assert_true(
    states[1].dispatch_accepted_human_export.notice.has_prefix("未下载"),
  )
  assert_eq(states[2].dispatch_accepted_human_export.request, 3)
}

///|
test "accepted human export actual response ignores changed task selection actor report revision and page" {
  let model = accepted_human_test_model()
  let changed = [
    {
      ..model,
      dispatch_task_commitment: {
        "task_id": "task-1",
        "receipts": [
          { "action": "report", "report_id": "report-H1", "revision": 2 },
        ],
      },
    },
    { ..model, dispatch_task_id: "task-2", },
    { ..model, dispatch_task_selection: model.dispatch_task_selection + 1, },
    { ..model, dispatch_task_actor_id: "other-actor", },
    { ..model, dispatch_task_report_id: "older-report", },
    { ..model, page: Delivery, },
    { ..model, dispatch_task_stage: "submitted", },
    {
      ..model,
      dispatch_continuation: { ..model.dispatch_continuation, request: 99, },
    },
    {
      ..model,
      dispatch_continuation: { ..model.dispatch_continuation, revision: 99.0, },
    },
    {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        accepted_report_id: "new-report",
      },
    },
    {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        accepted_delivery_source: human_revision_proj_source(id="H2"),
      },
    },
  ]
  for target in changed {
    let emitted : Array[Msg] = []
    let emit : @rabbita.Emit[Msg] = message => {
      emitted.push(message)
      none
    }
    let captures : Array[String] = []
    outcome_test_browser(() => {
      let (get, waiting) = update(
        emit,
        AcceptedHumanExportAction(Download),
        model,
      )
      lesson_receipt_test_run(get)
      outcome_test_respond(accepted_human_test_payload().stringify())
      let (ignored, _) = update(emit, emitted[0], {
        ..target,
        dispatch_accepted_human_export: waiting.dispatch_accepted_human_export,
      })
      lesson_receipt_test_run(ignored)
      captures.push(outcome_test_browser_state())
    })
    assert_eq(
      dispatch_continuation_array(@json.parse(captures[0]), "downloads").length(),
      0,
    )
  }
}

///|
test "accepted human export report round trip invalidates request and URL changes reject actual callback" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let captures : Array[String] = []
  let states : Array[Model] = []
  outcome_test_browser(() => {
    let (get, waiting) = update(
      emit,
      AcceptedHumanExportAction(Download),
      accepted_human_test_model(),
    )
    lesson_receipt_test_run(get)
    let (_, away) = update(
      emit,
      ContinuationAction(SelectReport("older-report")),
      waiting,
    )
    let (_, back) = update(
      emit,
      ContinuationAction(SelectReport("report-H1")),
      away,
    )
    states.push(back)
    outcome_test_respond(accepted_human_test_payload().stringify())
    let (ignored, _) = update(emit, emitted[0], back)
    lesson_receipt_test_run(ignored)
    captures.push(outcome_test_browser_state())
  })
  assert_false(states[0].dispatch_accepted_human_export.pending)
  assert_eq(states[0].dispatch_task_report_id, "report-H1")
  assert_eq(
    dispatch_continuation_array(@json.parse(captures[0]), "downloads").length(),
    0,
  )
  assert_true(
    accepted_human_test_clock(() => {
      anchor_test_browser("https://proj.test/dispatch?task=task-1", () => {
        let messages : Array[Msg] = []
        let send : @rabbita.Emit[Msg] = message => {
          messages.push(message)
          none
        }
        let (get, waiting) = update(
          send,
          AcceptedHumanExportAction(Download),
          accepted_human_test_model(),
        )
        drafts_test_execute(get)
        anchor_test_move("https://proj.test/dispatch?task=other")
        anchor_test_respond(accepted_human_test_payload().stringify())
        let (_, ignored) = update(send, messages[0], waiting)
        ignored.dispatch_accepted_human_export.expected is Null &&
        !ignored.dispatch_accepted_human_export.pending
      })
    }),
  )
}

///|
extern "js" fn accepted_human_test_clock(run : () -> Bool) -> Bool =
  #| run => {const prior=globalThis.setTimeout;globalThis.__acceptedHumanTimers=[];globalThis.setTimeout=(callback,ms)=>{globalThis.__acceptedHumanTimers.push({callback,ms});return globalThis.__acceptedHumanTimers.length;};try{return run();}finally{globalThis.setTimeout=prior;delete globalThis.__acceptedHumanTimers;}}

///|
extern "js" fn accepted_human_test_timeout() -> Bool =
  #| ()=>{const timer=globalThis.__acceptedHumanTimers.shift();if(!timer)return false;timer.callback();return timer.ms===30000;}

///|
#warnings("-alert_unstable")
test "accepted human export bounded timeout restores retry and fences late transport and timeout callbacks" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let captures : Array[String] = []
  let states : Array[Model] = []
  let timed : Array[Bool] = []
  outcome_test_browser(() => {
    timed.push(
      accepted_human_test_clock(() => {
        let (get, waiting) = update(
          emit,
          AcceptedHumanExportAction(Download),
          accepted_human_test_model(),
        )
        lesson_receipt_test_run(get)
        let fired = accepted_human_test_timeout()
        let (expired, timed_out) = update(emit, emitted[0], waiting)
        lesson_receipt_test_run(expired)
        states.push(timed_out)
        let (retry, retrying) = update(
          emit,
          AcceptedHumanExportAction(Download),
          timed_out,
        )
        lesson_receipt_test_run(retry)
        outcome_test_respond(accepted_human_test_payload().stringify())
        let (late, still_waiting) = update(emit, emitted[1], retrying)
        lesson_receipt_test_run(late)
        states.push(still_waiting)
        captures.push(outcome_test_browser_state())
        outcome_test_respond(accepted_human_test_payload().stringify())
        let (download, done) = update(emit, emitted[2], still_waiting)
        lesson_receipt_test_run(download)
        let fired_again = accepted_human_test_timeout()
        let (late_timeout, settled) = update(emit, emitted[3], done)
        lesson_receipt_test_run(late_timeout)
        states.push(settled)
        captures.push(outcome_test_browser_state())
        fired && fired_again
      }),
    )
  })
  assert_true(timed[0])
  assert_false(states[0].dispatch_accepted_human_export.pending)
  assert_true(
    states[0].dispatch_accepted_human_export.notice.contains("超时"),
  )
  let html = opc_render_cell(
    @rabbita.static_cell(
      dispatch_accepted_human_export_view(_ => none, states[0]),
    ),
  )
  assert_true(html.contains("下载已接受人工修订 JSON"))
  assert_true(states[1].dispatch_accepted_human_export.pending)
  assert_eq(states[1].dispatch_accepted_human_export.request, 2)
  assert_eq(
    dispatch_continuation_array(@json.parse(captures[0]), "downloads").length(),
    0,
  )
  assert_eq(
    dispatch_continuation_array(@json.parse(captures[1]), "downloads").length(),
    1,
  )
  assert_true(
    states[2].dispatch_accepted_human_export.notice.has_prefix("已下载"),
  )
}

///|
#warnings("-alert_unstable")
test "accepted human export view is visible read only human-only and filenames stay bounded" {
  let model = accepted_human_test_model()
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_report_selection_view(_ => none, model)),
  )
  for
    text in [
      "下载已接受人工修订 JSON", "只读文件", "来源观察", "未签名",
      "不授予权限", "Book 的接受状态",
    ] {
    assert_true(html.contains(text), msg=text)
  }
  for
    source in [
      Json::null(),
      continuation_proj_source(),
      {
        "type": "original",
        "original_run_id": "run-1",
        "command_id": "command-1",
      },
    ] {
    let hidden = {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        accepted_delivery_source: source,
      },
    }
    let html = opc_render_cell(
      @rabbita.static_cell(
        dispatch_accepted_human_export_view(_ => none, hidden),
      ),
    )
    assert_false(html.contains("下载已接受人工修订 JSON"))
    let (_, unchanged) = update(
      _ => none,
      AcceptedHumanExportAction(Download),
      hidden,
    )
    assert_eq(unchanged.dispatch_accepted_human_export.request, 0)
  }
  assert_eq(
    dispatch_accepted_human_filename("../task", "H/1?"),
    "moonproj-accepted-human-___task-H_1_.json",
  )
  assert_eq(dispatch_accepted_human_filename_part("x".repeat(500)).length(), 64)
  assert_eq(dispatch_accepted_human_filename_part(""), "unknown")
  for
    task in [
      "",
      ".",
      "..",
      "task/a",
      "task?a",
      "task#a",
      "task%2fpath",
      "task a",
      "a".repeat(129),
    ] {
    assert_false(dispatch_accepted_human_task_id_valid(task), msg=task)
    let (_, unchanged) = update(
      _ => none,
      AcceptedHumanExportAction(Download),
      accepted_human_test_model(task~),
    )
    assert_eq(unchanged.dispatch_accepted_human_export.request, 0)
  }
}
