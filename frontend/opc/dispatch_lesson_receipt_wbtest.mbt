///|
fn lesson_receipt_test_ref(id : String) -> Json {
  { "record_id": id, "record_version": "1", "record_digest": "sha256:" + id }
}

///|
fn lesson_receipt_test_set(
  value : Json,
  key : String,
  replacement : Json,
) -> Json {
  match value {
    Object(fields) => {
      let fields = fields.copy()
      fields[key] = replacement
      Json::object(fields)
    }
    _ => value
  }
}

///|
fn lesson_receipt_test_payload() -> Json {
  lesson_receipt_test_set(
    lesson_proj_test_payload(),
    "report",
    lesson_receipt_test_ref("report-fixture"),
  )
}

///|
fn lesson_receipt_test_return(state : String, currentness : String) -> Json {
  let payload = lesson_receipt_test_payload()
  let lesson = lesson_receipt_test_ref("lesson-fixture")
  {
    "contract_version": "moonbook.saved-lesson-return.v1",
    "book_origin": "https://book.example",
    "observed_at": 1791151200,
    "receipt": {
      "contract_version": "moonbook.saved-lesson-receipt.v1",
      "source_product": "moonbook",
      "destination_product": "moonproj",
      "task": dispatch_json_field(payload, "task"),
      "report": dispatch_json_field(payload, "report"),
      "submission": lesson_receipt_test_ref("submission"),
      "outcome": lesson_receipt_test_ref("outcome"),
      "assessment": lesson_receipt_test_ref("assessment"),
      "assessment_review": lesson_receipt_test_ref("assessment-review"),
      "lesson": lesson,
      "lesson_id": "lesson-family",
      "title": "Saved lesson",
      "state": state,
      "review": if state == "pending" {
        Json::null()
      } else {
        {
          "receipt": lesson_receipt_test_ref("lesson-review"),
          "disposition": if state == "retained" {
            "Accept"
          } else {
            "Reject"
          },
          "reviewer_id": "named-reviewer",
          "decided_at": 1791151100,
        }
      },
      "current": if currentness == "current" {
        lesson
      } else if currentness == "legacy_unselected" {
        Json::null()
      } else {
        lesson_receipt_test_ref("other-current-lesson")
      },
      "selection_review": Json::null(),
      "currentness": currentness,
      "journal_sequence": 18,
      "activation_authorized": false,
      "external_side_effects_applied": false,
      "customer_acceptance": "not_asserted",
      "cash": "not_asserted",
    },
  }
}

///|
fn lesson_receipt_test_model() -> Model {
  {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-fixture",
    dispatch_task_report_id: "report-fixture",
    dispatch_task_selection: 4,
    dispatch_task_stage: "accepted",
    dispatch_lesson_handoff: {
      ..empty_dispatch_lesson_handoff(),
      task_id: "task-fixture",
      selection: 4,
      request: 9,
      receipt_waiting: true,
      payload: Some(lesson_receipt_test_payload()),
      origin: "https://book.example",
    },
  }
}

///|
test "saved lesson decoder separates pending rejected retained and currentness without authorizing" {
  let payload = lesson_receipt_test_payload()
  for
    (state, currentness) in [
      ("pending", "not_retained"),
      ("rejected", "not_retained"),
      ("retained", "current"),
      ("retained", "historical"),
      ("retained", "legacy_unselected"),
    ] {
    let value = lesson_receipt_test_return(state, currentness)
    assert_eq(
      dispatch_lesson_receipt_decode(
        payload,
        "https://book.example",
        None,
        value.stringify(),
      ),
      Ok(value),
    )
    assert_false(value.stringify().contains("guidance"))
    assert_false(value.stringify().contains("private task text"))
  }
  let minimal_ack : Json = {
    "contract_version": "moonbook.task-lesson-readback.v1",
    "handoff": payload,
    "state": "reviewed_source_available",
    "activation_authorized": false,
    "external_side_effects_applied": false,
  }
  assert_true(
    dispatch_lesson_receipt_decode(payload, "", None, minimal_ack.stringify())
    is Err(_),
  )
}

