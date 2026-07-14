///|
/// Native MoonBit accounting-link persistence boundary.
///
/// Only explicit source/event/journal identity is persisted. This command
/// never posts journals, releases cash, infers accounting policy, or closes a
/// period.
pub(all) suberror PostgresAccountingLinkApplyError {
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
fn fail(message : String) -> PostgresAccountingLinkApplyError {
  PostgresAccountingLinkApplyError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresAccountingLinkApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresAccountingLinkApplyError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse accounting-link receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresAccountingLinkApplyError {
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
) -> Json raise PostgresAccountingLinkApplyError {
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
) -> String raise PostgresAccountingLinkApplyError {
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
) -> Array[Json] raise PostgresAccountingLinkApplyError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn load_receipt(
  path : String,
) -> LinkReceipt raise PostgresAccountingLinkApplyError {
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
  { source_snapshot_id, mapping_version, items }
}

///|
fn csv_cell(value : String) -> String {
  if value.contains(",") ||
    value.contains("\n") ||
    value.contains("\r") ||
    value.contains("\"") {
    "\"" +
    value.split("\"").map(fn(part) { part.to_owned() }).to_array().join("\"\"") +
    "\""
  } else {
    value
  }
}

///|
fn write_stage_csv(
  receipt : LinkReceipt,
  path : String,
) -> Unit raise PostgresAccountingLinkApplyError {
  let mut content = "event_id,source_type,source_id,journal_id,principal_id\n"
  for item in receipt.items {
    content += csv_cell(item.event_id) +
      "," +
      csv_cell(item.source_type) +
      "," +
      csv_cell(item.source_id) +
      "," +
      csv_cell(item.journal_id) +
      "," +
      csv_cell(item.principal_id) +
      "\n"
  }
  @fs.write_string_to_file(path, content) catch {
    error => raise PostgresAccountingLinkApplyError::Io(error)
  }
}

///|
fn decode_hex(value : String) -> String raise PostgresAccountingLinkApplyError {
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
fn parse_decimal(value : String) -> Int raise PostgresAccountingLinkApplyError {
  if value.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  for char in value.iter() {
    if char < '0' || char > '9' {
      raise fail("invalid integer: " + value)
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  result
}

///|
fn fields(
  line : String,
  expected : Int,
) -> Array[String] raise PostgresAccountingLinkApplyError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  values
}

///|
fn logical_hash_text(
  output : String,
) -> String raise PostgresAccountingLinkApplyError {
  let mut text = ""
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 5)
      let values : Array[Json] = []
      for item in row {
        values.push(Json::string(decode_hex(item)))
      }
      text += Json::array(values).stringify() + "\n"
    }
  }
  text
}

///|
async fn logical_link_hash(
  connection : @postgres.Connection,
  receipt : LinkReceipt,
) -> String raise PostgresAccountingLinkApplyError {
  let ids : Array[String] = []
  for item in receipt.items {
    ids.push(@postgres.sql_literal(item.event_id))
  }
  let output = @postgres.run_sql(
    connection,
    "SELECT encode(convert_to(event_id, 'UTF8'), 'hex'), encode(convert_to(source_type, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex'), encode(convert_to(journal_id, 'UTF8'), 'hex'), encode(convert_to(principal_id, 'UTF8'), 'hex') FROM company_accounting_event_link WHERE event_id IN (" +
    ids.join(", ") +
    ") ORDER BY event_id",
  ) catch {
    error => raise PostgresAccountingLinkApplyError::Database(error)
  }
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(logical_hash_text(output))),
  )
}

///|
fn parse_last_count(
  output : String,
) -> Int raise PostgresAccountingLinkApplyError {
  let mut result : Int? = None
  for line_view in output.split("\n") {
    let line = line_view.trim().to_owned()
    if !line.is_empty() {
      let value = parse_decimal(line) catch { _ => continue }
      result = Some(value)
    }
  }
  match result {
    Some(value) => value
    None =>
      raise fail("PostgreSQL accounting-link apply did not return a count")
  }
}

///|
async fn apply_rows(
  connection : @postgres.Connection,
  csv_path : String,
  sql_path : String,
) -> Int raise PostgresAccountingLinkApplyError {
  let sql = "BEGIN;\nLOCK TABLE company_accounting_event_link IN SHARE ROW EXCLUSIVE MODE;\nCREATE TEMP TABLE staging_company_accounting_link (event_id VARCHAR(255) NOT NULL, source_type VARCHAR(128) NOT NULL, source_id VARCHAR(255) NOT NULL, journal_id VARCHAR(255) NOT NULL, principal_id VARCHAR(255) NOT NULL) ON COMMIT DROP;\n\\copy staging_company_accounting_link(event_id, source_type, source_id, journal_id, principal_id) FROM " +
    @postgres.sql_literal(csv_path) +
    " WITH (FORMAT csv, HEADER true);\nDO $$ BEGIN IF EXISTS (SELECT 1 FROM staging_company_accounting_link s JOIN company_accounting_event_link l ON l.event_id = s.event_id WHERE l.source_type <> s.source_type OR l.source_id <> s.source_id OR l.journal_id <> s.journal_id OR l.principal_id <> s.principal_id) THEN RAISE EXCEPTION 'company accounting-link event conflict'; END IF; IF EXISTS (SELECT 1 FROM staging_company_accounting_link s JOIN company_accounting_event_link l ON l.source_type = s.source_type AND l.source_id = s.source_id WHERE l.event_id <> s.event_id) THEN RAISE EXCEPTION 'company accounting-link source conflict'; END IF; IF EXISTS (SELECT 1 FROM staging_company_accounting_link s JOIN company_accounting_event_link l ON l.journal_id = s.journal_id WHERE l.event_id <> s.event_id) THEN RAISE EXCEPTION 'company accounting-link journal conflict'; END IF; END $$;\nWITH inserted AS (INSERT INTO company_accounting_event_link(event_id, source_type, source_id, journal_id, principal_id) SELECT event_id, source_type, source_id, journal_id, principal_id FROM staging_company_accounting_link ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  @fs.write_string_to_file(sql_path, sql) catch {
    error => raise PostgresAccountingLinkApplyError::Io(error)
  }
  let output = @postgres.run_file(connection, sql_path) catch {
    error => raise PostgresAccountingLinkApplyError::Database(error)
  }
  parse_last_count(output)
}

