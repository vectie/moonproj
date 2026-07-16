///|
pub(all) suberror SqliteAccountingReconciliationError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SqliteAccountingReconciliationError {
  SqliteAccountingReconciliationError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteAccountingReconciliationError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingReconciliationError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteAccountingReconciliationError {
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
) -> Json raise SqliteAccountingReconciliationError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise SqliteAccountingReconciliationError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise fail("expected string at " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise SqliteAccountingReconciliationError {
  let value = string(fields, key, path)
  if value.trim().is_empty() {
    raise fail("expected non-empty string at " + path + "." + key)
  }
  value
}

///|
fn array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise SqliteAccountingReconciliationError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn json_equal(left : Json, right : Json) -> Bool {
  left.stringify() == right.stringify()
}

///|
fn key(
  fields : Map[String, Json],
  path : String,
) -> String raise SqliteAccountingReconciliationError {
  required_string(fields, "source_table", path) +
  "\u{1f}" +
  required_string(fields, "source_id", path)
}

///|
fn decode_hex(
  value : String,
) -> String raise SqliteAccountingReconciliationError {
  if value.length() % 2 != 0 {
    raise fail("invalid SQLite hexadecimal field")
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
    let high = digit(value.get_char(index * 2).unwrap()).unwrap_or(-1)
    let low = digit(value.get_char(index * 2 + 1).unwrap()).unwrap_or(-1)
    if high < 0 || low < 0 {
      raise fail("invalid SQLite hexadecimal field")
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
struct LinkRow {
  event_id : String
  source_type : String
  source_id : String
  journal_id : String
  principal_id : String
}

///|
fn rows(
  path : String,
) -> Array[LinkRow] raise SqliteAccountingReconciliationError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingReconciliationError::Io(error)
  }
  let result : Array[LinkRow] = []
  for view in text.split("\n") {
    let line = view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 5 {
        raise fail("unexpected SQLite accounting-link row")
      }
      result.push({
        event_id: decode_hex(values[0]),
        source_type: decode_hex(values[1]),
        source_id: decode_hex(values[2]),
        journal_id: decode_hex(values[3]),
        principal_id: decode_hex(values[4]),
      })
    }
  }
  result
}

///|
fn find_row(rows : Array[LinkRow], event_id : String) -> LinkRow? {
  for row in rows {
    if row.event_id == event_id {
      return Some(row)
    }
  }
  None
}

///|
fn fallback_amount(candidate : Map[String, Json]) -> Json {
  let names = [
    "completed_value_minor", "tax_amount_minor", "reported_tax_amount_minor", "notional_minor",
    "actual_amount_minor",
  ]
  for name in names {
    match candidate.get(name) {
      Some(value) => return value
      None => ()
    }
  }
  Json::null()
}

///|
fn prepare(
  receipt_path : String,
  work_dir : String,
) -> Unit raise SqliteAccountingReconciliationError {
  let root = object(read_json(receipt_path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  let values = array(root, "accepted_items", "receipt")
  if values.is_empty() {
    raise fail("accounting-link receipt has no accepted items")
  }
  let ids : Array[String] = []
  for value in values {
    ids.push(
      required_string(
        object(value, "accepted_items"),
        "event_id",
        "accepted_items",
      ),
    )
  }
  let sql_ids = ids
    .map(fn(value) {
      "'" +
      value.split("'").map(fn(part) { part.to_owned() }).to_array().join("''") +
      "'"
    })
    .join(",")
  let sql = "SELECT coalesce(hex(event_id), ''), coalesce(hex(source_type), ''), coalesce(hex(source_id), ''), coalesce(hex(journal_id), ''), coalesce(hex(principal_id), '') FROM company_accounting_event_link WHERE event_id IN (" +
    sql_ids +
    ") ORDER BY event_id;\n"
  @fs.write_string_to_file(work_dir + "/query.sql", sql) catch {
    error => raise SqliteAccountingReconciliationError::Io(error)
  }
}

///|
fn report(
  domain_path : String,
  plan_path : String,
  receipt_path : String,
  rows_path : String,
  integrity : String,
  output_path : String,
) -> Unit raise SqliteAccountingReconciliationError {
  let domain = object(read_json(domain_path), "domain")
  let plan = object(read_json(plan_path), "plan")
  let receipt = object(read_json(receipt_path), "receipt")
  if required_string(domain, "format", "domain") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected domain promotion format")
  }
  if required_string(plan, "format", "plan") !=
    "moonproj.erp.accounting-link-plan.v1" {
    raise fail("unexpected accounting-link plan format")
  }
  if required_string(receipt, "format", "receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  if required_string(receipt, "state", "receipt") !=
    "validated_accounting_links" {
    raise fail("accounting-link receipt is not validated")
  }
  let domain_map : Map[String, Map[String, Json]] = {}
  for value in array(domain, "accepted_items", "domain") {
    let item = object(value, "domain.accepted_items")
    domain_map.set(key(item, "domain.accepted_items"), item)
  }
  let plan_values = array(plan, "items", "plan")
  let receipt_map : Map[String, Map[String, Json]] = {}
  for value in array(receipt, "accepted_items", "receipt") {
    let item = object(value, "receipt.accepted_items")
    receipt_map.set(key(item, "receipt.accepted_items"), item)
  }
  if plan_values.is_empty() || receipt_map.is_empty() {
    raise fail("accounting reconciliation has no accepted items")
  }
  let durable = rows(rows_path)
  if integrity != "ok" {
    raise fail("SQLite integrity check failed")
  }
  let checks : Array[Json] = []
  for index in 0..<plan_values.length() {
    let path = "plan.items[" + index.to_string() + "]"
    let item = object(plan_values[index], path)
    if required_string(item, "disposition", path) != "ready_for_domain_import" {
      raise fail("accounting plan contains quarantined items")
    }
    let source_key = key(item, path)
    let domain_item = match domain_map.get(source_key) {
      Some(value) => value
      None => raise fail("missing domain or receipt identity at " + source_key)
    }
    let receipt_item = match receipt_map.get(source_key) {
      Some(value) => value
      None => raise fail("missing domain or receipt identity at " + source_key)
    }
    let candidate = object(
      required(item, "target_candidate", path),
      path + ".target_candidate",
    )
    let domain_candidate = object(
      required(domain_item, "target_candidate", "domain"),
      "domain.target_candidate",
    )
    let journal = object(
      required(candidate, "journal", path),
      path + ".journal",
    )
    let principal = required(candidate, "principal_id", path)
    if !json_equal(
        principal,
        required(domain_candidate, "principal_id", "domain.target_candidate"),
      ) {
      raise fail("principal_id mismatch at " + source_key)
    }
    let domain_amount = match domain_item.get("target_type") {
      Some(String("payment_application")) => {
        let application = object(
          required(domain_candidate, "application", "domain.target_candidate"),
          "application",
        )
        application.get("amount_minor").unwrap_or(Json::null())
      }
      _ =>
        match domain_candidate.get("amount_minor") {
          Some(value) => value
          None => fallback_amount(domain_candidate)
        }
    }
    if !json_equal(
        required(journal, "amount_minor", path + ".journal"),
        domain_amount,
      ) {
      raise fail("amount_minor mismatch at " + source_key)
    }
    if !json_equal(
        required(journal, "currency", path + ".journal"),
        required(domain_candidate, "currency", "domain.target_candidate"),
      ) {
      raise fail("currency mismatch at " + source_key)
    }
    let event_id = required_string(receipt_item, "event_id", "receipt item")
    let row = match find_row(durable, event_id) {
      Some(value) => value
      None => raise fail("durable accounting link mismatch at " + event_id)
    }
    let expected_source_type = required_string(
      receipt_item, "source_type", "receipt item",
    )
    let expected_source_id = required_string(
      receipt_item, "source_id", "receipt item",
    )
    let expected_journal = required_string(
      receipt_item, "journal_id", "receipt item",
    )
    let expected_principal = required_string(
      receipt_item, "principal_id", "receipt item",
    )
    if row.source_type != expected_source_type ||
      row.source_id != expected_source_id ||
      row.journal_id != expected_journal ||
      row.principal_id != expected_principal {
      raise fail("durable accounting link mismatch at " + event_id)
    }
    checks.push(
      Json::object({
        "source_table": Json::string(
          required_string(item, "source_table", path),
        ),
        "source_id": Json::string(required_string(item, "source_id", path)),
        "event_id": Json::string(event_id),
        "journal_id": Json::string(expected_journal),
        "principal_id": Json::string(expected_principal),
        "amount_minor": required(journal, "amount_minor", path + ".journal"),
        "currency": required(journal, "currency", path + ".journal"),
      }),
    )
  }
  let result = Json::object({
    "format": Json::string("moonproj.erp.accounting-reconciliation.v1"),
    "source_snapshot_id": required(receipt, "source_snapshot_id", "receipt"),
    "mapping_version": required(receipt, "mapping_version", "receipt"),
    "state": Json::string("reconciled"),
    "integrity": Json::string(integrity),
    "link_count": Json::number(
      checks.length().to_double(),
      repr=checks.length().to_string(),
    ),
    "checks": Json::array(checks),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
  })
  @fs.write_string_to_file(output_path, result.stringify(indent=2) + "\n") catch {
    error => raise SqliteAccountingReconciliationError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "state": Json::string("reconciled"),
      "link_count": Json::number(
        checks.length().to_double(),
        repr=checks.length().to_string(),
      ),
    }).stringify(),
  )
}

///|
fn run(args : Array[String]) -> Unit raise SqliteAccountingReconciliationError {
  if args.length() < 2 {
    raise fail("usage: sqlite_accounting_reconciliation <prepare|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 => prepare(args[2], args[3])
    "report" if args.length() >= 8 =>
      report(args[2], args[3], args[4], args[5], args[6], args[7])
    _ => raise fail("invalid sqlite accounting reconciliation arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteAccountingReconciliationError::InvalidInput(message) => {
      println("company SQLite accounting reconciliation failed: " + message)
      @sys.exit(1)
    }
    SqliteAccountingReconciliationError::Io(_) => {
      println(
        "company SQLite accounting reconciliation failed: filesystem error",
      )
      @sys.exit(1)
    }
  }
}
