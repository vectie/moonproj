///|
extern "js" fn offer_serialized_read(variable : String) -> String =
  #| variable=>{const path=globalThis.process?.env?.[variable];return path?require('node:fs').readFileSync(path,'utf8'):'';}

///|
extern "js" fn offer_serialized_write(variable : String, text : String) =
  #| (variable,text)=>{const path=globalThis.process?.env?.[variable];if(path)require('node:fs').writeFileSync(path,text);}

///|
// Production transports execute only against this isolated non-networking browser.
extern "js" fn offer_transport_browser(run : () -> Unit) =
  #| run=>{
  #|   const names=['fetch','window','Blob','URL','document','setTimeout'];const prior=Object.fromEntries(names.map(n=>[n,globalThis[n]]));
  #|   const state=globalThis.__offerTransport={requests:[],pending:[],downloads:[],events:[],storage:new Map()};
  #|   globalThis.window={localStorage:{setItem:(k,v)=>{state.events.push('store');state.storage.set(k,v);},getItem:k=>state.storage.get(k)||null},location:{href:'https://example.test/?task=offer-task'},history:{pushState(){},replaceState(){}}};
  #|   globalThis.fetch=(url,options)=>{state.events.push(options?.method||'GET');state.requests.push({url,...options});const pending={};state.pending.push(pending);return{then:callback=>{pending.callback=callback;return{catch:failure=>{pending.failure=failure;}};}};};
  #|   globalThis.Blob=class{constructor(parts){this.text=parts.join('');}};const blobs=new Map();
  #|   globalThis.URL=class extends prior.URL{static createObjectURL(blob){const id='blob:'+blobs.size;blobs.set(id,blob.text);return id;}static revokeObjectURL(){}};
  #|   globalThis.document={createElement:()=>({click(){state.downloads.push({name:this.download,text:blobs.get(this.href)});}})};globalThis.setTimeout=()=>0;
  #|   try{run();}finally{for(const name of names){if(prior[name]===undefined)delete globalThis[name];else globalThis[name]=prior[name];}delete globalThis.__offerTransport;}
  #| }

///|
extern "js" fn offer_transport_respond(status : Int, text : String) =
  #| (status,text)=>globalThis.__offerTransport.pending.shift().callback({status,text:()=>({then:callback=>callback(text)})})

///|
extern "js" fn offer_transport_fail() =
  #| ()=>globalThis.__offerTransport.pending.shift().failure(Error('offline'))

///|
extern "js" fn offer_transport_state() -> String =
  #| ()=>{const s=globalThis.__offerTransport;return JSON.stringify({requests:s.requests,downloads:s.downloads,events:s.events});}

///|
fn offer_serialized_create() -> DispatchDraft {
  {
    ..dispatch_active_draft(drafts_test_valid()).unwrap(),
    id: "offer-local-draft",
    task_id: "offer-task",
    idempotency_key: "offer-create-serialized",
    project_id: "offer-project",
    product_id: "",
    offer_draft: Some(offer_test_value()),
  }
}

///|
fn offer_serialized_update() -> DispatchOfferDraft {
  let draft = dispatch_offer_find(offer_test_frozen(), "offer-task").unwrap()
  let value = dispatch_offer_edit(
    dispatch_offer_edit(
      dispatch_offer_edit(
        offer_test_value(),
        "title",
        "Revised research proposal",
      ),
      "state",
      "closed",
    ),
    "closure_reason",
    "Example buyer paused this scope",
  )
  {
    ..draft,
    operation_key: "offer-update-serialized",
    operation_offer: Some(
      @task_evidence.normalize_offer_draft(value) catch {
        _ => value
      },
    ),
    value,
  }
}

///|
test "offer actual ordinary create without proposal supplies empty-detail qualification input" {
  let draft = {
    ..offer_serialized_create(),
    task_id: "offer-empty-task",
    idempotency_key: "offer-empty-create-serialized",
    offer_draft: None,
    research_brief: None,
  }
  let captured : Array[String] = []
  let emitted : Array[Msg] = []
  offer_transport_browser(() => {
    drafts_test_execute(
      dispatch_create_draft(
        message => {
          emitted.push(message)
          none
        },
        draft,
        "actor-offer",
      ),
    )
    offer_transport_respond(200, drafts_test_receipt(draft.task_id))
    captured.push(offer_transport_state())
  })
  assert_true(
    emitted[0]
    is DraftAction(CreateRead("actor-offer", "offer-local-draft", 200, _)),
  )
  let requests = dispatch_continuation_array(
    @json.parse(captured[0]),
    "requests",
  )
  assert_eq(requests.length(), 1)
  let body = dispatch_json_text(requests[0], "body")
  assert_true(dispatch_json_field(@json.parse(body), "offer_draft") is Null)
  offer_serialized_write("MOONPROJ_OFFER_EMPTY_CREATE_OUTPUT", body)
}

