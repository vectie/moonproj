///|
fn breakdown_test_model() -> Model {
  let m = plan_test_model()
  let d = m.plan.draft.unwrap()
  {
    ..m,
    plan: {
      ..m.plan,
      prepared: Some({ "saved": "immutable" }),
      phase: "prepared",
      task_finder: { ..plan_task_finder_initial(), focus: "task-design", },
      draft: Some({
        ..d,
        risks: [
          {
            id: "risk-1",
            summary: "Design <risk>",
            severity: "medium",
            owner: "owner-test",
            mitigation: "Review",
            tasks: ["task-design", "task-review"],
          },
        ],
      }),
    },
  }
}

///|
fn breakdown_test_input(m : Model) -> Model {
  let (_, chosen) = plan_update(_ => none, Breakdown(Choose("task-design")), m)
  let steps = chosen.plan.breakdown.steps
  let (_, a) = plan_update(
    _ => none,
    Breakdown(Edit(steps[0].id, "name", "Research <scope>")),
    chosen,
  )
  let (_, b) = plan_update(
    _ => none,
    Breakdown(Edit(steps[0].id, "cost", "100.10")),
    a,
  )
  let (_, c) = plan_update(
    _ => none,
    Breakdown(Edit(steps[1].id, "name", "Design \"界面\"")),
    b,
  )
  let (_, d) = plan_update(
    _ => none,
    Breakdown(Edit(steps[1].id, "cost", "100.15")),
    c,
  )
  d
}

///|
test "breakdown UI previews applies persists exports and prepares complete rewired draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = breakdown_test_model()
  let before = model.plan.draft.unwrap()
  assert_true(
    plan_store(
      model.plan.actor,
      model.plan.selected,
      ToJson::to_json(before).stringify(),
    ),
  )
  let input = breakdown_test_input(model)
  let (_, preview) = plan_update(_ => none, Breakdown(Preview), input)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    ToJson::to_json(before),
  )
  assert_eq(plan_test_requests(), "[]")
  let html = products_test_html(preview)
  assert_true(html.contains("Break down a task"))
  assert_true(html.contains("Research &lt;scope&gt;"))
  assert_true(html.contains("Design &lt;risk&gt;"))
  assert_true(html.contains("Updated follower dependencies"))
  assert_true(html.contains("Expanded risk links"))
  assert_true(
    html.contains(
      "task-design, task-review → " +
      input.plan.breakdown.steps[0].id +
      ", " +
      input.plan.breakdown.steps[1].id +
      ", task-review",
    ),
  )
  assert_true(html.contains("Remaining to allocate: 0.00 CNY"))
  assert_true(html.contains("for=\"plan-breakdown-task\""))
  for step in input.plan.breakdown.steps {
    assert_true(html.contains("for=\"plan-breakdown-" + step.id + "-name\""))
    assert_true(html.contains("id=\"plan-breakdown-" + step.id + "-cost\""))
  }
  ignore(plan_test_file("breakdown-preview.html", html))
  ignore(
    plan_test_file(
      "breakdown-before.json",
      ToJson::to_json(before).stringify(indent=2),
    ),
  )
  let (_, repeated_preview) = plan_update(
    _ => none,
    Breakdown(Preview),
    preview,
  )
  assert_eq(repeated_preview.plan, preview.plan)
  let (cmd, applied) = plan_update(_ => none, Breakdown(Apply), preview)
  assert_eq(products_test_effect_count(cmd), 0)
  let edited = applied.plan.draft.unwrap()
  let steps = input.plan.breakdown.steps
  let expected = @plan_workbench.break_down_task(before, "task-design", steps)
  assert_eq(
    { ..edited, key: before.key, prepared_at: before.prepared_at, },
    expected,
  )
  assert_true(edited.key != before.key)
  assert_eq(edited.tasks.map(t => t.id), [
    steps[0].id,
    steps[1].id,
    "task-review",
  ])
  assert_eq(edited.tasks[2].dependencies, [steps[1].id])
  assert_eq(edited.risks[0].tasks, [steps[0].id, steps[1].id, "task-review"])
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_true(applied.plan.prepared is None)
  assert_eq(applied.plan.history, model.plan.history)
  assert_eq(applied.plan.breakdown, plan_breakdown_initial())
  assert_eq(applied.plan.task_finder.focus, "")
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    ToJson::to_json(edited),
  )
  ignore(
    plan_test_file("breakdown-after.json", ToJson::to_json(edited).stringify(indent=2)),
  )
  let (_, repeated) = plan_update(_ => none, Breakdown(Apply), applied)
  assert_eq(repeated.plan, applied.plan)
  let (_, away) = plan_update(_ => none, Choose("company-second"), applied)
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), away)
  assert_eq(restored.plan.draft, applied.plan.draft)
  assert_eq(restored.plan.breakdown, plan_breakdown_initial())
  let (download, _) = plan_update(_ => none, ExportTasks, restored)
  drafts_test_execute(download)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one CSV")
  }
  let csv = products_text(file, "text")
  assert_true(csv.contains("Research <scope>"))
  assert_false(csv.contains("task-design"))
  assert_eq(
    @plan_workbench.preview_task_table_updates(edited, csv, false).draft,
    edited,
  )
  ignore(plan_test_file("breakdown-tasks.csv", csv))
  let (prepare, pending) = plan_update(_ => none, Prepare, restored)
  drafts_test_execute(prepare)
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare")
  }
  let body = products_text(request, "body")
  assert_eq(@json.parse(body), ToJson::to_json(edited))
  ignore(plan_test_file("breakdown-prepare-request.json", body))
  let (again, unchanged) = plan_update(_ => none, Prepare, pending)
  assert_eq(products_test_effect_count(again), 0)
  assert_eq(unchanged.plan, pending.plan)
}

