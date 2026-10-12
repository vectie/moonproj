///|
fn handoff_test_preview(model : Model) -> Model {
  let (_, selected) = update(
    _ => none,
    PlanAction(Handoff(Select("task-review"))),
    model,
  )
  let (_, preview) = update(_ => none, PlanAction(Handoff(Preview)), selected)
  preview
}

///|
test "plan task handoff creates persists and reopens an independent source-backed Dispatch draft" {
  drafts_navigation_setup(
    "https://example.test/app?page=projects&task=canonical-task", "uuid",
  )
  defer drafts_navigation_cleanup()
  let base = consolidation_test_model()
  let (_, old_model) = dispatch_prepare_draft(
    _ => none,
    base,
    "",
    "company-second",
    None,
    true,
  )
  let old = dispatch_active_draft(old_model).unwrap()
  assert_true(
    dispatch_write_drafts(
      base.dispatch_task_actor_id,
      dispatch_draft_store(old_model),
    ),
  )
  // Simulate a saved draft that has not yet hydrated into the current model.
  let original = {
    ..base,
    dispatch_task_id: "canonical-task",
    dispatch_task_stage: "running",
  }
  let before = original.plan.draft.unwrap()
  let preview = handoff_test_preview(original)
  assert_eq(preview.plan.draft, original.plan.draft)
  assert_eq(preview.plan.prepared, original.plan.prepared)
  assert_eq(preview.dispatch_drafts, original.dispatch_drafts)
  assert_eq(drafts_navigation_requests(), "")
  let html = products_test_html(preview)
  for
    expected in [
      "Task draft preview", "Source snapshot reference", "Named reviewer receipt",
      "Scope &lt;risk&gt;", "Design [task-design]", "id=\"plan-handoff-task\"", "for=\"plan-handoff-task\"",
      "Create local task draft",
    ] {
    assert_true(html.contains(expected))
  }
  ignore(plan_test_file("plan-task-handoff-preview.html", html))
  let messages : Array[Msg] = []
  let (command, applied) = update(
    msg => {
      messages.push(msg)
      none
    },
    PlanAction(Handoff(CreateDraft)),
    preview,
  )
  drafts_test_execute(command)
  assert_eq(applied.page, Dispatch)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(saved_page_token(), "dispatch")
  assert_eq(applied.dispatch_task_id, original.dispatch_task_id)
  assert_eq(applied.dispatch_task_stage, original.dispatch_task_stage)
  assert_eq(applied.dispatch_run, original.dispatch_run)
  assert_eq(applied.plan.draft, Some(before))
  assert_eq(applied.plan.prepared, original.plan.prepared)
  assert_eq(dispatch_draft_by_id(applied, old.id), Some(old))
  assert_eq(applied.dispatch_drafts.length(), 2)
  assert_eq(applied.plan.handoff, plan_handoff_initial())
  let fresh = dispatch_active_draft(applied).unwrap()
  assert_true(
    fresh.id != old.id &&
    fresh.task_id != old.task_id &&
    fresh.idempotency_key != old.idempotency_key,
  )
  assert_eq(fresh.title, "Review")
  assert_eq(fresh.project_id, before.project_id)
  assert_eq(fresh.end_date, "2026-10-31")
  assert_eq(fresh.owner_id, "")
  assert_eq(fresh.begin_date, "")
  assert_eq(fresh.workspace, "")
  assert_eq(fresh.model, "")
  assert_eq(fresh.product_id, "")
  assert_eq(fresh.product_snapshot, None)
  assert_eq(fresh.offer_draft, None)
  assert_eq(fresh.research_brief, None)
  assert_eq(fresh.state, "editing")
  assert_false(fresh.attempted || fresh.recovery_required)
  assert_eq(drafts_navigation_requests(), "")
  assert_eq(messages.length(), 1)
  let (_, saved) = update(_ => none, messages[0], applied)
  assert_eq(saved.dispatch_draft_storage, "已保存到此浏览器")
  let stored = dispatch_read_drafts(original.dispatch_task_actor_id)
  let reloaded = drafts_test_update(
    {
      ..initial_model(),
      dispatch_task_actor_id: original.dispatch_task_actor_id,
    },
    Restored(original.dispatch_task_actor_id, stored),
  )
  assert_eq(dispatch_draft_by_id(reloaded, fresh.id), Some(fresh))
  assert_eq(dispatch_draft_by_id(reloaded, old.id), Some(old))
  let (repeat, unchanged) = update(
    _ => none,
    PlanAction(Handoff(CreateDraft)),
    saved,
  )
  assert_eq(products_test_effect_count(repeat), 0)
  assert_eq(unchanged.dispatch_drafts, saved.dispatch_drafts)
  // The source reference and copied text remain the original snapshot after edits.
  let (_, edited_plan) = plan_update(
    _ => none,
    Edit("task", "task-review", "name", "New review"),
    saved,
  )
  assert_eq(dispatch_draft_by_id(edited_plan, fresh.id), Some(fresh))
  assert_true(edited_plan.plan.draft.unwrap().key != before.key)
  let packet = work_packet_from_draft(fresh)
  assert_eq(@work_packet.decode(packet.encode()), packet)
  let create_body = dispatch_draft_create_body(
    fresh,
    original.dispatch_task_actor_id,
  )
  assert_eq(
    products_text(products_field(create_body, "source_context"), "reference"),
    fresh.source_reference.unwrap(),
  )
  assert_eq(
    products_text(products_field(create_body, "source_context"), "problem"),
    fresh.observed_problem.unwrap().trim().to_string(),
  )
  ignore(
    plan_test_file(
      "plan-task-handoff-source.json",
      before.to_json().stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file(
      "plan-task-handoff-draft.json",
      fresh.to_json().stringify(indent=2),
    ),
  )
  ignore(plan_test_file("plan-task-handoff-brief.json", packet.encode()))
  ignore(
    plan_test_file(
      "plan-task-handoff-create-projection.json",
      create_body.stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file("plan-task-handoff-dispatch.html", products_test_html(saved)),
  )
}

///|
test "plan task handoff cancel edits selection and context changes invalidate preview" {
  drafts_navigation_setup("https://example.test/app?page=projects", "uuid")
  defer drafts_navigation_cleanup()
  let original = consolidation_test_model()
  let preview = handoff_test_preview(original)
  for
    action in [
      Handoff(Close),
      Handoff(Select("task-design")),
      Edit("task", "task-review", "cost", "7"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (_, after) = plan_update(_ => none, Handoff(CreateDraft), changed)
    assert_eq(after.dispatch_drafts, original.dispatch_drafts)
    assert_true(after.plan.handoff.preview is None)
  }
  let d = preview.plan.draft.unwrap()
  let stale = {
    ..preview,
    plan: {
      ..preview.plan,
      draft: Some({ ..d, notes: "Changed without reducer", }),
    },
  }
  let (_, rejected) = plan_update(_ => none, Handoff(CreateDraft), stale)
  assert_true(rejected.plan.handoff.note.contains("plan changed"))
  assert_eq(rejected.dispatch_drafts, original.dispatch_drafts)
  for
    context in [
      { ..preview, dispatch_task_actor_id: "different-actor", },
      { ..preview, page: Products, },
      { ..preview, plan: { ..preview.plan, selected: "company-second", }, },
    ] {
    let (cmd, unchanged) = update(
      _ => none,
      PlanAction(Handoff(CreateDraft)),
      context,
    )
    assert_eq(products_test_effect_count(cmd), 0)
    assert_eq(unchanged.dispatch_drafts, original.dispatch_drafts)
  }
  let (_, invalid) = plan_update(
    _ => none,
    Handoff(Select("missing")),
    original,
  )
  let (_, result) = plan_update(_ => none, Handoff(Preview), invalid)
  assert_true(result.plan.handoff.note.contains("uniquely identified"))
  assert_eq(drafts_navigation_requests(), "")
}

///|
test "plan task handoff preserves unreadable stored collections" {
  drafts_test_transport(false)
  defer drafts_test_transport_cleanup()
  let preview = handoff_test_preview(consolidation_test_model())
  for
    text in [
      "damaged-json", "{\"version\":2,\"drafts\":[],\"recent_tasks\":[]}",
    ] {
    assert_true(dispatch_write_drafts(preview.plan.actor, text))
    let (cmd, blocked) = plan_update(_ => none, Handoff(CreateDraft), preview)
    assert_eq(products_test_effect_count(cmd), 0)
    assert_eq(blocked.page, Projects)
    assert_eq(blocked.dispatch_drafts, preview.dispatch_drafts)
    assert_true(blocked.plan.handoff.note.contains("could not be read"))
    assert_eq(dispatch_read_drafts(preview.plan.actor), text)
  }
  assert_eq(drafts_test_post_count(), 0)
}

///|
test "plan task handoff navigates Back and Forward without duplicating work and drops replaced previews" {
  drafts_navigation_setup("https://example.test/app?page=projects", "uuid")
  defer drafts_navigation_cleanup()
  let preview = handoff_test_preview(plan_test_model())
  let (command, applied) = update(
    _ => none,
    PlanAction(Handoff(CreateDraft)),
    preview,
  )
  drafts_test_execute(command)
  let fresh = dispatch_active_draft(applied).unwrap()
  assert_eq(drafts_navigation_metric("pushes"), 1)
  drafts_navigation_move(-1)
  assert_eq(saved_page_token(), "projects")
  let (back, projects) = update(_ => none, saved_page_route(), applied)
  drafts_test_execute(back)
  assert_eq(projects.page, Projects)
  assert_eq(projects.plan.handoff, plan_handoff_initial())
  drafts_navigation_move(1)
  assert_eq(saved_page_token(), "dispatch")
  let (forward, resumed) = update(_ => none, saved_page_route(), projects)
  drafts_test_execute(forward)
  assert_eq(resumed.page, Dispatch)
  assert_eq(resumed.dispatch_drafts, applied.dispatch_drafts)
  assert_eq(dispatch_active_draft(resumed), Some(fresh))
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_false(drafts_navigation_requests().contains("POST"))
  let draft = { ..plan_test_draft(), key: "saved-other-version", }
  let saved = plan_compare_test_saved(draft)
  let (_, opening) = plan_update(_ => none, Open(draft.key), preview)
  assert_eq(opening.plan.handoff, plan_handoff_initial())
  let (_, opened) = plan_update(
    _ => none,
    Read(
      "owner-test",
      opening.plan.epoch,
      opening.plan.revision,
      draft.key,
      "",
      200,
      saved.stringify(),
    ),
    opening,
  )
  assert_eq(opened.plan.draft, Some(draft))
  assert_eq(opened.plan.handoff, plan_handoff_initial())
  let mut templated = preview
  for
    action in [
      Template(
        Source(@plan_workbench.export_template(plan_template_test_draft())),
      ),
      Template(Preview),
      Template(Owner("owner-1")),
      Template(Name("Replacement preparer")),
      Template(Apply),
    ] {
    let (_, next) = plan_update(_ => none, action, templated)
    templated = next
  }
  assert_eq(templated.plan.handoff, plan_handoff_initial())
  let (_, not_created) = plan_update(_ => none, Handoff(CreateDraft), templated)
  assert_eq(not_created.dispatch_drafts, preview.dispatch_drafts)
}

///|
test "plan task handoff failed persistence retains the editable draft and never sends a command" {
  drafts_test_transport(true)
  defer drafts_test_transport_cleanup()
  let preview = handoff_test_preview(plan_test_model())
  let messages : Array[Msg] = []
  let (cmd, applied) = update(
    msg => {
      messages.push(msg)
      none
    },
    PlanAction(Handoff(CreateDraft)),
    preview,
  )
  drafts_test_execute(cmd)
  assert_eq(messages.length(), 1)
  let (_, failed) = update(_ => none, messages[0], applied)
  assert_true(failed.dispatch_draft_storage.contains("未保存"))
  assert_eq(dispatch_active_draft(failed).unwrap().title, "Review")
  assert_eq(dispatch_active_draft(failed).unwrap().state, "editing")
  assert_eq(dispatch_read_drafts(failed.plan.actor), "")
  assert_eq(drafts_test_post_count(), 0)
}
