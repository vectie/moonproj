///|
fn update_table_draft() -> @plan_workbench.Draft {
  let (draft, _) = @plan_workbench.import_task_table(
    table_draft(),
    "id,title,cost,dependencies\nT1,Design,12.30,\nT2,Review,4.20,T1\nT3,Ship,3,T2",
    false,
    "alex",
    "release",
  ) catch {
    _ => abort("valid fixture")
  }
  {
    ..draft,
    owners: [..draft.owners, { id: "sam", name: "Sam", role: "reviewer", }],
    milestones: [
      ..draft.milestones,
      { ..draft.milestones[0], id: "later", name: "Later", },
    ],
    risks: [
      {
        id: "risk",
        summary: "Review availability",
        severity: "medium",
        owner: "alex",
        mitigation: "Arrange cover",
        tasks: ["T2"],
      },
    ],
  }
}

///|
test "task table updates preview partial rows and fields without changing relationships" {
  let original = update_table_draft()
  let update = @plan_workbench.preview_task_table_updates(
    original, "Issue key,Summary,Assignee,Milestone,Planned cost,Status\nT2,\"Review, \"\"new\"\"\n界面\",Sam,Later,4.25,Done\nT1,Design revised,alex,release,12.30,Open",
    false,
  )
  assert_eq(update.ignored, ["Status"])
  assert_eq(update.changes.map(c => c.before.id), ["T1", "T2"])
  assert_eq(update.changes[0].fields, ["title"])
  assert_eq(update.changes[1].fields, ["title", "owner", "milestone", "cost"])
  let draft = update.draft
  assert_eq(draft.tasks.map(t => t.id), ["T1", "T2", "T3"])
  assert_eq(draft.tasks[1].name, "Review, \"new\"\n界面")
  assert_eq(draft.tasks[1].owner, "sam")
  assert_eq(draft.tasks[1].milestone, "later")
  assert_eq(draft.tasks[1].dependencies, ["T1"])
  assert_eq(draft.tasks[2], original.tasks[2])
  assert_eq({ ..draft, tasks: original.tasks, }, original)
  assert_eq(original.tasks[1].name, "Review")
  let no_change = @plan_workbench.preview_task_table_updates(
    draft,
    @plan_workbench.export_task_table(draft),
    false,
  )
  assert_eq(no_change.draft, draft)
  assert_eq(no_change.changes, [])
}

///|
test "task table updates support TSV omitted title and explicit blank cost and dependencies" {
  let original = update_table_draft()
  let update = @plan_workbench.preview_task_table_updates(
    original, "\u{FEFF}id\tcost\tdependencies\r\nT2\t\t\r\n", true,
  )
  assert_eq(update.draft.tasks[1].name, "Review")
  assert_eq(update.draft.tasks[1].cost, "0")
  assert_eq(update.draft.tasks[1].dependencies, [])
  assert_eq(update.draft.tasks[2].dependencies, ["T2"])
  assert_eq(update.changes[0].fields, ["cost", "dependencies"])
  let text = @plan_workbench.preview_task_table_updates(
    original, "id,title\nT1,\"  Authored title  \"", false,
  )
  assert_eq(text.draft.tasks[0].name, "  Authored title  ")
}

///|
test "task table updates reject unknown duplicate and malformed rows atomically" {
  let original = update_table_draft()
  for
    source in [
      "id,title\nT1,Changed\nnew,Unknown", "id,title\nT1,Changed\nT1,Duplicate",
      "id,Status\nT1,Done", "title\nNo ID", "id,title,Summary\nT1,A,B", "id,title\nT1,",
      "id,owner\nT1,", "id,milestone\nT1,Missing", "id,cost\nT1,1.001", "id,cost\nT1,-1",
      "id,title\nT1,Too,many", "id,title\nT1,\"unfinished", "id,dependencies\nT2,T1;T1",
      "id,dependencies\nT1,T2", "id,dependencies\nT2,T2", "id,dependencies\nT2,missing",
    ] {
    try
      @plan_workbench.preview_task_table_updates(original, source, false)
    catch {
      @plan_workbench.Invalid(message) => assert_false(message.is_empty())
    } noraise {
      _ => fail("Should reject: " + source)
    }
    assert_eq(original, update_table_draft())
  }
}

///|
test "task table updates require unique assignments and preserve exact numeric strings" {
  let d = update_table_draft()
  let duplicate = {
    ..d,
    owners: [..d.owners, { id: "alex2", name: "Alex", role: "second", }],
  }
  try
    @plan_workbench.preview_task_table_updates(
      duplicate, "id,owner\nT1,Alex", false,
    )
  catch {
    @plan_workbench.Invalid(_) => ()
  } noraise {
    _ => fail("ambiguous owner")
  }
  let updated = @plan_workbench.preview_task_table_updates(
    duplicate, "id,owner,cost\nT1,alex2,90071992547409.93", false,
  )
  assert_eq(updated.draft.tasks[0].cost, "90071992547409.93")
  assert_eq(updated.draft.tasks[0].owner, "alex2")
  let duplicate_ids = { ..d, tasks: [..d.tasks, d.tasks[0]], }
  try
    @plan_workbench.preview_task_table_updates(
      duplicate_ids, "id,title\nT1,Title", false,
    )
  catch {
    @plan_workbench.Invalid(_) => ()
  } noraise {
    _ => fail("duplicate existing identity")
  }
}
