///|
fn text_replace_test_preview(model : Model) -> Model {
  let (_, query) = plan_update(_ => none, TextReplace(Query("Review")), model)
  let (_, replacement) = plan_update(
    _ => none,
    TextReplace(Replacement("Launch <script>界面")),
    query,
  )
  let (_, preview) = plan_update(_ => none, TextReplace(Preview), replacement)
  preview
}

///|
test "text replacement preview apply reload export and prepare use the edited draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let initial = plan_test_model()
  let original = {
    ..initial,
    plan: {
      ..initial.plan,
      prepared: Some({ "saved": "retained" }),
      phase: "prepared",
    },
  }
  let preview = text_replace_test_preview(original)
  assert_eq(preview.plan.draft, original.plan.draft)
  assert_eq(preview.plan.prepared, original.plan.prepared)
  assert_eq(preview.plan.revision, original.plan.revision)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  assert_eq(preview.plan.text_replace.preview.unwrap().occurrences, 3)
  let html = products_test_html(preview)
  assert_true(html.contains("Text replacement preview"))
  assert_true(html.contains("Launch &lt;script&gt;界面"))
  assert_true(!html.contains("Launch <script>界面"))
  assert_eq(plan_test_file("text-replace-preview.html", html), html)
  let (_, applied) = plan_update(_ => none, TextReplace(Apply), preview)
  let after = applied.plan.draft.unwrap()
  assert_eq(after.tasks[1].name, "Launch <script>界面")
  assert_eq(after.milestones[0].name, "Launch <script>界面able result")
  assert_eq(
    after.milestones[0].criteria,
    "Traceable requirements\nLaunch <script>界面able deliverable",
  )
  assert_eq(after.tasks[1].dependencies, ["task-design"])
  assert_eq(after.owners, original.plan.draft.unwrap().owners)
  assert_eq(applied.plan.revision, original.plan.revision + 1)
  assert_eq(applied.plan.prepared, None)
  assert_eq(applied.plan.text_replace.preview, None)
  assert_true(after.key != original.plan.draft.unwrap().key)
  assert_eq(
    plan_restore("owner-test", "company-actual"),
    after.to_json().stringify(),
  )
  let (_, again) = plan_update(_ => none, TextReplace(Apply), applied)
  assert_eq(again.plan, applied.plan)
  let (_, reload) = plan_update(_ => none, Choose("company-actual"), applied)
  assert_eq(reload.plan.draft, applied.plan.draft)
  assert_eq(reload.plan.text_replace, plan_text_replace_initial())
  let (download, same) = plan_update(_ => none, ExportTasks, applied)
  drafts_test_execute(download)
  assert_eq(same.plan, applied.plan)
  guard @json.parse(plan_test_downloads()) is Array([csv]) else {
    fail("one CSV download expected")
  }
  assert_true(products_text(csv, "text").contains("Launch <script>界面"))
  assert_eq(plan_test_requests(), "[]")
  let (prepare, _) = plan_update(_ => none, Prepare, applied)
  drafts_test_execute(prepare)
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare request expected")
  }
  let body = products_text(request, "body")
  assert_true(body.contains("Launch <script>界面"))
  let before_json = original.plan.draft.unwrap().to_json().stringify(indent=2)
  let after_json = after.to_json().stringify(indent=2)
  assert_eq(
    plan_test_file("text-replace-before.json", before_json),
    before_json,
  )
  assert_eq(plan_test_file("text-replace-after.json", after_json), after_json)
  assert_eq(
    plan_test_file("text-replace-task-output.csv", products_text(csv, "text")),
    products_text(csv, "text"),
  )
  assert_eq(plan_test_file("text-replace-prepare.json", body), body)
}

///|
test "text replacement close input scope edits and stale drafts cannot apply an old preview" {
  plan_test_browser()
  defer plan_test_cleanup()
  let preview = text_replace_test_preview(plan_test_model())
  for
    action in [
      PlanTextReplaceMsg::Close,
      Query("Design"),
      Replacement("New"),
      Scope("tasks"),
    ] {
    let (_, changed) = plan_update(_ => none, TextReplace(action), preview)
    assert_eq(changed.plan.text_replace.preview, None)
    let (_, applied) = plan_update(_ => none, TextReplace(Apply), changed)
    assert_eq(applied.plan.draft, preview.plan.draft)
    assert_eq(applied.plan.prepared, preview.plan.prepared)
    assert_eq(applied.plan.revision, preview.plan.revision)
  }
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-review", "name", "Changed elsewhere"),
    preview,
  )
  assert_eq(edited.plan.text_replace.preview, None)
  let stale = {
    ..edited,
    plan: { ..edited.plan, text_replace: preview.plan.text_replace, },
  }
  let (_, blocked) = plan_update(_ => none, TextReplace(Apply), stale)
  assert_eq(blocked.plan.draft, edited.plan.draft)
  assert_true(blocked.plan.text_replace.note.contains("Draft changed"))
  let (_, switched) = plan_update(_ => none, Choose("company-second"), preview)
  assert_eq(switched.plan.text_replace, plan_text_replace_initial())
  let (_, other_actor) = plan_update(_ => none, TextReplace(Apply), {
    ..preview,
    dispatch_task_actor_id: "different",
  })
  assert_eq(other_actor.plan.draft, None)
  assert_eq(other_actor.plan.text_replace, plan_text_replace_initial())
}

///|
test "text replacement no-op and invalid previews never save or discard a prepared result" {
  plan_test_browser()
  defer plan_test_cleanup()
  let initial = plan_test_model()
  let model = {
    ..initial,
    plan: { ..initial.plan, prepared: Some({ "saved": "retained" }), },
  }
  let (_, invalid) = plan_update(_ => none, TextReplace(Preview), model)
  assert_eq(invalid.plan.text_replace.preview, None)
  assert_true(invalid.plan.text_replace.note.contains("Find text"))
  let (_, query) = plan_update(_ => none, TextReplace(Query("Review")), model)
  let (_, scope) = plan_update(_ => none, TextReplace(Scope("tasks")), query)
  let (_, blanked) = plan_update(_ => none, TextReplace(Preview), scope)
  assert_true(blanked.plan.text_replace.note.contains("empty this field"))
  assert_eq(blanked.plan.draft, model.plan.draft)
  assert_eq(blanked.plan.prepared, model.plan.prepared)
  let (_, query) = plan_update(
    _ => none,
    TextReplace(Query("unmatched")),
    model,
  )
  let (_, preview) = plan_update(_ => none, TextReplace(Preview), query)
  assert_eq(preview.plan.text_replace.preview.unwrap().changes, [])
  assert_true(products_test_html(preview).contains("No text would change"))
  let (_, applied) = plan_update(_ => none, TextReplace(Apply), preview)
  assert_eq(applied.plan.draft, model.plan.draft)
  assert_eq(applied.plan.prepared, model.plan.prepared)
  assert_eq(applied.plan.revision, model.plan.revision)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  assert_eq(plan_test_requests(), "[]")
}
