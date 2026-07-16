///|
pub(all) suberror SqliteAccountingLinkParityError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct Item {
  event_id : String
  source_type : String
  source_id : String
  journal_id : String
  principal_id : String
}

///|
struct Receipt {
  source_snapshot_id : String
  mapping_version : String
  items : Array[Item]
}

///|
struct Row {
  event_id : String
  source_type : String
  source_id : String
  journal_id : String
  principal_id : String
}

///|
fn fail(message : String) -> SqliteAccountingLinkParityError {
  SqliteAccountingLinkParityError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteAccountingLinkParityError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingLinkParityError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteAccountingLinkParityError {
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
) -> Json raise SqliteAccountingLinkParityError {
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
) -> String raise SqliteAccountingLinkParityError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn load_receipt(path : String) -> Receipt raise SqliteAccountingLinkParityError {
  let root = object(read_json(path), "receipt")
  if string(root, "format", "receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" ||
    string(root, "state", "receipt") != "validated_accounting_links" {
    raise fail("unexpected accounting-link receipt")
  }
  let source_snapshot_id = string(root, "source_snapshot_id", "receipt")
  let mapping_version = string(root, "mapping_version", "receipt")
  let values = match required(root, "accepted_items", "receipt") {
    Array(values) => values
    _ => raise fail("accounting-link receipt has no accepted items")
  }
  if values.is_empty() {
    raise fail("accounting-link receipt has no accepted items")
  }
  let items : Array[Item] = []
  for index in 0..<values.length() {
    let path = "accepted_items[" + index.to_string() + "]"
    let item = object(values[index], path)
    items.push({
      event_id: string(item, "event_id", path),
      source_type: string(item, "source_type", path),
      source_id: string(item, "source_id", path),
      journal_id: string(item, "journal_id", path),
      principal_id: string(item, "principal_id", path),
    })
  }
  { source_snapshot_id, mapping_version, items }
}

///|
fn sql_literal(value : String) -> String {
  "'" +
  value.split("'").map(fn(part) { part.to_owned() }).to_array().join("''") +
  "'"
}

///|
fn decode_hex(value : String) -> String raise SqliteAccountingLinkParityError {
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
fn parse_rows(
  path : String,
) -> Array[Row] raise SqliteAccountingLinkParityError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingLinkParityError::Io(error)
  }
  let rows : Array[Row] = []
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
      rows.push({
        event_id: decode_hex(values[0]),
        source_type: decode_hex(values[1]),
        source_id: decode_hex(values[2]),
        journal_id: decode_hex(values[3]),
        principal_id: decode_hex(values[4]),
      })
    }
  }
  rows
}

///|
fn write_query(
  receipt : Receipt,
  work_dir : String,
) -> Unit raise SqliteAccountingLinkParityError {
  let ids = receipt.items.map(fn(item) { sql_literal(item.event_id) }).join(",")
  let sql = "SELECT coalesce(hex(event_id), ''), coalesce(hex(source_type), ''), coalesce(hex(source_id), ''), coalesce(hex(journal_id), ''), coalesce(hex(principal_id), '') FROM company_accounting_event_link WHERE event_id IN (" +
    ids +
    ") ORDER BY event_id;\n"
  @fs.write_string_to_file(work_dir + "/query.sql", sql) catch {
    error => raise SqliteAccountingLinkParityError::Io(error)
  }
}

///|
fn find(rows : Array[Row], event_id : String) -> Row? {
  for row in rows {
    if row.event_id == event_id {
      return Some(row)
    }
  }
  None
}

///|
fn same(left : Row, right : Item) -> Bool {
  left.event_id == right.event_id &&
  left.source_type == right.source_type &&
  left.source_id == right.source_id &&
  left.journal_id == right.journal_id &&
  left.principal_id == right.principal_id
}

///|
fn report(
  receipt_path : String,
  rows_path : String,
  backend : String,
  _database : String,
  output_path : String,
) -> Unit raise SqliteAccountingLinkParityError {
  let receipt = load_receipt(receipt_path)
  let rows = parse_rows(rows_path)
  let missing : Array[String] = []
  let mismatched : Array[String] = []
  for item in receipt.items {
    match find(rows, item.event_id) {
      None => missing.push(item.event_id)
      Some(row) => if !same(row, item) { mismatched.push(item.event_id) }
    }
  }
  let extras : Array[String] = []
  for row in rows {
    let mut found = false
    for item in receipt.items {
      if item.event_id == row.event_id {
        found = true
      }
    }
    if !found {
      extras.push(row.event_id)
    }
  }
  let matched = receipt.items.length() - missing.length() - mismatched.length()
  let exact = missing.is_empty() && extras.is_empty() && mismatched.is_empty()
  let report = Json::object({
    "format": Json::string("moonproj.erp.accounting-link-parity.v1"),
    "backend": Json::string(backend),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string(if exact { "shadow_verified" } else { "mismatch" }),
    "expected_count": Json::number(
      receipt.items.length().to_double(),
      repr=receipt.items.length().to_string(),
    ),
    "matched_count": Json::number(matched.to_double(), repr=matched.to_string()),
    "missing_event_ids": Json::array(missing.map(Json::string)),
    "extra_event_ids": Json::array(extras.map(Json::string)),
    "mismatched_event_ids": Json::array(mismatched.map(Json::string)),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise SqliteAccountingLinkParityError::Io(error)
  }
  println(report.stringify())
  if !exact {
    raise fail("durable accounting-link identity mismatch")
  }
}

///|
fn run(args : Array[String]) -> Unit raise SqliteAccountingLinkParityError {
  if args.length() < 2 {
    raise fail("usage: sqlite_accounting_link_parity <prepare|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 =>
      write_query(load_receipt(args[2]), args[3])
    "report" if args.length() >= 7 =>
      report(args[2], args[3], args[4], args[5], args[6])
    _ => raise fail("invalid sqlite accounting-link parity arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteAccountingLinkParityError::InvalidInput(message) => {
      println("company SQLite accounting-link parity failed: " + message)
      @sys.exit(1)
    }
    SqliteAccountingLinkParityError::Io(_) => {
      println("company SQLite accounting-link parity failed: filesystem error")
      @sys.exit(1)
    }
  }
}
