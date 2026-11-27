///|
fn continuation_proj_record(
  id~ : String = "K1",
  command~ : String = "C1",
  state~ : String = "completed",
) -> Json {
  {
    "continuation_id": id,
    "original_run_id": "run-1",
    "task_id": "task-1",
    "session_id": "session-1",
    "original_command_id": "command-1",
    "prior_result_command_id": "command-1",
    "command_id": command,
    "client_turn_id": "turn-" + id,
    "workspace": "/workspace/book",
    "model": "captured-model",
    "input": {
      "path": "captured/" + id + "/input.md",
      "sha256": "input-hash-" + id,
    },
    "state": state,
    "summary": "Exact result " + command,
    "error": "",
    "receipt": { "command_id": command, "status": "runtime-completed" },
    "evidence_ids": ["evidence-" + command],
    "output_urls": ["https://example.test/" + command],
    "artifact_refs": [
      {
        "command_id": command,
        "path": command + ".txt",
        "evidence_id": "file-" + command,
      },
    ],
  }
}

///|
fn continuation_proj_source(
  command~ : String = "C1",
  id~ : String = "K1",
) -> Json {
  {
    "type": "continuation",
    "continuation_id": id,
    "original_run_id": "run-1",
    "command_id": command,
  }
}

///|
fn continuation_proj_model() -> Model {
  let model = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_id: "task-1",
    dispatch_task_selection: 3,
    dispatch_task_stage: "in_progress",
    dispatch_task_actor_id: "actor-a",
    dispatch_task_project_id: "project-1",
    dispatch_run: Some(dispatch_test_run("completed")),
  }
  {
    ..model,
    dispatch_continuation: {
      ..empty_dispatch_continuation(),
      task_id: "task-1",
      selection: 3,
      actor: "actor-a",
      phase: "ready",
      source_verified: true,
      candidate: continuation_proj_record(),
      records: [
        continuation_proj_record(),
        continuation_proj_record(id="K2", command="C2"),
      ],
    },
  }
}

///|
fn continuation_proj_envelope(
  model : Model,
  source : Json,
  candidate : Json,
) -> String {
  (
    {
      "schema": "moonproj.task-continuations.v1",
      "task_id": "task-1",
      "original_run_id": "run-1",
      "session_id": "session-1",
      "original_command_id": "command-1",
      "workspace": "/workspace/book",
      "acceptance": "pending",
      "continuations": ToJson::to_json(model.dispatch_continuation.records),
      "selected_delivery_source": source,
      "candidate": candidate,
      "candidates": [],
      "candidate_state": "ready",
    } : Json).stringify()
}

///|
fn continuation_proj_confirm(model : Model, source : Json) -> Model {
  let state = dispatch_continuation_decode(
    model,
    model.dispatch_continuation,
    continuation_proj_envelope(
      model,
      source,
      model.dispatch_continuation.candidate,
    ),
  ).unwrap()
  { ..model, dispatch_continuation: state, }
}

///|
extern "js" fn continuation_proj_storage_setup() -> Int32 =
  #| () => { globalThis.__continuationPriorStorage = globalThis.localStorage; const data = new Map(); globalThis.localStorage = {getItem:key=>data.get(key)||null,setItem:(key,value)=>data.set(key,value),removeItem:key=>data.delete(key)}; return 0; }

///|
extern "js" fn continuation_proj_storage_cleanup(previous : Int32) =
  #| _ => { const previous = globalThis.__continuationPriorStorage; if (previous === undefined) delete globalThis.localStorage; else globalThis.localStorage = previous; delete globalThis.__continuationPriorStorage; }

