///|
test "optional source draft survives save restore and frozen retry with the original task key" {
  let source = drafts_test_update(
    drafts_test_update(
      drafts_test_valid(),
      Input("source_reference", "source:interview-7"),
    ),
    Input("observed_problem", "Founder cannot compare offers"),
  )
  let draft = dispatch_active_draft(source).unwrap()
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", dispatch_draft_store(source)),
  )
  let recovered = dispatch_draft_by_id(restored, draft.id).unwrap()
  assert_eq(recovered.source_reference, draft.source_reference)
  assert_eq(recovered.observed_problem, draft.observed_problem)
  assert_eq(
    dispatch_draft_create_body(recovered, "actor-drafts"),
    dispatch_draft_create_body(draft, "actor-drafts"),
  )
  let saving = drafts_test_update(source, Create)
  let changed = drafts_test_update(
    saving,
    Input("source_reference", "source:changed"),
  )
  assert_eq(
    dispatch_active_draft(changed).unwrap().source_reference,
    draft.source_reference,
  )
  assert_eq(
    dispatch_active_draft(changed).unwrap().idempotency_key,
    draft.idempotency_key,
  )
}

///|
test "old local drafts decode without source fields and keep signed create shape" {
  let model = drafts_test_valid()
  let draft = dispatch_active_draft(model).unwrap()
  let old = match ToJson::to_json(draft) {
    Object(fields) => {
      fields.remove("source_reference")
      fields.remove("observed_problem")
      Json::object(fields)
    }
    _ => fail("expected draft object")
  }
  let decoded : DispatchDraft = @json.from_json(old)
  assert_eq(decoded.source_reference, None)
  assert_eq(decoded.observed_problem, None)
  assert_eq(
    dispatch_draft_create_body(decoded, "actor"),
    dispatch_draft_create_body(draft, "actor"),
  )
  assert_eq(
    dispatch_json_field(
      dispatch_draft_create_body(decoded, "actor"),
      "source_context",
    ),
    Json::null(),
  )
}

///|
test "canonical task readback restores source and history without local draft dependence" {
  let response : Json = {
    "data": {
      "task": {
        "taskGuid": "task-1",
        "projGuid": "project-1",
        "taskName": "Compare",
        "status": "pending",
        "source_context": {
          "reference": "source:7",
          "problem": "Cannot compare",
        },
      },
      "reports": [],
      "commitment": {
        "task_id": "task-1",
        "original_brief": { "remarks": "Cite sources" },
        "receipts": [{ "event_id": "create-event", "actor_id": "owner" }],
      },
    },
  }
  let snapshot = dispatch_decode_snapshot(response.stringify(), "task-1").unwrap()
  let model = apply_dispatch_snapshot(initial_model(), snapshot)
  assert_eq(
    dispatch_json_text(model.dispatch_task_source_context, "reference"),
    "source:7",
  )
  assert_eq(
    dispatch_json_text(model.dispatch_task_commitment, "task_id"),
    "task-1",
  )
  assert_true(model.dispatch_drafts.is_empty())
  let legacy = dispatch_decode_snapshot(
    drafts_test_snapshot_body("task-2"),
    "task-2",
  ).unwrap()
  let (_, opening) = open_dispatch_task(_ => none, {
    ..model,
    dispatch_task_open_id: "task-2",
  })
  assert_eq(opening.dispatch_task_commitment, Json::null())
  assert_eq(
    apply_dispatch_snapshot(opening, legacy).dispatch_task_source_context,
    Json::null(),
  )
}

///|
#warnings("-alert_unstable")
test "source and technical receipt details render in existing task card with keyboard disclosures" {
  let model = {
    ..initial_model(),
    dispatch_task_id: "task-1",
    dispatch_task_title: "Compare offers",
    dispatch_task_source_context: {
      "reference": "https://example.test/interview-7",
      "problem": "Cannot compare offers",
    },
    dispatch_task_commitment: {
      "original_brief": {
        "task_name": "Compare offers",
        "remarks": "Cite three sources",
      },
      "receipts": [
        {
          "action": "internal_acceptance",
          "actor_id": "owner-7",
          "event_id": "accept-event-7",
          "audit_id": "audit-7",
          "audit_state": "missing",
        },
      ],
    },
  }
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => dispatch_durable_task_card(msg => emit(msg), model))
  let rendered = opc_render_cell(page)
  assert_true(rendered.contains("Cannot compare offers"))
  assert_true(rendered.contains("https://example.test/interview-7"))
  assert_true(rendered.contains("accept-event-7"))
  assert_true(rendered.contains("审计记录待核对"))
  assert_true(rendered.contains("<summary>任务身份与收据</summary>"))
  assert_true(
    rendered.contains(
      "内部验收、客户接受和实际收款是不同事实",
    ),
  )
}
