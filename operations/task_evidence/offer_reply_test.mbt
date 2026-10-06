///|
fn reply_test_input(patch : Json) -> Json {
  let fields : Map[String, Json] = {
    "schema": Json::string("moonproj.offer-reply.v1"),
    "offer_revision": Json::number(1),
    "summary": Json::string("Please explain the timeline"),
    "kind": Json::string("changes_requested"),
    "evidence_kind": Json::string("human_observation"),
  }
  if patch is Object(changes) {
    for key, value in changes {
      fields[key] = value
    }
  }
  Json::object(fields)
}

///|
fn reply_test_row(event : String, revision : Json, reply : Json) -> Json {
  {
    "event_id": event,
    "audit_id": event + ":audit",
    "recorded_at": "2026-10-05T12:30:00Z",
    "command": {
      "kind": "company_command",
      "command_family": "plan_task",
      "command_type": "update",
      "aggregate_type": "plan_task",
      "aggregate_id": "task-1",
      "idempotency_key": "operation-" + event,
      "actor_id": "recorder-1",
      "request": {
        "command_type": "update",
        "task_id": "task-1",
        "project_id": "project-1",
        "actor_id": "recorder-1",
        "changes": { "offer_reply": reply },
        "authority": { "secret": "never-project" },
      },
      "result": {
        "task_id": "task-1",
        "taskGuid": "task-1",
        "actor_id": "recorder-1",
        "revision": revision,
        "event_id": event,
        "audit_id": event + ":audit",
      },
    },
    "audit": {
      "event_id": event,
      "actor_id": "recorder-1",
      "aggregate_id": "task-1",
      "project_id": "project-1",
      "revision": revision,
    },
  }
}

///|
test "offer reply receipt history retains explicit feedback to exact saved revision" {
  let row = reply_test_row("reply-1", Json::number(2), reply_test_input({}))
  let history = @task_evidence.receipt_history("task-1", [row])
  assert_true(get(history, "offer_reply_history") is Array([_]))
  assert_true(
    get(history, "receipts") is Array([{ "action": String("offer_reply"), .. }]),
  )
  assert_eq(
    get(history, "customer_acceptance"),
    Json::string("not_recorded_here"),
  )
  assert_eq(get(history, "cash"), Json::string("not_recorded_here"))
  assert_eq(get(history, "authorizing"), Json::boolean(false))
}

///|
test "offer reply receipt action distinguishes feedback without changing other update labels" {
  let row = reply_test_row(
    "reply-action",
    Json::number(2),
    reply_test_input({}),
  )
  let changes = get(get(get(row, "command"), "request"), "changes")
  if changes is Object(fields) {
    fields["status"] = Json::string("done")
  }
  assert_true(
    get(@task_evidence.receipt_history("task-1", [row]), "receipts")
    is Array([{ "action": String("offer_reply"), .. }]),
  )
  if changes is Object(fields) {
    fields.remove("offer_reply")
  }
  assert_true(
    get(@task_evidence.receipt_history("task-1", [row]), "receipts")
    is Array([{ "action": String("internal_acceptance"), .. }]),
  )
  if changes is Object(fields) {
    fields.remove("status")
  }
  assert_true(
    get(@task_evidence.receipt_history("task-1", [row]), "receipts")
    is Array([{ "action": String("update"), .. }]),
  )
}

///|
fn reply_test_invalid(value : Json) -> Unit raise {
  try @task_evidence.normalize_offer_reply(value) catch {
    @task_evidence.InvalidOfferReply(_) => ()
  } noraise {
    _ => fail("invalid offer reply was accepted")
  }
}

///|
fn reply_test_patch(key : String, value : String) -> Json {
  Json::object(Map::from_array([(key, Json::string(value))]))
}