///|
test "returned exact candidate stays preview only and later C2 cannot select itself" {
  let model = continuation_proj_model()
  let state = { ..model.dispatch_continuation, preview_command: "C1", }
  let decoded = dispatch_continuation_decode(
    model,
    state,
    continuation_proj_envelope(model, Json::null(), continuation_proj_record()),
  ).unwrap()
  assert_eq(dispatch_json_text(decoded.candidate, "command_id"), "C1")
  assert_true(decoded.selected is Null)
  let mismatched = dispatch_continuation_decode(
    model,
    state,
    continuation_proj_envelope(
      model,
      Json::null(),
      continuation_proj_record(id="K2", command="C2"),
    ),
  ).unwrap()
  assert_true(mismatched.candidate is Null)
  let selected = dispatch_continuation_decode(
    model,
    state,
    continuation_proj_envelope(
      model,
      continuation_proj_source(),
      continuation_proj_record(id="K2", command="C2"),
    ),
  ).unwrap()
  assert_eq(dispatch_json_text(selected.selected, "command_id"), "C1")
}

///|
test "selection operations are durable before POST and C1 C2 C1 each deliberate selection gets new identity" {
  let prior = continuation_proj_storage_setup()
  let emitted : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = msg => {
    emitted.push(msg)
    none
  }
  let model = continuation_proj_model()
  let (store, saving) = dispatch_continuation_update(emit, Select, model)
  assert_eq(saving.dispatch_continuation.phase, "saving")
  assert_eq(emitted.length(), 0)
  drafts_test_execute(store)
  assert_eq(emitted.length(), 1)
  let restored = dispatch_selection_restore(model)
  assert_eq(
    dispatch_json_field(restored, "body"),
    saving.dispatch_continuation.operation,
  )
  assert_true(dispatch_json_field(restored, "pending") is True)
  let key1 = dispatch_json_text(
    saving.dispatch_continuation.operation,
    "idempotency_key",
  )
  assert_true(key1.length() < 128)
  let selected1 = continuation_proj_confirm(saving, continuation_proj_source())
  assert_false(selected1.dispatch_continuation.operation_pending)
  let (_, saving2) = dispatch_continuation_update(emit, Select, {
    ..selected1,
    dispatch_continuation: {
      ..selected1.dispatch_continuation,
      candidate: continuation_proj_record(id="K2", command="C2"),
    },
  })
  let selected2 = continuation_proj_confirm(
    saving2,
    continuation_proj_source(command="C2", id="K2"),
  )
  let (_, saving3) = dispatch_continuation_update(emit, Select, {
    ..selected2,
    dispatch_continuation: {
      ..selected2.dispatch_continuation,
      candidate: continuation_proj_record(),
    },
  })
  assert_true(
    dispatch_json_text(
      saving2.dispatch_continuation.operation,
      "idempotency_key",
    ) !=
    key1,
  )
  assert_true(
    dispatch_json_text(
      saving3.dispatch_continuation.operation,
      "idempotency_key",
    ) !=
    key1,
  )
  assert_eq(
    dispatch_selection_target(saving3.dispatch_continuation.operation),
    continuation_proj_source(),
  )
  continuation_proj_storage_cleanup(prior)
}

///|
test "original C1 original and lost response retry preserve operation versus source distinction" {
  let model = continuation_proj_model()
  let original : Json = {
    "type": "original",
    "original_run_id": "run-1",
    "command_id": "command-1",
  }
  let (_, first) = dispatch_continuation_update(
    _ => none,
    SelectOriginal,
    model,
  )
  let settled = continuation_proj_confirm(first, original)
  let (_, following) = dispatch_continuation_update(_ => none, Select, settled)
  let key = dispatch_json_text(
    following.dispatch_continuation.operation,
    "idempotency_key",
  )
  let (_, retrying) = dispatch_continuation_update(_ => none, Select, {
    ..following,
    dispatch_continuation: {
      ..following.dispatch_continuation,
      phase: "ready",
    },
  })
  assert_eq(
    dispatch_json_text(
      retrying.dispatch_continuation.operation,
      "idempotency_key",
    ),
    key,
  )
  let settled = continuation_proj_confirm(retrying, continuation_proj_source())
  let (_, back) = dispatch_continuation_update(
    _ => none,
    SelectOriginal,
    settled,
  )
  assert_true(
    dispatch_json_text(back.dispatch_continuation.operation, "idempotency_key") !=
    dispatch_json_text(first.dispatch_continuation.operation, "idempotency_key"),
  )
  assert_eq(
    dispatch_selection_target(back.dispatch_continuation.operation),
    original,
  )
}

