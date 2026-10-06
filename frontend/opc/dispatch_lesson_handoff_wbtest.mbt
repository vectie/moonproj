///|
extern "js" fn lesson_sender_unavailable_api(
  browser : LessonHandoffBrowser,
  failure : String,
) =
  #| (browser,failure) => { if(failure==='missing-crypto'){browser.crypto={};} if(failure==='throwing-crypto'){browser.crypto={randomUUID:()=>{throw Error('nonce unavailable');}};} if(failure==='throwing-popup'){browser.open=()=>{throw Error('popup unavailable');};} if(failure==='blocked-popup'){browser.open=()=>null;} }

///|
extern "js" fn lesson_sender_capture_throw(action : () -> Unit) -> String =
  #| action => { try { action(); return ''; } catch(error) { return String(error); } }

///|
test "unavailable secure nonce and denied popup release pending and retain file fallback" {
  for
    failure in [
      "missing-crypto", "throwing-crypto", "throwing-popup", "blocked-popup",
    ] {
    let browser = lesson_sender_test_browser()
    lesson_sender_unavailable_api(browser, failure)
    let results : Array[String] = []
    let thrown = lesson_sender_capture_throw(fn() {
      dispatch_lesson_open_book_on(
        browser,
        "https://book.example",
        "private payload",
        result => results.push(result),
      )
    })
    assert_eq(thrown, "", msg=failure)
    assert_eq(results, ["{}"], msg="Complete fallback exactly once: " + failure)
    let browser_state = @json.parse(lesson_sender_test_state(browser))
    assert_eq(dispatch_continuation_array(browser_state, "calls").length(), 0)
    assert_eq(
      dispatch_json_field(browser_state, "listening"),
      Json::boolean(false),
    )
    assert_eq(dispatch_json_field(browser_state, "timer"), Json::boolean(false))
    let payload = lesson_proj_test_payload()
    let model = {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_id: "task-fixture",
      dispatch_task_report_id: "report-fixture",
      dispatch_task_stage: "accepted",
      dispatch_task_selection: 4,
      dispatch_lesson_handoff: {
        ..empty_dispatch_lesson_handoff(),
        task_id: "task-fixture",
        selection: 4,
        request: 9,
        pending: true,
        payload: Some(payload),
      },
    }
    let emit : @rabbita.Emit[Msg] = _ => none
    let (_, recovered) = dispatch_lesson_handoff_update(
      emit,
      model,
      Readback("task-fixture", 4, 9, results[0]),
    )
    assert_false(recovered.dispatch_lesson_handoff.pending)
    assert_eq(recovered.dispatch_lesson_handoff.payload, Some(payload))
    assert_true(
      recovered.dispatch_lesson_handoff.notice.contains("下载交接文件"),
    )
    assert_true(dispatch_lesson_current(recovered))
  }
}

///|
fn lesson_proj_test_payload() -> Json {
  {
    "contract_version": "moonproj.book-lesson-handoff.v1",
    "source_product": "moonproj",
    "task": {
      "record_id": "task-fixture",
      "record_version": "3",
      "record_digest": "sha256:task-fixture",
    },
    "report": { "record_id": "report-fixture" },
    "task_snapshot": "private task text",
    "report_snapshot": "private report text",
    "authorizing": false,
    "customer_acceptance": "not_asserted",
    "cash": "not_asserted",
  }
}

///|
test "lesson sender binds current task report and exact receiver echo" {
  let payload = lesson_proj_test_payload()
  assert_eq(
    dispatch_lesson_payload(
      payload.stringify(),
      "task-fixture",
      "report-fixture",
    ),
    Ok(payload),
  )
  assert_true(
    dispatch_lesson_payload(payload.stringify(), "other", "report-fixture")
    is Err(_),
  )
  assert_true(
    dispatch_lesson_payload(payload.stringify(), "task-fixture", "other")
    is Err(_),
  )
  let receipt : Json = {
    "contract_version": "moonbook.task-lesson-readback.v1",
    "handoff": payload,
    "state": "reviewed_source_available",
    "activation_authorized": false,
    "external_side_effects_applied": false,
  }
  assert_true(
    dispatch_lesson_readback(payload, receipt.stringify()).contains(
      "已读回准确",
    ),
  )
  assert_true(
    dispatch_lesson_readback(Json::null(), receipt.stringify()).contains(
      "尚未确认",
    ),
  )
}

