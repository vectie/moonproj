///|
pub(all) suberror TaxAccountingPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> TaxAccountingPlanError {
  TaxAccountingPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TaxAccountingPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaxAccountingPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TaxAccountingPlanError {
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
) -> String raise TaxAccountingPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_bool(
  value : Json,
  key : String,
) -> Bool raise TaxAccountingPlanError {
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
  minimum : Int64,
) -> Int64 raise TaxAccountingPlanError {
  let result = match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), 0L)
    _ => raise fail(key + " must be an integer >= " + minimum.to_string())
  }
  if result < minimum {
    raise fail(key + " must be an integer >= " + minimum.to_string())
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
) -> Unit raise TaxAccountingPlanError {
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
fn map_string(
  mapping : Map[String, Json],
  key : String,
  path : String,
) -> String raise TaxAccountingPlanError {
  required_string(mapping.get(key).unwrap_or(Json::null()), path + "." + key)
}

///|
fn run(
  tax_plan_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise TaxAccountingPlanError {
  let tax_plan = object(read_json(tax_plan_path), "tax plan")
  let config_value = read_json(mapping_path)
  reject_secrets(config_value, "mapping")
  let config = object(config_value, "mapping")
  if required_string(field(Json::object(tax_plan), "format"), "format") !=
    "moonproj.erp.tax-filing-plan.v1" ||
    !required_bool(field(Json::object(tax_plan), "reviewed"), "reviewed") {
    raise fail("tax plan is not reviewed")
  }
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.tax-accounting-map.v1" ||
    !required_bool(field(Json::object(config), "reviewed"), "reviewed") {
    raise fail("tax accounting map is not reviewed")
  }
  let source_snapshot_id = required_string(
    field(Json::object(tax_plan), "source_snapshot_id"),
    "source_snapshot_id",
  )
  if required_string(
      field(Json::object(config), "source_snapshot_id"),
      "source_snapshot_id",
    ) !=
    source_snapshot_id {
    raise fail("tax accounting map source snapshot differs from tax plan")
  }
  let mappings = object(
    field(Json::object(config), "accounting_by_source"),
    "accounting_by_source",
  )
  let filings = match field(Json::object(tax_plan), "filings") {
    Array(values) if !values.is_empty() => values
    _ => raise fail("tax plan has no filings")
  }
  let items : Array[Json] = []
  let seen : Array[String] = []
  for index in 0..<filings.length() {
    let filing = object(filings[index], "filing")
    let tax_id = required_string(
      field(Json::object(filing), "tax_id"),
      "tax_id",
    )
    if seen.contains(tax_id) {
      raise fail("duplicate tax_id: " + tax_id)
    }
    seen.push(tax_id)
    let mapping = object(
      mappings.get("tax_obligation:" + tax_id).unwrap_or(Json::null()),
      "accounting mapping",
    ) catch {
      TaxAccountingPlanError::InvalidInput(_) =>
        raise fail("missing accounting map for tax_obligation:" + tax_id)
      TaxAccountingPlanError::Io(_) =>
        raise fail("missing accounting map for tax_obligation:" + tax_id)
    }
    let principal_id = required_string(
      field(Json::object(filing), "principal_id"),
      "principal_id",
    )
    let project_scope = required_string(
      field(Json::object(filing), "project_scope"),
      "project_scope",
    )
    let currency = required_string(
      field(Json::object(filing), "currency"),
      "currency",
    )
    let base = integer(
      field(Json::object(filing), "base_amount_minor"),
      "base_amount_minor",
      1L,
    )
    let rate = integer(
      field(Json::object(filing), "tax_rate_bps"),
      "tax_rate_bps",
      0L,
    )
    let amount = (base * rate + 5000L) / 10000L
    let required_mapping = [
      "event_id", "event_type", "tax_expense_account", "tax_payable_account", "journal_id",
      "description", "scope", "principal_id", "currency",
    ]
    for key in required_mapping {
      if field(Json::object(mapping), key) is Null ||
        !nonempty(field(Json::object(mapping), key)) {
        raise fail("tax_obligation:" + tax_id + " missing " + key)
      }
    }
    if field(Json::object(mapping), "amount_minor") is Null {
      raise fail("tax_obligation:" + tax_id + " missing amount_minor")
    }
    if text(field(Json::object(mapping), "principal_id")) != principal_id ||
      text(field(Json::object(mapping), "scope")) != project_scope ||
      text(field(Json::object(mapping), "currency")) != currency ||
      integer(field(Json::object(mapping), "amount_minor"), "amount_minor", 0L) !=
      amount {
      raise fail("tax accounting identity/amount mismatch: " + tax_id)
    }
    if text(field(Json::object(mapping), "journal_id")) !=
      "tax/" + tax_id + "/recognition" {
      raise fail("tax journal identity mismatch: " + tax_id)
    }
    let accounting = Json::object({
      "event_id": Json::string(
        map_string(mapping, "event_id", "tax accounting"),
      ),
      "event_type": Json::string(
        map_string(mapping, "event_type", "tax accounting"),
      ),
      "journal_id": Json::string(
        map_string(mapping, "journal_id", "tax accounting"),
      ),
      "description": Json::string(
        map_string(mapping, "description", "tax accounting"),
      ),
      "scope": Json::string(project_scope),
      "tax_expense_account": Json::string(
        map_string(mapping, "tax_expense_account", "tax accounting"),
      ),
      "tax_payable_account": Json::string(
        map_string(mapping, "tax_payable_account", "tax accounting"),
      ),
      "debit_account": Json::string(
        map_string(mapping, "debit_account", "tax accounting"),
      ),
      "credit_account": Json::string(
        map_string(mapping, "credit_account", "tax accounting"),
      ),
      "amount_minor": Json::number(amount.to_double(), repr=amount.to_string()),
    })
    items.push(
      Json::object({
        "source_table": Json::string("tax_obligation"),
        "source_id": Json::string(tax_id),
        "tax_id": Json::string(tax_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "source_reference": Json::string(
          required_string(
            field(Json::object(filing), "source_reference"),
            "source_reference",
          ),
        ),
        "jurisdiction": Json::string(
          required_string(
            field(Json::object(filing), "jurisdiction"),
            "jurisdiction",
          ),
        ),
        "category": Json::string(
          required_string(field(Json::object(filing), "category"), "category"),
        ),
        "currency": Json::string(currency),
        "base_amount_minor": Json::number(
          base.to_double(),
          repr=base.to_string(),
        ),
        "tax_rate_bps": Json::number(rate.to_double(), repr=rate.to_string()),
        "withholding_rate_bps": Json::number(
          integer(
            field(Json::object(filing), "withholding_rate_bps"),
            "withholding_rate_bps",
            0L,
          ).to_double(),
          repr=integer(
            field(Json::object(filing), "withholding_rate_bps"),
            "withholding_rate_bps",
            0L,
          ).to_string(),
        ),
        "accounting": accounting,
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.tax-accounting-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(
      required_string(
        field(Json::object(config), "mapping_version"),
        "mapping_version",
      ),
    ),
    "run_id": Json::string(
      required_string(field(Json::object(config), "run_id"), "run_id"),
    ),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TaxAccountingPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
    }).stringify(),
  )
}

///|
fn nonempty(value : Json) -> Bool {
  match value {
    String(value) => !value.trim().is_empty()
    _ => false
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: tax_accounting_plan <tax-plan.json> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    TaxAccountingPlanError::InvalidInput(message) => {
      println("tax accounting plan failed: " + message)
      @sys.exit(1)
    }
    TaxAccountingPlanError::Io(_) => {
      println("tax accounting plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
