///|
pub(all) suberror SqliteRehearsalError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct Record {
  record_type : String
  record_id : String
  source_id : String
  payload : Json
}

///|
struct ExistingRow {
  record_type : String
  record_id : String
  schema_version : Int
  payload : String
  source_id : String
}

///|
fn fail(message : String) -> SqliteRehearsalError {
  SqliteRehearsalError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteRehearsalError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteRehearsalError {
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
fn integer(value : Json, default : Int) -> Int {
  match value {
    Number(number, ..) if number == number.trunc() => number.to_int()
    String(value) => parse_int(value, default)
    _ => default
  }
}

///|
fn parse_int(value : String, default : Int) -> Int {
  let source = value.trim().to_owned()
  if source.is_empty() {
    return default
  }
  let mut index = 0
  let mut sign = 1
  if source.get_char(0) == Some('-') {
    sign = -1
    index = 1
  }
  let mut result = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return default
    }
    result = result * 10 + char.to_int() - '0'.to_int()
    index += 1
  }
  result * sign
}

///|
fn canonical(value : Json) -> String {
  match value {
    Null => "null"
    True => "true"
    False => "false"
    String(text) => Json::string(text).stringify()
    Number(number, repr~) =>
      match repr {
        Some(repr) => Json::number(number, repr~).stringify()
        None => Json::number(number).stringify()
      }
    Array(values) => "[" + values.map(canonical).join(",") + "]"
    Object(fields) => {
      let keys = fields.keys().to_array()
      keys.sort_by(fn(left, right) { left.lexical_compare(right) })
      "{" +
      keys
      .map(fn(key) {
        Json::string(key).stringify() +
        ":" +
        canonical(fields.get(key).unwrap())
      })
      .join(",") +
      "}"
    }
  }
}

///|
fn sql_literal(value : String) -> String {
  "'" +
  value.split("'").map(fn(part) { part.to_owned() }).to_array().join("''") +
  "'"
}

