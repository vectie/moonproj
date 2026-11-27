///|
fn journey_test_row(
  action : String,
  event : String,
  revision : Int32,
  request : Json,
  report~ : Bool = false,
) -> Json {
  {
    "event_id": event,
    "audit_id": event + "-audit",
    "recorded_at": if action == "create" {
      Json::null()
    } else {
      Json::string("2026-10-01T08:00:00Z")
    },
    "command": {
      "command_family": if report {
        "delivery"
      } else {
        "plan_task"
      },
      "family": if report {
        "task_report"
      } else {
        "plan_task"
      },
      "command_type": action,
      "aggregate_id": if report {
        "report-H1"
      } else {
        "task-1"
      },
      "actor_id": if report {
        "reporter-1"
      } else {
        "owner-1"
      },
      "idempotency_key": "key-" + event,
      "request": request,
      "result": { "revision": revision, "state": "pending" },
    },
    "audit": {
      "event_id": event,
      "actor_id": if report {
        "reporter-1"
      } else {
        "owner-1"
      },
      "task_id": "task-1",
    },
  }
}

///|
fn journey_test_rows() -> Array[Json] {
  let source = human_revision_proj_source()
  [
    // Deliberately put acceptance before creation and leave creation undated.
    journey_test_row("update", "accepted-1", 4, {
      "task_id": "task-1",
      "changes": {
        "status": "done",
        "accepted_report_id": "report-H1",
        "accepted_delivery_source": source,
      },
    }),
    journey_test_row("create", "created-1", 1, {
      "task_id": "task-1",
      "project_id": "project-1",
      "task_name": "Inspect the buyer problem",
      "remarks": "Retain the chosen evidence",
      "owner_id": "assigned-1",
      "source_context": {
        "reference": "https://source.test/original",
        "problem": "Original question",
      },
      "offer_draft": offer_test_value(),
      "authority": { "secret": "DO-NOT-PROJECT-AUTHORITY" },
    }),
    journey_test_row("update", "reply-1", 2, {
      "task_id": "task-1",
      "changes": {
        "offer_reply": {
          "schema": "moonproj.offer-reply.v1",
          "offer_revision": 1,
          "kind": "interested",
          "summary": "Would like to discuss",
          "evidence_kind": "human_observation",
          "respondent": "Claimed buyer",
        },
      },
    }),
    journey_test_row(
      "create",
      "reported-1",
      1,
      {
        "task_id": "task-1",
        "report_id": "report-H1",
        "delivery_source": source,
      },
      report=true,
    ),
  ]
}

///|
fn journey_test_body(rows~ : Array[Json] = journey_test_rows()) -> String {
  let source = human_revision_proj_source()
  (
    {
      "data": {
        "task": {
          "taskGuid": "task-1",
          "projGuid": "project-1",
          "taskName": "Inspect the buyer problem",
          "status": "done",
          "revision": 4,
          "ownerGuid": "assigned-1",
          "source_context": {
            "reference": "https://source.test/current",
            "problem": "Current question",
          },
          "offer_draft": offer_test_value(),
          "accepted_report_id": "report-H1",
          "accepted_delivery_source": source,
          "selected_delivery_source": source,
          "human_revisions": [human_revision_proj_record()],
          "execution": {
            "run_id": "run-1",
            "task_id": "task-1",
            "session_id": "session-1",
            "command_id": "command-1",
            "workspace": "/workspace/book",
            "state": "completed",
            "output_urls": ["https://output.test/result.txt"],
          },
        },
        "reports": [
          {
            "reportGuid": "report-H1",
            "taskGuid": "task-1",
            "summary": "Retained result",
            "delivery_source": source,
          },
        ],
        "commitment": @task_evidence.receipt_history("task-1", rows),
      },
    } : Json).stringify()
}

///|
fn journey_test_model() -> Model {
  apply_dispatch_snapshot(
    {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_actor_id: "session-reader",
    },
    dispatch_decode_snapshot(journey_test_body(), "task-1").unwrap(),
  )
}

