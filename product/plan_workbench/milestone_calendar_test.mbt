///|
fn calendar_unfold(value : String) -> String {
  value.replace_all(old="\r\n ", new="")
}

///|
test "milestone calendar retains authored dates and task context without scheduling tasks" {
  let initial = table_draft()
  let draft = {
    ..initial,
    milestones: [
      { ..initial.milestones[0], date: "2028-02-29", },
      {
        ..initial.milestones[0],
        id: "review",
        name: "Review",
        date: "2028-03-12",
      },
    ],
    tasks: [
      {
        id: "DESIGN-1",
        name: "Design",
        owner: "alex",
        milestone: "release",
        cost: "10",
        dependencies: [],
      },
      {
        id: "REVIEW-2",
        name: "Inspect",
        owner: "alex",
        milestone: "review",
        cost: "0",
        dependencies: ["DESIGN-1"],
      },
    ],
  }
  let before = ToJson::to_json(draft).stringify()
  let output = @plan_workbench.export_milestone_calendar(draft, "Launch")
  let unfolded = calendar_unfold(output)
  assert_true(output.has_prefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
  assert_true(output.has_suffix("END:VCALENDAR\r\n"))
  assert_eq(unfolded.split("BEGIN:VEVENT").count(), 3)
  assert_true(unfolded.contains("DTSTART;VALUE=DATE:20280229\r\n"))
  assert_true(unfolded.contains("DTSTART;VALUE=DATE:20280312\r\n"))
  assert_true(unfolded.contains("DTSTAMP:20261008T000000Z\r\n"))
  assert_true(unfolded.contains("Owner: Alex [alex]"))
  assert_true(unfolded.contains("Acceptance criteria:\\nWorks"))
  assert_true(unfolded.contains("Required evidence:\\nTests"))
  assert_true(
    unfolded.contains(
      "Inspect [REVIEW-2] | owner: Alex [alex] | prerequisites: DESIGN-1",
    ),
  )
  for
    absent in [
      "STATUS:", "DTEND", "DURATION", "VALARM", "ATTENDEE", "ORGANIZER", "METHOD:",
      "PERCENT-COMPLETE",
    ] {
    assert_false(unfolded.contains(absent))
  }
  assert_eq(unfolded.split("TRANSP:TRANSPARENT\r\n").count(), 3)
  assert_eq(ToJson::to_json(draft).stringify(), before)
  assert_eq(@plan_workbench.export_milestone_calendar(draft, "Launch"), output)
}

///|
test "calendar escapes content and folds Unicode at UTF8 octets" {
  let initial = table_draft()
  let draft = {
    ..initial,
    milestones: [
      {
        ..initial.milestones[0],
        name: "界😀".repeat(40) + ",review;\\plan",
        criteria: "One\r\nTwo\rBEGIN:VEVENT\nBEGIN:VALARM",
      },
    ],
  }
  let output = @plan_workbench.export_milestone_calendar(draft, "Demo, Inc;")
  for line in output.split("\r\n") {
    assert_true(@utf8.encode(line).length() <= 75)
    assert_false(line.contains("\n") || line.contains("\r"))
  }
  let unfolded = calendar_unfold(output)
  assert_true(unfolded.contains("界😀".repeat(40) + "\\,review\\;\\\\plan"))
  assert_true(unfolded.contains("Demo\\, Inc\\;"))
  assert_true(unfolded.contains("One\\nTwo\\nBEGIN:VEVENT\\nBEGIN:VALARM"))
  assert_eq(unfolded.split("\r\nBEGIN:VEVENT\r\n").count(), 2)
}

///|
test "calendar identity is stable across edits and separated by project and milestone" {
  let original = table_draft()
  fn uid(draft : @plan_workbench.Draft) -> String raise {
    calendar_unfold(@plan_workbench.export_milestone_calendar(draft, "Project"))
    .split("\r\n")
    .filter(line => line.has_prefix("UID:"))
    .collect()[0].to_owned()
  }
  let changed = {
    ..original,
    key: "new-key",
    milestones: [
      { ..original.milestones[0], name: "Renamed", date: "2030-01-01", },
    ],
  }
  assert_eq(uid(original), uid(changed))
  assert_false(
    uid(original) == uid({ ..original, project_id: "other-project", }),
  )
  assert_false(
    uid(original) ==
    uid({
      ..original,
      milestones: [{ ..original.milestones[0], id: "other-milestone", }],
    }),
  )
  let one = {
    ..original,
    project_id: "a-b",
    milestones: [{ ..original.milestones[0], id: "c", }],
  }
  let two = {
    ..original,
    project_id: "a",
    milestones: [{ ..original.milestones[0], id: "b-c", }],
  }
  assert_false(uid(one) == uid(two))
  assert_false(
    uid({ ..original, project_id: "a\nb", }) ==
    uid({ ..original, project_id: "a\r\nb", }),
  )
}

///|
test "calendar export rejects incomplete calendar inputs atomically" {
  let draft = table_draft()
  for
    date in [
      "", "2026-2-01", "2026-02-29", "2026-04-31", "2026-13-01", "2026-01-00", "2026-01-01\nBEGIN:VEVENT",
    ] {
    assert_true(
      (Ok(
        @plan_workbench.export_milestone_calendar(
          { ..draft, milestones: [{ ..draft.milestones[0], date, }], },
          "Demo",
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for
    prepared_at in [
      "", "2026-10-08T00:00:00+00:00", "2026-02-29T00:00:00Z", "2026-10-08T25:00:00Z",
    ] {
    assert_true(
      (Ok(
        @plan_workbench.export_milestone_calendar(
          { ..draft, prepared_at, },
          "Demo",
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for
    invalid in [
      { ..draft, milestones: [], },
      { ..draft, milestones: [draft.milestones[0], draft.milestones[0]], },
      { ..draft, milestones: [{ ..draft.milestones[0], owner: "missing", }], },
      { ..draft, milestones: [{ ..draft.milestones[0], name: "\u0000", }], },
      {
        ..draft,
        tasks: [
          {
            id: "orphan",
            name: "Task",
            owner: "alex",
            milestone: "missing",
            cost: "0",
            dependencies: [],
          },
        ],
      },
    ] {
    assert_true(
      (Ok(@plan_workbench.export_milestone_calendar(invalid, "Demo")) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}
