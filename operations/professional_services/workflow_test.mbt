///|
fn shadow_fixture() -> ProfessionalServiceShadow raise {
  ProfessionalServiceShadow::new(
    engagement_id="eng-001",
    principal_id="opc-001",
    customer_id="customer-001",
    owner_id="owner-001",
    title="Market-entry brief",
    currency="CNY",
    proposed_fee_minor=250000L,
    source_evidence=["evidence/customer-brief-001"],
  )
  .add_work(
    work_id="lead",
    title="Frame the engagement",
    role=EngagementLead,
    assigned_actor_id="owner-001",
    dependencies=[],
    acceptance_criteria=["scope is explicit"],
    expected_result_schema="moonproj.service-outline.v1",
  )
  .add_work(
    work_id="research",
    title="Research the market",
    role=Researcher,
    assigned_actor_id="agent-research",
    dependencies=["lead"],
    acceptance_criteria=["claims cite evidence"],
    expected_result_schema="moonproj.research-note.v1",
  )
  .add_work(
    work_id="produce",
    title="Produce the brief",
    role=Producer,
    assigned_actor_id="agent-producer",
    dependencies=["research"],
    acceptance_criteria=["brief answers customer question"],
    expected_result_schema="moonproj.customer-brief.v1",
  )
  .add_work(
    work_id="review",
    title="Independently review delivery",
    role=IndependentReviewer,
    assigned_actor_id="reviewer-002",
    dependencies=["produce"],
    acceptance_criteria=["all claims trace to evidence"],
    expected_result_schema="moonproj.delivery-review.v1",
  )
  .release()
}

///|
fn successful_result(
  request : @agent_port.AgentRequest,
  attempt_id : String,
  evidence : String,
) -> @agent_port.AgentResult {
  {
    protocol_version: @agent_port.protocol_version(),
    request_id: request.request_id,
    attempt_id,
    status: "succeeded",
    findings: "accepted output",
    confidence_percent: 90,
    evidence: [evidence],
    proposed_commands: [],
    error_classification: "",
  }
}

///|
test "professional service shadow coordinates dependencies without company effects" {
  let mut shadow = shadow_fixture()
  for work_id in ["lead", "research", "produce", "review"] {
    let attempt_id = "attempt-\{work_id}"
    let (request, dispatched) = shadow.request_work(
      work_id~,
      request_id="request-\{work_id}",
      attempt_id~,
      input_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    assert_eq(request.coordination_mode, CompanyTopDown)
    assert_true(request.protects_reserved_effects())
    assert_eq(request.authority_ceiling_minor, 0L)
    shadow = dispatched.record_result(
      successful_result(request, attempt_id, "evidence/output-\{work_id}"),
      activity_id="activity-\{work_id}",
      at_epoch=1L,
    )
  }
  let accepted = shadow.accept_shadow_delivery(
    reviewer_id="reviewer-002",
    acceptance_evidence=["evidence/acceptance-001"],
    proposal_id="proposal-invoice-001",
  )
  assert_eq(accepted.stage, ShadowAccepted)
  assert_true(!accepted.external_delivery_sent)
  assert_true(!accepted.contract_signed)
  assert_true(!accepted.accounting_posted)
  assert_true(!accepted.payment_collected)
  guard accepted.invoice_proposal is Some(proposal) else {
    fail("expected inert invoice proposal")
  }
  assert_eq(proposal.state, ProposalOnly)
  assert_true(!proposal.company_authority_granted)
}

///|
test "shadow workflow rejects unresolved dependencies and owner self-review" {
  let shadow = shadow_fixture()
  try
    shadow.request_work(
      work_id="produce",
      request_id="request-too-early",
      attempt_id="attempt-too-early",
      input_digest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected early dispatch to fail")
  }
  let invalid = ProfessionalServiceShadow::new(
      engagement_id="eng-002",
      principal_id="opc-001",
      customer_id="customer-001",
      owner_id="same-person",
      title="Invalid review",
      currency="CNY",
      proposed_fee_minor=1L,
      source_evidence=["evidence/brief"],
    )
    .add_work(
      work_id="lead",
      title="Lead",
      role=EngagementLead,
      assigned_actor_id="same-person",
      dependencies=[],
      acceptance_criteria=["done"],
      expected_result_schema="lead.v1",
    )
    .add_work(
      work_id="produce",
      title="Produce",
      role=Producer,
      assigned_actor_id="producer",
      dependencies=["lead"],
      acceptance_criteria=["done"],
      expected_result_schema="output.v1",
    )
    .add_work(
      work_id="review",
      title="Review",
      role=IndependentReviewer,
      assigned_actor_id="same-person",
      dependencies=["produce"],
      acceptance_criteria=["done"],
      expected_result_schema="review.v1",
    )
  try invalid.release() catch {
    ReviewIndependenceRequired => ()
    _ => fail("expected independent reviewer failure")
  } noraise {
    _ => fail("expected self-review to fail")
  }
}