///|
#warnings("-alert_unstable")
fn journey_test_html(model : Model, whole~ : Bool = false) -> String {
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => {
    if whole {
      dispatch_durable_task_card(msg => emit(msg), model)
    } else {
      dispatch_journey_view(model)
    }
  })
  opc_render_cell(page)
}

///|
test "journey uses production persisted receipt projection canonical decode and immutable source" {
  let body = journey_test_body()
  let model = journey_test_model()
  let stages = dispatch_journey_stages(model)
  assert_eq(stages.map(stage => stage.id), [
    "source", "offer", "work", "result", "acceptance", "customer", "cash",
  ])
  assert_eq(stages[0].detail, "Current question")
  assert_eq(stages[0].records[0].reference, "https://source.test/original")
  assert_eq(stages[0].records[0].recorded_at, "")
  assert_eq(stages[1].state, "方案版本 1 · 1 条回复记录")
  assert_eq(stages[1].records[0].actor, "owner-1")
  assert_eq(stages[1].records[1].actor, "owner-1")
  assert_true(
    stages[1].records[1].detail.contains("转述回复者：Claimed buyer"),
  )
  assert_eq(stages[2].owner, "assigned-1")
  assert_eq(stages[3].records[0].event_id, "reported-1")
  assert_eq(stages[3].records[0].actor, "reporter-1")
  assert_true(
    stages[3].records[0].detail.contains(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
  )
  assert_eq(stages[4].state, "已关联内部验收收据")
  assert_eq(stages[4].owner, "owner-1")
  assert_eq(stages[5].state, "外部凭据尚未接入此视图")
  assert_eq(stages[6].state, "财务凭据尚未接入此视图")
  assert_false(body.contains("DO-NOT-PROJECT-AUTHORITY"))
  offer_serialized_write("MOONPROJ_JOURNEY_FIXTURE", body)
  offer_serialized_write(
    "MOONPROJ_JOURNEY_RENDER",
    journey_test_html(model, whole=true),
  )
}

///|
test "journey historical offer replies never become feedback on a later offer and local edits stay local" {
  let original = journey_test_model()
  let revised_offer = dispatch_offer_edit(
    offer_test_value(),
    "title",
    "New proposal",
  )
  let rows = journey_test_rows() +
    [
      journey_test_row("update", "offer-v5", 5, {
        "task_id": "task-1",
        "changes": { "offer_draft": revised_offer },
      }),
    ]
  let body = @json.parse(journey_test_body(rows~))
  let data = dispatch_json_field(body, "data")
  let task = dispatch_json_field(data, "task")
  if task is Object(fields) {
    fields["offer_draft"] = revised_offer
    fields["revision"] = Json::number(5)
  }
  let updated = apply_dispatch_snapshot(
    original,
    dispatch_decode_snapshot(body.stringify(), "task-1").unwrap(),
  )
  let stage = dispatch_journey_stages(updated)[1]
  assert_eq(stage.state, "方案版本 5 · 此版本尚无已核对回复")
  assert_eq(stage.records.length(), 3)
  assert_true(
    stage.records.any(record => {
      record.label.contains("方案版本 1 的回复")
    }),
  )
  let local_offer = {
    ..dispatch_offer_seed(updated),
    value: dispatch_offer_edit(revised_offer, "title", "UNSAVED EDIT"),
  }
  let unsaved = { ..updated, dispatch_offer_drafts: [local_offer], }
  assert_eq(dispatch_journey_stages(unsaved), dispatch_journey_stages(updated))
  assert_false(journey_test_html(unsaved).contains("UNSAVED EDIT"))
}

///|
test "journey independent acceptance requires matching report source and receipt audit" {
  let ready = journey_test_model()
  let receipt = dispatch_journey_receipts(ready, "internal_acceptance")[0]
  for
    altered in [
      lesson_receipt_test_set(receipt, "audit_state", Json::string("missing")),
      lesson_receipt_test_set(
        receipt,
        "report_id",
        Json::string("different-report"),
      ),
      lesson_receipt_test_set(
        receipt,
        "delivery_source",
        human_revision_proj_source(id="H2"),
      ),
    ] {
    let model = {
      ..ready,
      dispatch_task_commitment: lesson_receipt_test_set(
        ready.dispatch_task_commitment,
        "receipts",
        Json::array([altered]),
      ),
    }
    assert_true(dispatch_journey_stages(model)[4].state.contains("待核对"))
    assert_eq(
      dispatch_journey_stages(model)[5].state,
      "外部凭据尚未接入此视图",
    )
  }
  for
    state in [
      { ..ready.dispatch_continuation, report_records: [], },
      { ..ready.dispatch_continuation, source_verified: false, },
      { ..ready.dispatch_continuation, accepted_report_id: "another-report", },
      {
        ..ready.dispatch_continuation,
        accepted_delivery_source: human_revision_proj_source(id="H2"),
      },
    ] {
    assert_true(
      dispatch_journey_stages({ ..ready, dispatch_continuation: state, })[4].state.contains(
        "待核对",
      ),
    )
  }
}

///|
test "journey failed refresh and older callback retain exact known record and disclose uncertainty" {
  let ready = journey_test_model()
  let (_, loading) = update(
    _ => none,
    RefreshDispatchTask("task-1", ready.dispatch_task_selection),
    ready,
  )
  assert_eq(dispatch_journey_stages(loading), dispatch_journey_stages(ready))
  assert_true(journey_test_html(loading).contains("正在刷新"))
  let (_, failed) = update(
    _ => none,
    DispatchTaskCommandFailed(
      "task-1",
      ready.dispatch_task_selection,
      "读取任务",
      "offline",
    ),
    loading,
  )
  assert_eq(dispatch_journey_stages(failed), dispatch_journey_stages(ready))
  assert_true(journey_test_html(failed).contains("上次成功读取的记录"))
  assert_eq(failed.dispatch_journey_read_state, "unconfirmed")
  let (_, reloading) = update(
    _ => none,
    RefreshDispatchTask("task-1", ready.dispatch_task_selection),
    failed,
  )
  let old = {
    ..dispatch_decode_snapshot(journey_test_body(), "task-1").unwrap(),
    revision: 1.0,
    title: "OLDER TITLE",
    source_context: Json::null(),
  }
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded("task-1", ready.dispatch_task_selection, old),
    reloading,
  )
  assert_eq(dispatch_journey_stages(stale), dispatch_journey_stages(ready))
  assert_eq(stale.dispatch_journey_read_state, "older")
  assert_false(journey_test_html(stale, whole=true).contains("OLDER TITLE"))
  let (_, refreshed) = update(
    _ => none,
    DispatchTaskLoaded(
      "task-1",
      ready.dispatch_task_selection,
      dispatch_decode_snapshot(journey_test_body(), "task-1").unwrap(),
    ),
    stale,
  )
  assert_eq(refreshed.dispatch_journey_read_state, "loaded")
}

