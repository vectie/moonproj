///|
test "offer draft preparation has explicit optional proposal editor without creating task" {
  let model = drafts_test_prepared()
  let rendered = guided_task(model)
  assert_true(rendered.contains("报价方案草稿"))
  assert_eq(dispatch_active_draft(model).unwrap().state, "editing")
  assert_false(dispatch_active_draft(model).unwrap().attempted)
}

///|
fn offer_test_update(model : Model, action : DispatchOfferMsg) -> Model {
  dispatch_offer_update(_ => none, model, action).1
}

///|
test "offer separate planning draft retains source without importing execution requirements" {
  let original = {
    ..offer_test_model(),
    dispatch_task_stage: "accepted",
    dispatch_task_product_id: "moonbook",
    dispatch_task_workspace: "/approved/original",
  }
  let events : Array[String] = []
  let states = [original]
  drafts_test_transport(false)
  let (command, prepared) = dispatch_offer_update(
    _ => none,
    original,
    NewPlanning,
  )
  drafts_test_execute(command)
  events.push(drafts_test_events())
  states[0] = prepared
  drafts_test_transport_cleanup()
  let draft = dispatch_active_draft(states[0]).unwrap()
  assert_eq(draft.state, "editing")
  assert_false(draft.attempted)
  assert_eq(draft.project_id, original.dispatch_task_project_id)
  assert_eq(draft.product_id, "")
  assert_eq(draft.workspace, "")
  assert_eq(draft.model, "")
  assert_true(draft.source_reference.unwrap().contains("offer-task"))
  assert_true(draft.source_reference.unwrap().contains("moonbook"))
  assert_eq(states[0].dispatch_task_stage, "accepted")
  assert_eq(states[0].dispatch_task_id, original.dispatch_task_id)
  assert_false(events[0].contains("POST"))
  assert_false(events[0].contains("PUT"))
  let ready = {
    ..draft,
    title: "Prepare new proposal",
    acceptance: "Review scope",
    begin_date: "2026-10-05",
    end_date: "2026-10-12",
  }
  assert_eq(dispatch_draft_validation(ready, "actor-offer"), "")
  let body = dispatch_draft_create_body(ready, "actor-offer")
  assert_eq(dispatch_json_text(body, "task_type"), "task")
  assert_true(dispatch_json_field(body, "product_id") is Null)
  assert_eq(
    dispatch_json_text(dispatch_json_field(body, "source_context"), "reference"),
    draft.source_reference.unwrap(),
  )
}

///|
test "offer receipt task mismatch and future revision cannot confirm a save" {
  let frozen = offer_test_frozen()
  let draft = dispatch_offer_find(frozen, "offer-task").unwrap()
  let entry = offer_test_receipt(draft, 2, "available")
  assert_eq(
    dispatch_offer_receipt_revision(
      { "task_id": "different-task", "offer_history": [entry] },
      draft,
    ),
    0,
  )
  let reading = dispatch_offer_put(frozen, { ..draft, state: "recovering", })
  let impossible = offer_test_update(
    reading,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(1, offer_test_value(), [entry]),
    ),
  )
  assert_eq(
    dispatch_offer_find(impossible, "offer-task").unwrap().state,
    "uncertain",
  )
}

///|
test "offer raw multiline editing retains trailing and blank lines" {
  let base = offer_test_editing()
  for field in ["deliverables", "acceptance_criteria"] {
    let first = offer_test_update(base, Edit(field, "first\n"))
    assert_eq(
      dispatch_offer_value_text(
        dispatch_offer_find(first, "offer-task").unwrap().value,
        field,
      ),
      "first\n",
    )
    let second = offer_test_update(first, Edit(field, "first\n\nsecond\n"))
    assert_eq(
      dispatch_offer_value_text(
        dispatch_offer_find(second, "offer-task").unwrap().value,
        field,
      ),
      "first\n\nsecond\n",
    )
  }
}

