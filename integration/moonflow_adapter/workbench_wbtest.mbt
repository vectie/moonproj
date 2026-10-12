///|
fn workbench_test_draft() -> @plan_workbench.Draft {
  {
    key: "plan-fixture",
    project_id: "company-actual",
    prepared_at: "2026-10-07T04:00:00Z",
    notes: "Synthetic test planning input; not company evidence",
    currency: "CNY",
    limit: "1000.00",
    contingency: "100.00",
    owners: [{ id: "owner-test", name: "Test owner", role: "Plan preparer", }],
    tasks: [
      {
        id: "task-design",
        name: "Design",
        owner: "owner-test",
        milestone: "milestone-one",
        cost: "200.25",
        dependencies: [],
      },
      {
        id: "task-review",
        name: "Review",
        owner: "owner-test",
        milestone: "milestone-one",
        cost: "300.00",
        dependencies: ["task-design"],
      },
    ],
    milestones: [
      {
        id: "milestone-one",
        name: "Reviewable result",
        owner: "owner-test",
        date: "2026-10-31",
        criteria: "Traceable requirements\nReviewable deliverable",
        evidence: "Named reviewer receipt",
      },
    ],
    risks: [
      {
        id: "risk-one",
        summary: "Scope may change",
        severity: "medium",
        owner: "owner-test",
        mitigation: "Reprepare an immutable new version",
        tasks: ["task-design"],
      },
    ],
  }
}

///|
fn workbench_test_project() -> Json {
  {
    "project_id": "company-actual",
    "project_code": "TEST",
    "project_name": "Synthetic test project",
    "bu_guid": "unit-test",
  }
}

///|
async test "workbench native prepare immutable replay reopen and actor project isolation" {
  let root = @fs.tmpdir(prefix="moonproj-plan-workbench")
  let draft = workbench_test_draft()
  let prepared = prepare_workbench(
    root,
    "owner-test",
    workbench_test_project(),
    draft.to_json(),
  )
  assert_eq(
    prepare_workbench(
      root,
      "owner-test",
      workbench_test_project(),
      draft.to_json(),
    ),
    prepared,
  )
  assert_eq(
    read_workbench(root, "owner-test", "company-actual", draft.key),
    prepared,
  )
  assert_eq(
    @plan_workbench.items(
      list_workbench(root, "owner-test", "company-actual"),
      "items",
    ).length(),
    1,
  )
  assert_eq(
    @plan_workbench.items(
      list_workbench(root, "other", "company-actual"),
      "items",
    ).length(),
    0,
  )
  assert_eq(
    @plan_workbench.items(list_workbench(root, "owner-test", "other"), "items").length(),
    0,
  )
  let artifact = @project_plan.decode_artifact(
    @plan_workbench.field(prepared, "artifact"),
  )
  assert_eq(artifact.budget.planned_total_minor, 50025L)
  assert_eq(artifact.budget.unallocated_minor, 39975L)
  assert_false(artifact.workflow.accepted)
  assert_eq(artifact.tasks[1].dependencies, ["task-design"])
  for i in 0..<101 {
    let history = { ..draft, key: "history-" + i.to_string(), }
    ignore(
      prepare_workbench(
        root,
        "owner-test",
        workbench_test_project(),
        history.to_json(),
      ),
    )
  }
  let history = list_workbench(root, "owner-test", draft.project_id)
  let newest = @plan_workbench.items(history, "items")
  assert_eq(newest.length(), 100)
  assert_eq(@plan_workbench.text(newest[0], "key"), "history-100")
  assert_eq(@plan_workbench.field(history, "total_count"), Json::number(102))
  assert_eq(@plan_workbench.field(history, "truncated"), Json::boolean(true))
  let changed = { ..draft, notes: "changed", }
  try
    prepare_workbench(
      root,
      "owner-test",
      workbench_test_project(),
      changed.to_json(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("same identity cannot overwrite")
  }
  assert_eq(
    read_workbench(root, "owner-test", "company-actual", draft.key),
    prepared,
  )
}

///|
async test "workbench invalid rows references dependencies duplicates dates criteria and budget never persist" {
  let root = @fs.tmpdir(prefix="moonproj-plan-invalid")
  let d = workbench_test_draft()
  let task = d.tasks[0]
  let milestone = d.milestones[0]
  let variants = [
    { ..d, owners: [..d.owners, d.owners[0]], },
    { ..d, tasks: [task, task], },
    { ..d, tasks: [{ ..task, owner: "missing", }], },
    { ..d, tasks: [{ ..task, milestone: "missing", }], },
    { ..d, tasks: [{ ..task, dependencies: ["missing"], }], },
    { ..d, tasks: [{ ..task, dependencies: [task.id], }], },
    { ..d, tasks: [d.tasks[1], task], },
    { ..d, tasks: [task, { ..d.tasks[1], dependencies: [task.id, task.id], }], },
    { ..d, milestones: [{ ..milestone, date: "2026-02-30", }], },
    { ..d, milestones: [{ ..milestone, criteria: "same\nsame", }], },
    { ..d, milestones: [{ ..milestone, evidence: "", }], },
    { ..d, limit: "1.00", },
    { ..d, contingency: "900.00", },
    { ..d, limit: "-1", },
    { ..d, limit: "1.001", },
    { ..d, tasks: [{ ..task, cost: "NaN", }], },
    { ..d, risks: [{ ..d.risks[0], tasks: ["missing"], }], },
    { ..d, notes: "", },
    { ..d, currency: "123", },
    { ..d, currency: "!!!", },
    { ..d, currency: "C1Y", },
    { ..d, currency: "   ", },
  ]
  for variant in variants {
    try
      prepare_workbench(
        root,
        "owner-test",
        workbench_test_project(),
        variant.to_json(),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid input prepared")
    }
  }
  assert_false(@fs.exists(root + "/.moonsuite"))
}

///|
async test "workbench detects changed source and artifact and missing workspace" {
  let root = @fs.tmpdir(prefix="moonproj-plan-integrity")
  let d = workbench_test_draft()
  let result = prepare_workbench(
    root,
    "owner-test",
    workbench_test_project(),
    d.to_json(),
  )
  let base = root +
    "/" +
    workbench_base("owner-test", d.project_id) +
    "/" +
    d.key
  let original = @fs.read_file(base + "/source.json").text()
  @fs.write_file(base + "/source.json", "{}")
  try read_workbench(root, "owner-test", d.project_id, d.key) catch {
    _ => ()
  } noraise {
    _ => fail("changed source accepted")
  }
  @fs.write_file(base + "/source.json", original)
  assert_eq(read_workbench(root, "owner-test", d.project_id, d.key), result)
  @fs.write_file(base + "/plan.json", "{}")
  try read_workbench(root, "owner-test", d.project_id, d.key) catch {
    _ => ()
  } noraise {
    _ => fail("changed plan accepted")
  }
  try
    prepare_workbench(
      root + "/missing",
      "owner-test",
      workbench_test_project(),
      d.to_json(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("missing workspace accepted")
  }
}
