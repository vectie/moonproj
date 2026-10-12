///|
fn consolidation_test_model() -> Model {
  let m = plan_test_model()
  let d = m.plan.draft.unwrap()
  {
    ..m,
    plan: {
      ..m.plan,
      prepared: Some({ "saved": "immutable" }),
      phase: "prepared",
      history: [{ "key": "previous-saved-version" }],
      task_finder: { ..plan_task_finder_initial(), focus: "task-review", },
      draft: Some({
        ..d,
        tasks: [
          ..d.tasks,
          {
            ..d.tasks[1],
            id: "task-ship",
            name: "Ship",
            dependencies: ["task-design", "task-review"],
            cost: "5",
          },
        ],
        risks: [
          {
            id: "risk-1",
            summary: "Scope <risk>",
            severity: "medium",
            owner: "owner-test",
            mitigation: "Check combined scope",
            tasks: ["task-design", "task-review", "task-ship"],
          },
        ],
      }),
    },
  }
}

///|
fn consolidation_test_input(model : Model) -> Model {
  let (_, first) = plan_update(
    _ => none,
    Consolidation(Toggle("task-design")),
    model,
  )
  let (_, both) = plan_update(
    _ => none,
    Consolidation(Toggle("task-review")),
    first,
  )
  let (_, named) = plan_update(
    _ => none,
    Consolidation(Name("Design & review <界面>")),
    both,
  )
  named
}

///|
test "consolidation UI previews applies persists reloads exports and prepares the rewired draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = consolidation_test_model()
  let before = model.plan.draft.unwrap()
  assert_true(
    plan_store(
      model.plan.actor,
      model.plan.selected,
      before.to_json().stringify(),
    ),
  )
  let input = consolidation_test_input(model)
  let (_, preview) = plan_update(_ => none, Consolidation(Preview), input)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    before.to_json(),
  )
  assert_eq(plan_test_requests(), "[]")
  let html = products_test_html(preview)
  for
    expected in [
      "Consolidate tasks", "Design &amp; review &lt;界面&gt;", "Scope &lt;risk&gt;",
      "Combined cost: 500.25 CNY", "task-design, task-review → task-design", "task-design, task-review, task-ship → task-design, task-ship",
      "Resulting dependency order", "for=\"plan-consolidation-name\"", "id=\"plan-consolidation-retained\"",
    ] {
    assert_true(html.contains(expected))
  }
  ignore(plan_test_file("consolidation-preview.html", html))
  ignore(
    plan_test_file(
      "consolidation-before.json",
      before.to_json().stringify(indent=2),
    ),
  )
  let (_, repeated_preview) = plan_update(
    _ => none,
    Consolidation(Preview),
    preview,
  )
  assert_eq(repeated_preview.plan, preview.plan)
  let (command, applied) = plan_update(_ => none, Consolidation(Apply), preview)
  assert_eq(products_test_effect_count(command), 0)
  let edited = applied.plan.draft.unwrap()
  let expected = @plan_workbench.consolidate_tasks(
    before,
    input.plan.consolidation.selected,
    "task-design",
    input.plan.consolidation.name,
  )
  assert_eq(
    { ..edited, key: before.key, prepared_at: before.prepared_at, },
    expected,
  )
  assert_true(edited.key != before.key)
  assert_eq(edited.tasks.map(t => t.id), ["task-design", "task-ship"])
  assert_eq(edited.tasks[1].dependencies, ["task-design"])
  assert_eq(edited.risks[0].tasks, ["task-design", "task-ship"])
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_true(applied.plan.prepared is None)
  assert_eq(applied.plan.history, model.plan.history)
  assert_eq(applied.plan.consolidation, plan_consolidation_initial())
  assert_eq(applied.plan.task_finder.focus, "")
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    edited.to_json(),
  )
  ignore(
    plan_test_file(
      "consolidation-after.json",
      edited.to_json().stringify(indent=2),
    ),
  )
  let (_, repeat) = plan_update(_ => none, Consolidation(Apply), applied)
  assert_eq(repeat.plan, applied.plan)
  let (_, away) = plan_update(_ => none, Choose("company-second"), applied)
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), away)
  assert_eq(restored.plan.draft, applied.plan.draft)
  assert_eq(restored.plan.consolidation, plan_consolidation_initial())
  let (download, _) = plan_update(_ => none, ExportTasks, restored)
  drafts_test_execute(download)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one CSV")
  }
  let csv = products_text(file, "text")
  assert_true(csv.contains("Design & review <界面>"))
  assert_false(csv.contains("task-review"))
  assert_eq(
    @plan_workbench.preview_task_table_updates(edited, csv, false).draft,
    edited,
  )
  ignore(plan_test_file("consolidation-tasks.csv", csv))
  let wire = @plan_workbench.request(
    edited,
    "owner-test",
    {},
    "synthetic-source",
    "digest",
  )
  ignore(
    plan_test_file(
      "consolidation-native-projection.json",
      wire.stringify(indent=2),
    ),
  )
  assert_eq(plan_test_requests(), "[]")
  let (prepare, _) = plan_update(_ => none, Prepare, restored)
  drafts_test_execute(prepare)
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare")
  }
  let body = products_text(request, "body")
  assert_eq(@json.parse(body), edited.to_json())
  ignore(plan_test_file("consolidation-prepare-request.json", body))
}

