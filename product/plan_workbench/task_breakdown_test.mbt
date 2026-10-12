///|
fn breakdown_steps() -> Array[@plan_workbench.TaskStep] {
  [
    { id: "review-1", name: "Read <requirements>", cost: "1.20", },
    { id: "review-2", name: "核对, \"结果\"\nSecond line", cost: "2", },
    { id: "review-3", name: "Finalize", cost: "1.0", },
  ]
}

///|
test "breakdown inserts sequence reconnects followers expands risks and preserves exact budget" {
  let d = update_table_draft()
  let steps = breakdown_steps()
  let after = @plan_workbench.break_down_task(d, "T2", steps)
  assert_eq(after.tasks.map(t => t.id), [
    "T1", "review-1", "review-2", "review-3", "T3",
  ])
  assert_eq(after.tasks[0], d.tasks[0])
  assert_eq(after.tasks[1].dependencies, ["T1"])
  assert_eq(after.tasks[2].dependencies, ["review-1"])
  assert_eq(after.tasks[3].dependencies, ["review-2"])
  assert_eq(after.tasks[4], { ..d.tasks[2], dependencies: ["review-3"], })
  for i, step in steps {
    let task = after.tasks[i + 1]
    assert_eq(task.name, step.name)
    assert_eq(task.cost, step.cost)
    assert_eq(task.owner, d.tasks[1].owner)
    assert_eq(task.milestone, d.tasks[1].milestone)
  }
  assert_eq(after.risks, [
    { ..d.risks[0], tasks: ["review-1", "review-2", "review-3"], },
  ])
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
    "synthetic-input",
    "digest",
  )
  assert_eq(@plan_workbench.items(wire, "tasks").length(), 5)
  let m = @plan_workbench.items(wire, "milestones")[0]
  assert_eq(
    @plan_workbench.field(m, "task_ids"),
    ["T1", "review-1", "review-2", "review-3", "T3"].to_json(),
  )
}

///|
test "breakdown handles fanout independent tasks and multiple risk references without alias mutation" {
  let original = update_table_draft()
  let d = {
    ..original,
    tasks: [
      ..original.tasks,
      { ..original.tasks[2], id: "T4", dependencies: ["T1", "T2"], },
      { ..original.tasks[0], id: "T5", dependencies: [], },
    ],
    risks: [
      { ..original.risks[0], tasks: ["T1", "T2", "T5"], },
      { ..original.risks[0], id: "unrelated-risk", tasks: ["T5"], },
    ],
  }
  let after = @plan_workbench.break_down_task(d, "T2", breakdown_steps())
  assert_eq(after.tasks[5].dependencies, ["T1", "review-3"])
  assert_eq(after.tasks[6], d.tasks[4])
  assert_eq(after.risks[0].tasks, [
    "T1", "review-1", "review-2", "review-3", "T5",
  ])
  assert_eq(after.risks[1], d.risks[1])
  after.tasks[0].dependencies.push("new")
  after.tasks[1].dependencies.push("new")
  after.risks[1].tasks.push("new")
  assert_eq(d.tasks[0].dependencies, [])
  assert_eq(d.tasks[1].dependencies, ["T1"])
  assert_eq(d.risks[1].tasks, ["T5"])
}

///|
test "breakdown rejects ambiguous or reused identities including dangling references" {
  let d = update_table_draft()
  let steps = breakdown_steps()
  assert_true(
    (try? @plan_workbench.break_down_task(d, "missing", steps)) is Err(_),
  )
  assert_true(
    (try? @plan_workbench.break_down_task(
      { ..d, tasks: [..d.tasks, d.tasks[1]], },
      "T2",
      steps,
    ))
    is Err(_),
  )
  assert_true(
    (try? @plan_workbench.break_down_task(
      { ..d, tasks: [..d.tasks, d.tasks[0]], },
      "T2",
      steps,
    ))
    is Err(_),
  )
  for id in ["", "  ", "T1", "T2", "T3", "review-2"] {
    assert_true(
      (try? @plan_workbench.break_down_task(d, "T2", [
        { ..steps[0], id, },
        steps[1],
        steps[2],
      ]))
      is Err(_),
    )
  }
  let dangling = {
    ..d,
    tasks: [
      d.tasks[0],
      d.tasks[1],
      { ..d.tasks[2], dependencies: ["review-1"], },
    ],
  }
  assert_true(
    (try? @plan_workbench.break_down_task(dangling, "T2", steps)) is Err(_),
  )
  let risk_ref = { ..d, risks: [{ ..d.risks[0], tasks: ["review-1"], }], }
  assert_true(
    (try? @plan_workbench.break_down_task(risk_ref, "T2", steps)) is Err(_),
  )
  let self_link = {
    ..d,
    tasks: [d.tasks[0], { ..d.tasks[1], dependencies: ["T2"], }, d.tasks[2]],
  }
  assert_true(
    (try? @plan_workbench.break_down_task(self_link, "T2", steps)) is Err(_),
  )
  assert_eq(d, update_table_draft())
}

