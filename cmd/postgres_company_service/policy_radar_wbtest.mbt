///|
test "policy review paths and contracts fail closed" {
  assert_true(
    policy_review_command_spec(
      @http.Post,
      "/api/company/policy/sources/beijing-plan/reviews",
    )
    is Some(("source", "beijing-plan")),
  )
  assert_true(
    policy_review_command_spec(
      @http.Post,
      "/api/company/policy/changes/compute-node-wording/reviews",
    )
    is Some(("change", "compute-node-wording")),
  )
  assert_true(
    policy_review_command_spec(
      @http.Post,
      "/api/company/policy/changes/../secret/reviews",
    )
    is None,
  )
  let source_review = normalize_policy_review(
    "source",
    "beijing-changping-15th-five-year-plan-2026",
    {
      "decision": "verified",
      "evidence": "publisher, canonical URL, date, and relevance checked",
      "reviewed_at": "2026-08-10",
    },
  )
  assert_eq(json_text(source_review, "decision", ""), "verified")
  let projection = policy_review_projection(
    source_review,
    "owner-1",
    1,
    "policy:source-review:test",
    "policy:source-review:test:audit",
  )
  assert_false(json_bool(projection, "legal_effect", true))
  assert_false(json_bool(projection, "procurement_effect", true))
}

///|
test "policy change catalog always resolves to a registered source" {
  assert_true(
    policy_change_source("compute-node-wording")
    is Some("beijing-changping-15th-five-year-plan-2026"),
  )
  assert_true(policy_change_source("unknown-change") is None)
  assert_true(policy_source_known("beijing-fgw-yinli-changping-2026"))
}
