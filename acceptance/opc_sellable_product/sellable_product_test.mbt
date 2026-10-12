///|
fn authority(
  grant_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  max_amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id: "opc-market-studio",
    actor_id,
    capability,
    scope,
    max_amount_minor,
    active: true,
  }
}

///|
fn signed_customer_message(
  message_id : String,
  sent_at_epoch : Int64,
  nonce : String,
  body : String,
  secret : String,
) -> @customer_channel.SignedCustomerEnvelope raise {
  let unsigned : @customer_channel.SignedCustomerEnvelope = {
    message_id,
    channel_id: "customer-webhook-acme",
    customer_id: "customer-acme",
    sent_at_epoch,
    nonce,
    content_type: "application/json",
    body,
    signature: "",
  }
  { ..unsigned, signature: @customer_channel.sign_envelope(unsigned, secret~) }
}

///|
fn successful_agent_result(
  request : @agent_port.AgentRequest,
  attempt_id : String,
  evidence : String,
  findings : String,
) -> @agent_port.AgentResult {
  {
    protocol_version: @agent_port.protocol_version(),
    request_id: request.request_id,
    attempt_id,
    status: "succeeded",
    findings,
    confidence_percent: 92,
    evidence: [evidence],
    proposed_commands: [],
    error_classification: "",
  }
}

