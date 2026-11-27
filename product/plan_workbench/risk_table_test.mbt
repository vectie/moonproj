///|
fn risk_table_draft() -> @plan_workbench.Draft {
  let d = update_table_draft()
  {
    ..d,
    risks: [
      ..d.risks,
      { ..d.risks[0], id: "untouched", summary: "Independent risk", tasks: [], },
    ],
  }
}

///|
test "risk register mixes additions and updates preserving exact authored text and plan context" {
  let original = risk_table_draft()
  let preview = @plan_workbench.preview_risk_table(
    original, "Risk ID,Title,severity,Assignee,Mitigation plan,Related tasks,Status\r\nnew-risk,New supplier,high,Sam,,T1;T3,Closed\r\nrisk,\"  Review, \"\"界面\"\"\n<source>  \",critical,Sam,\"Call supplier\nAsk for \"\"backup\"\"\",T3;T2,Resolved\r\n",
    false,
  )
  let d = preview.draft
  assert_eq(preview.ignored, ["Status"])
  assert_eq(preview.changes.map(c => c.after.id), ["risk", "new-risk"])
  assert_eq(preview.changes[0].before, Some(original.risks[0]))
  assert_eq(preview.changes[0].fields, [
    "summary", "severity", "owner", "mitigation", "tasks",
  ])
  assert_eq(preview.changes[1].before, None)
  assert_eq(preview.changes[1].fields, ["new risk"])
  assert_eq(d.risks.map(r => r.id), ["risk", "untouched", "new-risk"])
  assert_eq(d.risks[0].summary, "  Review, \"界面\"\n<source>  ")
  assert_eq(d.risks[0].mitigation, "Call supplier\nAsk for \"backup\"")
  assert_eq(d.risks[0].owner, "sam")
  assert_eq(d.risks[0].tasks, ["T3", "T2"])
  assert_eq(d.risks[1], original.risks[1])
  assert_eq(d.risks[2].mitigation, "")
  assert_eq({ ..d, risks: original.risks, }, original)
  assert_eq(original, risk_table_draft())
  let roundtrip = @plan_workbench.preview_risk_table(
    d,
    @plan_workbench.export_risk_table(d),
    false,
  )
  assert_eq(roundtrip.draft, d)
  assert_eq(roundtrip.changes, [])
}

///|
test "risk register partial TSV edits and explicit blanks clear optional fields only" {
  let original = risk_table_draft()
  let cleared = @plan_workbench.preview_risk_table(
    original, "\u{FEFF}id\tmitigation\ttasks\r\nrisk\t\"\"\t\r\n", true,
  )
  assert_eq(cleared.draft.risks[0], {
    ..original.risks[0],
    mitigation: "",
    tasks: [],
  })
  assert_eq(cleared.changes[0].fields, ["mitigation", "tasks"])
  assert_eq(cleared.draft.risks[1], original.risks[1])
  let multiline = @plan_workbench.preview_risk_table(
    original, "id\tmitigation\rrisk\t\"  Tabs\tand\nlines  \"", true,
  )
  assert_eq(multiline.draft.risks[0].mitigation, "  Tabs\tand\nlines  ")
  let incomplete = {
    ..original,
    risks: [
      {
        ..original.risks[0],
        summary: "",
        severity: "TBD",
        owner: "missing",
        tasks: ["missing"],
      },
    ],
  }
  let partial = @plan_workbench.preview_risk_table(
    incomplete, "id,mitigation\nrisk,Revised", false,
  )
  assert_eq(partial.draft.risks[0], {
    ..incomplete.risks[0],
    mitigation: "Revised",
  })
  let roundtrip = @plan_workbench.preview_risk_table(
    cleared.draft,
    @plan_workbench.export_risk_table(cleared.draft),
    false,
  )
  assert_eq(roundtrip.draft, cleared.draft)
}

///|
test "risk register can start empty and append rows with optional columns omitted" {
  let original = { ..risk_table_draft(), risks: [], }
  assert_eq(
    @plan_workbench.export_risk_table(original),
    "id,summary,severity,owner,mitigation,tasks\r\n",
  )
  let preview = @plan_workbench.preview_risk_table(
    original, "id,summary,severity,owner\nR1,Delivery,low,alex\nR2,Staff,medium,Sam",
    false,
  )
  assert_eq(preview.draft.risks.map(r => r.id), ["R1", "R2"])
  assert_eq(preview.draft.risks[0].mitigation, "")
  assert_eq(preview.draft.risks[0].tasks, [])
  assert_eq(preview.draft.risks[1].owner, "sam")
  assert_true(preview.changes.all(c => c.before is None))
  assert_eq(original.risks, [])
}

///|
test "risk register JSON task arrays preserve unusual stable IDs across CSV roundtrip" {
  let d = risk_table_draft()
  let ids = [
    "semi;colon", "comma,id", "quoted\"id", "line\nbreak", "[bracket]", "界面",
  ]
  let original = {
    ..d,
    tasks: ids.map(id => { ..d.tasks[0], id, }),
    risks: [{ ..d.risks[0], tasks: ids, }],
  }
  let csv = @plan_workbench.export_risk_table(original)
  let roundtrip = @plan_workbench.preview_risk_table(original, csv, false)
  assert_eq(roundtrip.draft, original)
  assert_eq(roundtrip.changes, [])
  let cleared = @plan_workbench.preview_risk_table(
    original, "id,tasks\nrisk,[]", false,
  )
  assert_eq(cleared.draft.risks[0].tasks, [])
}

