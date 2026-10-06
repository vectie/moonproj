///|
// Synthetic complete unit envelope. The serialized qualification test below
// separately consumes the actual native producer's complete bytes.
fn outcome_test_response(draft : DispatchOutcomeDraft) -> Json {
  let value = dispatch_outcome_draft_json(draft)
  let basis : Json = {
    "contract_version": "moonproj.outcome-authoring.v1",
    "handoff": draft.handoff,
    "draft": value,
  }
  let basis_text = basis.stringify()
  let digest = outcome_test_hash(basis_text)
  let identity = "moonproj-outcome-" + digest
  let reference : Json = {
    "record_id": identity,
    "record_version": "1",
    "record_digest": "sha256:" + digest,
  }
  let submission : Json = {
    "contract_version": "moonbook.bookkeeper.product_outcome_submission.v1",
    "submission": reference,
    "source_product": "moonproj",
    "deliverable_title": "Synthetic unit task <&>",
    "deliverable_summary": "Synthetic unit report",
    "outcome_summary": draft.outcome_summary,
    "observed_at": dispatch_json_field(value, "observed_at"),
    "recorded_at": draft.recorded_at,
    "information_gap": dispatch_json_field(value, "information_gap"),
    "recognition_gap": dispatch_json_field(value, "recognition_gap"),
    "decisiveness_gap": dispatch_json_field(value, "decisiveness_gap"),
    "owner_route": draft.owner_route,
    "decision_evidence_id": "task-fixture",
    "evidence_refs": ["task", "report"].map(key => {
      let item = dispatch_json_field(draft.handoff, key)
      {
        "reference_id": dispatch_json_field(item, "record_id"),
        "reference_version": dispatch_json_field(item, "record_version"),
        "digest": dispatch_json_field(item, "record_digest"),
        "provenance_ref": Json::string(
          identity + "-handoff.json#/" + key + "_snapshot",
        ),
      }
    }),
  }
  if dispatch_outcome_has_gap(draft) && submission is Object(fields) {
    fields["capability_id"] = Json::string(draft.capability_id)
    fields["capability_version"] = Json::string(draft.capability_version)
    fields["capability_summary"] = Json::string(draft.capability_summary)
    fields["capability_change_digest"] = Json::string(
      "sha256:" + outcome_test_hash(draft.change_text),
    )
  }
  let evidence : Json = {
    "contract_version": "moonproj.outcome-evidence.v1",
    "handoff": draft.handoff,
    "draft": value,
    "submission": reference,
    "digest_basis": basis_text,
    "authorizing": false,
    "customer_acceptance": "not_asserted",
    "cash": "not_asserted",
  }
  {
    "contract_version": "moonproj.outcome-export.v1",
    "handoff": draft.handoff,
    "draft": dispatch_outcome_draft_json(draft),
    "submission": submission,
    "evidence_bundle": evidence,
    "submission_json": submission.stringify(indent=2),
    "handoff_json": draft.handoff.stringify(indent=2),
    "evidence_json": evidence.stringify(indent=2),
    "submission_filename": identity + ".json",
    "handoff_filename": identity + "-handoff.json",
    "evidence_filename": identity + "-evidence.json",
  }
}

