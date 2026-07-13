///|
fn portfolio_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-portfolio",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn portfolio_mandate() -> @domain.InvestmentMandate raise @domain.InvestmentError {
  @domain.InvestmentMandate::new(
    mandate_id="mandate-portfolio",
    principal_id="co-001",
    project_scope="project:p-001",
    base_currency="CNY",
    max_exposure=try! @finance.Money::new(minor=1000000, currency="CNY"),
    max_single_position=try! @finance.Money::new(minor=600000, currency="CNY"),
    actor_id="alice",
    grant=portfolio_grant("investment:mandate:create"),
  )
}

///|
test "portfolio values positions against explicit quotes" {
  let mandate = portfolio_mandate()
  let portfolio = Portfolio::new(
    mandate,
    portfolio_id="portfolio-001",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  )
  let position : @domain.InvestmentPosition = {
    position_id: "position-001",
    mandate_id: "mandate-portfolio",
    instrument: "FUND-001",
    quantity: 100L,
    cost_basis: @finance.Money::new(minor=300000, currency="CNY"),
  }
  let report = portfolio
    .add_position(
      position,
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:add"),
    )
    .value([
      {
        instrument: "FUND-001",
        price: @finance.Money::new(minor=3200, currency="CNY"),
      },
    ])
  assert_eq(report.total_market_value.minor, 320000L)
  assert_true(report.within_mandate)
}

///|
test "portfolio rejects a position from another mandate" {
  let portfolio = Portfolio::new(
    portfolio_mandate(),
    portfolio_id="portfolio-002",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  )
  let position : @domain.InvestmentPosition = {
    position_id: "position-002",
    mandate_id: "other-mandate",
    instrument: "FUND-002",
    quantity: 1L,
    cost_basis: @finance.Money::new(minor=100, currency="CNY"),
  }
  try
    portfolio.add_position(
      position,
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:add"),
    )
  catch {
    PortfolioError::WrongMandate => ()
    _ => fail("wrong portfolio error")
  } noraise {
    _ => fail("expected portfolio error")
  }
}

///|
test "portfolio rejects a missing market quote" {
  let portfolio = Portfolio::new(
    portfolio_mandate(),
    portfolio_id="portfolio-003",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  )
  let position : @domain.InvestmentPosition = {
    position_id: "position-003",
    mandate_id: "mandate-portfolio",
    instrument: "FUND-003",
    quantity: 1L,
    cost_basis: @finance.Money::new(minor=100, currency="CNY"),
  }
  try
    portfolio
    .add_position(
      position,
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:add"),
    )
    .value([])
  catch {
    PortfolioError::MissingQuote => ()
    _ => fail("wrong portfolio error")
  } noraise {
    _ => fail("expected portfolio error")
  }
}

///|
test "portfolio valuation emits gain and loss accounting links" {
  let portfolio = Portfolio::new(
    portfolio_mandate(),
    portfolio_id="portfolio-valuation-events",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  ).add_position(
    {
      position_id: "position-valuation-events",
      mandate_id: "mandate-portfolio",
      instrument: "FUND-001",
      quantity: 100L,
      cost_basis: @finance.Money::new(minor=300000, currency="CNY"),
    },
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:add"),
  )
  let gain = portfolio.to_valuation_event(
    valuation_id="valuation-gain-001",
    event_id="investment-valuation-event-001",
    event_type="investment.valuation.gain",
    quotes=[
      {
        instrument: "FUND-001",
        price: @finance.Money::new(minor=3200, currency="CNY"),
      },
    ],
    investment_account="investment-asset",
    gain_account="unrealized-gain",
    loss_account="unrealized-loss",
    actor_id="alice",
    grant=portfolio_grant("investment:valuation:record"),
  )
  let loss = portfolio.to_valuation_event(
    valuation_id="valuation-loss-001",
    event_id="investment-valuation-event-002",
    event_type="investment.valuation.loss",
    quotes=[
      {
        instrument: "FUND-001",
        price: @finance.Money::new(minor=2800, currency="CNY"),
      },
    ],
    investment_account="investment-asset",
    gain_account="unrealized-gain",
    loss_account="unrealized-loss",
    actor_id="alice",
    grant=portfolio_grant("investment:valuation:record"),
  )
  assert_eq(gain.source_type, "investment_valuation")
  assert_eq(gain.journal.postings[0].amount.minor, 20000L)
  assert_true(gain.journal.postings[0].side == @finance.PostingSide::Debit)
  assert_eq(loss.journal.postings[0].amount.minor, 20000L)
  assert_true(loss.journal.postings[0].side == @finance.PostingSide::Debit)
}

