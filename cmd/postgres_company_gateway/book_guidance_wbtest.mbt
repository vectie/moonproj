///|
fn guidance_test_task() -> Json {
  {
    "taskGuid": "PT-native",
    "projGuid": "company-project",
    "product_id": "",
    "taskName": "Private task text",
    "remarks": "Private acceptance",
    "source_context": {
      "reference": "private source",
      "problem": "private problem",
    },
    "execution_workspace": "/tmp",
    "execution_model": "",
    "revision": 1,
    "status": "pending",
  }
}

///|
fn guidance_test_ref(id : String) -> Json {
  {
    "record_id": id,
    "record_version": "1",
    "record_digest": "sha256:fixture-" + id,
  }
}

///|
fn guidance_test_set(value : Json, key : String, replacement : Json) -> Json {
  guard value is Object(fields) else { abort("test expected object") }
  let fields = fields.copy()
  fields[key] = replacement
  Json::object(fields)
}

///|
fn guidance_test_selection(task : Json) -> Json raise GatewayError {
  let handoff = book_guidance_query_projection(task)
  let conditions = native_field(handoff, "conditions")
  {
    "contract_version": "moonbook.task-guidance-selection.v1",
    "handoff": handoff,
    "query": {
      "contract_version": "moonbook.outcome-lesson-query.v1",
      "target_task": native_field(handoff, "target_task"),
      "conditions": conditions,
    },
    "lesson": {
      "reference": guidance_test_ref("lesson"),
      "title": "Scope the review",
      "guidance": "GUIDANCE_SENTINEL: compare original customer constraints.",
      "applicability": conditions,
      "invalidation": [],
    },
    "review": {
      "receipt": guidance_test_ref("review"),
      "reviewer_id": "curator",
      "decided_at": 10,
    },
    "source": {
      "outcome": guidance_test_ref("outcome"),
      "assessment": guidance_test_ref("assessment"),
      "assessment_review": guidance_test_ref("assessment-review"),
    },
    "selection_review": null,
    "currentness": "legacy_unselected",
    "journal_sequence": 8,
    "book_origin": "https://book.example.test",
    "observed_at": 20,
    "applicability_decision_required": true,
    "activation_authorized": false,
    "external_side_effects_applied": false,
  }
}

///|
test "guidance query captures only canonical identity and separates suite product namespace" {
  let task = guidance_test_set(guidance_test_task(), "product_id", "moonbook")
  let handoff = book_guidance_query_projection(task)
  let snapshot = @json.parse(native_text(handoff, "task_snapshot"))
  assert_eq(snapshot, {
    "task_id": "PT-native",
    "project_id": "company-project",
    "product_id": "moonbook",
    "revision": 1,
  })
  assert_eq(native_field(handoff, "conditions"), [
    { "key": "project_id", "value": "company-project" },
    { "key": "suite_product_id", "value": "moonbook" },
  ])
  assert_false(handoff.stringify().contains("Private"))
  assert_false(handoff.stringify().contains("private source"))
  assert_false(handoff.stringify().contains("execution_workspace"))
  assert_eq(
    native_text(native_field(handoff, "target_task"), "record_digest"),
    "sha256:" +
    native_context_hash(
      @encoding/utf8.encode(native_text(handoff, "task_snapshot")),
    ),
  )
  assert_eq(
    book_guidance_query_task_id("/api/company/tasks/PT-native/guidance-query"),
    Some("PT-native"),
  )
  assert_eq(
    book_guidance_query_task_id("/api/company/tasks/../guidance-query"),
    None,
  )
  for
    changed in [
      guidance_test_set(task, "revision", 0),
      guidance_test_set(task, "status", "done"),
      guidance_test_set(task, "execution", {}),
    ] {
    try book_guidance_query_projection(changed) catch {
      _ => ()
    } noraise {
      _ => abort("invalid task must reject guidance query")
    }
  }
}

