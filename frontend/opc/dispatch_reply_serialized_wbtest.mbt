///|
extern "js" fn reply_transport_tab() =
  #| ()=>{const state=globalThis.__offerTransport;state.tab=new Map();window.sessionStorage={setItem:(k,v)=>{state.events.push('reply-store');state.tab.set(k,v);},getItem:k=>state.tab.get(k)||null,removeItem:k=>{state.events.push('reply-clear');state.tab.delete(k);}};}

///|
extern "js" fn reply_transport_tab_contents() -> String =
  #| ()=>JSON.stringify([...globalThis.__offerTransport.tab.entries()])

///|
extern "js" fn reply_transport_local_contents() -> String =
  #| ()=>JSON.stringify([...globalThis.__offerTransport.storage.entries()])

///|
test "offer reply compiled transport persists before PUT and retries identical frozen payload" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  let captures : Array[String] = []
  let checks : Array[Bool] = []
  offer_transport_browser(() => {
    reply_transport_tab()
    dispatch_reply_storage_session(
      "actor-offer",
      frozen.dispatch_reply_generation,
    )
    drafts_test_execute(
      dispatch_reply_persist(emit, frozen, draft.task_id, draft.operation_key),
    )
    let (send, sending) = update(emit, emitted[0], frozen)
    drafts_test_execute(send)
    offer_transport_fail()
    let (read, reading) = update(emit, emitted[1], sending)
    drafts_test_execute(read)
    offer_transport_respond(200, reply_ui_body(1, []))
    let (persist, uncertain) = update(emit, emitted[2], reading)
    drafts_test_execute(persist)
    checks.push(dispatch_reply_find(uncertain).unwrap().state == "uncertain")
    let (persist, retrying) = dispatch_reply_update(emit, uncertain, Retry)
    drafts_test_execute(persist)
    let (resend, resent) = update(emit, emitted[4], retrying)
    drafts_test_execute(resend)
    offer_transport_respond(200, "{\"reply_id\":\"reply-event\"}")
    let (read, reading) = update(emit, emitted[5], resent)
    drafts_test_execute(read)
    checks.push(dispatch_reply_find(reading).unwrap().state == "recovering")
    offer_transport_respond(200, reply_ui_body(2, [reply_ui_receipt(draft)]))
    let (persist, saved) = update(emit, emitted[6], reading)
    drafts_test_execute(persist)
    checks.push(dispatch_reply_find(saved).unwrap().state == "saved")
    checks.push(!reply_transport_tab_contents().contains("Please reduce scope"))
    checks.push(reply_transport_local_contents() == "[]")
    let (download, _) = dispatch_offer_update(emit, saved, ExportCanonical)
    drafts_test_execute(download)
    captures.push(offer_transport_state())
  })
  assert_eq(checks, [true, true, true, true, true])
  let capture = @json.parse(captures[0])
  let requests = dispatch_continuation_array(capture, "requests")
  assert_eq(requests.length(), 4)
  assert_eq(dispatch_json_text(requests[0], "method"), "PUT")
  assert_eq(
    dispatch_json_text(requests[0], "url"),
    "/api/company/plan/tasks/offer-task",
  )
  assert_eq(dispatch_json_text(requests[1], "method"), "GET")
  assert_eq(
    dispatch_json_text(requests[1], "url"),
    "/api/company/tasks/offer-task",
  )
  assert_eq(
    dispatch_json_text(requests[0], "body"),
    dispatch_json_text(requests[2], "body"),
  )
  let body = @json.parse(dispatch_json_text(requests[0], "body"))
  assert_eq(dispatch_json_field(body, "reply_base_revision"), Json::number(1))
  assert_eq(
    dispatch_json_field(
      dispatch_json_field(body, "offer_reply"),
      "offer_revision",
    ),
    Json::number(1),
  )
  assert_eq(
    dispatch_json_field(body, "offer_reply"),
    draft.operation_reply.unwrap(),
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(body, "authority"), "capability"),
    "project:task:update",
  )
  if body is Object(fields) {
    assert_eq(fields.length(), 4)
  } else {
    fail("expected body")
  }
  let events = dispatch_json_strings(capture, "events")
  assert_eq(events[0], "reply-store")
  assert_eq(events[1], "PUT")
  for request in requests {
    assert_false(dispatch_json_text(request, "url").contains("Please"))
  }
  let downloads = dispatch_continuation_array(capture, "downloads")
  assert_eq(downloads.length(), 1)
  let markdown = dispatch_json_text(downloads[0], "text")
  assert_false(markdown.contains("Please reduce scope"))
  assert_false(markdown.contains("offer-reply"))
  assert_true(markdown.contains("Task revision: 1"))
  offer_serialized_write(
    "MOONPROJ_REPLY_REQUEST_OUTPUT",
    dispatch_json_text(requests[0], "body"),
  )
  offer_serialized_write("MOONPROJ_REPLY_TRANSPORT_OUTPUT", captures[0])
}

