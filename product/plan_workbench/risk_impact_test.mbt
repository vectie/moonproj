///|
fn impact_draft() -> @plan_workbench.Draft {
  let task : @plan_workbench.Task = {
    id: "design",
    name: "Design",
    owner: "alex",
    milestone: "release",
    cost: "0.10",
    dependencies: [],
  }
  {
    ..table_draft(),
    tasks: [
      {
        ..task,
        id: "ship",
        name: "Ship",
        cost: "0.40",
        dependencies: ["build", "docs"],
      },
      { ..task, id: "unrelated", name: "Unrelated", cost: "999", },
      {
        ..task,
        id: "build",
        name: "Build",
        cost: "0.20",
        dependencies: ["design"],
      },
      task,
      {
        ..task,
        id: "docs",
        name: "Documentation",
        cost: "0.30",
        dependencies: ["design"],
      },
    ],
    risks: [
      {
        id: "supplier",
        summary: "Supplier API changes",
        severity: "high",
        owner: "alex",
        mitigation: "Pin API; test fallback",
        tasks: ["design", "build", "design"],
      },
    ],
  }
}

///|
test "risk impact unions convergent paths once and excludes ancestors and unrelated work" {
  let d = impact_draft()
  let before = d.to_json().stringify()
  let result = @plan_workbench.risk_impact(d, "supplier")
  assert_eq(result.direct_tasks, ["build", "design"])
  assert_eq(result.downstream_tasks, ["ship", "docs"])
  assert_eq(result.known_minor, Some(100L))
  assert_eq(result.invalid_tasks, 0)
  assert_eq(result.owners[0].task_ids, ["ship", "build", "design", "docs"])
  assert_eq(result.owners[0].known_minor, Some(100L))
  assert_eq(result.milestones[0].known_minor, Some(100L))
  let only_build = { ..d, risks: [{ ..d.risks[0], tasks: ["build"], }], }
  let scoped = @plan_workbench.risk_impact(only_build, "supplier")
  assert_eq(scoped.direct_tasks, ["build"])
  assert_eq(scoped.downstream_tasks, ["ship"])
  assert_eq(scoped.known_minor, Some(60L))
  let reverse = { ..d, tasks: d.tasks.rev(), }
  let reordered = @plan_workbench.risk_impact(reverse, "supplier")
  assert_eq(reordered.known_minor, result.known_minor)
  assert_eq(reordered.direct_tasks.length(), result.direct_tasks.length())
  let report = @plan_workbench.risk_impact_report(
    d, "supplier", "Synthetic release",
  )
  assert_true(report.contains("Local plan version: plan"))
  assert_true(report.contains("Project: Synthetic release [project]"))
  assert_true(
    report.contains("Revision timestamp (authored): 2026-10-08T00:00:00Z"),
  )
  assert_true(report.contains("Imported scope"))
  assert_true(report.contains("Pin API; test fallback"))
  assert_true(report.contains("Downstream-only tasks (2)"))
  assert_false(report.contains("Unrelated [unrelated]"))
  assert_true(report.contains("not expected loss"))
  assert_eq(d.to_json().stringify(), before)
}

///|
test "incomplete estimates absent links and unresolved assignments remain explicit" {
  let d = impact_draft()
  let incomplete = {
    ..d,
    tasks: d.tasks.map(t => {
      if t.id == "docs" {
        { ..t, cost: "", owner: "missing", milestone: "gone", }
      } else {
        t
      }
    }),
  }
  let impact = @plan_workbench.risk_impact(incomplete, "supplier")
  assert_eq(impact.known_minor, Some(70L))
  assert_eq(impact.invalid_tasks, 1)
  let report = @plan_workbench.risk_impact_report(
    incomplete, "supplier", "Release",
  )
  assert_true(report.contains("Cost coverage: incomplete"))
  assert_true(report.contains("Missing owner reference [missing]"))
  assert_true(report.contains("Missing/unassigned milestone [gone]"))
  assert_true(report.contains("minor units: Unavailable"))
  let unlinked = { ..d, risks: [{ ..d.risks[0], tasks: [], }], }
  assert_eq(@plan_workbench.risk_impact(unlinked, "supplier").known_minor, None)
  assert_true(
    @plan_workbench.risk_impact_report(unlinked, "supplier", "Release").contains(
      "unassessed, not zero",
    ),
  )
  let ambiguous = {
    ..d,
    owners: [d.owners[0], d.owners[0]],
    milestones: [d.milestones[0], d.milestones[0]],
  }
  let ambiguous_report = @plan_workbench.risk_impact_report(
    ambiguous, "supplier", "Release",
  )
  assert_true(ambiguous_report.contains("Ambiguous owner reference [alex]"))
  assert_true(ambiguous_report.contains("Ambiguous milestone [release]"))
}

///|
test "stale risk links and invalid dependency graphs reject without partial output" {
  let d = impact_draft()
  for
    bad in [
      { ..d, risks: [{ ..d.risks[0], tasks: ["gone"], }], },
      { ..d, risks: [d.risks[0], d.risks[0]], },
      { ..d, tasks: [..d.tasks, d.tasks[0]], },
      {
        ..d,
        tasks: d.tasks.map(t => {
          if t.id == "design" {
            { ..t, dependencies: ["ship"], }
          } else {
            t
          }
        }),
      },
      {
        ..d,
        tasks: d.tasks.map(t => {
          if t.id == "design" {
            { ..t, dependencies: ["missing"], }
          } else {
            t
          }
        }),
      },
    ] {
    assert_true(
      (try? @plan_workbench.risk_impact_report(bad, "supplier", "Release"))
      is Err(_),
    )
  }
  assert_true((try? @plan_workbench.risk_impact(d, "removed")) is Err(_))
  assert_true((try? @plan_workbench.risk_impact(d, "")) is Err(_))
  assert_eq(d, impact_draft())
}

///|
test "bounded large risk scope exposes cost overflow instead of wrapping" {
  let d = impact_draft()
  let tasks = Array::makei(100, i => {
    ..d.tasks[3],
    id: "t" + i.to_string(),
    cost: "999999999999999.99",
    dependencies: if i == 0 {
      []
    } else {
      ["t" + (i - 1).to_string()]
    },
  })
  let large = { ..d, tasks, risks: [{ ..d.risks[0], tasks: ["t0"], }], }
  let result = @plan_workbench.risk_impact(large, "supplier")
  assert_eq(result.downstream_tasks.length(), 99)
  assert_eq(result.known_minor, None)
  assert_eq(result.invalid_tasks, 0)
  assert_true(
    @plan_workbench.risk_impact_report(large, "supplier", "Release").contains(
      "unavailable (sum overflow)",
    ),
  )
  let too_many = { ..large, tasks: [..tasks, { ..tasks[0], id: "t100", }], }
  assert_true(
    (try? @plan_workbench.risk_impact(too_many, "supplier")) is Err(_),
  )
}