///|
test "offer first session identity preserves already authenticated task readback" {
  let early = apply_dispatch_snapshot(
    initial_model(),
    dispatch_decode_snapshot(
      offer_test_body(1, offer_test_value(), []),
      "offer-task",
    ).unwrap(),
  )
  assert_eq(early.dispatch_task_actor_id, "")
  let (_, ready) = dispatch_draft_session(_ => none, early, "actor-offer")
  assert_true(dispatch_offer_eligible(ready))
  assert_eq(ready.dispatch_offer_task, early.dispatch_offer_task)
  let (_, switched) = dispatch_draft_session(_ => none, ready, "other-actor")
  assert_true(switched.dispatch_offer_task is Null)
}

///|
test "offer rejects imported milestone and all execution or acceptance lineage" {
  for
    (field, value) in [
      ("sourceKind", Json::string("imported")),
      ("taskType", Json::string("milestone")),
      ("execution", Json::object({ "unexpected": Json::string("value") })),
      ("continuations", Json::array([Json::object({})])),
      ("human_revisions", Json::array([Json::object({})])),
      (
        "selected_delivery_source",
        Json::object({ "type": Json::string("original") }),
      ),
      (
        "accepted_delivery_source",
        Json::object({ "type": Json::string("original") }),
      ),
      ("accepted_report_id", Json::string("report-existing")),
    ] {
    let model = offer_test_model()
    let fields = Map::from_array(
      match model.dispatch_offer_task {
        Object(fields) => fields.to_array()
        _ => []
      },
    )
    fields[field] = value
    assert_false(
      dispatch_offer_eligible({
        ..model,
        dispatch_offer_task: Json::object(fields),
      }),
    )
  }
}

///|
test "offer dirty text survives refresh and late operation callbacks cannot replace newer edits" {
  let editing = offer_test_update(
    offer_test_editing(),
    Edit("title", "LOCAL UNSAVED"),
  )
  let refreshed = apply_dispatch_snapshot(
    editing,
    dispatch_decode_snapshot(
      offer_test_body(2, offer_test_value(), []),
      "offer-task",
    ).unwrap(),
  )
  assert_eq(
    dispatch_json_text(
      dispatch_offer_find(refreshed, "offer-task").unwrap().value,
      "title",
    ),
    "LOCAL UNSAVED",
  )
  let conflict = offer_test_update(refreshed, Save)
  assert_eq(
    dispatch_offer_find(conflict, "offer-task").unwrap().state,
    "conflict",
  )
  let rebased = offer_test_update(conflict, Rebase)
  let newer = offer_test_update(rebased, Save)
  let draft = dispatch_offer_find(newer, "offer-task").unwrap()
  assert_eq(draft.operation_revision, 2)
  let stale = offer_test_update(
    newer,
    OfferStored("actor-offer", "offer-task", "old-key", true),
  )
  let stale = offer_test_update(
    stale,
    Written("actor-offer", "offer-task", "old-key", 200, "{}"),
  )
  let stale = offer_test_update(
    stale,
    Read(
      "actor-offer",
      "offer-task",
      "old-key",
      200,
      offer_test_body(1, offer_test_value(), []),
    ),
  )
  assert_eq(stale.dispatch_offer_drafts, newer.dispatch_offer_drafts)
  let (_, opened) = open_dispatch_task(_ => none, {
    ..newer,
    dispatch_task_open_id: "another-task",
  })
  assert_eq(opened.dispatch_offer_drafts, newer.dispatch_offer_drafts)
  let planned = offer_test_update(newer, NewPlanning)
  assert_eq(planned.dispatch_offer_drafts, newer.dispatch_offer_drafts)
  let (_, signed_out) = dispatch_draft_session(_ => none, newer, "")
  assert_true(signed_out.dispatch_offer_drafts.is_empty())
  assert_false(dispatch_offer_store(newer).is_empty())
}

///|
test "offer history exposes prior full scheme and closure while current canonical stays distinct" {
  let old = dispatch_offer_edit(
    dispatch_offer_edit(offer_test_value(), "state", "closed"),
    "closure_reason",
    "Prior scope did not fit",
  )
  let current = dispatch_offer_edit(
    offer_test_value(),
    "title",
    "Current proposal",
  )
  let model = apply_dispatch_snapshot(
    offer_test_model(),
    dispatch_decode_snapshot(
      offer_test_body(3, current, [
        {
          "revision": 2,
          "offer_draft": old,
          "audit_state": "available",
          "recorded_at": "2026-10-05",
        },
      ]),
      "offer-task",
    ).unwrap(),
  )
  let html = guided_task(model)
  assert_true(html.contains("Prior scope did not fit"))
  assert_true(html.contains("Current proposal"))
  assert_true(html.contains("历史方案 · 版本 2"))
  assert_true(html.contains("当前正式方案 · 版本 3"))
  assert_true(html.contains("导出当前正式方案 Markdown"))
}

