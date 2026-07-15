///|
/// Native PostgreSQL accounting-link identity parity verifier.
///
/// This is deliberately identity-only. It proves that event, source, journal,
/// and principal fields survived the PostgreSQL adapter; it never posts a
/// journal, releases cash, or certifies a period.
pub(all) suberror PostgresAccountingLinkParityError {
  InvalidInput(String)
  Io(@fs.IOError)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
struct LinkItem {
  event_id : String
  source_type : String
  source_id : String
  journal_id : String
  principal_id : String
}

///|
struct LinkReceipt {
  source_snapshot_id : String
  mapping_version : String
  items : Array[LinkItem]
}

///|
fn fail(message : String) -> PostgresAccountingLinkParityError {
  PostgresAccountingLinkParityError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresAccountingLinkParityError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresAccountingLinkParityError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse accounting-link receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresAccountingLinkParityError {
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
) -> Json raise PostgresAccountingLinkParityError {
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
) -> String raise PostgresAccountingLinkParityError {
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
) -> Array[Json] raise PostgresAccountingLinkParityError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn load_receipt(
  path : String,
) -> LinkReceipt raise PostgresAccountingLinkParityError {
  let root = object(read_json(path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  if required_string(root, "state", "receipt") != "validated_accounting_links" {
    raise fail("accounting-link receipt is not native-validated")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "receipt",
  )
  let mapping_version = required_string(root, "mapping_version", "receipt")
  let values = required_array(root, "accepted_items", "receipt")
  if values.is_empty() {
    raise fail("accounting-link receipt has no accepted items")
  }
  let events : Array[String] = []
  let sources : Array[String] = []
  let journals : Array[String] = []
  let items : Array[LinkItem] = []
  for index in 0..<values.length() {
    let path = "receipt.accepted_items[" + index.to_string() + "]"
    let item = object(values[index], path)
    let event_id = required_string(item, "event_id", path)
    let source_type = required_string(item, "source_type", path)
    let source_id = required_string(item, "source_id", path)
    let journal_id = required_string(item, "journal_id", path)
    let principal_id = required_string(item, "principal_id", path)
    let source_key = source_type + ":" + source_id
    if events.contains(event_id) {
      raise fail("duplicate accounting event in receipt: " + event_id)
    }
    if sources.contains(source_key) {
      raise fail("duplicate accounting source in receipt: " + source_key)
    }
    if journals.contains(journal_id) {
      raise fail("duplicate journal in receipt: " + journal_id)
    }
    events.push(event_id)
    sources.push(source_key)
    journals.push(journal_id)
    items.push({ event_id, source_type, source_id, journal_id, principal_id })
  }
  { source_snapshot_id, mapping_version, items }
}

///|
fn decode_hex(value : String) -> String raise PostgresAccountingLinkParityError {
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
) -> Array[String] raise PostgresAccountingLinkParityError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL accounting-link row")
  }
  values
}

///|
fn link_equal(left : LinkItem, right : LinkItem) -> Bool {
  left.event_id == right.event_id &&
  left.source_type == right.source_type &&
  left.source_id == right.source_id &&
  left.journal_id == right.journal_id &&
  left.principal_id == right.principal_id
}

///|
async fn query_actual(
  connection : @postgres.Connection,
  receipt : LinkReceipt,
) -> Array[LinkItem] raise PostgresAccountingLinkParityError {
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
    error => raise PostgresAccountingLinkParityError::Database(error)
  }
  let result : Array[LinkItem] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 5)
      result.push({
        event_id: decode_hex(row[0]),
        source_type: decode_hex(row[1]),
        source_id: decode_hex(row[2]),
        journal_id: decode_hex(row[3]),
        principal_id: decode_hex(row[4]),
      })
    }
  }
  result
}

///|
fn event_ids(values : Array[LinkItem]) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(value.event_id)
  }
  result.sort_by(fn(left, right) { left.compare(right) })
  result
}

///|
fn string_array(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn json_text(value : Json, key : String) -> String {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => text
        _ => ""
      }
    _ => ""
  }
}

///|
async fn compare(
  receipt : LinkReceipt,
  connection : @postgres.Connection,
) -> Json raise PostgresAccountingLinkParityError {
  let actual = query_actual(connection, receipt)
  let missing : Array[String] = []
  let mismatched : Array[String] = []
  for expected in receipt.items {
    let mut found : LinkItem? = None
    for value in actual {
      if value.event_id == expected.event_id {
        found = Some(value)
      }
    }
    match found {
      None => missing.push(expected.event_id)
      Some(value) if !link_equal(expected, value) =>
        mismatched.push(expected.event_id)
      Some(_) => ()
    }
  }
  let expected_ids = event_ids(receipt.items)
  let actual_ids = event_ids(actual)
  let extra : Array[String] = []
  for actual_id in actual_ids {
    if !expected_ids.contains(actual_id) {
      extra.push(actual_id)
    }
  }
  missing.sort_by(fn(left, right) { left.compare(right) })
  mismatched.sort_by(fn(left, right) { left.compare(right) })
  extra.sort_by(fn(left, right) { left.compare(right) })
  let exact = missing.is_empty() && extra.is_empty() && mismatched.is_empty()
  Json::object({
    "format": Json::string("moonproj.erp.accounting-link-parity.v1"),
    "backend": Json::string("postgres"),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string(if exact { "shadow_verified" } else { "mismatch" }),
    "expected_count": Json::number(receipt.items.length().to_double()),
    "matched_count": Json::number(
      (receipt.items.length() - missing.length() - mismatched.length()).to_double(),
    ),
    "missing_event_ids": string_array(missing),
    "extra_event_ids": string_array(extra),
    "mismatched_event_ids": string_array(mismatched),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
  })
}

///|
fn option(args : Array[String], name : String) -> String? {
  for index in 2..<args.length() {
    if args[index] == name {
      return args.get(index + 1)
    }
  }
  None
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(
      "usage: postgres_accounting_link_parity <receipt> [--psql path] [--host host] [--port port] [--user user] [--database database]",
    )
    @sys.exit(2)
  }
  let receipt = load_receipt(args[1]) catch {
    error => {
      println(
        "company PostgreSQL accounting-link parity failed: \{to_repr(error)}",
      )
      @sys.exit(1)
      { source_snapshot_id: "", mapping_version: "", items: [] }
    }
  }
  let connection = @postgres.connection_from_env().with_overrides(
    psql=option(args, "--psql"),
    host=option(args, "--host"),
    port=option(args, "--port"),
    user=option(args, "--user"),
    database=Some(option(args, "--database").unwrap_or("moonproj")),
  )
  let report = compare(receipt, connection) catch {
    error => {
      println(
        "company PostgreSQL accounting-link parity failed: \{to_repr(error)}",
      )
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
  if json_text(report, "state") != "shadow_verified" {
    @sys.exit(1)
  }
}
