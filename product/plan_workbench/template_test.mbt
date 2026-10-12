///|
fn reusable_template() -> @plan_workbench.Template {
  {
    format: "moonproj-plan-template/v1",
    notes: "Synthetic two-stage delivery\nKeep customer examples and review separate. 🌓",
    currency: "USD",
    limit: "001000.00",
    contingency: "100.0",
    owners: [
      { id: "lead", name: "Alex", role: "Research / delivery", },
      { id: "reviewer", name: "Sam", role: "Independent review", },
    ],
    milestones: [
      {
        id: "discovery",
        name: "Discovery brief",
        owner: "lead",
        date: "2026-11-06",
        criteria: "Three examples\nSource references retained",
        evidence: "Source-backed brief\nReview notes",
      },
      {
        id: "delivery",
        name: "Delivery package",
        owner: "reviewer",
        date: "2026-11-13",
        criteria: "Readable final artifact\nScope checklist",
        evidence: "Artifact link\nReviewer comments",
      },
    ],
    tasks: [
      {
        id: "research",
        name: "Collect examples",
        owner: "lead",
        milestone: "discovery",
        cost: "0125.40",
        dependencies: [],
      },
      {
        id: "draft",
        name: "Draft brief",
        owner: "lead",
        milestone: "discovery",
        cost: "350.50",
        dependencies: ["research"],
      },
      {
        id: "review",
        name: "Review brief",
        owner: "reviewer",
        milestone: "delivery",
        cost: "100",
        dependencies: ["research", "draft"],
      },
      {
        id: "deliver",
        name: "Prepare delivery",
        owner: "lead",
        milestone: "delivery",
        cost: "25.00",
        dependencies: ["review"],
      },
    ],
    risks: [
      {
        id: "sources",
        summary: "Examples arrive late",
        severity: "medium",
        owner: "lead",
        mitigation: "Use named alternate sources\nKeep unresolved gaps explicit",
        tasks: ["research", "draft"],
      },
    ],
  }
}

///|
test "whole template reuse preserves authored fields and remaps every reference" {
  let t = reusable_template()
  let before = t.to_json().stringify()
  let target = {
    ..table_draft(),
    key: "new-request",
    project_id: "target-project",
  }
  let imported = @plan_workbench.apply_template(
    t, target, "alex", "reviewer", "Morgan", "fresh",
  )
  assert_eq(imported.project_id, target.project_id)
  assert_eq(imported.key, target.key)
  assert_eq(imported.prepared_at, target.prepared_at)
  assert_eq(imported.owners[1].id, "alex")
  assert_eq(imported.owners[1].name, "Morgan")
  assert_eq(imported.owners[1].role, t.owners[1].role)
  assert_eq(imported.owners[0].name, "Alex")
  assert_eq(imported.tasks[2].owner, "alex")
  assert_eq(imported.tasks[2].dependencies, ["fresh-task-1", "fresh-task-2"])
  assert_eq(imported.milestones[1].owner, "alex")
  assert_eq(imported.risks[0].tasks, ["fresh-task-1", "fresh-task-2"])
  assert_eq(imported.tasks[0].cost, "0125.40")
  assert_eq(imported.limit, "001000.00")
  assert_eq(imported.contingency, "100.0")
  assert_eq(t.to_json().stringify(), before)
  let exported = @plan_workbench.export_template(imported)
  for
    absent in [
      "target-project", "new-request", "prepared_at", "fresh-task-", "fresh-owner-",
      "\"alex\"",
    ] {
    assert_false(exported.contains(absent))
  }
  let portable = @plan_workbench.read_template(exported)
  let again = @plan_workbench.apply_template(
    portable, target, "alex", "owner-2", "Morgan", "second",
  )
  assert_eq(@plan_workbench.export_template(again), exported)
  assert_eq(portable.notes, t.notes)
  assert_eq(portable.currency, t.currency)
  assert_eq(
    portable.tasks.map(v => (v.name, v.cost)),
    t.tasks.map(v => (v.name, v.cost)),
  )
  assert_eq(
    portable.milestones.map(v => (v.name, v.date, v.criteria, v.evidence)),
    t.milestones.map(v => (v.name, v.date, v.criteria, v.evidence)),
  )
  assert_eq(
    portable.risks.map(v => (v.summary, v.severity, v.mitigation)),
    t.risks.map(v => (v.summary, v.severity, v.mitigation)),
  )
  let wire = @plan_workbench.request(
    imported,
    "alex",
    { "project_id": "target-project" },
    "synthetic-source",
    "synthetic-digest",
  )
  assert_eq(
    @plan_workbench.field(
      @plan_workbench.items(wire, "tasks")[0],
      "planned_cost_minor",
    ),
    ("12540" : Json),
  )
  assert_eq(@plan_workbench.text(wire, "prepared_by"), "alex")
}