///|
test "offer late refresh keeps active save frozen and old readback never clears native pending action" {
  let frozen = offer_test_frozen()
  let refreshed = apply_dispatch_snapshot(
    frozen,
    dispatch_decode_snapshot(offer_test_body(1, Json::null(), []), "offer-task").unwrap(),
  )
  assert_eq(refreshed.dispatch_task_pending_action, "offer")
  assert_false(dispatch_can_start(refreshed))
  let draft = dispatch_offer_find(refreshed, "offer-task").unwrap()
  let native = dispatch_offer_put(
    { ..refreshed, dispatch_task_pending_action: "start", },
    { ..draft, state: "recovering", },
  )
  let late = offer_test_update(
    native,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(2, draft.operation_offer.unwrap(), [
        offer_test_receipt(draft, 2, "available"),
      ]),
    ),
  )
  assert_eq(late.dispatch_task_pending_action, "start")
  assert_eq(dispatch_offer_find(late, "offer-task").unwrap().state, "saved")
  assert_eq(dispatch_offer_revision(late.dispatch_offer_task), 1)
  let repeated = offer_test_update(
    late,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(3, dispatch_offer_empty(), []),
    ),
  )
  assert_eq(repeated.dispatch_offer_drafts, late.dispatch_offer_drafts)
  assert_eq(repeated.dispatch_offer_task, late.dispatch_offer_task)
}

///|
fn offer_test_value() -> Json {
  {
    "schema": "moonproj.offer-draft.v1",
    "title": "Research proposal",
    "state": "draft",
    "demand_state": "unproven",
    "buyer": "Example buyer",
    "buyer_reference": "https://example.test/request",
    "problem": "Slow onboarding",
    "problem_observed_on": "2026-10-05",
    "scope": "Review one onboarding flow",
    "deliverables": ["Written findings", "Prioritized recommendations"],
    "acceptance_criteria": ["Findings cite observed steps"],
    "exclusions": "Implementation",
    "price_amount": "1250.50",
    "price_currency": "USD",
    "price_basis": "One-time draft estimate",
    "timing": "To confirm",
    "dependencies": "Access to a demo",
    "proof_sought": "Buyer confirms the problem",
    "closure_reason": Json::null(),
  }
}

///|
fn offer_test_body(
  revision : Int,
  offer : Json,
  history : Array[Json],
) -> String {
  let body : Json = {
    "data": {
      "task": {
        "taskGuid": "offer-task",
        "projGuid": "offer-project",
        "taskName": "Plan first offer",
        "taskType": "task",
        "sourceKind": "command",
        "created_by": "actor-offer",
        "status": "pending",
        "revision": revision,
        "remarks": "验收标准：Review a proposal draft",
        "offer_draft": offer,
      },
      "reports": [],
      "commitment": { "task_id": "offer-task", "offer_history": history },
    },
  }
  body.stringify()
}

///|
fn offer_test_model() -> Model {
  apply_dispatch_snapshot(
    {
      ..initial_model(),
      page: Dispatch,
      dispatch_task_actor_id: "actor-offer",
    },
    dispatch_decode_snapshot(offer_test_body(1, Json::null(), []), "offer-task").unwrap(),
  )
}

///|
fn offer_test_editing() -> Model {
  let model = offer_test_update(offer_test_model(), Begin)
  dispatch_offer_put(model, {
    ..dispatch_offer_find(model, "offer-task").unwrap(),
    value: offer_test_value(),
  })
}

///|
fn offer_test_frozen() -> Model {
  let saved = offer_test_update(offer_test_editing(), Save)
  let draft = dispatch_offer_find(saved, "offer-task").unwrap()
  dispatch_offer_put(saved, { ..draft, operation_key: "offer-update-fixture", })
}

