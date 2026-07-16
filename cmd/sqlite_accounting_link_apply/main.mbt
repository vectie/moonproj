///|
pub(all) suberror SqliteAccountingLinkApplyError {
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
fn fail(message : String) -> SqliteAccountingLinkApplyError {
  SqliteAccountingLinkApplyError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteAccountingLinkApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteAccountingLinkApplyError {
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
) -> Json raise SqliteAccountingLinkApplyError {
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
) -> String raise SqliteAccountingLinkApplyError {
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
) -> Array[Json] raise SqliteAccountingLinkApplyError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn load_receipt(path : String) -> Receipt raise SqliteAccountingLinkApplyError {
  let root = object(read_json(path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  if required_string(root, "state", "receipt") != "validated_accounting_links" {
    raise fail("accounting-link receipt is not native-validated")
  }
  let snapshot = required_string(root, "source_snapshot_id", "receipt")
  let mapping = required_string(root, "mapping_version", "receipt")
  let values = required_array(root, "accepted_items", "receipt")
  if values.is_empty() {
    raise fail("accounting-link receipt has no accepted items")
  }
  let events : Array[String] = []
  let sources : Array[String] = []
  let journals : Array[String] = []
  let items : Array[Item] = []
  for index in 0..<values.length() {
    let path = "accepted_items[" + index.to_string() + "]"
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
  { source_snapshot_id: snapshot, mapping_version: mapping, items }
}

///|
fn sql_literal(value : String) -> String {
  "'" +
  value.split("'").map(fn(part) { part.to_owned() }).to_array().join("''") +
  "'"
}

///|
fn decode_hex(value : String) -> String raise SqliteAccountingLinkApplyError {
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
fn parse_rows(path : String) -> Array[Row] raise SqliteAccountingLinkApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  let rows : Array[Row] = []
  for view in content.split("\n") {
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
fn row_sort(left : Row, right : Row) -> Int {
  left.event_id.lexical_compare(right.event_id)
}

///|
fn hash_rows(rows : Array[Row]) -> String {
  let sorted = rows.copy()
  sorted.sort_by(row_sort)
  let mut text = ""
  for row in sorted {
    text += Json::array([
        Json::string(row.event_id),
        Json::string(row.source_type),
        Json::string(row.source_id),
        Json::string(row.journal_id),
        Json::string(row.principal_id),
      ]).stringify() +
      "\n"
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(text)))
}

///|
fn write_query_files(
  receipt : Receipt,
  work_dir : String,
) -> Unit raise SqliteAccountingLinkApplyError {
  let ids = receipt.items.map(fn(item) { sql_literal(item.event_id) }).join(",")
  let mut preflight = "SELECT event_id FROM company_accounting_event_link WHERE event_id IN (" +
    ids +
    ") AND ("
  let clauses : Array[String] = []
  for item in receipt.items {
    clauses.push(
      "(event_id=" +
      sql_literal(item.event_id) +
      " AND (source_type<>" +
      sql_literal(item.source_type) +
      " OR source_id<>" +
      sql_literal(item.source_id) +
      " OR journal_id<>" +
      sql_literal(item.journal_id) +
      " OR principal_id<>" +
      sql_literal(item.principal_id) +
      "))",
    )
    clauses.push(
      "(source_type=" +
      sql_literal(item.source_type) +
      " AND source_id=" +
      sql_literal(item.source_id) +
      " AND event_id<>" +
      sql_literal(item.event_id) +
      ")",
    )
    clauses.push(
      "(journal_id=" +
      sql_literal(item.journal_id) +
      " AND event_id<>" +
      sql_literal(item.event_id) +
      ")",
    )
  }
  preflight += clauses.join(" OR ") + ");\n"
  let before = "SELECT coalesce(hex(event_id), ''), coalesce(hex(source_type), ''), coalesce(hex(source_id), ''), coalesce(hex(journal_id), ''), coalesce(hex(principal_id), '') FROM company_accounting_event_link WHERE event_id IN (" +
    ids +
    ") ORDER BY event_id;\n"
  let after = before
  @fs.write_string_to_file(work_dir + "/preflight.sql", preflight) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/before.sql", before) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/after.sql", after) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
}

///|
fn write_plan(
  receipt : Receipt,
  work_dir : String,
  before_path : String,
) -> Unit raise SqliteAccountingLinkApplyError {
  let before = parse_rows(before_path)
  let baseline_hash = hash_rows(before)
  let existing : Map[String, Bool] = {}
  for row in before {
    existing.set(row.event_id, true)
  }
  let simulated = before.copy()
  let mut sql = "BEGIN IMMEDIATE;\nPRAGMA foreign_keys=ON;\n"
  for item in receipt.items {
    sql += "INSERT INTO company_accounting_event_link(event_id, source_type, source_id, journal_id, principal_id) SELECT " +
      sql_literal(item.event_id) +
      "," +
      sql_literal(item.source_type) +
      "," +
      sql_literal(item.source_id) +
      "," +
      sql_literal(item.journal_id) +
      "," +
      sql_literal(item.principal_id) +
      " WHERE NOT EXISTS (SELECT 1 FROM company_accounting_event_link WHERE event_id=" +
      sql_literal(item.event_id) +
      ");\n"
    if existing.get(item.event_id) is None {
      simulated.push({
        event_id: item.event_id,
        source_type: item.source_type,
        source_id: item.source_id,
        journal_id: item.journal_id,
        principal_id: item.principal_id,
      })
      existing.set(item.event_id, true)
    }
  }
  let applied_hash = hash_rows(simulated)
  let seed = receipt.source_snapshot_id + "|" + receipt.mapping_version
  let run_id = "accounting-link-" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(seed)))[:16].to_owned()
  let mapping = "accounting:" + receipt.mapping_version
  let receipt_check = "SELECT run_id FROM company_migration_receipt WHERE run_id=" +
    sql_literal(run_id) +
    " AND (source_snapshot_id<>" +
    sql_literal(receipt.source_snapshot_id) +
    " OR target_schema_version<>4 OR mapping_version<>" +
    sql_literal(mapping) +
    " OR state<>'AccountingLinked' OR applied_hash<>" +
    sql_literal(applied_hash) +
    ");\n"
  sql += "INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) SELECT " +
    sql_literal(run_id) +
    "," +
    sql_literal(receipt.source_snapshot_id) +
    ",4," +
    sql_literal(mapping) +
    ",'AccountingLinked'," +
    sql_literal(baseline_hash) +
    "," +
    sql_literal(applied_hash) +
    ",CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM company_migration_receipt WHERE run_id=" +
    sql_literal(run_id) +
    ");\nSELECT changes();\nCOMMIT;\n"
  @fs.write_string_to_file(work_dir + "/receipt-check.sql", receipt_check) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/apply.sql", sql) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  @fs.write_string_to_file(
    work_dir + "/metadata.json",
    Json::object({
      "run_id": Json::string(run_id),
      "source_snapshot_id": Json::string(receipt.source_snapshot_id),
      "mapping_version": Json::string(receipt.mapping_version),
      "baseline_hash": Json::string(baseline_hash),
      "applied_hash": Json::string(applied_hash),
    }).stringify(indent=2) +
    "\n",
  ) catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
}

///|
fn parse_int(value : String) -> Int raise SqliteAccountingLinkApplyError {
  let source = value.trim().to_owned()
  if source.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  for char in source.iter() {
    if char < '0' || char > '9' {
      raise fail("invalid integer")
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  result
}

///|
fn report(
  work_dir : String,
  after_path : String,
  integrity : String,
  link_count : Int,
  receipt_count : Int,
  receipt_inserted : Bool,
  database : String,
  output_path : String,
) -> Unit raise SqliteAccountingLinkApplyError {
  let metadata = object(read_json(work_dir + "/metadata.json"), "metadata")
  let after = parse_rows(after_path)
  let before = parse_rows(work_dir + "/before.rows")
  let applied_hash = required_string(metadata, "applied_hash", "metadata")
  if integrity != "ok" || receipt_count != 1 {
    raise fail("accounting-link durability verification failed")
  }
  if hash_rows(after) != applied_hash {
    raise fail("accounting-link hash verification failed")
  }
  let report = Json::object({
    "database": Json::string(database),
    "run_id": Json::string(required_string(metadata, "run_id", "metadata")),
    "source_snapshot_id": Json::string(
      required_string(metadata, "source_snapshot_id", "metadata"),
    ),
    "mapping_version": Json::string(
      required_string(metadata, "mapping_version", "metadata"),
    ),
    "inserted_accounting_links": Json::number(
      (after.length() - before.length()).to_double(),
      repr=(after.length() - before.length()).to_string(),
    ),
    "accounting_link_count": Json::number(
      link_count.to_double(),
      repr=link_count.to_string(),
    ),
    "receipt_inserted": Json::boolean(receipt_inserted),
    "integrity": Json::string(integrity),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise SqliteAccountingLinkApplyError::Io(error)
  }
  println(report.stringify())
}

///|
fn run(args : Array[String]) -> Unit raise SqliteAccountingLinkApplyError {
  if args.length() < 2 {
    raise fail("usage: sqlite_accounting_link_apply <prepare|plan|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 =>
      write_query_files(load_receipt(args[2]), args[3])
    "plan" if args.length() >= 5 =>
      write_plan(load_receipt(args[2]), args[3], args[4])
    "report" if args.length() >= 10 =>
      report(
        args[2],
        args[3],
        args[4],
        parse_int(args[5]),
        parse_int(args[6]),
        args[7].trim() == "1",
        args[8],
        args[9],
      )
    _ => raise fail("invalid sqlite accounting-link apply arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteAccountingLinkApplyError::InvalidInput(message) => {
      println("company SQLite accounting-link apply failed: " + message)
      @sys.exit(1)
    }
    SqliteAccountingLinkApplyError::Io(_) => {
      println("company SQLite accounting-link apply failed: filesystem error")
      @sys.exit(1)
    }
  }
}
