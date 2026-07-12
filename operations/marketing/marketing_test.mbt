///|
fn marketing_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-marketing",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "campaign controls placement and spend" {
  let campaign = MarketingCampaign::new(
    campaign_id="campaign-001",
    principal_id="co-001",
    project_scope="project:p-001",
    name="Launch campaign",
    budget=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=marketing_grant("marketing:campaign:create"),
  ).activate(
    actor_id="alice",
    grant=marketing_grant("marketing:campaign:activate"),
  )
  let placement = MarketingPlacement::new(
    placement_id="placement-001",
    campaign,
    channel="online",
    amount=@finance.Money::new(minor=30000, currency="CNY"),
    actor_id="alice",
    grant=marketing_grant("marketing:placement:create"),
  ).place(
    leads=42,
    actor_id="alice",
    grant=marketing_grant("marketing:placement:place"),
  )
  let campaign = campaign
    .record_spend(
      amount=@finance.Money::new(minor=30000, currency="CNY"),
      actor_id="alice",
      grant=marketing_grant("marketing:spend"),
    )
    .complete(
      actor_id="alice",
      grant=marketing_grant("marketing:campaign:complete"),
    )
  assert_true(placement.state == PlacementState::Placed)
  assert_eq(placement.leads, 42)
  assert_true(campaign.state == CampaignState::Completed)
}

///|
test "campaign blocks spend above budget" {
  let campaign = MarketingCampaign::new(
    campaign_id="campaign-002",
    principal_id="co-001",
    project_scope="project:p-001",
    name="Small campaign",
    budget=@finance.Money::new(minor=100, currency="CNY"),
    actor_id="alice",
    grant=marketing_grant("marketing:campaign:create"),
  ).activate(
    actor_id="alice",
    grant=marketing_grant("marketing:campaign:activate"),
  )
  try
    campaign.record_spend(
      amount=@finance.Money::new(minor=101, currency="CNY"),
      actor_id="alice",
      grant=marketing_grant("marketing:spend"),
    )
  catch {
    MarketingError::BudgetExceeded => ()
    _ => fail("wrong marketing error")
  } noraise {
    _ => fail("expected marketing error")
  }
}