///|
test "offer actor scoped persisted uncertain operation survives signout and new-draft navigation" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let states = [offer_test_frozen()]
  offer_transport_browser(() => {
    drafts_test_execute(dispatch_offer_persist(emit, states[0], "", ""))
    let (_, signed_out) = dispatch_draft_session(emit, states[0], "")
    let (_, signed_back) = dispatch_draft_session(
      emit, signed_out, "actor-offer",
    )
    drafts_test_execute(dispatch_offer_session(emit, "actor-offer"))
    states[0] = update(emit, emitted[1], signed_back).1
  })
  let restored = dispatch_offer_find(states[0], "offer-task").unwrap()
  assert_eq(restored.state, "uncertain")
  assert_eq(restored.operation_key, "offer-update-fixture")
  assert_eq(
    dispatch_offer_update_body("actor-offer", restored),
    dispatch_offer_update_body(
      "actor-offer",
      dispatch_offer_find(offer_test_frozen(), "offer-task").unwrap(),
    ),
  )
}

///|
test "offer actual create and update callbacks preserve byte-identical retry and local-only downloads" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let capture : Array[String] = []
  let checks : Array[Bool] = []
  let create = offer_serialized_create()
  let draft = offer_serialized_update()
  offer_transport_browser(() => {
    drafts_test_execute(dispatch_create_draft(emit, create, "actor-offer"))
    offer_transport_respond(200, drafts_test_receipt(create.task_id))
    checks.push(
      emitted[0]
      is DraftAction(CreateRead("actor-offer", "offer-local-draft", 200, _)),
    )
    let frozen = dispatch_offer_put(
      { ..offer_test_model(), dispatch_task_pending_action: "offer", },
      draft,
    )
    drafts_test_execute(
      dispatch_offer_persist(emit, frozen, draft.task_id, draft.operation_key),
    )
    checks.push(
      emitted[1]
      is OfferAction(
        OfferStored(
          "actor-offer",
          "offer-task",
          "offer-update-serialized",
          true
        )
      ),
    )
    let (send, sending) = update(emit, emitted[1], frozen)
    drafts_test_execute(send)
    offer_transport_fail()
    checks.push(
      emitted[2]
      is OfferAction(
        Written("actor-offer", "offer-task", "offer-update-serialized", 0, "")
      ),
    )
    let (read, reading) = update(emit, emitted[2], sending)
    drafts_test_execute(read)
    offer_transport_respond(200, offer_test_body(1, offer_test_value(), []))
    let (store, uncertain) = update(emit, emitted[3], reading)
    drafts_test_execute(store)
    checks.push(
      dispatch_offer_find(uncertain, "offer-task").unwrap().state == "uncertain",
    )
    let (persist, retrying) = dispatch_offer_update(emit, uncertain, Retry)
    drafts_test_execute(persist)
    let (retry, resent) = update(emit, emitted[5], retrying)
    drafts_test_execute(retry)
    offer_transport_respond(
      200, "{\"task\":{\"task_id\":\"offer-task\",\"state\":\"pending\"}}",
    )
    let (read, reading) = update(emit, emitted[6], resent)
    drafts_test_execute(read)
    let readback = offer_test_body(2, draft.operation_offer.unwrap(), [
      offer_test_receipt(draft, 2, "available"),
    ])
    offer_transport_respond(200, readback)
    let (_, saved) = update(emit, emitted[7], reading)
    checks.push(
      dispatch_offer_find(saved, "offer-task").unwrap().state == "saved",
    )
    for _ in 0..<2 {
      let (download, _) = dispatch_offer_update(emit, saved, ExportCanonical)
      drafts_test_execute(download)
    }
    capture.push(offer_transport_state())
  })
  let captured = @json.parse(capture[0])
  assert_eq(checks, [true, true, true, true, true])
  let requests = dispatch_continuation_array(captured, "requests")
  assert_eq(requests.length(), 5)
  assert_eq(dispatch_json_text(requests[0], "method"), "POST")
  assert_eq(dispatch_json_text(requests[1], "method"), "PUT")
  assert_eq(dispatch_json_text(requests[2], "method"), "GET")
  assert_eq(
    dispatch_json_text(requests[3], "body"),
    dispatch_json_text(requests[1], "body"),
  )
  assert_eq(
    dispatch_json_text(requests[4], "url"),
    "/api/company/tasks/offer-task",
  )
  let events = dispatch_json_strings(captured, "events")
  assert_eq(events[0], "POST")
  assert_eq(events[1], "store")
  assert_eq(events[2], "PUT")
  let downloads = dispatch_continuation_array(captured, "downloads")
  assert_eq(downloads.length(), 2)
  assert_eq(downloads[0], downloads[1])
  assert_eq(dispatch_json_text(downloads[0], "name"), "moonproj-offer-draft.md")
  assert_eq(
    dispatch_json_text(downloads[0], "text"),
    @task_evidence.offer_draft_markdown(
      draft.operation_offer.unwrap(),
      task_id="offer-task",
      project_id="offer-project",
      revision=2,
    ),
  )
  offer_serialized_write(
    "MOONPROJ_OFFER_CREATE_OUTPUT",
    dispatch_json_text(requests[0], "body"),
  )
  offer_serialized_write(
    "MOONPROJ_OFFER_UPDATE_OUTPUT",
    dispatch_json_text(requests[1], "body"),
  )
  offer_serialized_write("MOONPROJ_OFFER_TRANSPORT_OUTPUT", capture[0])
}

