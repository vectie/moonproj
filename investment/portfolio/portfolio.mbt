///|
pub(all) struct MarketQuote {
  instrument : String
  price : @finance.Money
} derive(Debug, Eq)

///|
pub(all) struct Portfolio {
  portfolio_id : String
  mandate_id : String
  principal_id : String
  project_scope : String
  currency : String
  max_exposure : @finance.Money
  max_single_position : @finance.Money
  positions : Array[@domain.InvestmentPosition]
} derive(Debug, Eq)

///|
pub(all) struct ValuationReport {
  portfolio_id : String
  total_market_value : @finance.Money
  largest_position_value : @finance.Money
  position_count : Int
  within_mandate : Bool
} derive(Debug, Eq)

///|
pub(all) struct RiskScenario {
  scenario_id : String
  name : String
  shock_bps : Int64
  max_loss_minor : Int64
} derive(Debug, Eq)

///|
pub(all) struct StressReport {
  portfolio_id : String
  scenario_id : String
  stressed_market_value : @finance.Money
  loss_minor : Int64
  within_mandate : Bool
  within_loss_limit : Bool
} derive(Debug, Eq)

///|
pub(all) suberror PortfolioError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  WrongMandate
  DuplicatePosition
  ExposureExceeded
  MissingQuote
  InvalidScenario
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn RiskScenario::new(
  scenario_id~ : String,
  name~ : String,
  shock_bps~ : Int64,
  max_loss_minor~ : Int64,
) -> RiskScenario raise PortfolioError {
  if scenario_id.trim() == "" || name.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  if shock_bps < -10000L || shock_bps > 10000L || max_loss_minor < 0L {
    raise PortfolioError::InvalidScenario
  }
  { scenario_id, name, shock_bps, max_loss_minor }
}

///|
pub fn Portfolio::new(
  mandate : @domain.InvestmentMandate,
  portfolio_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Portfolio raise PortfolioError {
  if portfolio_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id=mandate.principal_id,
    actor_id~,
    capability="investment:portfolio:create",
    scope=mandate.project_scope,
    amount_minor=mandate.max_exposure.minor,
  ) catch {
    error => raise PortfolioError::NotAuthorized(error)
  }
  {
    portfolio_id,
    mandate_id: mandate.mandate_id,
    principal_id: mandate.principal_id,
    project_scope: mandate.project_scope,
    currency: mandate.base_currency,
    max_exposure: mandate.max_exposure,
    max_single_position: mandate.max_single_position,
    positions: [],
  }
}

