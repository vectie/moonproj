///|
fn budget_draft() -> @plan_workbench.Draft {
  let d = table_draft()
  {
    ..d,
    limit: "20",
    contingency: "1.50",
    tasks: [
      {
        id: "a",
        name: "Design",
        owner: "alex",
        milestone: "release",
        cost: "001.20",
        dependencies: [],
      },
      {
        id: "b",
        name: "Review",
        owner: "alex",
        milestone: "",
        cost: "2.30",
        dependencies: [],
      },
      {
        id: "c",
        name: "Input",
        owner: "missing",
        milestone: "release",
        cost: "0.10",
        dependencies: [],
      },
    ],
  }
}

///|
test "budget allocation partitions exact amounts and includes unassigned and missing references" {
  let d = budget_draft()
  let before = d.to_json().stringify()
  let b = @plan_workbench.budget_breakdown(d)
  assert_eq(b.known_minor, Some(360L))
  assert_eq(b.remaining_minor, Some(1490L))
  assert_eq(b.owners.length(), 2)
  assert_eq(b.owners[0].known_minor, Some(350L))
  assert_eq(b.owners[1].label, "Missing reference")
  assert_eq(b.milestones[0].known_minor, Some(130L))
  assert_eq(b.milestones[1].label, "Unassigned")
  assert_eq(b.milestones[1].task_ids, ["b"])
  assert_eq(d.to_json().stringify(), before)
  let report = @plan_workbench.budget_report(d, "Synthetic launch")
  assert_true(report.contains("001.20 => 120"))
  assert_true(report.contains("Remaining after tasks and contingency: 1490"))
  assert_eq(report, @plan_workbench.budget_report(d, "Synthetic launch"))
}

///|
test "unfinished and invalid cost rows remain visible and block a complete headroom claim" {
  let base = budget_draft()
  for amount in ["", "-1", "1.001", "abc", "1,000"] {
    let d = {
      ..base,
      tasks: [base.tasks[0], { ..base.tasks[1], cost: amount, }],
    }
    let b = @plan_workbench.budget_breakdown(d)
    assert_eq(b.known_minor, Some(120L))
    assert_eq(b.invalid_tasks, 1)
    assert_eq(b.remaining_minor, None)
    assert_eq(b.owners[0].invalid_tasks, 1)
    assert_true(
      @plan_workbench.budget_report(d, "P").contains(amount + " => Unavailable"),
    )
  }
  assert_eq(
    @plan_workbench.budget_breakdown({ ..base, limit: "", }).remaining_minor,
    None,
  )
  assert_eq(
    @plan_workbench.budget_breakdown({ ..base, contingency: "bad", }).remaining_minor,
    None,
  )
  assert_eq(
    @plan_workbench.budget_breakdown({ ..base, limit: "4", }).remaining_minor,
    Some(-110L),
  )
}

///|
test "cost overflow is unavailable in total and affected bucket with no wraparound" {
  let base = budget_draft()
  let tasks = Array::makei(100, i => {
    ..base.tasks[0],
    id: i.to_string(),
    cost: "999999999999999.99",
  })
  let b = @plan_workbench.budget_breakdown({ ..base, tasks, })
  assert_eq(b.known_minor, None)
  assert_eq(b.owners[0].known_minor, None)
  assert_eq(b.milestones[0].known_minor, None)
  assert_eq(b.invalid_tasks, 0)
  assert_eq(b.remaining_minor, None)
}

///|
test "empty plans and ambiguous references retain transparent counts" {
  let base = budget_draft()
  let empty = @plan_workbench.budget_breakdown({ ..base, tasks: [], })
  assert_eq(empty.known_minor, Some(0L))
  assert_eq(empty.remaining_minor, Some(1850L))
  assert_eq(empty.owners, [])
  let ambiguous = @plan_workbench.budget_breakdown({
    ..base,
    owners: [..base.owners, ..base.owners],
  })
  assert_eq(ambiguous.owners[0].label, "Ambiguous reference")
  assert_eq(ambiguous.owners[0].known_minor, Some(350L))
}

///|
test "minor units stay exact beyond JavaScript safe integers and current edits recalculate" {
  let base = budget_draft()
  let d = {
    ..base,
    limit: "999999999999999.99",
    contingency: "0.01",
    tasks: [
      { ..base.tasks[0], cost: "90071992547409.93", },
      { ..base.tasks[1], cost: "0.02", },
    ],
  }
  let b = @plan_workbench.budget_breakdown(d)
  assert_eq(b.known_minor, Some(9007199254740995L))
  assert_eq(b.remaining_minor, Some(90992800745259003L))
  assert_true(
    @plan_workbench.budget_report(d, "P").contains(
      "Known task subtotal: 9007199254740995",
    ),
  )
  let edited = { ..d, tasks: [{ ..d.tasks[0], cost: "0.01", }, d.tasks[1]], }
  assert_eq(@plan_workbench.budget_breakdown(edited).known_minor, Some(3L))
  assert_eq(@plan_workbench.budget_breakdown(d), b)
}
