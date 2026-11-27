///|
fn adversarial_product_in_gate_body(decision : String) -> Json {
  Json::object({
    "decision": Json::string(decision),
    "primary_value": Json::string("solution"),
    "segment": Json::string("owner-operated software company"),
    "workflow": Json::string("weekly release decision"),
    "decided_at": Json::string("2026-08-04"),
    "problem_evidence": Json::array([]),
    "commitment_evidence": Json::array([]),
    "current_behavior_cost": Json::string("two owner-days"),
    "outcome_metric": Json::string("two hours"),
    "adoption_path": Json::string("owner-led weekly workflow"),
    "unresolved_risks": Json::string("retention unknown"),
    "next_experiment": Json::string("four-week pilot"),
    "review_by": Json::string("2026-11-02"),
  })
}

///|
fn adversarial_product_body_with(key : String, value : Json) -> Json {
  let body = adversarial_product_in_gate_body("experiment")
  match body {
    Object(fields) => fields[key] = value
    _ => ()
  }
  body
}

///|
fn adversarial_product_body_without(key : String) -> Json {
  let body = adversarial_product_in_gate_body("experiment")
  match body {
    Object(fields) => fields.remove(key)
    _ => ()
  }
  body
}

///|
fn product_in_gate_rejection_status(body : Json) -> Int32 {
  try normalize_product_in_gate_request(body) catch {
    CompanyServiceError::CommandRejected(status, _) => status
    CompanyServiceError::InvalidInput(_) => 500
    _ => 599
  } noraise {
    _ => 0
  }
}

///|
fn adversarial_receipts(prefix : String, count : Int32) -> Array[Json] {
  let result : Array[Json] = []
  for index in 0..<count {
    result.push(Json::string(prefix + index.to_string()))
  }
  result
}

///|
fn adversarial_pass_body(
  problem_count : Int32,
  level4_count : Int32,
  level5_count : Int32,
) -> Json {
  let body = adversarial_product_in_gate_body("pass")
  match body {
    Object(fields) => {
      fields["problem_evidence"] = Json::array(
        adversarial_receipts("problem-", problem_count),
      )
      let commitments = adversarial_receipts("level4:pilot-", level4_count)
      for value in adversarial_receipts("level5:payment-", level5_count) {
        commitments.push(value)
      }
      fields["commitment_evidence"] = Json::array(commitments)
    }
    _ => ()
  }
  body
}

///|
test "adversarial product routes reject traversal aliases and method confusion" {
  let invalid_ids = [
    "",
    ".",
    "..",
    "../moonproj",
    "moonproj/child",
    "%2e%2e",
    "moonproj?x=1",
    "moonproj#fragment",
    "产品",
    "x".repeat(129),
  ]
  for id in invalid_ids {
    assert_true(
      product_in_gate_project("/api/company/products/" + id + "/in-gate")
      is None,
    )
  }
  let max_id = "x".repeat(128)
  assert_true(
    product_in_gate_project("/api/company/products/" + max_id + "/in-gate")
    is Some(_),
  )
  let path = "/api/company/products/moonproj/in-gate"
  assert_true(product_in_gate_command_spec(@http.Put, path) is Some("moonproj"))
  for request_method in [@http.Get, @http.Post, @http.Patch, @http.Delete] {
    assert_true(product_in_gate_command_spec(request_method, path) is None)
  }
  assert_true(product_in_gate_project(path + "/extra") is None)
  assert_true(product_in_gate_project(path + "/in-gate") is None)
}

///|
test "fuzzed product contracts fail closed as 422 instead of service errors" {
  let keys = [
    "decision", "primary_value", "segment", "workflow", "decided_at", "problem_evidence",
    "commitment_evidence", "current_behavior_cost", "outcome_metric", "adoption_path",
    "unresolved_risks", "next_experiment", "review_by",
  ]
  assert_eq(product_in_gate_rejection_status(Json::null()), 422)
  for key in keys {
    assert_eq(
      product_in_gate_rejection_status(adversarial_product_body_without(key)),
      422,
    )
  }
  let extra = adversarial_product_body_with("unexpected", Json::string("value"))
  assert_eq(product_in_gate_rejection_status(extra), 422)
  for
    key in [
      "decision", "primary_value", "segment", "workflow", "decided_at", "current_behavior_cost",
      "outcome_metric", "adoption_path", "unresolved_risks", "next_experiment", "review_by",
    ] {
    assert_eq(
      product_in_gate_rejection_status(
        adversarial_product_body_with(key, Json::number(7)),
      ),
      422,
    )
  }
  for key in ["problem_evidence", "commitment_evidence"] {
    assert_eq(
      product_in_gate_rejection_status(
        adversarial_product_body_with(key, Json::string("not-an-array")),
      ),
      422,
    )
    assert_eq(
      product_in_gate_rejection_status(
        adversarial_product_body_with(key, Json::array([Json::number(1)])),
      ),
      422,
    )
  }
  assert_eq(
    product_in_gate_rejection_status(
      adversarial_product_body_with("decision", Json::string("PASS")),
    ),
    422,
  )
}