///|
fn offer_test_receipt(
  draft : DispatchOfferDraft,
  revision : Int,
  audit : String,
) -> Json {
  {
    "revision": revision,
    "event_id": "offer-event",
    "audit_id": "offer-audit",
    "audit_state": audit,
    "recorded_at": "2026-10-05T00:00:00Z",
    "idempotency_key": draft.operation_key,
    "offer_draft": draft.operation_offer.unwrap(),
  }
}

///|
test "offer local editor preserves raw invalid input and legacy drafts restore" {
  let legacy = dispatch_draft_store(drafts_test_prepared())
  let no_offer = @json.parse(legacy)
  if no_offer is Object(root) && root.get("drafts") is Some(Array(drafts)) {
    for value in drafts {
      if value is Object(fields) {
        fields.remove("offer_draft")
      }
    }
  }
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", no_offer.stringify()),
  )
  assert_eq(restored.dispatch_drafts.length(), 1)
  assert_true(restored.dispatch_drafts[0].offer_draft is None)
  let prepared = offer_test_update(drafts_test_valid(), BeginLocal)
  let edited = offer_test_update(
    prepared,
    EditLocal("price_amount", "maybe 99"),
  )
  let edited = offer_test_update(
    edited,
    EditLocal("problem_observed_on", "2026-02-30"),
  )
  let draft = dispatch_active_draft(edited).unwrap()
  assert_eq(
    dispatch_json_text(draft.offer_draft.unwrap(), "price_amount"),
    "maybe 99",
  )
  assert_eq(
    dispatch_json_text(draft.offer_draft.unwrap(), "problem_observed_on"),
    "2026-02-30",
  )
  assert_false(dispatch_draft_validation(draft, "actor-drafts").is_empty())
  let denied = drafts_test_update(edited, Create)
  assert_eq(dispatch_active_draft(denied).unwrap().state, "editing")
  assert_false(dispatch_active_draft(denied).unwrap().attempted)
}

///|
test "offer local create keeps proposal separate and freezes exact create retry" {
  let model = drafts_test_valid()
  let draft = {
    ..dispatch_active_draft(model).unwrap(),
    task_id: "offer-create-task",
    idempotency_key: "offer-create-fixture",
    project_id: "offer-project",
    product_id: "",
    offer_draft: Some(offer_test_value()),
  }
  let model = dispatch_replace_draft(
    { ..model, dispatch_task_actor_id: "actor-offer", },
    draft,
  )
  let body = dispatch_draft_create_body(draft, "actor-offer")
  assert_eq(
    dispatch_json_field(body, "offer_draft"),
    @task_evidence.normalize_offer_draft(offer_test_value()),
  )
  assert_true(dispatch_json_field(body, "offer_base_revision") is Null)
  assert_eq(
    dispatch_json_text(body, "remarks"),
    "验收标准：Verify B's saved output",
  )
  assert_true(dispatch_json_field(body, "source_context") is Null)
  let saving = drafts_test_update(model, Create)
  let creating = drafts_test_update(
    saving,
    Stored("actor-offer", draft.id, true),
  )
  let changed = offer_test_update(creating, EditLocal("buyer", "not allowed"))
  assert_eq(
    dispatch_draft_create_body(
      dispatch_active_draft(changed).unwrap(),
      "actor-offer",
    ),
    body,
  )
  println("OFFER_CREATE_FIXTURE=" + body.stringify())
}

