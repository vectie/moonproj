///|
fn reply_ui_update(model : Model, action : DispatchReplyMsg) -> Model {
  dispatch_reply_update(_ => none, model, action).1
}

///|
fn reply_ui_body(revision : Int, history : Array[Json]) -> String {
  let parsed = @json.parse(
    offer_test_body(revision, offer_test_value(), [
      {
        "revision": 1,
        "audit_state": "available",
        "offer_draft": offer_test_value(),
      },
    ]),
  ) catch {
    _ => Json::null()
  }
  let commitment = dispatch_json_field(
    dispatch_json_field(parsed, "data"),
    "commitment",
  )
  if commitment is Object(fields) {
    fields["offer_reply_history"] = Json::array(history)
  }
  parsed.stringify()
}

///|
fn reply_ui_model() -> Model {
  apply_dispatch_snapshot(
    offer_test_model(),
    dispatch_decode_snapshot(reply_ui_body(1, []), "offer-task").unwrap(),
  )
}

///|
fn reply_ui_editing() -> Model {
  let model = reply_ui_update(reply_ui_model(), Begin)
  let model = reply_ui_update(model, Edit("offer_revision", "1"))
  let model = reply_ui_update(
    model,
    Edit("summary", "First line\n\nPlease reduce scope\n"),
  )
  let model = reply_ui_update(model, Edit("kind", "changes_requested"))
  reply_ui_update(model, Edit("evidence_kind", "human_observation"))
}

///|
fn reply_ui_frozen() -> Model {
  let model = reply_ui_update(reply_ui_editing(), Save)
  dispatch_reply_put(model, {
    ..dispatch_reply_find(model).unwrap(),
    operation_key: "offer-reply-serialized",
  })
}

///|
fn reply_ui_receipt(draft : DispatchReplyDraft) -> Json {
  {
    "reply_id": "reply-event",
    "event_id": "reply-event",
    "audit_id": "reply-audit",
    "audit_state": "available",
    "record_revision": draft.operation_revision + 1,
    "recorded_by": "actor-offer",
    "recorded_at": "2026-10-05T13:00:00Z",
    "idempotency_key": draft.operation_key,
    "offer_reply": draft.operation_reply.unwrap(),
  }
}

///|
test "offer reply reducer requires intentional exact offer kind and evidence selections" {
  let opened = reply_ui_update(reply_ui_model(), Begin)
  let draft = dispatch_reply_find(opened).unwrap()
  assert_eq(dispatch_json_text(draft.value, "evidence_kind"), "")
  assert_eq(dispatch_reply_number(draft.value, "offer_revision"), 0)
  assert_eq(dispatch_json_text(draft.value, "kind"), "")
  assert_true(dispatch_json_field(draft.value, "respondent") is Null)
  assert_eq(
    dispatch_reply_find(reply_ui_update(opened, Save)).unwrap().state,
    "editing",
  )
  let valid = reply_ui_editing()
  let no_evidence = reply_ui_update(valid, Edit("evidence_kind", ""))
  assert_eq(
    dispatch_reply_find(reply_ui_update(no_evidence, Save)).unwrap().state,
    "editing",
  )
  let reference = reply_ui_update(valid, Edit("evidence_kind", "reference"))
  assert_eq(
    dispatch_reply_find(reply_ui_update(reference, Save)).unwrap().state,
    "editing",
  )
  let reference = reply_ui_update(
    reference,
    Edit("source_reference", "email-thread-42"),
  )
  assert_eq(
    dispatch_reply_find(reply_ui_update(reference, Save)).unwrap().state,
    "saving",
  )
  let observed = reply_ui_update(
    reference,
    Edit("evidence_kind", "human_observation"),
  )
  assert_true(
    dispatch_json_field(
      dispatch_reply_find(observed).unwrap().value,
      "source_reference",
    )
    is Null,
  )
  let wrong = reply_ui_update(valid, Edit("offer_revision", "9"))
  assert_eq(
    dispatch_reply_find(reply_ui_update(wrong, Save)).unwrap().state,
    "editing",
  )
}