///|
test "portfolio valuation link rejects an unchanged market value" {
  let portfolio = Portfolio::new(
    portfolio_mandate(),
    portfolio_id="portfolio-valuation-gate",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  ).add_position(
    {
      position_id: "position-valuation-gate",
      mandate_id: "mandate-portfolio",
      instrument: "FUND-001",
      quantity: 100L,
      cost_basis: @finance.Money::new(minor=300000, currency="CNY"),
    },
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:add"),
  )
  try
    portfolio.to_valuation_event(
      valuation_id="valuation-unchanged-001",
      event_id="investment-valuation-gate",
      event_type="investment.valuation.noop",
      quotes=[
        {
          instrument: "FUND-001",
          price: @finance.Money::new(minor=3000, currency="CNY"),
        },
      ],
      investment_account="investment-asset",
      gain_account="unrealized-gain",
      loss_account="unrealized-loss",
      actor_id="alice",
      grant=portfolio_grant("investment:valuation:record"),
    )
  catch {
    PortfolioError::InvalidAmount => ()
    _ => fail("wrong valuation accounting error")
  } noraise {
    _ => fail("expected valuation accounting error")
  }
}

///|
test "portfolio attributes per-position performance and persists evidence" {
  let portfolio = Portfolio::new(
      portfolio_mandate(),
      portfolio_id="portfolio-performance",
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:create"),
    )
    .add_position(
      {
        position_id: "position-performance-001",
        mandate_id: "mandate-portfolio",
        instrument: "FUND-001",
        quantity: 100L,
        cost_basis: @finance.Money::new(minor=300000, currency="CNY"),
      },
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:add"),
    )
    .add_position(
      {
        position_id: "position-performance-002",
        mandate_id: "mandate-portfolio",
        instrument: "FUND-002",
        quantity: 50L,
        cost_basis: @finance.Money::new(minor=100000, currency="CNY"),
      },
      actor_id="alice",
      grant=portfolio_grant("investment:portfolio:add"),
    )
  let report = portfolio.attribute_performance(period_id="2026-07", quotes=[
    {
      instrument: "FUND-001",
      price: @finance.Money::new(minor=3200, currency="CNY"),
    },
    {
      instrument: "FUND-002",
      price: @finance.Money::new(minor=1800, currency="CNY"),
    },
  ])
  assert_eq(report.total_cost_basis.minor, 400000L)
  assert_eq(report.total_market_value.minor, 410000L)
  assert_eq(report.gain_loss.minor, 10000L)
  assert_eq(report.return_bps, 250L)
  assert_eq(report.positions.length(), 2)
  assert_eq(report.positions[1].gain_loss.minor, -10000L)
  let comparison = report.compare_benchmark(
    benchmark_id="benchmark-cn-equity-2026-07",
    benchmark_return_bps=100L,
  )
  assert_eq(comparison.active_return_bps, 150L)
  assert_true(comparison.outperformed)
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="investment_performance",
    aggregate_id="portfolio-performance:2026-07",
  )
  let projection = report.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("return_bps"))
      assert_true(latest.payload.contains("-10000"))
    }
    None => fail("expected investment performance projection")
  }
  let benchmark_projection = @store.AggregateProjection::new(
    projection.into_store(),
    aggregate_type="investment_benchmark",
    aggregate_id="portfolio-performance:2026-07:benchmark-cn-equity-2026-07",
  )
  let benchmark_projection = comparison.append_projection(benchmark_projection)
  match benchmark_projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("150"))
    None => fail("expected benchmark comparison projection")
  }
}

///|
test "portfolio stress scenarios and projections preserve mandate evidence" {
  let portfolio = Portfolio::new(
    portfolio_mandate(),
    portfolio_id="portfolio-risk",
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:create"),
  ).add_position(
    {
      position_id: "position-risk",
      mandate_id: "mandate-portfolio",
      instrument: "FUND-001",
      quantity: 100L,
      cost_basis: @finance.Money::new(minor=300000, currency="CNY"),
    },
    actor_id="alice",
    grant=portfolio_grant("investment:portfolio:add"),
  )
  let scenario = RiskScenario::new(
    scenario_id="stress-down-25",
    name="25 percent market drawdown",
    shock_bps=-2500L,
    max_loss_minor=100000L,
  )
  let stress = portfolio.stress(
    [
      {
        instrument: "FUND-001",
        price: @finance.Money::new(minor=3200, currency="CNY"),
      },
    ],
    scenario,
  )
  assert_eq(stress.stressed_market_value.minor, 240000L)
  assert_eq(stress.loss_minor, 80000L)
  assert_true(stress.within_loss_limit)
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let portfolio_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="portfolio",
    aggregate_id="portfolio-risk",
  )
  let portfolio_projection = portfolio.append_projection(portfolio_projection)
  let stress_projection = @store.AggregateProjection::new(
    portfolio_projection.into_store(),
    aggregate_type="portfolio_stress",
    aggregate_id="stress-down-25",
  )
  let stress_projection = stress.append_projection(stress_projection)
  match stress_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("80000"))
      assert_true(latest.payload.contains("stress-down-25"))
    }
    None => fail("expected stress projection")
  }
}