///|
test "saved lesson receipt rejects exact reference mismatches excessive content and inconsistent decisions" {
  let payload = lesson_receipt_test_payload()
  let valid = lesson_receipt_test_return("retained", "current")
  let receipt = dispatch_json_field(valid, "receipt")
  for reference in ["task", "report"] {
    for key in ["record_id", "record_version", "record_digest"] {
      let wrong = lesson_receipt_test_set(
        dispatch_json_field(receipt, reference),
        key,
        "wrong",
      )
      let value = lesson_receipt_test_set(
        valid,
        "receipt",
        lesson_receipt_test_set(receipt, reference, wrong),
      )
      assert_true(
        dispatch_lesson_receipt_decode(payload, "", None, value.stringify())
        is Err(_),
        msg=reference + key,
      )
    }
  }
  for
    (key, wrong) in [
      ("state", Json::string("ambiguous")),
      ("review", Json::null()),
      ("activation_authorized", Json::boolean(true)),
      ("external_side_effects_applied", Json::boolean(true)),
      ("currentness", Json::string("historical")),
      ("guidance", Json::string("must never cross")),
      ("journal_sequence", Json::number(-1)),
    ] {
    let value = lesson_receipt_test_set(
      valid,
      "receipt",
      lesson_receipt_test_set(receipt, key, wrong),
    )
    assert_true(
      dispatch_lesson_receipt_decode(payload, "", None, value.stringify())
      is Err(_),
      msg=key,
    )
  }
  for
    origin in [
      "https://wrong.example", "https://book.example/", "https://user:pass@book.example",
      "javascript:alert(1)",
    ] {
    let value = lesson_receipt_test_set(
      valid,
      "book_origin",
      Json::string(origin),
    )
    assert_true(
      dispatch_lesson_receipt_decode(
        payload,
        "https://book.example",
        None,
        value.stringify(),
      )
      is Err(_),
    )
  }
  assert_true(
    dispatch_lesson_receipt_decode(
      payload,
      "",
      Some(lesson_receipt_test_ref("different-lesson")),
      valid.stringify(),
    )
    is Err(_),
  )
  let bad_reviewer = lesson_receipt_test_set(
    dispatch_json_field(receipt, "review"),
    "reviewer_id",
    "",
  )
  assert_true(
    dispatch_lesson_receipt_decode(
      payload,
      "",
      None,
      lesson_receipt_test_set(
        valid,
        "receipt",
        lesson_receipt_test_set(receipt, "review", bad_reviewer),
      ).stringify(),
    )
    is Err(_),
  )
}

///|
test "saved lesson UI ignores stale task report selection request and page responses" {
  let model = lesson_receipt_test_model()
  let returned = lesson_receipt_test_return("retained", "current").stringify()
  let emit : @rabbita.Emit[Msg] = _ => none
  for
    (task, selection, request) in [
      ("other", 4, 9),
      ("task-fixture", 5, 9),
      ("task-fixture", 4, 8),
    ] {
    let (_, result) = dispatch_lesson_handoff_update(
      emit,
      model,
      ReceiptReturned(
        task,
        selection,
        request,
        "https://book.example",
        returned,
        _ => try! fail("stale ack"),
      ),
    )
    assert_true(result.dispatch_lesson_handoff.receipt is None)
  }
  let (_, result) = dispatch_lesson_handoff_update(
    emit,
    { ..model, dispatch_task_report_id: "new-report", },
    ReceiptReturned("task-fixture", 4, 9, "https://book.example", returned, _ => {
      try! fail("stale ack")
    }),
  )
  assert_true(result.dispatch_lesson_handoff.receipt is None)
  let (_, result) = dispatch_lesson_handoff_update(
    emit,
    { ..model, page: Overview, },
    ReceiptReturned("task-fixture", 4, 9, "https://book.example", returned, _ => {
      try! fail("stale ack")
    }),
  )
  assert_true(result.dispatch_lesson_handoff.receipt is None)
  let (_, accepted) = dispatch_lesson_handoff_update(
    emit,
    model,
    ReceiptReturned("task-fixture", 4, 9, "https://book.example", returned, _ => {
      ()
    }),
  )
  assert_true(accepted.dispatch_lesson_handoff.receipt is Some(_))
  assert_true(accepted.dispatch_lesson_handoff.receipt_direct)
  assert_false(accepted.dispatch_lesson_handoff.receipt_waiting)
  assert_eq(accepted.dispatch_task_stage, model.dispatch_task_stage)
  assert_eq(accepted.dispatch_task_report_id, model.dispatch_task_report_id)
  assert_eq(
    accepted.dispatch_lesson_handoff.payload,
    model.dispatch_lesson_handoff.payload,
  )
}