///|
test "template authoring round trip retains blanks invalid dates costs and order for later editing" {
  let base = reusable_template()
  let t = {
    ..base,
    notes: "",
    limit: "not yet estimated",
    tasks: [
      { ..base.tasks[1], owner: "", milestone: "", cost: "TBD", },
      base.tasks[0],
    ],
    milestones: [{ ..base.milestones[0], date: "date not set", }],
    risks: [],
  }
  let parsed = @plan_workbench.read_template(t.to_json().stringify())
  assert_eq(parsed, t)
  let imported = @plan_workbench.apply_template(
    parsed,
    table_draft(),
    "alex",
    "lead",
    "Alex",
    "copy",
  )
  assert_eq(imported.tasks[0].owner, "")
  assert_eq(imported.tasks[0].milestone, "")
  assert_eq(imported.tasks[0].dependencies, ["copy-task-2"])
  assert_eq(imported.tasks[0].cost, "TBD")
  assert_eq(imported.milestones[0].date, "date not set")
  assert_eq(imported.limit, "not yet estimated")
  assert_true(
    (try? @plan_workbench.request(imported, "alex", {}, "s", "d")) is Err(_),
  )
}

///|
test "invalid template structure and unsupported fields do not silently lose content" {
  let t = reusable_template()
  let json = t.to_json().stringify()
  for
    source in [
      "{",
      "{}",
      json.replace_all(
        old="moonproj-plan-template/v1",
        new="moonproj-plan-template/v2",
      ),
      json.replace_all(old="\"cost\":\"100\"", new="\"cost\":100"),
      json.replace_all(old="\"role\":", new="\"unrecognized\":0,\"role\":"),
      json.replace_all(
        old="\"format\":",
        new="\"status\":\"approved\",\"format\":",
      ),
    ] {
    assert_true((try? @plan_workbench.read_template(source)) is Err(_))
  }
  for
    changed in [
      { ..t, owners: [t.owners[0], t.owners[0]], },
      { ..t, tasks: [{ ..t.tasks[0], dependencies: ["missing"], }], },
      { ..t, tasks: [{ ..t.tasks[0], owner: "unknown", }], },
      { ..t, tasks: [{ ..t.tasks[0], milestone: "unknown", }], },
      { ..t, risks: [{ ..t.risks[0], tasks: ["missing"], }], },
      { ..t, owners: [], },
    ] {
    assert_true(
      (try? @plan_workbench.read_template(changed.to_json().stringify()))
      is Err(_),
    )
  }
  assert_true(
    (try? @plan_workbench.apply_template(
      t,
      table_draft(),
      "alex",
      "missing",
      "Morgan",
      "fresh",
    ))
    is Err(_),
  )
  assert_true(
    (try? @plan_workbench.apply_template(
      t,
      table_draft(),
      "alex",
      "lead",
      " ",
      "fresh",
    ))
    is Err(_),
  )
  assert_true(
    (try? @plan_workbench.apply_template(
      t,
      table_draft(),
      "other-actor",
      "lead",
      "Morgan",
      "fresh",
    ))
    is Err(_),
  )
}

///|
test "template row and text bounds are consistent for import and export" {
  let t = reusable_template()
  let too_many = { ..t, owners: Array::make(41, t.owners[0]), }
  assert_true(
    (try? @plan_workbench.read_template(too_many.to_json().stringify()))
    is Err(_),
  )
  let huge = { ..t, notes: "x".repeat(1000001), }
  assert_true(
    (try? @plan_workbench.read_template(huge.to_json().stringify())) is Err(_),
  )
  let draft = { ..table_draft(), notes: "x".repeat(1000001), }
  assert_true((try? @plan_workbench.export_template(draft)) is Err(_))
}
