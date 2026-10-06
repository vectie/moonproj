///|
fn offer_test_input(patch : Json) -> Json {
  let fields : Map[String, Json] = {
    "schema": Json::string("moonproj.offer-draft.v1"),
    "state": Json::string("draft"),
    "demand_state": Json::string("unproven"),
  }
  if patch is Object(changes) {
    for key, value in changes {
      fields[key] = value
    }
  }
  Json::object(fields)
}

///|
fn offer_test_invalid(value : Json) -> Unit raise {
  try @task_evidence.normalize_offer_draft(value) catch {
    @task_evidence.InvalidOfferDraft(_) => ()
  } noraise {
    _ => fail("invalid offer draft was accepted")
  }
}

///|
fn offer_test_repeat(value : String, count : Int) -> String {
  let result = StringBuilder()
  for _ in 0..<count {
    result.write_string(value)
  }
  result.to_string()
}

///|
test "offer sparse content has explicit stable defaults and unresolved fields" {
  let input = offer_test_input({})
  let draft = @task_evidence.normalize_offer_draft(input)
  assert_eq(@task_evidence.normalize_offer_draft(draft), draft)
  assert_true(draft is Object(fields) && fields.length() == 19)
  assert_eq(get(draft, "title"), Json::string(""))
  for
    key in [
      "buyer", "buyer_reference", "problem", "problem_observed_on", "scope", "exclusions",
      "price_amount", "price_currency", "price_basis", "timing", "dependencies",
      "proof_sought", "closure_reason",
    ] {
    assert_eq(get(draft, key), Json::null())
  }
  assert_eq(get(draft, "deliverables"), Json::array([]))
  assert_eq(get(draft, "acceptance_criteria"), Json::array([]))
  assert_eq(@task_evidence.offer_draft_unresolved(input), [
    "title", "buyer", "buyer_reference", "problem", "problem_observed_on", "scope",
    "exclusions", "deliverables", "acceptance_criteria", "price_amount", "price_currency",
    "price_basis", "timing", "dependencies", "proof_sought",
  ])
  assert_eq(get(input, "buyer"), Json::null())
  assert_true(input is Object(fields) && fields.length() == 3)
}

///|
test "offer contract markers and field types are strict" {
  for
    value in [
      Json::null(),
      Json::array([]),
      Json::string("offer"),
      Json::object(Map([])),
    ] {
    offer_test_invalid(value)
  }
  let invalid : Array[Json] = [
    { "schema": null },
    { "schema": "moonproj.offer-draft.v2" },
    { "schema": " moonproj.offer-draft.v1" },
    { "state": null },
    { "state": "accepted" },
    { "state": "draft " },
    { "demand_state": null },
    { "demand_state": "proven" },
    { "actor_id": "owner" },
    { "authority": { "approved": true } },
    { "token": "secret" },
    { "title": 12 },
    { "buyer": [] },
    { "problem": true },
    { "scope": {} },
    { "deliverables": "one" },
    { "deliverables": [null] },
    { "acceptance_criteria": ["one", 2] },
    { "closure_reason": false },
  ]
  for patch in invalid {
    offer_test_invalid(offer_test_input(patch))
  }
}

///|
test "offer text normalization preserves ordered duplicates and line meaning" {
  let draft = @task_evidence.normalize_offer_draft(
    offer_test_input({
      "title": "  Narrow service  ",
      "buyer": " \t ",
      "problem": "One\r\nTwo\rThree\nFour",
      "deliverables": ["  one  ", "", " \n ", "one", "two"],
      "acceptance_criteria": null,
    }),
  )
  assert_eq(get(draft, "title"), Json::string("Narrow service"))
  assert_eq(get(draft, "buyer"), Json::null())
  assert_eq(get(draft, "problem"), Json::string("One\nTwo\nThree\nFour"))
  assert_eq(get(draft, "deliverables"), Json::array(["one", "one", "two"]))
  assert_eq(get(draft, "acceptance_criteria"), Json::array([]))
  for
    bad in [
      "NUL\u0000text", "escape\u001btext", "delete\u007ftext", "bidi\u202etext",
      "line\u2028text",
    ] {
    offer_test_invalid(offer_test_input({ "problem": bad }))
  }
}

