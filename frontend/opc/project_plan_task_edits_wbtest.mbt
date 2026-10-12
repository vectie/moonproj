///|
fn task_edits_fixture() -> Model {
  let model = plan_test_model()
  {
    ..model,
    plan: {
      ..model.plan,
      prepared: Some({ "fixture": "previous prepared result" }),
      phase: "prepared",
      task_table: "id,title,cost,Status\ntask-review,\"Review <script>界面\nSecond line\",275.50,Done",
    },
  }
}

///|
test "task table update UI previews applies persists exports and prepares edited source" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = task_edits_fixture()
  assert_true(
    plan_store(
      "owner-test",
      "company-actual",
      original.plan.draft.unwrap().to_json().stringify(),
    ),
  )
  let stored = plan_restore("owner-test", "company-actual")
  let (_, previewed) = plan_update(_ => none, TaskEdits(Preview), original)
  assert_eq(previewed.plan.draft, original.plan.draft)
  assert_eq(previewed.plan.prepared, original.plan.prepared)
  assert_eq(previewed.plan.revision, original.plan.revision)
  assert_eq(previewed.plan.phase, original.plan.phase)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(previewed.plan.task_edits.unwrap().preview.changes.length(), 1)
  let html = products_test_html(previewed)
  assert_true(html.contains("现有任务修改预览"))
  assert_true(html.contains("Before / 修改前"))
  assert_true(html.contains("After / 修改后"))
  assert_true(html.contains("Review &lt;script&gt;界面"))
  assert_true(html.contains("忽略的列：Status"))
  assert_eq(plan_test_requests(), "[]")
  let (_, edited) = plan_update(_ => none, TaskEdits(Apply), previewed)
  let draft = edited.plan.draft.unwrap()
  assert_eq(draft.tasks[0], original.plan.draft.unwrap().tasks[0])
  assert_eq(draft.tasks[1].name, "Review <script>界面\nSecond line")
  assert_eq(draft.tasks[1].dependencies, ["task-design"])
  assert_eq(draft.tasks[1].cost, "275.50")
  assert_eq(edited.plan.prepared, None)
  assert_eq(edited.plan.revision, original.plan.revision + 1)
  assert_eq(edited.plan.task_edits, None)
  assert_eq(edited.plan.task_table, original.plan.task_table)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, draft)
  let (_, repeated) = plan_update(_ => none, TaskEdits(Apply), edited)
  assert_eq(repeated.plan, edited.plan)
  let (_, exported) = plan_update(_ => none, ExportTasks, edited)
  assert_eq(exported.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one CSV download")
  }
  let csv = products_text(download, "text")
  assert_eq(csv, @plan_workbench.export_task_table(draft))
  assert_eq(
    @plan_workbench.preview_task_table_updates(draft, csv, false).changes,
    [],
  )
  assert_eq(plan_test_requests(), "[]")
  ignore(
    plan_test_file(
      "task-edits-before.json",
      original.plan.draft.unwrap().to_json().stringify(indent=2),
    ),
  )
  ignore(plan_test_file("task-edits-input.csv", original.plan.task_table))
  ignore(plan_test_file("task-edits-preview.html", html))
  ignore(
    plan_test_file("task-edits-after.json", draft.to_json().stringify(indent=2)),
  )
  ignore(plan_test_file("task-edits-output.csv", csv))
  let (prepare, saving) = plan_update(_ => none, Prepare, edited)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare request")
  }
  assert_eq(@json.parse(products_text(request, "body")), draft.to_json())
}

///|
test "task table update preview cancels and invalidates on draft input format and scope changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, previewed) = plan_update(
    _ => none,
    TaskEdits(Preview),
    task_edits_fixture(),
  )
  for
    action in [
      TaskEdits(Close),
      Edit("task", "task-design", "name", "New design"),
      Edit("task-table", "", "source", "id,title\ntask-review,Other"),
      TaskTableFormat(true),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, previewed)
    assert_eq(changed.plan.task_edits, None)
    let (_, after) = plan_update(_ => none, TaskEdits(Apply), changed)
    assert_eq(after.plan, changed.plan)
  }
  let (_, changed_actor) = plan_update(_ => none, TaskEdits(Apply), {
    ..previewed,
    dispatch_task_actor_id: "other",
  })
  assert_eq(changed_actor.plan.task_edits, None)
  assert_eq(changed_actor.plan.draft, None)
  let draft = previewed.plan.draft.unwrap()
  let stale = {
    ..previewed,
    plan: { ..previewed.plan, draft: Some({ ..draft, notes: "new source", }), },
  }
  let (_, after) = plan_update(_ => none, TaskEdits(Apply), stale)
  assert_eq(after.plan.draft, stale.plan.draft)
  assert_eq(after.plan.revision, stale.plan.revision)
  assert_eq(after.plan.task_edits, None)
}

///|
test "failed and no-op task table previews preserve prepared source and storage" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = task_edits_fixture()
  let (_, previewed) = plan_update(_ => none, TaskEdits(Preview), original)
  let invalid = {
    ..previewed,
    plan: { ..previewed.plan, task_table: "id,title\nunknown,New", },
  }
  let (_, failed) = plan_update(_ => none, TaskEdits(Preview), invalid)
  assert_eq(failed.plan.task_edits, None)
  assert_eq(failed.plan.draft, original.plan.draft)
  assert_eq(failed.plan.prepared, original.plan.prepared)
  assert_eq(failed.plan.revision, original.plan.revision)
  assert_eq(failed.plan.task_table, invalid.plan.task_table)
  let same = {
    ..original,
    plan: {
      ..original.plan,
      task_table: @plan_workbench.export_task_table(
        original.plan.draft.unwrap(),
      ),
    },
  }
  let (_, no_change) = plan_update(_ => none, TaskEdits(Preview), same)
  assert_eq(no_change.plan.task_edits.unwrap().preview.changes, [])
  let (_, applied) = plan_update(_ => none, TaskEdits(Apply), no_change)
  assert_eq(applied.plan, no_change.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  assert_eq(plan_test_requests(), "[]")
}
