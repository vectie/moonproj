///|
fn rebase_fixture() -> @plan_workbench.Draft {
  let d = table_draft()
  let m = d.milestones[0]
  {
    ..d,
    milestones: [
      { ..m, id: "kickoff", date: "2028-02-28", },
      { ..m, id: "review", name: "Independent review", date: "2028-03-01", },
      { ..m, id: "release", name: "Release", date: "2028-03-10", },
      { ..m, id: "later", name: "Unscheduled follow-up", date: "  ", },
    ],
  }
}

///|
test "rebase crosses leap day preserves intervals blanks identities and every other field" {
  let source = rebase_fixture()
  let bytes = ToJson::to_json(source).stringify()
  let rebased = @plan_workbench.rebase_milestones(
    source, "kickoff", "2028-03-02",
  )
  assert_eq(rebased.offset_days, 3L)
  assert_eq(rebased.draft.milestones.map(m => m.date), [
    "2028-03-02", "2028-03-04", "2028-03-13", "  ",
  ])
  assert_eq(rebased.draft, {
    ..source,
    milestones: source.milestones.mapi((i, m) => {
      ..m,
      date: rebased.draft.milestones[i].date,
    }),
  })
  assert_eq(ToJson::to_json(source).stringify(), bytes)
  let reverse = @plan_workbench.rebase_milestones(
    rebased.draft,
    "review",
    "2028-03-01",
  )
  assert_eq(reverse.offset_days, -3L)
  assert_eq(reverse.draft, source)
  assert_eq(
    @plan_workbench.rebase_milestones(source, "review", "2028-03-01").draft,
    source,
  )
}

///|
test "rebase works backwards and across century calendar boundaries" {
  let source = rebase_fixture()
  for date in ["0001-01-01", "9999-12-31"] {
    let single = { ..source, milestones: [source.milestones[0]], }
    assert_eq(
      @plan_workbench.rebase_milestones(single, "kickoff", date).draft.milestones[0].date,
      date,
    )
  }
  let dates = {
    ..source,
    milestones: [
      { ..source.milestones[0], date: "2100-03-01", },
      { ..source.milestones[1], date: "2100-03-02", },
    ],
  }
  let moved = @plan_workbench.rebase_milestones(dates, "kickoff", "2099-12-31")
  assert_eq(moved.offset_days, -60L)
  assert_eq(moved.draft.milestones.map(m => m.date), [
    "2099-12-31", "2100-01-01",
  ])
  let leap = {
    ..source,
    milestones: [
      { ..source.milestones[0], date: "2000-02-28", },
      { ..source.milestones[1], date: "2000-03-01", },
    ],
  }
  assert_eq(
    @plan_workbench.rebase_milestones(leap, "kickoff", "2000-02-29").draft.milestones[1].date,
    "2000-03-02",
  )
}

///|
test "rebase rejects invalid input and shifted overflow atomically" {
  let source = rebase_fixture()
  let bytes = ToJson::to_json(source).stringify()
  for
    date in [
      "", "2026-02-29", "2100-02-29", "2028-13-01", "2028-02-30", "2028-2-29", " 2028-03-01",
      "0000-01-01", "10000-01-01",
    ] {
    assert_true(
      (try Ok(@plan_workbench.rebase_milestones(source, "kickoff", date)) catch { e => Err(e) })
      is Err(_),
    )
  }
  for anchor in ["missing", "", "later"] {
    assert_true(
      (try Ok(@plan_workbench.rebase_milestones(source, anchor, "2028-03-02")) catch { e => Err(e) })
      is Err(_),
    )
  }
  let invalid = {
    ..source,
    milestones: [
      source.milestones[0],
      { ..source.milestones[1], date: "broken", },
    ],
  }
  assert_true(
    (try Ok(@plan_workbench.rebase_milestones(invalid, "kickoff", "2028-03-02")) catch { e => Err(e) })
    is Err(@plan_workbench.Invalid(message)) &&
    message.contains("review"),
  )
  let duplicate = {
    ..source,
    milestones: [source.milestones[0], source.milestones[0]],
  }
  assert_true(
    (try Ok(@plan_workbench.rebase_milestones(duplicate, "kickoff", "2028-03-02")) catch { e => Err(e) })
    is Err(_),
  )
  assert_true(
    (try Ok(@plan_workbench.rebase_milestones(
      { ..source, milestones: [], },
      "kickoff",
      "2028-03-02",
    )) catch { e => Err(e) })
    is Err(_),
  )
  assert_true(
    (try Ok(@plan_workbench.rebase_milestones(
      { ..source, milestones: Array::make(41, source.milestones[0]), },
      "kickoff",
      "2028-03-02",
    )) catch { e => Err(e) })
    is Err(_),
  )
  for
    (anchor_date, other_date, new_date) in [
      ("9999-12-30", "9999-12-31", "9999-12-31"),
      ("0001-01-02", "0001-01-01", "0001-01-01"),
    ] {
    let edge = {
      ..source,
      milestones: [
        { ..source.milestones[0], date: anchor_date, },
        { ..source.milestones[1], date: other_date, },
      ],
    }
    let before = ToJson::to_json(edge).stringify()
    assert_true(
      (try Ok(@plan_workbench.rebase_milestones(edge, "kickoff", new_date)) catch { e => Err(e) })
      is Err(_),
    )
    assert_eq(ToJson::to_json(edge).stringify(), before)
  }
  assert_eq(ToJson::to_json(source).stringify(), bytes)
}
