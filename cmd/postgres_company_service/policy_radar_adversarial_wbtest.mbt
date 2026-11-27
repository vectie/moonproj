///|
fn adversarial_policy_review_body(decision : String) -> Json {
  Json::object({
    "decision": Json::string(decision),
    "evidence": Json::string("canonical publisher and date reviewed"),
    "reviewed_at": Json::string("2026-08-10"),
  })
}

///|
fn adversarial_policy_body_with(key : String, value : Json) -> Json {
  let body = adversarial_policy_review_body("verified")
  match body {
    Object(fields) => fields[key] = value
    _ => ()
  }
  body
}

///|
fn adversarial_policy_body_without(key : String) -> Json {
  let body = adversarial_policy_review_body("verified")
  match body {
    Object(fields) => fields.remove(key)
    _ => ()
  }
  body
}

///|
fn policy_review_rejection_status(
  kind : String,
  id : String,
  body : Json,
) -> Int32 {
  try normalize_policy_review(kind, id, body) catch {
    CompanyServiceError::CommandRejected(status, _) => status
    CompanyServiceError::InvalidInput(_) => 500
    _ => 599
  } noraise {
    _ => 0
  }
}

///|
test "adversarial policy routes reject traversal aliases and method confusion" {
  let prefixes = [
    "/api/company/policy/sources/", "/api/company/policy/changes/",
  ]
  let invalid_ids = [
    "",
    ".",
    "..",
    "../secret",
    "source/child",
    "%2e%2e",
    "source?x=1",
    "source#fragment",
    "政策",
    "x".repeat(129),
  ]
  for prefix in prefixes {
    for id in invalid_ids {
      assert_true(
        policy_review_path_id(prefix + id + "/reviews", prefix) is None,
      )
    }
  }
  let path = "/api/company/policy/sources/beijing-fgw-yinli-changping-2026/reviews"
  assert_true(policy_review_command_spec(@http.Post, path) is Some(_))
  for request_method in [@http.Get, @http.Put, @http.Patch, @http.Delete] {
    assert_true(policy_review_command_spec(request_method, path) is None)
  }
  assert_true(policy_review_command_spec(@http.Post, path + "/extra") is None)
}

///|
test "fuzzed policy contracts fail closed with stable client errors" {
  let source_id = "beijing-fgw-yinli-changping-2026"
  assert_eq(
    policy_review_rejection_status("source", source_id, Json::null()),
    422,
  )
  for key in ["decision", "evidence", "reviewed_at"] {
    assert_eq(
      policy_review_rejection_status(
        "source",
        source_id,
        adversarial_policy_body_without(key),
      ),
      422,
    )
  }
  assert_eq(
    policy_review_rejection_status(
      "source",
      source_id,
      adversarial_policy_body_with("unexpected", Json::string("value")),
    ),
    422,
  )
  for key in ["decision", "evidence", "reviewed_at"] {
    assert_eq(
      policy_review_rejection_status(
        "source",
        source_id,
        adversarial_policy_body_with(key, Json::number(7)),
      ),
      422,
    )
  }
  assert_eq(
    policy_review_rejection_status(
      "unknown",
      source_id,
      adversarial_policy_review_body("verified"),
    ),
    422,
  )
  assert_eq(
    policy_review_rejection_status(
      "source",
      "unknown-source",
      adversarial_policy_review_body("verified"),
    ),
    404,
  )
  assert_eq(
    policy_review_rejection_status(
      "change",
      "unknown-change",
      adversarial_policy_review_body("confirmed"),
    ),
    404,
  )
}

///|
test "policy source and interpretation decision vocabularies cannot be confused" {
  let source_id = "beijing-fgw-yinli-changping-2026"
  let change_id = "compute-node-wording"
  for decision in ["verified", "rejected"] {
    assert_eq(
      policy_review_rejection_status(
        "source",
        source_id,
        adversarial_policy_review_body(decision),
      ),
      0,
    )
  }
  for decision in ["confirmed", "rejected"] {
    assert_eq(
      policy_review_rejection_status(
        "change",
        change_id,
        adversarial_policy_review_body(decision),
      ),
      0,
    )
  }
  for decision in ["confirmed", "pending", "VERIFIED", ""] {
    assert_eq(
      policy_review_rejection_status(
        "source",
        source_id,
        adversarial_policy_review_body(decision),
      ),
      422,
    )
  }
  for decision in ["verified", "pending", "CONFIRMED", ""] {
    assert_eq(
      policy_review_rejection_status(
        "change",
        change_id,
        adversarial_policy_review_body(decision),
      ),
      422,
    )
  }
}

///|
test "policy evidence and date boundaries withstand oversized and malformed input" {
  let source_id = "beijing-fgw-yinli-changping-2026"
  assert_eq(
    policy_review_rejection_status(
      "source",
      source_id,
      adversarial_policy_body_with("evidence", Json::string("e".repeat(2048))),
    ),
    0,
  )
  assert_eq(
    policy_review_rejection_status(
      "source",
      source_id,
      adversarial_policy_body_with("evidence", Json::string("e".repeat(2049))),
    ),
    422,
  )
  for
    invalid in [
      "", "2026-8-10", "2026/08/10", "2026-02-29", "2026-04-31", "2026-13-01", "0000-01-01",
      "2026-08-10T00:00:00Z",
    ] {
    assert_eq(
      policy_review_rejection_status(
        "source",
        source_id,
        adversarial_policy_body_with("reviewed_at", Json::string(invalid)),
      ),
      422,
    )
  }
  assert_eq(
    policy_review_rejection_status(
      "source",
      source_id,
      adversarial_policy_body_with("reviewed_at", Json::string("2028-02-29")),
    ),
    0,
  )
}

///|
test "policy projection preserves non-effect safety flags under hostile text" {
  let hostile = "'); DROP TABLE company_record; -- <script>alert(1)</script>"
  let normalized = normalize_policy_review(
    "source",
    "beijing-fgw-yinli-changping-2026",
    adversarial_policy_body_with("evidence", Json::string(hostile)),
  )
  let projection = policy_review_projection(
    normalized, "owner-1", 9, "event-9", "audit-9",
  )
  assert_eq(json_text(projection, "evidence", ""), hostile)
  assert_false(json_bool(projection, "legal_effect", true))
  assert_false(json_bool(projection, "procurement_effect", true))
  assert_true(json_bool(projection, "persisted", false))
  assert_eq(json_text(projection, "audit_id", ""), "audit-9")
}