///|
test "journey task and actor switches clear prior observation and fence late callbacks" {
  let ready = journey_test_model()
  let (_, opened) = open_dispatch_task(_ => none, {
    ..ready,
    dispatch_task_open_id: "task-2",
  })
  assert_eq(journey_test_html(opened), "")
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded(
      "task-1",
      ready.dispatch_task_selection,
      dispatch_decode_snapshot(journey_test_body(), "task-1").unwrap(),
    ),
    opened,
  )
  assert_eq(journey_test_html(stale), "")
  assert_eq(stale.dispatch_task_id, "task-2")
  for actor in ["", "different-reader"] {
    let (_, changed) = update(_ => none, DispatchSessionLoaded(actor), ready)
    assert_eq(journey_test_html(changed), "")
    assert_true(changed.dispatch_task_source_context is Null)
    assert_true(changed.dispatch_task_commitment is Null)
    let (_, late) = update(
      _ => none,
      DispatchTaskLoaded(
        "task-1",
        ready.dispatch_task_selection,
        dispatch_decode_snapshot(journey_test_body(), "task-1").unwrap(),
      ),
      changed,
    )
    assert_eq(journey_test_html(late), "")
  }
}

///|
test "journey all anchors resolve for accepted and report without run and render has no command effects" {
  let ready = journey_test_model()
  for model in [ready, { ..ready, dispatch_run: None, }] {
    let history = model.dispatch_task_commitment.stringify()
    let html = journey_test_html(model, whole=true)
    for stage in dispatch_journey_stages(model) {
      if !stage.anchor.is_empty() {
        let id = stage.anchor.strip_prefix("#").unwrap().to_owned()
        assert_true(html.contains("id=\"" + id + "\""))
        assert_true(html.contains("href=\"" + stage.anchor + "\""))
      }
    }
    assert_true(html.contains("<summary>任务身份与收据</summary>"))
    assert_eq(model.dispatch_task_commitment.stringify(), history)
    assert_eq(model.dispatch_task_stage, "accepted")
    assert_eq(model.dispatch_task_pending_action, "")
    assert_eq(model.dispatch_drafts.length(), 0)
    assert_false(journey_test_html(model).contains("<button"))
    assert_true(journey_test_html(model).contains("<ol"))
  }
}