///|
test "offer price uses exact decimal text and each missing side stays unresolved" {
  for
    amount in [
      "0", "0.00", "00.10", "123456789012345678901234567890.12", " 25.50 ",
    ] {
    let draft = @task_evidence.normalize_offer_draft(
      offer_test_input({ "price_amount": amount }),
    )
    assert_eq(
      get(draft, "price_amount"),
      Json::string(amount.trim().to_owned()),
    )
    let unresolved = @task_evidence.offer_draft_unresolved(draft)
    assert_false(unresolved.contains("price_amount"))
    assert_true(unresolved.contains("price_currency"))
  }
  let only_currency = offer_test_input({ "price_currency": "USD" })
  let unresolved = @task_evidence.offer_draft_unresolved(only_currency)
  assert_true(unresolved.contains("price_amount"))
  assert_false(unresolved.contains("price_currency"))
  let invalid : Array[Json] = [
    { "price_amount": 0 },
    { "price_amount": "-0" },
    { "price_amount": "+1" },
    { "price_amount": "1e3" },
    { "price_amount": "1,000" },
    { "price_amount": ".50" },
    { "price_amount": "1." },
    { "price_amount": "1.001" },
    { "price_amount": "1.2.3" },
    { "price_amount": "NaN" },
    { "price_amount": "١" },
    { "price_amount": "1 2" },
    { "price_currency": "usd" },
    { "price_currency": "US" },
    { "price_currency": "USDD" },
    { "price_currency": "U$D" },
  ]
  for patch in invalid {
    offer_test_invalid(offer_test_input(patch))
  }
}

///|
test "offer observed date validates Gregorian calendar boundaries" {
  for
    date in [
      "2024-02-29", "2000-02-29", "2026-04-30", "0001-01-01", "9999-12-31",
    ] {
    assert_eq(
      get(
        @task_evidence.normalize_offer_draft(
          offer_test_input({ "problem_observed_on": date }),
        ),
        "problem_observed_on",
      ),
      Json::string(date),
    )
  }
  for
    date in [
      "2026-02-29", "1900-02-29", "2026-04-31", "0000-01-01", "2026-00-10", "2026-13-01",
      "2026-01-00", "2026-1-01", "2026-10-05T00:00:00Z", "today",
    ] {
    offer_test_invalid(offer_test_input({ "problem_observed_on": date }))
  }
}

///|
test "offer content limits count Unicode characters and canonical UTF8 bytes" {
  let unicode_title = offer_test_repeat("😀", 256)
  let valid = @task_evidence.normalize_offer_draft(
    offer_test_input({ "title": unicode_title, "buyer": unicode_title }),
  )
  assert_eq(get(valid, "title"), Json::string(unicode_title))
  offer_test_invalid(offer_test_input({ "title": unicode_title + "😀" }))
  offer_test_invalid(offer_test_input({ "buyer": unicode_title + "😀" }))
  let long_text = offer_test_repeat("x", 8192)
  assert_eq(
    get(
      @task_evidence.normalize_offer_draft(
        offer_test_input({ "problem": long_text }),
      ),
      "problem",
    ),
    Json::string(long_text),
  )
  offer_test_invalid(offer_test_input({ "problem": long_text + "x" }))
  let item = offer_test_repeat("😀", 2048)
  assert_true(
    @task_evidence.normalize_offer_draft(
      offer_test_input({ "deliverables": [item] }),
    )
    is Object(_),
  )
  offer_test_invalid(offer_test_input({ "deliverables": [item + "😀"] }))
  let entries : Array[Json] = []
  for _ in 0..<32 {
    entries.push(Json::string("one"))
  }
  assert_true(
    @task_evidence.normalize_offer_draft(
      offer_test_input({ "deliverables": entries }),
    )
    is Object(_),
  )
  entries.push(Json::string(""))
  offer_test_invalid(offer_test_input({ "deliverables": entries }))
  let multibyte = offer_test_repeat("😀", 8192)
  assert_true(
    @task_evidence.normalize_offer_draft(
      offer_test_input({ "problem": multibyte }),
    )
    is Object(_),
  )
  offer_test_invalid(
    offer_test_input({ "problem": multibyte, "scope": multibyte }),
  )
  offer_test_invalid(
    offer_test_input({
      "problem": long_text,
      "scope": long_text,
      "exclusions": long_text,
      "timing": long_text,
      "dependencies": long_text,
      "proof_sought": long_text,
      "buyer_reference": long_text,
      "price_basis": long_text,
    }),
  )
}

