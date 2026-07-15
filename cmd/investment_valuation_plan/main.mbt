///|
pub(all) suberror InvestmentValuationPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> InvestmentValuationPlanError {
  InvestmentValuationPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise InvestmentValuationPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentValuationPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise InvestmentValuationPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn required_string(
  value : Json,
  key : String,
) -> String raise InvestmentValuationPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_bool(
  value : Json,
  key : String,
) -> Bool raise InvestmentValuationPlanError {
  match value {
    True => true
    False => false
    _ => raise fail(key + " must be boolean")
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim()
  if source.is_empty() {
    return default
  }
  let mut index = 0
  let mut sign : Int64 = 1
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut result : Int64 = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return default
    }
    result = result * 10 + (char.to_int() - '0'.to_int()).to_int64()
    index += 1
  }
  result * sign
}

///|
fn integer(
  value : Json,
  key : String,
  minimum : Int64?,
) -> Int64 raise InvestmentValuationPlanError {
  let result = match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), 0L)
    _ => raise fail(key + " must be an integer")
  }
  match minimum {
    Some(value) if result < value =>
      raise fail(key + " must be >= " + value.to_string())
    _ => ()
  }
  result
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
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise InvestmentValuationPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secrets(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn run(
  performance_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise InvestmentValuationPlanError {
  let performance = object(read_json(performance_path), "performance")
  let config_value = read_json(mapping_path)
  reject_secrets(config_value, "mapping")
  let config = object(config_value, "mapping")
  if required_string(field(Json::object(performance), "format"), "format") !=
    "moonproj.erp.investment-performance-plan.v1" ||
    !required_bool(field(Json::object(performance), "reviewed"), "reviewed") {
    raise fail("unexpected or unreviewed investment performance plan")
  }
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.investment-valuation-map.v1" ||
    !required_bool(field(Json::object(config), "reviewed"), "reviewed") {
    raise fail("unexpected or unreviewed investment valuation map")
  }
  let source_snapshot_id = required_string(
    field(Json::object(performance), "source_snapshot_id"),
    "source_snapshot_id",
  )
  if required_string(
      field(Json::object(config), "source_snapshot_id"),
      "source_snapshot_id",
    ) !=
    source_snapshot_id {
    raise fail("valuation map source_snapshot_id differs from performance plan")
  }
  let mapping_version = required_string(
    field(Json::object(config), "mapping_version"),
    "mapping_version",
  )
  let run_id = required_string(field(Json::object(config), "run_id"), "run_id")
  let portfolio = object(
    field(Json::object(performance), "portfolio"),
    "portfolio",
  )
  let portfolio_source_id = required_string(
    field(Json::object(portfolio), "source_id"),
    "portfolio.source_id",
  )
  let portfolio_id = required_string(
    field(Json::object(portfolio), "portfolio_id"),
    "portfolio.portfolio_id",
  )
  let principal_id = required_string(
    field(Json::object(portfolio), "principal_id"),
    "portfolio.principal_id",
  )
  let project_scope = required_string(
    field(Json::object(portfolio), "project_scope"),
    "portfolio.project_scope",
  )
  let currency = required_string(
    field(Json::object(portfolio), "currency"),
    "portfolio.currency",
  )
  let checks : Array[(String, String)] = [
    ("portfolio_source_id", portfolio_source_id),
    ("portfolio_portfolio_id", portfolio_id),
    ("portfolio_principal_id", principal_id),
    ("portfolio_project_scope", project_scope),
    ("portfolio_currency", currency),
  ]
  for check in checks {
    let key = check.0
    let expected = check.1
    if required_string(field(Json::object(config), key), key) != expected {
      raise fail("valuation map " + key + " differs from performance plan")
    }
  }
  let valuation = object(field(Json::object(config), "valuation"), "valuation")
  let source_table = required_string(
    field(Json::object(valuation), "source_table"),
    "valuation.source_table",
  )
  let source_id = required_string(
    field(Json::object(valuation), "source_id"),
    "valuation.source_id",
  )
  let valuation_id = required_string(
    field(Json::object(valuation), "valuation_id"),
    "valuation.valuation_id",
  )
  if source_id != valuation_id {
    raise fail("valuation.source_id must equal valuation_id")
  }
  let event_id = required_string(
    field(Json::object(valuation), "event_id"),
    "valuation.event_id",
  )
  let event_type = required_string(
    field(Json::object(valuation), "event_type"),
    "valuation.event_type",
  )
  let scope = required_string(
    field(Json::object(valuation), "scope"),
    "valuation.scope",
  )
  if scope != project_scope {
    raise fail(
      "valuation.scope differs from performance portfolio project_scope",
    )
  }
  let investment_account = required_string(
    field(Json::object(valuation), "investment_account"),
    "valuation.investment_account",
  )
  let gain_account = required_string(
    field(Json::object(valuation), "gain_account"),
    "valuation.gain_account",
  )
  let loss_account = required_string(
    field(Json::object(valuation), "loss_account"),
    "valuation.loss_account",
  )
  let expected_gain_loss = integer(
    field(Json::object(valuation), "expected_gain_loss_minor"),
    "expected_gain_loss_minor",
    None,
  )
  let expected_amount = integer(
    field(Json::object(valuation), "expected_amount_minor"),
    "expected_amount_minor",
    Some(1L),
  )
  let absolute_gain = if expected_gain_loss < 0L {
    0L - expected_gain_loss
  } else {
    expected_gain_loss
  }
  if absolute_gain != expected_amount {
    raise fail("expected_amount_minor must equal absolute gain/loss")
  }
  let expected_journal_id = "investment/" +
    valuation_id +
    (if expected_gain_loss > 0L { "/gain" } else { "/loss" })
  let journal_id = required_string(
    field(Json::object(valuation), "journal_id"),
    "valuation.journal_id",
  )
  if journal_id != expected_journal_id {
    raise fail("valuation.journal_id does not match gain/loss direction")
  }
  let valuation_output = Json::object({
    "source_table": Json::string(source_table),
    "source_id": Json::string(source_id),
    "valuation_id": Json::string(valuation_id),
    "event_id": Json::string(event_id),
    "event_type": Json::string(event_type),
    "scope": Json::string(scope),
    "investment_account": Json::string(investment_account),
    "gain_account": Json::string(gain_account),
    "loss_account": Json::string(loss_account),
    "expected_gain_loss_minor": Json::number(
      expected_gain_loss.to_double(),
      repr=expected_gain_loss.to_string(),
    ),
    "expected_amount_minor": Json::number(
      expected_amount.to_double(),
      repr=expected_amount.to_string(),
    ),
    "journal_id": Json::string(journal_id),
    "principal_id": Json::string(principal_id),
    "currency": Json::string(currency),
  })
  let report = Json::object({
    "format": Json::string("moonproj.erp.investment-valuation-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "portfolio": Json::object(portfolio),
    "valuation": valuation_output,
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise InvestmentValuationPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "valuation_id": Json::string(valuation_id),
      "amount_minor": Json::number(
        expected_amount.to_double(),
        repr=expected_amount.to_string(),
      ),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: investment_valuation_plan <performance-plan.json> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    InvestmentValuationPlanError::InvalidInput(message) => {
      println("investment valuation plan failed: " + message)
      @sys.exit(1)
    }
    InvestmentValuationPlanError::Io(_) => {
      println("investment valuation plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