///|
test "breakdown cancel edit and changed scope invalidate only transient preview" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = breakdown_test_model()
  let input = breakdown_test_input(model)
  let (_, preview) = plan_update(_ => none, Breakdown(Preview), input)
  for
    action in [
      Breakdown(Close),
      Breakdown(Choose("")),
      Breakdown(Choose("task-review")),
      Breakdown(Edit(input.plan.breakdown.steps[0].id, "name", "Changed")),
      Breakdown(Add),
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (_, applied) = plan_update(_ => none, Breakdown(Apply), changed)
    assert_eq(applied.plan.draft, model.plan.draft)
    assert_eq(applied.plan.prepared, model.plan.prepared)
    assert_true(applied.plan.breakdown.preview is None)
  }
  let d = model.plan.draft.unwrap()
  let stale = {
    ..preview,
    plan: { ..preview.plan, draft: Some({ ..d, notes: "New scope", }), },
  }
  let (_, rejected) = plan_update(_ => none, Breakdown(Apply), stale)
  assert_eq(rejected.plan.draft, stale.plan.draft)
  assert_true(rejected.plan.breakdown.preview is None)
  assert_true(rejected.plan.breakdown.note.contains("draft changed"))
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-review", "cost", "250"),
    preview,
  )
  assert_eq(edited.plan.breakdown, plan_breakdown_initial())
  let (_, not_applied) = plan_update(_ => none, Breakdown(Apply), edited)
  assert_eq(not_applied.plan, edited.plan)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), preview)
  assert_eq(switched.plan.breakdown, plan_breakdown_initial())
  let (_, actor) = plan_update(_ => none, Breakdown(Apply), {
    ..preview,
    dispatch_task_actor_id: "someone-else",
  })
  assert_eq(actor.plan.breakdown, plan_breakdown_initial())
  let (_, refreshed) = plan_update(_ => none, Refresh, preview)
  assert_eq(refreshed.plan.breakdown, plan_breakdown_initial())
  assert_eq(plan_test_requests(), "[]")
}

