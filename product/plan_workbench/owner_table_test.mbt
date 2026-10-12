///|
test "owner roster adds and updates stable identities without changing assigned work" {
  let original = update_table_draft()
  let result = @plan_workbench.preview_owner_table(
    original, "Owner ID,Display name,Responsibility,Status\r\nnew-id,Sam,\"Reviewer\nBackup\",Active\r\nalex,\"  Alex, \"\"界面\"\"  \",Design lead,Admin\r\n",
    false,
  )
  assert_eq(result.ignored, ["Status"])
  assert_eq(result.changes.map(c => c.after.id), ["alex", "new-id"])
  assert_eq(result.changes[0].fields, ["name", "role"])
  assert_eq(result.changes[1].before, None)
  assert_eq(result.draft.owners.map(o => o.id), ["alex", "sam", "new-id"])
  assert_eq(result.draft.owners[0].name, "  Alex, \"界面\"  ")
  assert_eq(result.draft.owners[1], original.owners[1])
  assert_eq(result.draft.owners[2].role, "Reviewer\nBackup")
  assert_eq(result.draft.owners[2].name, result.draft.owners[1].name)
  assert_eq({ ..result.draft, owners: original.owners, }, original)
  assert_eq(original, update_table_draft())
  let csv = @plan_workbench.export_owner_table(result.draft)
  let roundtrip = @plan_workbench.preview_owner_table(result.draft, csv, false)
  assert_eq(roundtrip.draft, result.draft)
  assert_eq(roundtrip.changes, [])
  let request = @plan_workbench.request(
    result.draft,
    "alex",
    {},
    "source",
    "digest",
  )
  let roster = @plan_workbench.items(request, "owners")
  assert_eq(
    @plan_workbench.text(roster[0], "display_name"),
    result.draft.owners[0].name,
  )
  assert_eq(@plan_workbench.text(roster[2], "role"), "Reviewer\nBackup")
  assert_eq(
    @plan_workbench.text(@plan_workbench.items(request, "tasks")[0], "owner_id"),
    "alex",
  )
}

///|
test "owner roster TSV partial updates clear explicit role and retain missing fields" {
  let original = update_table_draft()
  let result = @plan_workbench.preview_owner_table(
    original, "\u{FEFF}id\trole\r\n alex \t\r\nsam\t\"Peer\treviewer\nSecond line\"\r\n",
    true,
  )
  assert_eq(result.draft.owners[0], { ..original.owners[0], role: "", })
  assert_eq(result.draft.owners[1], {
    ..original.owners[1],
    role: "Peer\treviewer\nSecond line",
  })
  assert_eq(result.changes.map(c => c.fields), [["role"], ["role"]])
  let empty = { ..original, owners: [], }
  let seeded = @plan_workbench.preview_owner_table(
    empty, "id,name,role\nnew,Name,", false,
  )
  assert_eq(seeded.draft.owners, [{ id: "new", name: "Name", role: "", }])
  let incomplete = {
    ..original,
    owners: [{ id: "alex", name: "", role: "", }],
  }
  assert_eq(
    @plan_workbench.preview_owner_table(
      incomplete, "id,role\nalex,Writer", false,
    ).draft.owners[0].name,
    "",
  )
}

///|
test "owner roster rejects invalid input atomically and does not match by name" {
  let original = update_table_draft()
  for
    source in [
      "id,name\nunknown,New", "id,role\nunknown,Reviewer", "id,name,role\n,New,Writer",
      "id,name\nalex,Changed\nalex,Again", "id,name\nalex,Changed\n alex ,Again",
      "id,name\nalex, ", "id,status\nalex,Active", "name,role\nNew,Writer", "id,name,display_name\nalex,A,B",
      "id,name\nalex,Too,many", "id,name\nalex,\"unclosed", "id,name\nalex,\"closed\"junk",
      "id,name\n",
    ] {
    assert_true(
      (try? @plan_workbench.preview_owner_table(original, source, false))
      is Err(_),
    )
    assert_eq(original, update_table_draft())
  }
  let distinct = @plan_workbench.preview_owner_table(
    original, "id,name,role\nSam,Sam,New slot", false,
  )
  assert_eq(distinct.draft.owners.map(o => o.id), ["alex", "sam", "Sam"])
  for
    owners in [
      [original.owners[0], original.owners[0]],
      [{ id: "", name: "Blank", role: "", }],
      [{ id: " alex ", name: "Padded", role: "", }],
    ] {
    assert_true(
      (try? @plan_workbench.preview_owner_table(
        { ..original, owners, },
        "id,role\nalex,Writer",
        false,
      ))
      is Err(_),
    )
  }
}

///|
test "owner roster bounds permit forty owners and reject an overflowing addition" {
  let original = update_table_draft()
  let owners : Array[@plan_workbench.Owner] = []
  for i = 0; i < 40; i = i + 1 {
    owners.push({
      id: "owner-" + i.to_string(),
      name: "Person",
      role: "Writer",
    })
  }
  let full = { ..original, owners, }
  let csv = @plan_workbench.export_owner_table(full)
  assert_eq(@plan_workbench.preview_owner_table(full, csv, false).draft, full)
  assert_true(
    (try? @plan_workbench.preview_owner_table(
      full, "id,name,role\nextra,New,Reviewer", false,
    ))
    is Err(_),
  )
  assert_true(
    (try? @plan_workbench.preview_owner_table(
      original,
      csv + "extra,New,Reviewer\n",
      false,
    ))
    is Err(_),
  )
  assert_true(
    (try? @plan_workbench.preview_owner_table(
      original,
      "x".repeat(1000001),
      false,
    ))
    is Err(_),
  )
}
