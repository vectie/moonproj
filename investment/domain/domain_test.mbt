///|
fn investment_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-investment",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 2000000,
    active: true,
  }
}

///|
test "investment proposal requires local analysis and approval" {
  let mandate = InvestmentMandate::new(
    mandate_id="mandate-001",
    principal_id="co-001",
    project_scope="project:p-001",
    base_currency="CNY",
    max_exposure=@finance.Money::new(minor=1000000, currency="CNY"),
    max_single_position=@finance.Money::new(minor=500000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:mandate:create"),
  ).activate(
    actor_id="alice",
    grant=investment_grant("investment:mandate:activate"),
  )
  let proposal = mandate.propose(
    proposal_id="proposal-001",
    instrument="FUND-001",
    quantity=100L,
    price=@finance.Money::new(minor=3000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:proposal:create"),
  )
  let report = @analytics.analyze_closes(instrument="FUND-001", closes=[
    2900L, 3000L, 3100L,
  ])
  let approved = proposal
    .attach_analysis(
      report~,
      actor_id="alice",
      grant=investment_grant("investment:proposal:analyze"),
    )
    .submit(
      actor_id="alice",
      grant=investment_grant("investment:proposal:submit"),
    )
    .approve(
      actor_id="alice",
      grant=investment_grant("investment:proposal:approve"),
    )
  let (executed, position) = approved.execute(
    position_id="position-001",
    actor_id="alice",
    grant=investment_grant("investment:execute"),
  )
  assert_true(executed.state == ProposalState::Executed)
  assert_eq(position.cost_basis.minor, 300000L)
  let journal = position.to_acquisition_journal(
    investment_account="1501",
    cash_account="1002",
  )
  @finance.validate_journal(journal)
  let event = position.to_accounting_event(
    event_id="event-position-001",
    event_type="investment.acquired",
    principal_id="co-001",
    investment_account="1501",
    cash_account="1002",
  )
  assert_eq(event.source_type, "investment_position")
}

///|
test "investment mandate blocks an oversized proposal" {
  let mandate = InvestmentMandate::new(
    mandate_id="mandate-002",
    principal_id="co-001",
    project_scope="project:p-001",
    base_currency="CNY",
    max_exposure=@finance.Money::new(minor=100000, currency="CNY"),
    max_single_position=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:mandate:create"),
  ).activate(
    actor_id="alice",
    grant=investment_grant("investment:mandate:activate"),
  )
  try
    mandate.propose(
      proposal_id="proposal-002",
      instrument="FUND-001",
      quantity=100L,
      price=@finance.Money::new(minor=1000, currency="CNY"),
      actor_id="alice",
      grant=investment_grant("investment:proposal:create"),
    )
  catch {
    InvestmentError::MandateLimitExceeded => ()
    _ => fail("wrong investment error")
  } noraise {
    _ => fail("expected investment error")
  }
}

///|
test "investment proposal rejects analysis for another instrument" {
  let mandate = InvestmentMandate::new(
    mandate_id="mandate-003",
    principal_id="co-001",
    project_scope="project:p-001",
    base_currency="CNY",
    max_exposure=@finance.Money::new(minor=100000, currency="CNY"),
    max_single_position=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:mandate:create"),
  ).activate(
    actor_id="alice",
    grant=investment_grant("investment:mandate:activate"),
  )
  let proposal = mandate.propose(
    proposal_id="proposal-003",
    instrument="FUND-001",
    quantity=10L,
    price=@finance.Money::new(minor=1000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:proposal:create"),
  )
  let report = @analytics.analyze_closes(instrument="FUND-002", closes=[
    100L, 110L, 120L,
  ])
  try
    proposal.attach_analysis(
      report~,
      actor_id="alice",
      grant=investment_grant("investment:proposal:analyze"),
    )
  catch {
    InvestmentError::AnalysisMismatch => ()
    _ => fail("wrong investment error")
  } noraise {
    _ => fail("expected investment error")
  }
}

///|
test "investment mandate proposal and position preserve Moonfish evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let mandate = InvestmentMandate::new(
    mandate_id="mandate-projection",
    principal_id="co-001",
    project_scope="project:p-001",
    base_currency="CNY",
    max_exposure=@finance.Money::new(minor=1000000, currency="CNY"),
    max_single_position=@finance.Money::new(minor=500000, currency="CNY"),
    actor_id="alice",
    grant=investment_grant("investment:mandate:create"),
  ).activate(
    actor_id="alice",
    grant=investment_grant("investment:mandate:activate"),
  )
  let mandate_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="investment_mandate",
    aggregate_id="mandate-projection",
  )
  let mandate_projection = mandate.append_projection(mandate_projection)
  let proposal = mandate
    .propose(
      proposal_id="proposal-projection",
      instrument="FUND-001",
      quantity=100L,
      price=@finance.Money::new(minor=3000, currency="CNY"),
      actor_id="alice",
      grant=investment_grant("investment:proposal:create"),
    )
    .attach_analysis(
      report=@analytics.analyze_closes(instrument="FUND-001", closes=[
        2900L, 3000L, 3100L,
      ]),
      actor_id="alice",
      grant=investment_grant("investment:proposal:analyze"),
    )
  let proposal_projection = @store.AggregateProjection::new(
    mandate_projection.into_store(),
    aggregate_type="investment_proposal",
    aggregate_id="proposal-projection",
  )
  let proposal_projection = proposal.append_projection(proposal_projection)
  match proposal_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("moving_average_minor"))
      assert_true(latest.payload.contains("analyzed"))
    }
    None => fail("expected proposal projection")
  }
}