///|
test "replayed old C1 operation acknowledgement retires while actual C2 remains selected" {
  let model = continuation_proj_model()
  let (_, pending) = dispatch_continuation_update(_ => none, Select, model)
  let response : Json = {
    "schema": "moonproj.task-continuations.v1",
    "task_id": "task-1",
    "acceptance": "pending",
    "inspection_only": false,
    "idempotent_replay": true,
    "operation_applied": true,
    "operation_idempotency_key": dispatch_json_field(
      pending.dispatch_continuation.operation,
      "idempotency_key",
    ),
    "operation_source": continuation_proj_source(),
    "continuations": ToJson::to_json(model.dispatch_continuation.records),
    "selected_delivery_source": continuation_proj_source(command="C2", id="K2"),
    "task": {
      "taskGuid": "task-1",
      "execution": {
        "run_id": "run-1",
        "command_id": "command-1",
        "session_id": "session-1",
      },
    },
  }
  let acknowledged = dispatch_selection_ack_state(pending, response.stringify()).unwrap()
  assert_false(acknowledged.operation_pending)
  assert_eq(dispatch_json_text(acknowledged.selected, "command_id"), "C2")
  let (_, new_selection) = dispatch_continuation_update(_ => none, Select, {
    ..pending,
    dispatch_continuation: acknowledged,
  })
  assert_true(
    dispatch_json_text(
      new_selection.dispatch_continuation.operation,
      "idempotency_key",
    ) !=
    dispatch_json_text(
      pending.dispatch_continuation.operation,
      "idempotency_key",
    ),
  )
}

///|
test "persisted completed original and selected continuation remain reportable with discovery offline" {
  let model = continuation_proj_model()
  for source in [Json::null(), continuation_proj_source()] {
    let ready = continuation_proj_confirm(model, source)
    let unavailable = {
      ..ready,
      dispatch_continuation: {
        ..ready.dispatch_continuation,
        phase: "unavailable",
        error: "native runtime unavailable",
      },
    }
    assert_true(dispatch_can_submit(unavailable))
    assert_eq(unavailable.dispatch_run, model.dispatch_run)
  }
  let unverified = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      selected: continuation_proj_source(),
      source_verified: false,
    },
  }
  assert_false(dispatch_can_submit(unverified))
}

///|
test "formal task snapshot supplies persisted result source before optional candidate lookup" {
  let model = continuation_proj_model()
  let snapshot = {
    ..dispatch_test_snapshot("failed"),
    continuation_records: [continuation_proj_record()],
    delivery_source: continuation_proj_source(),
  }
  let fresh = { ..model, dispatch_continuation: empty_dispatch_continuation(), }
  let restored = apply_dispatch_snapshot(fresh, snapshot)
  assert_true(restored.dispatch_continuation.source_verified)
  assert_true(dispatch_can_submit(restored))
  assert_eq(restored.dispatch_run.unwrap().state, "failed")
  assert_eq(dispatch_report_evidence(restored), ["evidence-C1"])
  assert_true(dispatch_report_summary(restored).contains("C1"))
}

///|
test "completed exact source only selects and failed pending control result cannot report" {
  let model = continuation_proj_model()
  for
    state in [
      "queued", "running", "failed", "cancelled", "delivered", "invalid",
    ] {
    let candidate = continuation_proj_record(state~)
    let pending = {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        candidate,
        records: [candidate],
        selected: continuation_proj_source(),
      },
    }
    let (_, unchanged) = dispatch_continuation_update(
      _ => none,
      Select,
      pending,
    )
    assert_true(unchanged.dispatch_continuation.operation is Null)
    assert_false(dispatch_can_submit(pending))
  }
}

