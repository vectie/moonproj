///|
fn milestone_table_draft() -> @plan_workbench.Draft {
  let d = update_table_draft()
  {
    ..d,
    milestones: [
      {
        id: "release",
        name: "Release",
        owner: "alex",
        date: "2028-02-28",
        criteria: "Readable brief\nReview completed",
        evidence: "Review receipt",
      },
      {
        id: "later",
        name: "Follow-up",
        owner: "sam",
        date: "2028-03-10",
        criteria: "Answer questions",
        evidence: "Response",
      },
      {
        id: "extra",
        name: "Optional",
        owner: "alex",
        date: "",
        criteria: "",
        evidence: "",
      },
    ],
  }
}

///|
test "milestone table roundtrip edits independently and keeps task links and exact text" {
  let original = milestone_table_draft()
  let changed = @plan_workbench.preview_milestone_table_updates(
    original, "Milestone ID,Title,Assignee,Target date,Acceptance criteria,Required evidence,Status\r\nlater,Follow-up,Sam,2028-03-05,Answer questions,Response,Done\r\nrelease,\"  Release, \"\"界面\"\"  \",sam,2028-02-29,\"One\nTwo, with commas\",\"  Receipt\n<source>  \",Accepted\r\n",
    false,
  )
  assert_eq(changed.ignored, ["Status"])
  assert_eq(changed.changes.map(c => c.before.id), ["release", "later"])
  assert_eq(changed.changes[0].fields, [
    "title", "owner", "date", "criteria", "evidence",
  ])
  assert_eq(changed.changes[1].fields, ["date"])
  let d = changed.draft
  assert_eq(d.milestones.map(m => m.id), ["release", "later", "extra"])
  assert_eq(d.milestones[0].date, "2028-02-29")
  assert_eq(d.milestones[1].date, "2028-03-05")
  assert_eq(d.milestones[0].name, "  Release, \"界面\"  ")
  assert_eq(d.milestones[0].criteria, "One\nTwo, with commas")
  assert_eq(d.milestones[0].evidence, "  Receipt\n<source>  ")
  assert_eq(d.milestones[2], original.milestones[2])
  assert_eq(d.tasks, original.tasks)
  assert_eq({ ..d, milestones: original.milestones, }, original)
  assert_eq(original, milestone_table_draft())
  let exported = @plan_workbench.export_milestone_table(d)
  let roundtrip = @plan_workbench.preview_milestone_table_updates(
    d, exported, false,
  )
  assert_eq(roundtrip.draft, d)
  assert_eq(roundtrip.changes, [])
}

///|
test "milestone partial TSV clears explicit blank fields and retains omitted fields" {
  let original = milestone_table_draft()
  let updated = @plan_workbench.preview_milestone_table_updates(
    original, "\u{FEFF}id\tdate\tcriteria\tevidence\r\nrelease\t \t\"\"\t\"\"\r\n",
    true,
  )
  assert_eq(updated.draft.milestones[0], {
    ..original.milestones[0],
    date: "",
    criteria: "",
    evidence: "",
  })
  assert_eq(updated.changes[0].fields, ["date", "criteria", "evidence"])
  assert_eq(updated.draft.milestones[1], original.milestones[1])
  let multiline = @plan_workbench.preview_milestone_table_updates(
    original, "id\tcriteria\nlater\t\"Use tabs\tand\nnewlines\"", true,
  )
  assert_eq(multiline.draft.milestones[1].criteria, "Use tabs\tand\nnewlines")
  let incomplete = {
    ..original,
    milestones: [
      { ..original.milestones[0], name: "", owner: "", date: "TBD", },
    ],
  }
  let partial = @plan_workbench.preview_milestone_table_updates(
    incomplete, "id,criteria\rrelease,Revised", false,
  )
  assert_eq(partial.draft.milestones[0], {
    ..incomplete.milestones[0],
    criteria: "Revised",
  })
  let spaced = @plan_workbench.preview_milestone_table_updates(
    original, " id , DUE DATE \nrelease, 2028-03-01 ", false,
  )
  assert_eq(spaced.draft.milestones[0].date, "2028-03-01")
}