///|
test "offer reply contract normalizes the complete raw multiline object exactly" {
  let input = reply_test_input({
    "offer_revision": 7,
    "respondent": "  Example buyer  ",
    "received_at": "2024-02-29T23:59:59Z",
    "summary": "  One\r\nTwo\rThree\nFour\n\n\tIndented line  ",
    "kind": "interested",
    "evidence_kind": "reference",
    "source_reference": "  email:message-7\r\nQuoted section  ",
    "supersedes_reply_id": "  reply-previous  ",
    "correction_reason": "  Corrected speaker\r\nKept original meaning  ",
  })
  let normalized = @task_evidence.normalize_offer_reply(input)
  let expected : Json = {
    "schema": "moonproj.offer-reply.v1",
    "offer_revision": 7,
    "respondent": "Example buyer",
    "received_at": "2024-02-29T23:59:59Z",
    "summary": "One\nTwo\nThree\nFour\n\n\tIndented line",
    "kind": "interested",
    "evidence_kind": "reference",
    "source_reference": "email:message-7\nQuoted section",
    "supersedes_reply_id": "reply-previous",
    "correction_reason": "Corrected speaker\nKept original meaning",
  }
  assert_eq(normalized, expected)
  assert_eq(@task_evidence.normalize_offer_reply(normalized), expected)
  assert_true(normalized is Object(fields) && fields.length() == 10)
  assert_eq(
    get(input, "summary"),
    Json::string("  One\r\nTwo\rThree\nFour\n\n\tIndented line  "),
  )
}

///|
test "offer reply unknown respondent time and reference remain explicitly unknown" {
  let normalized = @task_evidence.normalize_offer_reply(reply_test_input({}))
  for
    key in [
      "respondent", "received_at", "source_reference", "supersedes_reply_id", "correction_reason",
    ] {
    assert_eq(get(normalized, key), Json::null())
    assert_eq(
      get(
        @task_evidence.normalize_offer_reply(
          reply_test_input(reply_test_patch(key, " \t\r\n ")),
        ),
        key,
      ),
      Json::null(),
    )
  }
  for kind in ["interested", "changes_requested", "declined", "other"] {
    assert_eq(
      get(
        @task_evidence.normalize_offer_reply(reply_test_input({ "kind": kind })),
        "kind",
      ),
      Json::string(kind),
    )
  }
  assert_eq(
    get(
      @task_evidence.normalize_offer_reply(
        reply_test_input({ "offer_revision": 9007199254740991.0 }),
      ),
      "offer_revision",
    ),
    Json::number(9007199254740991.0),
  )
}

///|
test "offer reply schema types correction and reference requirements are strict" {
  for
    value in [
      Json::null(),
      Json::array([]),
      Json::string("reply"),
      Json::object(Map([])),
    ] {
    reply_test_invalid(value)
  }
  let invalid : Array[Json] = [
    { "schema": "moonproj.offer-reply.v2" },
    { "schema": " moonproj.offer-reply.v1" },
    { "schema": null },
    { "offer_revision": 0 },
    { "offer_revision": -1 },
    { "offer_revision": 1.5 },
    { "offer_revision": "1" },
    { "offer_revision": null },
    { "offer_revision": 9007199254740992.0 },
    { "kind": "accepted" },
    { "kind": "interested " },
    { "kind": null },
    { "evidence_kind": "authenticated" },
    { "evidence_kind": null },
    { "summary": null },
    { "summary": " \n\r\t " },
    { "summary": 1 },
    { "respondent": [] },
    { "received_at": true },
    { "source_reference": {} },
    { "supersedes_reply_id": 1 },
    { "correction_reason": [] },
    { "evidence_kind": "reference" },
    { "evidence_kind": "reference", "source_reference": " \n " },
    { "supersedes_reply_id": "reply-1" },
    { "supersedes_reply_id": "reply-1", "correction_reason": " \t " },
    { "actor_id": "pretend-recorder" },
    { "authority": { "approved": true } },
    { "cash": true },
  ]
  for patch in invalid {
    reply_test_invalid(reply_test_input(patch))
  }
  let correction = @task_evidence.normalize_offer_reply(
    reply_test_input({
      "supersedes_reply_id": "reply-1",
      "correction_reason": "Misheard the timeline",
    }),
  )
  assert_eq(get(correction, "supersedes_reply_id"), Json::string("reply-1"))
  assert_eq(
    get(correction, "correction_reason"),
    Json::string("Misheard the timeline"),
  )
}

