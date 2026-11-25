///|
test "calendar export uses the current edited draft without changing saved plan or storage" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = plan_test_model()
  let (_, edited) = plan_update(
    _ => none,
    Edit("milestone", "milestone-one", "date", "2028-02-29"),
    original,
  )
  let stored = plan_restore("owner-test", "company-actual")
  let before = edited.plan
  let html = products_test_html(edited)
  assert_true(html.contains("下载里程碑日历 (.ics)"))
  ignore(plan_test_file("calendar-workbench.html", html))
  let (cmd, after) = plan_update(_ => none, ExportCalendar, edited)
  drafts_test_execute(cmd)
  assert_eq(after.plan, before)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(plan_test_requests(), "[]")
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one download expected")
  }
  assert_eq(products_text(download, "name"), "plan-milestones.ics")
  assert_eq(products_text(download, "type"), "text/calendar;charset=utf-8")
  let expected = @plan_workbench.export_milestone_calendar(
    edited.plan.draft.unwrap(),
    "Synthetic test project",
  )
  assert_eq(products_text(download, "text"), expected)
  assert_true(expected.contains("DTSTART;VALUE=DATE:20280229"))
  ignore(
    plan_test_file(
      "calendar-input.json",
      ToJson::to_json(edited.plan.draft.unwrap()).stringify(),
    ),
  )
  ignore(plan_test_file("plan-milestones.ics", products_text(download, "text")))
  let (again, unchanged) = plan_update(_ => none, ExportCalendar, after)
  drafts_test_execute(again)
  assert_eq(unchanged.plan, before)
  guard @json.parse(plan_test_downloads()) is Array(downloads) else {
    fail("downloads expected")
  }
  assert_eq(downloads.length(), 2)
  assert_eq(products_text(downloads[1], "text"), expected)
  let prepared = {
    ..after,
    plan: {
      ..after.plan,
      prepared: Some({ "immutable_saved_version": "retained" }),
      phase: "prepared",
    },
  }
  let (from_prepared, still_prepared) = plan_update(
    _ => none,
    ExportCalendar,
    prepared,
  )
  drafts_test_execute(from_prepared)
  assert_eq(still_prepared.plan, prepared.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
}

///|
test "invalid calendar dates report a repair and scope changes prevent old draft downloads" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, invalid) = plan_update(
    _ => none,
    Edit("milestone", "milestone-one", "date", "2026-02-29"),
    model,
  )
  let (cmd, failed) = plan_update(_ => none, ExportCalendar, invalid)
  assert_eq(products_test_effect_count(cmd), 0)
  assert_eq(failed.plan.draft, invalid.plan.draft)
  assert_eq(failed.plan.revision, invalid.plan.revision)
  assert_true(failed.plan.note.contains("invalid target date"))
  assert_eq(plan_test_downloads(), "[]")
  let (_, switched) = plan_update(_ => none, Choose("company-second"), model)
  let (no_milestones, _) = plan_update(_ => none, ExportCalendar, switched)
  assert_eq(products_test_effect_count(no_milestones), 0)
  let (other_actor, _) = plan_update(_ => none, ExportCalendar, {
    ..model,
    dispatch_task_actor_id: "different",
  })
  assert_eq(products_test_effect_count(other_actor), 0)
  assert_eq(plan_test_downloads(), "[]")
}
