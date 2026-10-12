///|
test "owner brief selection render edits and download preserve local plan" {
  plan_test_browser()
  defer plan_test_cleanup()
  let base = plan_test_model()
  let d = base.plan.draft.unwrap()
  let original = {
    ..base,
    plan: {
      ..base.plan,
      draft: Some({
        ..d,
        owners: [
          ..d.owners,
          { id: "reviewer", name: "Synthetic reviewer", role: "Review", },
        ],
        tasks: [
          {
            ..d.tasks[0],
            id: "task-input",
            name: "Provide example",
            owner: "reviewer",
            dependencies: [],
          },
          { ..d.tasks[0], dependencies: ["task-input"], },
          { ..d.tasks[1], owner: "reviewer", },
        ],
        risks: [
          {
            id: "risk-review",
            summary: "Example arrives late",
            severity: "medium",
            owner: "reviewer",
            mitigation: "Agree a smaller example\nKeep source context",
            tasks: ["task-design"],
          },
        ],
      }),
    },
  }
  let (_, selected) = plan_update(_ => none, BriefOwner("owner-test"), original)
  assert_eq(selected.plan.draft, original.plan.draft)
  assert_eq(selected.plan.revision, original.plan.revision)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Design <script>界面"),
    selected,
  )
  let html = products_test_html(edited)
  assert_true(html.contains("负责人计划简报"))
  assert_true(html.contains("下载负责人简报 (.txt)"))
  assert_true(html.contains("Design &lt;script&gt;界面"))
  let stored = plan_restore("owner-test", "company-actual")
  let (cmd, after) = plan_update(_ => none, ExportOwnerBrief, edited)
  drafts_test_execute(cmd)
  assert_eq(after.plan, edited.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(plan_test_requests(), "[]")
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one download")
  }
  let expected = @plan_workbench.owner_brief(
    edited.plan.draft.unwrap(),
    "owner-test",
    "Synthetic test project",
  )
  assert_eq(products_text(download, "name"), "plan-owner-brief.txt")
  assert_eq(products_text(download, "text"), expected)
  assert_true(
    expected.contains(
      "Provide example [task-input] · Synthetic reviewer [reviewer] → Design <script>界面 [task-design] · Test owner [owner-test]",
    ),
  )
  assert_true(
    expected.contains(
      "Design <script>界面 [task-design] · Test owner [owner-test] → Review [task-review] · Synthetic reviewer [reviewer]",
    ),
  )
  assert_true(expected.contains("任务上下文：Example arrives late"))
  ignore(
    plan_test_file(
      "owner-brief-input.json",
      edited.plan.draft.unwrap().to_json().stringify(indent=2),
    ),
  )
  ignore(plan_test_file("owner-brief.html", html))
  ignore(plan_test_file("plan-owner-brief.txt", expected))
  let prepared = {
    ..edited,
    plan: {
      ..edited.plan,
      prepared: Some({ "saved": "retained" }),
      phase: "prepared",
    },
  }
  let (export_again, unchanged) = plan_update(
    _ => none,
    ExportOwnerBrief,
    prepared,
  )
  drafts_test_execute(export_again)
  assert_eq(unchanged.plan, prepared.plan)
}

///|
test "owner brief scope changes and removed owners cannot export stale assignments" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, selected) = plan_update(
    _ => none,
    BriefOwner("owner-test"),
    plan_test_model(),
  )
  let (_, switched) = plan_update(_ => none, Choose("company-second"), selected)
  assert_eq(switched.plan.brief_owner, "")
  let (no_selection, _) = plan_update(_ => none, ExportOwnerBrief, switched)
  assert_eq(products_test_effect_count(no_selection), 0)
  let (other_actor, _) = plan_update(_ => none, ExportOwnerBrief, {
    ..selected,
    dispatch_task_actor_id: "different",
  })
  assert_eq(products_test_effect_count(other_actor), 0)
  let d = selected.plan.draft.unwrap()
  let missing = {
    ..selected,
    plan: { ..selected.plan, draft: Some({ ..d, owners: [], }), },
  }
  let (removed, _) = plan_update(_ => none, ExportOwnerBrief, missing)
  assert_eq(products_test_effect_count(removed), 0)
  assert_eq(plan_test_downloads(), "[]")
}
