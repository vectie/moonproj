///|
// Regression: the pre-Start task card has no way to explicitly query reviewed
// Book guidance. This uses only the existing task card and Start-body APIs.
#warnings("-alert_unstable")
test "formal task offers optional reviewed Book guidance before first Start" {
  let model = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-guidance",
    dispatch_task_actor_id: "actor-guidance",
    dispatch_task_project_id: "project-guidance",
    dispatch_task_product_id: "moonproj",
    dispatch_task_stage: "pending",
    dispatch_task_selection: 4,
    dispatch_continuation: {
      ..empty_dispatch_continuation(),
      task_id: "task-guidance",
      actor: "actor-guidance",
      selection: 4,
      revision: 3.0,
    },
  }
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_durable_task_card(_ => none, model)),
  )
  assert_true(html.contains("可选：复用 Book 已审核经验"))
  assert_true(
    dispatch_json_field(dispatch_start_body(model), "book_guidance") is Null,
  )
  assert_true(dispatch_can_start(model))
}

///|
fn guidance_test_model() -> Model {
  {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-guidance",
    dispatch_task_actor_id: "actor-guidance",
    dispatch_task_project_id: "project-guidance",
    dispatch_task_product_id: "moonproj",
    dispatch_task_stage: "pending",
    dispatch_task_selection: 4,
    dispatch_continuation: {
      ..empty_dispatch_continuation(),
      task_id: "task-guidance",
      actor: "actor-guidance",
      selection: 4,
      revision: 3.0,
    },
  }
}

///|
fn guidance_test_ref(id : String) -> Json {
  {
    "record_id": id,
    "record_version": "3",
    "record_digest": "sha256:" + "a".repeat(64),
  }
}

///|
fn guidance_test_handoff() -> Json {
  {
    "contract_version": "moonproj.book-guidance-query.v1",
    "source_product": "moonproj",
    "target_task": guidance_test_ref("task-guidance"),
    "task_snapshot": (
      {
        "task_id": "task-guidance",
        "project_id": "project-guidance",
        "product_id": "moonproj",
        "revision": 3,
      } : Json).stringify(),
    "conditions": [
      { "key": "project_id", "value": "project-guidance" },
      { "key": "suite_product_id", "value": "moonproj" },
    ],
    "authorizing": false,
  }
}

///|
fn guidance_test_selection() -> Json {
  let handoff = guidance_test_handoff()
  {
    "contract_version": "moonbook.task-guidance-selection.v1",
    "handoff": handoff,
    "query": {
      "contract_version": "moonbook.outcome-lesson-query.v1",
      "target_task": dispatch_json_field(handoff, "target_task"),
      "conditions": dispatch_json_field(handoff, "conditions"),
    },
    "lesson": {
      "reference": guidance_test_ref("lesson-selected"),
      "title": "Reviewed advice <script>",
      "guidance": "GUIDANCE_PRIVATE_TEXT: test the narrow change first <script>",
      "applicability": [{ "key": "suite_product_id", "value": "moonproj" }],
      "invalidation": [{ "key": "decision_kind", "value": "unrelated" }],
    },
    "review": {
      "receipt": guidance_test_ref("review-selected"),
      "reviewer_id": "named-reviewer",
      "decided_at": 1791151100,
    },
    "source": {
      "outcome": guidance_test_ref("source-outcome"),
      "assessment": guidance_test_ref("source-assessment"),
      "assessment_review": guidance_test_ref("source-assessment-review"),
    },
    "selection_review": null,
    "currentness": "legacy_unselected",
    "journal_sequence": 18,
    "book_origin": "https://book.example",
    "observed_at": 1791151200,
    "applicability_decision_required": true,
    "activation_authorized": false,
    "external_side_effects_applied": false,
  }
}

///|
fn guidance_test_waiting() -> Model {
  let model = guidance_test_model()
  {
    ..model,
    dispatch_guidance: {
      ..empty_dispatch_guidance(),
      context: Some(dispatch_guidance_context(model)),
      request: 9,
      phase: "waiting",
      handoff: Some(guidance_test_handoff()),
      origin: "https://book.example",
    },
  }
}

