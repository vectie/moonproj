///|
test "task handoff preserves authored context and a stable exact source reference" {
  let base = update_table_draft()
  let d = {
    ..base,
    key: "plan:\"original\"",
    notes: "  Source <note> 界面\nKeep spacing  ",
    tasks: base.tasks.map(t => {
      if t.id == "T2" {
        { ..t, name: "  Review 🚀  ", }
      } else {
        t
      }
    }),
    milestones: base.milestones.map(m => {
      ..m,
      criteria: "Check quotes\nCheck sources",
      evidence: "Reviewer receipt",
      date: "date undecided",
    }),
    risks: [
      ..base.risks,
      { ..base.risks[0], id: "global", summary: "Plan-wide issue", tasks: [], },
      {
        ..base.risks[0],
        id: "unrelated",
        summary: "Unrelated issue",
        tasks: ["T3"],
      },
    ],
  }
  let before = ToJson::to_json(d).stringify()
  let handoff = @plan_workbench.task_handoff(d, "T2")
  assert_eq(handoff.title, "  Review 🚀  ")
  assert_eq(handoff.end_date, "date undecided")
  assert_true(handoff.acceptance.contains("Check quotes\nCheck sources"))
  assert_true(handoff.acceptance.contains("Reviewer receipt"))
  assert_true(handoff.acceptance.contains("adapt these criteria"))
  assert_true(handoff.context.contains(d.notes))
  assert_true(handoff.context.contains("Design [T1]"))
  assert_true(handoff.context.contains("4.20"))
  assert_true(handoff.context.contains("Arrange cover"))
  assert_true(handoff.context.contains("Plan-wide issue [global] (plan-wide)"))
  assert_false(handoff.context.contains("Unrelated issue"))
  let reference = @json.parse(
    handoff.source_reference
    .strip_prefix("MoonProj plan task (local snapshot): ")
    .unwrap()
    .to_string(),
  )
  assert_eq(reference, {
    "project_id": d.project_id,
    "plan_key": d.key,
    "task_id": "T2",
    "prepared_at": d.prepared_at,
  })
  assert_eq(ToJson::to_json(d).stringify(), before)
  let revised = { ..d, key: "later-plan", notes: "Changed context", }
  let next = @plan_workbench.task_handoff(revised, "T2")
  assert_true(next.source_reference != handoff.source_reference)
  assert_false(handoff.context.contains("Changed context"))
}

///|
test "task handoff shows incomplete and ambiguous planning links without guessing acceptance" {
  let base = update_table_draft()
  let task = {
    ..base.tasks[1],
    milestone: "missing",
    owner: "unknown",
    dependencies: ["missing", "T1"],
  }
  let d = { ..base, tasks: [base.tasks[0], base.tasks[0], task], }
  let handoff = @plan_workbench.task_handoff(d, "T2")
  assert_eq(handoff.acceptance, "")
  assert_eq(handoff.end_date, "")
  assert_true(handoff.context.contains("Missing or ambiguous [missing]"))
  assert_true(handoff.context.contains("Missing prerequisite [missing]"))
  assert_true(handoff.context.contains("Ambiguous prerequisite [T1]"))
  assert_true(handoff.context.contains("unknown"))
  let ambiguous = {
    ..base,
    milestones: [base.milestones[0], base.milestones[0]],
  }
  assert_eq(@plan_workbench.task_handoff(ambiguous, "T2").acceptance, "")
  let unassigned = {
    ..base,
    tasks: [{ ..task, id: "one", milestone: "", dependencies: [], }],
    milestones: [],
    risks: [],
  }
  let minimal = @plan_workbench.task_handoff(unassigned, "one")
  assert_true(minimal.context.contains("Milestone: Unassigned"))
  assert_true(minimal.context.contains("None declared."))
}

///|
test "task handoff rejects absent or ambiguous selected identity and missing snapshot identity" {
  let base = update_table_draft()
  for id in ["", "missing"] {
    assert_true((try Ok(@plan_workbench.task_handoff(base, id)) catch { e => Err(e) }) is Err(_))
  }
  for
    d in [
      { ..base, key: "", },
      { ..base, project_id: "", },
      { ..base, tasks: [base.tasks[1], base.tasks[1]], },
    ] {
    assert_true((try Ok(@plan_workbench.task_handoff(d, "T2")) catch { e => Err(e) }) is Err(_))
  }
}
