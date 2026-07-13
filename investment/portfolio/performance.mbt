///|
pub(all) struct PositionPerformance {
  position_id : String
  instrument : String
  cost_basis : @finance.Money
  market_value : @finance.Money
  gain_loss : @finance.Money
} derive(Debug, Eq)

///|
pub(all) struct PerformanceReport {
  portfolio_id : String
  period_id : String
  currency : String
  total_cost_basis : @finance.Money
  total_market_value : @finance.Money
  gain_loss : @finance.Money
  return_bps : Int64
  positions : Array[PositionPerformance]
  within_mandate : Bool
} derive(Debug, Eq)

///|
pub(all) struct BenchmarkComparison {
  portfolio_id : String
  period_id : String
  benchmark_id : String
  portfolio_return_bps : Int64
  benchmark_return_bps : Int64
  active_return_bps : Int64
  outperformed : Bool
} derive(Debug, Eq)

///|
/// Compare a locally calculated return with an explicitly supplied benchmark
/// result. Benchmark data is evidence-owned by the caller and is never
/// inferred from portfolio quotes.
pub fn PerformanceReport::compare_benchmark(
  self : PerformanceReport,
  benchmark_id~ : String,
  benchmark_return_bps~ : Int64,
) -> BenchmarkComparison raise PortfolioError {
  if benchmark_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  let active_return_bps = self.return_bps - benchmark_return_bps
  {
    portfolio_id: self.portfolio_id,
    period_id: self.period_id,
    benchmark_id,
    portfolio_return_bps: self.return_bps,
    benchmark_return_bps,
    active_return_bps,
    outperformed: active_return_bps > 0L,
  }
}

///|
/// Attribute a portfolio period against explicit market quotes. This is a
/// deterministic evidence report; it does not imply realized performance,
/// cash movement, or investment approval.
pub fn Portfolio::attribute_performance(
  self : Portfolio,
  period_id~ : String,
  quotes~ : Array[MarketQuote],
) -> PerformanceReport raise PortfolioError {
  if period_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  let valuation = self.value(quotes)
  if self.positions.length() == 0 {
    raise PortfolioError::InvalidAmount
  }
  let mut total_cost_minor : Int64 = 0
  let position_reports : Array[PositionPerformance] = []
  for position in self.positions {
    if position.quantity <= 0L || position.cost_basis.minor <= 0L {
      raise PortfolioError::InvalidAmount
    }
    let price = match quote_for(quotes, position.instrument) {
      Some(value) => value
      None => raise PortfolioError::MissingQuote
    }
    if price.currency != self.currency ||
      position.cost_basis.currency != self.currency {
      raise PortfolioError::CurrencyMismatch
    }
    let market_minor = position.quantity * price.minor
    let gain_loss_minor = market_minor - position.cost_basis.minor
    let market_value = @finance.Money::new(
      minor=market_minor,
      currency=self.currency,
    ) catch {
      error => raise PortfolioError::Money(error)
    }
    let gain_loss = @finance.Money::new(
      minor=gain_loss_minor,
      currency=self.currency,
    ) catch {
      error => raise PortfolioError::Money(error)
    }
    total_cost_minor += position.cost_basis.minor
    position_reports.push({
      position_id: position.position_id,
      instrument: position.instrument,
      cost_basis: position.cost_basis,
      market_value,
      gain_loss,
    })
  }
  if total_cost_minor <= 0L {
    raise PortfolioError::InvalidAmount
  }
  let total_cost_basis = @finance.Money::new(
    minor=total_cost_minor,
    currency=self.currency,
  ) catch {
    error => raise PortfolioError::Money(error)
  }
  let gain_loss_minor = valuation.total_market_value.minor - total_cost_minor
  let gain_loss = @finance.Money::new(
    minor=gain_loss_minor,
    currency=self.currency,
  ) catch {
    error => raise PortfolioError::Money(error)
  }
  {
    portfolio_id: self.portfolio_id,
    period_id,
    currency: self.currency,
    total_cost_basis,
    total_market_value: valuation.total_market_value,
    gain_loss,
    return_bps: gain_loss_minor * 10000L / total_cost_minor,
    positions: position_reports,
    within_mandate: valuation.within_mandate,
  }
}

///|
fn performance_positions_json(positions : Array[PositionPerformance]) -> Json {
  let values : Array[Json] = []
  for position in positions {
    values.push(
      Json::object({
        "position_id": Json::string(position.position_id),
        "instrument": Json::string(position.instrument),
        "cost_basis_minor": Json::number(
          position.cost_basis.minor.to_double(),
          repr=position.cost_basis.minor.to_string(),
        ),
        "market_value_minor": Json::number(
          position.market_value.minor.to_double(),
          repr=position.market_value.minor.to_string(),
        ),
        "gain_loss_minor": Json::number(
          position.gain_loss.minor.to_double(),
          repr=position.gain_loss.minor.to_string(),
        ),
      }),
    )
  }
  Json::array(values)
}

///|
pub fn PerformanceReport::append_projection(
  self : PerformanceReport,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PortfolioError {
  let aggregate_id = self.portfolio_id + ":" + self.period_id
  if projection.aggregate_type != "investment_performance" ||
    projection.aggregate_id != aggregate_id {
    raise PortfolioError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "portfolio_id": Json::string(self.portfolio_id),
    "period_id": Json::string(self.period_id),
    "currency": Json::string(self.currency),
    "total_cost_basis_minor": Json::number(
      self.total_cost_basis.minor.to_double(),
      repr=self.total_cost_basis.minor.to_string(),
    ),
    "total_market_value_minor": Json::number(
      self.total_market_value.minor.to_double(),
      repr=self.total_market_value.minor.to_string(),
    ),
    "gain_loss_minor": Json::number(
      self.gain_loss.minor.to_double(),
      repr=self.gain_loss.minor.to_string(),
    ),
    "return_bps": Json::number(
      self.return_bps.to_double(),
      repr=self.return_bps.to_string(),
    ),
    "within_mandate": Json::boolean(self.within_mandate),
    "positions": performance_positions_json(self.positions),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-performance:" +
      aggregate_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PortfolioError::Projection(error)
  }
}

///|
pub fn BenchmarkComparison::append_projection(
  self : BenchmarkComparison,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PortfolioError {
  let aggregate_id = self.portfolio_id +
    ":" +
    self.period_id +
    ":" +
    self.benchmark_id
  if projection.aggregate_type != "investment_benchmark" ||
    projection.aggregate_id != aggregate_id {
    raise PortfolioError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "portfolio_id": Json::string(self.portfolio_id),
    "period_id": Json::string(self.period_id),
    "benchmark_id": Json::string(self.benchmark_id),
    "portfolio_return_bps": Json::number(
      self.portfolio_return_bps.to_double(),
      repr=self.portfolio_return_bps.to_string(),
    ),
    "benchmark_return_bps": Json::number(
      self.benchmark_return_bps.to_double(),
      repr=self.benchmark_return_bps.to_string(),
    ),
    "active_return_bps": Json::number(
      self.active_return_bps.to_double(),
      repr=self.active_return_bps.to_string(),
    ),
    "outperformed": Json::boolean(self.outperformed),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-benchmark:" +
      aggregate_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PortfolioError::Projection(error)
  }
}