///|
test "offer reply tab draft survives page reload then clears across signout with stale writes rejected" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let model = reply_ui_editing()
  let checks : Array[Bool] = []
  offer_transport_browser(() => {
    reply_transport_tab()
    dispatch_reply_storage_session(
      "actor-offer",
      model.dispatch_reply_generation,
    )
    drafts_test_execute(dispatch_reply_persist(emit, model, "", ""))
    drafts_test_execute(dispatch_reply_session(emit, "", "actor-offer", 1))
    let reloaded = update(emit, emitted[1], {
        ..reply_ui_model(),
        dispatch_reply_generation: 1,
      }).1
    checks.push(
      dispatch_reply_find(reloaded).unwrap().value ==
      dispatch_reply_find(model).unwrap().value,
    )
    let (signout, signed_out) = dispatch_draft_session(emit, reloaded, "")
    drafts_test_execute(signout)
    checks.push(reply_transport_tab_contents() == "[]")
    drafts_test_execute(dispatch_reply_persist(emit, model, "", ""))
    checks.push(reply_transport_tab_contents() == "[]")
    checks.push(signed_out.dispatch_reply_drafts.is_empty())
    let (signin, signed_back) = dispatch_draft_session(
      emit, signed_out, "actor-offer",
    )
    drafts_test_execute(signin)
    let stale = update(emit, emitted[1], signed_back).1
    checks.push(stale.dispatch_reply_drafts.is_empty())
    checks.push(reply_transport_local_contents() == "[]")
  })
  assert_eq(checks, [true, true, true, true, true, true])
}

///|
// Exact bytes come from the actual native gateway/service qualification path.
test "offer reply actual native detail decodes exact receipt before UI success" {
  let text = offer_serialized_read("MOONPROJ_REPLY_DETAIL_INPUT")
  if text.is_empty() {
    return
  }
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  let snapshot = dispatch_decode_snapshot(text, "offer-task").unwrap()
  assert_eq(snapshot.project_id, "offer-project")
  assert_eq(
    dispatch_reply_receipt_revision(snapshot.commitment, draft, "actor-offer"),
    2,
  )
  let reading = dispatch_reply_put(frozen, { ..draft, state: "recovering", })
  let saved = reply_ui_update(
    reading,
    Read("actor-offer", "offer-task", draft.operation_key, 200, text),
  )
  assert_eq(dispatch_reply_find(saved).unwrap().state, "saved")
  assert_eq(dispatch_reply_find(saved).unwrap().saved_revision, 2)
  assert_eq(dispatch_offer_revision(saved.dispatch_offer_task), 2)
  assert_eq(dispatch_offer_canonical_revision(saved), 1)
  assert_eq(saved.dispatch_task_stage, "pending")
  assert_true(saved.dispatch_run is None)
  let rendered = guided_task(saved)
  assert_true(rendered.contains("Please reduce scope"))
  assert_true(rendered.contains("方案版本 1"))
  assert_true(rendered.contains("当前任务版本 2"))
  assert_true(rendered.contains("记录者 · actor-offer"))
  assert_true(rendered.contains("回复者 · 未知"))
  assert_true(rendered.contains("人工观察（没有来源引用）"))
  assert_false(dispatch_reply_store(saved).contains("Please reduce scope"))
  offer_serialized_write("MOONPROJ_REPLY_RENDER_OUTPUT", rendered)
}
