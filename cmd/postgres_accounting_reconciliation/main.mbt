///|
/// Native PostgreSQL accounting-link reconciliation verifier.
///
/// The report proves source identity, principal, amount, currency, and journal
/// continuity for a reviewed cohort. It never posts a journal, releases cash,
/// or authorizes a period close.
pub(all) suberror PostgresAccountingReconciliationError {
  InvalidInput(String)
  Io(@fs.IOError)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
struct DomainItem {
  source_table : String
  source_id : String
  target_type : String
  candidate : Json
}

///|
struct PlanItem {
  source_table : String
  source_id : String
  disposition : String
  candidate : Json
}

///|
struct LinkItem {
  source_table : String
  source_id : String
  event_id : String
  source_type : String
  durable_source_id : String
  journal_id : String
  principal_id : String
}

///|
struct Receipt {
  source_snapshot_id : String
  mapping_version : String
  items : Array[LinkItem]
}

///|
fn fail(message : String) -> PostgresAccountingReconciliationError {
  PostgresAccountingReconciliationError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresAccountingReconciliationError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresAccountingReconciliationError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresAccountingReconciliationError {
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
) -> Json raise PostgresAccountingReconciliationError {
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
) -> String raise PostgresAccountingReconciliationError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise PostgresAccountingReconciliationError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
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
fn source_key(table : String, id : String) -> String {
  table + "\u{1f}" + id
}

///|
fn load_domain(
  path : String,
) -> Array[DomainItem] raise PostgresAccountingReconciliationError {
  let root = object(read_json(path), "domain_receipt")
  if required_string(root, "format", "domain_receipt") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected domain promotion format")
  }
  let values = required_array(root, "accepted_items", "domain_receipt")
  let result : Array[DomainItem] = []
  for index in 0..<values.length() {
    let path = "domain_receipt.accepted_items[" + index.to_string() + "]"
    let item = object(values[index], path)
    let candidate = required(item, "target_candidate", path)
    match candidate {
      Object(_) => ()
      _ => raise fail("domain target_candidate is not an object at " + path)
    }
    result.push({
      source_table: required_string(item, "source_table", path),
      source_id: required_string(item, "source_id", path),
      target_type: required_string(item, "target_type", path),
      candidate,
    })
  }
  result
}

///|
fn load_plan(
  path : String,
) -> Array[PlanItem] raise PostgresAccountingReconciliationError {
  let root = object(read_json(path), "accounting_plan")
  if required_string(root, "format", "accounting_plan") !=
    "moonproj.erp.accounting-link-plan.v1" {
    raise fail("unexpected accounting-link plan format")
  }
  let values = required_array(root, "items", "accounting_plan")
  let result : Array[PlanItem] = []
  for index in 0..<values.length() {
    let path = "accounting_plan.items[" + index.to_string() + "]"
    let item = object(values[index], path)
    let candidate = required(item, "target_candidate", path)
    match candidate {
      Object(_) => ()
      _ => raise fail("accounting target_candidate is not an object at " + path)
    }
    result.push({
      source_table: required_string(item, "source_table", path),
      source_id: required_string(item, "source_id", path),
      disposition: required_string(item, "disposition", path),
      candidate,
    })
  }
  result
}

///|
fn load_receipt(
  path : String,
) -> Receipt raise PostgresAccountingReconciliationError {
  let root = object(read_json(path), "accounting_receipt")
  if required_string(root, "format", "accounting_receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  if required_string(root, "state", "accounting_receipt") !=
    "validated_accounting_links" {
    raise fail("accounting-link receipt is not native-validated")
  }
  let values = required_array(root, "accepted_items", "accounting_receipt")
  if values.is_empty() {
    raise fail("accounting reconciliation has no accepted items")
  }
  let result : Array[LinkItem] = []
  for index in 0..<values.length() {
    let path = "accounting_receipt.accepted_items[" + index.to_string() + "]"
    let item = object(values[index], path)
    result.push({
      source_table: required_string(item, "source_table", path),
      source_id: required_string(item, "source_id", path),
      event_id: required_string(item, "event_id", path),
      source_type: required_string(item, "source_type", path),
      durable_source_id: required_string(item, "source_id", path),
      journal_id: required_string(item, "journal_id", path),
      principal_id: required_string(item, "principal_id", path),
    })
  }
  {
    source_snapshot_id: required_string(
      root, "source_snapshot_id", "accounting_receipt",
    ),
    mapping_version: required_string(
      root, "mapping_version", "accounting_receipt",
    ),
    items: result,
  }
}

///|
fn find_domain(
  values : Array[DomainItem],
  table : String,
  id : String,
) -> DomainItem? {
  for value in values {
    if value.source_table == table && value.source_id == id {
      return Some(value)
    }
  }
  None
}

///|
fn find_receipt(
  values : Array[LinkItem],
  table : String,
  id : String,
) -> LinkItem? {
  for value in values {
    if value.source_table == table && value.source_id == id {
      return Some(value)
    }
  }
  None
}

///|
fn decode_hex(
  value : String,
) -> String raise PostgresAccountingReconciliationError {
  if value.length() % 2 != 0 {
    raise fail("invalid PostgreSQL hexadecimal field")
  }
  let bytes : FixedArray[Byte] = FixedArray::make(value.length() / 2, 0)
  fn digit(char : Char) -> Int? {
    if char >= '0' && char <= '9' {
      Some(char.to_int() - '0'.to_int())
    } else if char >= 'a' && char <= 'f' {
      Some(char.to_int() - 'a'.to_int() + 10)
    } else if char >= 'A' && char <= 'F' {
      Some(char.to_int() - 'A'.to_int() + 10)
    } else {
      None
    }
  }
  for index in 0..<(value.length() / 2) {
    let high = match value.get_char(index * 2) {
      Some(char) =>
        match digit(char) {
          Some(value) => value
          None => raise fail("invalid PostgreSQL hexadecimal field")
        }
      None => raise fail("invalid PostgreSQL hexadecimal field")
    }
    let low = match value.get_char(index * 2 + 1) {
      Some(char) =>
        match digit(char) {
          Some(value) => value
          None => raise fail("invalid PostgreSQL hexadecimal field")
        }
      None => raise fail("invalid PostgreSQL hexadecimal field")
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
fn fields(
  line : String,
  expected : Int,
) -> Array[String] raise PostgresAccountingReconciliationError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL accounting-link row")
  }
  values
}

///|
async fn durable_links(
  connection : @postgres.Connection,
  receipt : Receipt,
) -> Array[LinkItem] raise PostgresAccountingReconciliationError {
  let event_ids : Array[String] = []
  for item in receipt.items {
    event_ids.push(@postgres.sql_literal(item.event_id))
  }
  let output = @postgres.run_sql(
    connection,
    "SELECT encode(convert_to(event_id, 'UTF8'), 'hex'), encode(convert_to(source_type, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex'), encode(convert_to(journal_id, 'UTF8'), 'hex'), encode(convert_to(principal_id, 'UTF8'), 'hex') FROM company_accounting_event_link WHERE event_id IN (" +
    event_ids.join(", ") +
    ") ORDER BY event_id",
  ) catch {
    error => raise PostgresAccountingReconciliationError::Database(error)
  }
  let result : Array[LinkItem] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 5)
      result.push({
        source_table: "",
        source_id: "",
        event_id: decode_hex(row[0]),
        source_type: decode_hex(row[1]),
        durable_source_id: decode_hex(row[2]),
        journal_id: decode_hex(row[3]),
        principal_id: decode_hex(row[4]),
      })
    }
  }
  result
}