///|
// Inputs are produced by the actual gateway/service qualification harness.
// This path never synthesizes created_by or other canonical task fields.
test "offer actual native detail bytes unlock canonical editor and export exact shared Markdown" {
  let text = offer_serialized_read("MOONPROJ_OFFER_DETAIL_INPUT")
  if text.is_empty() {
    return
  }
  let snapshot = dispatch_decode_snapshot(text, "offer-task").unwrap()
  let model = apply_dispatch_snapshot(
    {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_actor_id: "actor-offer",
    },
    snapshot,
  )
  assert_true(dispatch_offer_eligible(model))
  let operation = { ..offer_serialized_update(), state: "recovering", }
  let recovering = dispatch_offer_put(offer_test_model(), operation)
  let reconciled = offer_test_update(
    recovering,
    Read("actor-offer", "offer-task", operation.operation_key, 200, text),
  )
  assert_eq(
    dispatch_offer_find(reconciled, "offer-task").unwrap().state,
    "saved",
  )
  assert_eq(
    dispatch_offer_find(reconciled, "offer-task").unwrap().saved_revision,
    2,
  )
  assert_eq(reconciled.dispatch_offer_task, model.dispatch_offer_task)
  let rendered = guided_task(model)
  assert_true(rendered.contains("Revised research proposal"))
  assert_true(rendered.contains("Example buyer paused this scope"))
  assert_true(rendered.contains("历史方案"))
  let edited = offer_test_update(model, Begin)
  assert_eq(
    dispatch_offer_find(edited, "offer-task").unwrap().value,
    dispatch_json_field(model.dispatch_offer_task, "offer_draft"),
  )
  let captured : Array[String] = []
  offer_transport_browser(() => {
    let (download, _) = dispatch_offer_update(
      _ => none,
      edited,
      ExportCanonical,
    )
    drafts_test_execute(download)
    captured.push(offer_transport_state())
  })
  let capture = @json.parse(captured[0])
  assert_eq(dispatch_continuation_array(capture, "requests").length(), 0)
  let markdown = dispatch_json_text(
    dispatch_continuation_array(capture, "downloads")[0],
    "text",
  )
  let expected = offer_serialized_read("MOONPROJ_OFFER_EXPECTED_MARKDOWN")
  assert_false(expected.is_empty())
  assert_eq(markdown, expected)
  offer_serialized_write("MOONPROJ_OFFER_MARKDOWN_OUTPUT", markdown)
  offer_serialized_write("MOONPROJ_OFFER_RENDER_OUTPUT", rendered)
  let empty_text = offer_serialized_read("MOONPROJ_OFFER_EMPTY_DETAIL_INPUT")
  assert_false(empty_text.is_empty())
  let empty_snapshot = dispatch_decode_snapshot(empty_text, "offer-empty-task").unwrap()
  let empty_model = apply_dispatch_snapshot(
    {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_actor_id: "actor-offer",
    },
    empty_snapshot,
  )
  assert_true(
    dispatch_json_field(empty_model.dispatch_offer_task, "offer_draft") is Null,
  )
  assert_true(dispatch_offer_eligible(empty_model))
}
