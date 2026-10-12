///|
fn finder_test_model() -> Model {
  let model = plan_test_model()
  let d = model.plan.draft.unwrap()
  {
    ..model,
    plan: {
      ..model.plan,
      draft: Some({
        ..d,
        owners: [
          ..d.owners,
          { id: "reviewer", name: "Test owner", role: "Independent reviewer", },
        ],
        milestones: [
          ..d.milestones,
          { ..d.milestones[0], id: "later", name: "Later", },
        ],
        tasks: [
          d.tasks[0],
          { ..d.tasks[1], owner: "reviewer", milestone: "later", },
        ],
      }),
      prepared: Some({ "fixture": "earlier prepared result" }),
      phase: "prepared",
    },
  }
}

///|
test "task finder searches filters and focuses the real editor without any draft write" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = finder_test_model()
  let d = original.plan.draft.unwrap()
  assert_true(
    plan_store("owner-test", "company-actual", d.to_json().stringify()),
  )
  let stored = plan_restore("owner-test", "company-actual")
  let (_, queried) = plan_update(
    _ => none,
    TaskFinder(Query("  ReViEw ")),
    original,
  )
  let (_, owner) = plan_update(
    _ => none,
    TaskFinder(Owner("reviewer")),
    queried,
  )
  let (_, filtered) = plan_update(
    _ => none,
    TaskFinder(Milestone("later")),
    owner,
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    filtered,
  )
  assert_eq(focused.plan.draft, original.plan.draft)
  assert_eq(focused.plan.prepared, original.plan.prepared)
  assert_eq(focused.plan.phase, original.plan.phase)
  assert_eq(focused.plan.revision, original.plan.revision)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  assert_eq(plan_task_finder_rows(focused.plan.task_finder, d), [d.tasks[1]])
  let html = products_test_html(focused)
  for
    expected in [
      "Find tasks", "Matches: 1 / 2", "Editing: task-review", "for=\"plan-task-find-query\"",
      "id=\"plan-task-find-query\"", "for=\"plan-task-find-owner\"", "id=\"plan-task-find-owner\"",
      "for=\"plan-task-find-milestone\"", "id=\"plan-task-find-milestone\"", "id=\"plan-task-task-review-name\"",
      "任务 2", "Show all task forms",
    ] {
    assert_true(html.contains(expected))
  }
  assert_false(html.contains("id=\"plan-task-task-design-name\""))
  // The existing editor still offers the hidden predecessor as a dependency.
  assert_true(html.contains("Design"))
  ignore(plan_test_file("task-finder-focused.html", html))
  assert_eq(plan_test_requests(), "[]")
}

///|
test "task finder focus survives edits that cease matching and prepares the whole persisted draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = finder_test_model()
  let (_, searched) = plan_update(
    _ => none,
    TaskFinder(Query("Review")),
    original,
  )
  let (_, searched) = plan_update(
    _ => none,
    TaskFinder(Owner("reviewer")),
    searched,
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    searched,
  )
  let (_, named) = plan_update(
    _ => none,
    Edit("task", "task-review", "name", "Deliver <script>界面, \"new\""),
    focused,
  )
  let (_, reassigned) = plan_update(
    _ => none,
    Edit("task", "task-review", "owner", "owner-test"),
    named,
  )
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-review", "cost", "325.25"),
    reassigned,
  )
  let d = edited.plan.draft.unwrap()
  assert_eq(edited.plan.task_finder.focus, "task-review")
  assert_eq(plan_task_finder_rows(edited.plan.task_finder, d), [])
  assert_eq(d.tasks.map(t => t.id), ["task-design", "task-review"])
  assert_eq(d.tasks[0], original.plan.draft.unwrap().tasks[0])
  assert_eq(d.tasks[1].dependencies, ["task-design"])
  assert_eq(d.tasks[1].owner, "owner-test")
  assert_eq(d.tasks[1].cost, "325.25")
  assert_eq(edited.plan.prepared, None)
  assert_eq(edited.plan.revision, original.plan.revision + 3)
  assert_false(d.key == original.plan.draft.unwrap().key)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, d)
  let html = products_test_html(edited)
  assert_true(html.contains("Matches: 0 / 2"))
  assert_true(html.contains("id=\"plan-task-task-review-name\""))
  assert_true(html.contains("Deliver &lt;script&gt;界面"))
  assert_false(html.contains("Deliver <script>界面"))
  let (_, shifted) = plan_update(
    _ => none,
    ShiftTask("task-review", -1),
    edited,
  )
  assert_eq(shifted.plan.draft.unwrap().tasks.map(t => t.id), [
    "task-review", "task-design",
  ])
  assert_eq(shifted.plan.task_finder.focus, "task-review")
  let (prepare, saving) = plan_update(_ => none, Prepare, edited)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit full draft request")
  }
  assert_eq(@json.parse(products_text(request, "body")), d.to_json())
  ignore(
    plan_test_file(
      "task-finder-edited-draft.json",
      d.to_json().stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file(
      "task-finder-prepare-request.json",
      products_text(request, "body"),
    ),
  )
  ignore(plan_test_file("task-finder-edited.html", html))
}