///|
test "journey unknown timestamps missing histories and unsafe source remain explicit and escaped" {
  let ready = journey_test_model()
  let model = {
    ..ready,
    dispatch_task_commitment: Json::null(),
    dispatch_task_source_context: {
      "reference": "javascript:alert(1)",
      "problem": "<script>not executable</script>",
    },
    dispatch_task_owner_id: "",
  }
  let stages = dispatch_journey_stages(model)
  assert_eq(stages[1].state, "方案已读回，版本关联待核对")
  assert_true(stages[4].state.contains("待核对"))
  let html = journey_test_html(model)
  assert_false(html.contains("href=\"javascript:"))
  assert_false(html.contains("<script>"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_true(journey_test_html(ready).contains("记录时间 · 未记录"))
  let unrelated = {
    ..ready,
    dispatch_task_commitment: lesson_receipt_test_set(
      ready.dispatch_task_commitment,
      "task_id",
      Json::string("wrong-task"),
    ),
  }
  assert_true(
    dispatch_journey_stages(unrelated)[0].records[0].event_id.is_empty(),
  )
  assert_eq(dispatch_journey_stages(unrelated)[1].records.length(), 0)
}

///|
test "journey viewing another report never rewrites accepted identity or retained digest" {
  let ready = journey_test_model()
  let model = {
    ..ready,
    dispatch_task_report_id: "report-H2",
    dispatch_continuation: {
      ..ready.dispatch_continuation,
      report_source: human_revision_proj_source(id="H2"),
      selected: human_revision_proj_source(id="H2"),
      human_revisions: ready.dispatch_continuation.human_revisions +
      [human_revision_proj_record(id="H2")],
      report_records: ready.dispatch_continuation.report_records +
      [
        {
          "reportGuid": "report-H2",
          "delivery_source": human_revision_proj_source(id="H2"),
        },
      ],
    },
  }
  assert_eq(
    dispatch_journey_stages(model)[4],
    dispatch_journey_stages(ready)[4],
  )
  assert_eq(dispatch_journey_stages(model)[3].records.length(), 2)
  assert_eq(
    dispatch_journey_stages(model)[3].records[0],
    dispatch_journey_stages(ready)[3].records[0],
  )
  assert_eq(
    dispatch_journey_stages(model)[5].state,
    "外部凭据尚未接入此视图",
  )
  assert_eq(
    dispatch_journey_stages(model)[6].state,
    "财务凭据尚未接入此视图",
  )
}

///|
test "journey corrections preserve originals and only audited same-offer corrections supersede" {
  let model = journey_test_model()
  let original = dispatch_reply_history(model)[0]
  let value = dispatch_json_field(original, "offer_reply")
  let correction_value = lesson_receipt_test_set(
    lesson_receipt_test_set(
      value,
      "supersedes_reply_id",
      Json::string("reply-1"),
    ),
    "correction_reason",
    Json::string("Corrected observation"),
  )
  let correction = lesson_receipt_test_set(
    lesson_receipt_test_set(original, "reply_id", Json::string("reply-2")),
    "offer_reply",
    correction_value,
  )
  assert_true(
    dispatch_journey_reply_superseded([original, correction], original),
  )
  for
    candidate in [
      lesson_receipt_test_set(
        correction,
        "audit_state",
        Json::string("missing"),
      ),
      lesson_receipt_test_set(
        correction,
        "offer_reply",
        lesson_receipt_test_set(
          correction_value,
          "offer_revision",
          Json::number(3),
        ),
      ),
    ] {
    assert_false(
      dispatch_journey_reply_superseded([original, candidate], original),
    )
  }
  let updated = {
    ..model,
    dispatch_task_commitment: lesson_receipt_test_set(
      model.dispatch_task_commitment,
      "offer_reply_history",
      Json::array([original, correction]),
    ),
  }
  assert_eq(
    dispatch_journey_stages(updated)[1].state,
    "方案版本 1 · 1 条回复记录",
  )
  assert_eq(dispatch_journey_stages(updated)[1].records.length(), 3)
  assert_true(
    dispatch_journey_stages(updated)[1].records[1].detail.contains(
      "已有更正",
    ),
  )
  assert_false(
    dispatch_journey_stages(updated)[1].records[2].detail.contains(
      "已有更正",
    ),
  )
}

///|
test "journey unknown task state and conflicting source records never invent completed lineage" {
  let model = journey_test_model()
  assert_eq(
    dispatch_journey_stages({ ..model, dispatch_task_stage: "future-state", })[2].state,
    "任务状态待核对",
  )
  let source = human_revision_proj_source()
  let duplicate = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      human_revisions: [
        human_revision_proj_record(),
        human_revision_proj_record(),
      ],
    },
  }
  assert_true(dispatch_journey_source(duplicate, source).contains("待核对"))
  assert_true(
    dispatch_journey_source(
      model,
      lesson_receipt_test_set(
        source,
        "original_run_id",
        Json::string("another-run"),
      ),
    ).contains("待核对"),
  )
  let row = dispatch_continuation_array(
      model.dispatch_task_commitment,
      "offer_history",
    )[0]
  assert_false(
    dispatch_journey_offer_current(
      lesson_receipt_test_set(row, "audit_state", Json::string("missing")),
      offer_test_value(),
      1,
    ),
  )
  assert_false(
    dispatch_journey_offer_current(
      lesson_receipt_test_set(
        row,
        "offer_draft",
        dispatch_offer_edit(offer_test_value(), "title", "different"),
      ),
      offer_test_value(),
      1,
    ),
  )
}