///|
fn execute_shadow_work(
  shadow : @professional_services.ProfessionalServiceShadow,
  work_id : String,
  cost_minor : Int64,
  at_epoch : Int64,
) -> (@professional_services.ProfessionalServiceShadow, Int64) raise {
  let request_id = "request-" + work_id
  let attempt_id = "attempt-" + work_id
  let claim_token = "claim-" + work_id
  let evidence = "evidence/output/" + work_id
  let (request, dispatched) = shadow.request_work(
    work_id~,
    request_id~,
    attempt_id~,
    input_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let ready = @agent_port.ExecutionAttempt::new(request, attempt_id~, at_epoch~)
  let claimed = ready.claim(
    expected_revision=ready.revision,
    claim_token~,
    executor_id="moonclaw-market-studio",
    now_epoch=at_epoch + 1L,
    lease_seconds=300L,
  )
  let running = claimed.transition(
    expected_revision=claimed.revision,
    to=Running,
    actor_id="moonclaw-market-studio",
    claim_token~,
    reason="bounded professional-service work started",
    at_epoch=at_epoch + 2L,
  )
  let evidenced = running.record_artifact(
    expected_revision=running.revision,
    artifact_ref=evidence,
  )
  let costed = evidenced.record_cost(
    expected_revision=evidenced.revision,
    additional_minor=cost_minor,
  )
  let completed = costed.transition(
    expected_revision=costed.revision,
    to=Succeeded,
    actor_id="moonclaw-market-studio",
    claim_token~,
    reason="acceptance contract satisfied",
    at_epoch=at_epoch + 3L,
  )
  assert_eq(completed.phase, Succeeded)
  assert_eq(completed.cost_minor, cost_minor)
  let updated = dispatched.record_result(
    successful_agent_result(
      request,
      attempt_id,
      evidence,
      "Customer-ready evidence produced for " + work_id,
    ),
    activity_id="activity-" + work_id,
    at_epoch=at_epoch + 3L,
  )
  (updated, completed.cost_minor)
}

///|
fn released_service(
  order_receipt : @customer_channel.VerifiedCustomerReceipt,
) -> @professional_services.ProfessionalServiceShadow raise {
  @professional_services.ProfessionalServiceShadow::new(
    engagement_id="engagement-acme-market-entry",
    principal_id="opc-market-studio",
    customer_id="customer-acme",
    owner_id="founder",
    title="Market Entry Decision Brief",
    currency="CNY",
    proposed_fee_minor=250000L,
    source_evidence=[order_receipt.receipt_id, order_receipt.body_digest],
  )
  .add_work(
    work_id="frame",
    title="Frame the decision and exclusions",
    role=EngagementLead,
    assigned_actor_id="founder",
    dependencies=[],
    acceptance_criteria=["decision, audience, and exclusions are explicit"],
    expected_result_schema="market-brief/decision-frame@1",
  )
  .add_work(
    work_id="research",
    title="Research the target market",
    role=Researcher,
    assigned_actor_id="agent-researcher",
    dependencies=["frame"],
    acceptance_criteria=["every material claim has source evidence"],
    expected_result_schema="market-brief/research@1",
  )
  .add_work(
    work_id="produce",
    title="Produce the customer decision brief",
    role=Producer,
    assigned_actor_id="agent-producer",
    dependencies=["research"],
    acceptance_criteria=[
      "brief gives a go, no-go, or experiment recommendation",
    ],
    expected_result_schema="market-brief/deliverable@1",
  )
  .add_work(
    work_id="review",
    title="Independently review claims and recommendation",
    role=IndependentReviewer,
    assigned_actor_id="reviewer-independent",
    dependencies=["produce"],
    acceptance_criteria=[
      "citations and recommendation survive independent review",
    ],
    expected_result_schema="market-brief/review@1",
  )
  .release()
}

///|
test "OPC sells a verified market-entry brief from order through collected cash" {
  let secret = "0123456789abcdef0123456789abcdef"
  let channel : @customer_channel.VerifiedWebhookChannel = {
    channel_id: "customer-webhook-acme",
    principal_id: "opc-market-studio",
    customer_id: "customer-acme",
    signing_key_id: "acme-key-2026-08",
    allowed_clock_skew_seconds: 300L,
    active: true,
  }
  let order = signed_customer_message(
    "message-order-001", 1000L, "nonce-order-001", "{\"kind\":\"order\",\"offer\":\"market-entry-decision-brief\",\"budget_minor\":250000}",
    secret,
  )
  let (order_receipt, replay_registry) = @customer_channel.verify_inbound(
    channel,
    @customer_channel.ChannelReplayRegistry::new(),
    order,
    secret~,
    now_epoch=1010L,
  )
  assert_true(order_receipt.signature_verified)
  assert_true(!order_receipt.company_authority_granted)

  let price = @finance.Money::new(minor=250000L, currency="CNY")
  let project_scope = "engagement:engagement-acme-market-entry"
  let draft_commitment = @commitment.Commitment::new(
    commitment_id="commitment-acme-market-entry",
    principal_id="opc-market-studio",
    project_scope~,
    counterparty_id="customer-acme",
    amount=price,
    actor_id="founder",
    grant=authority(
      "grant-commitment-create", "founder", "commitment:create", project_scope, 250000L,
    ),
  )
  let submitted_commitment = draft_commitment.transition(
    Submitted,
    actor_id="founder",
    grant=authority(
      "grant-commitment-submit", "founder", "commitment:submit", project_scope, 250000L,
    ),
  )
  let approved_commitment = submitted_commitment.transition(
    Approved,
    actor_id="commercial-reviewer",
    grant=authority(
      "grant-commitment-approve", "commercial-reviewer", "commitment:approve", project_scope,
      250000L,
    ),
  )
  assert_eq(approved_commitment.state, Approved)

  let mut shadow = released_service(order_receipt)
  let mut execution_cost_minor = 0L
  for
    item in [
      ("frame", 4000L, 1020L),
      ("research", 18000L, 1030L),
      ("produce", 16000L, 1040L),
      ("review", 6000L, 1050L),
    ] {
    let (work_id, cost_minor, at_epoch) = item
    let (updated, cost) = execute_shadow_work(
      shadow, work_id, cost_minor, at_epoch,
    )
    shadow = updated
    execution_cost_minor += cost
  }
  assert_eq(execution_cost_minor, 44000L)
  assert_true(price.minor - execution_cost_minor > 0L)
  assert_true((price.minor - execution_cost_minor) * 100L / price.minor >= 80L)

  let customer_acceptance = signed_customer_message(
    "message-acceptance-001", 1100L, "nonce-acceptance-001", "{\"kind\":\"delivery-acceptance\",\"deliverable_id\":\"deliverable-acme-market-entry\",\"accepted\":true}",
    secret,
  )
  let (acceptance_receipt, final_registry) = @customer_channel.verify_inbound(
    channel,
    replay_registry,
    customer_acceptance,
    secret~,
    now_epoch=1110L,
  )
  assert_eq(final_registry.message_ids.length(), 2)
  let accepted_shadow = shadow.accept_shadow_delivery(
    reviewer_id="reviewer-independent",
    acceptance_evidence=[
      "evidence/output/review",
      acceptance_receipt.receipt_id,
      acceptance_receipt.body_digest,
    ],
    proposal_id="proposal-invoice-acme-market-entry",
  )
  guard accepted_shadow.invoice_proposal is Some(invoice_proposal) else {
    fail("accepted shadow delivery must create an inert invoice proposal")
  }
  assert_eq(invoice_proposal.amount_minor, price.minor)
  assert_true(!invoice_proposal.company_authority_granted)

  let planned_deliverable = @delivery.Deliverable::new(
    deliverable_id="deliverable-acme-market-entry",
    project_id="engagement-acme-market-entry",
    principal_id="opc-market-studio",
    project_scope~,
    name="Market Entry Decision Brief",
    evidence_ids=[
      "evidence/output/produce",
      "evidence/output/review",
      acceptance_receipt.receipt_id,
    ],
    actor_id="agent-producer",
    grant=authority(
      "grant-deliverable-create", "agent-producer", "delivery:deliverable:create",
      project_scope, 0L,
    ),
  )
  let submitted_deliverable = planned_deliverable.submit(
    actor_id="agent-producer",
    grant=authority(
      "grant-deliverable-submit", "agent-producer", "delivery:deliverable:submit",
      project_scope, 0L,
    ),
  )
  let accepted_deliverable = submitted_deliverable.accept(
    actor_id="founder",
    grant=authority(
      "grant-deliverable-accept", "founder", "delivery:deliverable:accept", project_scope,
      0L,
    ),
  )
  assert_eq(accepted_deliverable.state, Accepted)
  let performed_commitment = approved_commitment.transition(
    Performed,
    actor_id="founder",
    grant=authority(
      "grant-commitment-perform", "founder", "commitment:perform", project_scope,
      250000L,
    ),
  )

  let customer_scope = "customer:customer-acme"
  let draft_invoice = @invoice.Invoice::new(
    invoice_id="invoice-acme-market-entry",
    principal_id="opc-market-studio",
    customer_id="customer-acme",
    source_id=accepted_deliverable.deliverable_id,
    amount=price,
    actor_id="founder",
    grant=authority(
      "grant-invoice-create", "founder", "invoice:create", customer_scope, 250000L,
    ),
  )
  let issued_invoice = draft_invoice.transition(
    Issued,
    actor_id="founder",
    grant=authority(
      "grant-invoice-issue", "founder", "invoice:issue", customer_scope, 250000L,
    ),
  )
  let accepted_invoice = issued_invoice.transition(
    Accepted,
    actor_id="commercial-reviewer",
    grant=authority(
      "grant-invoice-accept", "commercial-reviewer", "invoice:accept", customer_scope,
      250000L,
    ),
  )
  let receivable = accepted_invoice.open_receivable(
    receivable_id="receivable-acme-market-entry",
    actor_id="finance-operator",
    invoice_grant=authority(
      "grant-invoice-receivable-open", "finance-operator", "invoice:receivable-open",
      customer_scope, 250000L,
    ),
    receivable_grant=authority(
      "grant-receivable-open", "finance-operator", "receivable:open", customer_scope,
      250000L,
    ),
  )
  let opening_event = receivable.to_opening_event(
    event_id="accounting-receivable-open-acme",
    event_type="service_revenue_receivable_opened",
    receivable_account="1100-accounts-receivable",
    revenue_account="4100-professional-service-revenue",
  )
  assert_eq(opening_event.journal.postings.length(), 2)
  assert_eq(opening_event.journal.postings[0].amount.minor, 250000L)

  let collection_event = receivable.to_collection_event(
    collection_id="collection-acme-market-entry",
    event_id="accounting-collection-acme",
    event_type="customer_cash_collected",
    amount=price,
    cash_account="1000-bank",
    receivable_account="1100-accounts-receivable",
  )
  let collected_receivable = receivable.collect(
    amount_minor=250000L,
    actor_id="finance-operator",
    grant=authority(
      "grant-receivable-collect", "finance-operator", "receivable:collect", customer_scope,
      250000L,
    ),
  )
  let paid_invoice = accepted_invoice.record_payment(
    amount_minor=250000L,
    actor_id="finance-operator",
    grant=authority(
      "grant-invoice-collect", "finance-operator", "invoice:collect", customer_scope,
      250000L,
    ),
  )
  let settled_commitment = performed_commitment.transition(
    Settled,
    actor_id="finance-operator",
    grant=authority(
      "grant-commitment-settle", "finance-operator", "commitment:settle", project_scope,
      250000L,
    ),
  )
  assert_eq(collection_event.journal.postings.length(), 2)
  assert_eq(collected_receivable.state, Collected)
  assert_eq(paid_invoice.state, Paid)
  assert_eq(settled_commitment.state, Settled)

  let adoption : @product.WorkflowAdoptionEvidence = {
    principal_id: "opc-market-studio",
    product_id: "moonproj",
    workflow_id: "engagement-acme-market-entry",
    decision: Pass,
    product_in_gate_receipt: "product-in-gate/pass/market-entry-brief",
    accepted_customer_evidence: [acceptance_receipt.receipt_id],
    owner_id: "founder",
    adoption_count: 1,
    successful_completions: 1,
    reviewed_at_epoch: 1200L,
  }
  assert_true(adoption.qualifies())
}

///|
test "runtime execution and shadow proposal cannot authorize an invoice" {
  let price = @finance.Money::new(minor=250000L, currency="CNY")
  let runtime_only = authority(
    "runtime-tool-permission", "agent-producer", "professional-services.shadow.execute",
    "engagement:engagement-acme-market-entry", 250000L,
  )
  try
    @invoice.Invoice::new(
      invoice_id="invoice-illegal-runtime-promotion",
      principal_id="opc-market-studio",
      customer_id="customer-acme",
      source_id="proposal-invoice-acme-market-entry",
      amount=price,
      actor_id="agent-producer",
      grant=runtime_only,
    )
  catch {
    NotAuthorized(_) => ()
    _ =>
      fail("expected the company-authority plane to reject runtime permission")
  } noraise {
    _ => fail("runtime permission must never create an invoice")
  }
}