///|
fn secret_marker(key : String) -> Bool {
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
) -> Unit raise SqliteRehearsalError {
  match value {
    Object(fields) =>
      for key, child in fields {
        if secret_marker(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn file_hash(path : String) -> String raise SqliteRehearsalError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn load_records(
  stage_path : String,
) -> (String, String, Array[Record]) raise SqliteRehearsalError {
  let manifest_path = stage_path + ".manifest.json"
  let manifest = object(read_json(manifest_path), "staging manifest")
  let source_hash = text(field(Json::object(manifest), "source_sha256"))
  let output_hash = text(field(Json::object(manifest), "output_sha256"))
  if source_hash.length() != 64 || output_hash.length() != 64 {
    raise fail("staging manifest has an invalid hash")
  }
  if file_hash(stage_path) != output_hash {
    raise fail("staging hash mismatch")
  }
  let content = @fs.read_file_to_string(stage_path) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  let records : Array[Record] = []
  let seen : Map[String, Bool] = {}
  let mut line_number = 0
  for line_view in content.split("\n") {
    let line = line_view.to_owned()
    line_number += 1
    if !line.trim().is_empty() {
      let value = @json.parse(line) catch {
        _ =>
          raise fail("invalid staging JSON at line " + line_number.to_string())
      }
      ignore(object(value, "staging line " + line_number.to_string()))
      let record_type = text(field(value, "record_type"))
      let record_id = text(field(value, "record_id"))
      let source_id = text(field(value, "source_id"))
      let payload = field(value, "payload")
      if record_type.is_empty() || record_id.is_empty() || source_id.is_empty() {
        raise fail(
          "staging line missing identity at " + line_number.to_string(),
        )
      }
      if !record_type.has_prefix("legacy/raw/") {
        raise fail("non-raw record in staging line " + line_number.to_string())
      }
      if !source_id.has_prefix("erp:") {
        raise fail("non-ERP source in staging line " + line_number.to_string())
      }
      match payload {
        Object(_) | Array(_) => ()
        _ =>
          raise fail(
            "staging payload is not JSON data at line " +
            line_number.to_string(),
          )
      }
      if seen.get(source_id) is Some(_) {
        raise fail("duplicate source in staging: " + source_id)
      }
      seen.set(source_id, true)
      reject_secrets(payload, "payload")
      records.push({ record_type, record_id, source_id, payload })
    }
  }
  let tables = match manifest.get("tables") {
    Some(Array(values)) => values
    _ => raise fail("staging manifest tables are invalid")
  }
  let mut expected = 0
  for table in tables {
    expected += integer(field(table, "rows"), 0)
  }
  if expected != records.length() {
    raise fail("staging row count mismatch")
  }
  (source_hash, output_hash, records)
}

///|
fn parse_rows(path : String) -> Array[ExistingRow] raise SqliteRehearsalError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  let rows : Array[ExistingRow] = []
  for line_view in content.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 5 {
        raise fail("unexpected SQLite raw row")
      }
      rows.push({
        record_type: decode_hex(values[0]),
        record_id: decode_hex(values[1]),
        schema_version: parse_int(values[2], -1),
        payload: decode_hex(values[3]),
        source_id: decode_hex(values[4]),
      })
    }
  }
  rows
}

///|
fn decode_hex(value : String) -> String raise SqliteRehearsalError {
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
    let high = match value.get_char(index * 2) {
      Some(char) => digit(char).unwrap_or(-1)
      None => -1
    }
    let low = match value.get_char(index * 2 + 1) {
      Some(char) => digit(char).unwrap_or(-1)
      None => -1
    }
    if high < 0 || low < 0 {
      raise fail("invalid SQLite hexadecimal field")
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
fn hash_rows(rows : Array[ExistingRow]) -> String {
  let ordered = rows.copy()
  ordered.sort_by(fn(left, right) {
    let first = left.record_type.lexical_compare(right.record_type)
    if first != 0 {
      first
    } else {
      left.record_id.lexical_compare(right.record_id)
    }
  })
  let mut text = ""
  for row in ordered {
    text += Json::array([
        Json::string(row.record_type),
        Json::string(row.record_id),
        Json::number(
          row.schema_version.to_double(),
          repr=row.schema_version.to_string(),
        ),
        Json::string(row.payload),
        Json::string(row.source_id),
      ]).stringify() +
      "\n"
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(text)))
}

///|
fn schema_sql() -> String {
  "PRAGMA foreign_keys=ON;\n" +
  "CREATE TABLE IF NOT EXISTS company_schema(version INTEGER NOT NULL PRIMARY KEY, checksum VARCHAR(255) NOT NULL, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);\n" +
  "CREATE TABLE IF NOT EXISTS company_record(record_type VARCHAR(128) NOT NULL, record_id VARCHAR(255) NOT NULL, schema_version INTEGER NOT NULL, payload TEXT NOT NULL, source_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(record_type, record_id), UNIQUE(source_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_record_source_idx ON company_record(source_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_aggregate_projection(aggregate_type VARCHAR(128) NOT NULL, aggregate_id VARCHAR(255) NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, source_event_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(aggregate_type, aggregate_id, revision), UNIQUE(aggregate_type, aggregate_id, source_event_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_projection_event_idx ON company_aggregate_projection(source_event_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_accounting_event_link(event_id VARCHAR(255) NOT NULL PRIMARY KEY, source_type VARCHAR(128) NOT NULL, source_id VARCHAR(255) NOT NULL, journal_id VARCHAR(255) NOT NULL, principal_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(source_type, source_id), UNIQUE(journal_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_accounting_source_idx ON company_accounting_event_link(source_type, source_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_migration_receipt(run_id VARCHAR(255) NOT NULL PRIMARY KEY, source_snapshot_id VARCHAR(255) NOT NULL, target_schema_version INTEGER NOT NULL, mapping_version VARCHAR(255) NOT NULL, state VARCHAR(32) NOT NULL, baseline_hash VARCHAR(255) NOT NULL, applied_hash VARCHAR(255) NOT NULL, certified_at TIMESTAMP);\n" +
  "CREATE INDEX IF NOT EXISTS company_receipt_snapshot_idx ON company_migration_receipt(source_snapshot_id);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 1,'sha256:company-record-envelope-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=1);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 2,'sha256:aggregate-projection-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=2);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 3,'sha256:accounting-event-link-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=3);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 4,'sha256:migration-receipt-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=4);\n"
}

///|
fn write_prepare(
  stage : String,
  work_dir : String,
) -> Unit raise SqliteRehearsalError {
  let schema = schema_sql()
  let before = "SELECT coalesce(hex(record_type), ''), coalesce(hex(record_id), ''), schema_version, coalesce(hex(payload), ''), coalesce(hex(source_id), '') FROM company_record ORDER BY record_type, record_id;\n"
  let schema_check = "SELECT version FROM company_schema WHERE (version=1 AND checksum<>'sha256:company-record-envelope-v1') OR (version=2 AND checksum<>'sha256:aggregate-projection-v1') OR (version=3 AND checksum<>'sha256:accounting-event-link-v1') OR (version=4 AND checksum<>'sha256:migration-receipt-v1');\n"
  @fs.write_string_to_file(work_dir + "/schema.sql", schema) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/before.sql", before) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/schema-check.sql", schema_check) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  let content = @fs.read_file_to_string(stage) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/stage-copy.ndjson", content) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
}

///|
fn write_plan(
  stage : String,
  work_dir : String,
  before_path : String,
  run_id_option : String?,
) -> Unit raise SqliteRehearsalError {
  let (source_hash, _, records) = load_records(stage)
  let before = parse_rows(before_path)
  let baseline_hash = hash_rows(before)
  let existing : Map[String, ExistingRow] = {}
  let sources : Map[String, Bool] = {}
  for row in before {
    existing.set(row.record_type + "\u{1f}" + row.record_id, row)
    sources.set(row.source_id, true)
  }
  let simulated = before.copy()
  let mut sql = "BEGIN IMMEDIATE;\n" + schema_sql()
  let mut inserted = 0
  let mut preflight = "SELECT source_id FROM company_record WHERE "
  let mut first = true
  for record in records {
    let payload = canonical(record.payload)
    let key = record.record_type + "\u{1f}" + record.record_id
    let conflict = "(record_type=" +
      sql_literal(record.record_type) +
      " AND record_id=" +
      sql_literal(record.record_id) +
      " AND (schema_version<>4 OR payload<>" +
      sql_literal(payload) +
      " OR source_id<>" +
      sql_literal(record.source_id) +
      ")) OR (source_id=" +
      sql_literal(record.source_id) +
      " AND NOT (record_type=" +
      sql_literal(record.record_type) +
      " AND record_id=" +
      sql_literal(record.record_id) +
      "))"
    if !first {
      preflight += " OR "
    }
    preflight += conflict
    first = false
    let already = existing.get(key) is Some(_)
    sql += "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id, created_at) SELECT " +
      sql_literal(record.record_type) +
      "," +
      sql_literal(record.record_id) +
      ",4," +
      sql_literal(payload) +
      "," +
      sql_literal(record.source_id) +
      ",CURRENT_TIMESTAMP WHERE NOT EXISTS(SELECT 1 FROM company_record WHERE record_type=" +
      sql_literal(record.record_type) +
      " AND record_id=" +
      sql_literal(record.record_id) +
      ");\n"
    if !already {
      simulated.push({
        record_type: record.record_type,
        record_id: record.record_id,
        schema_version: 4,
        payload,
        source_id: record.source_id,
      })
      existing.set(key, {
        record_type: record.record_type,
        record_id: record.record_id,
        schema_version: 4,
        payload,
        source_id: record.source_id,
      })
      sources.set(record.source_id, true)
      inserted += 1
    }
  }
  preflight += ";\n"
  let applied_hash = hash_rows(simulated)
  let effective_run_id = run_id_option.unwrap_or(
    "raw-staging-" + source_hash[:16].to_owned(),
  )
  let source_snapshot_id = "erp-snapshot:" + source_hash
  let receipt_conflict = "SELECT run_id FROM company_migration_receipt WHERE run_id=" +
    sql_literal(effective_run_id) +
    " AND (source_snapshot_id<>" +
    sql_literal(source_snapshot_id) +
    " OR target_schema_version<>4 OR mapping_version<>'erp-raw-staging-v1' OR state<>'Applied' OR (applied_hash<>" +
    sql_literal(applied_hash) +
    " AND NOT (" +
    sql_literal(baseline_hash) +
    "=" +
    sql_literal(applied_hash) +
    " AND applied_hash=" +
    sql_literal(baseline_hash) +
    ")));\n"
  sql += "INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) SELECT " +
    sql_literal(effective_run_id) +
    "," +
    sql_literal(source_snapshot_id) +
    ",4,'erp-raw-staging-v1','Applied'," +
    sql_literal(baseline_hash) +
    "," +
    sql_literal(applied_hash) +
    ",CURRENT_TIMESTAMP WHERE NOT EXISTS(SELECT 1 FROM company_migration_receipt WHERE run_id=" +
    sql_literal(effective_run_id) +
    ");\nSELECT changes();\nCOMMIT;\n"
  @fs.write_string_to_file(work_dir + "/preflight.sql", preflight) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/receipt-check.sql", receipt_conflict) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/apply.sql", sql) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  @fs.write_string_to_file(
    work_dir + "/metadata.json",
    Json::object({
      "source_sha256": Json::string(source_hash),
      "source_snapshot_id": Json::string(source_snapshot_id),
      "run_id": Json::string(effective_run_id),
      "staged_rows": Json::number(
        records.length().to_double(),
        repr=records.length().to_string(),
      ),
      "inserted_rows": Json::number(
        inserted.to_double(),
        repr=inserted.to_string(),
      ),
      "baseline_hash": Json::string(baseline_hash),
      "applied_hash": Json::string(applied_hash),
    }).stringify(indent=2) +
    "\n",
  ) catch {
    error => raise SqliteRehearsalError::Io(error)
  }
}