///|
test "offer canonical editor opens without mutation and eligibility respects creator type execution acceptance" {
  drafts_test_transport(false)
  let (command, opened) = dispatch_offer_update(
    _ => none,
    offer_test_model(),
    Begin,
  )
  drafts_test_execute(command)
  assert_eq(drafts_test_post_count(), 0)
  assert_false(drafts_test_events().contains("PUT"))
  assert_eq(dispatch_offer_find(opened, "offer-task").unwrap().state, "editing")
  drafts_test_transport_cleanup()
  for
    model in [
      { ..offer_test_model(), dispatch_task_actor_id: "other", },
      { ..offer_test_model(), dispatch_task_stage: "accepted", },
      { ..offer_test_model(), dispatch_task_stage: "in_progress", },
      {
        ..offer_test_model(),
        dispatch_run: Some(dispatch_test_run("running")),
      },
    ] {
    assert_false(dispatch_offer_eligible(model))
    assert_eq(offer_test_update(model, Begin).dispatch_offer_drafts, [])
    assert_true(guided_task(model).contains("另建方案规划草稿"))
  }
  let old = { ..offer_test_model(), dispatch_task_stage: "accepted", }
  let fresh = offer_test_update(old, NewPlanning)
  assert_eq(fresh.dispatch_task_id, old.dispatch_task_id)
  assert_eq(fresh.dispatch_task_stage, "accepted")
  assert_true(dispatch_active_draft(fresh).unwrap().offer_draft is Some(_))
  assert_false(dispatch_active_draft(fresh).unwrap().attempted)
  assert_true(
    dispatch_active_draft(fresh).unwrap().task_id != old.dispatch_task_id,
  )
}

///|
test "offer saves persist before transport and storage failure preserves frozen request" {
  let frozen = offer_test_frozen()
  let draft = dispatch_offer_find(frozen, "offer-task").unwrap()
  let body = dispatch_offer_update_body("actor-offer", draft)
  assert_eq(dispatch_json_field(body, "offer_base_revision"), Json::number(1))
  assert_eq(
    dispatch_json_text(dispatch_json_field(body, "authority"), "capability"),
    "project:task:update",
  )
  if body is Object(fields) {
    assert_eq(fields.length(), 4)
  } else {
    fail("expected object")
  }
  assert_false(dispatch_offer_store(frozen).contains("authority"))
  assert_false(dispatch_offer_store(frozen).contains("principal-opc-dispatch"))
  let failed = offer_test_update(
    frozen,
    OfferStored("actor-offer", "offer-task", draft.operation_key, false),
  )
  assert_eq(
    dispatch_offer_find(failed, "offer-task").unwrap().state,
    "uncertain",
  )
  assert_eq(failed.dispatch_task_pending_action, "")
  let retry = offer_test_update(failed, Retry)
  assert_eq(
    dispatch_offer_update_body(
      "actor-offer",
      dispatch_offer_find(retry, "offer-task").unwrap(),
    ),
    body,
  )
  let edited = offer_test_update(retry, Edit("title", "changed"))
  assert_eq(edited.dispatch_offer_drafts, retry.dispatch_offer_drafts)
  println("OFFER_UPDATE_FIXTURE=" + body.stringify())
}

///|
test "offer lost response reconciles exact available receipt and distinguishes historical save" {
  let frozen = offer_test_frozen()
  let draft = dispatch_offer_find(frozen, "offer-task").unwrap()
  let sending = offer_test_update(
    frozen,
    OfferStored("actor-offer", "offer-task", draft.operation_key, true),
  )
  let reading = offer_test_update(
    sending,
    Written("actor-offer", "offer-task", draft.operation_key, 0, ""),
  )
  let history = [offer_test_receipt(draft, 2, "available")]
  let saved = offer_test_update(
    reading,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(2, draft.operation_offer.unwrap(), history),
    ),
  )
  assert_eq(dispatch_offer_find(saved, "offer-task").unwrap().state, "saved")
  assert_eq(dispatch_offer_find(saved, "offer-task").unwrap().saved_revision, 2)
  let newer = dispatch_offer_edit(
    offer_test_value(),
    "title",
    "Newer canonical title",
  )
  let historical = offer_test_update(
    reading,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(3, newer, history),
    ),
  )
  assert_eq(
    dispatch_offer_find(historical, "offer-task").unwrap().state,
    "historical",
  )
  assert_eq(
    dispatch_json_text(
      dispatch_json_field(historical.dispatch_offer_task, "offer_draft"),
      "title",
    ),
    "Newer canonical title",
  )
  assert_eq(
    offer_test_update(historical, Edit("title", "unsafe overwrite")).dispatch_offer_drafts,
    historical.dispatch_offer_drafts,
  )
  let rebased = offer_test_update(historical, Rebase)
  assert_eq(
    dispatch_offer_find(rebased, "offer-task").unwrap().base_revision,
    3,
  )
  assert_eq(
    dispatch_offer_find(rebased, "offer-task").unwrap().state,
    "editing",
  )
  println(
    "OFFER_MARKDOWN_FIXTURE=" +
    ToJson::to_json(
      @task_evidence.offer_draft_markdown(
        draft.operation_offer.unwrap(),
        task_id="offer-task",
        project_id="offer-project",
        revision=2,
      ),
    ).stringify(),
  )
}

