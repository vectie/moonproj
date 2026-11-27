///|
fn phase_extract_source() -> @plan_workbench.Draft {
  let t = reusable_template()
  {
    ..table_draft(),
    notes: "Whole-company scope, not a phase",
    owners: [..t.owners, { id: "unused", name: "Other", role: "Unrelated", }],
    tasks: [
      ..t.tasks,
      { ..t.tasks[0], id: "later", name: "Later discovery", dependencies: [], },
    ],
    milestones: t.milestones,
    risks: [
      ..t.risks,
      {
        ..t.risks[0],
        id: "cross",
        summary: "Review and delivery",
        tasks: ["review", "deliver"],
      },
      { ..t.risks[0], id: "global", summary: "Source-wide risk", tasks: [], },
      {
        ..t.risks[0],
        id: "outside",
        summary: "Unrelated risk",
        tasks: ["later"],
      },
    ],
  }
}

///|
test "extract prerequisite closure preserves authored rows and complete portable references" {
  let source = phase_extract_source()
  let before = ToJson::to_json(source).stringify()
  let e = @plan_workbench.extract_phase(source, ["review"], "")
  assert_eq(e.selected, ["review"])
  assert_eq(e.prerequisites, ["research", "draft"])
  assert_eq(e.partial_milestones, ["discovery", "delivery"])
  assert_eq(e.cross_scope_risks, ["cross"])
  assert_eq(e.unscoped_risks, ["global"])
  assert_eq(e.omitted_risk_count, 3)
  assert_false(e.fallback_owner)
  let t = @plan_workbench.read_template(e.json)
  assert_eq(t.owners.length(), 2)
  assert_eq(t.tasks.length(), 3)
  assert_eq(t.milestones.length(), 2)
  assert_eq(t.risks.length(), 1)
  assert_eq(t.limit, "")
  assert_eq(t.contingency, "")
  assert_eq(t.currency, source.currency)
  assert_false(t.notes.contains(source.notes))
  for
    context in [
      "Partial milestone", "Later discovery", "Prepare delivery", "Omitted cross-scope risk",
      "Review and delivery", "Source-wide risk", "not apportioned",
    ] {
    assert_true(t.notes.contains(context))
  }
  assert_false(e.json.contains("Unrelated risk"))
  assert_false(e.json.contains("\"unused\""))
  assert_eq(t.owners[0], { ..source.owners[0], id: "owner-1", })
  assert_eq(t.owners[1], { ..source.owners[1], id: "owner-2", })
  assert_eq(t.tasks[0], {
    ..source.tasks[0],
    id: "task-1",
    owner: "owner-1",
    milestone: "milestone-1",
  })
  assert_eq(t.tasks[1], {
    ..source.tasks[1],
    id: "task-2",
    owner: "owner-1",
    milestone: "milestone-1",
    dependencies: ["task-1"],
  })
  assert_eq(t.tasks[2], {
    ..source.tasks[2],
    id: "task-3",
    owner: "owner-2",
    milestone: "milestone-2",
    dependencies: ["task-1", "task-2"],
  })
  assert_eq(t.milestones[0], {
    ..source.milestones[0],
    id: "milestone-1",
    owner: "owner-1",
  })
  assert_eq(t.milestones[1], {
    ..source.milestones[1],
    id: "milestone-2",
    owner: "owner-2",
  })
  assert_eq(t.risks[0], {
    ..source.risks[0],
    id: "risk-1",
    owner: "owner-1",
    tasks: ["task-1", "task-2"],
  })
  let target = table_draft()
  let replaced = @plan_workbench.apply_template(
    t, target, "alex", "owner-1", "Alex", "reuse",
  )
  // The explicitly chosen replacement display name matches the source here.
  assert_eq(@plan_workbench.export_template(replaced), e.json)
  assert_eq(replaced.key, target.key)
  assert_eq(replaced.project_id, target.project_id)
  assert_eq(replaced.prepared_at, target.prepared_at)
  let target = phase_append_target()
  let combined = @plan_workbench.append_template(
    t, target, "alex", "owner-2", "phase",
  )
  assert_eq(combined.tasks[0], target.tasks[0])
  assert_eq(combined.tasks[3].dependencies, ["phase-task-1", "phase-task-2"])
  assert_eq(combined.tasks[3].milestone, "phase-milestone-2")
  assert_eq(combined.tasks[3].owner, "alex")
  assert_eq(combined.risks[1].tasks, ["phase-task-1", "phase-task-2"])
  assert_eq(combined.milestones[2].owner, "alex")
  assert_eq(combined.notes, target.notes)
  assert_eq(combined.limit, target.limit)
  assert_eq(combined.contingency, target.contingency)
  ignore(
    @plan_workbench.read_template(@plan_workbench.export_template(combined)),
  )
  t.tasks[1].dependencies.push("local-edit")
  t.risks[0].tasks.push("local-edit")
  assert_eq(ToJson::to_json(source).stringify(), before)
}

