///|
test "two acquired customers complete independent repeat-revenue cycles" {
  let marketing_scope = "portfolio:decision-brief"
  let budget = cny(30000L)
  let planned = @marketing.MarketingCampaign::new(
    campaign_id="campaign-decision-brief",
    principal_id="opc-market-studio",
    project_scope=marketing_scope,
    name="Founder network decision-brief launch",
    budget~,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-campaign-create", "founder", "marketing:campaign:create", marketing_scope,
      30000L,
    ),
  )
  let active = planned.activate(
    actor_id="commercial-reviewer",
    grant=portfolio_authority(
      "grant-campaign-activate", "commercial-reviewer", "marketing:campaign:activate",
      marketing_scope, 30000L,
    ),
  )
  let placement = @marketing.MarketingPlacement::new(
    placement_id="placement-founder-network",
    active,
    channel="founder-network",
    amount=cny(12000L),
    actor_id="founder",
    grant=portfolio_authority(
      "grant-placement-create", "founder", "marketing:placement:create", marketing_scope,
      12000L,
    ),
  ).place(
    leads=10,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-placement-place", "founder", "marketing:placement:place", marketing_scope,
      12000L,
    ),
  )
  let completed_campaign = active
    .record_spend(
      amount=cny(12000L),
      actor_id="finance-operator",
      grant=portfolio_authority(
        "grant-marketing-spend", "finance-operator", "marketing:spend", marketing_scope,
        12000L,
      ),
    )
    .complete(
      actor_id="commercial-reviewer",
      grant=portfolio_authority(
        "grant-campaign-complete", "commercial-reviewer", "marketing:campaign:complete",
        marketing_scope, 12000L,
      ),
    )
  assert_eq(placement.leads, 10)
  assert_eq(completed_campaign.actual_cost.minor, 12000L)

  let august = fulfilled_sale("acme-2026-08", "customer-acme", 250000L)
  let august_partial = august.collect(
    amount_minor=100000L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-collect-acme-deposit", "finance-operator", "receivable:collect", "customer:customer-acme",
      100000L,
    ),
  )
  assert_eq(august_partial.state, PartiallyCollected)
  let august_paid = august_partial.collect(
    amount_minor=150000L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-collect-acme-balance", "finance-operator", "receivable:collect", "customer:customer-acme",
      150000L,
    ),
  )
  let september = fulfilled_sale("beta-2026-09", "customer-beta", 250000L)
  let september_paid = september.collect(
    amount_minor=250000L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-collect-beta", "finance-operator", "receivable:collect", "customer:customer-beta",
      250000L,
    ),
  )
  assert_eq(august_paid.state, Collected)
  assert_eq(september_paid.state, Collected)

  let revenue_minor = 500000L
  let modeled_delivery_cost_minor = 88000L
  let acquisition_cost_minor = completed_campaign.actual_cost.minor
  let contribution_minor = revenue_minor -
    modeled_delivery_cost_minor -
    acquisition_cost_minor
  assert_eq(contribution_minor, 400000L)
  assert_eq(contribution_minor * 100L / revenue_minor, 80L)
  let adoption : @product.WorkflowAdoptionEvidence = {
    principal_id: "opc-market-studio",
    product_id: "moonproj",
    workflow_id: "decision-brief-repeat-sales",
    decision: Pass,
    product_in_gate_receipt: "product-in-gate/pass/repeat-sales",
    accepted_customer_evidence: ["acceptance-acme", "acceptance-beta"],
    owner_id: "founder",
    adoption_count: 2,
    successful_completions: 2,
    reviewed_at_epoch: 2000L,
  }
  assert_true(adoption.qualifies())
}