///|
test "consolidation preview is invalidated by selection scope and other editing without draft mutation" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = consolidation_test_model()
  let input = consolidation_test_input(model)
  let (_, preview) = plan_update(_ => none, Consolidation(Preview), input)
  for
    action in [
      Consolidation(Close),
      Consolidation(Toggle("task-review")),
      Consolidation(Retain("task-review")),
      Consolidation(Name("Changed")),
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (_, applied) = plan_update(_ => none, Consolidation(Apply), changed)
    assert_eq(applied.plan.draft, model.plan.draft)
    assert_eq(applied.plan.prepared, model.plan.prepared)
    assert_true(applied.plan.consolidation.preview is None)
  }
  let d = model.plan.draft.unwrap()
  let stale = {
    ..preview,
    plan: { ..preview.plan, draft: Some({ ..d, notes: "Changed source", }), },
  }
  let (_, rejected) = plan_update(_ => none, Consolidation(Apply), stale)
  assert_eq(rejected.plan.draft, stale.plan.draft)
  assert_true(rejected.plan.consolidation.preview is None)
  assert_true(rejected.plan.consolidation.note.contains("draft changed"))
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-ship", "cost", "8"),
    preview,
  )
  assert_eq(edited.plan.consolidation, plan_consolidation_initial())
  let (_, apply) = plan_update(_ => none, Consolidation(Apply), edited)
  assert_eq(apply.plan, edited.plan)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), preview)
  assert_eq(switched.plan.consolidation, plan_consolidation_initial())
  let (_, actor) = plan_update(_ => none, Consolidation(Apply), {
    ..preview,
    dispatch_task_actor_id: "other",
  })
  assert_eq(actor.plan.consolidation, plan_consolidation_initial())
  let (_, refreshed) = plan_update(_ => none, Refresh, preview)
  assert_eq(refreshed.plan.consolidation, plan_consolidation_initial())
  assert_eq(plan_test_requests(), "[]")
}

///|
test "consolidation selection controls validation and storage failure leave the draft usable" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = consolidation_test_model()
  for
    action in [
      Consolidation(Toggle("missing")),
      Consolidation(Retain("task-ship")),
      Consolidation(Apply),
    ] {
    let (_, unchanged) = plan_update(_ => none, action, model)
    assert_eq(unchanged.plan, model.plan)
  }
  let (_, short) = plan_update(_ => none, Consolidation(Preview), model)
  assert_true(short.plan.consolidation.note.contains("2 to 100"))
  let input = consolidation_test_input(model)
  let (_, retained) = plan_update(
    _ => none,
    Consolidation(Retain("task-review")),
    input,
  )
  let (_, preview) = plan_update(_ => none, Consolidation(Preview), retained)
  assert_eq(
    preview.plan.consolidation.preview.unwrap().tasks[0].id,
    "task-review",
  )
  let (_, unnamed) = plan_update(_ => none, Consolidation(Name(" ")), preview)
  let (_, invalid) = plan_update(_ => none, Consolidation(Preview), unnamed)
  assert_true(invalid.plan.consolidation.preview is None)
  assert_true(invalid.plan.consolidation.note.contains("name"))
  assert_eq(invalid.plan.draft, model.plan.draft)
  let (_, toggled) = plan_update(
    _ => none,
    Consolidation(Toggle("task-review")),
    retained,
  )
  assert_eq(toggled.plan.consolidation.retained, "task-design")
  let (_, cleared) = plan_update(
    _ => none,
    Consolidation(Toggle("task-design")),
    toggled,
  )
  assert_eq(cleared.plan.consolidation.retained, "")
  consolidation_test_storage_failure()
  let (_, applied) = plan_update(_ => none, Consolidation(Apply), preview)
  assert_eq(applied.plan.draft.unwrap().tasks[0].id, "task-review")
  assert_true(applied.plan.note.contains("浏览器存储不可用"))
  assert_eq(plan_test_requests(), "[]")
}

///|
extern "js" fn consolidation_test_storage_failure() =
  #| () => {window.localStorage.setItem = () => {throw new Error('synthetic storage unavailable')};}

///|
test "consolidation opening saved history template replacement and reload discard the old preview" {
  plan_test_browser()
  defer plan_test_cleanup()
  let input = consolidation_test_input(consolidation_test_model())
  let (_, preview) = plan_update(_ => none, Consolidation(Preview), input)
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
  assert_eq(replaced.plan.consolidation, plan_consolidation_initial())
  let (_, cannot_apply) = plan_update(_ => none, Consolidation(Apply), replaced)
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
  assert_eq(opened.plan.consolidation, plan_consolidation_initial())
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), preview)
  assert_eq(reloaded.plan.draft, Some(draft))
  assert_eq(reloaded.plan.consolidation, plan_consolidation_initial())
  assert_eq(plan_test_requests(), "[]")
}