///|
async fn finalize_receipt(
  connection : @postgres.Connection,
  receipt : LinkReceipt,
  run_id : String,
  baseline_hash : String,
  applied_hash : String,
) -> Bool raise PostgresAccountingLinkApplyError {
  let mapping = "accounting:" + receipt.mapping_version
  let sql = "BEGIN;\nDO $$ DECLARE existing company_migration_receipt%ROWTYPE; BEGIN SELECT * INTO existing FROM company_migration_receipt WHERE run_id = " +
    @postgres.sql_literal(run_id) +
    "; IF FOUND THEN IF existing.source_snapshot_id <> " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    " OR existing.target_schema_version <> 4 OR existing.mapping_version <> " +
    @postgres.sql_literal(mapping) +
    " OR existing.state <> 'AccountingLinked' OR existing.applied_hash <> " +
    @postgres.sql_literal(applied_hash) +
    " THEN RAISE EXCEPTION 'accounting-link migration receipt conflict'; END IF; END IF; END $$;\nWITH inserted AS (INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) VALUES (" +
    @postgres.sql_literal(run_id) +
    ", " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    ", 4, " +
    @postgres.sql_literal(mapping) +
    ", 'AccountingLinked', " +
    @postgres.sql_literal(baseline_hash) +
    ", " +
    @postgres.sql_literal(applied_hash) +
    ", CURRENT_TIMESTAMP) ON CONFLICT (run_id) DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  let output = @postgres.run_sql(connection, sql) catch {
    error => raise PostgresAccountingLinkApplyError::Database(error)
  }
  parse_last_count(output) == 1
}

///|
async fn run(
  receipt_path : String,
  schema_path : String,
  connection : @postgres.Connection,
  database : String,
) -> Json raise PostgresAccountingLinkApplyError {
  let receipt = load_receipt(receipt_path)
  let seed = receipt.source_snapshot_id + "|" + receipt.mapping_version
  let run_id = "postgres-accounting-link-" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(seed)))[:16].to_owned()
  let _ = @postgres.run_file(connection, schema_path) catch {
    error => raise PostgresAccountingLinkApplyError::Database(error)
  }
  let result = @fsx.with_temporary_directory(
    "moonproj-postgres-accounting-XXXXXX",
    directory => {
      let csv_path = directory + "/accounting-links.csv"
      let sql_path = directory + "/apply-company-accounting-links.sql"
      write_stage_csv(receipt, csv_path)
      let baseline_hash = logical_link_hash(connection, receipt)
      let inserted = apply_rows(connection, csv_path, sql_path)
      let applied_hash = logical_link_hash(connection, receipt)
      let receipt_inserted = finalize_receipt(
        connection, receipt, run_id, baseline_hash, applied_hash,
      )
      let output = @postgres.run_sql(
        connection, "SELECT count(*)::text FROM company_accounting_event_link",
      ) catch {
        error => raise PostgresAccountingLinkApplyError::Database(error)
      }
      let count = parse_last_count(output)
      Json::object({
        "database": Json::string(database),
        "run_id": Json::string(run_id),
        "source_snapshot_id": Json::string(receipt.source_snapshot_id),
        "mapping_version": Json::string(receipt.mapping_version),
        "inserted_accounting_links": Json::number(inserted.to_double()),
        "accounting_link_count": Json::number(count.to_double()),
        "receipt_inserted": Json::boolean(receipt_inserted),
        "baseline_hash": Json::string(baseline_hash),
        "applied_hash": Json::string(applied_hash),
      })
    },
  ) catch {
    error =>
      raise fail(
        "temporary PostgreSQL accounting workspace failed: \{to_repr(error)}",
      )
  }
  result
}

///|
fn option(
  args : Array[String],
  name : String,
) -> String? raise PostgresAccountingLinkApplyError {
  for index in 2..<args.length() {
    if args[index] == name {
      match args.get(index + 1) {
        Some(value) if !value.has_prefix("--") => return Some(value)
        _ => raise fail("missing value for " + name)
      }
    }
  }
  None
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(
      "usage: postgres_accounting_link_apply <receipt> [--schema path] [--psql path] [--host host] [--port port] [--user user] [--database database]",
    )
    @sys.exit(2)
  }
  let schema_path = option(args, "--schema").unwrap_or(
    "scripts/postgres_target_schema.sql",
  )
  let database = option(args, "--database").unwrap_or("moonproj")
  let connection = @postgres.connection_from_env().with_overrides(
    psql=option(args, "--psql"),
    host=option(args, "--host"),
    port=option(args, "--port"),
    user=option(args, "--user"),
    database=Some(database),
  )
  let report = run(args[1], schema_path, connection, database) catch {
    error => {
      println(
        "company PostgreSQL accounting-link apply failed: \{to_repr(error)}",
      )
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