///|
test "offer closure preserves reason and never claims demand or completeness" {
  offer_test_invalid(offer_test_input({ "state": "closed" }))
  offer_test_invalid(
    offer_test_input({ "state": "closed", "closure_reason": " \n " }),
  )
  let draft = @task_evidence.normalize_offer_draft(
    offer_test_input({
      "title": "Try one offer",
      "state": "closed",
      "closure_reason": " Buyer declined ",
    }),
  )
  assert_eq(get(draft, "closure_reason"), Json::string("Buyer declined"))
  assert_eq(get(draft, "demand_state"), Json::string("unproven"))
  assert_true(
    @task_evidence.offer_draft_unresolved(draft).contains("price_amount"),
  )
  assert_false(
    @task_evidence.offer_draft_unresolved(draft).contains("closure_reason"),
  )
  let summary = @task_evidence.offer_draft_summary(draft)
  assert_true(summary is Object(fields) && fields.length() == 5)
  assert_eq(
    get(summary, "schema"),
    Json::string("moonproj.offer-draft-summary.v1"),
  )
  assert_eq(get(summary, "state"), Json::string("closed"))
  assert_eq(get(summary, "title"), Json::string("Try one offer"))
  assert_false(summary.stringify().contains("Buyer declined"))
}

///|
test "offer Markdown has deterministic local and exact saved-source labels" {
  let input = offer_test_input({
    "title": "Pilot",
    "price_amount": "0",
    "price_currency": "USD",
    "state": "closed",
    "closure_reason": "No fit",
  })
  let local_export = @task_evidence.offer_draft_markdown(
    input,
    task_id="",
    project_id="",
    revision=0,
  )
  assert_true(
    local_export.contains(
      "Local draft export. No canonical saved revision is established.",
    ),
  )
  assert_false(local_export.contains("Task revision:"))
  assert_true(local_export.contains("Offer state: closed"))
  assert_true(local_export.contains("Demand state: unproven"))
  assert_true(local_export.contains("## Closure reason\n\n> No fit\n"))
  assert_true(local_export.contains("## Price amount\n\n> 0\n"))
  assert_true(local_export.contains("## Unresolved fields\n\n- buyer\n"))
  for
    (task, project, revision) in [
      ("task-1", "project-1", 0),
      ("", "project-1", 2),
      ("task-1", "", 2),
      ("task-1", "project-1", -1),
    ] {
    assert_true(
      @task_evidence.offer_draft_markdown(
        input,
        task_id=task,
        project_id=project,
        revision~,
      ).contains("Local draft export."),
    )
  }
  let saved = @task_evidence.offer_draft_markdown(
    input,
    task_id="task-1",
    project_id="project-1",
    revision=7,
  )
  assert_true(saved.contains("Canonical task-linked offer draft"))
  assert_true(saved.contains("Task:\n\n> task\\-1\n"))
  assert_true(saved.contains("Project:\n\n> project\\-1\n"))
  assert_true(saved.contains("Task revision: 7\n"))
  assert_false(saved.contains("Local draft export."))
  assert_eq(
    saved,
    @task_evidence.offer_draft_markdown(
      @task_evidence.normalize_offer_draft(input),
      task_id="task-1",
      project_id="project-1",
      revision=7,
    ),
  )
}