///|
fn guidance_test_selected() -> Model {
  let model = guidance_test_waiting()
  let (_, selected) = dispatch_guidance_update(
    _ => none,
    model,
    Returned(
      model.dispatch_guidance.context.unwrap(),
      9,
      "https://book.example",
      guidance_test_selection().stringify(),
      _ => (),
    ),
  )
  selected
}

///|
test "guidance query preserves canonical project and suite scope without guessing business product" {
  let context = dispatch_guidance_context(guidance_test_model())
  let handoff = guidance_test_handoff()
  assert_eq(dispatch_guidance_query(handoff.stringify(), context), Ok(handoff))
  for
    changed in [
      { ..context, actor: "other", },
      { ..context, task: "other", },
      { ..context, project: "other", },
      { ..context, product: "other", },
      { ..context, revision: 4.0, },
    ] {
    // Actor is carried by request correlation, never embedded in the Book URL.
    if changed.actor == context.actor {
      assert_true(
        dispatch_guidance_query(handoff.stringify(), changed) is Err(_),
      )
    }
  }
  let wrong = lesson_receipt_test_set(handoff, "conditions", [
    { "key": "project_id", "value": "project-guidance" },
    { "key": "product_id", "value": "moonproj" },
  ])
  assert_true(dispatch_guidance_query(wrong.stringify(), context) is Err(_))
  assert_true(dispatch_guidance_query("{}", context) is Err(_))
}

///|
test "optional selection is exact Start snapshot while ordinary Start bytes remain unchanged" {
  let plain = guidance_test_model()
  let expected : Json = {
    "idempotency_key": "opc-dispatch-start-task-guidance",
    "authority": dispatch_task_authority(plain, "project:task:update"),
  }
  assert_eq(dispatch_start_body(plain).stringify(), expected.stringify())
  let selected = guidance_test_selected()
  assert_eq(
    selected.dispatch_guidance.selected,
    Some(guidance_test_selection()),
  )
  assert_eq(
    dispatch_json_field(dispatch_start_body(selected), "book_guidance"),
    guidance_test_selection(),
  )
  assert_false(dispatch_draft_store(selected).contains("GUIDANCE_PRIVATE_TEXT"))
  let (_, cleared) = update(_ => none, GuidanceAction(Clear), selected)
  assert_true(cleared.dispatch_guidance.selected is None)
  assert_eq(dispatch_start_body(cleared).stringify(), expected.stringify())
  assert_true(dispatch_can_start(guidance_test_waiting()))
}

///|
test "only exact current actor task revision page request and Book may acknowledge a selection" {
  let model = guidance_test_waiting()
  let context = model.dispatch_guidance.context.unwrap()
  let accepted : Array[Bool] = []
  let text = guidance_test_selection().stringify()
  for
    changed in [
      { ..model, dispatch_task_actor_id: "other", },
      { ..model, dispatch_task_id: "other", },
      { ..model, dispatch_task_selection: 5, },
      { ..model, dispatch_task_project_id: "other", },
      { ..model, dispatch_task_product_id: "other", },
      { ..model, page: Products, },
      {
        ..model,
        dispatch_continuation: { ..model.dispatch_continuation, revision: 4.0, },
      },
      { ..model, dispatch_task_pending_action: "start", },
      { ..model, dispatch_run: Some(dispatch_test_run("running")), },
    ] {
    let (cmd, rejected) = dispatch_guidance_update(
      _ => none,
      changed,
      Returned(context, 9, "https://book.example", text, value => {
        accepted.push(value)
      }),
    )
    lesson_receipt_test_run(cmd)
    assert_true(rejected.dispatch_guidance.selected is None)
  }
  for
    (request, origin, response) in [
      (8, "https://book.example", text),
      (9, "https://other.example", text),
      (9, "https://book.example", "{}"),
      (
        9,
        "https://book.example",
        lesson_receipt_test_set(
          guidance_test_selection(),
          "activation_authorized",
          true,
        ).stringify(),
      ),
    ] {
    let (cmd, rejected) = dispatch_guidance_update(
      _ => none,
      model,
      Returned(context, request, origin, response, value => accepted.push(value)),
    )
    lesson_receipt_test_run(cmd)
    assert_true(rejected.dispatch_guidance.selected is None)
  }
  assert_eq(accepted, [])
  let (cmd, selected) = dispatch_guidance_update(
    _ => none,
    model,
    Returned(context, 9, "https://book.example", text, value => {
      accepted.push(value)
    }),
  )
  assert_eq(accepted, [])
  assert_eq(
    selected.dispatch_guidance.selected,
    Some(guidance_test_selection()),
  )
  lesson_receipt_test_run(cmd)
  assert_eq(accepted, [true])
}