///|
test "product input boundaries accept exact limits and reject one byte over" {
  let segment_limit = adversarial_product_body_with(
    "segment",
    Json::string("s".repeat(512)),
  )
  assert_eq(product_in_gate_rejection_status(segment_limit), 0)
  let segment_over = adversarial_product_body_with(
    "segment",
    Json::string("s".repeat(513)),
  )
  assert_eq(product_in_gate_rejection_status(segment_over), 422)
  let adoption_limit = adversarial_product_body_with(
    "adoption_path",
    Json::string("a".repeat(1024)),
  )
  assert_eq(product_in_gate_rejection_status(adoption_limit), 0)
  let adoption_over = adversarial_product_body_with(
    "adoption_path",
    Json::string("a".repeat(1025)),
  )
  assert_eq(product_in_gate_rejection_status(adoption_over), 422)
  let receipts_limit = adversarial_product_body_with(
    "problem_evidence",
    Json::array(adversarial_receipts("receipt-", 20)),
  )
  assert_eq(product_in_gate_rejection_status(receipts_limit), 0)
  let receipts_over = adversarial_product_body_with(
    "problem_evidence",
    Json::array(adversarial_receipts("receipt-", 21)),
  )
  assert_eq(product_in_gate_rejection_status(receipts_over), 422)
  let reference_limit = adversarial_product_body_with(
    "problem_evidence",
    Json::array([Json::string("r".repeat(512))]),
  )
  assert_eq(product_in_gate_rejection_status(reference_limit), 0)
  let reference_over = adversarial_product_body_with(
    "problem_evidence",
    Json::array([Json::string("r".repeat(513))]),
  )
  assert_eq(product_in_gate_rejection_status(reference_over), 422)
}

///|
test "exhaustive product pass matrix cannot bypass evidence thresholds" {
  for problem_count in 0..<=5 {
    for level4_count in 0..<=3 {
      for level5_count in 0..<=1 {
        let accepted = product_in_gate_rejection_status(
            adversarial_pass_body(problem_count, level4_count, level5_count),
          ) ==
          0
        let expected = problem_count >= 3 &&
          (level4_count >= 2 || level5_count >= 1)
        assert_eq(accepted, expected)
      }
    }
  }
  for forged in ["level4:", "level5:", "LEVEL5:payment", "level6:payment"] {
    let body = adversarial_pass_body(3, 0, 0)
    match body {
      Object(fields) =>
        fields["commitment_evidence"] = Json::array([Json::string(forged)])
      _ => ()
    }
    assert_eq(product_in_gate_rejection_status(body), 422)
  }
  let duplicate = adversarial_product_body_with(
    "problem_evidence",
    Json::array([Json::string(" receipt-1 "), Json::string("receipt-1")]),
  )
  assert_eq(product_in_gate_rejection_status(duplicate), 422)
}

///|
test "fuzzed product dates enforce calendar validity and ninety-day freshness" {
  for
    invalid in [
      "", "2026-8-04", "2026/08/04", "2026-02-29", "2026-04-31", "2026-13-01", "0000-01-01",
      "2026-08-04T00:00:00Z",
    ] {
    assert_eq(
      product_in_gate_rejection_status(
        adversarial_product_body_with("decided_at", Json::string(invalid)),
      ),
      422,
    )
  }
  assert_eq(
    product_in_gate_rejection_status(
      adversarial_product_body_with("review_by", Json::string("2026-11-02")),
    ),
    0,
  )
  assert_eq(
    product_in_gate_rejection_status(
      adversarial_product_body_with("review_by", Json::string("2026-11-03")),
    ),
    422,
  )
  assert_eq(
    product_in_gate_rejection_status(
      adversarial_product_body_with("review_by", Json::string("2026-08-03")),
    ),
    422,
  )
  let leap = adversarial_product_in_gate_body("experiment")
  match leap {
    Object(fields) => {
      fields["decided_at"] = Json::string("2028-02-29")
      fields["review_by"] = Json::string("2028-05-29")
    }
    _ => ()
  }
  assert_eq(product_in_gate_rejection_status(leap), 0)
}

///|
test "adversarial product text remains data and cannot change control flags" {
  let payload = "'); DROP TABLE company_record; -- <script>alert(1)</script>"
  let body = adversarial_product_body_with("segment", Json::string(payload))
  let normalized = normalize_product_in_gate_request(body)
  assert_eq(json_text(normalized, "segment", ""), payload)
  let projection = product_in_gate_projection(
    "moonproj", normalized, "owner-1", 7, "event-7",
  )
  assert_eq(json_text(projection, "segment", ""), payload)
  assert_false(json_bool(projection, "exit_gate_effect", true))
  assert_true(json_bool(projection, "persisted", false))
  assert_eq(json_text(projection, "product", ""), "moonproj")
}