///|
test "accepted task and changed actor reject late responses and saved operation replay" {
  let prior = continuation_proj_storage_setup()
  let model = continuation_proj_model()
  let (_, saving) = dispatch_continuation_update(_ => none, Select, model)
  assert_true(
    dispatch_selection_store(
      dispatch_selection_key(saving),
      saving.dispatch_continuation.operation.stringify(),
      true,
    ),
  )
  let (_, switched) = update(
    _ => none,
    DispatchSessionLoaded("actor-b"),
    saving,
  )
  assert_true(switched.dispatch_run is None)
  assert_eq(switched.dispatch_continuation.records.length(), 0)
  assert_true(dispatch_selection_restore(switched) is Null)
  let (_, late) = dispatch_continuation_update(
    _ => none,
    Attached("task-1", 3, saving.dispatch_continuation.request, "", Ok("{}")),
    switched,
  )
  assert_true(late.dispatch_run is None)
  let (_, accepted) = dispatch_continuation_update(_ => none, Select, {
    ..model,
    dispatch_task_stage: "accepted",
  })
  assert_true(accepted.dispatch_continuation.operation is Null)
  continuation_proj_storage_cleanup(prior)
}

///|
test "C0 report then C1 source requires another exact report before explicit acceptance" {
  let model = continuation_proj_model()
  let old_report : Json = {
    "reportGuid": "report-C0",
    "summary": "Original report",
    "delivery_source": Json::null(),
    "evidence_ids": ["old-report-evidence"],
  }
  let current = {
    ..continuation_proj_confirm(model, continuation_proj_source()),
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "report-C0",
    dispatch_task_evidence_id: "old-report-evidence",
    dispatch_continuation: {
      ..continuation_proj_confirm(model, continuation_proj_source()).dispatch_continuation,
      report_records: [old_report],
      report_source: Json::null(),
    },
  }
  assert_true(dispatch_can_submit(current))
  assert_false(dispatch_can_accept_report(current))
  assert_eq(dispatch_report_evidence(current), ["evidence-C1"])
  let new_report : Json = {
    "reportGuid": "report-C1",
    "summary": "Follow-up report",
    "delivery_source": continuation_proj_source(),
    "evidence_ids": ["evidence-C1"],
  }
  let (_, chosen) = dispatch_continuation_update(
    _ => none,
    SelectReport("report-C1"),
    {
      ..current,
      dispatch_continuation: {
        ..current.dispatch_continuation,
        report_records: [old_report, new_report],
      },
    },
  )
  assert_true(dispatch_can_accept_report(chosen))
  assert_false(dispatch_can_submit(chosen))
  let body = dispatch_accept_report_body(chosen, "accept-op")
  assert_eq(dispatch_json_text(body, "report_id"), "report-C1")
  assert_eq(
    dispatch_json_field(body, "delivery_source"),
    continuation_proj_source(),
  )
  assert_eq(chosen.dispatch_continuation.report_records[0], old_report)
}

///|
test "report submission lost response reload retains exact key id summary source and evidence" {
  let prior = continuation_proj_storage_setup()
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let first = dispatch_new_report_body(model)
  assert_true(
    dispatch_selection_store(
      dispatch_report_operation_key(model),
      first.stringify(),
      true,
    ),
  )
  let retrying = dispatch_report_operation_body(
    model,
    dispatch_new_report_body(model),
  ).unwrap()
  assert_eq(retrying, first)
  let record : Json = {
    "reportGuid": dispatch_json_field(first, "report_id"),
    "delivery_source": continuation_proj_source(),
  }
  let settled = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      report_records: [record],
    },
  }
  let another = dispatch_report_operation_body(
    settled,
    dispatch_new_report_body(settled),
  ).unwrap()
  assert_true(
    dispatch_json_text(another, "report_id") !=
    dispatch_json_text(first, "report_id"),
  )
  assert_eq(
    dispatch_json_field(retrying, "delivery_source"),
    continuation_proj_source(),
  )
  assert_false(retrying.stringify().contains("authority"))
  continuation_proj_storage_cleanup(prior)
}