///|
test "offer reply timestamps validate UTC seconds and Gregorian dates" {
  for
    timestamp in [
      "0001-01-01T00:00:00Z", "2000-02-29T12:34:56Z", "2024-02-29T23:59:59Z", "9999-12-31T23:59:59Z",
    ] {
    assert_eq(
      get(
        @task_evidence.normalize_offer_reply(
          reply_test_input({ "received_at": timestamp }),
        ),
        "received_at",
      ),
      Json::string(timestamp),
    )
  }
  for
    timestamp in [
      "0000-01-01T00:00:00Z", "1900-02-29T12:00:00Z", "2026-02-29T12:00:00Z", "2026-04-31T12:00:00Z",
      "2026-00-01T12:00:00Z", "2026-13-01T12:00:00Z", "2026-10-00T12:00:00Z", "2026-10-05T24:00:00Z",
      "2026-10-05T23:60:00Z", "2026-10-05T23:59:60Z", "2026-10-05T-1:00:00Z", "2026-10-05T0a:00:00Z",
      "2026-10-05t12:00:00Z", "2026-10-05T12:00:00z", "2026-10-05 12:00:00Z", "2026-10-05T12:00:00+00:00",
      "2026-10-05T12:00:00.000Z", "2026-10-05", "unknown", "2026-1-05T12:00:00Z",
    ] {
    reply_test_invalid(reply_test_input({ "received_at": timestamp }))
  }
}

///|
test "offer reply text rejects controls and enforces character and byte bounds" {
  for
    key in [
      "summary", "respondent", "source_reference", "supersedes_reply_id", "correction_reason",
    ] {
    for
      value in [
        "NUL\u0000text", "ESC\u001btext", "DEL\u007ftext", "C1\u0085text", "bidi\u202etext",
        "line\u2028text", "isolate\u2066text", "mark\u061ctext",
      ] {
      let patch : Json = { "correction_reason": "Known correction" }
      if patch is Object(fields) {
        fields[key] = Json::string(value)
      }
      reply_test_invalid(reply_test_input(patch))
    }
  }
  for
    (key, limit) in [
      ("summary", 8192),
      ("respondent", 512),
      ("source_reference", 2048),
      ("supersedes_reply_id", 512),
      ("correction_reason", 2048),
    ] {
    let text = offer_test_repeat("x", limit)
    let patch : Json = { "correction_reason": "Known correction" }
    if patch is Object(fields) {
      fields[key] = Json::string(text)
    }
    assert_eq(
      get(@task_evidence.normalize_offer_reply(reply_test_input(patch)), key),
      Json::string(text),
    )
    if patch is Object(fields) {
      fields[key] = Json::string(text + "x")
    }
    reply_test_invalid(reply_test_input(patch))
  }
  let unicode = offer_test_repeat("😀", 512)
  assert_eq(
    get(
      @task_evidence.normalize_offer_reply(
        reply_test_input({ "respondent": unicode }),
      ),
      "respondent",
    ),
    Json::string(unicode),
  )
  reply_test_invalid(reply_test_input({ "respondent": unicode + "😀" }))
  assert_true(
    @task_evidence.normalize_offer_reply(
      reply_test_input({ "summary": offer_test_repeat("😀", 8000) }),
    )
    is Object(_),
  )
  reply_test_invalid(
    reply_test_input({ "summary": offer_test_repeat("😀", 8192) }),
  )
}