///|
test "Start freezes guidance through uncertain retry and canonical no-reservation read permits clear" {
  let selected = guidance_test_selected()
  let body = dispatch_start_body(selected)
  let (_, starting) = update(_ => none, StartDispatchTask, selected)
  assert_eq(starting.dispatch_guidance.start_body, Some(body))
  let (_, failed) = update(
    _ => none,
    DispatchTaskCommandFailed("task-guidance", 4, "Start", "unavailable"),
    starting,
  )
  for action in [Clear, Prepare, Origin("https://other.example"), OpenBook] {
    let (_, unchanged) = update(_ => none, GuidanceAction(action), failed)
    assert_eq(dispatch_start_body(unchanged), body)
    assert_eq(
      unchanged.dispatch_guidance.selected,
      Some(guidance_test_selection()),
    )
  }
  let (_, retry) = update(_ => none, StartDispatchTask, failed)
  assert_eq(dispatch_start_body(retry), body)
  let snapshot = {
    ..dispatch_test_snapshot("running"),
    task_id: "task-guidance",
    project_id: "project-guidance",
    product_id: "moonproj",
    revision: 3.0,
    run: None,
    state: "pending",
  }
  let (_, reread) = update(
    _ => none,
    DispatchTaskLoaded("task-guidance", 4, snapshot),
    failed,
  )
  assert_true(reread.dispatch_guidance.start_body is None)
  assert_true(dispatch_guidance_editable(reread))
  let (_, cleared) = update(_ => none, GuidanceAction(Clear), reread)
  assert_true(
    dispatch_json_field(dispatch_start_body(cleared), "book_guidance") is Null,
  )
}

///|
#warnings("-alert_unstable")
test "reserved execution displays captured references instead of tab-local guidance text" {
  let selected = guidance_test_selected()
  let (_, starting) = update(_ => none, StartDispatchTask, selected)
  let captured = @task_evidence.guidance_summary(
    guidance_test_selection(),
    sha256="a".repeat(64),
  )
  let run = {
    ..dispatch_test_run("unknown"),
    task_id: "task-guidance",
    book_guidance: captured,
  }
  let snapshot = {
    ..dispatch_test_snapshot("unknown"),
    task_id: "task-guidance",
    project_id: "project-guidance",
    product_id: "moonproj",
    revision: 4.0,
    run: Some(run),
  }
  let (_, reserved) = update(
    _ => none,
    DispatchTaskLoaded("task-guidance", 4, snapshot),
    starting,
  )
  assert_true(reserved.dispatch_guidance.selected is None)
  assert_false(dispatch_guidance_editable(reserved))
  assert_eq(
    dispatch_start_body(reserved),
    starting.dispatch_guidance.start_body.unwrap(),
  )
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_native_result(reserved)),
  )
  assert_true(html.contains("lesson-selected"))
  assert_true(html.contains("本次执行捕获的 Book 经验引用"))
  assert_false(html.contains("GUIDANCE_PRIVATE_TEXT"))
  let restored = { ..guidance_test_model(), dispatch_run: Some(run), }
  assert_true(
    dispatch_json_field(dispatch_start_body(restored), "book_guidance") is Null,
  )
}

///|
test "navigation actor task and revision changes clear unsubmitted tab guidance" {
  let model = guidance_test_selected()
  let (_, navigated) = update(_ => none, Navigate(Products), model)
  assert_true(navigated.dispatch_guidance.selected is None)
  assert_true(navigated.dispatch_guidance.handoff is None)
  for
    changed in [
      { ..model, dispatch_task_actor_id: "other", },
      { ..model, dispatch_task_id: "other", },
      { ..model, dispatch_task_selection: 5, },
      {
        ..model,
        dispatch_continuation: { ..model.dispatch_continuation, revision: 4.0, },
      },
    ] {
    let (_, next) = update(_ => none, DismissNotice, changed)
    assert_true(next.dispatch_guidance.selected is None)
    assert_true(
      dispatch_json_field(dispatch_start_body(next), "book_guidance") is Null,
    )
  }
}