///|
test "guidance rejects stale targets unsupported scope authority and private extra bodies" {
  let task = guidance_test_task()
  let selected = guidance_test_selection(task)
  let handoff = native_field(selected, "handoff")
  @task_evidence.validate_guidance_selection(selected, handoff)
  assert_true(
    native_book_guidance(task, { "book_guidance": selected }) is Some(_),
  )
  assert_eq(native_book_guidance(task, {}), None)
  let lesson = native_field(selected, "lesson")
  let query = native_field(selected, "query")
  for
    invalid in [
      guidance_test_set(selected, "activation_authorized", true),
      guidance_test_set(selected, "external_side_effects_applied", true),
      guidance_test_set(selected, "raw_outcome", { "private": "sentinel" }),
      guidance_test_set(selected, "currentness", "historical"),
      guidance_test_set(selected, "currentness", "current"),
      guidance_test_set(
        selected,
        "query",
        guidance_test_set(query, "conditions", []),
      ),
      guidance_test_set(
        selected,
        "lesson",
        guidance_test_set(lesson, "applicability", [
          { "key": "customer_id", "value": "wrong-customer" },
        ]),
      ),
      guidance_test_set(
        selected,
        "lesson",
        guidance_test_set(
          lesson,
          "invalidation",
          native_field(query, "conditions"),
        ),
      ),
      guidance_test_set(
        selected,
        "review",
        guidance_test_set(native_field(selected, "review"), "reviewer_id", ""),
      ),
      guidance_test_set(
        selected, "book_origin", "https://book.example.test/?private=sentinel",
      ),
      guidance_test_set(selected, "observed_at", -1),
      guidance_test_set(
        selected,
        "lesson",
        guidance_test_set(lesson, "guidance", Json::string("x".repeat(8193))),
      ),
    ] {
    try @task_evidence.validate_guidance_selection(invalid, handoff) catch {
      _ => ()
    } noraise {
      _ => abort("invalid selected advice must reject")
    }
  }
  for key in ["revision", "projGuid", "product_id"] {
    let changed = guidance_test_set(
      task,
      key,
      if key == "revision" {
        Json::number(2)
      } else {
        Json::string("other")
      },
    )
    try native_book_guidance(changed, { "book_guidance": selected }) catch {
      _ => ()
    } noraise {
      _ => abort("changed task must reject old selection")
    }
  }
}

///|
test "captured guidance is private advisory input with stable digest and frozen resume" {
  let task = guidance_test_task()
  let selected = guidance_test_selection(task)
  let execution = native_execution_snapshot(
    task,
    "moongate/test",
    "owner",
    book_guidance=selected,
  )
  let request = @json.parse(native_text(execution, "request_body"))
  assert_true(native_text(request, "text").contains("GUIDANCE_SENTINEL"))
  assert_true(native_text(request, "text").contains("not additional authority"))
  let digest = native_text(execution, "book_guidance_sha256")
  let summary = @task_evidence.guidance_summary(selected, sha256=digest)
  assert_false(summary.stringify().contains("GUIDANCE_SENTINEL"))
  assert_false(summary.stringify().contains("applicability"))
  assert_false(summary.stringify().contains("curator"))
  assert_eq(native_text(summary, "state"), "captured_input")
  let public_execution : Json = { "book_guidance": summary }
  let public_task = guidance_test_set(task, "execution", public_execution)
  assert_eq(
    native_book_guidance(public_task, { "book_guidance": selected }),
    None,
  )
  assert_eq(native_book_guidance(public_task, {}), None)
  let changed = guidance_test_set(
    selected,
    "lesson",
    guidance_test_set(
      native_field(selected, "lesson"),
      "guidance",
      "new advice",
    ),
  )
  try native_book_guidance(public_task, { "book_guidance": changed }) catch {
    _ => ()
  } noraise {
    _ => abort("reserved guidance must stay frozen")
  }
  let reorder = match selected {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      let result : Map[String, Json] = Map([])
      for key in keys.rev() {
        result[key] = fields[key]
      }
      Json::object(result)
    }
    _ => selected
  }
  assert_eq(native_guidance_digest(reorder), digest)
  let numeric = @json.parse(
    selected
    .stringify()
    .replace_all(old="\"observed_at\":20", new="\"observed_at\":20.0"),
  )
  assert_eq(native_guidance_digest(numeric), digest)
  assert_eq(
    native_text(@json.parse(execution.stringify()), "request_body"),
    native_text(execution, "request_body"),
  )
}

///|
test "guidance and total native reservation retain explicit nontruncating limits" {
  let task = guidance_test_task()
  let selection = guidance_test_selection(task)
  let unicode = guidance_test_set(
    selection,
    "lesson",
    guidance_test_set(
      native_field(selection, "lesson"),
      "guidance",
      Json::string("汉".repeat(8192)),
    ),
  )
  @task_evidence.validate_guidance_selection(
    unicode,
    native_field(unicode, "handoff"),
  )
  let execution = native_execution_snapshot(
    task,
    "moongate/test",
    "owner",
    book_guidance=unicode,
  )
  assert_true(
    native_text(execution, "request_body").contains("汉".repeat(8192)),
  )
  assert_true(
    native_reservation_fits(native_reservation_body(task, {}, execution)),
  )
  assert_false(
    native_reservation_fits({ "large": Json::string("x".repeat(128 * 1024)) }),
  )
}
