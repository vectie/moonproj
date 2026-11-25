///|
fn client_packet_ready(model : Model, source : String) -> Model {
  let (_, waiting) = update(_ => none, ClientDeliveryAction(Prepare), model)
  let state = waiting.dispatch_client_delivery
  update(
    _ => none,
    ClientDeliveryAction(
      Loaded(state.request, state.expected, state.page, Ok(source)),
    ),
    waiting,
  ).1
}

///|
extern "js" fn client_packet_test_browser(run : () -> Unit) =
  #| run => {
  #|   const names=['fetch','Blob','URL','document','setTimeout','localStorage'];
  #|   const prior=Object.fromEntries(names.map(name=>[name,globalThis[name]]));
  #|   const state=globalThis.__outcomeTest={requests:[],pending:[],downloads:[],storage:0};
  #|   globalThis.fetch=(url,config)=>{state.requests.push({url,...config});return {then:callback=>{const pending={callback};state.pending.push(pending);return {catch:failure=>{pending.failure=failure;}};}};};
  #|   globalThis.Blob=class {constructor(parts,options){this.bytes=Buffer.concat(parts.map(part=>Buffer.from(part)));this.type=options?.type;}};
  #|   const blobs=new Map();globalThis.URL=class extends prior.URL {static createObjectURL(blob){const key='blob:'+blobs.size;blobs.set(key,blob);return key;}static revokeObjectURL(){}};
  #|   globalThis.document={createElement:()=>({click(){const blob=blobs.get(this.href);state.downloads.push({filename:this.download,type:blob.type,base64:blob.bytes.toString('base64'),text:blob.bytes.toString('utf8')});}})};
  #|   globalThis.setTimeout=()=>0;
  #|   globalThis.localStorage={setItem:()=>{state.storage++;throw Error('delivery stays page-local');},getItem:()=>null};
  #|   try{run();}finally{for(const name of names){if(prior[name]===undefined)delete globalThis[name];else globalThis[name]=prior[name];}delete globalThis.__outcomeTest;}
  #| }

///|
extern "js" fn client_packet_test_zip(data : String) -> String =
  #| data => {const zip=Buffer.from(data,'base64');const result=[];let p=0;while(zip.readUInt32LE(p)===0x04034b50){const size=zip.readUInt32LE(p+18),n=zip.readUInt16LE(p+26),e=zip.readUInt16LE(p+28),start=p+30+n+e;const body=zip.subarray(start,start+size);result.push({name:zip.subarray(p+30,p+30+n).toString('utf8'),base64:body.toString('base64'),text:body.toString('utf8')});p=start+size;}return JSON.stringify(result);}

///|
extern "js" fn client_packet_test_save(name : String, data : String) =
  #| (name,data)=>{const dir=globalThis.process?.env?.MOONPROJ_CLIENT_PACKET_OUTPUT_DIR;if(dir)require('node:fs').writeFileSync(require('node:path').join(dir,name),Buffer.from(data,'base64'));}