///|
test "milestone union reverse order cyclic editable graph and unassigned owner slot" {
  let source = phase_extract_source()
  let e = @plan_workbench.extract_phase(source, ["later"], "delivery")
  assert_eq(e.selected, ["review", "deliver", "later"])
  assert_eq(e.prerequisites, ["research", "draft"])
  assert_eq(e.partial_milestones, [])
  assert_eq(e.cross_scope_risks, [])
  assert_eq(@plan_workbench.read_template(e.json).risks.length(), 3)
  let reversed = {
    ..source,
    tasks: [source.tasks[2], source.tasks[1], source.tasks[0]],
    risks: [],
  }
  let reverse = @plan_workbench.extract_phase(reversed, ["review"], "")
  assert_eq(reverse.prerequisites, ["draft", "research"])
  assert_eq(@plan_workbench.read_template(reverse.json).tasks[0].dependencies, [
    "task-3", "task-2",
  ])
  let cycle = {
    ..reversed,
    tasks: [
      reversed.tasks[0],
      reversed.tasks[1],
      { ..reversed.tasks[2], dependencies: ["review"], },
    ],
  }
  assert_eq(
    @plan_workbench.read_template(
      @plan_workbench.extract_phase(cycle, ["review"], "").json,
    ).tasks.length(),
    3,
  )
  let blank = {
    ..source,
    tasks: [{ ..source.tasks[0], owner: "", milestone: "", cost: "TBD", }],
    milestones: [],
    risks: [],
  }
  let blank_phase = @plan_workbench.extract_phase(blank, ["research"], "")
  assert_true(blank_phase.fallback_owner)
  let t = @plan_workbench.read_template(blank_phase.json)
  assert_eq(t.owners.length(), 1)
  assert_eq(t.tasks[0].owner, "")
  assert_eq(t.tasks[0].milestone, "")
  assert_eq(t.tasks[0].cost, "TBD")
  assert_true(t.notes.contains("required reusable owner slot"))
}

///|
test "invalid extraction rejects without altering source and fresh edits regenerate output" {
  let d = phase_extract_source()
  let before = ToJson::to_json(d).stringify()
  for
    (tasks, milestone) in [
      ([], ""),
      (["missing"], ""),
      (["review", "review"], ""),
      ([""], ""),
      ([], "missing"),
    ] {
    assert_true(
      (Ok(@plan_workbench.extract_phase(d, tasks, milestone)) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let empty = {
    ..d,
    milestones: [..d.milestones, { ..d.milestones[0], id: "empty", }],
  }
  assert_true(
    (Ok(@plan_workbench.extract_phase(empty, [], "empty")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  for
    broken in [
      { ..d, tasks: [..d.tasks, d.tasks[0]], },
      { ..d, tasks: [{ ..d.tasks[0], dependencies: ["missing"], }], risks: [], },
      { ..d, tasks: [{ ..d.tasks[0], owner: "missing", }], risks: [], },
      { ..d, notes: "x".repeat(1000001), },
    ] {
    assert_true(
      (Ok(@plan_workbench.extract_phase(broken, ["research"], "")) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let old = @plan_workbench.extract_phase(d, ["review"], "")
  let edited = {
    ..d,
    tasks: d.tasks.map(t => {
      if t.id == "draft" {
        { ..t, name: "New draft", cost: "012.30", }
      } else {
        t
      }
    }),
  }
  let fresh = @plan_workbench.extract_phase(edited, ["review"], "")
  assert_true(fresh.json != old.json)
  assert_true(fresh.json.contains("New draft"))
  assert_true(fresh.json.contains("012.30"))
  assert_eq(ToJson::to_json(d).stringify(), before)
}
