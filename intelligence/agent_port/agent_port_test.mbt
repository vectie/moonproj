///|
test "agent port keeps authority and idempotency in the request" {
  let request : AgentRequest = {
    request_id: "agent-001",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "investment:research",
    authority_ceiling_minor: 0,
    input_evidence: ["market-snapshot-001"],
    expected_result_schema: "investment-proposal.v1",
    idempotency_key: "idem-001",
  }
  assert_true(request.is_well_formed())
}

///|
test "agent result distinguishes terminal state" {
  let result : AgentResult = {
    request_id: "agent-002",
    status: "succeeded",
    findings: "No breach",
    confidence_percent: 90,
    evidence: ["evidence-001"],
    proposed_commands: [],
    error_classification: "",
  }
  assert_true(result.is_terminal())
}