///|
#warnings("-alert_unstable")
test "guidance review scope and text render escaped before explicit Start" {
  let selected = guidance_test_selected()
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_guidance_view(_ => none, selected)),
  )
  assert_true(html.contains("named-reviewer"))
  assert_true(html.contains("suite_product_id"))
  assert_true(html.contains("GUIDANCE_PRIVATE_TEXT"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_false(html.contains("<script>"))
  assert_true(html.contains("清除经验选择"))
}

///|
test "guidance browser isolates kinds origin source nonce and ACK waits for current reducer" {
  let browser = lesson_sender_test_browser()
  let states = [guidance_test_waiting()]
  let context = states[0].dispatch_guidance.context.unwrap()
  let ended : Array[String] = []
  let _ = dispatch_guidance_connect_book_on(
    browser,
    "https://book.example",
    guidance_test_handoff().stringify(),
    (text, acknowledge) => {
      let (cmd, next) = dispatch_guidance_update(
        _ => none,
        states[0],
        Returned(context, 9, "https://book.example", text, acknowledge),
      )
      states[0] = next
      lesson_receipt_test_run(cmd)
    },
    reason => ended.push(reason),
  )
  let initial = @json.parse(lesson_sender_test_state(browser))
  let url = dispatch_json_text(initial, "url")
  assert_true(url.starts_with("https://book.example/apps/moonbook/?"))
  assert_true(url.contains("proj_guidance_source="))
  assert_true(url.contains("proj_guidance_nonce="))
  assert_true(url.contains("#task-guidance-query"))
  assert_false(url.contains("task_id"))
  assert_false(url.contains("project-guidance"))
  for
    (origin, window, nonce, kind) in [
      (
        "https://wrong.example", true, "test-nonce", "moonbook.guidance-ready.v1",
      ),
      (
        "https://book.example", false, "test-nonce", "moonbook.guidance-ready.v1",
      ),
      ("https://book.example", true, "wrong", "moonbook.guidance-ready.v1"),
      ("https://book.example", true, "test-nonce", "moonbook.lesson-ready.v1"),
    ] {
    lesson_sender_test_event(browser, origin, window, nonce, kind, "")
  }
  assert_eq(
    dispatch_continuation_array(
      @json.parse(lesson_sender_test_state(browser)),
      "calls",
    ).length(),
    0,
  )
  lesson_sender_test_event(
    browser,
    "https://book.example",
    true,
    "test-nonce",
    "moonbook.guidance-selection.v1",
    guidance_test_selection().stringify(),
  )
  assert_true(states[0].dispatch_guidance.selected is None)
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.guidance-ready.v1",
    "",
  )
  lesson_sender_test_event(
    browser, "https://book.example", true, "test-nonce", "moonbook.guidance-selection.v1",
    "{}",
  )
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
    "moonbook.guidance-selection.v1",
    guidance_test_selection().stringify(),
  )
  let calls = dispatch_continuation_array(
    @json.parse(lesson_sender_test_state(browser)),
    "calls",
  )
  assert_eq(calls.length(), 2)
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[0], "value"), "kind"),
    "moonproj.guidance-query.v1",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[1], "value"), "kind"),
    "moonproj.guidance-received.v1",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(calls[1], "value"), "payload"),
    guidance_test_selection().stringify(),
  )
  assert_eq(ended, ["received"])
  for
    invalid in [
      "https://book.example/apps/moonbook/", "https://book.example/?query=1", "https://user:secret@book.example",
    ] {
    let rejected = lesson_sender_test_browser()
    let reasons : Array[String] = []
    let _ = dispatch_guidance_connect_book_on(
      rejected,
      invalid,
      "private query",
      (_, _) => (),
      reason => reasons.push(reason),
    )
    assert_eq(
      dispatch_json_text(@json.parse(lesson_sender_test_state(rejected)), "url"),
      "",
    )
    assert_eq(reasons, ["unavailable"])
  }
}