///|
test "risk register rejects malformed records and references atomically" {
  let original = risk_table_draft()
  for
    source in [
      "id,summary\nrisk,Changed\nnew,Missing new fields", "id,summary,severity\nnew,New,low",
      "id,summary,owner\nnew,New,alex", "id,severity,owner\nnew,low,alex", "id,summary\nrisk,Changed\nrisk,Again",
      "id,Status\nrisk,Resolved", "summary\nNo ID", "id,title,summary\nrisk,A,B",
      "id,summary\nrisk,", "id,owner\nrisk,", "id,owner\nrisk,nobody", "id,severity\nrisk,",
      "id,severity\nrisk,urgent", "id,severity\nrisk,High", "id,tasks\nrisk,unknown",
      "id,tasks\nrisk,T1;T1", "id,tasks\nrisk,[1]", "id,tasks\nrisk,[broken]", "id,summary\nrisk,Too,many",
      "id,summary\nrisk,\"unclosed", "id,summary\nrisk,\"closed\"junk", "id,summary\n,No ID",
      "id,summary\n",
    ] {
    try @plan_workbench.preview_risk_table(original, source, false) catch {
      @plan_workbench.Invalid(message) => assert_false(message.is_empty())
    } noraise {
      _ => fail("Should reject: " + source)
    }
    assert_eq(original, risk_table_draft())
  }
  let duplicate_risks = {
    ..original,
    risks: [original.risks[0], original.risks[0]],
  }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        duplicate_risks, "id,summary\nrisk,Changed", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let padded = { ..original, risks: [{ ..original.risks[0], id: " risk ", }], }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        padded, "id,summary\nrisk,Changed", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let duplicate_tasks = {
    ..original,
    tasks: [original.tasks[0], original.tasks[0]],
  }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        duplicate_tasks, "id,tasks\nrisk,T1", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let duplicate_names = {
    ..original,
    owners: [..original.owners, { id: "other", name: "Sam", role: "other", }],
  }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        duplicate_names, "id,owner\nrisk,Sam", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_eq(
    @plan_workbench.preview_risk_table(
      duplicate_names, "id,owner\nrisk,other", false,
    ).draft.risks[0].owner,
    "other",
  )
  let duplicate_owner_ids = {
    ..original,
    owners: [
      ..original.owners,
      { id: "sam", name: "Other", role: "duplicate", },
    ],
  }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        duplicate_owner_ids, "id,owner\nrisk,Other", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "risk register bounded tables retain existing rows at capacity" {
  let d = risk_table_draft()
  let rows = Array::makei(100, i => { ..d.risks[0], id: "R" + i.to_string(), })
  let full = { ..d, risks: rows, }
  assert_eq(
    @plan_workbench.preview_risk_table(
      full,
      @plan_workbench.export_risk_table(full),
      false,
    ).changes,
    [],
  )
  assert_eq(
    @plan_workbench.preview_risk_table(full, "id,summary\nR0,Changed", false).draft.risks.length(),
    100,
  )
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        full, "id,summary,severity,owner\nnew,New,low,alex", false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let too_many = { ..full, risks: [..rows, { ..d.risks[0], id: "extra", }], }
  assert_true(
    (Ok(
      @plan_workbench.preview_risk_table(
        d,
        @plan_workbench.export_risk_table(too_many),
        false,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@plan_workbench.preview_risk_table(d, "x".repeat(1000001), false)) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "risk register edits project through the existing native request wire contract" {
  let original = risk_table_draft()
  let d = @plan_workbench.preview_risk_table(
      original, "id,summary,severity,owner,mitigation,tasks\nrisk,Revised,critical,sam,Backup plan,T1;T3\nnew,New,low,alex,Monitor,",
      false,
    ).draft
  let request = @plan_workbench.request(
    d,
    "alex",
    { "project_id": d.project_id },
    "source-fixture",
    "digest-fixture",
  )
  let risks = @plan_workbench.items(request, "risks")
  assert_eq(risks.length(), 3)
  assert_eq(@plan_workbench.text(risks[0], "risk_id"), "risk")
  assert_eq(@plan_workbench.text(risks[0], "mitigation"), "Backup plan")
  assert_eq(@plan_workbench.text(risks[0], "severity"), "critical")
  assert_eq(@plan_workbench.text(risks[0], "owner_id"), "sam")
  assert_eq(
    @plan_workbench.field(risks[0], "related_task_ids"),
    ToJson::to_json(["T1", "T3"]),
  )
  assert_eq(
    @plan_workbench.field(risks[2], "related_task_ids"),
    ToJson::to_json(([] : Array[String])),
  )
  assert_eq(@plan_workbench.text(request, "plan_request_id"), original.key)
}