///|
test "journey production GET consumes projected canonical bytes and rendering issues no request" {
  let emitted : Array[Msg] = []
  let states : Array[Model] = []
  let captures : Array[String] = []
  offer_transport_browser(() => {
    let emit : @rabbita.Emit[Msg] = msg => {
      emitted.push(msg)
      none
    }
    let ready = journey_test_model()
    let (get, loading) = update(
      emit,
      RefreshDispatchTask("task-1", ready.dispatch_task_selection),
      ready,
    )
    drafts_test_execute(get)
    offer_transport_respond(200, journey_test_body())
    let (_, loaded) = update(emit, emitted[0], loading)
    ignore(journey_test_html(loaded, whole=true))
    ignore(journey_test_html(loaded, whole=true))
    states.push(loaded)
    captures.push(offer_transport_state())
  })
  let requests = dispatch_continuation_array(
    @json.parse(captures[0]),
    "requests",
  )
  assert_eq(requests.length(), 1)
  assert_eq(dispatch_json_text(requests[0], "method"), "GET")
  assert_eq(dispatch_json_text(requests[0], "url"), "/api/company/tasks/task-1")
  assert_eq(dispatch_json_field(requests[0], "body"), Json::null())
  assert_eq(states[0].dispatch_journey_read_state, "loaded")
  assert_eq(
    dispatch_journey_stages(states[0]),
    dispatch_journey_stages(journey_test_model()),
  )
}
