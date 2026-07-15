///|
/// Build an explicit source-to-journal link plan from a domain receipt.
///
/// Only allow-listed target/source domains cross this boundary. The planner
/// never infers a journal or amount from source metadata; the native candidate
/// and reviewed mapping must agree before a link is accepted.
pub(all) suberror AccountingLinkPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> AccountingLinkPlanError {
  AccountingLinkPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AccountingLinkPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AccountingLinkPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AccountingLinkPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("JSON root is not an object: " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise AccountingLinkPlanError {
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
) -> String raise AccountingLinkPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn json_text(value : Json, key : String) -> String {
  match json_field(value, key) {
    Some(String(text)) => text
    Some(Number(number, ..)) => number.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => ""
  }
}

///|
fn parse_number(value : String) -> Double {
  if value.is_empty() {
    return 0.0
  }
  let mut sign = 1.0
  let mut index = 0
  match value.get_char(0) {
    Some('-') => {
      sign = -1.0
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut whole = 0.0
  let mut fraction = 0.0
  let mut divisor = 1.0
  let mut after_decimal = false
  while index < value.length() {
    let char = match value.get_char(index) {
      Some(value) => value
      None => return 0.0
    }
    if char == '.' {
      if after_decimal {
        return 0.0
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      let digit = (char.to_int() - '0'.to_int()).to_double()
      if after_decimal {
        divisor *= 10.0
        fraction += digit / divisor
      } else {
        whole = whole * 10.0 + digit
      }
    } else {
      return 0.0
    }
    index += 1
  }
  sign * (whole + fraction)
}

///|
fn json_number(value : Json, key : String) -> Double? {
  match json_field(value, key) {
    Some(Number(number, ..)) => Some(number)
    Some(String(text)) => Some(parse_number(text.trim().to_owned()))
    _ => None
  }
}

///|
fn json_present(value : Json, key : String) -> Bool {
  match json_field(value, key) {
    None | Some(Null) => false
    Some(String(text)) if text.is_empty() => false
    _ => true
  }
}

///|
fn json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (String(a), String(b)) => a == b
    (Number(a, ..), Number(b, ..)) => a == b
    (String(a), Number(b, ..)) => parse_number(a) == b
    (Number(a, ..), String(b)) => a == parse_number(b)
    (True, True) | (False, False) | (Null, Null) => true
    _ => false
  }
}

///|
fn supported_source_type(
  target_type : String,
  source_table : String,
) -> String? {
  match target_type {
    "commitment" => Some(source_table)
    "employee_advance" => Some("employee_advance")
    "employee_advance_offset" => Some("employee_advance_offset")
    "payment_application" => Some("payment_application")
    "settlement" => Some("settlement")
    "expense_claim" => Some("expense_claim")
    "delivery_progress" | "delivery_recognition" => Some("delivery_progress")
    "asset_depreciation" => Some("asset_depreciation")
    "receivable" => Some("receivable")
    "receivable_collection" => Some("receivable_collection")
    "payable" => Some("payable")
    "payable_payment" => Some("payable_payment")
    "tax_obligation" => Some("tax_obligation")
    "tax_filing" => Some("tax_filing")
    "financing_facility" => Some("financing_facility")
    "investment_position" => Some("investment_position")
    "investment_valuation" => Some("investment_valuation")
    "asset_disposal" => Some("asset_disposal")
    "cash_movement" => Some("cash_movement")
    "bank_statement" => Some("bank_statement")
    _ => None
  }
}

///|
fn target_type_supported(target_type : String) -> Bool {
  supported_source_type(target_type, "source") is Some(_)
}

///|
fn candidate_amount(candidate : Json, target_type : String) -> Double? {
  if target_type == "payment_application" {
    match json_field(candidate, "application") {
      Some(application) => json_number(application, "amount_minor")
      None => None
    }
  } else {
    let fields = [
      "amount_minor", "tax_amount_minor", "reported_tax_amount_minor", "notional_minor",
      "actual_amount_minor", "completed_value_minor",
    ]
    let mut result : Double? = None
    for field in fields {
      if result is None {
        result = json_number(candidate, field)
      }
    }
    result
  }
}

///|
fn add_reason(reasons : Array[String], reason : String) -> Unit {
  if !reasons.contains(reason) {
    reasons.push(reason)
  }
}

///|
fn sorted_reasons(reasons : Array[String]) -> Array[Json] {
  let values = reasons.copy()
  values.sort_by(fn(left, right) { left.compare(right) })
  values.map(fn(value) { Json::string(value) })
}

///|
fn source_sha256(snapshot_id : String) -> String {
  let parts = snapshot_id.split(":").to_array()
  if parts.is_empty() {
    snapshot_id
  } else {
    parts[parts.length() - 1].to_owned()
  }
}

///|
fn target_types(
  config : Map[String, Json],
) -> Array[String] raise AccountingLinkPlanError {
  match json_field(Json::object(config), "target_types") {
    None =>
      [
        "commitment", "employee_advance", "employee_advance_offset", "payment_application",
        "settlement", "expense_claim", "delivery_progress", "delivery_recognition",
        "asset_depreciation", "receivable", "receivable_collection", "payable", "payable_payment",
        "tax_obligation", "tax_filing", "financing_facility", "investment_position",
        "investment_valuation", "asset_disposal", "cash_movement", "bank_statement",
      ]
    Some(Array(values)) => {
      if values.is_empty() {
        raise fail("target_types must be a non-empty string array")
      }
      let result : Array[String] = []
      for value in values {
        match value {
          String(text) if !text.is_empty() && target_type_supported(text) =>
            result.push(text)
          _ =>
            raise fail(
              "target_types contains an unsupported or empty target type",
            )
        }
      }
      result
    }
    Some(_) => raise fail("target_types must be a non-empty string array")
  }
}

///|
fn mapping_for(
  mappings : Map[String, Json],
  base_key : String,
  target_type : String,
) -> Json {
  mappings
  .get(base_key + ":" + target_type)
  .unwrap_or(mappings.get(base_key).unwrap_or(Json::null()))
}

///|
fn mapping_missing(mapping : Json, field : String) -> Bool {
  !json_present(mapping, field)
}

///|
fn strict_candidate_field(
  reasons : Array[String],
  mapping : Json,
  candidate : Json,
  target_type : String,
  field : String,
) -> Unit {
  if !json_equal(
      json_field(mapping, field).unwrap_or(Json::null()),
      json_field(candidate, field).unwrap_or(Json::null()),
    ) {
    add_reason(reasons, target_type + "_" + field + "_mismatch")
  }
}

///|
fn run(
  domain_path : String,
  mapping_path : String,
  output_path : String,
) -> Json raise AccountingLinkPlanError {
  let receipt = object(read_json(domain_path), "domain_receipt")
  let config = object(read_json(mapping_path), "mapping")
  if required_string(receipt, "format", "domain_receipt") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected domain receipt format")
  }
  let accepted = match required(receipt, "accepted_items", "domain_receipt") {
    Array(values) => values
    _ => raise fail("domain receipt has no accepted items")
  }
  let mappings = match
    json_field(Json::object(config), "accounting_by_source") {
    Some(Object(values)) => values
    _ => raise fail("accounting_by_source must be an object")
  }
  let allowed = target_types(config)
  let items : Array[Json] = []
  for index in 0..<accepted.length() {
    let target_type = json_text(accepted[index], "target_type")
    if !allowed.contains(target_type) {
      continue
    }
    let source_table = json_text(accepted[index], "source_table")
    let source_id = json_text(accepted[index], "source_id")
    let key = source_table + ":" + source_id
    let candidate_value = json_field(accepted[index], "target_candidate").unwrap_or(
      Json::null(),
    )
    let candidate = match candidate_value {
      Object(_) => candidate_value
      _ => Json::object({})
    }
    let reasons : Array[String] = []
    match candidate_value {
      Object(_) => ()
      _ => add_reason(reasons, "domain_receipt_missing_candidate")
    }
    let mapping = mapping_for(mappings, key, target_type)
    match mapping {
      Object(_) => ()
      _ => add_reason(reasons, "missing_accounting_mapping")
    }
    let required_fields = [
      "event_id", "event_type", "journal_id", "description", "debit_account", "credit_account",
      "principal_id", "scope", "amount_minor", "currency",
    ]
    for field in required_fields {
      if mapping_missing(mapping, field) {
        add_reason(reasons, "missing_accounting_field:" + field)
      }
    }
    if json_text(mapping, "principal_id") !=
      json_text(candidate, "principal_id") {
      add_reason(reasons, "accounting_principal_mismatch")
    }
    let expected_amount = candidate_amount(candidate, target_type)
    match expected_amount {
      None => add_reason(reasons, "domain_candidate_missing_amount")
      Some(value) =>
        if json_number(mapping, "amount_minor") != Some(value) {
          add_reason(reasons, "accounting_amount_mismatch")
        }
    }
    let expected_currency = {
      let value = json_text(candidate, "currency")
      if value.is_empty() {
        json_text(candidate, "base_currency")
      } else {
        value
      }
    }
    if expected_currency.is_empty() {
      add_reason(reasons, "domain_candidate_missing_currency")
    }
    if json_text(mapping, "currency") != expected_currency {
      add_reason(reasons, "accounting_currency_mismatch")
    }
    if target_type == "investment_valuation" ||
      target_type == "tax_obligation" ||
      target_type == "financing_facility" {
      for
        field in [
          "event_id", "event_type", "journal_id", "debit_account", "credit_account",
          "scope",
        ] {
        strict_candidate_field(reasons, mapping, candidate, target_type, field)
      }
    }
    let source_type = supported_source_type(target_type, source_table).unwrap_or(
      source_table,
    )
    let target_candidate = Json::object({
      "source_target_type": Json::string(target_type),
      "event_id": json_field(mapping, "event_id").unwrap_or(Json::null()),
      "principal_id": json_field(mapping, "principal_id").unwrap_or(
        Json::null(),
      ),
      "source_type": Json::string(source_type),
      "source_id": Json::string(source_id),
      "event_type": json_field(mapping, "event_type").unwrap_or(Json::null()),
      "scope": json_field(mapping, "scope").unwrap_or(Json::null()),
      "journal": Json::object({
        "entry_id": json_field(mapping, "journal_id").unwrap_or(Json::null()),
        "description": json_field(mapping, "description").unwrap_or(
          Json::null(),
        ),
        "debit_account": json_field(mapping, "debit_account").unwrap_or(
          Json::null(),
        ),
        "credit_account": json_field(mapping, "credit_account").unwrap_or(
          Json::null(),
        ),
        "amount_minor": json_field(mapping, "amount_minor").unwrap_or(
          Json::null(),
        ),
        "currency": json_field(mapping, "currency").unwrap_or(Json::null()),
      }),
    })
    let mapped_event_id = json_text(mapping, "event_id")
    let target_id = if mapped_event_id.is_empty() {
      source_id
    } else {
      mapped_event_id
    }
    items.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("accounting_event_link"),
        "target_id": Json::string(target_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": Json::array(sorted_reasons(reasons)),
        "warnings": Json::array([
          Json::string(
            "this link validates an explicit journal; it does not post cash or infer accounting policy",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          target_candidate
        } else {
          Json::null()
        },
      }),
    )
  }
  if items.is_empty() {
    raise fail("domain receipt contains no supported accounting events to map")
  }
  let mut ready = 0
  for item in items {
    if json_text(item, "disposition") == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_snapshot_id = required_string(
    receipt, "source_snapshot_id", "domain_receipt",
  )
  let mapping_version = json_text(Json::object(config), "mapping_version")
  let report = Json::object({
    "format": Json::string("moonproj.erp.accounting-link-plan.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "source_sha256": Json::string(source_sha256(source_snapshot_id)),
    "mapping_version": Json::string(
      if mapping_version.is_empty() {
        "unversioned-accounting-map"
      } else {
        mapping_version
      },
    ),
    "summary": Json::object({
      "items": Json::number(items.length().to_double()),
      "ready": Json::number(ready.to_double()),
      "quarantined": Json::number((items.length() - ready).to_double()),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise AccountingLinkPlanError::Io(error)
  }
  report
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: accounting_link_plan <domain_receipt> <mapping> <output>")
    @sys.exit(2)
  }
  let report = run(args[1], args[2], args[3]) catch {
    error => {
      println("accounting-link plan failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
