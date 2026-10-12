///|
fn table_draft() -> @plan_workbench.Draft {
  {
    key: "plan",
    project_id: "project",
    prepared_at: "2026-10-08T00:00:00Z",
    notes: "Imported scope",
    currency: "USD",
    limit: "500",
    contingency: "0",
    owners: [{ id: "alex", name: "Alex", role: "lead", }],
    milestones: [
      {
        id: "release",
        name: "Release",
        owner: "alex",
        date: "2026-11-01",
        criteria: "Works",
        evidence: "Tests",
      },
    ],
    tasks: [],
    risks: [],
  }
}

///|
test "issue CSV imports quoted multiline titles and common columns into editable native request" {
  let (draft, ignored) = @plan_workbench.import_task_table(
    table_draft(),
    "\u{FEFF}Issue key,Summary,Assignee,cost,Depends on,Status\r\nAPP-1,\"Design, then \"\"build\"\"\n界面\",Alex,12.30,,Done\r\nAPP-2,Test,,0.20,APP-1,Open\r\n",
    false,
    "alex",
    "release",
  )
  assert_eq(draft.tasks.length(), 2)
  assert_eq(draft.tasks[0].name, "Design, then \"build\"\n界面")
  assert_eq(draft.tasks[0].owner, "alex")
  assert_eq(draft.tasks[1].dependencies, ["APP-1"])
  assert_eq(ignored, ["Status"])
  let request = @plan_workbench.request(
    draft,
    "alex",
    { "project_id": "project" },
    "local-export",
    "digest",
  )
  assert_eq(@plan_workbench.items(request, "tasks").length(), 2)
  assert_eq(
    @plan_workbench.field(
      @plan_workbench.items(request, "tasks")[0],
      "planned_cost_minor",
    ),
    ("1230" : Json),
  )
  let csv = @plan_workbench.export_task_table(draft)
  let (again, omitted) = @plan_workbench.import_task_table(
    table_draft(),
    csv,
    false,
    "",
    "",
  )
  assert_eq(again, draft)
  assert_eq(omitted, [])
}

///|
test "TSV appends and references existing tasks without changing earlier rows" {
  let (first, _) = @plan_workbench.import_task_table(
    table_draft(),
    "id\ttitle\nT1\tFirst",
    true,
    "alex",
    "release",
  )
  let (second, _) = @plan_workbench.import_task_table(
    first, "Identifier\tTitle\tAssignee\tMilestone\tDependencies\nT2\tSecond\tAlex\tRelease\tT1",
    true, "", "",
  )
  assert_eq(first.tasks.length(), 1)
  assert_eq(second.tasks[0], first.tasks[0])
  assert_eq(second.tasks[1].dependencies, ["T1"])
}

///|
test "invalid tables fail atomically with actionable input errors" {
  let draft = table_draft()
  for
    source in [
      "id,title\nT1,Valid\nT1,Duplicate", "id,title\n,Missing ID", "id,title\nT1,",
      "title\nNo ID column", "id,title,Summary\nT1,A,B", "id,title\nT1,Too,many",
      "id,title\nT1,\"unfinished", "id,title\nT1,\"closed\"junk", "id,title,owner\nT1,Title,Nobody",
      "id,title,milestone\nT1,Title,Missing", "id,title,cost\nT1,Title,1.001", "id,title,dependencies\nT1,Title,T2\nT2,Other,",
      "id,title,dependencies\nT1,Title,T1",
    ] {
    try
      @plan_workbench.import_task_table(draft, source, false, "alex", "release")
    catch {
      @plan_workbench.Invalid(message) => assert_false(message.is_empty())
    } noraise {
      _ => fail("Should reject: " + source)
    }
    assert_eq(draft.tasks.length(), 0)
  }
}

///|
test "ambiguous owner names require an exact ID" {
  let draft = table_draft()
  let draft = {
    ..draft,
    owners: [..draft.owners, { id: "alex2", name: "Alex", role: "reviewer", }],
  }
  try
    @plan_workbench.import_task_table(
      draft, "id,title,owner\nT1,Title,Alex", false, "alex", "release",
    )
  catch {
    @plan_workbench.Invalid(_) => ()
  } noraise {
    _ => fail("Ambiguous name must reject")
  }
  let (accepted, _) = @plan_workbench.import_task_table(
    draft, "id,title,owner\nT1,Title,alex2", false, "alex", "release",
  )
  assert_eq(accepted.tasks[0].owner, "alex2")
}
