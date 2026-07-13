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
/// An externally supplied benchmark observation. The observation is treated
/// as source evidence, not as a quote that the portfolio can execute against.
/// Its snapshot, mapping, and evidence identities are mandatory so a later
/// reconciliation can be replayed without guessing which feed was used.
pub(all) struct BenchmarkObservation {
  observation_id : String
  benchmark_id : String
  period_id : String
  source_snapshot_id : String
  mapping_version : String
  evidence_id : String
  return_bps : Int64
} derive(Debug, Eq)

///|
/// Reconciles a local benchmark comparison against one source-owned external
/// observation. This is analytics evidence only: it cannot mutate positions,
/// post accounting, or release cash.
pub(all) struct BenchmarkReconciliation {
  reconciliation_id : String
  portfolio_id : String
  period_id : String
  benchmark_id : String
  observation_id : String
  source_snapshot_id : String
  mapping_version : String
  evidence_id : String
  portfolio_return_bps : Int64
  observed_benchmark_return_bps : Int64
  comparison_benchmark_return_bps : Int64
  active_return_bps : Int64
  difference_bps : Int64
  tolerance_bps : Int64
  reconciled : Bool
} derive(Debug, Eq)

///|
pub fn BenchmarkObservation::new(
  observation_id~ : String,
  benchmark_id~ : String,
  period_id~ : String,
  source_snapshot_id~ : String,
  mapping_version~ : String,
  evidence_id~ : String,
  return_bps~ : Int64,
) -> BenchmarkObservation raise PortfolioError {
  if observation_id.trim() == "" ||
    benchmark_id.trim() == "" ||
    period_id.trim() == "" ||
    source_snapshot_id.trim() == "" ||
    mapping_version.trim() == "" ||
    evidence_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  {
    observation_id,
    benchmark_id,
    period_id,
    source_snapshot_id,
    mapping_version,
    evidence_id,
    return_bps,
  }
}

///|
/// Build a benchmark comparison from explicit return evidence. Keeping this
/// constructor public lets migration adapters validate source-shaped values
/// without constructing a portfolio or position book.
pub fn BenchmarkComparison::new(
  portfolio_id~ : String,
  period_id~ : String,
  benchmark_id~ : String,
  portfolio_return_bps~ : Int64,
  benchmark_return_bps~ : Int64,
) -> BenchmarkComparison raise PortfolioError {
  if portfolio_id.trim() == "" ||
    period_id.trim() == "" ||
    benchmark_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  let active_return_bps = portfolio_return_bps - benchmark_return_bps
  {
    portfolio_id,
    period_id,
    benchmark_id,
    portfolio_return_bps,
    benchmark_return_bps,
    active_return_bps,
    outperformed: active_return_bps > 0L,
  }
}

///|
/// Compare a locally calculated return with an explicitly supplied benchmark
/// result. Benchmark data is evidence-owned by the caller and is never
/// inferred from portfolio quotes.
pub fn PerformanceReport::compare_benchmark(
  self : PerformanceReport,
  benchmark_id~ : String,
  benchmark_return_bps~ : Int64,
) -> BenchmarkComparison raise PortfolioError {
  BenchmarkComparison::new(
    portfolio_id=self.portfolio_id,
    period_id=self.period_id,
    benchmark_id~,
    portfolio_return_bps=self.return_bps,
    benchmark_return_bps~,
  )
}

///|
pub fn BenchmarkComparison::reconcile(
  self : BenchmarkComparison,
  observation : BenchmarkObservation,
  tolerance_bps~ : Int64,
) -> BenchmarkReconciliation raise PortfolioError {
  if tolerance_bps < 0L {
    raise PortfolioError::InvalidAmount
  }
  if observation.benchmark_id != self.benchmark_id ||
    observation.period_id != self.period_id {
    raise PortfolioError::ProjectionIdentity
  }
  let difference_bps = self.benchmark_return_bps - observation.return_bps
  let absolute_difference_bps = if difference_bps < 0L {
    0L - difference_bps
  } else {
    difference_bps
  }
  {
    reconciliation_id: self.portfolio_id +
    ":" +
    self.period_id +
    ":" +
    self.benchmark_id +
    ":" +
    observation.observation_id,
    portfolio_id: self.portfolio_id,
    period_id: self.period_id,
    benchmark_id: self.benchmark_id,
    observation_id: observation.observation_id,
    source_snapshot_id: observation.source_snapshot_id,
    mapping_version: observation.mapping_version,
    evidence_id: observation.evidence_id,
    portfolio_return_bps: self.portfolio_return_bps,
    observed_benchmark_return_bps: observation.return_bps,
    comparison_benchmark_return_bps: self.benchmark_return_bps,
    active_return_bps: self.portfolio_return_bps - observation.return_bps,
    difference_bps,
    tolerance_bps,
    reconciled: absolute_difference_bps <= tolerance_bps,
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

///|
pub fn BenchmarkReconciliation::append_projection(
  self : BenchmarkReconciliation,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PortfolioError {
  if projection.aggregate_type != "investment_benchmark_reconciliation" ||
    projection.aggregate_id != self.reconciliation_id {
    raise PortfolioError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "reconciliation_id": Json::string(self.reconciliation_id),
    "portfolio_id": Json::string(self.portfolio_id),
    "period_id": Json::string(self.period_id),
    "benchmark_id": Json::string(self.benchmark_id),
    "observation_id": Json::string(self.observation_id),
    "source_snapshot_id": Json::string(self.source_snapshot_id),
    "mapping_version": Json::string(self.mapping_version),
    "evidence_id": Json::string(self.evidence_id),
    "portfolio_return_bps": Json::number(
      self.portfolio_return_bps.to_double(),
      repr=self.portfolio_return_bps.to_string(),
    ),
    "observed_benchmark_return_bps": Json::number(
      self.observed_benchmark_return_bps.to_double(),
      repr=self.observed_benchmark_return_bps.to_string(),
    ),
    "comparison_benchmark_return_bps": Json::number(
      self.comparison_benchmark_return_bps.to_double(),
      repr=self.comparison_benchmark_return_bps.to_string(),
    ),
    "active_return_bps": Json::number(
      self.active_return_bps.to_double(),
      repr=self.active_return_bps.to_string(),
    ),
    "difference_bps": Json::number(
      self.difference_bps.to_double(),
      repr=self.difference_bps.to_string(),
    ),
    "tolerance_bps": Json::number(
      self.tolerance_bps.to_double(),
      repr=self.tolerance_bps.to_string(),
    ),
    "reconciled": Json::boolean(self.reconciled),
    "analytics_only": Json::boolean(true),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-benchmark-reconciliation:" +
      self.reconciliation_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PortfolioError::Projection(error)
  }
}
