///|
fn founder_compatibility_fixture() -> String {
  let value : Json = {
    "kind": "moonproj-founder-draft-v1",
    "title": "Synthetic offer",
    "source_ref": "moonfind:synthetic-note-1",
    "problem": "Synthetic buyer loses handoff context",
    "acceptance": "One reviewable artifact",
    "project_id": "proj-test",
    "owner_id": "owner-test",
    "begin_date": "2026-09-30",
    "end_date": "2026-10-02",
    // Unknown old fields must never become current authenticated identity.
    "actor_id": "legacy-private-actor",
    "authority": "legacy-private-authority",
  }
  value.stringify()
}

///|
fn founder_compatibility_model() -> Model {
  let model = initial_model()
  {
    ..model,
    dispatch_task_actor_id: "current-private-actor",
    dispatch_draft_storage: "已读取此浏览器草稿",
    company_setup: {
      ..model.company_setup,
      actor: "current-private-actor",
      session_state: "ready",
      epoch: 3,
    },
  }
}

///|
test "legacy founder decoder accepts ordinary context and rejects malformed storage" {
  let legacy = founder_legacy_draft(founder_compatibility_fixture()).unwrap()
  assert_eq(legacy.source_ref, "moonfind:synthetic-note-1")
  assert_eq(legacy.problem, "Synthetic buyer loses handoff context")
  assert_true(founder_legacy_draft("{") is None)
  assert_true(founder_legacy_draft("{\"kind\":\"v999\"}") is None)
  assert_true(
    founder_legacy_draft("{\"kind\":\"moonproj-founder-draft-v1\",\"title\":4}")
    is None,
  )
}

///|
test "legacy founder context becomes a parked fresh actor scoped draft without formal effects" {
  let model = founder_compatibility_model()
  let (_, imported) = founder_import_legacy_draft(
    _ => none,
    model,
    model.dispatch_task_actor_id,
    founder_compatibility_fixture(),
    "",
    "",
  )
  assert_eq(imported.page, Overview)
  assert_eq(imported.products, model.products)
  assert_eq(imported.dispatch_task_selection, model.dispatch_task_selection)
  assert_eq(imported.dispatch_task_actor_id, "current-private-actor")
  assert_eq(imported.dispatch_task_id, "")
  assert_eq(imported.dispatch_task_pending_action, "")
  assert_eq(imported.dispatch_draft_id, "")
  assert_false(imported.dispatch_task_form_open)
  assert_eq(imported.dispatch_drafts.length(), 1)
  let draft = imported.dispatch_drafts[0]
  assert_eq(draft.title, "Synthetic offer")
  assert_eq(draft.source_reference, Some("moonfind:synthetic-note-1"))
  assert_eq(
    draft.observed_problem,
    Some("Synthetic buyer loses handoff context"),
  )
  assert_eq(draft.acceptance, "One reviewable artifact")
  assert_eq(draft.project_id, "proj-test")
  assert_eq(draft.owner_id, "owner-test")
  assert_eq(draft.state, "editing")
  assert_false(draft.attempted)
  assert_false(draft.recovery_required)
  assert_eq(draft.workspace, "")
  assert_eq(draft.model, "")
  assert_true(draft.task_id.has_prefix("OPC-TASK-"))
  assert_true(draft.idempotency_key.has_prefix("opc-dispatch-create-"))
  assert_true(!dispatch_draft_store(imported).contains("legacy-private-actor"))
  assert_true(
    !dispatch_draft_store(imported).contains("legacy-private-authority"),
  )
}

///|
test "legacy import refuses occupied anonymous foreign or unconfirmed state" {
  let model = founder_compatibility_model()
  let emit : @rabbita.Emit[Msg] = _ => none
  let (_, imported) = founder_import_legacy_draft(
    emit,
    model,
    model.dispatch_task_actor_id,
    founder_compatibility_fixture(),
    "",
    "",
  )
  let states = [
    initial_model(),
    { ..model, dispatch_task_id: "existing-task", },
    { ..model, dispatch_task_open_id: "selected-task", },
    { ..model, dispatch_task_form_open: true, },
    { ..model, dispatch_task_pending_action: "load", },
    { ..model, dispatch_recent_tasks: ["uncertain-task"], },
    { ..model, dispatch_draft_storage: "storage-unavailable", },
    {
      ..model,
      company_setup: { ..model.company_setup, session_state: "loading", },
    },
    {
      ..model,
      company_setup: { ..model.company_setup, actor: "other-actor", },
    },
    imported,
  ]
  for current in states {
    let (_, unchanged) = founder_import_legacy_draft(
      emit,
      current,
      model.dispatch_task_actor_id,
      founder_compatibility_fixture(),
      "",
      "",
    )
    assert_eq(unchanged.dispatch_drafts, current.dispatch_drafts)
    assert_eq(unchanged.dispatch_task_id, current.dispatch_task_id)
    assert_eq(
      unchanged.dispatch_task_selection,
      current.dispatch_task_selection,
    )
    assert_eq(unchanged.page, current.page)
  }
  let (_, unchanged) = founder_import_legacy_draft(
    emit,
    model,
    "other-actor",
    founder_compatibility_fixture(),
    "",
    "",
  )
  assert_true(unchanged.dispatch_drafts.is_empty())
  let (_, invalid_scoped) = founder_after_draft_restore(
    emit,
    model,
    model.dispatch_task_actor_id,
    "{\"version\":999}",
  )
  assert_true(invalid_scoped.dispatch_drafts.is_empty())
}