///|
test "offer reply raw multiline invalid timestamp and unknown fields survive editing and refresh" {
  let model = reply_ui_update(
    reply_ui_editing(),
    Edit("received_at", "yesterday maybe"),
  )
  let draft = dispatch_reply_find(model).unwrap()
  assert_eq(
    dispatch_json_text(draft.value, "summary"),
    "First line\n\nPlease reduce scope\n",
  )
  assert_eq(
    dispatch_reply_find(reply_ui_update(model, Save)).unwrap().state,
    "editing",
  )
  let restored = reply_ui_update(
    reply_ui_model(),
    ReplyRestored("actor-offer", dispatch_reply_store(model)),
  )
  assert_eq(dispatch_reply_find(restored).unwrap().value, draft.value)
  let refreshed = apply_dispatch_snapshot(
    model,
    dispatch_decode_snapshot(reply_ui_body(2, []), "offer-task").unwrap(),
  )
  assert_eq(dispatch_reply_find(refreshed).unwrap().value, draft.value)
  let frozen = dispatch_reply_find(reply_ui_frozen()).unwrap()
  let value = frozen.operation_reply.unwrap()
  for
    field in [
      "respondent", "received_at", "source_reference", "supersedes_reply_id", "correction_reason",
    ] {
    assert_true(dispatch_json_field(value, field) is Null)
  }
  assert_false(dispatch_reply_store(model).contains("authority"))
}

///|
test "offer reply task navigation project isolation and authentication generation guard drafts" {
  let model = reply_ui_editing()
  let (_, opened) = open_dispatch_task(_ => none, {
    ..model,
    dispatch_task_open_id: "task-b",
  })
  assert_eq(opened.dispatch_reply_drafts, model.dispatch_reply_drafts)
  assert_true(
    dispatch_reply_find({
      ..model,
      dispatch_task_project_id: "different-project",
    })
    is None,
  )
  assert_false(
    dispatch_reply_eligible({
      ..model,
      dispatch_task_project_id: "different-project",
    }),
  )
  assert_true(
    dispatch_reply_find({ ..model, dispatch_task_id: "task-b", }) is None,
  )
  let (_, signed_out) = dispatch_draft_session(_ => none, model, "")
  assert_true(signed_out.dispatch_reply_drafts.is_empty())
  assert_true(signed_out.dispatch_task_commitment is Null)
  let (_, signed_back) = dispatch_draft_session(
    _ => none,
    signed_out,
    "actor-offer",
  )
  let stale = reply_ui_update(
    signed_back,
    Scoped(
      model.dispatch_reply_generation,
      ReplyRestored("actor-offer", dispatch_reply_store(model)),
    ),
  )
  assert_true(stale.dispatch_reply_drafts.is_empty())
  let wrong_actor = reply_ui_update(
    model,
    ReplyRestored("other", dispatch_reply_store(model)),
  )
  assert_eq(wrong_actor.dispatch_reply_drafts, model.dispatch_reply_drafts)
}