///|
test "file receipt is historical observation and bad import keeps exact prior receipt" {
  let value = lesson_receipt_test_return("retained", "historical")
  let model = lesson_receipt_test_model()
  let importing = {
    ..model,
    dispatch_lesson_handoff: { ..model.dispatch_lesson_handoff, pending: true, },
  }
  let emit : @rabbita.Emit[Msg] = _ => none
  let (_, imported) = dispatch_lesson_handoff_update(
    emit,
    importing,
    ReceiptImported("task-fixture", 4, 9, value.stringify()),
  )
  assert_eq(imported.dispatch_lesson_handoff.receipt, Some(value))
  assert_false(imported.dispatch_lesson_handoff.receipt_direct)
  assert_false(imported.dispatch_lesson_handoff.pending)
  let again = {
    ..imported,
    dispatch_lesson_handoff: {
      ..imported.dispatch_lesson_handoff,
      pending: true,
    },
  }
  let (_, failed) = dispatch_lesson_handoff_update(
    emit,
    again,
    ReceiptImported("task-fixture", 4, 9, "bad json"),
  )
  assert_eq(failed.dispatch_lesson_handoff.receipt, Some(value))
  assert_eq(
    failed.dispatch_lesson_handoff.payload,
    model.dispatch_lesson_handoff.payload,
  )
  let (_, reopened) = dispatch_lesson_handoff_update(
    emit,
    imported,
    ReopenLesson,
  )
  assert_eq(
    reopened.dispatch_lesson_handoff.receipt_target,
    Some(dispatch_json_field(dispatch_json_field(value, "receipt"), "lesson")),
  )
  assert_true(reopened.dispatch_lesson_handoff.receipt_waiting)
  assert_false(reopened.dispatch_lesson_handoff.receipt_direct)
}

///|
extern "js" fn lesson_receipt_browser_timeout(browser : LessonHandoffBrowser) =
  #| b => b.timer?.()

///|
extern "js" fn lesson_receipt_browser_closed(browser : LessonHandoffBrowser) =
  #| b => {b.child.closed=true;}

///|
fn lesson_receipt_test_run(cmd : Cmd) -> Unit {
  opc_run_cmd(cmd)
}

///|
test "only current validated receipt reducer executes return acknowledgement" {
  let model = lesson_receipt_test_model()
  let text = lesson_receipt_test_return("retained", "current").stringify()
  let accepted : Array[Bool] = []
  let emit : @rabbita.Emit[Msg] = _ => none
  let (command, _) = dispatch_lesson_handoff_update(
    emit,
    model,
    ReceiptReturned("task-fixture", 4, 8, "https://book.example", text, value => {
      accepted.push(value)
    }),
  )
  lesson_receipt_test_run(command)
  assert_true(accepted.is_empty())
  let (command, _) = dispatch_lesson_handoff_update(
    emit,
    model,
    ReceiptReturned("task-fixture", 4, 9, "https://book.example", "{}", value => {
      accepted.push(value)
    }),
  )
  lesson_receipt_test_run(command)
  assert_true(accepted.is_empty())
  let (command, _) = dispatch_lesson_handoff_update(
    emit,
    model,
    ReceiptReturned("task-fixture", 4, 9, "https://book.example", text, value => {
      accepted.push(value)
    }),
  )
  assert_true(accepted.is_empty())
  lesson_receipt_test_run(command)
  assert_eq(accepted, [true])
}

///|
#warnings("-alert_unstable")
test "saved receipt UI escapes title labels observations and leaves explicit import reopen controls" {
  let returned = lesson_receipt_test_return("retained", "historical")
  let receipt = lesson_receipt_test_set(
    dispatch_json_field(returned, "receipt"),
    "title",
    "Saved <script>lesson</script>",
  )
  let value = lesson_receipt_test_set(returned, "receipt", receipt)
  let state = { ..empty_dispatch_lesson_handoff(), receipt: Some(value), }
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_lesson_receipt_view(_ => none, state)),
  )
  assert_true(html.contains("导入 / 已缓存观察"))
  assert_true(html.contains("historical"))
  assert_true(html.contains("named-reviewer"))
  assert_true(html.contains("Reopen in this Book"))
  assert_false(html.contains("<script>"))
  let fresh = opc_render_cell(
    @rabbita.static_cell(
      dispatch_lesson_receipt_view(_ => none, { ..state, receipt_direct: true, }),
    ),
  )
  assert_true(fresh.contains("本次 Book 主机读回"))
  assert_false(fresh.contains("导入 / 已缓存观察"))
}

