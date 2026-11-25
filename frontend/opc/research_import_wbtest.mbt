///|
fn research_test_update(model : Model, action : ResearchImportMsg) -> Model {
  let (_, next) = update(_ => none, ResearchImportAction(action), model)
  next
}

///|
fn research_test_loaded(model : Model, kind : String) -> Model {
  let choosing = research_test_update({ ..model, page: Dispatch, }, Choose)
  research_test_update(
    choosing,
    Loaded(
      choosing.research_import.generation,
      choosing.dispatch_task_actor_id,
      research_test_export(kind),
      "",
    ),
  )
}

///|
fn research_test_ready(model : Model) -> Model {
  research_test_loaded(model, "current")
}

///|
test "research imported producer bytes only preview until one explicit prepare action" {
  let original = drafts_test_valid()
  let loaded = research_test_loaded(original, "current")
  assert_eq(loaded.dispatch_drafts, original.dispatch_drafts)
  assert_eq(loaded.dispatch_draft_id, original.dispatch_draft_id)
  let prepared = research_test_update(loaded, Prepare)
  assert_eq(
    prepared.dispatch_drafts.length(),
    original.dispatch_drafts.length() + 1,
  )
  assert_eq(
    dispatch_draft_by_id(prepared, original.dispatch_draft_id),
    dispatch_active_draft(original),
  )
  let draft = dispatch_active_draft(prepared).unwrap()
  assert_eq(draft.title, "Prepare the interview questions")
  assert_eq(draft.observed_problem, Some("independent-handoff open questions"))
  assert_eq(draft.acceptance, "")
  assert_eq(draft.project_id, "")
  assert_eq(draft.owner_id, "")
  assert_eq(draft.state, "editing")
  assert_false(draft.attempted)
  assert_eq(prepared.dispatch_task_id, original.dispatch_task_id)
  assert_eq(prepared.dispatch_run, original.dispatch_run)
}

///|
test "research repeated prepare and repeated import preserve exact edited draft and identity" {
  let prepared = research_test_update(
    research_test_ready(drafts_test_valid()),
    Prepare,
  )
  let edited = drafts_test_update(
    drafts_test_update(prepared, Input("title", "My revised work 学习")),
    Input("acceptance", "Observe three independent replies"),
  )
  let id = edited.dispatch_draft_id
  let repeated = research_test_update(edited, Prepare)
  assert_eq(repeated.dispatch_drafts, edited.dispatch_drafts)
  let resumed = research_test_update(research_test_ready(edited), Prepare)
  assert_eq(resumed.dispatch_draft_id, id)
  assert_eq(resumed.dispatch_drafts, edited.dispatch_drafts)
  assert_eq(
    dispatch_active_draft(resumed).unwrap().title,
    "My revised work 学习",
  )
}

///|
test "research malformed import and missing choice preserve existing draft and preview" {
  let loaded = research_test_ready(drafts_test_valid())
  let choosing = research_test_update(loaded, Choose)
  let malformed = research_test_update(
    choosing,
    Loaded(
      choosing.research_import.generation,
      choosing.dispatch_task_actor_id,
      "{",
      "",
    ),
  )
  assert_eq(malformed.research_import.brief, loaded.research_import.brief)
  assert_eq(malformed.dispatch_drafts, loaded.dispatch_drafts)
  assert_true(malformed.research_import.notice.contains("未被替换"))
  let undecided = research_test_loaded(loaded, "undecided")
  assert_eq(
    research_test_update(undecided, Prepare).dispatch_drafts,
    loaded.dispatch_drafts,
  )
}

///|
test "research stale file reads cancel newer choice navigation and actor switch cannot replace preview" {
  let base = { ..initial_model(), page: Dispatch, }
  let first = research_test_update(base, Choose)
  let old_generation = first.research_import.generation
  let second = research_test_update(first, Choose)
  let stale = research_test_update(
    second,
    Loaded(old_generation, "", research_test_export("current"), ""),
  )
  assert_true(stale.research_import.loading)
  assert_eq(stale.research_import.brief, None)
  assert_eq(
    research_test_update(stale, Prepare).dispatch_drafts,
    base.dispatch_drafts,
  )
  let closed = research_test_update(second, Close)
  let late = research_test_update(
    closed,
    Loaded(
      second.research_import.generation,
      "",
      research_test_export("current"),
      "",
    ),
  )
  assert_false(late.research_import.open)
  assert_eq(late.research_import.brief, None)
  assert_eq(
    research_test_update(late, Prepare).dispatch_drafts,
    base.dispatch_drafts,
  )
  let (_, away) = update(_ => none, Navigate(Guide), second)
  let (_, back) = update(_ => none, Navigate(Dispatch), away)
  assert_eq(
    research_test_update(
      back,
      Loaded(
        second.research_import.generation,
        "",
        research_test_export("current"),
        "",
      ),
    ).research_import.brief,
    None,
  )
  let changed = research_import_reconcile(second, {
    ..second,
    dispatch_task_actor_id: "other-actor",
  })
  assert_eq(
    research_test_update(
      changed,
      Loaded(
        second.research_import.generation,
        "",
        research_test_export("current"),
        "",
      ),
    ).research_import.brief,
    None,
  )
}

