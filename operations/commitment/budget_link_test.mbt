///|
fn budget_commitment_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "budget-commitment-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "commitment reserves a project budget line" {
  let commitment = Commitment::new(
    commitment_id="commit-budget-001",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=budget_commitment_grant("commitment:create"),
  )
  let budget = @finance.BudgetLine::new(
    line_id="budget-project-001",
    principal_id="co-001",
    scope="project:p-001",
    currency="CNY",
    allocated_minor=100000,
  )
  let (reservation, reserved) = reserve_budget(
    commitment,
    budget,
    reservation_id="reservation-001",
    amount_minor=50000,
  )
  assert_eq(reservation.commitment_id, "commit-budget-001")
  assert_eq(reserved.reserved_minor, 50000)
  assert_eq(reserved.available_minor(), 50000)
  let consumed = reservation.consume(reserved)
  assert_eq(consumed.reserved_minor, 0)
  assert_eq(consumed.consumed_minor, 50000)
}
