///|
fn checklist_test_input(model : Model) -> Model {
  let (_, text) = update(
    _ => none,
    PlanAction(
      Checklist(
        Text(
          "# Customer <brief>\n- [ ] Research [buyers](https://example.test)\n  - [ ] Review 😀\n- [x] Prior delivery\n",
        ),
      ),
    ),
    model,
  )
  let (_, owner) = update(
    _ => none,
    PlanAction(Checklist(Owner("owner-test"))),
    text,
  )
  let (_, assigned) = update(
    _ => none,
    PlanAction(Checklist(Milestone("milestone-one"))),
    owner,
  )
  assigned
}

///|
test "checklist UI previews appends persists reloads and exports source-backed planned tasks" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = consolidation_test_model()
  let before = model.plan.draft.unwrap()
  assert_true(
    plan_store(
      model.plan.actor,
      model.plan.selected,
      ToJson::to_json(before).stringify(),
    ),
  )
  let input = checklist_test_input(model)
  let (cmd, preview) = update(_ => none, PlanAction(Checklist(Preview)), input)
  assert_eq(products_test_effect_count(cmd), 0)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    ToJson::to_json(before),
  )
  let html = products_test_html(preview)
  for
    expected in [
      "Checklist append preview", "New planned tasks: 2; checked items skipped: 1",
      "Customer &lt;brief&gt;", "for=\"plan-checklist-source\"", "id=\"plan-checklist-owner\"",
      "value=\"owner-test\" selected", "Append checklist tasks", "Original source retained verbatim",
    ] {
    assert_true(html.contains(expected))
  }
  ignore(plan_test_file("checklist-preview.html", html))
  ignore(plan_test_file("checklist-input.md", input.plan.checklist.text))
  let (_, repeated) = update(_ => none, PlanAction(Checklist(Preview)), preview)
  assert_eq(repeated.plan, preview.plan)
  let (command, applied) = update(
    _ => none,
    PlanAction(Checklist(Apply)),
    preview,
  )
  assert_eq(products_test_effect_count(command), 0)
  let after = applied.plan.draft.unwrap()
  assert_eq(after.tasks.length(), before.tasks.length() + 2)
  assert_eq(after.tasks[:before.tasks.length()].to_array(), before.tasks)
  assert_eq(after.risks, before.risks)
  assert_eq(after.milestones, before.milestones)
  assert_eq(after.owners, before.owners)
  assert_eq(after.limit, before.limit)
  assert_eq(after.contingency, before.contingency)
  assert_true(after.key != before.key)
  assert_true(after.notes.has_suffix(input.plan.checklist.text))
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_true(applied.plan.prepared is None)
  assert_eq(applied.plan.history, model.plan.history)
  assert_eq(applied.plan.checklist, plan_checklist_initial())
  assert_eq(applied.dispatch_task_id, model.dispatch_task_id)
  assert_eq(applied.dispatch_task_stage, model.dispatch_task_stage)
  assert_eq(applied.dispatch_drafts, model.dispatch_drafts)
  assert_eq(plan_test_requests(), "[]")
  let (_, repeat_apply) = update(
    _ => none,
    PlanAction(Checklist(Apply)),
    applied,
  )
  assert_eq(repeat_apply.plan, applied.plan)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
  )
  assert_eq(restored, after)
  let (_, reloaded) = plan_update(_ => none, Choose(model.plan.selected), {
    ..model,
    plan: {
      ..plan_initial(),
      actor: model.plan.actor,
      projects: model.plan.projects,
    },
  })
  assert_eq(reloaded.plan.draft, Some(after))
  let (_, exported) = plan_update(_ => none, ExportTasks, applied)
  assert_eq(exported.plan.draft, Some(after))
  let downloads = @json.parse(plan_test_downloads())
  let csv = match downloads {
    Array(items) => products_text(items[0], "text")
    _ => ""
  }
  assert_eq(csv, @plan_workbench.export_task_table(after))
  assert_true(csv.contains("Research [buyers](https://example.test)"))
  let added = after.tasks[before.tasks.length()]
  let handoff = @plan_workbench.task_handoff(after, added.id)
  assert_true(handoff.context.contains(input.plan.checklist.text))
  let request = @plan_workbench.request(
    after,
    model.plan.actor,
    {},
    "synthetic-input",
    "digest",
  )
  assert_eq(@plan_workbench.items(request, "tasks").length(), 5)
  ignore(
    plan_test_file(
      "checklist-after.json",
      ToJson::to_json(after).stringify(indent=2),
    ),
  )
  ignore(plan_test_file("checklist-tasks.csv", csv))
  ignore(
    plan_test_file(
      "checklist-prepare-projection.json",
      request.stringify(indent=2),
    ),
  )
}