///|
test "explicit original report evidence does not absorb earlier C1 report evidence" {
  let model = continuation_proj_model()
  let original : Json = {
    "type": "original",
    "original_run_id": "run-1",
    "command_id": "command-1",
  }
  let model = {
    ..continuation_proj_confirm(model, original),
    dispatch_task_evidence_id: "evidence-C1\nother-old-report",
  }
  assert_eq(
    dispatch_report_evidence(model),
    model.dispatch_run.unwrap().evidence_ids,
  )
}

///|
test "navigation candidates require exact task run and encoded return never authorize selection" {
  assert_eq(
    dispatch_continuation_return_hint(
      "https://proj.example/?task=task-1&source_run=run-1&continuation_id=K1&continuation_command=C1",
      "task-1", "run-1",
    ),
    "C1",
  )
  assert_eq(
    dispatch_continuation_return_hint(
      "https://proj.example/?task=task-1&source_run=other&continuation_id=K1&continuation_command=C2",
      "task-1", "run-1",
    ),
    "",
  )
  let model = continuation_proj_model()
  let (_, pending) = dispatch_continuation_update(
    _ => none,
    Preview("C1"),
    model,
  )
  let (_, stale) = dispatch_continuation_update(
    _ => none,
    Loaded(
      "task-1",
      2,
      pending.dispatch_continuation.request,
      "",
      "C1",
      Ok(
        continuation_proj_envelope(
          model,
          continuation_proj_source(),
          continuation_proj_record(),
        ),
      ),
    ),
    pending,
  )
  assert_true(stale.dispatch_continuation.selected is Null)
}

///|
#warnings("-alert_unstable")
test "UI shows exact candidate input result source and report identity separately" {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let model = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      candidate: continuation_proj_record(),
    },
  }
  let cell = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => dispatch_continuation_view(msg => emit(msg), model))
  let html = opc_render_cell(cell)
  for
    text in [
      "C1", "input-hash-K1", "Exact result C1", "captured-model", "evidence-C1",
      "准确报告", "不会自动提交报告",
    ] {
    assert_true(html.contains(text), msg=text)
  }
}

///|
test "newer task revision updates offline source while older callback cannot reverse it" {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let model = {
    ..model,
    dispatch_continuation: {
      ..model.dispatch_continuation,
      revision: 4.0,
      phase: "unavailable",
    },
  }
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    revision: 5.0,
    continuation_records: model.dispatch_continuation.records,
    delivery_source: continuation_proj_source(command="C2", id="K2"),
  }
  let newer = apply_dispatch_snapshot(model, snapshot)
  assert_eq(
    dispatch_json_text(newer.dispatch_continuation.selected, "command_id"),
    "C2",
  )
  assert_true(dispatch_can_submit(newer))
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 3, {
      ..snapshot,
      revision: 4.0,
      delivery_source: continuation_proj_source(),
    }),
    newer,
  )
  assert_eq(
    dispatch_json_text(stale.dispatch_continuation.selected, "command_id"),
    "C2",
  )
  let listed = dispatch_continuation_decode(
    newer,
    newer.dispatch_continuation,
    continuation_proj_envelope(
      newer,
      continuation_proj_source(),
      continuation_proj_record(),
    ),
  ).unwrap()
  assert_eq(dispatch_json_text(listed.selected, "command_id"), "C2")
}

///|
test "chosen immutable report survives refresh and accepted report is pinned and labelled" {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let old : Json = {
    "reportGuid": "old",
    "summary": "C0 report",
    "delivery_source": Json::null(),
  }
  let chosen : Json = {
    "reportGuid": "chosen",
    "summary": "C1 report",
    "delivery_source": continuation_proj_source(),
  }
  let model = { ..model, dispatch_task_report_id: "chosen", }
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    report_id: "old",
    report_summary: "C0 report",
    report_records: [old, chosen],
    continuation_records: model.dispatch_continuation.records,
    delivery_source: continuation_proj_source(),
  }
  let refreshed = apply_dispatch_snapshot(model, snapshot)
  assert_eq(refreshed.dispatch_task_report_id, "chosen")
  assert_eq(refreshed.dispatch_task_report_summary, "C1 report")
  let accepted = apply_dispatch_snapshot(
    { ..refreshed, dispatch_task_report_id: "old", },
    {
      ..snapshot,
      revision: 10.0,
      state: "done",
      accepted_report_id: "chosen",
      accepted_delivery_source: continuation_proj_source(),
    },
  )
  assert_eq(accepted.dispatch_task_report_id, "chosen")
  assert_eq(accepted.dispatch_continuation.accepted_report_id, "chosen")
  assert_false(dispatch_can_submit(accepted))
  assert_false(dispatch_can_accept_report(accepted))
}