///|
fn report(
  work_dir : String,
  after_path : String,
  integrity : String,
  schema_version : Int,
  record_count : Int,
  unique_sources : Int,
  receipt_count : Int,
  receipt_inserted : Bool,
  database : String,
  output : String,
) -> Unit raise SqliteRehearsalError {
  let metadata = object(read_json(work_dir + "/metadata.json"), "metadata")
  let after = parse_rows(after_path)
  let expected = integer(field(Json::object(metadata), "staged_rows"), -1)
  let applied_hash = text(field(Json::object(metadata), "applied_hash"))
  if integrity != "ok" ||
    schema_version != 4 ||
    record_count != expected ||
    unique_sources != record_count ||
    receipt_count != 1 ||
    hash_rows(after) != applied_hash {
    raise fail("durability verification failed after reopen")
  }
  let before = parse_rows(work_dir + "/before.rows")
  let report = Json::object({
    "database": Json::string(database),
    "source_sha256": field(Json::object(metadata), "source_sha256"),
    "run_id": field(Json::object(metadata), "run_id"),
    "schema_version": Json::number(
      schema_version.to_double(),
      repr=schema_version.to_string(),
    ),
    "staged_rows": Json::number(expected.to_double(), repr=expected.to_string()),
    "inserted_rows": Json::number(
      (after.length() - before.length()).to_double(),
      repr=(after.length() - before.length()).to_string(),
    ),
    "receipt_inserted": Json::boolean(receipt_inserted),
    "reopened_record_count": Json::number(
      record_count.to_double(),
      repr=record_count.to_string(),
    ),
    "unique_sources": Json::number(
      unique_sources.to_double(),
      repr=unique_sources.to_string(),
    ),
  })
  @fs.write_string_to_file(output, report.stringify(indent=2) + "\n") catch {
    error => raise SqliteRehearsalError::Io(error)
  }
  println(report.stringify())
}

///|
fn parse_bool(value : String) -> Bool {
  value.trim() == "1"
}

///|
fn run(args : Array[String]) -> Unit raise SqliteRehearsalError {
  if args.length() < 2 {
    raise fail("usage: sqlite_rehearsal <prepare|plan|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 => write_prepare(args[2], args[3])
    "plan" if args.length() >= 5 => {
      let run_id = if args.length() >= 6 { Some(args[5]) } else { None }
      write_plan(args[2], args[3], args[4], run_id)
    }
    "report" if args.length() >= 12 =>
      report(
        args[2],
        args[3],
        args[4],
        parse_int(args[5], -1),
        parse_int(args[6], -1),
        parse_int(args[7], -1),
        parse_int(args[8], -1),
        parse_bool(args[9]),
        args[10],
        args[11],
      )
    _ => raise fail("invalid sqlite rehearsal arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteRehearsalError::InvalidInput(message) => {
      println("company SQLite rehearsal failed: " + message)
      @sys.exit(1)
    }
    SqliteRehearsalError::Io(_) => {
      println("company SQLite rehearsal failed: filesystem error")
      @sys.exit(1)
    }
  }
}