///|
test "offer reply immutable operation storage failure repeat clicks and stale callbacks" {
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  assert_eq(
    reply_ui_update(frozen, Save).dispatch_reply_drafts,
    frozen.dispatch_reply_drafts,
  )
  assert_eq(
    reply_ui_update(frozen, Edit("summary", "rewrite")).dispatch_reply_drafts,
    frozen.dispatch_reply_drafts,
  )
  let failed = reply_ui_update(
    frozen,
    ReplyStored("actor-offer", "offer-task", draft.operation_key, false),
  )
  assert_eq(dispatch_reply_find(failed).unwrap().state, "uncertain")
  assert_eq(failed.dispatch_task_pending_action, "")
  let retried = reply_ui_update(failed, Retry)
  assert_eq(
    dispatch_reply_update_body(
      "actor-offer",
      dispatch_reply_find(retried).unwrap(),
    ),
    dispatch_reply_update_body("actor-offer", draft),
  )
  assert_eq(
    reply_ui_update(
      retried,
      ReplyStored("actor-offer", "offer-task", "old-key", true),
    ).dispatch_reply_drafts,
    retried.dispatch_reply_drafts,
  )
  let restored = reply_ui_update(
    reply_ui_model(),
    ReplyRestored("actor-offer", dispatch_reply_store(frozen)),
  )
  assert_eq(dispatch_reply_find(restored).unwrap().state, "uncertain")
  assert_eq(
    dispatch_reply_update_body(
      "actor-offer",
      dispatch_reply_find(restored).unwrap(),
    ),
    dispatch_reply_update_body("actor-offer", draft),
  )
  let refreshed = apply_dispatch_snapshot(
    frozen,
    dispatch_decode_snapshot(reply_ui_body(1, []), "offer-task").unwrap(),
  )
  assert_eq(refreshed.dispatch_task_pending_action, "offer-reply")
  assert_false(dispatch_can_start(refreshed))
}

///|
test "offer reply save waits for exact audited history and cleans private local copy" {
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  let sending = reply_ui_update(
    frozen,
    ReplyStored("actor-offer", "offer-task", draft.operation_key, true),
  )
  let reading = reply_ui_update(
    sending,
    Written(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      "{\"reply_id\":\"reply-event\"}",
    ),
  )
  assert_eq(dispatch_reply_find(reading).unwrap().state, "recovering")
  let saved = reply_ui_update(
    reading,
    Read(
      "actor-offer",
      "offer-task",
      draft.operation_key,
      200,
      reply_ui_body(2, [reply_ui_receipt(draft)]),
    ),
  )
  assert_eq(dispatch_reply_find(saved).unwrap().state, "saved")
  assert_eq(dispatch_reply_find(saved).unwrap().saved_revision, 2)
  assert_false(dispatch_reply_store(saved).contains("Please reduce scope"))
  assert_true(guided_task(saved).contains("Please reduce scope"))
  assert_eq(saved.dispatch_task_stage, "pending")
  assert_eq(
    dispatch_json_text(
      dispatch_json_field(saved.dispatch_offer_task, "offer_draft"),
      "demand_state",
    ),
    "unproven",
  )
  assert_true(saved.dispatch_run is None)
  assert_eq(
    reply_ui_update(
      saved,
      Read(
        "actor-offer",
        "offer-task",
        draft.operation_key,
        200,
        reply_ui_body(99, []),
      ),
    ).dispatch_reply_drafts,
    saved.dispatch_reply_drafts,
  )
}

///|
test "offer reply mismatched history fields never confirm and stale CAS preserves target revision" {
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  let reading = dispatch_reply_put(frozen, { ..draft, state: "recovering", })
  for
    (field, replacement) in [
      ("audit_state", Json::string("missing")),
      ("audit_id", Json::string("")),
      ("event_id", Json::string("other")),
      ("idempotency_key", Json::string("wrong")),
      ("recorded_by", Json::string("other")),
      ("record_revision", Json::number(3)),
      (
        "offer_reply",
        dispatch_reply_edit(
          draft.operation_reply.unwrap(),
          "summary",
          "different",
        ),
      ),
    ] {
    let receipt = reply_ui_receipt(draft)
    if receipt is Object(fields) {
      fields[field] = replacement
    }
    let result = reply_ui_update(
      reading,
      Read(
        "actor-offer",
        "offer-task",
        draft.operation_key,
        200,
        reply_ui_body(2, [receipt]),
      ),
    )
    assert_eq(dispatch_reply_find(result).unwrap().state, "conflict")
    assert_eq(dispatch_reply_find(result).unwrap().value, draft.value)
  }
  let changed = apply_dispatch_snapshot(
    reply_ui_editing(),
    dispatch_decode_snapshot(reply_ui_body(2, []), "offer-task").unwrap(),
  )
  let conflict = reply_ui_update(changed, Save)
  assert_eq(dispatch_reply_find(conflict).unwrap().state, "conflict")
  let rebased = reply_ui_update(conflict, Rebase)
  assert_eq(dispatch_reply_find(rebased).unwrap().base_revision, 2)
  assert_eq(
    dispatch_reply_number(
      dispatch_reply_find(rebased).unwrap().value,
      "offer_revision",
    ),
    1,
  )
  let new_save = reply_ui_update(rebased, Save)
  assert_eq(dispatch_reply_find(new_save).unwrap().operation_revision, 2)
}