///|
test "client packet actual GET preview editable note and ZIP preserve exact accepted bytes without private context" {
  for
    (index, text) in ["", "你好🌙\r\nsecond\n", "\u{feff}# Brief\r\nkept\n"].mapi((
        index,
        text,
      ) => (index, text),
    ) {
    let initial = accepted_human_test_model(text~)
    let initial = {
      ..initial,
      dispatch_task_title: "PRIVATE INTERNAL TITLE",
      dispatch_task_acceptance: "PRIVATE PRD CRITERIA /root/private",
      dispatch_task_workspace: "/root/private",
    }
    let response = " \n" +
      accepted_human_test_payload(text~).stringify(indent=2) +
      "\n"
    let messages : Array[Msg] = []
    let emit : @rabbita.Emit[Msg] = msg => {
      messages.push(msg)
      none
    }
    let captures : Array[String] = []
    let states : Array[Model] = []
    client_packet_test_browser(() => {
      let (get, waiting) = update(emit, ClientDeliveryAction(Prepare), initial)
      lesson_receipt_test_run(get)
      let (duplicate, same) = update(
        emit,
        ClientDeliveryAction(Prepare),
        waiting,
      )
      lesson_receipt_test_run(duplicate)
      outcome_test_respond(response)
      let (_, ready) = update(emit, messages[0], same)
      try! assert_eq(ready.dispatch_client_delivery.body, text)
      try! assert_false(ready.dispatch_client_delivery.include_source)
      try! assert_eq(ready.dispatch_client_delivery.note.title, "交付结果")
      let mut edited = ready
      for
        (field, value) in [
          ("title", "市场建议"),
          ("summary", "包含调研结论与建议。"),
          ("review_request", "请回复需修改的地方。"),
          ("filename", "客户简报.md"),
        ] {
        edited = update(emit, ClientDeliveryAction(Edit(field, value)), edited).1
      }
      let (download, done) = update(
        emit,
        ClientDeliveryAction(Download),
        edited,
      )
      lesson_receipt_test_run(download)
      let (_, technical) = update(
        emit,
        ClientDeliveryAction(ToggleSource),
        done,
      )
      let (with_source, final_model) = update(
        emit,
        ClientDeliveryAction(Download),
        technical,
      )
      lesson_receipt_test_run(with_source)
      let (old_callback, stable) = update(emit, messages[0], final_model)
      lesson_receipt_test_run(old_callback)
      states.push(stable)
      captures.push(outcome_test_browser_state())
    })
    let capture = @json.parse(captures[0])
    let requests = dispatch_continuation_array(capture, "requests")
    assert_eq(requests.length(), 1)
    assert_eq(dispatch_json_text(requests[0], "method"), "GET")
    assert_eq(
      dispatch_json_text(requests[0], "url"),
      "/api/company/tasks/task-1/accepted-human-result",
    )
    let downloads = dispatch_continuation_array(capture, "downloads")
    assert_eq(downloads.length(), 2)
    for (i, download) in downloads.mapi((i, value) => (i, value)) {
      assert_eq(dispatch_json_text(download, "type"), "application/zip")
      assert_eq(dispatch_json_text(download, "filename"), "客户简报.md.zip")
      let data = dispatch_json_text(download, "base64")
      let files = match @json.parse(client_packet_test_zip(data)) {
        Array(files) => files
        _ => []
      }
      assert_eq(files.length(), if i == 0 { 2 } else { 3 })
      assert_eq(dispatch_json_text(files[0], "name"), "客户简报.md")
      assert_eq(
        dispatch_json_text(files[0], "base64"),
        accepted_human_test_base64(text),
      )
      assert_eq(
        dispatch_json_text(files[1], "text"),
        @client_delivery.readme(states[0].dispatch_client_delivery.note),
      )
      for
        secret in [
          "PRIVATE", "/root/private", "actor-", "original_command_id", "contract_version",
        ] {
        assert_false(dispatch_json_text(files[1], "text").contains(secret))
      }
      if i == 1 {
        assert_eq(dispatch_json_text(files[2], "text"), response)
      }
      client_packet_test_save(
        "client-packet-" + index.to_string() + "-" + i.to_string() + ".zip",
        data,
      )
    }
    client_packet_test_save(
      "accepted-body-" + index.to_string() + ".bin",
      accepted_human_test_base64(text),
    )
    assert_eq(dispatch_json_field(capture, "storage"), Json::number(0))
    assert_eq(
      states[0].dispatch_task_commitment,
      initial.dispatch_task_commitment,
    )
    assert_eq(states[0].dispatch_task_stage, initial.dispatch_task_stage)
    assert_eq(
      states[0].dispatch_continuation.accepted_delivery_source,
      initial.dispatch_continuation.accepted_delivery_source,
    )
    assert_eq(states[0].dispatch_lesson_handoff.payload, None)
  }
}

///|
test "client packet same-length changed body cannot reach preview or download" {
  let response = accepted_human_test_payload().stringify()
  let corrupt = response.replace_all(
    old=accepted_human_test_base64("edited bytes"),
    new=accepted_human_test_base64("alterd bytes"),
  )
  let model = accepted_human_test_model()
  assert_true(dispatch_accepted_human_payload(model, corrupt))
  let failed = client_packet_ready(model, corrupt)
  assert_true(failed.dispatch_client_delivery.source.is_empty())
  assert_eq(
    failed.dispatch_client_delivery.notice,
    "结果字节与已捕获来源不一致",
  )
  let (_, after) = update(_ => none, ClientDeliveryAction(Download), failed)
  assert_eq(after.dispatch_client_delivery.source, "")
}

///|
test "client packet transport failure timeout retry and closed preview fence stale callbacks" {
  let messages : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = msg => {
    messages.push(msg)
    none
  }
  let captures : Array[String] = []
  client_packet_test_browser(() => {
    let (get, waiting) = update(
      emit,
      ClientDeliveryAction(Prepare),
      accepted_human_test_model(),
    )
    lesson_receipt_test_run(get)
    outcome_test_fail()
    let (_, failed) = update(emit, messages[0], waiting)
    try! assert_false(failed.dispatch_client_delivery.pending)
    let (retry, retrying) = update(emit, ClientDeliveryAction(Prepare), failed)
    lesson_receipt_test_run(retry)
    try! assert_eq(retrying.dispatch_client_delivery.request, 2)
    let (_, closed) = update(emit, ClientDeliveryAction(Close), retrying)
    outcome_test_respond(accepted_human_test_payload().stringify())
    let (_, ignored) = update(emit, messages[1], closed)
    try! assert_true(ignored.dispatch_client_delivery.source.is_empty())
    let (again, active) = update(emit, ClientDeliveryAction(Prepare), ignored)
    lesson_receipt_test_run(again)
    let state = active.dispatch_client_delivery
    let (_, expired) = update(
      emit,
      ClientDeliveryAction(
        Loaded(state.request, state.expected, state.page, Err("timeout")),
      ),
      active,
    )
    try! assert_false(expired.dispatch_client_delivery.pending)
    try! assert_true(expired.dispatch_client_delivery.notice.contains("超时"))
    outcome_test_respond(accepted_human_test_payload().stringify())
    let (_, late) = update(emit, messages[2], expired)
    try! assert_true(late.dispatch_client_delivery.source.is_empty())
    let (last, pending) = update(emit, ClientDeliveryAction(Prepare), late)
    lesson_receipt_test_run(last)
    outcome_test_respond(accepted_human_test_payload().stringify())
    let (_, ready) = update(emit, messages[3], pending)
    try! assert_eq(ready.dispatch_client_delivery.body, "edited bytes")
    captures.push(outcome_test_browser_state())
  })
  let captured = @json.parse(captures[0])
  assert_eq(dispatch_continuation_array(captured, "downloads").length(), 0)
  assert_eq(dispatch_continuation_array(captured, "requests").length(), 4)
}