///|
test "research historical evidence stays visibly unverified with one explicit editable draft action" {
  let loaded = research_test_loaded(drafts_test_valid(), "historical")
  let html = opc_render_cell(
    @rabbita.static_cell(research_import_view(_ => none, loaded)),
  )
  assert_true(html.contains("Historical or unavailable current context"))
  assert_true(html.contains("当前新鲜度未核实"))
  assert_true(html.contains("&lt;evidence&gt;"))
  assert_false(html.contains("source <evidence>"))
  assert_true(html.contains("准备可编辑草稿"))
  assert_false(html.contains("我已核对保留来源"))
  assert_false(html.contains("已核对来源与局限"))
  let prepared = research_test_update(loaded, Prepare)
  assert_eq(
    prepared.dispatch_drafts.length(),
    loaded.dispatch_drafts.length() + 1,
  )
  assert_true(
    dispatch_active_draft(prepared).unwrap().research_brief.unwrap().evidence_status.has_prefix(
      "Historical",
    ),
  )
  assert_true(
    research_founder_packet(dispatch_active_draft(prepared).unwrap()).contains(
      "Historical or unavailable current context",
    ),
  )
}

///|
test "research storage and portable founder packet round-trip full provenance without authority" {
  let prepared = research_test_update(
    research_test_ready(drafts_test_valid()),
    Prepare,
  )
  let edited = drafts_test_update(
    prepared,
    Input("acceptance", "Compare three replies"),
  )
  let body = dispatch_draft_store(edited)
  assert_false(body.contains("actor-drafts"))
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", body),
  )
  let draft = dispatch_draft_by_id(restored, edited.dispatch_draft_id).unwrap()
  assert_eq(draft, dispatch_active_draft(edited).unwrap())
  let packet = research_founder_packet(draft)
  for
    text in [
      "Compare three replies", "Local pilot 学习 🌒", "Reduce uncertainty", "Table 2",
      "Replication missing", "1790000000000", "2026-09-14", "sha256:independent-handoff",
      "https://example.org/independent-handoff.pdf",
    ] {
    assert_true(packet.contains(text), msg=text)
  }
  for
    text in [
      "actor-drafts",
      "principal-opc-dispatch",
      draft.idempotency_key,
      draft.task_id,
    ] {
    assert_false(packet.contains(text), msg=text)
  }
}

///|
test "research prepare effect stores locally and never dispatches a network command" {
  drafts_test_transport(false)
  defer drafts_test_transport_cleanup()
  let ready = research_test_ready(drafts_test_valid())
  let (command, prepared) = update(
    _ => none,
    ResearchImportAction(Prepare),
    ready,
  )
  drafts_test_execute(command)
  assert_eq(drafts_test_events(), "save")
  assert_eq(drafts_test_post_count(), 0)
  assert_eq(prepared.dispatch_task_id, ready.dispatch_task_id)
  assert_false(dispatch_active_draft(prepared).unwrap().attempted)
  assert_eq(
    dispatch_json_field(
      dispatch_draft_create_body(
        dispatch_active_draft(prepared).unwrap(),
        "actor-drafts",
      ),
      "research_brief",
    ),
    Json::null(),
  )
}

///|
test "research same run revision changed source rejects without destroying prior draft" {
  let prepared = research_test_update(
    research_test_ready(drafts_test_valid()),
    Prepare,
  )
  let brief = prepared.research_import.brief.unwrap()
  let changed = {
    ..brief,
    worksheet: { ..brief.worksheet, reasoning: "Changed without a revision", },
  }
  let choosing = research_test_update(prepared, Choose)
  let rejected = research_test_update(
    choosing,
    Loaded(
      choosing.research_import.generation,
      choosing.dispatch_task_actor_id,
      ToJson::to_json(changed).stringify(),
      "",
    ),
  )
  assert_eq(rejected.dispatch_drafts, prepared.dispatch_drafts)
  assert_eq(rejected.research_import.brief, prepared.research_import.brief)
  assert_true(
    rejected.research_import.notice.contains(
      "同一研究运行和版本已有不同内容",
    ),
  )
}

///|
test "research malformed retained storage fails visibly and legacy drafts still load" {
  let prepared = research_test_update(
    research_test_ready(drafts_test_valid()),
    Prepare,
  )
  let draft = dispatch_active_draft(prepared).unwrap()
  let brief = draft.research_brief.unwrap()
  let invalid = {
    ..draft,
    research_brief: Some({
      ..brief,
      worksheet: { ..brief.worksheet, chosen_option_id: "missing", },
    }),
  }
  let text = dispatch_draft_store(dispatch_replace_draft(prepared, invalid))
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", text),
  )
  assert_eq(restored.dispatch_drafts.length(), 1)
  assert_eq(dispatch_draft_by_id(restored, draft.id), None)
  assert_true(
    restored.dispatch_draft_storage.contains(
      "研究来源版本或引用损坏",
    ),
  )
}
