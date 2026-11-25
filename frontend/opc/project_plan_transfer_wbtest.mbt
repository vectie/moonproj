///|
fn transfer_test_model() -> Model {
  let m = plan_test_model()
  let d = m.plan.draft.unwrap()
  {
    ..m,
    plan: {
      ..m.plan,
      prepared: Some({ "saved": "immutable" }),
      phase: "prepared",
      draft: Some({
        ..d,
        owners: [
          ..d.owners,
          { id: "next", name: "Next <owner>", role: "Delivery", },
        ],
        risks: [
          {
            id: "risk",
            summary: "Delay <risk>",
            severity: "high",
            owner: "owner-test",
            mitigation: "Review",
            tasks: ["task-design"],
          },
        ],
      }),
    },
  }
}

///|
fn transfer_test_preview(m : Model) -> Model {
  let (_, a) = plan_update(_ => none, Transfer(From("owner-test")), m)
  let (_, b) = plan_update(_ => none, Transfer(To("next")), a)
  let (_, c) = plan_update(_ => none, Transfer(Preview), b)
  c
}

///|
test "owner transfer preview apply reload and exported template retain assignment changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = transfer_test_model()
  let source = model.plan.draft.unwrap()
  assert_true(
    plan_store(
      model.plan.actor,
      model.plan.selected,
      ToJson::to_json(source).stringify(),
    ),
  )
  let before = plan_restore(model.plan.actor, model.plan.selected)
  let preview = transfer_test_preview(model)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), before)
  let html = products_test_html(preview)
  assert_true(html.contains("Reassign owner"))
  assert_true(html.contains("Next &lt;owner&gt;"))
  assert_true(html.contains("Delay &lt;risk&gt;"))
  assert_true(html.contains("owner-test → next"))
  ignore(plan_test_file("transfer-preview.html", html))
  ignore(
    plan_test_file("transfer-input.json", ToJson::to_json(source).stringify(indent=2)),
  )
  let (cmd, applied) = plan_update(_ => none, Transfer(Apply), preview)
  assert_eq(products_test_effect_count(cmd), 0)
  let edited = applied.plan.draft.unwrap()
  let expected = @plan_workbench.transfer_owner(source, "owner-test", "next")
  assert_eq(
    { ..edited, key: source.key, prepared_at: source.prepared_at, },
    expected,
  )
  assert_true(edited.key != source.key)
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_true(applied.plan.prepared is None)
  assert_eq(applied.plan.phase, "editing")
  assert_eq(applied.plan.history, model.plan.history)
  assert_eq(applied.plan.actor, model.plan.actor)
  assert_eq(applied.plan.transfer, plan_transfer_initial())
  assert_eq(
    @json.parse(plan_restore(model.plan.actor, model.plan.selected)),
    ToJson::to_json(edited),
  )
  ignore(
    plan_test_file("transfer-output.json", ToJson::to_json(edited).stringify(indent=2)),
  )
  let (_, repeated) = plan_update(_ => none, Transfer(Apply), applied)
  assert_eq(repeated.plan, applied.plan)
  let (_, away) = plan_update(_ => none, Choose("company-second"), applied)
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), away)
  assert_eq(restored.plan.draft, applied.plan.draft)
  assert_eq(restored.plan.transfer, plan_transfer_initial())
  let (download, _) = plan_update(_ => none, Template(Download), restored)
  drafts_test_execute(download)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one template")
  }
  ignore(plan_test_file("transfer-template.json", products_text(file, "text")))
  let exported = @json.parse(products_text(file, "text"))
  for category in ["tasks", "milestones", "risks"] {
    assert_true(
      @plan_workbench.items(exported, category).all(row => {
        products_text(row, "owner") == "owner-2"
      }),
    )
  }
  assert_eq(plan_test_requests(), "[]")
}

///|
test "transfer cancellation endpoint changes edits stale input and scope cannot apply old preview" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = transfer_test_model()
  let preview = transfer_test_preview(model)
  for
    action in [
      Transfer(Close),
      Transfer(From("next")),
      Transfer(To("owner-test")),
    ] {
    let (_, changed) = plan_update(_ => none, action, preview)
    let (_, applied) = plan_update(_ => none, Transfer(Apply), changed)
    assert_eq(applied.plan.draft, model.plan.draft)
    assert_eq(applied.plan.prepared, model.plan.prepared)
  }
  let d = model.plan.draft.unwrap()
  let stale = {
    ..preview,
    plan: {
      ..preview.plan,
      draft: Some({ ..d, notes: "Changed externally", }),
    },
  }
  let (_, rejected) = plan_update(_ => none, Transfer(Apply), stale)
  assert_eq(rejected.plan.draft, stale.plan.draft)
  assert_true(rejected.plan.transfer.preview is None)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Changed"),
    preview,
  )
  assert_true(edited.plan.transfer.preview is None)
  let (_, after_edit) = plan_update(_ => none, Transfer(Apply), edited)
  assert_eq(after_edit.plan, edited.plan)
  let (_, away) = plan_update(_ => none, Choose("company-second"), preview)
  let (_, after_switch) = plan_update(_ => none, Transfer(Apply), away)
  assert_eq(after_switch.plan, away.plan)
  let (_, actor) = plan_update(_ => none, Transfer(Apply), {
    ..preview,
    dispatch_task_actor_id: "different",
  })
  assert_true(actor.plan.transfer.preview is None)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "transfer invalid endpoint and empty allocation never invalidate prepared result" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = transfer_test_model()
  let (_, chosen) = plan_update(_ => none, Transfer(From("missing")), model)
  let (_, target) = plan_update(_ => none, Transfer(To("next")), chosen)
  let (_, invalid) = plan_update(_ => none, Transfer(Preview), target)
  assert_true(invalid.plan.transfer.preview is None)
  assert_true(!invalid.plan.transfer.note.is_empty())
  assert_eq(invalid.plan.draft, model.plan.draft)
  let (_, empty_source) = plan_update(_ => none, Transfer(From("next")), model)
  let (_, dest) = plan_update(
    _ => none,
    Transfer(To("owner-test")),
    empty_source,
  )
  let (_, empty) = plan_update(_ => none, Transfer(Preview), dest)
  let (_, applied) = plan_update(_ => none, Transfer(Apply), empty)
  assert_eq(applied.plan, empty.plan)
  assert_eq(applied.plan.prepared, model.plan.prepared)
}
