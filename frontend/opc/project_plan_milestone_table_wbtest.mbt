///|
fn milestone_edits_fixture() -> Model {
  let model = plan_test_model()
  let d = model.plan.draft.unwrap()
  {
    ..model,
    plan: {
      ..model.plan,
      draft: Some({
        ..d,
        milestones: [
          ..d.milestones,
          {
            ..d.milestones[0],
            id: "milestone-two",
            name: "Follow-up",
            date: "2026-11-10",
          },
          {
            ..d.milestones[0],
            id: "milestone-three",
            name: "Later",
            date: "2026-12-01",
          },
        ],
      }),
      prepared: Some({ "fixture": "previous prepared result" }),
      phase: "prepared",
      milestone_table: {
        ..plan_milestone_table_initial(),
        text: "id,title,date,criteria,evidence,Status\nmilestone-two,Follow-up,2026-11-04,,,Done\nmilestone-one,\"Review <script>界面, \"\"new\"\"\",2026-11-02,\"One\nTwo\",\"Receipt\nEvidence\",Accepted",
      },
    },
  }
}

///|
test "milestone table UI roundtrip renders persists exports and prepares current edits" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = milestone_edits_fixture()
  assert_true(
    plan_store(
      "owner-test",
      "company-actual",
      ToJson::to_json(original.plan.draft.unwrap()).stringify(),
    ),
  )
  let stored = plan_restore("owner-test", "company-actual")
  let (_, previewed) = plan_update(_ => none, MilestoneTable(Preview), original)
  assert_eq(previewed.plan.draft, original.plan.draft)
  assert_eq(previewed.plan.prepared, original.plan.prepared)
  assert_eq(previewed.plan.revision, original.plan.revision)
  assert_eq(previewed.plan.phase, original.plan.phase)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(previewed.plan.milestone_table.preview.unwrap().changes.length(), 2)
  let html = products_test_html(previewed)
  assert_true(html.contains("Edit milestone table"))
  assert_true(html.contains("Milestone edit preview"))
  assert_true(html.contains("Before / 修改前"))
  assert_true(html.contains("Review &lt;script&gt;界面"))
  assert_true(html.contains("Ignored columns: Status"))
  assert_true(html.contains("for=\"plan-milestone-table\""))
  let (_, edited) = plan_update(_ => none, MilestoneTable(Apply), previewed)
  let d = edited.plan.draft.unwrap()
  assert_eq(d.milestones[0].id, "milestone-one")
  assert_eq(d.milestones[0].date, "2026-11-02")
  assert_eq(d.milestones[0].name, "Review <script>界面, \"new\"")
  assert_eq(d.milestones[0].criteria, "One\nTwo")
  assert_eq(d.milestones[1].date, "2026-11-04")
  assert_eq(d.milestones[1].criteria, "")
  assert_eq(d.milestones[1].evidence, "")
  assert_eq(d.milestones[2], original.plan.draft.unwrap().milestones[2])
  assert_eq(d.tasks, original.plan.draft.unwrap().tasks)
  assert_eq(edited.plan.prepared, None)
  assert_eq(edited.plan.revision, original.plan.revision + 1)
  assert_eq(edited.plan.milestone_table.preview, None)
  assert_eq(
    edited.plan.milestone_table.text,
    original.plan.milestone_table.text,
  )
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, d)
  let (_, repeated) = plan_update(_ => none, MilestoneTable(Apply), edited)
  assert_eq(repeated.plan, edited.plan)
  let (export, exported) = plan_update(
    _ => none,
    MilestoneTable(Export),
    edited,
  )
  drafts_test_execute(export)
  assert_eq(exported.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one CSV download")
  }
  assert_eq(products_text(download, "name"), "plan-milestones.csv")
  let csv = products_text(download, "text")
  assert_eq(csv, @plan_workbench.export_milestone_table(d))
  assert_eq(
    @plan_workbench.preview_milestone_table_updates(d, csv, false).changes,
    [],
  )
  assert_eq(plan_test_requests(), "[]")
  ignore(
    plan_test_file(
      "milestone-edits-before.json",
      ToJson::to_json(original.plan.draft.unwrap()).stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file(
      "milestone-edits-input.csv",
      original.plan.milestone_table.text,
    ),
  )
  ignore(plan_test_file("milestone-edits-preview.html", html))
  ignore(
    plan_test_file(
      "milestone-edits-after.json",
      ToJson::to_json(d).stringify(indent=2),
    ),
  )
  ignore(plan_test_file("milestone-edits-output.csv", csv))
  let (_, switched) = plan_update(_ => none, Choose("company-second"), edited)
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), switched)
  assert_eq(reloaded.plan.draft, Some(d))
  assert_eq(reloaded.plan.milestone_table, plan_milestone_table_initial())
  let (prepare, saving) = plan_update(_ => none, Prepare, reloaded)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare")
  }
  assert_eq(@json.parse(products_text(request, "body")), ToJson::to_json(d))
  ignore(
    plan_test_file(
      "milestone-edits-prepare-request.json",
      products_text(request, "body"),
    ),
  )
}

