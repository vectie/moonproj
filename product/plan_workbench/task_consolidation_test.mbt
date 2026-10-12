///|
test "consolidation keeps chosen identity cost and external references through export and wire projection" {
  let d = update_table_draft()
  let after = @plan_workbench.consolidate_tasks(
    d,
    ["T2", "T1"],
    "T2",
    "Design and review 界面",
  )
  assert_eq(after.tasks.map(t => t.id), ["T2", "T3"])
  assert_eq(after.tasks[0], {
    ..d.tasks[1],
    name: "Design and review 界面",
    cost: "16.50",
    dependencies: [],
  })
  assert_eq(after.tasks[1], d.tasks[2])
  assert_eq(after.risks, d.risks)
  assert_eq({ ..after, tasks: d.tasks, risks: d.risks, }, d)
  assert_eq(
    @plan_workbench.budget_breakdown(after).known_minor,
    @plan_workbench.budget_breakdown(d).known_minor,
  )
  assert_eq(d, update_table_draft())
  assert_eq(
    @plan_workbench.preview_task_table_updates(
      after,
      @plan_workbench.export_task_table(after),
      false,
    ).draft,
    after,
  )
  let wire = @plan_workbench.request(
    after,
    "alex",
    {},
    "synthetic-source",
    "digest",
  )
  assert_eq(@plan_workbench.items(wire, "tasks").length(), 2)
  assert_eq(
    @plan_workbench.field(
      @plan_workbench.items(wire, "milestones")[0],
      "task_ids",
    ),
    ["T2", "T3"].to_json(),
  )
  assert_eq(
    @plan_workbench.field(
      @plan_workbench.items(wire, "tasks")[0],
      "planned_cost_minor",
    ),
    1650L.to_json(),
  )
}

///|
test "consolidation unions prerequisites rewrites fanout and risks and stably reorders without alias mutation" {
  let base = update_table_draft()
  let proto = base.tasks[0]
  let d = {
    ..base,
    tasks: [
      { ..proto, id: "A", dependencies: [], },
      { ..proto, id: "B", dependencies: ["A", "C"], },
      { ..proto, id: "X", dependencies: [], },
      { ..proto, id: "C", dependencies: ["X", "X"], },
      { ..proto, id: "D", dependencies: ["C", "X", "A"], },
    ],
    risks: [
      { ..base.risks[0], tasks: ["C", "A", "D"], },
      {
        ..base.risks[0],
        id: "unchanged",
        tasks: ["missing-risk-reference", "X"],
      },
    ],
  }
  let after = @plan_workbench.consolidate_tasks(
    d,
    ["C", "A"],
    "C",
    "  One scope\n界面  ",
  )
  assert_eq(after.tasks.map(t => t.id), ["X", "C", "B", "D"])
  assert_eq(after.tasks[1].name, "  One scope\n界面  ")
  assert_eq(after.tasks[1].dependencies, ["X"])
  assert_eq(after.tasks[1].cost, "24.60")
  assert_eq(after.tasks[2].dependencies, ["C"])
  assert_eq(after.tasks[3].dependencies, ["C", "X"])
  assert_eq(after.risks[0].tasks, ["C", "D"])
  assert_eq(after.risks[1], d.risks[1])
  assert_eq(@plan_workbench.dependency_plan(after, "").issues, [])
  after.tasks[0].dependencies.push("mutated")
  after.tasks[1].dependencies.push("mutated")
  after.risks[1].tasks.push("mutated")
  assert_eq(d.tasks[2].dependencies, [])
  assert_eq(d.tasks[3].dependencies, ["X", "X"])
  assert_eq(d.risks[1].tasks, ["missing-risk-reference", "X"])
}

///|
test "consolidation rejects path contraction cycles missing dependencies and ambiguous task identities" {
  let d = update_table_draft()
  try
    @plan_workbench.consolidate_tasks(
      d,
      ["T1", "T3"],
      "T1",
      "Wrong contraction",
    )
  catch {
    @plan_workbench.Invalid(message) =>
      assert_true(message.contains("unselected task"))
  } noraise {
    _ => fail("A to B to C cannot contract A and C")
  }
  for
    tasks in [
      [d.tasks[0], { ..d.tasks[1], dependencies: ["missing"], }, d.tasks[2]],
      [{ ..d.tasks[0], dependencies: ["T3"], }, d.tasks[1], d.tasks[2]],
      [d.tasks[0], d.tasks[1], d.tasks[2], d.tasks[0]],
      [d.tasks[0], d.tasks[1], { ..d.tasks[2], id: "", }],
    ] {
    assert_true(
      (try? @plan_workbench.consolidate_tasks(
        { ..d, tasks, },
        ["T1", "T2"],
        "T1",
        "Combined",
      ))
      is Err(_),
    )
  }
  assert_eq(d, update_table_draft())
}

///|
test "consolidation requires distinct same-assignment selection and a nonempty combined title" {
  let d = update_table_draft()
  for selected in [[], ["T1"], ["T1", "T1"], ["T1", "missing"]] {
    assert_true(
      (try? @plan_workbench.consolidate_tasks(d, selected, "T1", "Combined"))
      is Err(_),
    )
  }
  for retained in ["", "T3", "missing"] {
    assert_true(
      (try? @plan_workbench.consolidate_tasks(
        d,
        ["T1", "T2"],
        retained,
        "Combined",
      ))
      is Err(_),
    )
  }
  for name in ["", " \n "] {
    assert_true(
      (try? @plan_workbench.consolidate_tasks(d, ["T1", "T2"], "T1", name))
      is Err(_),
    )
  }
  for
    task in [
      { ..d.tasks[1], owner: "sam", },
      { ..d.tasks[1], milestone: "later", },
    ] {
    assert_true(
      (try? @plan_workbench.consolidate_tasks(
        { ..d, tasks: [d.tasks[0], task, d.tasks[2]], },
        ["T1", "T2"],
        "T1",
        "Combined",
      ))
      is Err(_),
    )
  }
}

///|
test "consolidation adds exact cents rejects unsupported cost and supports the full bounded plan" {
  let d = update_table_draft()
  let cents = {
    ..d,
    tasks: [
      { ..d.tasks[0], cost: "0.1", },
      { ..d.tasks[1], cost: "0.20", },
      d.tasks[2],
    ],
  }
  assert_eq(
    @plan_workbench.consolidate_tasks(cents, ["T1", "T2"], "T1", "Combined").tasks[0].cost,
    "0.30",
  )
  for
    cost in ["", "nan", "-1", "0.001", "1000000000000000", "999999999999999.99"] {
    let bad = { ..d, tasks: [{ ..d.tasks[0], cost, }, d.tasks[1], d.tasks[2]], }
    assert_true(
      (try? @plan_workbench.consolidate_tasks(
        bad,
        ["T1", "T2"],
        "T1",
        "Combined",
      ))
      is Err(_),
    )
  }
  let large = {
    ..d,
    tasks: Array::makei(100, i => {
      ..d.tasks[0],
      id: "item-" + i.to_string(),
      cost: "0",
    }),
  }
  let selected = large.tasks.map(t => t.id)
  let one = @plan_workbench.consolidate_tasks(
    large, selected, "item-99", "All scope",
  )
  assert_eq(one.tasks.length(), 1)
  assert_eq(one.tasks[0].cost, "0.00")
  assert_eq(one.tasks[0].id, "item-99")
  assert_true(
    (try? @plan_workbench.consolidate_tasks(
      { ..large, tasks: [..large.tasks, { ..d.tasks[0], id: "extra", }], },
      selected,
      "item-99",
      "All",
    ))
    is Err(_),
  )
}
