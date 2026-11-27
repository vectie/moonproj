///|
fn extract_test_model() -> Model {
  let model = transfer_test_model()
  let d = model.plan.draft.unwrap()
  {
    ..model,
    plan: {
      ..model.plan,
      draft: Some({
        ..d,
        tasks: [
          ..d.tasks,
          { ..d.tasks[0], id: "later", name: "Later <task>", owner: "next", },
        ],
        risks: [
          ..d.risks,
          {
            ..d.risks[0],
            id: "cross",
            summary: "Cross <risk>",
            tasks: ["task-review", "later"],
          },
          { ..d.risks[0], id: "global", summary: "Global <risk>", tasks: [], },
        ],
      }),
    },
  }
}

///|
fn extract_test_preview(model : Model) -> Model {
  let (_, selected) = plan_update(
    _ => none,
    Extract(Task("task-review")),
    model,
  )
  let (_, preview) = plan_update(_ => none, Extract(Preview), selected)
  preview
}

///|
test "compiled phase selection preview download and existing append replacement journeys" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = extract_test_model()
  let d = model.plan.draft.unwrap()
  let original = ToJson::to_json(d).stringify()
  assert_true(plan_store(model.plan.actor, model.plan.selected, original))
  let preview = extract_test_preview(model)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(preview.plan.history, model.plan.history)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), original)
  assert_eq(preview.plan.extract.preview.unwrap().prerequisites, ["task-design"])
  let html = products_test_html(preview)
  for
    text in [
      "Extract reusable phase", "Automatically included prerequisites: 1", "Partial milestone",
      "Later &lt;task&gt;", "Cross &lt;risk&gt;", "Global &lt;risk&gt;", "Download phase template",
      "not apportioned",
    ] {
    assert_true(html.contains(text))
  }
  ignore(
    plan_test_file("phase-input.json", ToJson::to_json(d).stringify(indent=2)),
  )
  ignore(plan_test_file("phase-preview.html", html))
  let (download, unchanged) = plan_update(_ => none, Extract(Download), preview)
  drafts_test_execute(download)
  assert_eq(unchanged.plan, preview.plan)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one phase download")
  }
  assert_eq(products_text(file, "name"), "plan-phase-template.json")
  assert_eq(products_text(file, "type"), "application/json;charset=utf-8")
  let exported = products_text(file, "text")
  let t = @plan_workbench.read_template(exported)
  assert_eq(t.tasks.length(), 2)
  assert_eq(t.owners.length(), 1)
  assert_eq(t.limit, "")
  ignore(plan_test_file("phase-template.json", exported))
  let (_, input) = plan_update(_ => none, Template(Source(exported)), unchanged)
  let (_, template) = plan_update(_ => none, Template(Preview), input)
  let (_, owner) = plan_update(_ => none, Template(Owner("owner-1")), template)
  let (_, append_preview) = plan_update(
    _ => none,
    Template(PreviewAppend),
    owner,
  )
  assert_eq(append_preview.plan.draft, model.plan.draft)
  let (_, appended) = plan_update(
    _ => none,
    Template(ApplyAppend),
    append_preview,
  )
  let combined = appended.plan.draft.unwrap()
  assert_eq(combined.tasks.length(), 5)
  assert_eq(combined.tasks[0], d.tasks[0])
  assert_eq(combined.tasks[4].dependencies, [combined.tasks[3].id])
  assert_eq(combined.risks[3].tasks, [combined.tasks[3].id])
  assert_eq(combined.notes, d.notes)
  assert_eq(combined.limit, d.limit)
  ignore(
    plan_test_file(
      "phase-appended.json",
      ToJson::to_json(combined).stringify(indent=2),
    ),
  )
  let (_, named) = plan_update(
    _ => none,
    Template(Name("Replacement preparer")),
    owner,
  )
  let (_, replaced) = plan_update(_ => none, Template(Apply), named)
  assert_eq(replaced.plan.draft.unwrap().tasks.length(), 2)
  assert_eq(replaced.plan.draft.unwrap().limit, "")
  assert_eq(replaced.plan.extract, plan_extract_initial())
  ignore(
    plan_test_file(
      "phase-replaced.json",
      ToJson::to_json(replaced.plan.draft.unwrap()).stringify(indent=2),
    ),
  )
  assert_eq(ToJson::to_json(d).stringify(), original)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "phase selection and edits invalidate export while repreview uses fresh current rows" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = extract_test_model()
  let preview = extract_test_preview(model)
  for
    action in [
      Extract(Task("task-design")),
      Extract(Milestone("milestone-one")),
      Extract(Close),
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (download, _) = plan_update(_ => none, Extract(Download), changed)
    assert_eq(products_test_effect_count(download), 0)
    assert_true(changed.plan.extract.preview is None)
    assert_eq(changed.plan.draft, model.plan.draft)
    assert_eq(changed.plan.prepared, model.plan.prepared)
  }
  let (_, milestone) = plan_update(
    _ => none,
    Extract(Milestone("milestone-one")),
    model,
  )
  let (_, all) = plan_update(_ => none, Extract(Preview), milestone)
  assert_eq(all.plan.extract.preview.unwrap().selected.length(), 3)
  assert_eq(all.plan.extract.preview.unwrap().partial_milestones, [])
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Fresh prerequisite"),
    preview,
  )
  assert_true(edited.plan.extract.preview is None)
  assert_eq(edited.plan.extract.tasks, ["task-review"])
  let (blocked, _) = plan_update(_ => none, Extract(Download), edited)
  assert_eq(products_test_effect_count(blocked), 0)
  let saved = plan_restore(edited.plan.actor, edited.plan.selected)
  let (_, fresh) = plan_update(_ => none, Extract(Preview), edited)
  let (download, result) = plan_update(_ => none, Extract(Download), fresh)
  drafts_test_execute(download)
  assert_eq(result.plan.draft, edited.plan.draft)
  assert_eq(result.plan.prepared, edited.plan.prepared)
  assert_eq(result.plan.revision, edited.plan.revision)
  assert_eq(plan_restore(edited.plan.actor, edited.plan.selected), saved)
  assert_true(plan_test_downloads().contains("Fresh prerequisite"))
  ignore(
    plan_test_file(
      "phase-fresh-template.json",
      fresh.plan.extract.preview.unwrap().json,
    ),
  )
  let stale = {
    ..preview,
    plan: { ..preview.plan, draft: edited.plan.draft, },
  }
  assert_false(products_test_html(stale).contains("Download phase template"))
  let (blocked, rejected) = plan_update(_ => none, Extract(Download), stale)
  assert_eq(products_test_effect_count(blocked), 0)
  assert_true(rejected.plan.extract.preview is None)
  assert_eq(rejected.plan.draft, stale.plan.draft)
  let (_, dependency_edit) = plan_update(
    _ => none,
    Toggle("task", "task-review", "task-design"),
    fresh,
  )
  let (_, new_closure) = plan_update(
    _ => none,
    Extract(Preview),
    dependency_edit,
  )
  assert_eq(new_closure.plan.extract.preview.unwrap().prerequisites, [])
  let new_template = @plan_workbench.read_template(
    new_closure.plan.extract.preview.unwrap().json,
  )
  assert_eq(new_template.tasks.length(), 1)
  assert_eq(new_template.tasks[0].name, "Review")
  assert_eq(new_template.risks.length(), 0)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "phase project and account switches repeated download and invalid source remain isolated" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = extract_test_model()
  let preview = extract_test_preview(model)
  let (_, away) = plan_update(_ => none, Choose("company-second"), preview)
  assert_eq(away.plan.extract, plan_extract_initial())
  let (download, _) = plan_update(_ => none, Extract(Download), away)
  assert_eq(products_test_effect_count(download), 0)
  let (_, back) = plan_update(_ => none, Choose("company-actual"), away)
  assert_eq(back.plan.extract, plan_extract_initial())
  let (download, switched) = plan_update(_ => none, Extract(Download), {
    ..preview,
    dispatch_task_actor_id: "other",
  })
  assert_eq(products_test_effect_count(download), 0)
  assert_eq(switched.plan.extract, plan_extract_initial())
  assert_true(switched.plan.draft is None)
  for _ in 0..<2 {
    let (download, result) = plan_update(_ => none, Extract(Download), preview)
    drafts_test_execute(download)
    assert_eq(result.plan, preview.plan)
  }
  guard @json.parse(plan_test_downloads()) is Array(files) else {
    fail("downloads")
  }
  assert_eq(files.length(), 2)
  assert_eq(files[0], files[1])
  let (_, empty) = plan_update(_ => none, Extract(Preview), model)
  assert_true(empty.plan.extract.preview is None)
  assert_true(!empty.plan.extract.note.is_empty())
  let d = model.plan.draft.unwrap()
  let broken = {
    ..preview,
    plan: {
      ..preview.plan,
      draft: Some({ ..d, tasks: [{ ..d.tasks[1], dependencies: ["gone"], }], }),
    },
  }
  let (_, invalid) = plan_update(_ => none, Extract(Preview), broken)
  assert_true(invalid.plan.extract.preview is None)
  assert_eq(invalid.plan.draft, broken.plan.draft)
  assert_eq(invalid.plan.prepared, model.plan.prepared)
  assert_eq(plan_test_requests(), "[]")
}
