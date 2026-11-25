///|
fn packet_test_model() -> Model {
  let base = drafts_test_valid()
  let draft = dispatch_active_draft(base).unwrap()
  dispatch_replace_draft(base, {
    ..draft,
    title: "  Interview <script>学习 🚀</script>  ",
    acceptance: "Keep source quote\r\n  Second line\tvalue",
    source_reference: Some(
      "https://example.test/one?q=中文&v=1\nsecond source",
    ),
    observed_problem: Some(
      "  Buyer said \"I cannot find the result\"\nKeep trailing space  ",
    ),
    begin_date: "2028-02-29",
    end_date: "date still unknown",
    offer_draft: Some({ "title": "excluded proposal attachment" }),
  })
}

///|
fn packet_test_update(model : Model, action : WorkPacketMsg) -> Model {
  let (_, next) = update(_ => none, WorkPacketAction(action), model)
  next
}

///|
fn packet_test_ready(model : Model) -> Model raise {
  packet_test_update(
    packet_test_update(
      model,
      Source(
        work_packet_from_draft(dispatch_active_draft(model).unwrap()).encode(),
      ),
    ),
    Preview,
  )
}

///|
test "portable brief real UI export preview and import preserve exact text and original draft" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = packet_test_model()
  let old = dispatch_active_draft(original).unwrap()
  let (download, exported) = update(
    _ => none,
    WorkPacketAction(Export),
    original,
  )
  drafts_test_execute(download)
  assert_eq(exported.dispatch_drafts, original.dispatch_drafts)
  assert_eq(dispatch_read_drafts(original.dispatch_task_actor_id), "")
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one download expected")
  }
  assert_eq(products_text(file, "name"), "moonproj-work-brief.json")
  assert_eq(products_text(file, "type"), "application/json;charset=utf-8")
  let text = products_text(file, "text")
  let packet = @work_packet.decode(text)
  assert_eq(packet, work_packet_from_draft(old))
  for
    secret in [
      old.id,
      old.task_id,
      old.idempotency_key,
      original.dispatch_task_actor_id,
      old.project_id,
      old.owner_id,
      old.workspace,
      old.model,
      "excluded proposal attachment",
    ] {
    assert_false(text.contains(secret))
  }
  let source = packet_test_update(original, Source(text))
  let preview = packet_test_update(source, Preview)
  assert_eq(preview.dispatch_drafts, original.dispatch_drafts)
  let html = products_test_html(preview)
  assert_true(html.contains("简报预览"))
  assert_true(html.contains("for=\"work-packet-source\""))
  assert_true(html.contains("id=\"work-packet-source\""))
  assert_true(html.contains("&lt;script&gt;学习 🚀&lt;/script&gt;"))
  assert_false(html.contains("<script>学习"))
  assert_true(html.contains("date still unknown"))
  assert_true(html.contains("company-actual"))
  assert_true(html.contains("提案或附加研究"))
  let messages : Array[Msg] = []
  let (apply, applied) = update(
    msg => {
      messages.push(msg)
      none
    },
    WorkPacketAction(Apply),
    preview,
  )
  drafts_test_execute(apply)
  assert_eq(messages.length(), 1)
  let (_, stored) = update(_ => none, messages[0], applied)
  assert_eq(stored.dispatch_draft_storage, "已保存到此浏览器")
  let fresh = dispatch_active_draft(stored).unwrap()
  assert_eq(work_packet_from_draft(fresh), packet)
  assert_eq(dispatch_draft_by_id(stored, old.id), Some(old))
  assert_eq(
    stored.dispatch_drafts.length(),
    original.dispatch_drafts.length() + 1,
  )
  assert_true(
    fresh.id != old.id &&
    fresh.task_id != old.task_id &&
    fresh.idempotency_key != old.idempotency_key,
  )
  assert_eq(fresh.project_id, old.project_id)
  assert_eq(fresh.state, "editing")
  assert_false(fresh.attempted || fresh.recovery_required)
  assert_eq(fresh.product_id, "")
  assert_eq(fresh.product_snapshot, None)
  assert_eq(fresh.owner_id, "")
  assert_eq(fresh.workspace, "")
  assert_eq(fresh.model, "")
  assert_eq(fresh.offer_draft, None)
  assert_eq(fresh.research_brief, None)
  assert_eq(stored.dispatch_task_id, original.dispatch_task_id)
  assert_eq(stored.dispatch_run, original.dispatch_run)
  assert_false(stored.work_packet.open)
  let (repeat, unchanged) = update(_ => none, WorkPacketAction(Apply), stored)
  assert_eq(products_test_effect_count(repeat), 0)
  assert_eq(unchanged.dispatch_drafts, stored.dispatch_drafts)
  let reloaded = drafts_test_update(
    {
      ..initial_model(),
      dispatch_task_actor_id: original.dispatch_task_actor_id,
    },
    Restored(
      original.dispatch_task_actor_id,
      dispatch_read_drafts(original.dispatch_task_actor_id),
    ),
  )
  assert_eq(dispatch_draft_by_id(reloaded, fresh.id), Some(fresh))
  assert_eq(dispatch_draft_by_id(reloaded, old.id), Some(old))
  let body = dispatch_draft_create_body(fresh, original.dispatch_task_actor_id)
  assert_eq(products_text(body, "task_name"), fresh.title.trim().to_owned())
  guard body is Object(fields) else { fail("body expected") }
  assert_eq(
    fields["source_context"],
    Json::object({
      "reference": Json::string(packet.source_reference.trim().to_owned()),
      "problem": Json::string(packet.observed_problem.trim().to_owned()),
    }),
  )
  assert_eq(plan_test_requests(), "[]")
  ignore(plan_test_file("portable-task-brief.json", text))
  ignore(plan_test_file("portable-task-brief-preview.html", html))
  ignore(
    plan_test_file(
      "portable-task-brief-original.json",
      ToJson::to_json(old).stringify(),
    ),
  )
  ignore(
    plan_test_file(
      "portable-task-brief-imported.json",
      ToJson::to_json(fresh).stringify(),
    ),
  )
  ignore(
    plan_test_file("portable-task-brief-create-payload.json", body.stringify()),
  )
}