///|
test "offer reply history retains original correction and precise independent revisions" {
  let original = reply_test_row(
    "reply-1",
    Json::number(2),
    reply_test_input({ "respondent": "Customer claim", "kind": "interested" }),
  )
  let correction = reply_test_row(
    "reply-2",
    Json::number(4),
    reply_test_input({
      "summary": "Correction\nThey asked for changes",
      "supersedes_reply_id": "reply-1",
      "correction_reason": "Misheard first call",
    }),
  )
  let later_offer = offer_test_row(
    "update",
    "offer-later",
    Json::number(3),
    offer_test_input({ "title": "Later proposal" }),
  )
  let history = @task_evidence.offer_reply_history("task-1", [
    original, later_offer, correction, original,
  ])
  assert_eq(history.length(), 2)
  assert_true(history[0] is Object(fields) && fields.length() == 12)
  assert_eq(get(history[0], "reply_id"), Json::string("reply-1"))
  assert_eq(get(history[1], "reply_id"), Json::string("reply-2"))
  assert_eq(get(history[0], "record_revision"), Json::number(2))
  assert_eq(get(history[1], "record_revision"), Json::number(4))
  for entry in history {
    assert_eq(get(get(entry, "offer_reply"), "offer_revision"), Json::number(1))
    assert_eq(get(entry, "recorded_by"), Json::string("recorder-1"))
    assert_eq(get(entry, "recorded_at"), Json::string("2026-10-05T12:30:00Z"))
    assert_eq(get(entry, "audit_state"), Json::string("available"))
    assert_eq(get(entry, "customer_acceptance"), Json::string("not_asserted"))
    assert_eq(get(entry, "cash"), Json::string("not_asserted"))
    assert_eq(get(entry, "authorizing"), Json::boolean(false))
  }
  assert_eq(
    get(get(history[0], "offer_reply"), "kind"),
    Json::string("interested"),
  )
  assert_eq(
    get(get(history[1], "offer_reply"), "supersedes_reply_id"),
    Json::string("reply-1"),
  )
  assert_eq(
    get(history[1], "idempotency_key"),
    Json::string("operation-reply-2"),
  )
  assert_false(Json::array(history).stringify().contains("never-project"))
  assert_false(Json::array(history).stringify().contains("Later proposal"))
}

///|
fn reply_test_history_state(row : Json) -> Json raise {
  let history = @task_evidence.offer_reply_history("task-1", [row])
  assert_eq(history.length(), 1)
  get(history[0], "audit_state")
}

///|
test "offer reply history excludes malformed bodies targets actions and record revisions" {
  assert_eq(@task_evidence.offer_reply_history(" ", []), [])
  let row = reply_test_row("reply-1", Json::number(2), reply_test_input({}))
  assert_eq(@task_evidence.offer_reply_history("task-2", [row]), [])
  for
    revision in [
      Json::null(),
      Json::number(0),
      Json::number(-1),
      Json::number(1.5),
      Json::string("2"),
      Json::number(9007199254740992.0),
    ] {
    assert_eq(
      @task_evidence.offer_reply_history("task-1", [
        reply_test_row("reply", revision, reply_test_input({})),
      ]),
      [],
    )
  }
  for
    reply in [
      Json::null(),
      Json::object(Map([])),
      reply_test_input({ "schema": "bad" }),
    ] {
    assert_eq(
      @task_evidence.offer_reply_history("task-1", [
        reply_test_row("reply", Json::number(2), reply),
      ]),
      [],
    )
  }
  for
    (key, value) in [
      ("command_type", "create"),
      ("command_type", "delete"),
      ("command_family", "delivery"),
      ("aggregate_id", "task-2"),
    ] {
    let wrong = reply_test_row("reply", Json::number(2), reply_test_input({}))
    if get(wrong, "command") is Object(command) {
      command[key] = Json::string(value)
    }
    assert_eq(@task_evidence.offer_reply_history("task-1", [wrong]), [])
  }
  let wrong_task = reply_test_row(
    "reply",
    Json::number(2),
    reply_test_input({}),
  )
  if get(get(wrong_task, "command"), "request") is Object(request) {
    request["task_id"] = Json::string("task-2")
  }
  assert_eq(@task_evidence.offer_reply_history("task-1", [wrong_task]), [])
  for event in ["", " \t "] {
    assert_eq(
      @task_evidence.offer_reply_history("task-1", [
        reply_test_row(event, Json::number(2), reply_test_input({})),
      ]),
      [],
    )
  }
}

