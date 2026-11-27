///|
fn replacement_test_draft() -> @plan_workbench.Draft {
  {
    key: "Draft",
    project_id: "Project",
    prepared_at: "2026-10-11T00:00:00Z",
    notes: "Pilot brief\nPilot scope; pilot is distinct.",
    currency: "USD",
    limit: "1000.00",
    contingency: "0",
    owners: [{ id: "Pilot-owner", name: "Pilot", role: "Pilot reviewer", }],
    tasks: [
      {
        id: "Pilot-one",
        name: "Pilot design",
        owner: "Pilot-owner",
        milestone: "Pilot-m",
        cost: "12.30",
        dependencies: [],
      },
      {
        id: "two",
        name: "Pilot review",
        owner: "Pilot-owner",
        milestone: "Pilot-m",
        cost: "0",
        dependencies: ["Pilot-one"],
      },
    ],
    milestones: [
      {
        id: "Pilot-m",
        name: "Pilot delivery",
        owner: "Pilot-owner",
        date: "2026-12-01",
        criteria: "Pilot criteria\nKeep receipt",
        evidence: "Pilot evidence",
      },
    ],
    risks: [
      {
        id: "Pilot-r",
        summary: "Pilot delay",
        severity: "medium",
        owner: "Pilot-owner",
        mitigation: "Pilot fallback",
        tasks: ["Pilot-one"],
      },
    ],
  }
}

///|
test "literal plan replacement updates selected authored fields while all references remain exact" {
  let before = replacement_test_draft()
  let result = @plan_workbench.preview_plan_text_replacement(
    before, "Pilot", "Launch 界面", "all",
  )
  assert_eq(result.occurrences, 9)
  assert_eq(result.changes.length(), 8)
  assert_eq(result.changes.map(c => c.kind), [
    "notes", "tasks", "tasks", "milestones", "milestones", "milestones", "risks",
    "risks",
  ])
  assert_eq(
    result.draft.notes,
    "Launch 界面 brief\nLaunch 界面 scope; pilot is distinct.",
  )
  assert_eq(result.draft.owners, before.owners)
  assert_eq(result.draft.tasks[0], {
    ..before.tasks[0],
    name: "Launch 界面 design",
  })
  assert_eq(result.draft.tasks[1], {
    ..before.tasks[1],
    name: "Launch 界面 review",
  })
  assert_eq(result.draft.milestones[0], {
    ..before.milestones[0],
    name: "Launch 界面 delivery",
    criteria: "Launch 界面 criteria\nKeep receipt",
    evidence: "Launch 界面 evidence",
  })
  assert_eq(result.draft.risks[0], {
    ..before.risks[0],
    summary: "Launch 界面 delay",
    mitigation: "Launch 界面 fallback",
  })
  assert_eq(
    {
      ..result.draft,
      notes: before.notes,
      tasks: before.tasks,
      milestones: before.milestones,
      risks: before.risks,
    },
    before,
  )
  assert_eq(before, replacement_test_draft())
}

///|
test "replacement scopes literal punctuation multiline Unicode no-op and removal" {
  let before = replacement_test_draft()
  for scope in ["notes", "tasks", "milestones", "risks"] {
    let result = @plan_workbench.preview_plan_text_replacement(
      before, "Pilot", "New", scope,
    )
    assert_true(result.changes.all(c => c.kind == scope))
    assert_true(!result.changes.is_empty())
  }
  let special = { ..before, notes: "[a].* [a].*\n界面🚀界面🚀 aaaa", }
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(
      special, "[a].*", "$&", "notes",
    ).draft.notes,
    "$& $&\n界面🚀界面🚀 aaaa",
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(
      special, "界面🚀", "星", "notes",
    ).occurrences,
    2,
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(special, "aa", "b", "notes").draft.notes,
    "[a].* [a].*\n界面🚀界面🚀 bb",
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(
      before, "brief\nPilot", "outline\nLaunch", "notes",
    ).draft.notes,
    "Pilot outline\nLaunch scope; pilot is distinct.",
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(before, "Pilot ", "", "tasks").draft.tasks[0].name,
    "design",
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(
      before, "Pilot", "Pilot", "all",
    ).changes,
    [],
  )
  assert_eq(
    @plan_workbench.preview_plan_text_replacement(before, "MISSING", "X", "all").draft,
    before,
  )
}

///|
test "invalid replacement and field-emptying failures are atomic and bounded" {
  let before = replacement_test_draft()
  for
    args in [
      ("", "x", "all"),
      ("Pilot", "x", "owners"),
      ("Pilot design", "", "tasks"),
      ("x".repeat(2001), "", "all"),
      ("Pilot", "x".repeat(2001), "all"),
    ] {
    assert_true(
      (Ok(
        @plan_workbench.preview_plan_text_replacement(
          before,
          args.0,
          args.1,
          args.2,
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
    assert_eq(before, replacement_test_draft())
  }
  let expansion = { ..before, notes: "x".repeat(1000), }
  assert_true(
    (Ok(
      @plan_workbench.preview_plan_text_replacement(
        expansion,
        "x",
        "z".repeat(2000),
        "notes",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let huge = { ..before, notes: "x".repeat(1000000), }
  assert_true(
    (Ok(@plan_workbench.preview_plan_text_replacement(huge, "x", "z", "all")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let too_many = { ..before, tasks: Array::make(101, before.tasks[0]), }
  assert_true(
    (Ok(
      @plan_workbench.preview_plan_text_replacement(
        too_many, "Pilot", "New", "all",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}
