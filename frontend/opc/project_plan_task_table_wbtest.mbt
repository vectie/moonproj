///|
test "task table UI imports edits exports and prepares through existing workflow" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, model) = plan_update(
    _ => none,
    Edit("task-table", "", "owner", "owner-test"),
    model,
  )
  let (_, model) = plan_update(
    _ => none,
    Edit("task-table", "", "milestone", "milestone-one"),
    model,
  )
  let (_, model) = plan_update(
    _ => none,
    Edit(
      "task-table", "", "source", "Issue key,Summary,Depends on,Status\nAPP-3,Imported task,task-review,Open",
    ),
    model,
  )
  let (_, imported) = plan_update(_ => none, ImportTasks, model)
  let draft = imported.plan.draft.unwrap()
  assert_eq(draft.tasks.length(), 3)
  assert_eq(draft.tasks[2].owner, "owner-test")
  assert_eq(imported.plan.revision, model.plan.revision + 1)
  assert_eq(imported.plan.prepared, None)
  assert_true(imported.plan.note.contains("Status"))
  assert_eq(plan_test_requests(), "[]")
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "APP-3", "name", "Edited imported task"),
    imported,
  )
  let (_, exported) = plan_update(_ => none, ExportTasks, edited)
  assert_eq(exported.plan, edited.plan)
  assert_true(plan_test_downloads().contains("Edited imported task"))
  let (cmd, saving) = plan_update(_ => none, Prepare, edited)
  drafts_test_execute(cmd)
  assert_eq(saving.plan.phase, "saving")
  assert_true(plan_test_requests().contains("Edited imported task"))
  assert_true(plan_test_requests().contains("prepared-plans"))
}

///|
test "failed table import preserves draft prepared result revision and source for correction" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let model = {
    ..model,
    plan: {
      ..model.plan,
      prepared: Some({ "fixture": true }),
      task_table: "id,title\ntask-design,Duplicate",
      task_table_owner: "owner-test",
      task_table_milestone: "milestone-one",
    },
  }
  let (_, failed) = plan_update(_ => none, ImportTasks, model)
  assert_eq(failed.plan.draft, model.plan.draft)
  assert_eq(failed.plan.prepared, model.plan.prepared)
  assert_eq(failed.plan.revision, model.plan.revision)
  assert_eq(failed.plan.phase, model.plan.phase)
  assert_eq(failed.plan.task_table, model.plan.task_table)
  assert_true(failed.plan.note.contains("duplicate task ID"))
  assert_eq(plan_test_requests(), "[]")
}