///|
test "lesson sender stale completion cannot cross selected task or revision request" {
  let initial = initial_model()
  let current = {
    ..initial,
    page: Dispatch,
    dispatch_task_id: "task-fixture",
    dispatch_task_report_id: "report-fixture",
    dispatch_task_stage: "accepted",
    dispatch_task_selection: 4,
    dispatch_lesson_handoff: {
      ..empty_dispatch_lesson_handoff(),
      task_id: "task-fixture",
      selection: 4,
      request: 8,
      pending: true,
    },
  }
  let emit : @rabbita.Emit[Msg] = _ => none
  let (_, stale) = dispatch_lesson_handoff_update(
    emit,
    current,
    Loaded("task-fixture", 4, 7, Ok(lesson_proj_test_payload().stringify())),
  )
  assert_true(stale.dispatch_lesson_handoff.payload is None)
  let (_, other) = dispatch_lesson_handoff_update(
    emit,
    { ..current, dispatch_task_selection: 5, },
    Loaded("task-fixture", 4, 8, Ok(lesson_proj_test_payload().stringify())),
  )
  assert_true(other.dispatch_lesson_handoff.payload is None)
  let prepared = {
    ..current,
    dispatch_lesson_handoff: {
      ..current.dispatch_lesson_handoff,
      pending: false,
      payload: Some(lesson_proj_test_payload()),
    },
  }
  assert_true(dispatch_lesson_current(prepared))
  assert_false(
    dispatch_lesson_current({
      ..prepared,
      dispatch_task_report_id: "new-accepted-report",
    }),
  )
}

///|
extern "js" fn lesson_sender_test_browser() -> LessonHandoffBrowser =
  #| () => { const b={location:{origin:'https://proj.example'},crypto:{randomUUID:()=> 'test-nonce'},calls:[],listener:null,timer:null}; b.child={postMessage:(value,origin)=>b.calls.push({value,origin})}; b.open=url=>{b.url=url;return b.child;}; b.addEventListener=(_,f)=>b.listener=f;b.removeEventListener=()=>b.listener=null;b.setTimeout=f=>{b.timer=f;return 1;};b.clearTimeout=()=>b.timer=null;return b; }

///|
extern "js" fn lesson_sender_test_event(
  browser : LessonHandoffBrowser,
  origin : String,
  correct_window : Bool,
  nonce : String,
  kind : String,
  payload : String,
) =
  #| (b,origin,correct,nonce,kind,payload) => {b.listener?.({origin,source:correct?b.child:{},data:{nonce,kind,payload}});}

///|
extern "js" fn lesson_sender_test_state(
  browser : LessonHandoffBrowser,
) -> String =
  #| b => JSON.stringify({url:b.url||'',calls:b.calls,listening:!!b.listener,timer:!!b.timer})

///|
test "direct lesson sender uses explicit origin no URL payload and exact browser correlation" {
  let browser = lesson_sender_test_browser()
  let results : Array[String] = []
  dispatch_lesson_open_book_on(
    browser,
    "https://book.example",
    "private report payload",
    result => results.push(result),
  )
  for
    (origin, window, nonce) in [
      ("https://wrong.example", true, "test-nonce"),
      ("https://book.example", false, "test-nonce"),
      ("https://book.example", true, "wrong"),
    ] {
    lesson_sender_test_event(
      browser, origin, window, nonce, "moonbook.lesson-ready.v1", "",
    )
  }
  let before = @json.parse(lesson_sender_test_state(browser))
  assert_eq(dispatch_continuation_array(before, "calls").length(), 0)
  assert_false(dispatch_json_text(before, "url").contains("private"))
  assert_false(dispatch_json_text(before, "url").contains("report"))
  assert_true(dispatch_json_text(before, "url").contains("proj_lesson_source="))
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-ready.v1",
    "",
  )
  assert_eq(
    dispatch_continuation_array(
      @json.parse(lesson_sender_test_state(browser)),
      "calls",
    ).length(),
    1,
  )
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.lesson-readback.v1",
    "exact-receipt",
  )
  assert_eq(results, ["exact-receipt"])
  assert_eq(
    dispatch_json_field(
      @json.parse(lesson_sender_test_state(browser)),
      "listening",
    ),
    Json::boolean(false),
  )
  for
    origin in [
      "", "javascript:alert(1)", "https://user:secret@book.example", "https://book.example/another-app",
      "https://book.example/?query=1",
    ] {
    let rejected = lesson_sender_test_browser()
    dispatch_lesson_open_book_on(rejected, origin, "private", _ => ())
    assert_eq(
      dispatch_json_text(@json.parse(lesson_sender_test_state(rejected)), "url"),
      "",
    )
  }
}