///|
test "outcome decoder requires complete delivery fields and retained evidence basis" {
  let draft = outcome_test_draft()
  let valid = outcome_test_response(draft)
  assert_true(
    dispatch_outcome_decode(
      draft.handoff,
      dispatch_outcome_draft_json(draft),
      valid.stringify(),
    )
    is Ok(_),
  )
  for field in ["deliverable_title", "deliverable_summary"] {
    let original = dispatch_json_field(valid, "submission")
    guard original is Object(fields) else { fail("Expected submission") }
    let fields = fields.copy()
    fields.remove(field)
    let submission = Json::object(fields)
    let invalid = lesson_receipt_test_set(
      lesson_receipt_test_set(valid, "submission", submission),
      "submission_json",
      Json::string(submission.stringify(indent=2)),
    )
    assert_true(
      dispatch_outcome_decode(
        draft.handoff,
        dispatch_outcome_draft_json(draft),
        invalid.stringify(),
      )
      is Err(_),
      msg=field,
    )
  }
  for
    basis in [
      Json::null(),
      Json::string("not JSON"),
      Json::string("{}"),
      Json::string(
        (
          {
            "contract_version": "moonproj.outcome-authoring.v1",
            "handoff": draft.handoff,
            "draft": { "outcome_summary": "altered observation" },
          } : Json).stringify(),
      ),
    ] {
    let evidence = lesson_receipt_test_set(
      dispatch_json_field(valid, "evidence_bundle"),
      "digest_basis",
      basis,
    )
    let invalid = outcome_test_replace_response(
      valid, "evidence_bundle", evidence,
    )
    assert_true(
      dispatch_outcome_decode(
        draft.handoff,
        dispatch_outcome_draft_json(draft),
        invalid.stringify(),
      )
      is Err(_),
    )
  }
  let submission = dispatch_json_field(valid, "submission")
  let reference = dispatch_json_field(submission, "submission")
  for
    (key, text) in [
      ("record_digest", "sha256:not-a-digest"),
      (
        "record_digest", "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
      ("record_id", "moonproj-outcome-wrong-suffix"),
    ] {
    let wrong_ref = lesson_receipt_test_set(reference, key, Json::string(text))
    let invalid = outcome_test_replace_response(
      valid,
      "submission",
      lesson_receipt_test_set(submission, "submission", wrong_ref),
    )
    assert_true(
      dispatch_outcome_decode(
        draft.handoff,
        dispatch_outcome_draft_json(draft),
        invalid.stringify(),
      )
      is Err(_),
    )
  }
}

///|
fn outcome_test_replace_response(
  value : Json,
  key : String,
  replacement : Json,
) -> Json {
  let serialized_key = if key == "evidence_bundle" {
    "evidence_json"
  } else {
    key + "_json"
  }
  lesson_receipt_test_set(
    lesson_receipt_test_set(value, key, replacement),
    serialized_key,
    Json::string(replacement.stringify(indent=2)),
  )
}

///|
test "outcome decoder retains exact change text and checks capability digest shape" {
  let original = outcome_test_draft()
  let gaps = original.gaps.copy()
  gaps[0] = { ..gaps[0], choice: "present", severity: "2", }
  let draft = {
    ..original,
    gaps,
    capability_id: "actual.fixture-method",
    capability_version: "2",
    capability_summary: "Proposed real change",
    change_text: "Exact proposed change.\n",
  }
  let valid = outcome_test_response(draft)
  assert_true(
    dispatch_outcome_decode(
      draft.handoff,
      dispatch_outcome_draft_json(draft),
      valid.stringify(),
    )
    is Ok(_),
  )
  let wrong_digest = outcome_test_replace_response(
    valid,
    "submission",
    lesson_receipt_test_set(
      dispatch_json_field(valid, "submission"),
      "capability_change_digest",
      Json::string("sha256:short"),
    ),
  )
  assert_true(
    dispatch_outcome_decode(
      draft.handoff,
      dispatch_outcome_draft_json(draft),
      wrong_digest.stringify(),
    )
    is Err(_),
  )
  let changed_draft = dispatch_outcome_draft_json({
    ..draft,
    change_text: "Different proposal",
  })
  let wrong_change = outcome_test_replace_response(
    valid,
    "evidence_bundle",
    lesson_receipt_test_set(
      dispatch_json_field(valid, "evidence_bundle"),
      "draft",
      changed_draft,
    ),
  )
  assert_true(
    dispatch_outcome_decode(
      draft.handoff,
      dispatch_outcome_draft_json(draft),
      wrong_change.stringify(),
    )
    is Err(_),
  )
}

///|
test "unset outcome gap cannot send HTTP or become an absence claim" {
  let source = outcome_test_source()
  let draft = outcome_test_draft()
  let gaps = draft.gaps.copy()
  gaps[1] = { ..gaps[1], choice: "", }
  let model = dispatch_outcome_store(outcome_test_model(), { ..draft, gaps, })
  let captures : Array[String] = []
  outcome_test_browser(() => {
    let (command, _) = dispatch_outcome_update(
      _ => none,
      model,
      source,
      Preview,
    )
    lesson_receipt_test_run(command)
    captures.push(outcome_test_browser_state())
  })
  assert_eq(
    dispatch_continuation_array(@json.parse(captures[0]), "requests").length(),
    0,
  )
}

///|
// Fixture construction only; production hashing is owned by the native API.
extern "js" fn outcome_test_hash(text : String) -> String =
  #| text=>require('node:crypto').createHash('sha256').update(text,'utf8').digest('hex')

///|
extern "js" fn outcome_test_browser(run : () -> Unit) =
  #| run => {
  #|   const names=['fetch','Blob','URL','document','setTimeout','localStorage'];
  #|   const prior=Object.fromEntries(names.map(name=>[name,globalThis[name]]));
  #|   const state=globalThis.__outcomeTest={requests:[],pending:[],downloads:[],storage:0};
  #|   globalThis.fetch=(url,config)=>{state.requests.push({url,...config});return {then:callback=>{const pending={callback};state.pending.push(pending);return {catch:failure=>{pending.failure=failure;}};}};};
  #|   globalThis.Blob=class {constructor(parts){this.text=parts.join('');}};
  #|   const blobs=new Map();globalThis.URL=class extends prior.URL {static createObjectURL(blob){const key='blob:'+blobs.size;blobs.set(key,blob.text);return key;}static revokeObjectURL(){}};
  #|   globalThis.document={createElement:()=>({click(){state.downloads.push({filename:this.download,text:blobs.get(this.href)});}})};
  #|   globalThis.setTimeout=()=>0;
  #|   globalThis.localStorage={setItem:()=>{state.storage++;throw Error('outcome drafts must remain in memory');},getItem:()=>null};
  #|   try{run();}finally{for(const name of names){if(prior[name]===undefined)delete globalThis[name];else globalThis[name]=prior[name];}delete globalThis.__outcomeTest;}
  #| }

///|
extern "js" fn outcome_test_respond(text : String) =
  #| text=>globalThis.__outcomeTest.pending.shift().callback({text:()=>({then:callback=>callback(text)})})

///|
extern "js" fn outcome_test_fail() =
  #| ()=>globalThis.__outcomeTest.pending.shift().failure(Error('offline'))

///|
extern "js" fn outcome_test_browser_state() -> String =
  #| ()=>JSON.stringify({requests:globalThis.__outcomeTest.requests,downloads:globalThis.__outcomeTest.downloads,storage:globalThis.__outcomeTest.storage})

///|
test "outcome preview executes actual HTTP command and downloads identical retained response bytes" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let states = [outcome_test_model()]
  let captures : Array[String] = []
  let source = outcome_test_source()
  outcome_test_browser(() => {
    let (command, waiting) = dispatch_outcome_update(
      emit,
      states[0],
      source,
      Preview,
    )
    states[0] = waiting
    lesson_receipt_test_run(command)
    outcome_test_respond(
      outcome_test_response(dispatch_outcome_draft(waiting, source)).stringify(),
    )
    let (_, ready) = update(emit, emitted[0], waiting)
    states[0] = ready
    for
      kind in [
        "submission", "handoff", "evidence", "submission", "handoff", "evidence",
      ] {
      let (download, _) = dispatch_outcome_update(
        emit,
        ready,
        source,
        Download(kind),
      )
      lesson_receipt_test_run(download)
    }
    let (again, repeated) = dispatch_outcome_update(
      emit,
      ready,
      source,
      Preview,
    )
    states[0] = repeated
    lesson_receipt_test_run(again)
    captures.push(outcome_test_browser_state())
    outcome_test_respond(
      outcome_test_response(dispatch_outcome_draft(repeated, source)).stringify(),
    )
    let (_, settled) = update(emit, emitted[1], repeated)
    states[0] = settled
  })
  let captured = @json.parse(captures[0])
  let requests = dispatch_continuation_array(captured, "requests")
  assert_eq(requests.length(), 2)
  assert_eq(
    dispatch_json_text(requests[0], "url"),
    "/api/company/tasks/task-fixture/outcome-export",
  )
  assert_eq(dispatch_json_text(requests[0], "method"), "POST")
  assert_eq(
    dispatch_json_text(requests[0], "body"),
    dispatch_json_text(requests[1], "body"),
  )
  let body = @json.parse(dispatch_json_text(requests[0], "body"))
  assert_eq(dispatch_json_field(body, "handoff"), source)
  assert_eq(
    dispatch_json_field(body, "draft"),
    dispatch_outcome_draft_json(outcome_test_draft()),
  )
  let downloads = dispatch_continuation_array(captured, "downloads")
  assert_eq(downloads.length(), 6)
  let response = outcome_test_response(outcome_test_draft())
  for index, kind in ["submission", "handoff", "evidence"] {
    assert_eq(downloads[index], downloads[index + 3])
    assert_eq(
      dispatch_json_text(downloads[index], "text"),
      dispatch_json_text(response, kind + "_json"),
    )
    assert_eq(
      dispatch_json_text(downloads[index], "filename"),
      dispatch_json_text(response, kind + "_filename"),
    )
  }
  assert_eq(dispatch_json_field(captured, "storage"), Json::number(0))
  assert_eq(states[0].dispatch_task_stage, "accepted")
  assert_eq(states[0].dispatch_task_report_id, "report-fixture")
  assert_eq(dispatch_outcome_draft(states[0], source).prepared, Some(response))
}