///|
test "production receipt bridge releases authoring after minimal ack and returns exact selected lesson only by explicit action" {
  let browser = lesson_sender_test_browser()
  let payload = lesson_receipt_test_payload()
  let value = lesson_receipt_test_return("retained", "current")
  let selected = dispatch_json_field(
    dispatch_json_field(value, "receipt"),
    "lesson",
  )
  let sources : Array[String] = []
  let results : Array[String] = []
  let closed : Array[String] = []
  dispatch_lesson_connect_book_on(
    browser,
    "https://book.example",
    payload.stringify(),
    selected.stringify(),
    true,
    source => sources.push(source),
    (text, ack) => {
      if dispatch_lesson_receipt_decode(
          payload,
          "https://book.example",
          Some(selected),
          text,
        )
        is Ok(_) {
        results.push(text)
        ack(true)
      }
    },
    reason => closed.push(reason),
  )
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-ready.v1",
    "",
  )
  let calls = dispatch_continuation_array(
    @json.parse(lesson_sender_test_state(browser)),
    "calls",
  )
  assert_eq(
    dispatch_json_field(
      dispatch_json_field(calls[0], "value"),
      "selected_lesson",
    ),
    selected,
  )
  assert_false(
    dispatch_json_text(@json.parse(lesson_sender_test_state(browser)), "url").contains(
      "lesson-fixture",
    ),
  )
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-readback.v1",
    "minimal-ack",
  )
  assert_eq(sources, ["minimal-ack"])
  assert_true(results.is_empty())
  assert_eq(
    dispatch_json_field(
      @json.parse(lesson_sender_test_state(browser)),
      "listening",
    ),
    Json::boolean(true),
  )
  for
    (origin, correct, nonce) in [
      ("https://wrong.example", true, "test-nonce"),
      ("https://book.example", false, "test-nonce"),
      ("https://book.example", true, "wrong"),
    ] {
    lesson_sender_test_event(
      browser,
      origin,
      correct,
      nonce,
      "moonbook.saved-lesson-return.v1",
      value.stringify(),
    )
  }
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.saved-lesson-return.v1",
    "{}",
  )
  assert_true(results.is_empty())
  assert_eq(
    dispatch_continuation_array(
      @json.parse(lesson_sender_test_state(browser)),
      "calls",
    ).length(),
    1,
  )
  lesson_sender_test_event(
    browser,
    "https://book.example",
    true,
    "test-nonce",
    "moonbook.saved-lesson-return.v1",
    value.stringify(),
  )
  assert_eq(results, [value.stringify()])
  assert_eq(closed, ["received"])
  let calls = dispatch_continuation_array(
    @json.parse(lesson_sender_test_state(browser)),
    "calls",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[1], "value"), "kind"),
    "moonproj.saved-lesson-received.v1",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[1], "value"), "payload"),
    value.stringify(),
  )
  assert_eq(
    dispatch_json_field(
      @json.parse(lesson_sender_test_state(browser)),
      "listening",
    ),
    Json::boolean(false),
  )
  lesson_sender_test_event(
    browser,
    "https://book.example",
    true,
    "test-nonce",
    "moonbook.saved-lesson-return.v1",
    value.stringify(),
  )
  assert_eq(results.length(), 1)
}

///|
test "production receipt bridge source timeout receipt timeout and popup failures retain bounded recovery" {
  for acknowledged in [false, true] {
    let browser = lesson_sender_test_browser()
    let sources : Array[String] = []
    let closed : Array[String] = []
    dispatch_lesson_connect_book_on(
      browser,
      "https://book.example",
      "payload",
      "null",
      true,
      source => sources.push(source),
      (_, _) => try! fail("no return expected"),
      reason => closed.push(reason),
    )
    if acknowledged {
      lesson_sender_test_event(
        browser, "https://book.example", true, "test-nonce", "moonbook.lesson-readback.v1",
        "ack",
      )
    }
    lesson_receipt_browser_timeout(browser)
    assert_eq(sources, [if acknowledged { "ack" } else { "{}" }])
    assert_eq(closed, ["timeout"])
    assert_eq(
      dispatch_json_field(
        @json.parse(lesson_sender_test_state(browser)),
        "listening",
      ),
      Json::boolean(false),
    )
  }
  for
    failure in [
      "missing-crypto", "throwing-crypto", "throwing-popup", "blocked-popup",
    ] {
    let browser = lesson_sender_test_browser()
    lesson_sender_unavailable_api(browser, failure)
    let sources : Array[String] = []
    let closed : Array[String] = []
    dispatch_lesson_connect_book_on(
      browser,
      "https://book.example",
      "payload",
      "null",
      true,
      source => sources.push(source),
      (_, _) => try! fail("no return expected"),
      reason => closed.push(reason),
    )
    assert_eq(sources, ["{}"])
    assert_eq(closed, ["unavailable"])
  }
  let browser = lesson_sender_test_browser()
  let closed : Array[String] = []
  dispatch_lesson_connect_book_on(
    browser,
    "https://book.example",
    "payload",
    "null",
    true,
    _ => (),
    (_, _) => try! fail("no return expected"),
    reason => closed.push(reason),
  )
  lesson_receipt_browser_closed(browser)
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-ready.v1",
    "",
  )
  assert_eq(closed, ["closed"])
}