///|
pub fn Portfolio::add_position(
  self : Portfolio,
  position : @domain.InvestmentPosition,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Portfolio raise PortfolioError {
  if position.position_id.trim() == "" || position.instrument.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  if position.mandate_id != self.mandate_id {
    raise PortfolioError::WrongMandate
  }
  if position.cost_basis.currency != self.currency {
    raise PortfolioError::CurrencyMismatch
  }
  for existing in self.positions {
    if existing.position_id == position.position_id {
      raise PortfolioError::DuplicatePosition
    }
  }
  let mut total_cost = position.cost_basis.minor
  for existing in self.positions {
    total_cost += existing.cost_basis.minor
  }
  if position.cost_basis.minor > self.max_single_position.minor ||
    total_cost > self.max_exposure.minor {
    raise PortfolioError::ExposureExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:portfolio:add",
    scope=self.project_scope,
    amount_minor=position.cost_basis.minor,
  ) catch {
    error => raise PortfolioError::NotAuthorized(error)
  }
  let positions = self.positions.copy()
  positions.push(position)
  { ..self, positions, }
}

///|
fn quote_for(
  quotes : Array[MarketQuote],
  instrument : String,
) -> @finance.Money? {
  for quote in quotes {
    if quote.instrument == instrument {
      return Some(quote.price)
    }
  }
  None
}

///|
pub fn Portfolio::value(
  self : Portfolio,
  quotes : Array[MarketQuote],
) -> ValuationReport raise PortfolioError {
  let mut total_minor : Int64 = 0
  let mut largest_minor : Int64 = 0
  for position in self.positions {
    let price = match quote_for(quotes, position.instrument) {
      Some(value) => value
      None => raise PortfolioError::MissingQuote
    }
    if price.currency != self.currency {
      raise PortfolioError::CurrencyMismatch
    }
    if price.minor <= 0 || position.quantity <= 0 {
      raise PortfolioError::InvalidAmount
    }
    let value_minor = position.quantity * price.minor
    total_minor += value_minor
    if value_minor > largest_minor {
      largest_minor = value_minor
    }
  }
  let total = @finance.Money::new(minor=total_minor, currency=self.currency) catch {
    error => raise PortfolioError::Money(error)
  }
  let largest = @finance.Money::new(minor=largest_minor, currency=self.currency) catch {
    error => raise PortfolioError::Money(error)
  }
  {
    portfolio_id: self.portfolio_id,
    total_market_value: total,
    largest_position_value: largest,
    position_count: self.positions.length(),
    within_mandate: total_minor <= self.max_exposure.minor &&
    largest_minor <= self.max_single_position.minor,
  }
}

///|
pub fn Portfolio::stress(
  self : Portfolio,
  quotes : Array[MarketQuote],
  scenario : RiskScenario,
) -> StressReport raise PortfolioError {
  let valuation = self.value(quotes)
  let multiplier = 10000L + scenario.shock_bps
  let stressed_minor : Int64 = Int64::div(
    valuation.total_market_value.minor * multiplier,
    10000L,
  )
  if stressed_minor < 0L {
    raise PortfolioError::InvalidScenario
  }
  let loss_minor = valuation.total_market_value.minor - stressed_minor
  let stressed = @finance.Money::new(
    minor=stressed_minor,
    currency=self.currency,
  ) catch {
    error => raise PortfolioError::Money(error)
  }
  {
    portfolio_id: self.portfolio_id,
    scenario_id: scenario.scenario_id,
    stressed_market_value: stressed,
    loss_minor,
    within_mandate: stressed_minor <= self.max_exposure.minor,
    within_loss_limit: loss_minor <= scenario.max_loss_minor,
  }
}

///|
fn portfolio_positions_json(
  positions : Array[@domain.InvestmentPosition],
) -> Json {
  let values : Array[Json] = []
  for position in positions {
    values.push(
      Json::object({
        "position_id": Json::string(position.position_id),
        "mandate_id": Json::string(position.mandate_id),
        "instrument": Json::string(position.instrument),
        "quantity": Json::number(
          position.quantity.to_double(),
          repr=position.quantity.to_string(),
        ),
        "cost_basis_minor": Json::number(
          position.cost_basis.minor.to_double(),
          repr=position.cost_basis.minor.to_string(),
        ),
        "currency": Json::string(position.cost_basis.currency),
      }),
    )
  }
  Json::array(values)
}

///|
pub fn Portfolio::append_projection(
  self : Portfolio,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PortfolioError {
  if projection.aggregate_type != "portfolio" ||
    projection.aggregate_id != self.portfolio_id {
    raise PortfolioError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "portfolio_id": Json::string(self.portfolio_id),
    "mandate_id": Json::string(self.mandate_id),
    "principal_id": Json::string(self.principal_id),
    "project_scope": Json::string(self.project_scope),
    "currency": Json::string(self.currency),
    "max_exposure_minor": Json::number(
      self.max_exposure.minor.to_double(),
      repr=self.max_exposure.minor.to_string(),
    ),
    "max_single_position_minor": Json::number(
      self.max_single_position.minor.to_double(),
      repr=self.max_single_position.minor.to_string(),
    ),
    "positions": portfolio_positions_json(self.positions),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:portfolio:" +
      self.portfolio_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PortfolioError::Projection(error)
  }
}

///|
pub fn StressReport::append_projection(
  self : StressReport,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PortfolioError {
  if projection.aggregate_type != "portfolio_stress" ||
    projection.aggregate_id != self.scenario_id {
    raise PortfolioError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "portfolio_id": Json::string(self.portfolio_id),
    "scenario_id": Json::string(self.scenario_id),
    "stressed_market_value_minor": Json::number(
      self.stressed_market_value.minor.to_double(),
      repr=self.stressed_market_value.minor.to_string(),
    ),
    "loss_minor": Json::number(
      self.loss_minor.to_double(),
      repr=self.loss_minor.to_string(),
    ),
    "within_mandate": Json::boolean(self.within_mandate),
    "within_loss_limit": Json::boolean(self.within_loss_limit),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:portfolio-stress:" +
      self.scenario_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PortfolioError::Projection(error)
  }
}
