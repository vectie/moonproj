///|
fn milestone_import_fixture() -> Model {
  let model = plan_test_model()
  let draft = { ..model.plan.draft.unwrap(), milestones: [], tasks: [], }
  let (_, mode) = plan_update(_ => none, MilestoneTable(ImportMode(true)), {
    ..model,
    plan: {
      ..model.plan,
      draft: Some(draft),
      prepared: Some({ "fixture": "previous result" }),
      phase: "prepared",
    },
  })
  let (_, input) = plan_update(
    _ => none,
    MilestoneTable(
      Text(
        "id,title,owner,date,criteria,evidence,Status\nroadmap-alpha,\"Launch <script>, \"\"界面\"\"\",owner-test,2028-02-29,\"First\nSecond\",\"Artifact\nReview\",Done\nroadmap-beta,Follow-up,owner-test,2028-03-04,Questions,Response,Accepted",
      ),
    ),
    mode,
  )
  input
}

///|
test "new milestone UI import previews adds then task CSV exports reopens and explicitly prepares" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = milestone_import_fixture()
  let before = original.plan.draft.unwrap()
  assert_true(
    plan_store(
      original.plan.actor,
      original.plan.selected,
      ToJson::to_json(before).stringify(),
    ),
  )
  let stored = plan_restore(original.plan.actor, original.plan.selected)
  let (_, preview) = plan_update(_ => none, MilestoneTable(Preview), original)
  assert_eq(preview.plan.draft, original.plan.draft)
  assert_eq(preview.plan.prepared, original.plan.prepared)
  assert_eq(preview.plan.revision, original.plan.revision)
  assert_eq(preview.plan.phase, original.plan.phase)
  assert_eq(plan_restore(original.plan.actor, original.plan.selected), stored)
  let html = products_test_html(preview)
  assert_true(html.contains("Import new milestones"))
  assert_true(html.contains("New milestone preview"))
  assert_true(html.contains("Apply new milestones"))
  assert_true(html.contains("Launch &lt;script&gt;"))
  assert_true(html.contains("Ignored columns: Status"))
  let (_, applied) = plan_update(_ => none, MilestoneTable(Apply), preview)
  let imported = applied.plan.draft.unwrap()
  assert_eq(imported.milestones.map(m => m.id), [
    "roadmap-alpha", "roadmap-beta",
  ])
  assert_eq(imported.tasks, before.tasks)
  assert_eq(imported.owners, before.owners)
  assert_eq(applied.plan.prepared, None)
  assert_eq(applied.plan.revision, original.plan.revision + 1)
  assert_eq(applied.plan.milestone_table.import_preview, None)
  assert_true(imported.key != before.key)
  let (_, repeated) = plan_update(_ => none, MilestoneTable(Apply), applied)
  assert_eq(repeated.plan, applied.plan)
  let (_, repreview) = plan_update(_ => none, MilestoneTable(Preview), applied)
  assert_eq(repreview.plan.milestone_table.import_preview.unwrap().additions, [])
  assert_eq(repreview.plan.milestone_table.import_preview.unwrap().unchanged, [
    "roadmap-alpha", "roadmap-beta",
  ])
  let (_, no_op) = plan_update(_ => none, MilestoneTable(Apply), repreview)
  assert_eq(no_op.plan, repreview.plan)
  let task_csv = "id,title,owner,milestone,cost,dependencies\nroadmap-work,Prepare,owner-test,roadmap-alpha,1.25,\nroadmap-check,Review,owner-test,roadmap-beta,2.75,roadmap-work"
  let (_, task_input) = plan_update(
    _ => none,
    Edit("task-table", "", "source", task_csv),
    applied,
  )
  let (_, tasks) = plan_update(_ => none, ImportTasks, task_input)
  let draft = tasks.plan.draft.unwrap()
  assert_eq(draft.tasks.map(t => t.milestone), ["roadmap-alpha", "roadmap-beta"])
  assert_eq(draft.tasks[1].dependencies, ["roadmap-work"])
  let (export, _) = plan_update(_ => none, MilestoneTable(Export), tasks)
  drafts_test_execute(export)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one roadmap CSV")
  }
  assert_eq(
    products_text(download, "text"),
    @plan_workbench.export_milestone_table(draft),
  )
  assert_eq(plan_test_requests(), "[]")
  let (_, other) = plan_update(_ => none, Choose("company-second"), tasks)
  let (_, reopened) = plan_update(_ => none, Choose("company-actual"), other)
  assert_eq(reopened.plan.draft, Some(draft))
  assert_eq(reopened.plan.milestone_table, plan_milestone_table_initial())
  let (prepare, saving) = plan_update(_ => none, Prepare, reopened)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit native request")
  }
  assert_eq(@json.parse(products_text(request, "body")), ToJson::to_json(draft))
  ignore(
    plan_test_file(
      "milestone-import-before.json",
      ToJson::to_json(before).stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file(
      "milestone-import-input.csv",
      original.plan.milestone_table.text,
    ),
  )
  ignore(plan_test_file("milestone-import-preview.html", html))
  ignore(plan_test_file("milestone-import-tasks.csv", task_csv))
  ignore(
    plan_test_file(
      "milestone-import-after.json",
      ToJson::to_json(draft).stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file(
      "milestone-import-output.csv",
      products_text(download, "text"),
    ),
  )
  ignore(
    plan_test_file(
      "milestone-import-prepare-request.json",
      products_text(request, "body"),
    ),
  )
}

///|
test "new milestone UI cancel mode and scope changes discard staged additions" {
  plan_test_browser()
  defer plan_test_cleanup()
  let input = milestone_import_fixture()
  let (_, preview) = plan_update(_ => none, MilestoneTable(Preview), input)
  for
    action in [
      MilestoneTable(Close),
      MilestoneTable(ImportMode(false)),
      MilestoneTable(Text("id,title,owner\nnew,New,owner-test")),
      MilestoneTable(Format(true)),
      Edit("plan", "", "notes", "Changed context"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    assert_eq(changed.plan.milestone_table.import_preview, None)
    let (_, apply) = plan_update(_ => none, MilestoneTable(Apply), changed)
    assert_eq(apply.plan, changed.plan)
  }
  let (_, closed) = plan_update(_ => none, MilestoneTable(Close), preview)
  assert_eq(closed.plan.draft, input.plan.draft)
  assert_eq(closed.plan.prepared, input.plan.prepared)
  assert_eq(closed.plan.milestone_table.text, input.plan.milestone_table.text)
  let (_, actor) = plan_update(_ => none, MilestoneTable(Apply), {
    ..preview,
    dispatch_task_actor_id: "other",
  })
  assert_eq(actor.plan.draft, None)
  let stale = {
    ..preview,
    plan: {
      ..preview.plan,
      draft: Some({ ..preview.plan.draft.unwrap(), notes: "different", }),
    },
  }
  let (_, refused) = plan_update(_ => none, MilestoneTable(Apply), stale)
  assert_eq(refused.plan.draft, stale.plan.draft)
  assert_eq(refused.plan.milestone_table.import_preview, None)
  assert_true(refused.plan.milestone_table.note.contains("draft changed"))
  assert_eq(plan_test_requests(), "[]")
}

///|
test "new milestone UI errors retain input and prior prepared result and storage warning is honest" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = milestone_import_fixture()
  let (_, bad) = plan_update(
    _ => none,
    MilestoneTable(Text("id,title,owner,date\nnew,New,owner-test,2027-02-29")),
    original,
  )
  let (_, failed) = plan_update(_ => none, MilestoneTable(Preview), bad)
  assert_eq(failed.plan.draft, original.plan.draft)
  assert_eq(failed.plan.prepared, original.plan.prepared)
  assert_eq(failed.plan.milestone_table.text, bad.plan.milestone_table.text)
  assert_eq(failed.plan.milestone_table.import_preview, None)
  assert_true(failed.plan.milestone_table.note.contains("invalid date"))
  let (_, preview) = plan_update(_ => none, MilestoneTable(Preview), original)
  checklist_test_storage_failure()
  let (_, applied) = plan_update(_ => none, MilestoneTable(Apply), preview)
  assert_eq(applied.plan.draft.unwrap().milestones.length(), 2)
  assert_true(applied.plan.note.contains("浏览器存储不可用"))
  assert_eq(plan_restore(original.plan.actor, original.plan.selected), "")
  assert_eq(applied.plan.milestone_table.import_preview, None)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "new milestone UI saved history and template replacement reset import state" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, preview) = plan_update(
    _ => none,
    MilestoneTable(Preview),
    milestone_import_fixture(),
  )
  let (_, source) = plan_update(
    _ => none,
    Template(
      Source(@plan_workbench.export_template(plan_template_test_draft())),
    ),
    preview,
  )
  let (_, template) = plan_update(_ => none, Template(Preview), source)
  let (_, mapped) = plan_update(_ => none, Template(Owner("owner-1")), template)
  let (_, replaced) = plan_update(_ => none, Template(Apply), mapped)
  assert_eq(replaced.plan.milestone_table, plan_milestone_table_initial())
  let draft = { ..plan_test_draft(), key: "saved-roadmap", }
  let saved = plan_compare_test_saved(draft)
  let (_, opening) = plan_update(_ => none, Open(draft.key), preview)
  let (_, opened) = plan_update(
    _ => none,
    Read(
      "owner-test",
      opening.plan.epoch,
      opening.plan.revision,
      draft.key,
      "",
      200,
      saved.stringify(),
    ),
    opening,
  )
  assert_eq(opened.plan.draft, Some(draft))
  assert_eq(opened.plan.milestone_table, plan_milestone_table_initial())
  let (_, cannot_apply) = plan_update(_ => none, MilestoneTable(Apply), opened)
  assert_eq(cannot_apply.plan, opened.plan)
  assert_eq(plan_test_requests(), "[]")
}
