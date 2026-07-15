///|
/// Compile a reviewed portfolio/quote/benchmark map into the explicit native
/// investment-performance plan. No market provider or trading authority is
/// called by this compiler.
pub(all) suberror InvestmentPerformancePlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> InvestmentPerformancePlanError {
  InvestmentPerformancePlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise InvestmentPerformancePlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentPerformancePlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise InvestmentPerformancePlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise InvestmentPerformancePlanError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise InvestmentPerformancePlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
  fallback : String,
  path : String,
) -> String raise InvestmentPerformancePlanError {
  match fields.get(key) {
    None => fallback
    Some(String(value)) if !value.trim().is_empty() => value
    Some(_) => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise InvestmentPerformancePlanError {
  match required(fields, key, path) {
    True => true
    False => false
    _ => raise fail("expected boolean at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise InvestmentPerformancePlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise InvestmentPerformancePlanError {
  match required(fields, key, path) {
    Array(values) if !values.is_empty() => values
    _ => raise fail("expected non-empty array at " + path + "." + key)
  }
}

///|
fn secret_key(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.has_suffix("ip")
}

///|
fn reject_secret_keys(
  value : Json,
  path : String,
) -> Unit raise InvestmentPerformancePlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secret_keys(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secret_keys(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise InvestmentPerformancePlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.investment-performance-map.v1" {
    raise fail("unexpected investment performance map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("investment performance map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let portfolio = object(required(root, "portfolio", "mapping"), "portfolio")
  let source_table = required_string(portfolio, "source_table", "portfolio")
  let source_id = required_string(portfolio, "source_id", "portfolio")
  let portfolio_id = required_string(portfolio, "portfolio_id", "portfolio")
  let mandate_id = required_string(portfolio, "mandate_id", "portfolio")
  let principal_id = required_string(portfolio, "principal_id", "portfolio")
  let project_scope = required_string(portfolio, "project_scope", "portfolio")
  let currency = required_string(portfolio, "currency", "portfolio")
  let max_exposure = required_int(portfolio, "max_exposure_minor", "portfolio")
  let max_single_position = required_int(
    portfolio, "max_single_position_minor", "portfolio",
  )
  if max_exposure < 1 ||
    max_single_position < 1 ||
    max_single_position > max_exposure {
    raise fail("portfolio exposure limits are invalid")
  }
  let position_values = required_array(portfolio, "positions", "portfolio")
  let position_ids : Array[String] = []
  let instruments : Array[String] = []
  let positions : Array[Json] = []
  for index in 0..<position_values.length() {
    let path = "portfolio.positions[" + index.to_string() + "]"
    let position = object(position_values[index], path)
    let position_id = required_string(position, "position_id", path)
    let instrument = required_string(position, "instrument", path)
    let quantity = required_int(position, "quantity", path)
    let cost_basis = required_int(position, "cost_basis_minor", path)
    let position_currency = optional_string(
      position, "currency", currency, path,
    )
    if quantity < 1 || cost_basis < 1 {
      raise fail("position amount/quantity is invalid at " + path)
    }
    if position_ids.contains(position_id) {
      raise fail("duplicate position_id: " + position_id)
    }
    if instruments.contains(instrument) {
      raise fail("duplicate instrument: " + instrument)
    }
    if position_currency != currency {
      raise fail("position currency differs from portfolio at " + path)
    }
    if cost_basis > max_single_position {
      raise fail("position cost basis exceeds max single position at " + path)
    }
    position_ids.push(position_id)
    instruments.push(instrument)
    positions.push(
      Json::object({
        "position_id": Json::string(position_id),
        "instrument": Json::string(instrument),
        "quantity": number(quantity),
        "cost_basis_minor": number(cost_basis),
        "currency": Json::string(position_currency),
      }),
    )
  }
  let quote_values = required(portfolio, "quotes", "portfolio")
  let quotes_array = match quote_values {
    Array(values) if values.length() == positions.length() => values
    _ => raise fail("portfolio.quotes must contain one quote per position")
  }
  let quote_instruments : Array[String] = []
  let quotes : Array[Json] = []
  for index in 0..<quotes_array.length() {
    let path = "portfolio.quotes[" + index.to_string() + "]"
    let quote = object(quotes_array[index], path)
    let instrument = required_string(quote, "instrument", path)
    let price = required_int(quote, "price_minor", path)
    let quote_currency = optional_string(quote, "currency", currency, path)
    if price < 1 || !instruments.contains(instrument) {
      raise fail("quote instrument or price is invalid at " + path)
    }
    if quote_instruments.contains(instrument) {
      raise fail("duplicate quote instrument: " + instrument)
    }
    if quote_currency != currency {
      raise fail("quote currency differs from portfolio at " + path)
    }
    quote_instruments.push(instrument)
    quotes.push(
      Json::object({
        "instrument": Json::string(instrument),
        "price_minor": number(price),
        "currency": Json::string(quote_currency),
      }),
    )
  }
  let benchmark = object(required(root, "benchmark", "mapping"), "benchmark")
  let benchmark_source_table = required_string(
    benchmark, "source_table", "benchmark",
  )
  let benchmark_source_id = required_string(benchmark, "source_id", "benchmark")
  let period_id = required_string(benchmark, "period_id", "benchmark")
  let benchmark_id = required_string(benchmark, "benchmark_id", "benchmark")
  let observation_id = required_string(benchmark, "observation_id", "benchmark")
  let evidence_id = required_string(benchmark, "evidence_id", "benchmark")
  let benchmark_return = required_int(
    benchmark, "benchmark_return_bps", "benchmark",
  )
  let observed_return = required_int(
    benchmark, "observed_return_bps", "benchmark",
  )
  let tolerance = required_int(benchmark, "tolerance_bps", "benchmark")
  let expected_within_mandate = required_bool(
    benchmark, "expected_within_mandate", "benchmark",
  )
  let expected_reconciled = required_bool(
    benchmark, "expected_reconciled", "benchmark",
  )
  if benchmark_return < 0 ||
    observed_return < 0 ||
    tolerance < 0 ||
    benchmark_source_id != observation_id {
    raise fail("benchmark identity or return values are invalid")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.investment-performance-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "portfolio": Json::object({
      "source_table": Json::string(source_table),
      "source_id": Json::string(source_id),
      "portfolio_id": Json::string(portfolio_id),
      "mandate_id": Json::string(mandate_id),
      "principal_id": Json::string(principal_id),
      "project_scope": Json::string(project_scope),
      "currency": Json::string(currency),
      "max_exposure_minor": number(max_exposure),
      "max_single_position_minor": number(max_single_position),
      "positions": Json::array(positions),
      "quotes": Json::array(quotes),
    }),
    "benchmark": Json::object({
      "source_table": Json::string(benchmark_source_table),
      "source_id": Json::string(benchmark_source_id),
      "period_id": Json::string(period_id),
      "benchmark_id": Json::string(benchmark_id),
      "observation_id": Json::string(observation_id),
      "evidence_id": Json::string(evidence_id),
      "benchmark_return_bps": number(benchmark_return),
      "observed_return_bps": number(observed_return),
      "tolerance_bps": number(tolerance),
      "expected_within_mandate": Json::boolean(expected_within_mandate),
      "expected_reconciled": Json::boolean(expected_reconciled),
    }),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise InvestmentPerformancePlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "positions": number(positions.length().to_int64()),
      "quotes": number(quotes.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: investment_performance_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    InvestmentPerformancePlanError::InvalidInput(message) => {
      println("investment performance plan failed: " + message)
      @sys.exit(1)
    }
    InvestmentPerformancePlanError::Io(_) => {
      println("investment performance plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