///|
test "offer Markdown escapes hostile text within quoted content boundaries" {
  let hostile = "# Source\n\n## Status\nDemand state: proven\n<script>alert(1)</script>\n[x](javascript:alert(1))\n```html\n</blockquote>\n&amp; &#35;\n---\n> outside\n![image](https://example.invalid)"
  let rendered = @task_evidence.offer_draft_markdown(
    offer_test_input({ "problem": hostile, "deliverables": [hostile] }),
    task_id="task\n## Forged",
    project_id="<iframe>",
    revision=3,
  )
  assert_false(rendered.contains("\n# Source\n"))
  assert_false(rendered.contains("\n## Forged\n"))
  assert_false(rendered.contains("<script>"))
  assert_false(rendered.contains("</blockquote>"))
  assert_false(rendered.contains("[x](javascript:"))
  assert_false(rendered.contains("```html"))
  assert_false(rendered.contains("<iframe>"))
  assert_true(rendered.contains("> \\# Source\n> \n> \\#\\# Status\n"))
  assert_true(rendered.contains("&lt;script&gt;alert\\(1\\)&lt;\\/script&gt;"))
  assert_true(rendered.contains("&amp;amp\\; &amp;\\#35\\;"))
  assert_eq(rendered.split("\n## Status\n").count(), 2)
  assert_eq(rendered.split("\n## Source\n").count(), 2)
  assert_eq(rendered.split("\n## Unresolved fields\n").count(), 2)
}

///|
fn offer_test_row(
  action : String,
  event : String,
  revision : Json,
  offer : Json,
  audit? : Json,
) -> Json {
  let request : Json = if action == "create" {
    { "task_id": "task-1", "offer_draft": offer }
  } else {
    { "task_id": "task-1", "changes": { "offer_draft": offer } }
  }
  {
    "event_id": event,
    "audit_id": event + ":audit",
    "recorded_at": "2026-10-05T00:00:00Z",
    "command": {
      "command_family": "plan_task",
      "command_type": action,
      "aggregate_id": "task-1",
      "idempotency_key": "operation-" + event,
      "actor_id": "private-actor",
      "request": request,
      "result": { "revision": revision },
      "authority": "must-not-project",
    },
    "audit": audit.unwrap_or({
      "event_id": event,
      "actor_id": "private-actor",
      "aggregate_id": "task-1",
    }),
  }
}

///|
test "offer history retains exact revisions closure and retry identity without authority" {
  let draft = offer_test_input({ "title": "First" })
  let closed = offer_test_input({
    "title": "Second",
    "state": "closed",
    "closure_reason": "No response",
  })
  let first = offer_test_row("create", "event-1", Json::number(1), draft)
  let second = offer_test_row("update", "event-2", Json::number(3), closed)
  let history = @task_evidence.offer_draft_history("task-1", [
    first, second, first,
  ])
  assert_eq(history.length(), 2)
  assert_true(history[0] is Object(fields) && fields.length() == 7)
  assert_eq(get(history[0], "revision"), Json::number(1))
  assert_eq(get(history[1], "revision"), Json::number(3))
  assert_eq(
    get(history[1], "idempotency_key"),
    Json::string("operation-event-2"),
  )
  assert_eq(get(history[1], "audit_state"), Json::string("available"))
  assert_eq(
    get(get(history[1], "offer_draft"), "closure_reason"),
    Json::string("No response"),
  )
  assert_eq(get(get(history[0], "offer_draft"), "title"), Json::string("First"))
  assert_false(Json::array(history).stringify().contains("private-actor"))
  assert_false(Json::array(history).stringify().contains("must-not-project"))
  assert_eq(@task_evidence.offer_draft_history("task-2", [first]), [])
  assert_eq(@task_evidence.offer_draft_history("", [first]), [])
}

///|
test "offer history excludes malformed offers actions revisions and keeps audit anomalies" {
  let draft = offer_test_input({})
  let missing = offer_test_row(
    "update",
    "missing",
    Json::number(1),
    draft,
    audit=Json::null(),
  )
  let conflict = offer_test_row("update", "conflict", Json::number(2), draft, audit={
    "event_id": "wrong",
    "actor_id": "private-actor",
    "aggregate_id": "task-1",
  })
  let rows = [
    missing,
    conflict,
    offer_test_row("delete", "delete", Json::number(3), draft),
    offer_test_row("update", "invalid", Json::number(4), {}),
    offer_test_row("update", "empty", Json::number(4), Json::null()),
    offer_test_row("create", "", Json::number(4), draft),
  ]
  for
    revision in [
      Json::null(),
      Json::number(0),
      Json::number(-1),
      Json::number(1.5),
      Json::string("2"),
      Json::number(9007199254740992.0),
    ] {
    rows.push(offer_test_row("update", "bad-revision", revision, draft))
  }
  let history = @task_evidence.offer_draft_history("task-1", rows)
  assert_eq(history.length(), 2)
  assert_eq(get(history[0], "audit_state"), Json::string("missing"))
  assert_eq(get(history[1], "audit_state"), Json::string("conflict"))
}