///|
test "Book popup unavailable timeout and late selection never block ordinary Start" {
  for
    failure in [
      "throwing-popup", "blocked-popup", "missing-crypto", "throwing-crypto",
    ] {
    let browser = lesson_sender_test_browser()
    lesson_sender_unavailable_api(browser, failure)
    let ended : Array[String] = []
    let thrown = lesson_sender_capture_throw(fn() {
      ignore(
        dispatch_guidance_connect_book_on(
          browser,
          "https://book.example",
          "query",
          (_, _) => (),
          reason => ended.push(reason),
        ),
      )
    })
    assert_eq(thrown, "")
    assert_eq(ended, ["unavailable"])
  }
  let model = guidance_test_waiting()
  let (_, ended) = update(
    _ => none,
    GuidanceAction(
      Ended(model.dispatch_guidance.context.unwrap(), 9, "timeout"),
    ),
    model,
  )
  assert_true(dispatch_can_start(ended))
  assert_true(
    dispatch_json_field(dispatch_start_body(ended), "book_guidance") is Null,
  )
  let accepted : Array[Bool] = []
  let (cmd, late) = dispatch_guidance_update(
    _ => none,
    ended,
    Returned(
      model.dispatch_guidance.context.unwrap(),
      9,
      "https://book.example",
      guidance_test_selection().stringify(),
      value => accepted.push(value),
    ),
  )
  lesson_receipt_test_run(cmd)
  assert_eq(accepted, [])
  assert_true(late.dispatch_guidance.selected is None)
}

///|
test "malformed or stale explicit selection blocks Start rather than silently omitting guidance" {
  let selected = guidance_test_selected()
  let malformed = lesson_receipt_test_set(
    guidance_test_selection(),
    "activation_authorized",
    true,
  )
  for
    invalid in [
      {
        ..selected,
        dispatch_guidance: {
          ..selected.dispatch_guidance,
          selected: Some(malformed),
        },
      },
      {
        ..selected,
        dispatch_guidance: { ..selected.dispatch_guidance, handoff: None, },
      },
      {
        ..selected,
        dispatch_continuation: {
          ..selected.dispatch_continuation,
          revision: 4.0,
        },
      },
    ] {
    let (_, blocked) = update(_ => none, StartDispatchTask, invalid)
    assert_eq(blocked.dispatch_task_pending_action, "")
    assert_true(blocked.dispatch_guidance.start_body is None)
    assert_true(blocked.notice.contains("刷新或清除"))
  }
  assert_eq(dispatch_guidance_start_blocker(guidance_test_model()), "")
  assert_eq(dispatch_guidance_start_blocker(selected), "")
}

///|
extern "js" fn guidance_test_capture_listener(browser : LessonHandoffBrowser) =
  #| b=>{b.previousListener=b.listener;b.previousChild=b.child;}

///|
extern "js" fn guidance_test_late_event(
  browser : LessonHandoffBrowser,
  kind : String,
  payload : String,
) =
  #| (b,kind,payload)=>b.previousListener?.({origin:'https://book.example',source:b.previousChild,data:{nonce:'test-nonce',kind,payload}})