///|
test "offer reply history exposes missing audit while malformed lineage stays conflict" {
  let missing = reply_test_row("reply", Json::number(2), reply_test_input({}))
  if missing is Object(row) {
    row["audit"] = Json::null()
    row["recorded_at"] = { "authority": "hidden-time" }
  }
  assert_eq(reply_test_history_state(missing), Json::string("missing"))
  let projected = @task_evidence.offer_reply_history("task-1", [missing])
  assert_eq(get(projected[0], "recorded_at"), Json::null())
  assert_false(Json::array(projected).stringify().contains("hidden-time"))
  for offer_revision in [2, 3] {
    assert_eq(
      reply_test_history_state(
        reply_test_row(
          "reply",
          Json::number(2),
          reply_test_input({ "offer_revision": offer_revision }),
        ),
      ),
      Json::string("conflict"),
    )
  }
  for
    (part, keys) in [
      (
        "command",
        [
          "kind", "aggregate_type", "actor_id", "idempotency_key", "project_id",
          "projectGuid",
        ],
      ),
      (
        "request",
        ["command_type", "actor_id", "taskGuid", "project_id", "projectGuid"],
      ),
      (
        "result",
        [
          "task_id", "taskGuid", "aggregate_id", "actor_id", "event_id", "audit_id",
          "project_id", "projectGuid",
        ],
      ),
      (
        "audit",
        [
          "aggregate_id", "task_id", "taskGuid", "actor_id", "event_id", "audit_id",
          "revision", "project_id", "projectGuid",
        ],
      ),
    ] {
    for key in keys {
      for
        bad in [
          Json::null(),
          Json::string("wrong"),
          Json::string(""),
          Json::number(7),
        ] {
        if key == "idempotency_key" && bad == Json::string("wrong") {
          continue
        }
        let row = reply_test_row("reply", Json::number(2), reply_test_input({}))
        let target = if part == "command" || part == "audit" {
          get(row, part)
        } else {
          get(get(row, "command"), part)
        }
        if target is Object(fields) {
          fields[key] = bad
        }
        assert_eq(reply_test_history_state(row), Json::string("conflict"))
      }
    }
  }
}

///|
test "offer reply receipt history remains additive and never alters offer Markdown" {
  let offer = offer_test_input({ "title": "Exact saved proposal" })
  let offer_row = offer_test_row("create", "offer-1", Json::number(1), offer)
  let reply_row = reply_test_row(
    "reply-1",
    Json::number(2),
    reply_test_input({ "summary": "Private response body" }),
  )
  let with_reply = @task_evidence.receipt_history("task-1", [
    offer_row, reply_row,
  ])
  let without_reply = @task_evidence.receipt_history("task-1", [offer_row])
  assert_eq(get(without_reply, "offer_reply_history"), Json::null())
  assert_eq(
    get(with_reply, "offer_history"),
    get(without_reply, "offer_history"),
  )
  assert_eq(
    get(with_reply, "original_brief"),
    get(without_reply, "original_brief"),
  )
  let markdown = @task_evidence.offer_draft_markdown(
    offer,
    task_id="task-1",
    project_id="project-1",
    revision=1,
  )
  assert_false(markdown.contains("Private response body"))
  assert_false(
    @task_evidence.offer_draft_summary(offer)
    .stringify()
    .contains("Private response body"),
  )
}

///|
test "offer reply history tolerates omitted legacy markers but checks all supplied aliases" {
  let row : Json = {
    "event_id": "legacy-reply",
    "audit_id": "legacy-reply:audit",
    "command": {
      "command_family": "plan_task",
      "command_type": "update",
      "aggregate_id": "task-1",
      "actor_id": "recorder-1",
      "idempotency_key": "legacy-operation",
      "request": {
        "task_id": "task-1",
        "changes": { "offer_reply": reply_test_input({}) },
      },
      "result": { "revision": 2 },
    },
    "audit": {
      "event_id": "legacy-reply",
      "actor_id": "recorder-1",
      "task_id": "task-1",
    },
  }
  assert_eq(reply_test_history_state(row), Json::string("available"))
  if get(row, "audit") is Object(audit) {
    audit["aggregate_id"] = Json::string("task-2")
  }
  assert_eq(reply_test_history_state(row), Json::string("conflict"))
  if row is Object(fields) {
    fields["audit"] = Json::null()
  }
  assert_eq(reply_test_history_state(row), Json::string("missing"))
  if get(get(row, "command"), "result") is Object(result) {
    result["task_id"] = Json::string("task-2")
  }
  assert_eq(reply_test_history_state(row), Json::string("conflict"))
}
