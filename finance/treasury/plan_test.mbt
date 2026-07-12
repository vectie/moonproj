///|
fn treasury_plan_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-treasury-plan",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope,
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "cash plan confirms and actualizes within its plan" {
  let plan = CashPlan::new(
      plan_id="plan-001",
      principal_id="co-001",
      project_scope="project:p-001",
      period="2026-07",
      category="construction",
      direction=CashPlanDirection::Outflow,
      planned_amount=@finance.Money::new(minor=100000, currency="CNY"),
      actor_id="alice",
      grant=treasury_plan_grant("treasury:plan:create", "project:p-001"),
    )
    .confirm(
      actor_id="alice",
      grant=treasury_plan_grant("treasury:plan:confirm", "project:p-001"),
    )
    .actualize(
      actual_amount=@finance.Money::new(minor=95000, currency="CNY"),
      actor_id="alice",
      grant=treasury_plan_grant("treasury:plan:actualize", "project:p-001"),
    )
  assert_true(plan.state == CashPlanState::Actualized)
  assert_eq(plan.actual_amount.minor, 95000L)
}

///|
test "fund dispatch requires approval before execution" {
  let dispatch = FundDispatch::new(
      dispatch_id="dispatch-001",
      principal_id="co-001",
      from_project="project:p-001",
      to_project="project:p-002",
      amount=@finance.Money::new(minor=30000, currency="CNY"),
      reason="Liquidity balancing",
      actor_id="alice",
      grant=treasury_plan_grant("treasury:dispatch:create", "project:p-001"),
    )
    .approve(
      actor_id="alice",
      grant=treasury_plan_grant("treasury:dispatch:approve", "project:p-001"),
    )
    .execute(
      actor_id="alice",
      grant=treasury_plan_grant("treasury:dispatch:execute", "project:p-001"),
    )
  assert_true(dispatch.state == DispatchState::Executed)
}

///|
test "cash plan rejects actualization above the plan" {
  let plan = CashPlan::new(
    plan_id="plan-002",
    principal_id="co-001",
    project_scope="project:p-001",
    period="2026-07",
    category="construction",
    direction=CashPlanDirection::Outflow,
    planned_amount=@finance.Money::new(minor=100, currency="CNY"),
    actor_id="alice",
    grant=treasury_plan_grant("treasury:plan:create", "project:p-001"),
  ).confirm(
    actor_id="alice",
    grant=treasury_plan_grant("treasury:plan:confirm", "project:p-001"),
  )
  try
    plan.actualize(
      actual_amount=@finance.Money::new(minor=101, currency="CNY"),
      actor_id="alice",
      grant=treasury_plan_grant("treasury:plan:actualize", "project:p-001"),
    )
  catch {
    TreasuryPlanError::OverActualization => ()
    _ => fail("wrong treasury plan error")
  } noraise {
    _ => fail("expected treasury plan error")
  }
}
