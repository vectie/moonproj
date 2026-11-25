///|
extern "js" fn outcome_serialized_fixture() -> String =
  #| () => {const path=globalThis.process?.env?.MOONPROJ_OUTCOME_FIXTURE;return path?require('node:fs').readFileSync(path,'utf8'):'';}

///|
extern "js" fn outcome_serialized_time(seconds : Int) -> String =
  #| seconds=>new Date(seconds*1000).toISOString().slice(0,19)

///|
extern "js" fn outcome_serialized_clock(seconds : Int, run : () -> Unit) =
  #| (seconds,run)=>{const prior=Date.now;Date.now=()=>seconds*1000;try{run();}finally{Date.now=prior;}}

///|
extern "js" fn outcome_serialized_page(page : String, run : () -> Unit) =
  #| (page,run)=>{const prior=globalThis.location;globalThis.location={href:page};try{run();}finally{if(prior===undefined)delete globalThis.location;else globalThis.location=prior;}}

///|
extern "js" fn outcome_serialized_save(name : String, text : String) =
  #| (name,text)=>{const dir=globalThis.process?.env?.MOONPROJ_OUTCOME_UI_OUTPUT_DIR;if(dir)require('node:fs').writeFileSync(require('node:path').join(dir,name),text);}

///|
fn outcome_serialized_fill(
  model : Model,
  source : Json,
  supplied : Json,
) -> Model {
  let mut current = model
  let actions : Array[DispatchOutcomeMsg] = [
    Edit("summary", dispatch_json_text(supplied, "outcome_summary")),
    Edit(
      "observed_at",
      outcome_serialized_time(
        match dispatch_json_field(supplied, "observed_at") {
          Number(value, ..) => value.to_int()
          _ => 0
        },
      ),
    ),
  ]
  for index, name in ["information_gap", "recognition_gap", "decisiveness_gap"] {
    let gap = dispatch_json_field(supplied, name)
    actions.push(
      GapEdit(
        index,
        "choice",
        if dispatch_json_field(gap, "present") == Json::boolean(true) {
          "present"
        } else {
          "absent"
        },
      ),
    )
    actions.push(GapEdit(index, "summary", dispatch_json_text(gap, "summary")))
    if dispatch_json_field(gap, "present") == Json::boolean(true) {
      actions.push(
        GapEdit(
          index,
          "severity",
          match dispatch_json_field(gap, "severity") {
            Number(value, ..) => value.to_int().to_string()
            _ => ""
          },
        ),
      )
    }
    for reference in dispatch_continuation_array(gap, "evidence_refs") {
      if reference is String(id) {
        actions.push(Evidence(index, id))
      }
    }
  }
  let capability = dispatch_json_field(supplied, "capability")
  if !(capability is Null) {
    for
      (field, name) in [
        ("capability_id", "id"),
        ("capability_version", "version"),
        ("capability_summary", "summary"),
        ("change_text", "change_text"),
      ] {
      actions.push(Edit(field, dispatch_json_text(capability, name)))
    }
  }
  for action in actions {
    let (_, next) = dispatch_outcome_update(_ => none, current, source, action)
    current = next
  }
  current
}

///|
// Enabled by qualification after the native producer writes actual bytes.
// All authored fields enter through production edit actions, then the actual
// production HTTP command runs and its exact body is retained for round-trip.
test "production serialized outcome crosses form HTTP preview and exact three file downloads" {
  let text = outcome_serialized_fixture()
  if text.is_empty() {
    return
  }
  let fixture = @json.parse(text)
  let source = dispatch_json_field(fixture, "handoff")
  let supplied = dispatch_json_field(fixture, "draft")
  let task = dispatch_json_text(
    dispatch_json_field(source, "task"),
    "record_id",
  )
  let report = dispatch_json_text(
    dispatch_json_field(source, "report"),
    "record_id",
  )
  let recorded = match dispatch_json_field(supplied, "recorded_at") {
    Number(value, ..) => value.to_int()
    _ => 0
  }
  let initial = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: task,
    dispatch_task_report_id: report,
    dispatch_task_stage: "accepted",
    dispatch_task_selection: 4,
    dispatch_lesson_handoff: {
      ..empty_dispatch_lesson_handoff(),
      task_id: task,
      selection: 4,
      payload: Some(source),
    },
  }
  let models = [initial]
  outcome_serialized_page(dispatch_json_text(supplied, "owner_route"), () => {
    models[0] = outcome_serialized_fill(initial, source, supplied)
  })
  let model = models[0]
  assert_eq(
    dispatch_outcome_validation(dispatch_outcome_draft(model, source)),
    "",
  )
  let states = [model]
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let captures : Array[String] = []
  outcome_serialized_clock(recorded, () => {
    outcome_test_browser(() => {
      let (command, waiting) = dispatch_outcome_update(
        emit,
        model,
        source,
        Preview,
      )
      lesson_receipt_test_run(command)
      outcome_test_respond(text)
      let (_, ready) = update(emit, emitted[0], waiting)
      states[0] = ready
      for kind in ["submission", "handoff", "evidence", "submission"] {
        let (download, _) = dispatch_outcome_update(
          emit,
          ready,
          source,
          Download(kind),
        )
        lesson_receipt_test_run(download)
      }
      captures.push(outcome_test_browser_state())
    })
  })
  let ready = dispatch_outcome_draft(states[0], source)
  assert_eq(ready.prepared, Some(fixture))
  assert_eq(dispatch_outcome_draft_json(ready), supplied)
  assert_eq(states[0].dispatch_task_stage, "accepted")
  let captured = @json.parse(captures[0])
  let requests = dispatch_continuation_array(captured, "requests")
  assert_eq(requests.length(), 1)
  assert_eq(
    dispatch_json_text(requests[0], "url"),
    "/api/company/tasks/" + dispatch_url_encode(task) + "/outcome-export",
  )
  assert_eq(dispatch_json_text(requests[0], "method"), "POST")
  let body = dispatch_json_text(requests[0], "body")
  assert_eq(@json.parse(body), { "handoff": source, "draft": supplied })
  let downloads = dispatch_continuation_array(captured, "downloads")
  assert_eq(downloads.length(), 4)
  assert_eq(downloads[0], downloads[3])
  for index, kind in ["submission", "handoff", "evidence"] {
    assert_eq(
      dispatch_json_text(downloads[index], "text"),
      dispatch_json_text(fixture, kind + "_json"),
    )
    assert_eq(
      dispatch_json_text(downloads[index], "filename"),
      dispatch_json_text(fixture, kind + "_filename"),
    )
    outcome_serialized_save(
      dispatch_json_text(downloads[index], "filename"),
      dispatch_json_text(downloads[index], "text"),
    )
  }
  outcome_serialized_save("UI_OUTCOME_REQUEST.json", body)
  outcome_serialized_save(
    "UI_OUTCOME_DOWNLOADS.json",
    captured.stringify(indent=2),
  )
  let html = opc_render_cell(
    @rabbita.static_cell(dispatch_lesson_handoff_view(_ => none, states[0])),
  )
  assert_true(html.contains("准备导出的实际结果"))
  assert_true(html.contains("下载完整结果"))
  assert_true(html.contains("客户接受与现金事实需要各自证据"))
  assert_false(html.contains("Synthetic accepted task <&>"))
}