///|
test "offer reply late task project or native callbacks cannot replace current selection" {
  let frozen = reply_ui_frozen()
  let draft = dispatch_reply_find(frozen).unwrap()
  for
    selected in [
      {
        ..frozen,
        dispatch_task_id: "task-b",
        dispatch_task_pending_action: "load",
      },
      {
        ..frozen,
        dispatch_task_project_id: "project-b",
        dispatch_task_pending_action: "load",
      },
      {
        ..frozen,
        dispatch_task_project_id: "project-b",
        dispatch_task_pending_action: "offer-reply",
      },
      { ..frozen, dispatch_task_pending_action: "start", },
    ] {
    let reading = dispatch_reply_put(selected, { ..draft, state: "recovering", })
    let saved = reply_ui_update(
      reading,
      Read(
        "actor-offer",
        "offer-task",
        draft.operation_key,
        200,
        reply_ui_body(2, [reply_ui_receipt(draft)]),
      ),
    )
    assert_eq(saved.dispatch_task_id, selected.dispatch_task_id)
    assert_eq(saved.dispatch_task_project_id, selected.dispatch_task_project_id)
    assert_eq(
      saved.dispatch_task_pending_action,
      selected.dispatch_task_pending_action,
    )
  }
}

///|
test "offer reply correction appends requires reason and cannot rewrite target or original" {
  let draft = dispatch_reply_find(reply_ui_frozen()).unwrap()
  let original = reply_ui_receipt(draft)
  let model = apply_dispatch_snapshot(
    reply_ui_model(),
    dispatch_decode_snapshot(reply_ui_body(2, [original]), "offer-task").unwrap(),
  )
  let correcting = reply_ui_update(model, Correct("reply-event"))
  let invalid = reply_ui_update(correcting, Save)
  assert_eq(dispatch_reply_find(invalid).unwrap().state, "editing")
  let edited = reply_ui_update(correcting, Edit("offer_revision", "2"))
  assert_eq(
    dispatch_reply_number(
      dispatch_reply_find(edited).unwrap().value,
      "offer_revision",
    ),
    1,
  )
  let edited = reply_ui_update(
    edited,
    Edit("correction_reason", "Corrected my transcription"),
  )
  let edited = reply_ui_update(
    edited,
    Edit("summary", "Actually one smaller scope"),
  )
  let saved = reply_ui_update(edited, Save)
  assert_eq(dispatch_reply_find(saved).unwrap().state, "saving")
  assert_eq(dispatch_reply_history(saved), [original])
  let html = guided_task(edited)
  assert_true(html.contains("更正原因（必填）"))
  assert_true(html.contains("First line"))
  assert_true(html.contains("Actually one smaller scope"))
  let correction : Json = {
    "reply_id": "corrected",
    "offer_reply": dispatch_reply_find(saved).unwrap().operation_reply.unwrap(),
    "audit_state": "available",
  }
  let newer = apply_dispatch_snapshot(
    model,
    dispatch_decode_snapshot(
      reply_ui_body(3, [original, correction]),
      "offer-task",
    ).unwrap(),
  )
  assert_true(
    dispatch_reply_find(reply_ui_update(newer, Correct("reply-event"))) is None,
  )
  assert_true(guided_task(newer).contains("已有更正，原记录保留"))
}