///|
test "breakdown step controls enforce bounds and validation explains remaining allocation" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = breakdown_test_model()
  let (_, idle_add) = plan_update(_ => none, Breakdown(Add), model)
  assert_eq(idle_add.plan, model.plan)
  let (_, invalid_choice) = plan_update(
    _ => none,
    Breakdown(Choose("missing")),
    model,
  )
  assert_eq(invalid_choice.plan, model.plan)
  let (_, chosen) = plan_update(
    _ => none,
    Breakdown(Choose("task-design")),
    model,
  )
  let steps = chosen.plan.breakdown.steps
  let (_, short) = plan_update(
    _ => none,
    Breakdown(Remove(steps[0].id)),
    chosen,
  )
  assert_eq(short.plan, chosen.plan)
  let (_, unnamed) = plan_update(_ => none, Breakdown(Preview), chosen)
  assert_true(unnamed.plan.breakdown.preview is None)
  assert_true(unnamed.plan.breakdown.note.contains("name"))
  let input = breakdown_test_input(model)
  let (_, expensive) = plan_update(
    _ => none,
    Breakdown(Edit(input.plan.breakdown.steps[1].id, "cost", "101.15")),
    input,
  )
  assert_true(
    products_test_html(expensive).contains("Remaining to allocate: -1.00 CNY"),
  )
  let (_, rejected) = plan_update(_ => none, Breakdown(Preview), expensive)
  assert_true(rejected.plan.breakdown.preview is None)
  assert_true(rejected.plan.breakdown.note.contains("add up exactly"))
  let mut added = input
  for _ in 0..<8 {
    let (_, next) = plan_update(_ => none, Breakdown(Add), added)
    added = next
  }
  assert_eq(added.plan.breakdown.steps.length(), 10)
  let (_, over) = plan_update(_ => none, Breakdown(Add), added)
  assert_eq(over.plan, added.plan)
  let (_, removed) = plan_update(
    _ => none,
    Breakdown(Remove(added.plan.breakdown.steps[5].id)),
    added,
  )
  assert_eq(removed.plan.breakdown.steps.length(), 9)
  let (_, unknown_edit) = plan_update(
    _ => none,
    Breakdown(Edit("missing", "name", "X")),
    removed,
  )
  assert_eq(unknown_edit.plan, removed.plan)
  assert_eq(
    plan_breakdown_cost_note(
      [{ id: "a", name: "A", cost: "nan", }],
      "20",
      "USD",
    ),
    "Enter valid costs to see the remaining amount.",
  )
  assert_eq(
    plan_breakdown_cost_note([], "bad", "USD"),
    "Fix the original task cost before breaking it down.",
  )
  assert_eq(rejected.plan.draft, model.plan.draft)
  assert_eq(rejected.plan.prepared, model.plan.prepared)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "breakdown template replacement saved read and reload discard pending decomposition" {
  plan_test_browser()
  defer plan_test_cleanup()
  let input = breakdown_test_input(breakdown_test_model())
  let (_, preview) = plan_update(_ => none, Breakdown(Preview), input)
  let (_, source) = plan_update(
    _ => none,
    Template(
      Source(@plan_workbench.export_template(plan_template_test_draft())),
    ),
    preview,
  )
  let (_, template) = plan_update(_ => none, Template(Preview), source)
  let (_, mapped) = plan_update(_ => none, Template(Owner("owner-1")), template)
  let (_, replaced) = plan_update(_ => none, Template(Apply), mapped)
  assert_eq(replaced.plan.breakdown, plan_breakdown_initial())
  let (_, cannot_apply) = plan_update(_ => none, Breakdown(Apply), replaced)
  assert_eq(cannot_apply.plan, replaced.plan)
  let draft = { ..plan_test_draft(), key: "saved-synthetic", }
  let saved = plan_compare_test_saved(draft)
  let (_, opening) = plan_update(_ => none, Open(draft.key), preview)
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
  assert_eq(opened.plan.breakdown, plan_breakdown_initial())
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), preview)
  assert_eq(reloaded.plan.draft, Some(draft))
  assert_eq(reloaded.plan.breakdown, plan_breakdown_initial())
  let large = {
    ..draft,
    tasks: Array::makei(100, i => {
      ..draft.tasks[0],
      id: "task-" + i.to_string(),
    }),
  }
  let full = {
    ..preview,
    plan: {
      ..preview.plan,
      draft: Some(large),
      breakdown: plan_breakdown_initial(),
    },
  }
  let (_, chosen) = plan_update(_ => none, Breakdown(Choose("task-0")), full)
  let (_, too_large) = plan_update(_ => none, Breakdown(Preview), chosen)
  assert_true(too_large.plan.breakdown.preview is None)
  assert_true(too_large.plan.breakdown.note.contains("100 tasks"))
  assert_eq(too_large.plan.draft, Some(large))
  assert_eq(plan_test_requests(), "[]")
}