///|
test "client packet prepared output disappears on changed task report revision actor and navigation" {
  let model = accepted_human_test_model()
  let ready = client_packet_ready(
    model,
    accepted_human_test_payload().stringify(),
  )
  let targets = [
    { ..model, dispatch_task_id: "other", },
    { ..model, dispatch_task_selection: 99, },
    { ..model, dispatch_task_actor_id: "other", },
    { ..model, dispatch_task_report_id: "older-report", },
    { ..model, page: Delivery, },
    { ..model, dispatch_task_stage: "submitted", },
    {
      ..model,
      dispatch_continuation: { ..model.dispatch_continuation, revision: 99.0, },
    },
    {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        accepted_report_id: "other",
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
  for target in targets {
    let (_, waiting) = update(_ => none, ClientDeliveryAction(Prepare), model)
    let pending = waiting.dispatch_client_delivery
    let (_, late) = update(
      _ => none,
      ClientDeliveryAction(
        Loaded(
          pending.request,
          pending.expected,
          pending.page,
          Ok(accepted_human_test_payload().stringify()),
        ),
      ),
      { ..target, dispatch_client_delivery: pending, },
    )
    assert_true(late.dispatch_client_delivery.source.is_empty())
    let changed = {
      ..target,
      dispatch_client_delivery: ready.dispatch_client_delivery,
    }
    let captures : Array[String] = []
    client_packet_test_browser(() => {
      let (command, after) = update(
        _ => none,
        ClientDeliveryAction(Download),
        changed,
      )
      lesson_receipt_test_run(command)
      try! assert_true(after.dispatch_client_delivery.source.is_empty())
      captures.push(outcome_test_browser_state())
    })
    assert_eq(
      dispatch_continuation_array(@json.parse(captures[0]), "downloads").length(),
      0,
    )
  }
  let (_, away) = update(
    _ => none,
    ContinuationAction(SelectReport("older-report")),
    ready,
  )
  let (_, back) = update(
    _ => none,
    ContinuationAction(SelectReport("report-H1")),
    away,
  )
  assert_true(back.dispatch_client_delivery.source.is_empty())
}

///|
test "client packet browser URL changes invalidate preparation before download" {
  let checked = anchor_test_browser("https://proj.test/dispatch?task=task-1", () => {
    let ready = client_packet_ready(
      accepted_human_test_model(),
      accepted_human_test_payload().stringify(),
    )
    anchor_test_move("https://proj.test/dispatch?task=task-2")
    let (_, after) = update(_ => none, ClientDeliveryAction(Download), ready)
    after.dispatch_client_delivery.source.is_empty()
  })
  assert_true(checked)
}

///|
#warnings("-alert_unstable")
test "client packet view is human-only editable and hides technical content by default" {
  let model = accepted_human_test_model()
  let ready = client_packet_ready(
    model,
    accepted_human_test_payload().stringify(),
  )
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_client_delivery_view(_ => none, ready)),
  )
  for
    label in [
      "交付标题", "结果文件名", "交付说明", "审阅请求", "下载交付包 ZIP",
      "结果正文预览", "README.txt", "可选技术来源",
    ] {
    assert_true(html.contains(label), msg=label)
  }
  assert_false(html.contains("checked"))
  assert_false(html.contains("contract_version"))
  assert_false(html.contains("确认继续"))
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
    let unsupported = {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        accepted_delivery_source: source,
      },
    }
    let html = opc_render_cell(
      @rabbita.static_cell(
        dispatch_client_delivery_view(_ => none, unsupported),
      ),
    )
    assert_false(html.contains("准备客户交付包"))
  }
  let (_, bad) = update(
    _ => none,
    ClientDeliveryAction(Edit("filename", "../escape")),
    ready,
  )
  assert_false(
    @client_delivery.validate_note(bad.dispatch_client_delivery.note).is_empty(),
  )
  let (_, closed) = update(_ => none, ClientDeliveryAction(Close), ready)
  assert_true(closed.dispatch_client_delivery.source.is_empty())
  assert_false(closed.dispatch_client_delivery.include_source)
}
