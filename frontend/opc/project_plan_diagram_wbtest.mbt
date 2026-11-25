///|
test "dependency map previews and downloads the current draft with focus and no external effect" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Design <draft> & review 🚀"),
    model,
  )
  let (_, focused) = plan_update(
    _ => none,
    DependencyFocus("task-design"),
    edited,
  )
  let stored = plan_restore("owner-test", "company-actual")
  let html = products_test_html(focused)
  assert_true(html.contains("Download dependency map (.svg)"))
  assert_true(html.contains("Visual dependency map"))
  assert_true(html.contains("data:image/svg+xml;charset=utf-8,"))
  assert_false(html.contains("<draft>"))
  ignore(plan_test_file("dependency-map-preview.html", html))
  let (cmd, after) = plan_update(_ => none, ExportDependencyDiagram, focused)
  drafts_test_execute(cmd)
  assert_eq(after.plan, focused.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(plan_test_requests(), "[]")
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one map expected")
  }
  assert_eq(products_text(download, "name"), "plan-dependencies.svg")
  assert_eq(products_text(download, "type"), "image/svg+xml;charset=utf-8")
  let expected = @plan_workbench.export_dependency_svg(
    focused.plan.draft.unwrap(),
    "Synthetic test project",
    "task-design",
  )
  assert_eq(products_text(download, "text"), expected)
  ignore(plan_test_file("plan-dependencies.svg", expected))
  ignore(
    plan_test_file(
      "dependency-map-input.json",
      ToJson::to_json(focused.plan.draft.unwrap()).stringify(),
    ),
  )
  let (repeat, unchanged) = plan_update(
    _ => none,
    ExportDependencyDiagram,
    after,
  )
  drafts_test_execute(repeat)
  assert_eq(unchanged.plan, after.plan)
  guard @json.parse(plan_test_downloads()) is Array(downloads) else {
    fail("downloads expected")
  }
  assert_eq(downloads.length(), 2)
  assert_eq(products_text(downloads[1], "text"), expected)
  let (_, cleared) = plan_update(_ => none, DependencyFocus(""), unchanged)
  assert_eq(cleared.plan.draft, unchanged.plan.draft)
  let (neutral, _) = plan_update(_ => none, ExportDependencyDiagram, cleared)
  drafts_test_execute(neutral)
  guard @json.parse(plan_test_downloads()) is Array(all_downloads) else {
    fail("downloads expected")
  }
  assert_true(products_text(all_downloads[2], "text").contains("Focus: none"))
}

///|
test "dependency map errors preserve saved results and scope changes cannot export an old plan" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let prepared = {
    ..model,
    plan: {
      ..model.plan,
      prepared: Some({ "immutable": "saved" }),
      phase: "prepared",
    },
  }
  let (cmd, kept) = plan_update(_ => none, ExportDependencyDiagram, prepared)
  drafts_test_execute(cmd)
  assert_eq(kept.plan, prepared.plan)
  let (_, cyclic) = plan_update(
    _ => none,
    Toggle("task", "task-design", "task-review"),
    model,
  )
  let (blocked, failed) = plan_update(
    _ => none,
    ExportDependencyDiagram,
    cyclic,
  )
  assert_eq(products_test_effect_count(blocked), 0)
  assert_eq(failed.plan.draft, cyclic.plan.draft)
  assert_eq(failed.plan.revision, cyclic.plan.revision)
  assert_true(failed.plan.note.contains("Dependency cycle"))
  assert_true(products_test_html(failed).contains("Dependency cycle"))
  for
    changed in [
      { ..model, page: Overview, },
      { ..model, dispatch_task_actor_id: "another-owner", },
      { ..model, plan: { ..model.plan, selected: "company-second", }, },
      { ..model, plan: { ..model.plan, projects: [], }, },
    ] {
    let (no_export, _) = plan_update(
      _ => none,
      ExportDependencyDiagram,
      changed,
    )
    assert_eq(products_test_effect_count(no_export), 0)
  }
  let (_, switched) = plan_update(_ => none, Choose("company-second"), model)
  let (empty, _) = plan_update(_ => none, ExportDependencyDiagram, switched)
  assert_eq(products_test_effect_count(empty), 0)
  let (_, stale) = plan_update(_ => none, DependencyFocus("removed"), model)
  let (missing, repair) = plan_update(_ => none, ExportDependencyDiagram, stale)
  assert_eq(products_test_effect_count(missing), 0)
  assert_true(repair.plan.note.contains("clear the diagram focus"))
  assert_eq(plan_test_requests(), "[]")
  guard @json.parse(plan_test_downloads()) is Array(downloads) else {
    fail("downloads expected")
  }
  assert_eq(downloads.length(), 1)
}

///|
test "parallel dependency map provides reusable practical diagram output" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let draft = model.plan.draft.unwrap()
  let first = draft.tasks[0]
  let last = draft.tasks[1]
  let full = {
    ..draft,
    tasks: [
      first,
      { ..last, id: "task-build", name: "Build prototype", },
      { ..last, id: "task-docs", name: "Write buyer documentation", },
      {
        ..last,
        name: "Review and deliver",
        dependencies: [first.id, "task-build", "task-docs"],
      },
    ],
  }
  let selected = {
    ..model,
    plan: { ..model.plan, draft: Some(full), dependency_focus: "task-build", },
  }
  let (cmd, _) = plan_update(_ => none, ExportDependencyDiagram, selected)
  drafts_test_execute(cmd)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("diagram expected")
  }
  ignore(plan_test_file("parallel-plan.svg", products_text(download, "text")))
  ignore(plan_test_file("parallel-input.json", ToJson::to_json(full).stringify()))
  assert_true(
    products_text(download, "text").contains("task-design -&gt; task-review"),
  )
}
