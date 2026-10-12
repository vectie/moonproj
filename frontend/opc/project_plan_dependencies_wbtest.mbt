///|
test "dependency explorer edits repairs restores exports and prepares an actual draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, reversed) = plan_update(
    _ => none,
    ShiftTask("task-review", -1),
    model,
  )
  let (_, focused) = plan_update(
    _ => none,
    DependencyFocus("task-design"),
    reversed,
  )
  assert_eq(focused.plan.draft, reversed.plan.draft)
  assert_eq(focused.plan.revision, reversed.plan.revision)
  let html = products_test_html(focused)
  ignore(plan_test_file("dependency-explorer.html", html))
  assert_true(html.contains("Wave 2"))
  assert_true(
    html.contains("Downstream tasks affected by a delay (1): task-review"),
  )
  assert_true(html.contains("Reviewable result"))
  let (_, ordered) = plan_update(_ => none, OrderDependencies, focused)
  assert_eq(ordered.plan.draft.unwrap().tasks.map(t => t.id), [
    "task-design", "task-review",
  ])
  assert_eq(ordered.plan.revision, focused.plan.revision + 1)
  assert_eq(ordered.plan.prepared, None)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, ordered.plan.draft.unwrap())
  let (_, exported) = plan_update(_ => none, ExportDependencies, ordered)
  assert_eq(exported.plan, ordered.plan)
  let downloads = @json.parse(plan_test_downloads())
  guard downloads is Array(items) else { fail("missing download") }
  assert_eq(
    products_text(items[0], "text"),
    @plan_workbench.dependency_report(restored, "task-design"),
  )
  ignore(plan_test_file("dependency-plan.txt", products_text(items[0], "text")))
  assert_eq(plan_test_requests(), "[]")
  let (cmd, saving) = plan_update(_ => none, Prepare, exported)
  drafts_test_execute(cmd)
  assert_eq(saving.plan.phase, "saving")
  assert_true(plan_test_requests().contains("task-design"))
}

///|
test "dependency cycle is actionable and leaves saved preview intact" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, cyclic) = plan_update(
    _ => none,
    Toggle("task", "task-design", "task-review"),
    model,
  )
  let (_, unchanged) = plan_update(_ => none, OrderDependencies, cyclic)
  assert_eq(unchanged.plan.draft, cyclic.plan.draft)
  assert_eq(unchanged.plan.revision, cyclic.plan.revision)
  assert_true(unchanged.plan.note.contains("Dependency cycle"))
  assert_true(products_test_html(unchanged).contains("Dependency cycle"))
}
