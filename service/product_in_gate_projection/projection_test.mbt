///|
test "product admission projection has no engineering exit-gate effect" {
  let projection = @product_in_gate_projection.persisted(
    product="moonproj",
    normalized={
      "decision": "pass",
      "primary_value": "solution",
      "workflow": "professional-service-shadow",
      "problem_evidence": ["problem-1", "problem-2", "problem-3"],
      "commitment_evidence": ["level5:customer-1"],
    },
    owner="owner-001",
    revision=1,
    event_id="event-001",
    updated_at_ms=1000UL,
  )
  guard projection is Object(fields) else {
    fail("projection must be an object")
  }
  assert_eq(fields.get("decision"), Some(Json::string("pass")))
  assert_eq(fields.get("exit_gate_effect"), Some(Json::boolean(false)))
  assert_eq(fields.get("persisted"), Some(Json::boolean(true)))
  guard @product_in_gate_projection.unknown(product="moonproj")
    is Object(unknown_fields) else {
    fail("unknown projection must be an object")
  }
  assert_eq(unknown_fields.get("persisted"), Some(Json::boolean(false)))
}