///|
test "source-less legacy report needs new attributed report after explicit original selection" {
  let model = continuation_proj_model()
  let model = {
    ..model,
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "legacy-report",
  }
  assert_true(dispatch_can_accept_report(model))
  let original : Json = {
    "type": "original",
    "original_run_id": "run-1",
    "command_id": "command-1",
  }
  let explicit = continuation_proj_confirm(model, original)
  assert_false(dispatch_can_accept_report(explicit))
  assert_true(dispatch_can_submit(explicit))
  let attributed = {
    ..explicit,
    dispatch_continuation: {
      ..explicit.dispatch_continuation,
      report_source: original,
    },
  }
  assert_true(dispatch_can_accept_report(attributed))
}

///|
test "continuation storage failure never sends and retry reuses unsent bounded operation" {
  let model = continuation_proj_model()
  let (_, saving) = dispatch_continuation_update(_ => none, Select, model)
  let (_, failed) = dispatch_continuation_update(
    _ => none,
    SelectionStored(
      "task-1",
      3,
      saving.dispatch_continuation.request,
      "",
      false,
    ),
    saving,
  )
  assert_eq(failed.dispatch_continuation.phase, "ready")
  assert_true(failed.dispatch_continuation.operation_pending)
  let (_, retrying) = dispatch_continuation_update(_ => none, Select, failed)
  assert_eq(
    retrying.dispatch_continuation.operation,
    saving.dispatch_continuation.operation,
  )
  assert_true(
    dispatch_json_text(
      retrying.dispatch_continuation.operation,
      "idempotency_key",
    ).length() <
    128,
  )
}

///|
test "return followup handoff requires authoritative nonaccepted mode" {
  let inspect = handoff_proj_fixture()
  assert_true(
    dispatch_desk_handoff_url(
      inspect,
      "task-1",
      "https://proj.example/?task=task-1",
      follow_up=true,
    )
    is Err(_),
  )
  let json = @json.parse(inspect)
  if json is Object(fields) {
    fields["task_accepted"] = false
    fields["mode"] = "follow_up"
  }
  let url = dispatch_desk_handoff_url(
    json.stringify(),
    "task-1",
    "https://proj.example/?task=task-1",
    follow_up=true,
  ).unwrap()
  assert_true(url.contains("work_mode=follow_up"))
}

///|
test "legacy original report posts without local storage and retries use exact in-memory body" {
  drafts_navigation_setup("https://proj.example/?task=task-1", "uuid")
  let model = continuation_proj_model()
  assert_false(dispatch_report_requires_capture(model))
  let (command, pending) = update(_ => none, SubmitDispatchTask, model)
  drafts_test_execute(command)
  assert_true(
    drafts_navigation_requests().contains(
      "POST /api/company/plan/tasks/task-1/report",
    ),
  )
  let captured = pending.dispatch_continuation.report_operation
  assert_eq(dispatch_json_field(captured, "delivery_source"), {
    "type": "original",
    "original_run_id": "run-1",
    "command_id": "command-1",
  })
  assert_true(pending.dispatch_continuation.report_operation_pending)
  let (_, retrying) = update(_ => none, SubmitDispatchTask, {
    ..pending,
    dispatch_task_pending_action: "",
  })
  assert_eq(retrying.dispatch_continuation.report_operation, captured)
  drafts_navigation_cleanup()
}