///|
test "offer missing conflicting wrong-key and different-payload receipts never confirm save" {
  let frozen = offer_test_frozen()
  let draft = dispatch_offer_find(frozen, "offer-task").unwrap()
  let reading = dispatch_offer_put(frozen, { ..draft, state: "recovering", })
  for audit in ["missing", "conflict"] {
    let result = offer_test_update(
      reading,
      Read(
        "actor-offer",
        "offer-task",
        draft.operation_key,
        200,
        offer_test_body(2, draft.operation_offer.unwrap(), [
          offer_test_receipt(draft, 2, audit),
        ]),
      ),
    )
    assert_eq(
      dispatch_offer_find(result, "offer-task").unwrap().state,
      "conflict",
    )
    assert_eq(
      dispatch_offer_find(result, "offer-task").unwrap().value,
      draft.value,
    )
  }
  let wrong_key = { ..draft, operation_key: "other-operation", }
  assert_eq(
    dispatch_offer_receipt_revision(
      {
        "task_id": "offer-task",
        "offer_history": [offer_test_receipt(wrong_key, 2, "available")],
      },
      draft,
    ),
    0,
  )
  let different = {
    ..draft,
    operation_offer: Some(
      dispatch_offer_edit(offer_test_value(), "title", "different"),
    ),
  }
  assert_eq(
    dispatch_offer_receipt_revision(
      {
        "task_id": "offer-task",
        "offer_history": [offer_test_receipt(different, 2, "available")],
      },
      draft,
    ),
    0,
  )
  assert_eq(
    dispatch_offer_receipt_revision(
      {
        "task_id": "offer-task",
        "offer_history": [offer_test_receipt(draft, 3, "available")],
      },
      draft,
    ),
    0,
  )
}

///|
test "offer actor reload task switching and stale callbacks preserve separate drafts" {
  let frozen = offer_test_frozen()
  let draft = dispatch_offer_find(frozen, "offer-task").unwrap()
  let restored = offer_test_update(
    offer_test_model(),
    OfferRestored("actor-offer", dispatch_offer_store(frozen)),
  )
  assert_eq(
    dispatch_offer_find(restored, "offer-task").unwrap().state,
    "uncertain",
  )
  assert_eq(
    dispatch_offer_update_body(
      "actor-offer",
      dispatch_offer_find(restored, "offer-task").unwrap(),
    ),
    dispatch_offer_update_body("actor-offer", draft),
  )
  let (_, switched) = dispatch_draft_session(_ => none, frozen, "other-actor")
  assert_true(switched.dispatch_offer_drafts.is_empty())
  assert_true(switched.dispatch_offer_task is Null)
  let stale = offer_test_update(
    switched,
    OfferRestored("actor-offer", dispatch_offer_store(frozen)),
  )
  assert_true(stale.dispatch_offer_drafts.is_empty())
  let stale = offer_test_update(
    frozen,
    OfferStored("other-actor", "offer-task", draft.operation_key, true),
  )
  assert_eq(stale.dispatch_offer_drafts, frozen.dispatch_offer_drafts)
  let selected_b = {
    ..frozen,
    dispatch_task_id: "task-b",
    dispatch_task_stage: "loading",
    dispatch_task_pending_action: "load",
  }
  let reading = dispatch_offer_put(selected_b, { ..draft, state: "recovering", })
  let result = offer_test_update(
    reading,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      offer_test_body(2, draft.operation_offer.unwrap(), [
        offer_test_receipt(draft, 2, "available"),
      ]),
    ),
  )
  assert_eq(result.dispatch_task_id, "task-b")
  assert_eq(result.dispatch_task_pending_action, "load")
  assert_eq(dispatch_offer_find(result, "offer-task").unwrap().state, "saved")
}