///|
test "milestone table rejects broken identity dates and records without partial edits" {
  let original = milestone_table_draft()
  for
    source in [
      "id,title\nrelease,Changed\nunknown,Unknown", "id,title\nrelease,Changed\nrelease,Again",
      "id,Status\nrelease,Done", "title\nTitle", "id,title,name\nrelease,A,B", "id,title\nrelease, ",
      "id,owner\nrelease,", "id,owner\nrelease,Missing", "id,date\nrelease,2027-02-29",
      "id,date\nrelease,2028-04-31", "id,date\nrelease,0000-01-01", "id,date\nrelease,10000-01-01",
      "id,date\nrelease,2028-2-1", "id,title\nrelease,Too,many", "id,title\nrelease,\"unclosed",
      "id,title\nrelease,\"closed\"junk", "id,title\n", "id,title\n,New",
    ] {
    try
      @plan_workbench.preview_milestone_table_updates(original, source, false)
    catch {
      @plan_workbench.Invalid(message) => assert_false(message.is_empty())
    } noraise {
      _ => fail("Should reject: " + source)
    }
    assert_eq(original, milestone_table_draft())
  }
  let duplicate = {
    ..original,
    milestones: [original.milestones[0], original.milestones[0]],
  }
  assert_true(
    (try Ok(@plan_workbench.preview_milestone_table_updates(
      duplicate, "id,date\nrelease,", false,
    )) catch { e => Err(e) })
    is Err(_),
  )
  let owners = {
    ..original,
    owners: [..original.owners, { id: "other", name: "Sam", role: "second", }],
  }
  assert_true(
    (try Ok(@plan_workbench.preview_milestone_table_updates(
      owners, "id,owner\nrelease,Sam", false,
    )) catch { e => Err(e) })
    is Err(_),
  )
  assert_eq(
    @plan_workbench.preview_milestone_table_updates(
      owners, "id,owner\nrelease,other", false,
    ).draft.milestones[0].owner,
    "other",
  )
  let duplicate_owner = {
    ..original,
    owners: [
      ..original.owners,
      { id: "sam", name: "Other", role: "duplicate", },
    ],
  }
  assert_true(
    (try Ok(@plan_workbench.preview_milestone_table_updates(
      duplicate_owner, "id,owner\nrelease,Other", false,
    )) catch { e => Err(e) })
    is Err(_),
  )
  assert_true(
    (try Ok(@plan_workbench.preview_milestone_table_updates(
      original,
      "x".repeat(1000001),
      false,
    )) catch { e => Err(e) })
    is Err(_),
  )
}

///|
test "milestone table edits reach existing plan request and calendar projections" {
  let original = milestone_table_draft()
  let edited = @plan_workbench.preview_milestone_table_updates(
      original, "id,date,criteria,evidence\nrelease,2028-02-29,\"First\nSecond\",\"Artifact digest\nReview report\"\nlater,2028-03-06,Questions,Response\nextra,2028-03-07,Optional,Note",
      false,
    ).draft
  let request = @plan_workbench.request(
    edited,
    "alex",
    { "project_id": edited.project_id },
    "source",
    "digest",
  )
  let first = @plan_workbench.items(request, "milestones")[0]
  assert_eq(@plan_workbench.text(first, "milestone_id"), "release")
  assert_eq(@plan_workbench.text(first, "target_date"), "2028-02-29")
  assert_eq(
    @plan_workbench.items(first, "task_ids"),
    original.tasks
    .filter(t => t.milestone == "release")
    .map(t => ToJson::to_json(t.id)),
  )
  let gate = @plan_workbench.items(request, "acceptance_gates")[0]
  assert_eq(@plan_workbench.items(gate, "criteria"), ["First", "Second"])
  assert_eq(@plan_workbench.items(gate, "required_evidence"), [
    "Artifact digest", "Review report",
  ])
  let calendar = @plan_workbench.export_milestone_calendar(
    edited, "Synthetic plan",
  )
  assert_true(calendar.contains("DTSTART;VALUE=DATE:20280229"))
  assert_true(calendar.contains("DTSTART;VALUE=DATE:20280306"))
  assert_true(calendar.contains("DTSTART;VALUE=DATE:20280307"))
}