///|
test "checklist input cancellation edits and navigation invalidate append previews" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = checklist_test_input(consolidation_test_model())
  let (_, preview) = update(_ => none, PlanAction(Checklist(Preview)), model)
  for
    action in [
      Checklist(Close),
      Checklist(Text("- [ ] Replacement")),
      Checklist(Owner("missing")),
      Checklist(Milestone("missing")),
      Checklist(IncludeChecked(true)),
      Edit("task", "task-design", "name", "Changed"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (_, applied) = plan_update(_ => none, Checklist(Apply), changed)
    assert_eq(applied.plan.draft, changed.plan.draft)
    assert_true(applied.plan.checklist.preview is None)
  }
  let d = preview.plan.draft.unwrap()
  let stale = {
    ..preview,
    plan: { ..preview.plan, draft: Some({ ..d, notes: "Changed elsewhere", }), },
  }
  let (_, rejected) = plan_update(_ => none, Checklist(Apply), stale)
  assert_eq(rejected.plan.draft, stale.plan.draft)
  assert_true(rejected.plan.checklist.note.contains("plan changed"))
  for
    context in [
      { ..preview, dispatch_task_actor_id: "other", },
      { ..preview, page: Products, },
      { ..preview, plan: { ..preview.plan, selected: "company-second", }, },
    ] {
    let (_, unchanged) = update(
      _ => none,
      PlanAction(Checklist(Apply)),
      context,
    )
    assert_eq(unchanged.dispatch_drafts, context.dispatch_drafts)
    if unchanged.plan.draft is Some(after) {
      assert_eq(after.tasks, d.tasks)
    }
  }
}

///|
test "checklist includes checked items only by choice and errors leave the draft usable" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = checklist_test_input(consolidation_test_model())
  let (_, invalid_input) = plan_update(
    _ => none,
    Checklist(Text("- [x] Earlier result")),
    model,
  )
  let (_, invalid) = plan_update(_ => none, Checklist(Preview), invalid_input)
  assert_true(invalid.plan.checklist.note.contains("No unchecked tasks"))
  assert_true(invalid.plan.checklist.preview is None)
  assert_eq(invalid.plan.draft, model.plan.draft)
  let (_, include_checked) = plan_update(
    _ => none,
    Checklist(IncludeChecked(true)),
    invalid,
  )
  let (_, preview) = plan_update(_ => none, Checklist(Preview), include_checked)
  assert_true(
    products_test_html(preview).contains("checked; will be planned again"),
  )
  let (_, applied) = plan_update(_ => none, Checklist(Apply), preview)
  let d = applied.plan.draft.unwrap()
  assert_eq(d.tasks.last().unwrap().name, "Earlier result")
  assert_eq(d.tasks.last().unwrap().dependencies, [])
  assert_eq(d.tasks.last().unwrap().cost, "0")
  assert_eq(applied.dispatch_task_stage, model.dispatch_task_stage)
  assert_eq(plan_test_requests(), "[]")
}

///|
extern "js" fn checklist_test_storage_failure() =
  #| () => { window.localStorage.setItem = () => { throw new Error('synthetic storage failure'); }; }

///|
test "checklist storage failure retains the local edit with an honest warning" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = checklist_test_input(consolidation_test_model())
  let (_, preview) = plan_update(_ => none, Checklist(Preview), model)
  checklist_test_storage_failure()
  let (_, applied) = plan_update(_ => none, Checklist(Apply), preview)
  assert_eq(applied.plan.draft.unwrap().tasks.length(), 5)
  assert_true(applied.plan.note.contains("浏览器存储不可用"))
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), "")
  assert_true(applied.plan.checklist.preview is None)
  assert_eq(plan_test_requests(), "[]")
}
