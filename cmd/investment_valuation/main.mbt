///|
pub(all) suberror InvestmentValuationError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Investment(@domain.InvestmentError)
  Portfolio(@portfolio.PortfolioError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise InvestmentValuationError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentValuationError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise InvestmentValuationError {
  match value {
    Object(value) => value
    _ => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise InvestmentValuationError {
  match obj.get(key) {
    Some(value) => value
    None => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise InvestmentValuationError {
  match required(obj, key) {
    String(value) => value
    _ => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise InvestmentValuationError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise InvestmentValuationError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise InvestmentValuationError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise InvestmentValuationError {
  match required(obj, key) {
    Array(value) => value
    _ => raise InvestmentValuationError::InvalidInput
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
) -> @finance.Money raise InvestmentValuationError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise InvestmentValuationError::Money(error)
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
    grant_id: "investment-valuation-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise InvestmentValuationError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.investment-valuation-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise InvestmentValuationError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let portfolio_item = object(required(root, "portfolio"))
  let portfolio_source_table = required_string(portfolio_item, "source_table")
  let portfolio_source_id = required_string(portfolio_item, "source_id")
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
    error => raise InvestmentValuationError::Investment(error)
  }
  let mandate = mandate.activate(
    actor_id="migration",
    grant=grant(
      principal_id, "investment:mandate:activate", project_scope, max_exposure_minor,
    ),
  ) catch {
    error => raise InvestmentValuationError::Investment(error)
  }
  let portfolio = @portfolio.Portfolio::new(
    mandate,
    portfolio_id~,
    actor_id="migration",
    grant=grant(
      principal_id, "investment:portfolio:create", project_scope, max_exposure_minor,
    ),
  ) catch {
    error => raise InvestmentValuationError::Portfolio(error)
  }
  let mut portfolio = portfolio
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
      error => raise InvestmentValuationError::Portfolio(error)
    }
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

  let valuation_item = object(required(root, "valuation"))
  let source_table = required_string(valuation_item, "source_table")
  let source_id = required_string(valuation_item, "source_id")
  let valuation_id = required_string(valuation_item, "valuation_id")
  let event_id = required_string(valuation_item, "event_id")
  let event_type = required_string(valuation_item, "event_type")
  let scope = required_string(valuation_item, "scope")
  let investment_account = required_string(valuation_item, "investment_account")
  let gain_account = required_string(valuation_item, "gain_account")
  let loss_account = required_string(valuation_item, "loss_account")
  let expected_gain_loss_minor = required_int64(
    valuation_item, "expected_gain_loss_minor",
  )
  let expected_amount_minor = required_int64(
    valuation_item, "expected_amount_minor",
  )
  let expected_journal_id = required_string(valuation_item, "journal_id")
  if source_id != valuation_id ||
    required_string(valuation_item, "principal_id") != principal_id ||
    required_string(valuation_item, "currency") != currency ||
    scope != project_scope {
    raise InvestmentValuationError::InvalidInput
  }
  let valuation = portfolio.value(quotes) catch {
    error => raise InvestmentValuationError::Portfolio(error)
  }
  let mut cost_minor : Int64 = 0
  for position in portfolio.positions {
    cost_minor += position.cost_basis.minor
  }
  let gain_loss_minor = valuation.total_market_value.minor - cost_minor
  if gain_loss_minor != expected_gain_loss_minor ||
    (if gain_loss_minor < 0L { 0L - gain_loss_minor } else { gain_loss_minor }) !=
    expected_amount_minor ||
    expected_amount_minor <= 0L {
    raise InvestmentValuationError::InvalidInput
  }
  let event = portfolio.to_valuation_event(
    valuation_id~,
    event_id~,
    event_type~,
    quotes~,
    investment_account~,
    gain_account~,
    loss_account~,
    actor_id="migration",
    grant=grant(
      principal_id, "investment:valuation:record", scope, expected_amount_minor,
    ),
  ) catch {
    error => raise InvestmentValuationError::Portfolio(error)
  }
  if event.source_type != "investment_valuation" ||
    event.source_id != source_id ||
    event.principal_id != principal_id ||
    event.journal.entry_id != expected_journal_id ||
    event.journal.postings.length() != 2 ||
    event.journal.postings[0].amount.minor != expected_amount_minor ||
    event.journal.postings[0].amount.currency != currency {
    raise InvestmentValuationError::InvalidInput
  }
  let candidate = Json::object({
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "portfolio_source_table": Json::string(portfolio_source_table),
    "portfolio_source_id": Json::string(portfolio_source_id),
    "valuation_id": Json::string(valuation_id),
    "event_id": Json::string(event.event_id),
    "event_type": Json::string(event.event_type),
    "source_type": Json::string(event.source_type),
    "source_id": Json::string(event.source_id),
    "principal_id": Json::string(event.principal_id),
    "scope": Json::string(scope),
    "journal_id": Json::string(event.journal.entry_id),
    "debit_account": Json::string(event.journal.postings[0].account),
    "credit_account": Json::string(event.journal.postings[1].account),
    "amount_minor": number(event.journal.postings[0].amount.minor),
    "currency": Json::string(event.journal.postings[0].amount.currency),
    "gain_loss_minor": number(gain_loss_minor),
    "accounting_event_created": Json::boolean(true),
    "accounting_linked": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "position_mutated": Json::boolean(false),
    "period_closed": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("investment-valuation-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("investment_valuation"),
        "target_id": Json::string(valuation_id),
        "target_candidate": candidate,
      }),
    ]),
    "valuation_count": number(1),
    "accounting_event_created": Json::boolean(true),
    "accounting_linked": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "position_mutated": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise InvestmentValuationError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: investment_valuation <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      InvestmentValuationError::InvalidInput => {
        println("investment valuation failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      InvestmentValuationError::Io(_) => {
        println("investment valuation failed: filesystem error")
        @sys.exit(1)
      }
      InvestmentValuationError::Money(_) => {
        println("investment valuation failed: money validation")
        @sys.exit(1)
      }
      InvestmentValuationError::Investment(error) => {
        println(
          "investment valuation failed: mandate validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      InvestmentValuationError::Portfolio(error) => {
        println(
          "investment valuation failed: portfolio validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
    }
  }
}
