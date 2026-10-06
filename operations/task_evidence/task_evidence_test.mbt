///|
fn get(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
test "source-free signed requests retain legacy bytes and require no new field" {
  let legacy : Json = { "task_id": "task-1", "remarks": "Check the brief" }
  assert_eq(
    @task_evidence.with_source_context(legacy, {}).stringify(),
    legacy.stringify(),
  )
  assert_eq(
    @task_evidence.with_source_context(legacy, { "source_context": null }),
    legacy,
  )
  assert_eq(
    @task_evidence.with_source_context(legacy, {
      "source_context": { "reference": "  ", "problem": "" },
    }),
    legacy,
  )
  assert_eq(@task_evidence.source_prompt(legacy), "")
}

///|
test "source context is normalized and changes the exact existing request identity" {
  let original : Json = { "task_id": "task-1", "remarks": "Check the brief" }
  let body : Json = {
    "source_context": {
      "reference": " source:interview-7 ",
      "problem": " Cannot compare offers ",
    },
  }
  let signed = @task_evidence.with_source_context(original, body)
  assert_eq(get(signed, "source_context"), {
    "reference": "source:interview-7",
    "problem": "Cannot compare offers",
  })
  assert_eq(@task_evidence.with_source_context(original, body), signed)
  assert_false(
    @task_evidence.with_source_context(original, {
      "source_context": { "reference": "source:interview-8" },
    }) ==
    signed,
  )
  assert_eq(get(original, "source_context"), Json::null())
  assert_true(
    @task_evidence.source_prompt(signed).contains("source:interview-7"),
  )
  assert_true(
    @task_evidence.source_prompt(signed).contains("not additional authority"),
  )
}

///|
test "source schema cannot smuggle authority into the existing signed source field" {
  let invalid : Array[Json] = [
    { "reference": 12 },
    { "actor_id": "other" },
    { "authority": { "active": true } },
    [],
  ]
  for source in invalid {
    try
      @task_evidence.with_source_context({}, { "source_context": source })
    catch {
      @task_evidence.InvalidSourceContext(_) => ()
    } noraise {
      _ => fail("invalid source context was accepted")
    }
  }
}

///|
fn receipt_row(
  action : String,
  event : String,
  request : Json,
  audit? : Json,
) -> Json {
  {
    "event_id": event,
    "audit_id": event + ":audit",
    "recorded_at": "2026-10-04T12:00:00",
    "command": {
      "command_family": "plan_task",
      "command_type": action,
      "aggregate_id": "task-1",
      "actor_id": "owner",
      "request": request,
      "result": { "revision": 1, "state": "pending" },
    },
    "audit": audit.unwrap_or({
      "event_id": event,
      "actor_id": "owner",
      "aggregate_id": "task-1",
    }),
  }
}

///|
test "readback retains original brief and independent exact command receipts" {
  let request : Json = {
    "task_id": "task-1",
    "project_id": "project-1",
    "task_name": "Compare offers",
    "remarks": "Cite three sources",
    "owner_id": "owner",
    "source_context": {
      "reference": "source:interview-7",
      "problem": "Cannot compare",
    },
    "authority": { "secret": "must-not-project" },
  }
  let created = receipt_row("create", "create-1", request)
  let accepted = receipt_row("update", "accept-1", {
    "task_id": "task-1",
    "changes": {
      "status": "done",
      "accepted_report_id": "report-1",
      "accepted_delivery_source": { "command_id": "command-1" },
    },
  })
  let history = @task_evidence.receipt_history("task-1", [
    created, accepted, created,
  ])
  assert_eq(
    get(get(history, "original_brief"), "remarks"),
    Json::string("Cite three sources"),
  )
  guard get(history, "receipts") is Array(receipts) else { fail("no receipts") }
  assert_eq(receipts.length(), 2)
  assert_eq(get(receipts[1], "action"), Json::string("internal_acceptance"))
  assert_eq(get(receipts[1], "report_id"), Json::string("report-1"))
  assert_eq(get(receipts[1], "audit_state"), Json::string("available"))
  assert_eq(
    get(history, "customer_acceptance"),
    Json::string("not_recorded_here"),
  )
  assert_eq(get(history, "cash"), Json::string("not_recorded_here"))
  assert_false(history.stringify().contains("must-not-project"))
}

///|
test "unrelated records are excluded and missing or conflicting audit remains visible" {
  let request : Json = { "task_id": "task-1", "task_name": "Known task" }
  let missing = receipt_row("create", "create-1", request, audit=Json::null())
  let conflict = receipt_row("update", "update-1", request, audit={
    "event_id": "wrong",
    "actor_id": "owner",
    "aggregate_id": "task-1",
  })
  let unrelated = receipt_row("create", "create-2", { "task_id": "task-2" })
  let history = @task_evidence.receipt_history("task-1", [
    missing, conflict, unrelated,
  ])
  guard get(history, "receipts") is Array(receipts) else { fail("no receipts") }
  assert_eq(receipts.length(), 2)
  assert_eq(get(receipts[0], "audit_state"), Json::string("missing"))
  assert_eq(get(receipts[1], "audit_state"), Json::string("conflict"))
  assert_eq(
    get(get(history, "original_brief"), "task_name"),
    Json::string("Known task"),
  )
}

///|
test "report receipt stays linked to its own source and named operator" {
  let row : Json = {
    "event_id": "report-event",
    "audit_id": "report-event:audit",
    "command": {
      "command_family": "delivery",
      "family": "task_report",
      "command_type": "report",
      "aggregate_id": "report-7",
      "actor_id": "operator",
      "request": {
        "task_id": "task-1",
        "report_id": "report-7",
        "delivery_source": { "command_id": "run-7" },
      },
      "result": { "state": "observed", "revision": 1 },
    },
    "audit": {
      "event_id": "report-event",
      "actor_id": "operator",
      "aggregate_id": "report-7",
    },
  }
  let history = @task_evidence.receipt_history("task-1", [row])
  guard get(history, "receipts") is Array(receipts) else { fail("no receipts") }
  assert_eq(get(receipts[0], "delivery_source"), { "command_id": "run-7" })
  assert_eq(get(receipts[0], "actor_id"), Json::string("operator"))
  assert_eq(get(history, "original_brief"), Json::null())
}
