///|
fn reply_service_value() -> Json {
  {
    "schema": "moonproj.offer-reply.v1",
    "offer_revision": 3,
    "respondent": "Buyer recorded by a different person",
    "received_at": "2026-10-05T09:15:00Z",
    "summary": "Please narrow the scope.\n\nWe only need one report.",
    "kind": "changes_requested",
    "evidence_kind": "human_observation",
    "source_reference": null,
    "supersedes_reply_id": null,
    "correction_reason": null,
  }
}

///|
fn reply_service_body() -> Json {
  {
    "offer_reply": reply_service_value(),
    "reply_base_revision": 3,
    "authority": offer_service_authority(),
  }
}

///|
fn reply_service_history() -> Json {
  {
    "task_id": "T",
    "offer_history": [
      {
        "revision": 3,
        "audit_state": "available",
        "offer_draft": offer_service_fixture(),
      },
    ],
    "offer_reply_history": [],
  }
}

///|
test "reply-only request retains actor and original offer identity separately" {
  let request = plan_task_reply_request("T", "P", reply_service_body(), "actor")
  assert_eq(json_text(request, "actor_id", ""), "actor")
  let changes = json_field(request, "changes").unwrap()
  assert_true(changes is Object(fields) && fields.length() == 1)
  let reply = json_field(changes, "offer_reply").unwrap()
  assert_eq(json_int(reply, "offer_revision", 0), 3)
  assert_eq(
    json_text(reply, "respondent", ""),
    "Buyer recorded by a different person",
  )
  assert_eq(
    json_text(reply, "summary", ""),
    "Please narrow the scope.\n\nWe only need one report.",
  )
  let cases : Array[(String, Json)] = [
    ("status", "done"),
    ("offer_draft", offer_service_fixture()),
    ("remarks", "Changed criterion"),
    ("execution", {}),
    ("cash", true),
    ("reply_base_revision", 0),
    ("reply_base_revision", 3.5),
    (
      "offer_reply",
      offer_service_replace(
        reply_service_value(),
        "offer_revision",
        4294967299.0,
      ),
    ),
    (
      "offer_reply",
      offer_service_replace(reply_service_value(), "offer_revision", 4),
    ),
    ("authority", offer_service_authority(actor="other")),
    ("authority", offer_service_authority(scope="project:other")),
    ("authority", offer_service_authority(capability="invoice:collect")),
  ]
  for (key, value) in cases {
    try
      plan_task_reply_request(
        "T",
        "P",
        offer_service_replace(reply_service_body(), key, value),
        "actor",
      )
    catch {
      CompanyServiceError::CommandRejected(status, _) =>
        assert_true(status == 422 || status == 403)
      _ => raise fail("unexpected reply request rejection")
    } noraise {
      _ => raise fail("mixed or unauthorized reply update accepted")
    }
  }
}

///|
test "reply history target must be one saved offer and correction retains its target" {
  let reply = reply_service_value()
  let history = reply_service_history()
  plan_task_reply_validate_history("T", history, reply)
  for
    altered in [
      offer_service_replace(history, "task_id", "other"),
      offer_service_replace(history, "offer_history", []),
      offer_service_replace(history, "offer_history", [
        { "revision": 3, "audit_state": "missing" },
      ]),
      offer_service_replace(history, "offer_history", [
        { "revision": 3, "audit_state": "available" },
        { "revision": 3, "audit_state": "available" },
      ]),
    ] {
    try plan_task_reply_validate_history("T", altered, reply) catch {
      CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 409)
      _ => raise fail("unexpected offer target rejection")
    } noraise {
      _ => raise fail("unresolved offer target accepted")
    }
  }
  let correction = offer_service_replace(
    offer_service_replace(reply, "supersedes_reply_id", "reply-first"),
    "correction_reason",
    "Corrected the transcription",
  )
  let first : Json = {
    "reply_id": "reply-first",
    "audit_state": "available",
    "offer_reply": reply,
  }
  let valid = offer_service_replace(history, "offer_reply_history", [first])
  plan_task_reply_validate_history("T", valid, correction)
  for
    altered in [
      history,
      offer_service_replace(history, "offer_reply_history", [
        offer_service_replace(first, "audit_state", "conflict"),
      ]),
      offer_service_replace(history, "offer_reply_history", [
        offer_service_replace(
          first,
          "offer_reply",
          offer_service_replace(reply, "offer_revision", 2),
        ),
      ]),
      offer_service_replace(history, "offer_reply_history", [
        first,
        { "reply_id": "reply-second", "offer_reply": correction },
      ]),
    ] {
    try plan_task_reply_validate_history("T", altered, correction) catch {
      CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 409)
      _ => raise fail("unexpected correction rejection")
    } noraise {
      _ => raise fail("unbound or already corrected reply accepted")
    }
  }
}