///|
test "outcome response decoder rejects mismatched source draft missing companion bytes and filename traversal" {
  let draft = outcome_test_draft()
  let valid = outcome_test_response(draft)
  assert_eq(
    dispatch_outcome_decode(
      draft.handoff,
      dispatch_outcome_draft_json(draft),
      valid.stringify(),
    ),
    Ok(valid),
  )
  for
    (key, replacement) in [
      ("handoff", Json::null()),
      ("draft", Json::null()),
      ("submission_json", Json::string("{}")),
      ("handoff_json", Json::string("{}")),
      ("evidence_json", Json::string("{}")),
      ("submission_filename", Json::string("../outcome.json")),
      ("evidence_filename", Json::string("")),
    ] {
    let invalid = lesson_receipt_test_set(valid, key, replacement)
    assert_true(
      dispatch_outcome_decode(
        draft.handoff,
        dispatch_outcome_draft_json(draft),
        invalid.stringify(),
      )
      is Err(_),
    )
  }
}

///|
test "outcome ignores stale request selection source and edited draft response" {
  let source = outcome_test_source()
  let model = outcome_test_model()
  let (_, waiting) = dispatch_outcome_update(_ => none, model, source, Preview)
  let draft = dispatch_outcome_draft(waiting, source)
  let response = outcome_test_response(draft).stringify()
  let expected = dispatch_outcome_draft_json(draft)
  let actions : Array[DispatchOutcomeMsg] = [
    Loaded("another-task", 4, draft.request, expected, Ok(response)),
    Loaded("task-fixture", 5, draft.request, expected, Ok(response)),
    Loaded("task-fixture", 4, draft.request - 1, expected, Ok(response)),
    Loaded("task-fixture", 4, draft.request, Json::null(), Ok(response)),
  ]
  for action in actions {
    let (_, ignored) = dispatch_outcome_update(
      _ => none,
      waiting,
      source,
      action,
    )
    assert_true(dispatch_outcome_draft(ignored, source).prepared is None)
    assert_true(dispatch_outcome_draft(ignored, source).pending)
  }
  let edited = outcome_test_edit(
    waiting,
    Edit("summary", "A later real observation"),
  )
  let (_, ignored) = dispatch_outcome_update(
    _ => none,
    edited,
    source,
    Loaded("task-fixture", 4, draft.request, expected, Ok(response)),
  )
  assert_true(dispatch_outcome_draft(ignored, source).prepared is None)
  assert_eq(
    dispatch_outcome_draft(ignored, source).outcome_summary,
    "A later real observation",
  )
  let changed = lesson_receipt_test_set(
    source,
    "report_snapshot",
    Json::string("new capture"),
  )
  let (_, ignored) = dispatch_outcome_update(
    _ => none,
    {
      ..waiting,
      dispatch_lesson_handoff: {
        ..waiting.dispatch_lesson_handoff,
        payload: Some(changed),
      },
    },
    source,
    Loaded("task-fixture", 4, draft.request, expected, Ok(response)),
  )
  assert_true(dispatch_outcome_draft(ignored, source).prepared is None)
}

///|
test "outcome failed HTTP preview retains exact draft and frozen time for retry" {
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    emitted.push(message)
    none
  }
  let states = [outcome_test_model()]
  let captures : Array[String] = []
  let source = outcome_test_source()
  outcome_test_browser(() => {
    let (command, waiting) = dispatch_outcome_update(
      emit,
      states[0],
      source,
      Preview,
    )
    lesson_receipt_test_run(command)
    outcome_test_fail()
    let (_, failed) = update(emit, emitted[0], waiting)
    states[0] = failed
    let (retry, _) = dispatch_outcome_update(emit, failed, source, Preview)
    lesson_receipt_test_run(retry)
    captures.push(outcome_test_browser_state())
  })
  let draft = dispatch_outcome_draft(states[0], source)
  assert_false(draft.pending)
  assert_true(draft.prepared is None)
  assert_true(draft.notice.contains("预览未完成"))
  assert_eq(
    dispatch_outcome_draft_json(draft),
    dispatch_outcome_draft_json(outcome_test_draft()),
  )
  let captured = @json.parse(captures[0])
  let requests = dispatch_continuation_array(captured, "requests")
  assert_eq(
    dispatch_json_text(requests[0], "body"),
    dispatch_json_text(requests[1], "body"),
  )
}
