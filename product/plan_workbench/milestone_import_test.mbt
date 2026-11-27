///|
fn milestone_import_rejected(
  draft : @plan_workbench.Draft,
  source : String,
  tsv : Bool,
) -> Bool {
  try @plan_workbench.preview_milestone_table_import(draft, source, tsv) catch {
    @plan_workbench.Invalid(_) => true
  } noraise {
    _ => false
  }
}

///|
test "milestone import starts an empty roadmap and task CSV retains exact source IDs" {
  let source = milestone_table_draft()
  let empty = { ..source, milestones: [], tasks: [], risks: [], }
  let csv = "id,title,owner,date,criteria,evidence,Status\r\nroadmap-alpha,\"  Launch, \"\"界面\"\"  \",Alex,2028-02-29,\"First\nSecond\",\"Artifact\nReview\",Done\r\nroadmap-beta,Follow-up,sam,2028-03-04,Questions,Response,Accepted\r\n"
  let preview = @plan_workbench.preview_milestone_table_import(
    empty, csv, false,
  )
  assert_eq(preview.additions.map(m => m.id), ["roadmap-alpha", "roadmap-beta"])
  assert_eq(preview.ignored, ["Status"])
  assert_eq(preview.unchanged, [])
  assert_eq(preview.draft.milestones[0].name, "  Launch, \"界面\"  ")
  assert_eq(preview.draft.milestones[0].criteria, "First\nSecond")
  assert_eq(preview.draft.milestones[0].owner, "alex")
  assert_eq({ ..preview.draft, milestones: [], }, empty)
  assert_eq(empty.milestones, [])
  let (with_tasks, _) = @plan_workbench.import_task_table(
    preview.draft,
    "id,title,owner,milestone,cost,dependencies\nalpha,Prepare,alex,roadmap-alpha,1.25,\nbeta,Review,sam,roadmap-beta,2.75,alpha",
    false,
    "alex",
    "roadmap-alpha",
  )
  assert_eq(with_tasks.tasks.map(t => t.milestone), [
    "roadmap-alpha", "roadmap-beta",
  ])
  let request = @plan_workbench.request(
    with_tasks,
    "alex",
    { "project_id": empty.project_id },
    "source",
    "digest",
  )
  let milestones = @plan_workbench.items(request, "milestones")
  assert_eq(@plan_workbench.items(milestones[0], "task_ids"), ["alpha"])
  assert_eq(@plan_workbench.items(milestones[1], "task_ids"), ["beta"])
  let gate = @plan_workbench.items(request, "acceptance_gates")[0]
  assert_eq(@plan_workbench.items(gate, "criteria"), ["First", "Second"])
  let exported = @plan_workbench.export_milestone_table(with_tasks)
  let replay = @plan_workbench.preview_milestone_table_import(
    with_tasks, exported, false,
  )
  assert_eq(replay.draft, with_tasks)
  assert_eq(replay.additions, [])
  assert_eq(replay.unchanged, ["roadmap-alpha", "roadmap-beta"])
}

///|
test "milestone import appends TSV drafts and preserves existing plan values" {
  let original = milestone_table_draft()
  let preview = @plan_workbench.preview_milestone_table_import(
    original, "\u{FEFF}Milestone ID\tName\tAssignee\tAcceptance criteria\r\nnew-phase\t Phase \tsam\t\"Use tabs\tand\nnewlines\"\r\n",
    true,
  )
  assert_eq(preview.draft.milestones.map(m => m.id), [
    "release", "later", "extra", "new-phase",
  ])
  assert_eq(preview.additions[0].criteria, "Use tabs\tand\nnewlines")
  assert_eq(preview.additions[0].date, "")
  assert_eq(preview.additions[0].evidence, "")
  assert_eq({ ..preview.draft, milestones: original.milestones, }, original)
  let mixed = @plan_workbench.export_milestone_table(original) +
    "\"new-phase\",\"Phase\",\"sam\",\"\",\"\",\"\"\r\n"
  let result = @plan_workbench.preview_milestone_table_import(
    original, mixed, false,
  )
  assert_eq(result.unchanged, ["release", "later", "extra"])
  assert_eq(result.additions.map(m => m.id), ["new-phase"])
  assert_true(
    (Ok(
      @plan_workbench.preview_milestone_table_updates(
        original, "id,title\nnew-phase,Phase", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "milestone import refuses malformed rows collisions and ambiguous owners atomically" {
  let original = milestone_table_draft()
  for
    csv in [
      "id,title,owner\nnew,New,alex\nrelease,Changed,alex", "id,title,owner\nnew,New,alex\nnew,Again,sam",
      "id,title,owner\n,New,alex", "id,title,owner\nnew, ,alex", "id,title,owner\nnew,New,",
      "id,title,owner\nnew,New,unknown", "id,title\nnew,New", "id,owner\nnew,alex",
      "title,owner\nNew,alex", "id,title,name,owner\nnew,New,Other,alex", "id,id,title,owner\nnew,new,New,alex",
      "id,title,owner,date\nnew,New,alex,2027-02-29", "id,title,owner\nnew,New,alex,extra",
      "id,title,owner\nnew,\"unclosed,alex", "id,title,owner\nnew,\"closed\"junk,alex",
      "id,title,owner\n",
    ] {
    assert_true(milestone_import_rejected(original, csv, false))
    assert_eq(original, milestone_table_draft())
  }
  let ambiguous = {
    ..original,
    owners: [..original.owners, { id: "another", name: "Sam", role: "second", }],
  }
  assert_true(
    milestone_import_rejected(ambiguous, "id,title,owner\nnew,New,Sam", false),
  )
  let duplicate = {
    ..original,
    milestones: [original.milestones[0], original.milestones[0]],
  }
  assert_true(
    milestone_import_rejected(duplicate, "id,title,owner\nnew,New,alex", false),
  )
  let padded = {
    ..original,
    milestones: [{ ..original.milestones[0], id: " release ", }],
  }
  assert_true(
    milestone_import_rejected(padded, "id,title,owner\nnew,New,alex", false),
  )
}

///|
test "milestone import enforces total and input limits and preserves replay at capacity" {
  let original = milestone_table_draft()
  let full = {
    ..original,
    milestones: Array::makei(40, i => {
      ..original.milestones[0],
      id: "m-" + i.to_string(),
    }),
  }
  let same = @plan_workbench.preview_milestone_table_import(
    full,
    @plan_workbench.export_milestone_table(full),
    false,
  )
  assert_eq(same.draft, full)
  assert_eq(same.unchanged.length(), 40)
  assert_true(
    milestone_import_rejected(full, "id,title,owner\nnew,New,alex", false),
  )
  let rows = Array::makei(41, i => "new-" + i.to_string() + ",New,alex")
  assert_true(
    milestone_import_rejected(
      original,
      "id,title,owner\n" + rows.join("\n"),
      false,
    ),
  )
  assert_true(milestone_import_rejected(original, "x".repeat(1000001), false))
}