///|
test "portable brief malformed text and late stale actions leave all existing drafts intact" {
  let original = packet_test_model()
  let ready = packet_test_ready(original)
  let invalid = packet_test_update(
    packet_test_update(ready, Source("not JSON")),
    Preview,
  )
  assert_eq(invalid.work_packet.packet, None)
  assert_true(invalid.work_packet.notice.contains("无法解析"))
  let (apply, failed) = update(_ => none, WorkPacketAction(Apply), invalid)
  assert_eq(products_test_effect_count(apply), 0)
  assert_eq(failed.dispatch_drafts, original.dispatch_drafts)
  let closed = packet_test_update(ready, Close)
  assert_false(closed.work_packet.open)
  assert_eq(
    packet_test_update(closed, Apply).dispatch_drafts,
    original.dispatch_drafts,
  )
  let (_, changed_project) = update(
    _ => none,
    DraftAction(Input("project_id", "other-company")),
    ready,
  )
  assert_false(changed_project.work_packet.open)
  assert_eq(
    packet_test_update(changed_project, Apply).dispatch_drafts,
    changed_project.dispatch_drafts,
  )
  let (_, changed_actor) = update(
    _ => none,
    DispatchSessionLoaded("different-actor"),
    ready,
  )
  assert_false(changed_actor.work_packet.open)
  let (_, parked) = update(_ => none, DraftAction(Park), ready)
  assert_false(parked.work_packet.open)
  let (_, other_draft) = update(_ => none, DraftAction(New), ready)
  assert_false(other_draft.work_packet.open)
  let (_, navigated) = update(_ => none, Navigate(Products), ready)
  assert_false(navigated.work_packet.open)
  let selecting = packet_test_update(ready, Choose)
  let cancelled = packet_test_update(selecting, Close)
  let late = packet_test_update(
    cancelled,
    Loaded(selecting.work_packet.generation, ready.work_packet.text, ""),
  )
  assert_false(late.work_packet.open)
  assert_eq(late.dispatch_drafts, original.dispatch_drafts)
  assert_eq(initial_model().work_packet, empty_work_packet(0))
}

///|
test "portable brief failed storage keeps imported draft on page and original recovery record" {
  drafts_test_transport(true)
  defer drafts_test_transport_cleanup()
  let original = packet_test_model()
  let ready = packet_test_ready(original)
  let messages : Array[Msg] = []
  let (apply, applied) = update(
    msg => {
      messages.push(msg)
      none
    },
    WorkPacketAction(Apply),
    ready,
  )
  drafts_test_execute(apply)
  let (_, failed) = update(_ => none, messages[0], applied)
  assert_eq(failed.dispatch_drafts, applied.dispatch_drafts)
  assert_eq(
    dispatch_draft_by_id(failed, original.dispatch_draft_id),
    dispatch_active_draft(original),
  )
  assert_true(failed.dispatch_draft_storage.contains("未保存"))
  assert_eq(drafts_test_post_count(), 0)
  assert_eq(drafts_test_events(), "save-failed")
}

///|
test "portable brief exports attempted drafts only as text and accepts blank destination project" {
  let original = packet_test_model()
  let old = dispatch_active_draft(original).unwrap()
  let model = dispatch_replace_draft(original, {
    ..old,
    project_id: "",
    state: "uncertain",
    attempted: true,
    recovery_required: true,
  })
  let ready = packet_test_ready(model)
  let applied = packet_test_update(ready, Apply)
  let fresh = dispatch_active_draft(applied).unwrap()
  assert_eq(fresh.project_id, "")
  assert_eq(fresh.state, "editing")
  assert_eq(dispatch_draft_by_id(applied, old.id), dispatch_active_draft(model))
  assert_false(dispatch_draft_validation(fresh, "").is_empty())
  let ready_again = packet_test_ready(applied)
  let edited = drafts_test_update(
    ready_again,
    Input("title", "edited current original"),
  )
  let copy = packet_test_update(edited, Apply)
  assert_eq(
    dispatch_draft_by_id(copy, fresh.id).unwrap().title,
    "edited current original",
  )
  assert_eq(dispatch_active_draft(copy).unwrap().title, old.title)
}
