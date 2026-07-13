///|
fn financing_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-financing",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 2000000,
    active: true,
  }
}

///|
test "financing facility controls draw, interest, and repayment" {
  let facility = FinancingFacility::new(
      facility_id="facility-001",
      principal_id="co-001",
      project_scope="project:p-001",
      lender_id="lender-001",
      limit_amount=@finance.Money::new(minor=1000000, currency="CNY"),
      annual_rate_bps=600L,
      actor_id="alice",
      grant=financing_grant("financing:create"),
    )
    .approve(actor_id="alice", grant=financing_grant("financing:approve"))
    .activate(actor_id="alice", grant=financing_grant("financing:activate"))
    .draw(
      amount=@finance.Money::new(minor=500000, currency="CNY"),
      actor_id="alice",
      grant=financing_grant("financing:draw"),
    )
  let (interest, facility) = facility.accrue_interest(
    30L,
    actor_id="alice",
    grant=financing_grant("financing:accrue"),
  )
  assert_true(interest.minor > 0L)
  let facility = facility.repay(
    amount=@finance.Money::new(minor=500000, currency="CNY"),
    actor_id="alice",
    grant=financing_grant("financing:repay"),
  )
  assert_true(facility.state == FacilityState::Closed)
  assert_eq(facility.outstanding_principal.minor, 0L)
}

///|
test "financing draw and repayment emit separate source events" {
  let facility = FinancingFacility::new(
      facility_id="facility-events",
      principal_id="co-001",
      project_scope="project:p-001",
      lender_id="lender-001",
      limit_amount=@finance.Money::new(minor=1000000, currency="CNY"),
      annual_rate_bps=600L,
      actor_id="alice",
      grant=financing_grant("financing:create"),
    )
    .approve(actor_id="alice", grant=financing_grant("financing:approve"))
    .activate(actor_id="alice", grant=financing_grant("financing:activate"))
  let drawn = facility.draw(
    amount=@finance.Money::new(minor=500000, currency="CNY"),
    actor_id="alice",
    grant=financing_grant("financing:draw"),
  )
  let draw_event = drawn.to_draw_event(
    draw_id="draw-events-001",
    event_id="financing-event-draw-001",
    event_type="financing.drawn",
    amount=@finance.Money::new(minor=500000, currency="CNY"),
    cash_account="cash",
    liability_account="financing-liability",
  )
  let repayment_event = drawn.to_repayment_event(
    repayment_id="repayment-events-001",
    event_id="financing-event-repayment-001",
    event_type="financing.repayment",
    amount=@finance.Money::new(minor=100000, currency="CNY"),
    liability_account="financing-liability",
    cash_account="cash",
  )
  assert_eq(draw_event.source_type, "financing_facility")
  assert_eq(draw_event.source_id, "draw-events-001")
  assert_eq(repayment_event.source_id, "repayment-events-001")
  assert_eq(draw_event.journal.postings[0].amount.minor, 500000L)
  assert_eq(repayment_event.journal.postings[0].amount.minor, 100000L)
}

///|
test "financing accounting link rejects repayment above outstanding balance" {
  let facility = FinancingFacility::new(
      facility_id="facility-event-gate",
      principal_id="co-001",
      project_scope="project:p-001",
      lender_id="lender-001",
      limit_amount=@finance.Money::new(minor=1000000, currency="CNY"),
      annual_rate_bps=600L,
      actor_id="alice",
      grant=financing_grant("financing:create"),
    )
    .approve(actor_id="alice", grant=financing_grant("financing:approve"))
    .activate(actor_id="alice", grant=financing_grant("financing:activate"))
    .draw(
      amount=@finance.Money::new(minor=100000, currency="CNY"),
      actor_id="alice",
      grant=financing_grant("financing:draw"),
    )
  try
    facility.to_repayment_event(
      repayment_id="repayment-event-gate",
      event_id="financing-event-gate",
      event_type="financing.repayment",
      amount=@finance.Money::new(minor=100001, currency="CNY"),
      liability_account="financing-liability",
      cash_account="cash",
    )
  catch {
    FinancingError::OverRepayment => ()
    _ => fail("wrong financing accounting error")
  } noraise {
    _ => fail("expected financing accounting error")
  }
}

///|
test "financing facility blocks a draw above its limit" {
  let facility = FinancingFacility::new(
      facility_id="facility-002",
      principal_id="co-001",
      project_scope="project:p-001",
      lender_id="lender-001",
      limit_amount=@finance.Money::new(minor=100, currency="CNY"),
      annual_rate_bps=600L,
      actor_id="alice",
      grant=financing_grant("financing:create"),
    )
    .approve(actor_id="alice", grant=financing_grant("financing:approve"))
    .activate(actor_id="alice", grant=financing_grant("financing:activate"))
  try
    facility.draw(
      amount=@finance.Money::new(minor=101, currency="CNY"),
      actor_id="alice",
      grant=financing_grant("financing:draw"),
    )
  catch {
    FinancingError::LimitExceeded => ()
    _ => fail("wrong financing error")
  } noraise {
    _ => fail("expected financing error")
  }
}

///|
test "financing facility persists draw and repayment evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let facility = FinancingFacility::new(
      facility_id="facility-projection",
      principal_id="co-001",
      project_scope="project:p-001",
      lender_id="lender-001",
      limit_amount=@finance.Money::new(minor=1000000, currency="CNY"),
      annual_rate_bps=600L,
      actor_id="alice",
      grant=financing_grant("financing:create"),
    )
    .approve(actor_id="alice", grant=financing_grant("financing:approve"))
    .activate(actor_id="alice", grant=financing_grant("financing:activate"))
    .draw(
      amount=@finance.Money::new(minor=500000, currency="CNY"),
      actor_id="alice",
      grant=financing_grant("financing:draw"),
    )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="financing_facility",
    aggregate_id="facility-projection",
  )
  let projection = facility.append_projection(projection)
  let repaid = facility.repay(
    amount=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=financing_grant("financing:repay"),
  )
  let projection = repaid.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("400000"))
      assert_true(latest.payload.contains("partially_repaid"))
    }
    None => fail("expected financing projection")
  }
}