///|
test "breakdown rejects incomplete names and invalid unequal costs with integer-cent precision" {
  let d = update_table_draft()
  let steps = breakdown_steps()
  for name in ["", " \n "] {
    assert_true(
      (try? @plan_workbench.break_down_task(d, "T2", [
        { ..steps[0], name, },
        steps[1],
        steps[2],
      ]))
      is Err(_),
    )
  }
  for cost in ["-1", "1.201", "nan", "", "1.19", "1.21", "1000000000000000"] {
    assert_true(
      (try? @plan_workbench.break_down_task(d, "T2", [
        { ..steps[0], cost, },
        steps[1],
        steps[2],
      ]))
      is Err(_),
    )
  }
  let zero = {
    ..d,
    tasks: [d.tasks[0], { ..d.tasks[1], cost: "0", }, d.tasks[2]],
  }
  let after = @plan_workbench.break_down_task(zero, "T2", [
    { ..steps[0], cost: "0.00", },
    { ..steps[1], cost: "0", },
  ])
  assert_eq(after.tasks[1].cost, "0.00")
  let cents = {
    ..d,
    tasks: [d.tasks[0], { ..d.tasks[1], cost: "0.30", }, d.tasks[2]],
  }
  assert_eq(
    @plan_workbench.break_down_task(cents, "T2", [
      { ..steps[0], cost: "0.10", },
      { ..steps[1], cost: "0.20", },
    ]).tasks.length(),
    4,
  )
  let bad_original = {
    ..d,
    tasks: [d.tasks[0], { ..d.tasks[1], cost: "unknown", }, d.tasks[2]],
  }
  assert_true(
    (try? @plan_workbench.break_down_task(bad_original, "T2", steps)) is Err(_),
  )
}

///|
test "breakdown enforces step and resulting task bounds and preserves later validation gaps" {
  let d = update_table_draft()
  let steps = breakdown_steps()
  for size in [0, 1, 11] {
    let invalid : Array[@plan_workbench.TaskStep] = Array::makei(size, i => {
      id: "new-" + i.to_string(),
      name: "Step",
      cost: "0",
    })
    assert_true(
      (try? @plan_workbench.break_down_task(d, "T2", invalid)) is Err(_),
    )
  }
  let tasks = Array::makei(98, i => {
    ..d.tasks[0],
    id: "T" + i.to_string(),
    cost: "0",
    dependencies: [],
  })
  let large = { ..d, tasks, risks: [], }
  let two = [{ ..steps[0], cost: "0", }, { ..steps[1], cost: "0", }]
  assert_eq(
    @plan_workbench.break_down_task(large, "T0", two).tasks.length(),
    99,
  )
  assert_eq(
    @plan_workbench.break_down_task(
      large,
      "T0",
      [..two, { ..steps[2], cost: "0", }],
    ).tasks.length(),
    100,
  )
  assert_true(
    (try? @plan_workbench.break_down_task(
      { ..large, tasks: [..tasks, { ..tasks[0], id: "overflow", }], },
      "T0",
      [..two, { ..steps[2], cost: "0", }],
    ))
    is Err(_),
  )
  let incomplete = {
    ..d,
    tasks: [
      d.tasks[0],
      { ..d.tasks[1], owner: "missing-owner", dependencies: ["missing-task"], },
      d.tasks[2],
    ],
  }
  let after = @plan_workbench.break_down_task(incomplete, "T2", steps)
  assert_eq(after.tasks[1].owner, "missing-owner")
  assert_eq(after.tasks[1].dependencies, ["missing-task"])
}

///|
test "breakdown supports all ten steps and bounded high amounts without overflow" {
  let d = update_table_draft()
  let high = {
    ..d,
    tasks: [
      d.tasks[0],
      { ..d.tasks[1], cost: "999999999999999.99", },
      d.tasks[2],
    ],
  }
  let steps : Array[@plan_workbench.TaskStep] = Array::makei(10, i => {
    id: "step-" + i.to_string(),
    name: "Step " + i.to_string(),
    cost: if i == 0 {
      "999999999999999.99"
    } else {
      "0"
    },
  })
  let after = @plan_workbench.break_down_task(high, "T2", steps)
  assert_eq(after.tasks.length(), 12)
  assert_eq(after.tasks[11].dependencies, ["step-9"])
  assert_eq(after.risks[0].tasks.length(), 10)
  assert_true(
    (try? @plan_workbench.break_down_task(
      high,
      "T2",
      steps.map(step => { ..step, cost: "999999999999999.99", }),
    ))
    is Err(_),
  )
}
