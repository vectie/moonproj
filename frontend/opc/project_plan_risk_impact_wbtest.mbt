///|
fn risk_impact_test_model() -> Model {
  let model = plan_test_model()
  let d = model.plan.draft.unwrap()
  let draft = {
    ..d,
    tasks: [
      d.tasks[0],
      { ..d.tasks[1], id: "task-build", name: "Build", cost: "120.50", },
      { ..d.tasks[1], id: "task-docs", name: "Documentation", cost: "", },
      { ..d.tasks[1], dependencies: ["task-build", "task-docs"], },
      { ..d.tasks[0], id: "task-unrelated", name: "Unrelated", },
    ],
    risks: [
      {
        id: "risk-api",
        summary: "API <change> & rollout 风险",
        severity: "high",
        owner: "owner-test",
        mitigation: "Keep fallback\nReview contract",
        tasks: ["task-design", "task-build"],
      },
    ],
  }
  { ..model, plan: { ..model.plan, draft: Some(draft), }, }
}

///|
test "risk explorer is reachable and downloads the exact source-backed live draft without writes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = risk_impact_test_model()
  assert_true(products_test_html(model).contains("Risk impact explorer"))
  assert_true(products_test_html(model).contains("Select a risk to inspect"))
  let (_, selected) = plan_update(_ => none, RiskFocus("risk-api"), model)
  let prepared = {
    ..selected,
    plan: { ..selected.plan, prepared: Some({ "saved": "unchanged" }), },
  }
  let stored = plan_restore("owner-test", "company-actual")
  let html = products_test_html(prepared)
  assert_true(html.contains("Download risk impact brief (.txt)"))
  assert_true(html.contains("Directly linked tasks (2)"))
  assert_true(html.contains("Downstream-only tasks (2)"))
  assert_false(html.contains("API <change>"))
  ignore(plan_test_file("risk-impact-preview.html", html))
  for _i in 0..<2 {
    let (cmd, after) = plan_update(_ => none, ExportRiskImpact, prepared)
    drafts_test_execute(cmd)
    assert_eq(after.plan, prepared.plan)
  }
  guard @json.parse(plan_test_downloads()) is Array([first, second]) else {
    fail("two downloads expected")
  }
  assert_eq(first, second)
  assert_eq(products_text(first, "name"), "plan-risk-impact.txt")
  assert_eq(products_text(first, "type"), "text/plain;charset=utf-8")
  let expected = @plan_workbench.risk_impact_report(
    prepared.plan.draft.unwrap(),
    "risk-api",
    "Synthetic test project",
  )
  assert_eq(products_text(first, "text"), expected)
  assert_true(
    expected.contains(
      "Known cost subtotal (minor units, 100 per entered unit): 62075",
    ),
  )
  assert_true(expected.contains("Blank/invalid cost estimates: 1"))
  ignore(plan_test_file("risk-impact-brief.txt", expected))
  ignore(
    plan_test_file(
      "risk-impact-input.json",
      prepared.plan.draft.unwrap().to_json().stringify(),
    ),
  )
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "risk impact follows task and risk link edits then restores draft without saving selection" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, selected) = plan_update(
    _ => none,
    RiskFocus("risk-api"),
    risk_impact_test_model(),
  )
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-docs", "cost", "80.25"),
    selected,
  )
  let (cmd, unchanged) = plan_update(_ => none, ExportRiskImpact, edited)
  drafts_test_execute(cmd)
  assert_eq(unchanged.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([first]) else {
    fail("download expected")
  }
  assert_true(
    products_text(first, "text").contains(
      "minor units, 100 per entered unit): 70100",
    ),
  )
  assert_true(
    products_text(first, "text").contains("Blank/invalid cost estimates: 0"),
  )
  let (_, narrowed) = plan_update(
    _ => none,
    Toggle("risk", "risk-api", "task-design"),
    edited,
  )
  assert_true(
    products_test_html(narrowed).contains("Downstream-only tasks (1)"),
  )
  let stored = plan_restore("owner-test", "company-actual")
  assert_false(stored.contains("risk_focus"))
  let (_, cleared) = plan_update(_ => none, RiskFocus(""), narrowed)
  assert_eq(cleared.plan.draft, narrowed.plan.draft)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  let (none_selected, _) = plan_update(_ => none, ExportRiskImpact, cleared)
  assert_eq(products_test_effect_count(none_selected), 0)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), narrowed)
  assert_eq(switched.plan.risk_focus, "")
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), switched)
  assert_eq(restored.plan.draft, narrowed.plan.draft)
  assert_eq(restored.plan.risk_focus, "")
  assert_eq(plan_test_requests(), "[]")
}

///|
test "risk export blocks stale scope and invalid graph with repairable errors and unchanged drafts" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, model) = plan_update(
    _ => none,
    RiskFocus("risk-api"),
    risk_impact_test_model(),
  )
  let (_, cyclic) = plan_update(
    _ => none,
    Toggle("task", "task-design", "task-review"),
    model,
  )
  let (blocked, error) = plan_update(_ => none, ExportRiskImpact, cyclic)
  assert_eq(products_test_effect_count(blocked), 0)
  assert_true(error.plan.note.contains("Dependency cycle"))
  assert_eq(error.plan.draft, cyclic.plan.draft)
  assert_eq(error.plan.prepared, cyclic.plan.prepared)
  let (_, removed) = plan_update(_ => none, Remove("risk", "risk-api"), model)
  let (stale, stale_error) = plan_update(_ => none, ExportRiskImpact, removed)
  assert_eq(products_test_effect_count(stale), 0)
  assert_true(stale_error.plan.note.contains("Select a current risk"))
  let (_, missing) = plan_update(
    _ => none,
    Remove("task", "task-review"),
    model,
  )
  // Removing a linked source task leaves an explicit repair error.
  let (_, dangling) = plan_update(
    _ => none,
    Remove("task", "task-design"),
    missing,
  )
  let (bad_link, repair) = plan_update(_ => none, ExportRiskImpact, dangling)
  assert_eq(products_test_effect_count(bad_link), 0)
  assert_true(repair.plan.note.contains("missing prerequisite"))
  for
    changed in [
      { ..model, page: Overview, },
      { ..model, dispatch_task_actor_id: "other", },
      { ..model, plan: { ..model.plan, selected: "company-second", }, },
      { ..model, plan: { ..model.plan, projects: [], }, },
    ] {
    let (no_export, _) = plan_update(_ => none, ExportRiskImpact, changed)
    assert_eq(products_test_effect_count(no_export), 0)
  }
  assert_eq(plan_test_downloads(), "[]")
  assert_eq(plan_test_requests(), "[]")
}