///|
test "milestone table cancel input edits format and scope discard preview" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, previewed) = plan_update(
    _ => none,
    MilestoneTable(Preview),
    milestone_edits_fixture(),
  )
  for
    action in [
      MilestoneTable(Close),
      MilestoneTable(Text("id,date\nmilestone-one,")),
      MilestoneTable(Format(true)),
      Edit("milestone", "milestone-one", "date", "2028-02-29"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, previewed)
    assert_eq(changed.plan.milestone_table.preview, None)
    let (_, after) = plan_update(_ => none, MilestoneTable(Apply), changed)
    assert_eq(after.plan, changed.plan)
  }
  let (_, actor) = plan_update(_ => none, MilestoneTable(Apply), {
    ..previewed,
    dispatch_task_actor_id: "other",
  })
  assert_eq(actor.plan.draft, None)
  assert_eq(actor.plan.milestone_table, plan_milestone_table_initial())
  let stale = {
    ..previewed,
    plan: {
      ..previewed.plan,
      draft: Some({ ..previewed.plan.draft.unwrap(), notes: "new context", }),
    },
  }
  let (_, refused) = plan_update(_ => none, MilestoneTable(Apply), stale)
  assert_eq(refused.plan.draft, stale.plan.draft)
  assert_eq(refused.plan.revision, stale.plan.revision)
  assert_eq(refused.plan.milestone_table.preview, None)
  let mismatched = {
    ..previewed,
    plan: { ..previewed.plan, selected: "company-second", },
  }
  let (_, ignored) = plan_update(_ => none, MilestoneTable(Export), mismatched)
  assert_eq(ignored.plan, mismatched.plan)
  assert_eq(plan_test_downloads(), "[]")
  assert_eq(plan_test_requests(), "[]")
}

///|
test "milestone table no-op failed and repeated changed exports preserve useful state" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = milestone_edits_fixture()
  let (_, bad_input) = plan_update(
    _ => none,
    MilestoneTable(Text("id,date\nmilestone-one,2027-02-29")),
    original,
  )
  let (_, failed) = plan_update(_ => none, MilestoneTable(Preview), bad_input)
  assert_eq(failed.plan.draft, original.plan.draft)
  assert_eq(failed.plan.prepared, original.plan.prepared)
  assert_eq(
    failed.plan.milestone_table.text,
    bad_input.plan.milestone_table.text,
  )
  assert_eq(failed.plan.milestone_table.preview, None)
  assert_true(failed.plan.milestone_table.note.contains("invalid date"))
  let (_, same_input) = plan_update(
    _ => none,
    MilestoneTable(
      Text(@plan_workbench.export_milestone_table(original.plan.draft.unwrap())),
    ),
    original,
  )
  let (_, previewed) = plan_update(
    _ => none,
    MilestoneTable(Preview),
    same_input,
  )
  assert_eq(previewed.plan.milestone_table.preview.unwrap().changes, [])
  let (_, no_op) = plan_update(_ => none, MilestoneTable(Apply), previewed)
  assert_eq(no_op.plan, previewed.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  let (first, _) = plan_update(_ => none, MilestoneTable(Export), original)
  drafts_test_execute(first)
  let (_, edited) = plan_update(
    _ => none,
    Edit("milestone", "milestone-one", "criteria", "Fresh edited criterion"),
    original,
  )
  let (second, _) = plan_update(_ => none, MilestoneTable(Export), edited)
  drafts_test_execute(second)
  guard @json.parse(plan_test_downloads()) is Array([before, after]) else {
    fail("two downloads")
  }
  assert_false(products_text(before, "text").contains("Fresh edited criterion"))
  assert_true(products_text(after, "text").contains("Fresh edited criterion"))
  assert_eq(
    products_text(after, "text"),
    @plan_workbench.export_milestone_table(edited.plan.draft.unwrap()),
  )
  assert_eq(plan_test_requests(), "[]")
}
