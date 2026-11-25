///|
test "budget breakdown renders current costs edits reload and repeated download without side effects" {
  plan_test_browser()
  defer plan_test_cleanup()
  let base = plan_test_model()
  let d = base.plan.draft.unwrap()
  let model = {
    ..base,
    plan: {
      ..base.plan,
      draft: Some({
        ..d,
        limit: "100",
        contingency: "5",
        tasks: [
          { ..d.tasks[0], name: "Design <script>界面", cost: "12.25", },
          { ..d.tasks[1], owner: "", milestone: "", cost: "", },
        ],
      }),
    },
  }
  let html = products_test_html(model)
  assert_true(html.contains("草稿成本分配 / Budget breakdown"))
  assert_true(html.contains("Design &lt;script&gt;界面"))
  assert_true(html.contains("Invalid or blank task costs: 1"))
  let (first, unchanged) = plan_update(_ => none, ExportBudgetBreakdown, model)
  drafts_test_execute(first)
  assert_eq(unchanged.plan, model.plan)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-review", "cost", "2.75"),
    model,
  )
  let reloaded : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(reloaded.tasks[1].cost, "2.75")
  let expected = @plan_workbench.budget_report(
    edited.plan.draft.unwrap(),
    "Synthetic test project",
  )
  assert_true(expected.contains("Known task subtotal: 1500"))
  assert_true(expected.contains("Remaining after tasks and contingency: 8000"))
  let prepared = {
    ..edited,
    plan: {
      ..edited.plan,
      prepared: Some({ "retained": true }),
      phase: "prepared",
    },
  }
  let storage = plan_restore("owner-test", "company-actual")
  let (second, after) = plan_update(_ => none, ExportBudgetBreakdown, prepared)
  drafts_test_execute(second)
  assert_eq(after.plan, prepared.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), storage)
  assert_eq(plan_test_requests(), "[]")
  guard @json.parse(plan_test_downloads()) is Array([old, current]) else {
    fail("two exports")
  }
  assert_eq(products_text(current, "name"), "plan-budget-breakdown.txt")
  assert_eq(products_text(current, "text"), expected)
  assert_true(
    products_text(old, "text").contains("Invalid or blank task costs: 1"),
  )
  assert_false(expected == products_text(old, "text"))
  ignore(
    plan_test_file(
      "budget-input.json",
      ToJson::to_json(edited.plan.draft.unwrap()).stringify(indent=2),
    ),
  )
  ignore(plan_test_file("budget-breakdown.txt", expected))
  ignore(
    plan_test_file(
      "budget-breakdown.json",
      ToJson::to_json(
        @plan_workbench.budget_breakdown(edited.plan.draft.unwrap()),
      ).stringify(indent=2),
    ),
  )
  ignore(plan_test_file("budget-preview.html", products_test_html(edited)))
}

///|
test "budget export is scoped to the current project and actor" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (wrong_actor, _) = plan_update(_ => none, ExportBudgetBreakdown, {
    ..model,
    dispatch_task_actor_id: "other",
  })
  assert_eq(products_test_effect_count(wrong_actor), 0)
  let (wrong_project, _) = plan_update(_ => none, ExportBudgetBreakdown, {
    ..model,
    plan: { ..model.plan, selected: "other", },
  })
  assert_eq(products_test_effect_count(wrong_project), 0)
  let (empty, _) = plan_update(_ => none, ExportBudgetBreakdown, {
    ..model,
    plan: { ..model.plan, draft: None, },
  })
  assert_eq(products_test_effect_count(empty), 0)
  assert_eq(plan_test_downloads(), "[]")
}

///|
test "budget allocation follows owner milestone and currency edits on the current draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let base = plan_test_model()
  let (_, owner_changed) = plan_update(
    _ => none,
    Edit("task", "task-design", "owner", ""),
    base,
  )
  let (_, milestone_changed) = plan_update(
    _ => none,
    Edit("task", "task-design", "milestone", ""),
    owner_changed,
  )
  let (_, edited) = plan_update(
    _ => none,
    Edit("plan", "", "currency", "EUR"),
    milestone_changed,
  )
  let report = @plan_workbench.budget_report(
    edited.plan.draft.unwrap(),
    "Synthetic test project",
  )
  assert_true(report.contains("Currency (authored): EUR"))
  let b = @plan_workbench.budget_breakdown(edited.plan.draft.unwrap())
  assert_eq(b.owners[0].label, "Unassigned")
  assert_eq(b.owners[0].task_ids, ["task-design"])
  assert_eq(b.milestones[0].label, "Unassigned")
  assert_eq(b.milestones[0].task_ids, ["task-design"])
  let (_, reopened) = plan_update(_ => none, Choose("company-actual"), edited)
  assert_eq(
    @plan_workbench.budget_report(
      reopened.plan.draft.unwrap(),
      "Synthetic test project",
    ),
    report,
  )
  let (cmd, unchanged) = plan_update(_ => none, ExportBudgetBreakdown, reopened)
  drafts_test_execute(cmd)
  assert_eq(unchanged.plan, reopened.plan)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one current export")
  }
  assert_eq(products_text(download, "text"), report)
  assert_eq(plan_test_requests(), "[]")
}
