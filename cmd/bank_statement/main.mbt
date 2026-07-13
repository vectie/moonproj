///|
pub(all) suberror BankStatementPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Statement(@treasury.StatementError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise BankStatementPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise BankStatementPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise BankStatementPromotionError {
  match value {
    Object(value) => value
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise BankStatementPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise BankStatementPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise BankStatementPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise BankStatementPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise BankStatementPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn direction(
  value : String,
) -> @treasury.CashDirection raise BankStatementPromotionError {
  match value {
    "inflow" => @treasury.CashDirection::Inflow
    "outflow" => @treasury.CashDirection::Outflow
    _ => raise BankStatementPromotionError::InvalidInput
  }
}

///|
fn direction_name(value : @treasury.CashDirection) -> String {
  match value {
    @treasury.CashDirection::Inflow => "inflow"
    @treasury.CashDirection::Outflow => "outflow"
  }
}

///|
fn grant(principal_id : String, scope : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "bank-statement-migration/import",
    principal_id,
    actor_id: "migration",
    capability: "treasury:statement:import",
    scope,
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise BankStatementPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.bank-statement-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise BankStatementPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for statement_value in required_array(root, "statements") {
    let statement_obj = object(statement_value)
    let source_table = required_string(statement_obj, "source_table")
    let source_id = required_string(statement_obj, "source_id")
    let statement_id = required_string(statement_obj, "statement_id")
    let account_id = required_string(statement_obj, "account_id")
    let principal_id = required_string(statement_obj, "principal_id")
    let project_scope = required_string(statement_obj, "project_scope")
    let period = required_string(statement_obj, "period")
    let currency = required_string(statement_obj, "currency")
    let opening_balance_minor = required_int64(
      statement_obj, "opening_balance_minor",
    )
    let closing_balance_minor = required_int64(
      statement_obj, "closing_balance_minor",
    )
    let lines : Array[@treasury.BankStatementLine] = []
    let line_candidates : Array[Json] = []
    for line_value in required_array(statement_obj, "lines") {
      let line_obj = object(line_value)
      let line_id = required_string(line_obj, "line_id")
      let external_reference = required_string(line_obj, "external_reference")
      let booked_at = required_string(line_obj, "booked_at")
      let amount_minor = required_int64(line_obj, "amount_minor")
      let line_direction = direction(required_string(line_obj, "direction"))
      let amount = @finance.Money::new(minor=amount_minor, currency~) catch {
        error => raise BankStatementPromotionError::Money(error)
      }
      lines.push({
        line_id,
        account_id,
        principal_id,
        project_scope,
        external_reference,
        booked_at,
        amount,
        direction: line_direction,
      })
      line_candidates.push(
        Json::object({
          "line_id": Json::string(line_id),
          "external_reference": Json::string(external_reference),
          "booked_at": Json::string(booked_at),
          "amount_minor": number(amount_minor),
          "direction": Json::string(direction_name(line_direction)),
        }),
      )
    }
    let opening_balance = @finance.Money::new(
      minor=opening_balance_minor,
      currency~,
    ) catch {
      error => raise BankStatementPromotionError::Money(error)
    }
    let closing_balance = @finance.Money::new(
      minor=closing_balance_minor,
      currency~,
    ) catch {
      error => raise BankStatementPromotionError::Money(error)
    }
    let statement = @treasury.BankStatement::from_statement(
      statement_id~,
      account_id~,
      principal_id~,
      project_scope~,
      period~,
      opening_balance~,
      closing_balance~,
      lines~,
      actor_id="migration",
      grant=grant(principal_id, project_scope),
    ) catch {
      error => raise BankStatementPromotionError::Statement(error)
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("bank_statement"),
        "target_id": Json::string(statement.statement_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "statement_id": Json::string(statement.statement_id),
          "account_id": Json::string(statement.account_id),
          "principal_id": Json::string(statement.principal_id),
          "project_scope": Json::string(statement.project_scope),
          "period": Json::string(statement.period),
          "opening_balance_minor": number(statement.opening_balance.minor),
          "closing_balance_minor": number(statement.closing_balance.minor),
          "currency": Json::string(statement.opening_balance.currency),
          "line_count": number(statement.lines.length().to_int64()),
          "lines": Json::array(line_candidates),
          "state": Json::string("imported"),
          "cash_released": Json::boolean(false),
          "reconciled": Json::boolean(false),
          "ledger_reconciled": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise BankStatementPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("bank-statement-v1"),
    "accepted_items": Json::array(accepted),
    "statement_count": number(accepted.length().to_int64()),
    "bank_adapter_called": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "reconciled": Json::boolean(false),
    "ledger_reconciled": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise BankStatementPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: bank_statement <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      BankStatementPromotionError::InvalidInput => {
        println("bank statement promotion failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      BankStatementPromotionError::Io(_) => {
        println("bank statement promotion failed: filesystem error")
        @sys.exit(1)
      }
      BankStatementPromotionError::Money(_) => {
        println("bank statement promotion failed: money validation")
        @sys.exit(1)
      }
      BankStatementPromotionError::Statement(_) => {
        println("bank statement promotion failed: statement validation")
        @sys.exit(1)
      }
    }
  }
}
