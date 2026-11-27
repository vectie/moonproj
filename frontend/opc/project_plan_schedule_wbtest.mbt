///|
fn schedule_test_model() -> Model {
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
        milestones: [
          { ..d.milestones[0], date: "2028-02-28", },
          {
            ..d.milestones[0],
            id: "review",
            name: "Independent review",
            date: "2028-03-01",
          },
          {
            ..d.milestones[0],
            id: "release",
            name: "Release",
            date: "2028-03-10",
          },
          { ..d.milestones[0], id: "later", name: "Follow-up", date: "", },
        ],
      }),
    },
  }
}

///|
fn schedule_test_preview(model : Model) -> Model {
  let (_, anchor) = plan_update(
    _ => none,
    Schedule(Anchor("milestone-one")),
    model,
  )
  let (_, date) = plan_update(_ => none, Schedule(Date("2028-03-02")), anchor)
  let (_, preview) = plan_update(_ => none, Schedule(Preview), date)
  preview
}

///|
test "schedule preview apply reload and repeat flow retains all non-date draft content" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = schedule_test_model()
  let source = model.plan.draft.unwrap()
  assert_true(
    plan_store(
      model.plan.actor,
      model.plan.selected,
      ToJson::to_json(source).stringify(),
    ),
  )
  let original_store = plan_restore(model.plan.actor, model.plan.selected)
  let preview = schedule_test_preview(model)
  assert_eq(preview.plan.draft, model.plan.draft)
  assert_eq(preview.plan.prepared, model.plan.prepared)
  assert_eq(preview.plan.revision, model.plan.revision)
  assert_eq(preview.plan.phase, model.plan.phase)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), original_store)
  let html = products_test_html(preview)
  assert_true(html.contains("整体调整里程碑日期"))
  assert_true(html.contains("2028-03-01 → 2028-03-04"))
  assert_true(html.contains("未定日期 → 未定日期"))
  ignore(plan_test_file("schedule-preview.html", html))
  ignore(
    plan_test_file(
      "schedule-input.json",
      ToJson::to_json(source).stringify(indent=2),
    ),
  )
  let (cmd, applied) = plan_update(_ => none, Schedule(Apply), preview)
  assert_eq(products_test_effect_count(cmd), 0)
  let edited = applied.plan.draft.unwrap()
  assert_eq(edited.milestones.map(m => m.date), [
    "2028-03-02", "2028-03-04", "2028-03-13", "",
  ])
  assert_eq(
    {
      ..edited,
      key: source.key,
      prepared_at: source.prepared_at,
      milestones: source.milestones,
    },
    source,
  )
  assert_true(edited.key != source.key)
  assert_eq(applied.plan.revision, model.plan.revision + 1)
  assert_true(applied.plan.prepared is None)
  assert_eq(applied.plan.phase, "editing")
  assert_eq(applied.plan.schedule, plan_schedule_initial())
  assert_eq(applied.plan.history, model.plan.history)
  let stored = plan_restore(model.plan.actor, model.plan.selected)
  assert_eq(@json.parse(stored), ToJson::to_json(edited))
  ignore(
    plan_test_file(
      "schedule-output.json",
      ToJson::to_json(edited).stringify(indent=2),
    ),
  )
  let (download, unchanged) = plan_update(
    _ => none,
    Template(Download),
    applied,
  )
  drafts_test_execute(download)
  assert_eq(unchanged.plan, applied.plan)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one template download expected")
  }
  assert_eq(products_text(file, "name"), "plan-template.json")
  ignore(
    plan_test_file(
      "schedule-adjusted-template.json",
      products_text(file, "text"),
    ),
  )
  let (_, repeated) = plan_update(_ => none, Schedule(Apply), applied)
  assert_eq(repeated.plan, applied.plan)
  let (_, away) = plan_update(_ => none, Choose("company-second"), repeated)
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), away)
  assert_eq(restored.plan.draft, applied.plan.draft)
  assert_eq(restored.plan.schedule, plan_schedule_initial())
  assert_eq(plan_test_requests(), "[]")
}

///|
test "schedule cancellation changed inputs and invalid previews leave editor untouched" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = schedule_test_model()
  let preview = schedule_test_preview(model)
  for
    action in [
      Schedule(Close),
      Schedule(Date("broken")),
      Schedule(Anchor("review")),
    ] {
    let (_, dismissed) = plan_update(_ => none, action, preview)
    assert_true(dismissed.plan.schedule.preview is None)
    let (_, apply) = plan_update(_ => none, Schedule(Apply), dismissed)
    assert_eq(apply.plan.draft, model.plan.draft)
    assert_eq(apply.plan.prepared, model.plan.prepared)
    assert_eq(apply.plan.revision, model.plan.revision)
  }
  let (_, bad_date) = plan_update(
    _ => none,
    Schedule(Date("2028-02-30")),
    preview,
  )
  let (_, invalid) = plan_update(_ => none, Schedule(Preview), bad_date)
  assert_true(invalid.plan.schedule.note.contains("invalid date"))
  assert_true(invalid.plan.schedule.preview is None)
  assert_eq(invalid.plan.draft, model.plan.draft)
  assert_eq(invalid.plan.prepared, model.plan.prepared)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), "")
  let (_, same_date) = plan_update(
    _ => none,
    Schedule(Date("2028-02-28")),
    preview,
  )
  let (_, same_preview) = plan_update(_ => none, Schedule(Preview), same_date)
  let (_, same) = plan_update(_ => none, Schedule(Apply), same_preview)
  assert_eq(same.plan.draft, model.plan.draft)
  assert_eq(same.plan.revision, model.plan.revision)
  assert_eq(same.plan.prepared, model.plan.prepared)
  assert_eq(plan_test_requests(), "[]")
}

///|
test "schedule preview cannot overwrite later edits project or actor changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let preview = schedule_test_preview(schedule_test_model())
  let (_, edited) = plan_update(
    _ => none,
    Edit("milestone", "review", "date", "2028-04-01"),
    preview,
  )
  assert_true(edited.plan.schedule.preview is None)
  let (_, apply) = plan_update(_ => none, Schedule(Apply), edited)
  assert_eq(apply.plan, edited.plan)
  // Even an old preview reintroduced after an edit cannot replace new content.
  let (_, stale) = plan_update(_ => none, Schedule(Apply), {
    ..edited,
    plan: { ..edited.plan, schedule: preview.plan.schedule, },
  })
  assert_eq(stale.plan.draft, edited.plan.draft)
  assert_eq(stale.plan.revision, edited.plan.revision)
  assert_true(stale.plan.schedule.preview is None)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), preview)
  let (_, wrong_project) = plan_update(_ => none, Schedule(Apply), switched)
  assert_eq(wrong_project.plan, switched.plan)
  assert_eq(wrong_project.plan.schedule, plan_schedule_initial())
  let (_, wrong_actor) = plan_update(_ => none, Schedule(Apply), {
    ..preview,
    dispatch_task_actor_id: "other-actor",
  })
  assert_true(wrong_actor.plan.draft is None)
  assert_eq(wrong_actor.plan.schedule, plan_schedule_initial())
  let (_, refreshed) = plan_update(_ => none, Refresh, preview)
  assert_eq(refreshed.plan.schedule, plan_schedule_initial())
  assert_eq(plan_test_requests(), "[]")
}
