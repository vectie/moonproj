///|
pub(all) suberror SalesCohortPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SalesCohortPlanError {
  SalesCohortPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SalesCohortPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SalesCohortPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SalesCohortPlanError {
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
) -> String raise SalesCohortPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_bool(value : Json, key : String) -> Bool raise SalesCohortPlanError {
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
) -> Int64 raise SalesCohortPlanError {
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
) -> Unit raise SalesCohortPlanError {
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
fn source(
  value : Map[String, Json],
  path : String,
) -> (String, String) raise SalesCohortPlanError {
  (
    required_string(
      value.get("source_table").unwrap_or(Json::null()),
      path + ".source_table",
    ),
    required_string(
      value.get("source_id").unwrap_or(Json::null()),
      path + ".source_id",
    ),
  )
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise SalesCohortPlanError {
  let config_value = read_json(mapping_path)
  reject_secrets(config_value, "mapping")
  let config = object(config_value, "mapping")
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.sales-cohort-map.v1" ||
    !required_bool(field(Json::object(config), "reviewed"), "reviewed") {
    raise fail("sales map is not reviewed")
  }
  let snapshot = required_string(
    field(Json::object(config), "source_snapshot_id"),
    "source_snapshot_id",
  )
  let mapping_version = required_string(
    field(Json::object(config), "mapping_version"),
    "mapping_version",
  )
  let run_id = required_string(field(Json::object(config), "run_id"), "run_id")
  let customer = object(field(Json::object(config), "customer"), "customer")
  let subscription = object(
    field(Json::object(config), "subscription"),
    "subscription",
  )
  let agreement = object(field(Json::object(config), "agreement"), "agreement")
  let mortgage = object(field(Json::object(config), "mortgage"), "mortgage")
  let refund = object(field(Json::object(config), "refund"), "refund")
  let revenue = object(field(Json::object(config), "revenue"), "revenue")
  if required_string(
      field(Json::object(customer), "expected_state"),
      "customer.expected_state",
    ) !=
    "active" {
    raise fail("customer.expected_state must be active")
  }
  if required_string(
      field(Json::object(subscription), "expected_state"),
      "subscription.expected_state",
    ) !=
    "converted" {
    raise fail("subscription.expected_state must be converted")
  }
  let subscription_amount = integer(
    field(Json::object(subscription), "amount_minor"),
    "subscription.amount_minor",
    1L,
  )
  let subscription_currency = required_string(
    field(Json::object(subscription), "currency"),
    "subscription.currency",
  )
  if required_string(
      field(Json::object(agreement), "expected_state"),
      "agreement.expected_state",
    ) !=
    "fulfilled" {
    raise fail("agreement.expected_state must be fulfilled")
  }
  let agreement_amount = integer(
    field(Json::object(agreement), "amount_minor"),
    "agreement.amount_minor",
    1L,
  )
  let agreement_currency = required_string(
    field(Json::object(agreement), "currency"),
    "agreement.currency",
  )
  if agreement_amount != subscription_amount ||
    agreement_currency != subscription_currency {
    raise fail("agreement amount/currency differs from subscription")
  }
  let receivable_id = required_string(
    field(Json::object(agreement), "receivable_id"),
    "agreement.receivable_id",
  )
  if required_string(
      field(Json::object(mortgage), "expected_state"),
      "mortgage.expected_state",
    ) !=
    "released" {
    raise fail("mortgage.expected_state must be released")
  }
  let loan_amount = integer(
    field(Json::object(mortgage), "loan_amount_minor"),
    "mortgage.loan_amount_minor",
    1L,
  )
  if loan_amount > agreement_amount {
    raise fail("mortgage.loan_amount_minor exceeds agreement amount")
  }
  let annual_rate = integer(
    field(Json::object(mortgage), "annual_rate_bps"),
    "mortgage.annual_rate_bps",
    0L,
  )
  if annual_rate > 10000L {
    raise fail("mortgage.annual_rate_bps exceeds 10000")
  }
  if required_string(
      field(Json::object(refund), "expected_state"),
      "refund.expected_state",
    ) !=
    "paid" {
    raise fail("refund.expected_state must be paid")
  }
  let refund_amount = integer(
    field(Json::object(refund), "amount_minor"),
    "refund.amount_minor",
    1L,
  )
  if refund_amount > agreement_amount {
    raise fail("refund.amount_minor exceeds agreement amount")
  }
  if required_string(
      field(Json::object(revenue), "evidence_state"),
      "revenue.evidence_state",
    ) !=
    "source_evidence_only" {
    raise fail("revenue must remain source_evidence_only")
  }
  let revenue_amount = integer(
    field(Json::object(revenue), "amount_minor"),
    "revenue.amount_minor",
    1L,
  )
  let revenue_currency = required_string(
    field(Json::object(revenue), "currency"),
    "revenue.currency",
  )
  if revenue_amount != agreement_amount ||
    revenue_currency != agreement_currency {
    raise fail("revenue amount/currency differs from agreement")
  }
  let agreement_id = required_string(
    field(Json::object(agreement), "agreement_id"),
    "agreement.agreement_id",
  )
  if required_string(
      field(Json::object(revenue), "contract_code"),
      "revenue.contract_code",
    ) !=
    agreement_id {
    raise fail("revenue.contract_code does not identify agreement")
  }
  let customer_source = source(customer, "customer")
  let subscription_source = source(subscription, "subscription")
  let agreement_source = source(agreement, "agreement")
  let mortgage_source = source(mortgage, "mortgage")
  let refund_source = source(refund, "refund")
  let revenue_source = source(revenue, "revenue")
  let report = Json::object({
    "format": Json::string("moonproj.erp.sales-cohort-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(snapshot),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "customer": Json::object({
      "source_table": Json::string(customer_source.0),
      "source_id": Json::string(customer_source.1),
      "customer_id": Json::string(
        required_string(
          field(Json::object(customer), "customer_id"),
          "customer.customer_id",
        ),
      ),
      "principal_id": Json::string(
        required_string(
          field(Json::object(customer), "principal_id"),
          "customer.principal_id",
        ),
      ),
      "project_scope": Json::string(
        required_string(
          field(Json::object(customer), "project_scope"),
          "customer.project_scope",
        ),
      ),
      "customer_code": Json::string(
        required_string(
          field(Json::object(customer), "customer_code"),
          "customer.customer_code",
        ),
      ),
      "name": Json::string(
        required_string(field(Json::object(customer), "name"), "customer.name"),
      ),
      "contact_reference": Json::string(
        required_string(
          field(Json::object(customer), "contact_reference"),
          "customer.contact_reference",
        ),
      ),
    }),
    "subscription": Json::object({
      "source_table": Json::string(subscription_source.0),
      "source_id": Json::string(subscription_source.1),
      "subscription_id": Json::string(
        required_string(
          field(Json::object(subscription), "subscription_id"),
          "subscription.subscription_id",
        ),
      ),
      "unit_reference": Json::string(
        required_string(
          field(Json::object(subscription), "unit_reference"),
          "subscription.unit_reference",
        ),
      ),
      "amount_minor": Json::number(
        subscription_amount.to_double(),
        repr=subscription_amount.to_string(),
      ),
      "currency": Json::string(subscription_currency),
    }),
    "agreement": Json::object({
      "source_table": Json::string(agreement_source.0),
      "source_id": Json::string(agreement_source.1),
      "agreement_id": Json::string(agreement_id),
      "receivable_id": Json::string(receivable_id),
      "amount_minor": Json::number(
        agreement_amount.to_double(),
        repr=agreement_amount.to_string(),
      ),
      "currency": Json::string(agreement_currency),
    }),
    "mortgage": Json::object({
      "source_table": Json::string(mortgage_source.0),
      "source_id": Json::string(mortgage_source.1),
      "mortgage_id": Json::string(
        required_string(
          field(Json::object(mortgage), "mortgage_id"),
          "mortgage.mortgage_id",
        ),
      ),
      "bank_reference": Json::string(
        required_string(
          field(Json::object(mortgage), "bank_reference"),
          "mortgage.bank_reference",
        ),
      ),
      "loan_amount_minor": Json::number(
        loan_amount.to_double(),
        repr=loan_amount.to_string(),
      ),
      "annual_rate_bps": Json::number(
        annual_rate.to_double(),
        repr=annual_rate.to_string(),
      ),
    }),
    "refund": Json::object({
      "source_table": Json::string(refund_source.0),
      "source_id": Json::string(refund_source.1),
      "refund_id": Json::string(
        required_string(
          field(Json::object(refund), "refund_id"),
          "refund.refund_id",
        ),
      ),
      "reason": Json::string(
        required_string(field(Json::object(refund), "reason"), "refund.reason"),
      ),
      "amount_minor": Json::number(
        refund_amount.to_double(),
        repr=refund_amount.to_string(),
      ),
    }),
    "revenue": Json::object({
      "source_table": Json::string(revenue_source.0),
      "source_id": Json::string(revenue_source.1),
      "revenue_id": Json::string(
        required_string(
          field(Json::object(revenue), "revenue_id"),
          "revenue.revenue_id",
        ),
      ),
      "revenue_code": Json::string(
        required_string(
          field(Json::object(revenue), "revenue_code"),
          "revenue.revenue_code",
        ),
      ),
      "amount_minor": Json::number(
        revenue_amount.to_double(),
        repr=revenue_amount.to_string(),
      ),
      "currency": Json::string(revenue_currency),
      "status": Json::string(
        required_string(
          field(Json::object(revenue), "status"),
          "revenue.status",
        ),
      ),
      "contract_code": Json::string(agreement_id),
      "evidence_state": Json::string("source_evidence_only"),
    }),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise SalesCohortPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(7.0, repr="7"),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: sales_cohort_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    SalesCohortPlanError::InvalidInput(message) => {
      println("sales cohort plan failed: " + message)
      @sys.exit(1)
    }
    SalesCohortPlanError::Io(_) => {
      println("sales cohort plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