///|
test "older outstanding task read retires load without replacing newer source and can retry" {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let loading = {
    ..model,
    dispatch_task_pending_action: "load",
    dispatch_continuation: { ..model.dispatch_continuation, revision: 6.0, },
  }
  let (_, retained) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 3, {
      ..dispatch_test_snapshot("failed"),
      revision: 5.0,
    }),
    loading,
  )
  assert_eq(retained.dispatch_task_pending_action, "")
  assert_eq(retained.dispatch_run.unwrap().state, "completed")
  assert_eq(retained.dispatch_continuation.selected, continuation_proj_source())
  let (_, retrying) = update(
    _ => none,
    RefreshDispatchTask("task-1", 3),
    retained,
  )
  assert_eq(retrying.dispatch_task_pending_action, "load")
  let accepted = {
    ..model,
    dispatch_task_stage: "accepted",
    dispatch_continuation: {
      ..model.dispatch_continuation,
      revision: 6.0,
      accepted: true,
    },
  }
  assert_eq(
    apply_dispatch_snapshot(accepted, {
      ..dispatch_test_snapshot("failed"),
      revision: 5.0,
    }).dispatch_task_stage,
    "accepted",
  )
}

///|
test "acknowledged report survives older same revision report collection" {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  let captured = dispatch_new_report_body(model)
  let id = dispatch_json_text(captured, "report_id")
  let waiting = {
    ..model,
    dispatch_task_pending_action: "submit",
    dispatch_continuation: {
      ..model.dispatch_continuation,
      report_operation: captured,
      report_operation_pending: true,
    },
  }
  let (_, acknowledged) = update(
    _ => none,
    DispatchTaskSubmitted("task-1", 3, id, "event", "audit"),
    waiting,
  )
  assert_eq(acknowledged.dispatch_continuation.report_records.length(), 1)
  let older_report : Json = {
    "reportGuid": "R1",
    "summary": "Old C0 report",
    "delivery_source": Json::null(),
  }
  let stale = {
    ..dispatch_test_snapshot("completed"),
    report_id: "R1",
    report_summary: "Old C0 report",
    report_records: [older_report],
    continuation_records: model.dispatch_continuation.records,
    delivery_source: continuation_proj_source(),
  }
  let retained = apply_dispatch_snapshot(acknowledged, stale)
  assert_eq(retained.dispatch_task_report_id, id)
  assert_eq(retained.dispatch_continuation.report_records.length(), 2)
  assert_eq(
    retained.dispatch_continuation.report_source,
    continuation_proj_source(),
  )
  assert_true(dispatch_can_accept_report(retained))
  let fresh = apply_dispatch_snapshot(retained, {
    ..stale,
    report_records: retained.dispatch_continuation.report_records,
  })
  assert_eq(fresh.dispatch_task_report_id, id)
}

///|
test "selection rejection remains visible through canonical readback while operation is pending" {
  let model = continuation_proj_model()
  let (_, saving) = dispatch_continuation_update(_ => none, Select, model)
  let attaching = {
    ..saving,
    dispatch_continuation: {
      ..saving.dispatch_continuation,
      phase: "attaching",
    },
  }
  let (_, rejected) = dispatch_continuation_update(
    _ => none,
    Attached(
      "task-1",
      3,
      attaching.dispatch_continuation.request,
      "",
      Ok("{\"error\":\"Actor no longer has project scope\"}"),
    ),
    attaching,
  )
  assert_true(
    rejected.dispatch_continuation.error.contains(
      "Actor no longer has project scope",
    ),
  )
  let (_, loading) = dispatch_continuation_update(_ => none, Refresh, rejected)
  let decoded = dispatch_continuation_decode(
    loading,
    loading.dispatch_continuation,
    continuation_proj_envelope(
      loading,
      Json::null(),
      continuation_proj_record(),
    ),
  ).unwrap()
  assert_true(decoded.operation_pending)
  assert_true(decoded.error.contains("Actor no longer has project scope"))
}