///|
test "reply projection changes no proposal task acceptance execution demand or money fields" {
  let task : Json = {
    "task_id": "T",
    "project_id": "P",
    "created_by": "actor",
    "state": "pending",
    "source_kind": "command",
    "remarks": "Original acceptance",
    "offer_draft": offer_service_fixture(),
    "execution_workspace": "/authorized/work",
    "accepted_report_id": null,
    "source_context": { "reference": "original", "problem": "Unchanged" },
  }
  let request = plan_task_reply_request("T", "P", reply_service_body(), "actor")
  let (command, audit, next) = plan_task_reply_payloads(
    "T", task, 3, request, "actor", "reply-first",
  )
  if task is Object(fields) {
    for key, value in fields {
      assert_eq(json_field(next, key), Some(value))
    }
  }
  assert_true(json_field(next, "offer_reply") is None)
  assert_false(next.stringify().contains("Please narrow"))
  assert_eq(
    json_text(json_field(next, "offer_draft").unwrap(), "demand_state", ""),
    "unproven",
  )
  let result = json_field(command, "result").unwrap()
  assert_eq(json_text(result, "reply_id", ""), "plan_task:update:reply-first")
  assert_eq(json_int(result, "revision", 0), 4)
  for key in ["cash_effect", "accounting_effect", "tax_effect"] {
    assert_eq(json_field(result, key), Some(false.to_json()))
  }
  assert_eq(json_text(audit, "action", ""), "plan.task.offer_reply")
  let list = plan_task_offer_public({ "taskGuid": "T" }, next, false)
  assert_false(list.stringify().contains("Please narrow"))
  let markdown = @task_evidence.offer_draft_markdown(
    json_field(next, "offer_draft").unwrap(),
    task_id="T",
    project_id="P",
    revision=4,
  )
  assert_false(markdown.contains("Please narrow"))
  let sql = plan_task_reply_sql("T", task, 3, request, "actor", "reply-first").replace_all(
    old="''",
    new="'",
  )
  for
    required in [
      "LOCK TABLE company_aggregate_projection",
      "LOCK TABLE company_record",
      "payload->>'state'='pending'",
      "payload->'execution'",
      "aggregate_type='task_report'",
      " = 3 AND NOT EXISTS",
      @postgres.sql_literal(command.stringify()),
      @postgres.sql_literal(audit.stringify()),
      @postgres.sql_literal(next.stringify()),
    ] {
    assert_true(sql.contains(required), msg=required)
  }
  assert_false(sql.contains("CREATE TABLE"))
}

///|
test "reply replay binds the exact actor task authority target content and original base" {
  let body = reply_service_body()
  let request = plan_task_reply_request("T", "P", body, "actor")
  let (command, _, _) = plan_task_reply_payloads(
    "T",
    { "state": "pending" },
    3,
    request,
    "actor",
    "reply-first",
  )
  assert_true(
    json_bool(
      plan_task_reply_replay(command, "T", body, "actor"),
      "idempotent_replay",
      false,
    ),
  )
  for
    (task, actor, altered) in [
      ("other", "actor", body),
      ("T", "other", body),
      ("T", "actor", offer_service_replace(body, "reply_base_revision", 4)),
      (
        "T",
        "actor",
        offer_service_replace(
          body,
          "offer_reply",
          offer_service_replace(reply_service_value(), "offer_revision", 2),
        ),
      ),
      (
        "T",
        "actor",
        offer_service_replace(
          body,
          "offer_reply",
          offer_service_replace(
            reply_service_value(),
            "summary",
            "Changed content",
          ),
        ),
      ),
      (
        "T",
        "actor",
        offer_service_replace(
          body,
          "authority",
          offer_service_authority(scope="project:other"),
        ),
      ),
    ] {
    try plan_task_reply_replay(command, task, altered, actor) catch {
      CompanyServiceError::CommandRejected(status, _) =>
        assert_true(status == 409 || status == 403)
      _ => raise fail("unexpected reply replay error")
    } noraise {
      _ => raise fail("changed operation replay accepted")
    }
  }
}