///|
fn find_durable(values : Array[LinkItem], event_id : String) -> LinkItem? {
  for value in values {
    if value.event_id == event_id {
      return Some(value)
    }
  }
  None
}

///|
fn amount_candidate(candidate : Json, target_type : String) -> Double? {
  if target_type == "payment_application" {
    match json_field(candidate, "application") {
      Some(application) => json_number(application, "amount_minor")
      None => None
    }
  } else {
    match json_number(candidate, "amount_minor") {
      Some(value) => Some(value)
      None => {
        let fields = [
          "completed_value_minor", "tax_amount_minor", "reported_tax_amount_minor",
          "notional_minor", "actual_amount_minor",
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
  }
}

///|
async fn reconcile(
  domain_path : String,
  plan_path : String,
  receipt_path : String,
  output_path : String,
  schema_path : String,
  connection : @postgres.Connection,
) -> Json raise PostgresAccountingReconciliationError {
  let domain = load_domain(domain_path)
  let plan = load_plan(plan_path)
  let receipt = load_receipt(receipt_path)
  let _ = @postgres.run_file(connection, schema_path) catch {
    error => raise PostgresAccountingReconciliationError::Database(error)
  }
  if plan.is_empty() || receipt.items.is_empty() {
    raise fail("accounting reconciliation has no accepted items")
  }
  for item in plan {
    if item.disposition != "ready_for_domain_import" {
      raise fail("accounting plan contains quarantined items")
    }
  }
  let durable = durable_links(connection, receipt)
  let checks : Array[Json] = []
  for item in plan {
    let domain_item = match
      find_domain(domain, item.source_table, item.source_id) {
      Some(value) => value
      None =>
        raise fail(
          "missing domain identity at " +
          source_key(item.source_table, item.source_id),
        )
    }
    let receipt_item = match
      find_receipt(receipt.items, item.source_table, item.source_id) {
      Some(value) => value
      None =>
        raise fail(
          "missing accounting receipt identity at " +
          source_key(item.source_table, item.source_id),
        )
    }
    let domain_amount = match
      amount_candidate(domain_item.candidate, domain_item.target_type) {
      Some(value) => value
      None =>
        raise fail(
          "missing domain amount at " +
          source_key(item.source_table, item.source_id),
        )
    }
    let journal = match json_field(item.candidate, "journal") {
      Some(Object(_)) => json_field(item.candidate, "journal").unwrap()
      _ =>
        raise fail(
          "missing journal at " + source_key(item.source_table, item.source_id),
        )
    }
    let plan_amount = match json_number(journal, "amount_minor") {
      Some(value) => value
      None =>
        raise fail(
          "missing journal amount at " +
          source_key(item.source_table, item.source_id),
        )
    }
    if plan_amount != domain_amount {
      raise fail(
        "amount_minor mismatch at " +
        source_key(item.source_table, item.source_id),
      )
    }
    let domain_currency = json_text(domain_item.candidate, "currency")
    let plan_currency = json_text(journal, "currency")
    if domain_currency.is_empty() || plan_currency != domain_currency {
      raise fail(
        "currency mismatch at " + source_key(item.source_table, item.source_id),
      )
    }
    let domain_principal = json_text(domain_item.candidate, "principal_id")
    let plan_principal = json_text(item.candidate, "principal_id")
    if plan_principal != domain_principal {
      raise fail(
        "principal_id mismatch at " +
        source_key(item.source_table, item.source_id),
      )
    }
    let durable_item = match find_durable(durable, receipt_item.event_id) {
      Some(value) => value
      None =>
        raise fail(
          "durable PostgreSQL accounting link missing at " +
          receipt_item.event_id,
        )
    }
    if durable_item.source_type != receipt_item.source_type ||
      durable_item.durable_source_id != receipt_item.source_id ||
      durable_item.journal_id != receipt_item.journal_id ||
      durable_item.principal_id != receipt_item.principal_id {
      raise fail(
        "durable PostgreSQL accounting link mismatch at " +
        receipt_item.event_id,
      )
    }
    checks.push(
      Json::object({
        "source_table": Json::string(item.source_table),
        "source_id": Json::string(item.source_id),
        "event_id": Json::string(receipt_item.event_id),
        "journal_id": Json::string(receipt_item.journal_id),
        "principal_id": Json::string(receipt_item.principal_id),
        "amount_minor": Json::number(plan_amount),
        "currency": Json::string(plan_currency),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.accounting-reconciliation.v1"),
    "backend": Json::string("postgres"),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string("reconciled"),
    "integrity": Json::string("ok"),
    "link_count": Json::number(checks.length().to_double()),
    "checks": Json::array(checks),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise PostgresAccountingReconciliationError::Io(error)
  }
  report
}

///|
fn option(args : Array[String], name : String) -> String? {
  for index in 5..<args.length() {
    if args[index] == name {
      return args.get(index + 1)
    }
  }
  None
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 5 {
    println(
      "usage: postgres_accounting_reconciliation <domain_receipt> <accounting_plan> <accounting_receipt> <output> [--schema path] [--psql path] [--host host] [--port port] [--user user] [--database database]",
    )
    @sys.exit(2)
  }
  let connection = @postgres.connection_from_env().with_overrides(
    psql=option(args, "--psql"),
    host=option(args, "--host"),
    port=option(args, "--port"),
    user=option(args, "--user"),
    database=Some(option(args, "--database").unwrap_or("moonproj")),
  )
  let report = reconcile(
    args[1],
    args[2],
    args[3],
    args[4],
    option(args, "--schema").unwrap_or("scripts/postgres_target_schema.sql"),
    connection,
  ) catch {
    error => {
      println(
        "company PostgreSQL accounting reconciliation failed: \{to_repr(error)}",
      )
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
