///|
extern "js" fn lesson_receipt_serialized_fixture(suffix : String) -> String =
  #| suffix=>{const path=globalThis.process?.env?.MOONPROJ_LESSON_FIXTURE_OUTPUT;return path?require('node:fs').readFileSync(path+suffix,'utf8'):'';}

///|
// Qualification enables the shared fixture path after the native producer,
// Book journal resolver and production Book UI have written their actual bytes.
test "actual native Book and production Book UI receipt crosses production Proj bridge reducer and file decoder" {
  let source = lesson_receipt_serialized_fixture("")
  if source.is_empty() {
    return
  }
  let payload = @json.parse(source)
  let text = lesson_receipt_serialized_fixture(".saved-return-ui.json")
  let returned = @json.parse(text)
  let receipt = dispatch_json_field(returned, "receipt")
  let task = dispatch_json_text(
    dispatch_json_field(payload, "task"),
    "record_id",
  )
  let report = dispatch_json_text(
    dispatch_json_field(payload, "report"),
    "record_id",
  )
  assert_eq(dispatch_lesson_payload(source, task, report), Ok(payload))
  assert_eq(
    dispatch_lesson_receipt_decode(payload, "https://book.example", None, text),
    Ok(returned),
  )
  let states = [
    {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_id: task,
      dispatch_task_report_id: report,
      dispatch_task_selection: 17,
      dispatch_task_stage: "accepted",
      dispatch_lesson_handoff: {
        ..empty_dispatch_lesson_handoff(),
        task_id: task,
        selection: 17,
        request: 23,
        pending: true,
        receipt_waiting: true,
        payload: Some(payload),
        origin: "https://book.example",
      },
    },
  ]
  let emit : @rabbita.Emit[Msg] = _ => none
  let browser = lesson_sender_test_browser()
  dispatch_lesson_connect_book_on(
    browser,
    "https://book.example",
    payload.stringify(),
    "null",
    true,
    source => {
      let (cmd, next) = dispatch_lesson_handoff_update(
        emit,
        states[0],
        Readback(task, 17, 23, source),
      )
      states[0] = next
      lesson_receipt_test_run(cmd)
    },
    (response, ack) => {
      let (cmd, next) = dispatch_lesson_handoff_update(
        emit,
        states[0],
        ReceiptReturned(task, 17, 23, "https://book.example", response, ack),
      )
      states[0] = next
      lesson_receipt_test_run(cmd)
    },
    reason => {
      let (cmd, next) = dispatch_lesson_handoff_update(
        emit,
        states[0],
        ReceiptEnded(task, 17, 23, reason),
      )
      states[0] = next
      lesson_receipt_test_run(cmd)
    },
  )
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-ready.v1",
    "",
  )
  let source_ack : Json = {
    "contract_version": "moonbook.task-lesson-readback.v1",
    "handoff": payload,
    "state": "reviewed_source_available",
    "activation_authorized": false,
    "external_side_effects_applied": false,
  }
  lesson_sender_test_event(
    browser,
    "https://book.example",
    true,
    "test-nonce",
    "moonbook.lesson-readback.v1",
    source_ack.stringify(),
  )
  assert_false(states[0].dispatch_lesson_handoff.pending)
  assert_true(states[0].dispatch_lesson_handoff.receipt_waiting)
  assert_true(states[0].dispatch_lesson_handoff.receipt is None)
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.saved-lesson-return.v1",
    text,
  )
  let accepted = states[0]
  assert_eq(accepted.dispatch_lesson_handoff.receipt, Some(returned))
  assert_true(accepted.dispatch_lesson_handoff.receipt_direct)
  assert_false(accepted.dispatch_lesson_handoff.receipt_waiting)
  assert_eq(dispatch_json_text(receipt, "state"), "retained")
  assert_eq(dispatch_json_text(receipt, "currentness"), "current")
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
    text,
  )
  let (_, imported) = dispatch_lesson_handoff_update(
    emit,
    {
      ..accepted,
      dispatch_lesson_handoff: {
        ..accepted.dispatch_lesson_handoff,
        pending: true,
      },
    },
    ReceiptImported(task, 17, 23, text),
  )
  assert_eq(imported.dispatch_lesson_handoff.receipt, Some(returned))
  assert_false(imported.dispatch_lesson_handoff.receipt_direct)
  assert_eq(imported.dispatch_task_stage, "accepted")
  assert_eq(imported.dispatch_task_report_id, report)
  assert_eq(imported.dispatch_lesson_handoff.payload, Some(payload))
}
