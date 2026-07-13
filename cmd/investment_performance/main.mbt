///|
pub(all) suberror InvestmentPerformanceError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Investment(@domain.InvestmentError)
  Portfolio(@portfolio.PortfolioError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise InvestmentPerformanceError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentPerformanceError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise InvestmentPerformanceError {
  match value {
    Object(value) => value
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise InvestmentPerformanceError {
  match obj.get(key) {
    Some(value) => value
    None => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise InvestmentPerformanceError {
  match required(obj, key) {
    String(value) => value
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise InvestmentPerformanceError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise InvestmentPerformanceError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise InvestmentPerformanceError {
  match required(obj, key) {
    Array(value) => value
    _ => raise InvestmentPerformanceError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise InvestmentPerformanceError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise InvestmentPerformanceError::Money(error)
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "investment-performance-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn positions_json(positions : Array[@domain.InvestmentPosition]) -> Json {
  let values : Array[Json] = []
  for position in positions {
    values.push(
      Json::object({
        "position_id": Json::string(position.position_id),
        "mandate_id": Json::string(position.mandate_id),
        "instrument": Json::string(position.instrument),
        "quantity": number(position.quantity),
        "cost_basis_minor": number(position.cost_basis.minor),
        "currency": Json::string(position.cost_basis.currency),
      }),
    )
  }
  Json::array(values)
}

///|
fn quotes_json(quotes : Array[@portfolio.MarketQuote]) -> Json {
  let values : Array[Json] = []
  for quote in quotes {
    values.push(
      Json::object({
        "instrument": Json::string(quote.instrument),
        "price_minor": number(quote.price.minor),
        "currency": Json::string(quote.price.currency),
      }),
    )
  }
  Json::array(values)
}

///|
fn performance_positions_json(
  positions : Array[@portfolio.PositionPerformance],
) -> Json {
  let values : Array[Json] = []
  for position in positions {
    values.push(
      Json::object({
        "position_id": Json::string(position.position_id),
        "instrument": Json::string(position.instrument),
        "cost_basis_minor": number(position.cost_basis.minor),
        "market_value_minor": number(position.market_value.minor),
        "gain_loss_minor": number(position.gain_loss.minor),
      }),
    )
  }
  Json::array(values)
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise InvestmentPerformanceError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.investment-performance-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise InvestmentPerformanceError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let portfolio_item = object(required(root, "portfolio"))
  let source_table = required_string(portfolio_item, "source_table")
  let source_id = required_string(portfolio_item, "source_id")
  let portfolio_id = required_string(portfolio_item, "portfolio_id")
  let mandate_id = required_string(portfolio_item, "mandate_id")
  let principal_id = required_string(portfolio_item, "principal_id")
  let project_scope = required_string(portfolio_item, "project_scope")
  let currency = required_string(portfolio_item, "currency")
  let max_exposure_minor = required_int64(portfolio_item, "max_exposure_minor")
  let max_single_position_minor = required_int64(
    portfolio_item, "max_single_position_minor",
  )
  let max_exposure = money(max_exposure_minor, currency)
  let max_single_position = money(max_single_position_minor, currency)
  let mandate = @domain.InvestmentMandate::new(
    mandate_id~,
    principal_id~,
    project_scope~,
    base_currency=currency,
    max_exposure~,
    max_single_position~,
    actor_id="migration",
    grant=grant(
      principal_id, "investment:mandate:create", project_scope, max_exposure_minor,
    ),
  ) catch {
    error => raise InvestmentPerformanceError::Investment(error)
  }
  let mandate = mandate.activate(
    actor_id="migration",
    grant=grant(
      principal_id, "investment:mandate:activate", project_scope, max_exposure_minor,
    ),
  ) catch {
    error => raise InvestmentPerformanceError::Investment(error)
  }
  let portfolio = @portfolio.Portfolio::new(
    mandate,
    portfolio_id~,
    actor_id="migration",
    grant=grant(
      principal_id, "investment:portfolio:create", project_scope, max_exposure_minor,
    ),
  ) catch {
    error => raise InvestmentPerformanceError::Portfolio(error)
  }
  let mut portfolio = portfolio
  let positions : Array[@domain.InvestmentPosition] = []
  for value in required_array(portfolio_item, "positions") {
    let item = object(value)
    let position_id = required_string(item, "position_id")
    let instrument = required_string(item, "instrument")
    let quantity = required_int64(item, "quantity")
    let cost_basis_minor = required_int64(item, "cost_basis_minor")
    let position_currency = required_string(item, "currency")
    let position_cost_basis = money(cost_basis_minor, position_currency)
    let position : @domain.InvestmentPosition = {
      position_id,
      mandate_id,
      instrument,
      quantity,
      cost_basis: position_cost_basis,
    }
    portfolio = portfolio.add_position(
      position,
      actor_id="migration",
      grant=grant(
        principal_id, "investment:portfolio:add", project_scope, cost_basis_minor,
      ),
    ) catch {
      error => raise InvestmentPerformanceError::Portfolio(error)
    }
    positions.push(position)
  }
  let quotes : Array[@portfolio.MarketQuote] = []
  for value in required_array(portfolio_item, "quotes") {
    let item = object(value)
    let instrument = required_string(item, "instrument")
    let price_minor = required_int64(item, "price_minor")
    let quote_currency = required_string(item, "currency")
    let quote_price = money(price_minor, quote_currency)
    let quote : @portfolio.MarketQuote = { instrument, price: quote_price }
    quotes.push(quote)
  }
  let benchmark_item = object(required(root, "benchmark"))
  let period_id = required_string(benchmark_item, "period_id")
  let benchmark_id = required_string(benchmark_item, "benchmark_id")
  let observation_id = required_string(benchmark_item, "observation_id")
  let evidence_id = required_string(benchmark_item, "evidence_id")
  let benchmark_return_bps = required_int64(
    benchmark_item, "benchmark_return_bps",
  )
  let observed_return_bps = required_int64(
    benchmark_item, "observed_return_bps",
  )
  let tolerance_bps = required_int64(benchmark_item, "tolerance_bps")
  let expected_within_mandate = required_bool(
    benchmark_item, "expected_within_mandate",
  )
  let expected_reconciled = required_bool(benchmark_item, "expected_reconciled")
  let performance = portfolio.attribute_performance(period_id~, quotes~) catch {
    error => raise InvestmentPerformanceError::Portfolio(error)
  }
  let comparison = performance.compare_benchmark(
    benchmark_id~,
    benchmark_return_bps~,
  ) catch {
    error => raise InvestmentPerformanceError::Portfolio(error)
  }
  let observation = @portfolio.BenchmarkObservation::new(
    observation_id~,
    benchmark_id~,
    period_id~,
    source_snapshot_id~,
    mapping_version~,
    evidence_id~,
    return_bps=observed_return_bps,
  ) catch {
    error => raise InvestmentPerformanceError::Portfolio(error)
  }
  let reconciliation = comparison.reconcile(observation, tolerance_bps~) catch {
    error => raise InvestmentPerformanceError::Portfolio(error)
  }
  if performance.within_mandate != expected_within_mandate ||
    reconciliation.reconciled != expected_reconciled {
    raise InvestmentPerformanceError::InvalidInput
  }
  let accepted : Array[Json] = []
  accepted.push(
    Json::object({
      "source_table": Json::string(source_table),
      "source_id": Json::string(source_id),
      "target_type": Json::string("investment_portfolio"),
      "target_id": Json::string(portfolio.portfolio_id),
      "target_candidate": Json::object({
        "source_snapshot_id": Json::string(source_snapshot_id),
        "mapping_version": Json::string(mapping_version),
        "run_id": Json::string(run_id),
        "portfolio_id": Json::string(portfolio.portfolio_id),
        "mandate_id": Json::string(portfolio.mandate_id),
        "principal_id": Json::string(portfolio.principal_id),
        "project_scope": Json::string(portfolio.project_scope),
        "currency": Json::string(portfolio.currency),
        "max_exposure_minor": number(portfolio.max_exposure.minor),
        "max_single_position_minor": number(portfolio.max_single_position.minor),
        "positions": positions_json(portfolio.positions),
        "quotes": quotes_json(quotes),
        "position_count": number(portfolio.positions.length().to_int64()),
        "portfolio_reviewed": Json::boolean(true),
        "position_mutated": Json::boolean(false),
        "analytics_only": Json::boolean(true),
        "accounting_posted": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "period_closed": Json::boolean(false),
      }),
    }),
  )
  accepted.push(
    Json::object({
      "source_table": Json::string(source_table),
      "source_id": Json::string(source_id),
      "target_type": Json::string("investment_performance"),
      "target_id": Json::string(
        performance.portfolio_id + ":" + performance.period_id,
      ),
      "target_candidate": Json::object({
        "source_snapshot_id": Json::string(source_snapshot_id),
        "mapping_version": Json::string(mapping_version),
        "run_id": Json::string(run_id),
        "portfolio_id": Json::string(performance.portfolio_id),
        "period_id": Json::string(performance.period_id),
        "currency": Json::string(performance.currency),
        "total_cost_basis_minor": number(performance.total_cost_basis.minor),
        "total_market_value_minor": number(performance.total_market_value.minor),
        "gain_loss_minor": number(performance.gain_loss.minor),
        "return_bps": number(performance.return_bps),
        "within_mandate": Json::boolean(performance.within_mandate),
        "positions": performance_positions_json(performance.positions),
        "analytics_only": Json::boolean(true),
        "position_mutated": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "period_closed": Json::boolean(false),
      }),
    }),
  )
  accepted.push(
    Json::object({
      "source_table": Json::string(
        required_string(benchmark_item, "source_table"),
      ),
      "source_id": Json::string(required_string(benchmark_item, "source_id")),
      "target_type": Json::string("investment_benchmark_reconciliation"),
      "target_id": Json::string(reconciliation.reconciliation_id),
      "target_candidate": Json::object({
        "source_snapshot_id": Json::string(source_snapshot_id),
        "mapping_version": Json::string(mapping_version),
        "run_id": Json::string(run_id),
        "reconciliation_id": Json::string(reconciliation.reconciliation_id),
        "portfolio_id": Json::string(reconciliation.portfolio_id),
        "period_id": Json::string(reconciliation.period_id),
        "benchmark_id": Json::string(reconciliation.benchmark_id),
        "observation_id": Json::string(reconciliation.observation_id),
        "evidence_id": Json::string(reconciliation.evidence_id),
        "portfolio_return_bps": number(reconciliation.portfolio_return_bps),
        "observed_benchmark_return_bps": number(
          reconciliation.observed_benchmark_return_bps,
        ),
        "comparison_benchmark_return_bps": number(
          reconciliation.comparison_benchmark_return_bps,
        ),
        "active_return_bps": number(reconciliation.active_return_bps),
        "difference_bps": number(reconciliation.difference_bps),
        "tolerance_bps": number(reconciliation.tolerance_bps),
        "reconciled": Json::boolean(reconciliation.reconciled),
        "analytics_only": Json::boolean(true),
        "position_mutated": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "period_closed": Json::boolean(false),
      }),
    }),
  )
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("investment-performance-v1"),
    "accepted_items": Json::array(accepted),
    "portfolio_count": number(1),
    "performance_count": number(1),
    "benchmark_reconciliation_count": number(1),
    "analytics_only": Json::boolean(true),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise InvestmentPerformanceError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: investment_performance <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      InvestmentPerformanceError::InvalidInput => {
        println("investment performance failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      InvestmentPerformanceError::Io(_) => {
        println("investment performance failed: filesystem error")
        @sys.exit(1)
      }
      InvestmentPerformanceError::Money(_) => {
        println("investment performance failed: money validation")
        @sys.exit(1)
      }
      InvestmentPerformanceError::Investment(error) => {
        println(
          "investment performance failed: mandate validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      InvestmentPerformanceError::Portfolio(error) => {
        println(
          "investment performance failed: portfolio validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
    }
  }
}