///|
test "task finder CSV uses current matches independently of focus and keeps hidden dependencies" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, searched) = plan_update(
    _ => none,
    TaskFinder(Query("Review")),
    finder_test_model(),
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    searched,
  )
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-review", "name", "Review, \"new\"\n界面"),
    focused,
  )
  let d = edited.plan.draft.unwrap()
  let (download, exported) = plan_update(_ => none, TaskFinder(Export), edited)
  drafts_test_execute(download)
  assert_eq(exported.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one subset CSV")
  }
  let csv = products_text(file, "text")
  assert_eq(products_text(file, "name"), "plan-task-search-results.csv")
  assert_eq(
    csv,
    @plan_workbench.export_task_table({ ..d, tasks: [d.tasks[1]], }),
  )
  assert_true(csv.contains("\"task-design\""))
  assert_false(csv.contains("\"task-design\",\"Design\""))
  assert_eq(@plan_workbench.preview_task_table_updates(d, csv, false).changes, [])
  ignore(plan_test_file("task-finder-results.csv", csv))
  let (_, empty) = plan_update(_ => none, TaskFinder(Query("nothing")), edited)
  let (download, after) = plan_update(_ => none, TaskFinder(Export), empty)
  assert_eq(products_test_effect_count(download), 0)
  assert_eq(after.plan, empty.plan)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "task finder clears focus on filter changes reset show-all and scope changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, searched) = plan_update(
    _ => none,
    TaskFinder(Query("Review")),
    finder_test_model(),
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    searched,
  )
  for
    action in [
      TaskFinder(Query("Design")),
      TaskFinder(Owner("owner-test")),
      TaskFinder(Milestone("milestone-one")),
      TaskFinder(ShowAll),
      TaskFinder(Reset),
    ] {
    let (_, changed) = plan_update(_ => none, action, focused)
    assert_eq(changed.plan.task_finder.focus, "")
    assert_eq(changed.plan.draft, focused.plan.draft)
    assert_eq(changed.plan.prepared, focused.plan.prepared)
    assert_true(
      products_test_html(changed).contains("id=\"plan-task-task-design-name\""),
    )
  }
  for id in ["task-design", "missing"] {
    let (_, refused) = plan_update(_ => none, TaskFinder(Focus(id)), focused)
    assert_eq(refused.plan, focused.plan)
  }
  for action in [PlanMsg::Choose("company-second"), PlanMsg::Refresh] {
    let (_, changed) = plan_update(_ => none, action, focused)
    assert_eq(changed.plan.task_finder, plan_task_finder_initial())
  }
  let (_, other_actor) = plan_update(_ => none, TaskFinder(Export), {
    ..focused,
    dispatch_task_actor_id: "other",
  })
  assert_eq(other_actor.plan.task_finder, plan_task_finder_initial())
  assert_eq(other_actor.plan.draft, None)
  let wrong_project = {
    ..focused,
    plan: { ..focused.plan, selected: "company-second", },
  }
  let (effect, unchanged) = plan_update(
    _ => none,
    TaskFinder(Export),
    wrong_project,
  )
  assert_eq(products_test_effect_count(effect), 0)
  assert_eq(unchanged.plan, wrong_project.plan)
  assert_eq(plan_test_downloads(), "[]")
}

