///|
extern "js" fn guidance_serialized_read(variable : String) -> String =
  #| variable=>{const path=globalThis.process?.env?.[variable];return path?require('node:fs').readFileSync(path,'utf8'):'';}

///|
extern "js" fn guidance_serialized_write(text : String) =
  #| text=>{const path=globalThis.process?.env?.MOONPROJ_GUIDANCE_START_OUTPUT;if(path)require('node:fs').writeFileSync(path,text);}

///|
// Qualification runs with the real native Proj query and Book UI return. No
// test reconstruction of the selected payload is allowed at this boundary.
test "actual Book selected guidance passes production Proj bridge reducer and exact Start serialization" {
  let handoff_text = guidance_serialized_read("MOONPROJ_GUIDANCE_HANDOFF_INPUT")
  if handoff_text.is_empty() {
    return
  }
  let selection_text = guidance_serialized_read(
    "MOONPROJ_GUIDANCE_SELECTION_INPUT",
  )
  assert_false(selection_text.is_empty())
  let handoff = @json.parse(handoff_text)
  let selection = @json.parse(selection_text)
  let task = @json.parse(dispatch_json_text(handoff, "task_snapshot"))
  let task_id = dispatch_json_text(task, "task_id")
  let base = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: task_id,
    dispatch_task_actor_id: "guidance-qualification-actor",
    dispatch_task_project_id: dispatch_json_text(task, "project_id"),
    dispatch_task_product_id: dispatch_json_text(task, "product_id"),
    dispatch_task_selection: 71,
    dispatch_task_stage: "pending",
    dispatch_continuation: {
      ..empty_dispatch_continuation(),
      task_id,
      actor: "guidance-qualification-actor",
      selection: 71,
      revision: dispatch_continuation_revision(task),
    },
  }
  let context = dispatch_guidance_context(base)
  assert_eq(dispatch_guidance_query(handoff_text, context), Ok(handoff))
  let origin = dispatch_json_text(selection, "book_origin")
  let states = [
    {
      ..base,
      dispatch_guidance: {
        ..empty_dispatch_guidance(),
        context: Some(context),
        request: 81,
        phase: "waiting",
        handoff: Some(handoff),
        origin,
      },
    },
  ]
  let browser = lesson_sender_test_browser()
  let _ = dispatch_guidance_connect_book_on(
    browser,
    origin,
    handoff_text,
    (text, acknowledge) => {
      let (cmd, next) = update(
        _ => none,
        GuidanceAction(Returned(context, 81, origin, text, acknowledge)),
        states[0],
      )
      states[0] = next
      lesson_receipt_test_run(cmd)
    },
    _ => (),
  )
  lesson_sender_test_event(
    browser, origin, true, "test-nonce", "moonbook.guidance-ready.v1", "",
  )
  lesson_sender_test_event(
    browser, origin, true, "test-nonce", "moonbook.guidance-selection.v1", selection_text,
  )
  assert_eq(states[0].dispatch_guidance.selected, Some(selection))
  assert_eq(dispatch_guidance_start_blocker(states[0]), "")
  let body = dispatch_start_body(states[0])
  assert_eq(dispatch_json_field(body, "book_guidance"), selection)
  assert_false(dispatch_draft_store(states[0]).contains("book_guidance"))
  let calls = dispatch_continuation_array(
    @json.parse(lesson_sender_test_state(browser)),
    "calls",
  )
  assert_eq(calls.length(), 2)
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[1], "value"), "payload"),
    selection_text,
  )
  let (_, starting) = update(_ => none, StartDispatchTask, states[0])
  assert_eq(starting.dispatch_guidance.start_body, Some(body))
  guidance_serialized_write(body.stringify())
}