///|
test "offer reply SSR privacy boundary and eligibility preserve ordinary proposal actions" {
  let html = guided_task(reply_ui_editing())
  for
    text in [
      "已经收到的回复", "关闭标签页", "切换账号", "回复者（可留空）",
      "记录依据", "我的人工观察", "修改或关闭报价方案",
    ] {
    assert_true(html.contains(text))
  }
  let model = reply_ui_model()
  for
    blocked in [
      { ..model, dispatch_task_actor_id: "other", },
      { ..model, dispatch_task_stage: "accepted", },
      { ..model, dispatch_run: Some(dispatch_test_run("running")), },
      offer_test_model(),
    ] {
    assert_false(dispatch_reply_eligible(blocked))
    assert_true(dispatch_reply_find(reply_ui_update(blocked, Begin)) is None)
    assert_false(guided_task(blocked).contains(">记录客户回复</button>"))
  }
  let source = reply_ui_editing()
  let revised = offer_test_update(source, Begin)
  assert_eq(revised.dispatch_reply_drafts, source.dispatch_reply_drafts)
  assert_true(dispatch_offer_find(revised, "offer-task") is Some(_))
}

///|
test "offer reply later proposal keeps earlier feedback attached to original revision only" {
  let draft = dispatch_reply_find(reply_ui_frozen()).unwrap()
  let parsed = @json.parse(reply_ui_body(3, [reply_ui_receipt(draft)]))
  let task = dispatch_json_field(dispatch_json_field(parsed, "data"), "task")
  let commitment = dispatch_json_field(
    dispatch_json_field(parsed, "data"),
    "commitment",
  )
  let newer = dispatch_offer_edit(
    offer_test_value(),
    "title",
    "Replacement proposal",
  )
  if task is Object(fields) {
    fields["offer_draft"] = newer
  }
  if commitment is Object(fields) {
    fields["offer_history"] = Json::array([
      {
        "revision": 1,
        "audit_state": "available",
        "offer_draft": offer_test_value(),
      },
      { "revision": 3, "audit_state": "available", "offer_draft": newer },
    ])
  }
  let model = apply_dispatch_snapshot(
    reply_ui_model(),
    dispatch_decode_snapshot(parsed.stringify(), "offer-task").unwrap(),
  )
  assert_eq(dispatch_offer_canonical_revision(model), 3)
  assert_eq(
    dispatch_reply_number(
      dispatch_json_field(dispatch_reply_history(model)[0], "offer_reply"),
      "offer_revision",
    ),
    1,
  )
  let opened = reply_ui_update(model, Begin)
  assert_eq(
    dispatch_reply_number(
      dispatch_reply_find(opened).unwrap().value,
      "offer_revision",
    ),
    0,
  )
  assert_eq(dispatch_reply_offers(opened).map(dispatch_offer_revision), [1, 3])
  let html = guided_task(opened)
  assert_true(html.contains("当前正式方案 · 方案版本 3"))
  assert_true(html.contains("此方案版本尚无已保存回复"))
  assert_true(
    html.contains(
      "当前方案版本尚无已保存回复。历史回复仍按原方案版本保留。",
    ),
  )
  assert_true(html.contains("其他方案版本的回复不会自动沿用"))
  assert_eq(dispatch_receipt_action_label("offer_reply"), "记录客户回复")
  assert_eq(
    dispatch_receipt_action_label("internal_acceptance"),
    "内部验收",
  )
}

///|
test "offer reply untrusted summary is rendered as escaped text" {
  let model = reply_ui_update(
    reply_ui_editing(),
    Edit("summary", "<script>alert('private')</script>\n\nNext line\n"),
  )
  let html = guided_task(model)
  assert_false(html.contains("<script>alert"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_eq(
    dispatch_json_text(dispatch_reply_find(model).unwrap().value, "summary"),
    "<script>alert('private')</script>\n\nNext line\n",
  )
}
