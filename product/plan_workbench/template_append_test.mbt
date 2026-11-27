///|
fn phase_append_target() -> @plan_workbench.Draft {
  let base = table_draft()
  {
    ..base,
    limit: "2000.00",
    tasks: [
      {
        id: "existing",
        name: "Existing discovery",
        owner: "alex",
        milestone: "release",
        cost: "40.00",
        dependencies: [],
      },
    ],
    risks: [
      {
        id: "existing-risk",
        summary: "Existing source risk",
        severity: "low",
        owner: "alex",
        mitigation: "Keep source",
        tasks: ["existing"],
      },
    ],
  }
}

///|
test "phase append preserves destination and composes complete remapped rows" {
  let t = reusable_template()
  let target = phase_append_target()
  let old = ToJson::to_json(target).stringify()
  let source = ToJson::to_json(t).stringify()
  let combined = @plan_workbench.append_template(
    t, target, "alex", "reviewer", "phase",
  )
  assert_eq(ToJson::to_json(target).stringify(), old)
  assert_eq(ToJson::to_json(t).stringify(), source)
  assert_eq(combined.key, target.key)
  assert_eq(combined.project_id, target.project_id)
  assert_eq(combined.prepared_at, target.prepared_at)
  assert_eq(combined.notes, target.notes)
  assert_eq(combined.currency, target.currency)
  assert_eq(combined.limit, target.limit)
  assert_eq(combined.contingency, target.contingency)
  assert_eq(combined.owners[0], target.owners[0])
  assert_eq(combined.tasks[0], target.tasks[0])
  assert_eq(combined.milestones[0], target.milestones[0])
  assert_eq(combined.risks[0], target.risks[0])
  assert_eq(combined.owners.length(), 2)
  assert_eq(combined.tasks.length(), 5)
  assert_eq(combined.milestones.length(), 3)
  assert_eq(combined.risks.length(), 2)
  assert_eq(combined.owners[1].name, "Alex")
  assert_eq(combined.owners[1].id, "phase-owner-1")
  assert_eq(combined.tasks[3].owner, "alex")
  assert_eq(combined.tasks[3].dependencies, ["phase-task-1", "phase-task-2"])
  assert_eq(combined.tasks[4].milestone, "phase-milestone-2")
  assert_eq(combined.milestones[2].owner, "alex")
  assert_eq(combined.milestones[1].criteria, t.milestones[0].criteria)
  assert_eq(combined.milestones[2].evidence, t.milestones[1].evidence)
  assert_eq(combined.risks[1].tasks, ["phase-task-1", "phase-task-2"])
  assert_eq(combined.tasks[1].cost, "0125.40")
  let request = @plan_workbench.request(
    combined,
    "alex",
    { "project_id": "project" },
    "synthetic-phase",
    "digest",
  )
  assert_eq(@plan_workbench.items(request, "tasks").length(), 5)
  assert_eq(
    @plan_workbench.field(
      @plan_workbench.items(request, "tasks")[1],
      "planned_cost_minor",
    ),
    ("12540" : Json),
  )
  let portable = @plan_workbench.read_template(
    @plan_workbench.export_template(combined),
  )
  assert_eq(portable.tasks.length(), 5)
  assert_eq(portable.notes, target.notes)
  assert_eq(portable.tasks[3].dependencies, ["task-2", "task-3"])
  // Returned arrays can be edited without changing either authored input.
  combined.tasks[3].dependencies.push("unrelated")
  combined.risks[0].tasks.push("unrelated")
  assert_eq(ToJson::to_json(target).stringify(), old)
  assert_eq(ToJson::to_json(t).stringify(), source)
}

///|
test "phase can be repeated with distinct identities and no automatic joins" {
  let t = reusable_template()
  let first = @plan_workbench.append_template(
    t,
    phase_append_target(),
    "alex",
    "lead",
    "one",
  )
  let second = @plan_workbench.append_template(t, first, "alex", "lead", "two")
  assert_eq(second.tasks.length(), 9)
  assert_eq(second.tasks[1].dependencies, [])
  assert_eq(second.tasks[5].dependencies, [])
  assert_eq(second.tasks[7].dependencies, ["two-task-1", "two-task-2"])
  assert_eq(second.owners.length(), 3)
  assert_eq(second.owners[0].role, "lead")
  assert_true(second.owners[1].id != second.owners[2].id)
  assert_eq(second.tasks[3], first.tasks[3])
}

///|
test "phase append rejects currency identity mapping and combined limit mistakes" {
  let t = reusable_template()
  let target = phase_append_target()
  for bad in [{ ..t, currency: "EUR", }, { ..t, tasks: [], }] {
    let result = Ok(
      @plan_workbench.append_template(bad, target, "alex", "lead", "fresh"),
    ) catch {
      e => Err(e)
    }
    assert_true(result is Err(_))
  }
  assert_true(
    (Ok(@plan_workbench.append_template(t, target, "alex", "unknown", "fresh")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@plan_workbench.append_template(t, target, "missing", "lead", "fresh")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let imported = @plan_workbench.append_template(
    t, target, "alex", "lead", "fresh",
  )
  assert_true(
    (Ok(@plan_workbench.append_template(t, imported, "alex", "lead", "fresh")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let many = {
    ..target,
    tasks: Array::makei(97, i => {
      ..target.tasks[0],
      id: "existing-" + i.to_string(),
    }),
    risks: [],
  }
  assert_true(
    (Ok(@plan_workbench.append_template(t, many, "alex", "lead", "fresh")) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "phase append retains incomplete authored dates costs and blank assignments" {
  let t = reusable_template()
  let edited = {
    ..t,
    tasks: t.tasks.map(v => { ..v, cost: "estimate pending", owner: "", }),
    milestones: t.milestones.map(v => { ..v, date: "target pending", }),
  }
  let after = @plan_workbench.append_template(
    edited,
    phase_append_target(),
    "alex",
    "lead",
    "fresh",
  )
  assert_eq(after.tasks[1].cost, "estimate pending")
  assert_eq(after.tasks[1].owner, "")
  assert_eq(after.milestones[1].date, "target pending")
  assert_true(
    (Ok(
      @plan_workbench.request(
        after,
        "alex",
        { "project_id": "project" },
        "synthetic",
        "digest",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}