///|
test "offer history metadata cannot project nested authority" {
  let row = offer_test_row(
    "create",
    "event",
    Json::number(1),
    offer_test_input({}),
  )
  if row is Object(fields) {
    fields["recorded_at"] = { "authority": "hidden-metadata" }
  }
  let history = @task_evidence.offer_draft_history("task-1", [row])
  assert_eq(history.length(), 1)
  assert_eq(get(history[0], "recorded_at"), Json::null())
  assert_false(Json::array(history).stringify().contains("hidden-metadata"))
}

///|
fn offer_test_history_state(row : Json) -> Json raise {
  let history = @task_evidence.offer_draft_history("task-1", [row])
  assert_eq(history.length(), 1)
  get(history[0], "audit_state")
}

///|
test "offer history cannot verify unnamed actors or missing operation identity" {
  for
    value in [
      Json::null(),
      Json::string(""),
      Json::string(" \t "),
      Json::number(1),
    ] {
    let actor_row = offer_test_row(
      "create",
      "event",
      Json::number(1),
      offer_test_input({}),
    )
    if get(actor_row, "command") is Object(command) {
      command["actor_id"] = value
    }
    if get(actor_row, "audit") is Object(audit) {
      audit["actor_id"] = value
    }
    assert_eq(offer_test_history_state(actor_row), Json::string("conflict"))
    let operation_row = offer_test_row(
      "create",
      "event",
      Json::number(1),
      offer_test_input({}),
    )
    if get(operation_row, "command") is Object(command) {
      command["idempotency_key"] = value
    }
    assert_eq(offer_test_history_state(operation_row), Json::string("conflict"))
  }
}

///|
test "offer history checks every supplied result lineage marker without hiding legacy rows" {
  let legacy = offer_test_row(
    "create",
    "event",
    Json::number(1),
    offer_test_input({}),
  )
  assert_eq(offer_test_history_state(legacy), Json::string("available"))
  let valid = offer_test_row(
    "create",
    "event",
    Json::number(1),
    offer_test_input({}),
  )
  if get(get(valid, "command"), "result") is Object(result) {
    result["task_id"] = Json::string("task-1")
    result["taskGuid"] = Json::string("task-1")
    result["event_id"] = Json::string("event")
    result["audit_id"] = Json::string("event:audit")
  }
  assert_eq(offer_test_history_state(valid), Json::string("available"))
  for key in ["task_id", "taskGuid", "event_id", "audit_id"] {
    for
      bad in [
        Json::null(),
        Json::string("wrong"),
        Json::string(""),
        Json::number(1),
      ] {
      let row = offer_test_row(
        "update",
        "event",
        Json::number(1),
        offer_test_input({}),
      )
      if get(get(row, "command"), "result") is Object(result) {
        result[key] = bad
      }
      assert_eq(offer_test_history_state(row), Json::string("conflict"))
    }
  }
  let missing_audit = offer_test_row(
    "create",
    "event",
    Json::number(1),
    offer_test_input({}),
    audit=Json::null(),
  )
  if get(get(missing_audit, "command"), "result") is Object(result) {
    result["task_id"] = Json::string("task-2")
  }
  assert_eq(offer_test_history_state(missing_audit), Json::string("conflict"))
}

///|
test "offer history requires supplied audit revision to match the command result" {
  let valid = offer_test_row(
    "create",
    "event",
    Json::number(1),
    offer_test_input({}),
  )
  if get(valid, "audit") is Object(audit) {
    audit["revision"] = Json::number(1)
  }
  assert_eq(offer_test_history_state(valid), Json::string("available"))
  for
    bad in [
      Json::null(),
      Json::string("1"),
      Json::number(0),
      Json::number(2),
      Json::number(1.5),
    ] {
    let row = offer_test_row(
      "create",
      "event",
      Json::number(1),
      offer_test_input({}),
    )
    if get(row, "audit") is Object(audit) {
      audit["revision"] = bad
    }
    assert_eq(offer_test_history_state(row), Json::string("conflict"))
  }
}
