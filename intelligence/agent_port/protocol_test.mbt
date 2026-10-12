///|
fn execution_request() -> AgentRequest {
  {
    protocol_version: protocol_version(),
    request_id: "agent-001",
    work_item_id: "work-001",
    flow_run_id: "flow-001",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "delivery:prepare",
    scope: "engagement:eng-001",
    coordination_mode: CompanyTopDown,
    authority_ceiling_minor: 0,
    input_evidence: ["evidence:brief-001"],
    input_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    acceptance_criteria: ["deliverable cites the customer brief"],
    expected_result_schema: "professional-service-deliverable.v1",
    prohibited_effects: reserved_company_effects(),
    idempotency_key: "idem-001",
  }
}

///|
test "agent request versions the top-down contract and protects company effects" {
  let request = execution_request()
  assert_true(request.is_well_formed())
  assert_true(request.protects_reserved_effects())
  assert_true(request.coordination_mode is CompanyTopDown)
}

///|
test "agent request refuses incomplete evidence and effect boundaries" {
  let malformed = {
    ..execution_request(),
    input_evidence: [],
    prohibited_effects: ["payment.release"],
  }
  assert_false(malformed.is_well_formed())
  assert_false(malformed.protects_reserved_effects())
}

///|
test "proposed command remains inert when runtime permission was observed" {
  let proposal : ProposedCommand = {
    protocol_version: protocol_version(),
    command_id: "proposal-001",
    request_id: "agent-001",
    attempt_id: "attempt-001",
    principal_id: "co-001",
    proposed_by: "delivery-agent",
    capability: "invoice:draft",
    scope: "engagement:eng-001",
    amount_minor: 125000,
    payload_schema: "moonproj.invoice-draft.v1",
    payload: "{\"engagement_id\":\"eng-001\"}",
    evidence: ["evidence:acceptance-001"],
    idempotency_key: "proposal-idem-001",
    state: ProposalOnly,
    runtime_permission_observed: true,
    company_authority_granted: false,
  }
  assert_true(proposal.is_well_formed())
  let review = proposal.accept_for_review()
  assert_true(review.state is AcceptedForReview)
  assert_false(review.company_authority_granted)
}

///|
test "agent result is versioned and terminal" {
  let result : AgentResult = {
    protocol_version: protocol_version(),
    request_id: "agent-002",
    attempt_id: "attempt-002",
    status: "succeeded",
    findings: "No breach",
    confidence_percent: 90,
    evidence: ["evidence-001"],
    proposed_commands: [],
    error_classification: "",
  }
  assert_true(result.is_well_formed())
  assert_true(result.is_terminal())
}