///|
test "clear actor task revision page origin and reopen teardown before a delayed ready can send private query" {
  for
    change in [
      "clear", "actor", "task", "revision", "page", "origin", "reopen", "start",
    ] {
    let browser = lesson_sender_test_browser()
    let ended : Array[String] = []
    let cancel = dispatch_guidance_connect_book_on(
      browser,
      "https://book.example",
      guidance_test_handoff().stringify(),
      (_, acknowledge) => acknowledge(true),
      reason => ended.push(reason),
    )
    guidance_test_capture_listener(browser)
    let model = guidance_test_waiting()
    let (_, connected) = dispatch_guidance_update(
      _ => none,
      model,
      Connected(model.dispatch_guidance.context.unwrap(), 9, cancel),
    )
    let changed = match change {
      "actor" => { ..connected, dispatch_task_actor_id: "other", }
      "task" => { ..connected, dispatch_task_id: "other", }
      "revision" =>
        {
          ..connected,
          dispatch_continuation: {
            ..connected.dispatch_continuation,
            revision: 4.0,
          },
        }
      "page" => { ..connected, page: Products, }
      _ => connected
    }
    let action : Msg = match change {
      "clear" => GuidanceAction(Clear)
      "origin" => GuidanceAction(Origin("https://other.example"))
      "reopen" => GuidanceAction(OpenBook)
      "start" => StartDispatchTask
      _ => DismissNotice
    }
    let (_, next) = update(_ => none, action, changed)
    // Execute the production transition's teardown without executing the new
    // network/start command, which is independently covered by transport tests.
    lesson_receipt_test_run(dispatch_guidance_transition(connected, next, none))
    guidance_test_late_event(browser, "moonbook.guidance-ready.v1", "")
    guidance_test_late_event(
      browser,
      "moonbook.guidance-selection.v1",
      guidance_test_selection().stringify(),
    )
    let captured = @json.parse(lesson_sender_test_state(browser))
    assert_eq(
      dispatch_continuation_array(captured, "calls").length(),
      0,
      msg=change,
    )
    assert_eq(
      dispatch_json_field(captured, "listening"),
      Json::boolean(false),
      msg=change,
    )
    assert_eq(
      dispatch_json_field(captured, "timer"),
      Json::boolean(false),
      msg=change,
    )
    assert_eq(ended, ["cancelled"], msg=change)
  }
}

///|
extern "js" fn guidance_test_global_browser(
  browser : LessonHandoffBrowser,
  action : () -> Unit,
) =
  #| (browser,action)=>{
  #|   const names=['location','crypto','open','addEventListener','removeEventListener','setTimeout','clearTimeout'];
  #|   const saved=new Map(names.map(name=>[name,Object.getOwnPropertyDescriptor(globalThis,name)]));
  #|   try{for(const name of names)Object.defineProperty(globalThis,name,{value:browser[name],writable:true,configurable:true});action();}
  #|   finally{for(const [name,descriptor]of saved){if(descriptor)Object.defineProperty(globalThis,name,descriptor);else delete globalThis[name];}}
  #| }

///|
fn guidance_test_reduce(states : Array[Model], msg : Msg) -> Cmd {
  let (cmd, next) = update(
    message => guidance_test_reduce(states, message),
    msg,
    states[0],
  )
  states[0] = next
  cmd
}

///|
test "production OpenBook scheduler opens immediately and Clear tears down active transport" {
  let browser = lesson_sender_test_browser()
  let states = [guidance_test_waiting()]
  let connected : Array[Bool] = []
  let captures : Array[String] = []
  guidance_test_global_browser(browser, fn() {
    let command = guidance_test_reduce(states, GuidanceAction(OpenBook))
    lesson_receipt_test_run(command)
    connected.push(states[0].dispatch_guidance.cancel is Some(_))
    captures.push(lesson_sender_test_state(browser))
    guidance_test_capture_listener(browser)
    lesson_receipt_test_run(guidance_test_reduce(states, GuidanceAction(Clear)))
    guidance_test_late_event(browser, "moonbook.guidance-ready.v1", "")
    captures.push(lesson_sender_test_state(browser))
  })
  assert_eq(connected, [true])
  assert_true(
    dispatch_json_text(@json.parse(captures[0]), "url").contains(
      "#task-guidance-query",
    ),
  )
  assert_true(states[0].dispatch_guidance.selected is None)
  assert_eq(
    dispatch_continuation_array(@json.parse(captures[1]), "calls").length(),
    0,
  )
}

