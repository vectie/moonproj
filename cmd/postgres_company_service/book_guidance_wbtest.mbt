///|
test "execution readback exposes captured guidance references but no private guidance or prompt" {
  let selection : Json = {
    "query": {
      "target_task": {
        "record_id": "task",
        "record_version": "1",
        "record_digest": "task-digest",
      },
    },
    "lesson": {
      "reference": {
        "record_id": "lesson",
        "record_version": "1",
        "record_digest": "lesson-digest",
      },
      "title": "PRIVATE_TITLE",
      "guidance": "PRIVATE_GUIDANCE",
      "applicability": [{ "key": "customer_id", "value": "PRIVATE_CUSTOMER" }],
    },
    "review": {
      "receipt": {
        "record_id": "review",
        "record_version": "1",
        "record_digest": "review-digest",
      },
      "reviewer_id": "PRIVATE_PERSON",
    },
    "selection_review": null,
    "book_origin": "https://book.example.test",
    "observed_at": 20,
    "source": { "outcome": "PRIVATE_OUTCOME" },
    "handoff": { "task_snapshot": "PRIVATE_SNAPSHOT" },
  }
  let execution : Json = {
    "run_id": "run",
    "task_id": "task",
    "session_id": "session",
    "command_id": "command",
    "state": "queued",
    "request_body": "PRIVATE_PROMPT",
    "book_guidance": selection,
    "book_guidance_sha256": "retained-canonical-hash",
  }
  let public = plan_task_execution_public({
    "state": "pending",
    "execution": execution,
  })
  assert_false(public.stringify().contains("PRIVATE_"))
  let summary = json_field(public, "book_guidance").unwrap()
  assert_eq(
    json_text(summary, "schema", ""),
    "moonproj.book-guidance-capture.v1",
  )
  assert_eq(json_text(summary, "state", ""), "captured_input")
  assert_eq(json_text(summary, "sha256", ""), "retained-canonical-hash")
  assert_eq(
    json_field(summary, "lesson"),
    Some({
      "record_id": "lesson",
      "record_version": "1",
      "record_digest": "lesson-digest",
    }),
  )
  assert_eq(json_text(public, "acceptance", ""), "pending")
  let legacy = plan_task_execution_public({
    "state": "pending",
    "execution": { "state": "queued" },
  })
  assert_eq(json_field(legacy, "book_guidance"), None)
}
