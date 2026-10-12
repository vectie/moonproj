///|
fn phase_test_model() -> Model {
  let base = plan_test_model()
  {
    ..base,
    plan: {
      ..base.plan,
      draft: Some({ ..plan_test_draft(), currency: "USD", limit: "2000.00", }),
      prepared: Some({ "saved": "retained until apply" }),
    },
  }
}

///|
fn phase_test_preview(model : Model) -> Model {
  let source = @plan_workbench.export_template(plan_template_test_draft()) catch {
    _ => ""
  }
  let (_, entered) = plan_update(_ => none, Template(Source(source)), model)
  let (_, parsed) = plan_update(_ => none, Template(Preview), entered)
  let (_, selected) = plan_update(_ => none, Template(Owner("owner-1")), parsed)
  let (_, previewed) = plan_update(_ => none, Template(PreviewAppend), selected)
  previewed
}

///|
test "append a complete phase preview apply edit reload export and prepare request" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = phase_test_model()
  let before = model.plan.draft.unwrap()
  let previewed = phase_test_preview(model)
  assert_eq(previewed.plan.draft, model.plan.draft)
  assert_eq(previewed.plan.prepared, model.plan.prepared)
  assert_eq(previewed.plan.revision, model.plan.revision)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  assert_eq(plan_test_requests(), "[]")
  let proposed = previewed.plan.template.append_after.unwrap()
  assert_eq(proposed.tasks.length(), 6)
  assert_eq(proposed.owners[0], before.owners[0])
  assert_eq(proposed.tasks[0], before.tasks[0])
  assert_eq(proposed.tasks[1], before.tasks[1])
  assert_eq(proposed.notes, before.notes)
  assert_eq(proposed.limit, "2000.00")
  assert_eq(proposed.contingency, before.contingency)
  assert_eq(proposed.tasks[4].dependencies, [
    proposed.tasks[2].id,
    proposed.tasks[3].id,
  ])
  assert_eq(proposed.risks[0].tasks, [
    proposed.tasks[2].id,
    proposed.tasks[3].id,
  ])
  let html = products_test_html(previewed)
  for
    value in [
      "Preview phase append", "Apply phase append", "Complete combined draft", "Source references retained",
      "2000.00", "模板范围说明及预算不导入",
    ] {
    assert_true(html.contains(value))
  }
  ignore(
    plan_test_file("phase-input-template.json", previewed.plan.template.source),
  )
  ignore(
    plan_test_file(
      "phase-destination-before.json",
      before.to_json().stringify(indent=2),
    ),
  )
  ignore(plan_test_file("phase-preview.html", html))
  ignore(
    plan_test_file(
      "phase-preview-draft.json",
      proposed.to_json().stringify(indent=2),
    ),
  )
  let (_, applied) = plan_update(_ => none, Template(ApplyAppend), previewed)
  let result = applied.plan.draft.unwrap()
  assert_eq(result.tasks, proposed.tasks)
  assert_eq(result.owners, proposed.owners)
  assert_eq(result.milestones, proposed.milestones)
  assert_eq(result.risks, proposed.risks)
  assert_true(result.key != before.key)
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_eq(applied.plan.prepared, None)
  assert_eq(applied.plan.template, plan_template_initial())
  assert_eq(plan_test_requests(), "[]")
  let (_, repeated) = plan_update(_ => none, Template(ApplyAppend), applied)
  assert_eq(repeated.plan, applied.plan)
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), applied)
  assert_eq(reloaded.plan.draft, applied.plan.draft)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", result.tasks[2].id, "name", "Research phase for this project"),
    reloaded,
  )
  assert_eq(
    edited.plan.draft.unwrap().tasks[2].name,
    "Research phase for this project",
  )
  let (download, same) = plan_update(_ => none, Template(Download), edited)
  drafts_test_execute(download)
  assert_eq(same.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one template export expected")
  }
  let portable = @plan_workbench.read_template(products_text(file, "text"))
  assert_eq(portable.tasks.length(), 6)
  assert_eq(portable.tasks[4].dependencies, ["task-3", "task-4"])
  ignore(
    plan_test_file("phase-combined-template.json", products_text(file, "text")),
  )
  let (prepare, saving) = plan_update(_ => none, Prepare, edited)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([call]) else {
    fail("one explicit prepare request expected")
  }
  assert_eq(
    products_text(call, "url"),
    "/api/company/projects/company-actual/prepared-plans",
  )
  assert_eq(
    @json.parse(products_text(call, "body")),
    edited.plan.draft.unwrap().to_json(),
  )
  ignore(
    plan_test_file("phase-ui-prepare-request.json", products_text(call, "body")),
  )
  let native_request = @plan_workbench.request(
    edited.plan.draft.unwrap(),
    "owner-test",
    { "project_id": "company-actual" },
    "synthetic-phase",
    "digest",
  )
  assert_eq(@plan_workbench.items(native_request, "tasks").length(), 6)
  ignore(
    plan_test_file(
      "phase-native-request.json",
      native_request.stringify(indent=2),
    ),
  )
}

///|
test "phase staging is invalidated by edits mapping source or project changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let base = phase_test_model()
  let previewed = phase_test_preview(base)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Changed before append"),
    previewed,
  )
  assert_eq(edited.plan.template.append_after, None)
  let (_, applied) = plan_update(_ => none, Template(ApplyAppend), edited)
  assert_eq(applied.plan, edited.plan)
  for
    action in [
      Template(Owner("owner-2")),
      Template(Source("changed")),
      Template(Close),
      Choose("company-second"),
    ] {
    let (_, changed) = plan_update(_ => none, action, previewed)
    assert_eq(changed.plan.template.append_after, None)
    let (_, noop) = plan_update(_ => none, Template(ApplyAppend), changed)
    assert_eq(noop.plan, changed.plan)
  }
  // An older model's staged values cannot replace a changed draft either.
  let stale = {
    ..previewed,
    plan: { ..previewed.plan, draft: edited.plan.draft, },
  }
  let (_, blocked) = plan_update(_ => none, Template(ApplyAppend), stale)
  assert_eq(blocked.plan.draft, edited.plan.draft)
  assert_eq(blocked.plan.template.append_after, None)
}

///|
test "phase currency correction retains original source draft and prepared result" {
  plan_test_browser()
  defer plan_test_cleanup()
  let base = plan_test_model()
  let wrong = phase_test_preview(base)
  assert_eq(wrong.plan.template.append_after, None)
  assert_true(wrong.plan.template.note.contains("currency"))
  assert_eq(wrong.plan.draft, base.plan.draft)
  assert_eq(wrong.plan.prepared, base.plan.prepared)
  assert_false(wrong.plan.template.source.is_empty())
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  let (_, corrected) = plan_update(
    _ => none,
    Edit("plan", "", "currency", "USD"),
    wrong,
  )
  // Preview also works on a corrected current draft without reparsing source.
  assert_eq(corrected.plan.draft.unwrap().currency, "USD")
  let (_, previewed) = plan_update(
    _ => none,
    Template(PreviewAppend),
    corrected,
  )
  assert_true(previewed.plan.template.append_after is Some(_))
  assert_eq(plan_test_requests(), "[]")
}