///|
test "same task canonical revision change requires an explicit refresh or clear decision" {
  let selected = guidance_test_selected()
  let snapshot = {
    ..dispatch_test_snapshot("running"),
    task_id: "task-guidance",
    project_id: "project-guidance",
    product_id: "moonproj",
    revision: 4.0,
    run: None,
    state: "pending",
  }
  let (_, changed) = update(
    _ => none,
    DispatchTaskLoaded("task-guidance", 4, snapshot),
    selected,
  )
  assert_true(changed.dispatch_guidance.selected is None)
  assert_true(changed.dispatch_guidance.handoff is None)
  assert_true(changed.dispatch_guidance.needs_refresh)
  assert_true(
    changed.dispatch_guidance.notice.contains("版本或范围已变化"),
  )
  let (_, blocked) = update(_ => none, StartDispatchTask, changed)
  assert_eq(blocked.dispatch_task_pending_action, "")
  let (_, cleared) = update(_ => none, GuidanceAction(Clear), blocked)
  let (_, started) = update(_ => none, StartDispatchTask, cleared)
  assert_eq(started.dispatch_task_pending_action, "start")
  assert_true(
    dispatch_json_field(dispatch_start_body(started), "book_guidance") is Null,
  )
}

///|
test "outer scheduler handles immediate popup failure and exact accepted ACK" {
  for unavailable in [true, false] {
    let browser = lesson_sender_test_browser()
    if unavailable {
      lesson_sender_unavailable_api(browser, "blocked-popup")
    }
    let states = [guidance_test_waiting()]
    guidance_test_global_browser(browser, fn() {
      lesson_receipt_test_run(
        guidance_test_reduce(states, GuidanceAction(OpenBook)),
      )
      if !unavailable {
        lesson_sender_test_event(
          browser, "https://book.example", true, "test-nonce", "moonbook.guidance-ready.v1",
          "",
        )
        lesson_sender_test_event(
          browser,
          "https://book.example",
          true,
          "test-nonce",
          "moonbook.guidance-selection.v1",
          guidance_test_selection().stringify(),
        )
      }
    })
    assert_true(dispatch_can_start(states[0]))
    assert_true(states[0].dispatch_guidance.cancel is None)
    if unavailable {
      assert_eq(states[0].dispatch_guidance.phase, "ready")
      assert_true(states[0].dispatch_guidance.selected is None)
      assert_eq(
        dispatch_continuation_array(
          @json.parse(lesson_sender_test_state(browser)),
          "calls",
        ).length(),
        0,
      )
    } else {
      assert_eq(states[0].dispatch_guidance.phase, "selected")
      assert_eq(
        states[0].dispatch_guidance.selected,
        Some(guidance_test_selection()),
      )
      assert_eq(
        dispatch_continuation_array(
          @json.parse(lesson_sender_test_state(browser)),
          "calls",
        ).length(),
        2,
      )
    }
  }
}

///|
test "outer scheduler invalidates old popup on reopen actor route and Start while waiting" {
  for change in ["reopen", "actor", "route", "start"] {
    let browser = lesson_sender_test_browser()
    let states = [guidance_test_waiting()]
    let captures : Array[String] = []
    outcome_test_browser(fn() {
      guidance_test_global_browser(browser, fn() {
        lesson_receipt_test_run(
          guidance_test_reduce(states, GuidanceAction(OpenBook)),
        )
        guidance_test_capture_listener(browser)
        if change == "actor" {
          states[0] = {
            ..states[0],
            dispatch_task_actor_id: "different-actor",
          }
        }
        let msg : Msg = match change {
          "reopen" => GuidanceAction(OpenBook)
          "route" => Navigate(Overview)
          "start" => StartDispatchTask
          _ => DismissNotice
        }
        lesson_receipt_test_run(guidance_test_reduce(states, msg))
        guidance_test_late_event(browser, "moonbook.guidance-ready.v1", "")
        guidance_test_late_event(
          browser,
          "moonbook.guidance-selection.v1",
          guidance_test_selection().stringify(),
        )
        captures.push(lesson_sender_test_state(browser))
        captures.push(outcome_test_browser_state())
      })
    })
    assert_eq(
      dispatch_continuation_array(@json.parse(captures[0]), "calls").length(),
      0,
      msg=change,
    )
    assert_true(states[0].dispatch_guidance.selected is None)
    if change == "start" {
      assert_eq(states[0].dispatch_task_pending_action, "start")
      let requests = dispatch_continuation_array(
        @json.parse(captures[1]),
        "requests",
      )
      assert_eq(requests.length(), 1)
      assert_false(
        dispatch_json_text(requests[0], "body").contains("book_guidance"),
      )
    }
  }
}