///|
test "task finder adding deleting and missing filter references never discard hidden draft rows" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, selected) = plan_update(
    _ => none,
    TaskFinder(Owner("reviewer")),
    finder_test_model(),
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    selected,
  )
  let (_, added) = plan_update(_ => none, Add("task"), focused)
  assert_eq(added.plan.task_finder.focus, "")
  assert_eq(added.plan.draft.unwrap().tasks.length(), 3)
  assert_eq(
    added.plan.draft.unwrap().tasks[0:2].to_owned(),
    focused.plan.draft.unwrap().tasks,
  )
  let (_, hidden_removed) = plan_update(
    _ => none,
    Remove("task", "task-design"),
    focused,
  )
  assert_eq(hidden_removed.plan.task_finder.focus, "task-review")
  assert_eq(hidden_removed.plan.draft.unwrap().tasks[0].dependencies, [
    "task-design",
  ])
  let (_, removed) = plan_update(
    _ => none,
    Remove("task", "task-review"),
    focused,
  )
  assert_eq(removed.plan.task_finder.focus, "")
  assert_eq(removed.plan.draft.unwrap().tasks.map(t => t.id), ["task-design"])
  let (_, owner_removed) = plan_update(
    _ => none,
    Remove("owner", "reviewer"),
    focused,
  )
  assert_eq(owner_removed.plan.task_finder.owner, "reviewer")
  assert_eq(
    plan_task_finder_rows(
      owner_removed.plan.task_finder,
      owner_removed.plan.draft.unwrap(),
    ).map(t => t.id),
    ["task-review"],
  )
  assert_true(
    products_test_html(owner_removed).contains(
      "Missing reference / 已移除引用 · reviewer",
    ),
  )
  let (_, reassigned) = plan_update(
    _ => none,
    Edit("task", "task-review", "owner", "owner-test"),
    owner_removed,
  )
  assert_eq(
    plan_task_finder_rows(
      reassigned.plan.task_finder,
      reassigned.plan.draft.unwrap(),
    ),
    [],
  )
  assert_eq(reassigned.plan.draft.unwrap().tasks.length(), 2)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "task finder resets on template replacement saved-version open and draft reload" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, searched) = plan_update(
    _ => none,
    TaskFinder(Query("Review")),
    finder_test_model(),
  )
  let (_, focused) = plan_update(
    _ => none,
    TaskFinder(Focus("task-review")),
    searched,
  )
  let (_, source) = plan_update(
    _ => none,
    Template(
      Source(@plan_workbench.export_template(plan_template_test_draft())),
    ),
    focused,
  )
  let (_, template) = plan_update(_ => none, Template(Preview), source)
  let (_, mapped) = plan_update(_ => none, Template(Owner("owner-1")), template)
  let (_, replaced) = plan_update(_ => none, Template(Apply), mapped)
  assert_eq(replaced.plan.task_finder, plan_task_finder_initial())
  assert_eq(replaced.plan.template, plan_template_initial())
  assert_false(
    replaced.plan.draft.unwrap().tasks.any(t => t.id == "task-review"),
  )
  let draft = { ..plan_test_draft(), key: "saved-synthetic", }
  let artifact : Json = {
    "operation_ref": "moonproj/project.plan.prepare@0.1.0",
    "plan_request_id": draft.key,
    "project": { "project_id": draft.project_id },
    "workflow": {
      "status": "pending_review",
      "accepted": false,
      "review_required": true,
    },
    "authority_effects": {
      "spend_authorized": false,
      "accounting_posted": false,
      "payment_released": false,
      "contract_signed": false,
      "work_executed": false,
    },
  }
  let saved : Json = {
    "contract": "moonproj.project-plan-workbench.v1",
    "actor": "owner-test",
    "project_id": draft.project_id,
    "key": draft.key,
    "persisted": true,
    "draft": draft.to_json(),
    "artifact": artifact,
    "artifact_json": artifact.stringify(),
    "readable": "Synthetic response fixture only",
  }
  let (_, opening) = plan_update(_ => none, Open(draft.key), focused)
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
  assert_eq(opened.plan.task_finder, plan_task_finder_initial())
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), focused)
  assert_eq(reloaded.plan.draft, Some(draft))
  assert_eq(reloaded.plan.task_finder, plan_task_finder_initial())
  assert_eq(plan_test_requests(), "[]")
}