///|
test "legacy pending task and link block import rather than fork identity" {
  let model = founder_compatibility_model()
  for hints in [("OPC-TASK-legacy-pending", ""), ("", "OPC-TASK-legacy-link")] {
    let (_, deferred) = founder_import_legacy_draft(
      _ => none,
      model,
      model.dispatch_task_actor_id,
      founder_compatibility_fixture(),
      hints.0,
      hints.1,
    )
    assert_true(deferred.dispatch_drafts.is_empty())
    assert_true(deferred.dispatch_recent_tasks.is_empty())
    assert_eq(deferred.dispatch_task_id, "")
    assert_eq(deferred.dispatch_task_pending_action, "")
    assert_eq(deferred.page, model.page)
    assert_true(deferred.notice.contains("只读恢复"))
  }
}

///|
test "Markdown export uses active draft context without identity authority or cash claims" {
  let model = founder_compatibility_model()
  let (_, imported) = founder_import_legacy_draft(
    _ => none,
    model,
    model.dispatch_task_actor_id,
    founder_compatibility_fixture(),
    "",
    "",
  )
  let draft = imported.dispatch_drafts[0]
  let active = {
    ..imported,
    page: Dispatch,
    dispatch_task_form_open: true,
    dispatch_draft_id: draft.id,
    dispatch_task_title: "stale unrelated task text",
    dispatch_task_evidence_id: "private-evidence-id",
  }
  let packet = founder_packet_markdown(founder_packet_context(active).unwrap())
  assert_true(packet.contains("Synthetic offer"))
  assert_true(packet.contains("moonfind:synthetic-note-1"))
  assert_true(packet.contains("local draft; no formal task receipt"))
  assert_true(packet.contains("Customer acceptance: no evidence"))
  assert_true(!packet.contains("stale unrelated task text"))
  assert_true(!packet.contains("current-private-actor"))
  assert_true(!packet.contains("private-evidence-id"))
  assert_true(!packet.contains("legacy-private-authority"))
}

///|
test "Markdown canonical export requires loaded task and current authenticated identity" {
  let model = founder_compatibility_model()
  let canonical = {
    ..model,
    page: Dispatch,
    dispatch_task_id: "OPC-TASK-canonical",
    dispatch_task_stage: "submitted",
    dispatch_journey_read_state: "loaded",
    dispatch_task_title: "Canonical task",
    dispatch_task_source_context: {
      "reference": "source:canonical",
      "problem": "Readback problem",
    },
    dispatch_task_acceptance: "Canonical acceptance",
  }
  let context = founder_packet_context(canonical).unwrap()
  assert_eq(context.task_id, "OPC-TASK-canonical")
  assert_eq(context.source_reference, "source:canonical")
  assert_eq(context.observed_problem, "Readback problem")
  assert_true(
    founder_packet_context({ ..canonical, dispatch_task_stage: "loading", })
    is None,
  )
  assert_true(
    founder_packet_context({
      ..canonical,
      dispatch_journey_read_state: "unconfirmed",
    })
    is None,
  )
  assert_true(
    founder_packet_context({
      ..canonical,
      dispatch_task_actor_id: "foreign-actor",
    })
    is None,
  )
  assert_true(founder_packet_context(initial_model()) is None)
}

///|
test "late Markdown completion does not update a changed session or route" {
  let model = founder_compatibility_model()
  for
    response in [
      FounderPacketDownloaded("foreign-actor", 3, 0, Products, "", true),
      FounderPacketDownloaded(
        model.dispatch_task_actor_id,
        2,
        0,
        Products,
        "",
        true,
      ),
      FounderPacketDownloaded(
        model.dispatch_task_actor_id,
        3,
        1,
        Products,
        "",
        true,
      ),
      FounderPacketDownloaded(
        model.dispatch_task_actor_id,
        3,
        0,
        Dispatch,
        "",
        true,
      ),
    ] {
    let (_, unchanged) = update_model(_ => none, response, model)
    assert_eq(unchanged.notice, model.notice)
    assert_eq(unchanged.dispatch_task_actor_id, model.dispatch_task_actor_id)
    assert_eq(unchanged.dispatch_task_selection, model.dispatch_task_selection)
  }
}
