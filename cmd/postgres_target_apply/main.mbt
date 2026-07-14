///|
/// Native MoonBit PostgreSQL raw-staging apply boundary.
///
/// The command validates the credential-safe NDJSON staging contract, writes
/// a temporary CSV consumed by PostgreSQL's `\copy`, applies the immutable raw
/// envelope transaction, and finalizes a migration receipt. Shell remains
/// orchestration only; the validation, SQL contract, and result envelope live
/// in MoonBit.
pub(all) suberror PostgresTargetApplyError {
  InvalidInput(String)
  Io(@fs.IOError)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
struct RawRecord {
  record_type : String
  record_id : String
  source_id : String
  payload : Json
}

///|
struct Stage {
  source_hash : String
  records : Array[RawRecord]
}

///|
fn fail(message : String) -> PostgresTargetApplyError {
  PostgresTargetApplyError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresTargetApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresTargetApplyError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresTargetApplyError {
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
) -> Json raise PostgresTargetApplyError {
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
) -> String raise PostgresTargetApplyError {
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
) -> Array[Json] raise PostgresTargetApplyError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise PostgresTargetApplyError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn is_sha256(value : String) -> Bool {
  value.length() == 64 &&
  value.iter().all(fn(char) { char.is_ascii_hexdigit() })
}

///|
fn sha256_file(path : String) -> String raise PostgresTargetApplyError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    error => raise PostgresTargetApplyError::Io(error)
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn contains_secret_marker(key : String) -> Bool {
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
) -> Unit raise PostgresTargetApplyError {
  match value {
    Object(fields) =>
      fields.each((key, child) => {
        if contains_secret_marker(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      })
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn load_stage(stage_path : String) -> Stage raise PostgresTargetApplyError {
  let manifest_path = stage_path + ".manifest.json"
  let manifest = object(read_json(manifest_path), "manifest")
  let source_hash = match
    required_string(manifest, "source_sha256", "manifest") {
    value if is_sha256(value) => value
    _ => raise fail("staging manifest has an invalid source hash")
  }
  let expected_output_hash = required_string(
    manifest, "output_sha256", "manifest",
  )
  let actual_output_hash = sha256_file(stage_path)
  if expected_output_hash != actual_output_hash {
    raise fail(
      "staging hash mismatch: expected " +
      expected_output_hash +
      ", got " +
      actual_output_hash,
    )
  }
  let content = @fs.read_file_to_string(stage_path) catch {
    error => raise PostgresTargetApplyError::Io(error)
  }
  let lines = content.split("\n").to_array()
  let records : Array[RawRecord] = []
  let seen_sources : Array[String] = []
  for line_index in 0..<lines.length() {
    let line = lines[line_index].to_owned()
    if !line.trim().is_empty() {
      let path = "staging line " + (line_index + 1).to_string()
      let record = object(
        @json.parse(line) catch {
          _ => raise fail("invalid staging JSON at " + path)
        },
        path,
      )
      let record_type = required_string(record, "record_type", path)
      let record_id = required_string(record, "record_id", path)
      let source_id = required_string(record, "source_id", path)
      if !record_type.has_prefix("legacy/raw/") {
        raise fail("non-raw record in " + path)
      }
      if !source_id.has_prefix("erp:") {
        raise fail("non-ERP source in " + path)
      }
      let payload = required(record, "payload", path)
      match payload {
        Object(_) | Array(_) => ()
        _ => raise fail("staging payload is not JSON data at " + path)
      }
      if seen_sources.contains(source_id) {
        raise fail("duplicate source in staging: " + source_id)
      }
      seen_sources.push(source_id)
      reject_secrets(payload, path + ".payload")
      records.push({ record_type, record_id, source_id, payload })
    }
  }
  let mut expected_rows = 0
  for index in 0..<required_array(manifest, "tables", "manifest").length() {
    let entry_path = "manifest.tables[" + index.to_string() + "]"
    let entry = object(
      required_array(manifest, "tables", "manifest")[index],
      entry_path,
    )
    let rows = required_int(entry, "rows", entry_path)
    if rows < 0 {
      raise fail("negative staging row count at " + entry_path)
    }
    expected_rows += rows
  }
  if expected_rows != records.length() {
    raise fail(
      "staging row count mismatch: manifest " +
      expected_rows.to_string() +
      ", file " +
      records.length().to_string(),
    )
  }
  { source_hash, records }
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
  stage : Stage,
  path : String,
) -> Unit raise PostgresTargetApplyError {
  let mut content = "record_type,record_id,schema_version,payload,source_id\n"
  for record in stage.records {
    content += csv_cell(record.record_type) +
      "," +
      csv_cell(record.record_id) +
      ",4," +
      csv_cell(record.payload.stringify()) +
      "," +
      csv_cell(record.source_id) +
      "\n"
  }
  @fs.write_string_to_file(path, content) catch {
    error => raise PostgresTargetApplyError::Io(error)
  }
}

///|
fn decode_hex(value : String) -> String raise PostgresTargetApplyError {
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
) -> Array[String] raise PostgresTargetApplyError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  values
}

///|
fn parse_decimal(value : String) -> Int raise PostgresTargetApplyError {
  if value.is_empty() {
    raise fail("expected integer")
  }
  let mut sign = 1
  let mut start = 0
  if value.get_char(0) == Some('-') {
    sign = -1
    start = 1
  }
  if start == value.length() {
    raise fail("invalid integer: " + value)
  }
  let mut result = 0
  for index in start..<value.length() {
    let char = match value.get_char(index) {
      Some(char) => char
      None => raise fail("invalid integer: " + value)
    }
    if char < '0' || char > '9' {
      raise fail("invalid integer: " + value)
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  result * sign
}

///|
fn row_hash_text(
  output : String,
  expected : Int,
) -> String raise PostgresTargetApplyError {
  let mut text = ""
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, expected)
      let values : Array[Json] = []
      for index in 0..<row.length() {
        if index == 2 {
          let number = parse_decimal(row[index].trim().to_owned())
          values.push(Json::number(number.to_double()))
        } else {
          values.push(Json::string(decode_hex(row[index])))
        }
      }
      text += Json::array(values).stringify() + "\n"
    }
  }
  text
}

///|
async fn logical_record_hash(
  connection : @postgres.Connection,
) -> String raise PostgresTargetApplyError {
  let output = @postgres.run_sql(
    connection, "SELECT encode(convert_to(record_type, 'UTF8'), 'hex'), encode(convert_to(record_id, 'UTF8'), 'hex'), schema_version::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex') FROM company_record ORDER BY record_type, record_id",
  ) catch {
    error => raise PostgresTargetApplyError::Database(error)
  }
  let text = row_hash_text(output, 5)
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(text)))
}

///|
async fn schema(
  connection : @postgres.Connection,
  path : String,
) -> Unit raise PostgresTargetApplyError {
  let _ = @postgres.run_file(connection, path) catch {
    error => raise PostgresTargetApplyError::Database(error)
  }
  ()
}

///|
async fn apply_rows(
  connection : @postgres.Connection,
  csv_path : String,
  sql_path : String,
) -> Int raise PostgresTargetApplyError {
  let copy_path = @postgres.sql_literal(csv_path)
  let sql = "BEGIN;\n" +
    "CREATE TEMP TABLE staging_company_record (record_type VARCHAR(128) NOT NULL, record_id VARCHAR(255) NOT NULL, schema_version INTEGER NOT NULL, payload JSONB NOT NULL, source_id VARCHAR(255) NOT NULL) ON COMMIT DROP;\n" +
    "\\copy staging_company_record(record_type, record_id, schema_version, payload, source_id) FROM " +
    copy_path +
    " WITH (FORMAT csv, HEADER true);\n" +
    "DO $$ BEGIN IF EXISTS (SELECT 1 FROM staging_company_record s JOIN company_record r ON r.record_type = s.record_type AND r.record_id = s.record_id WHERE r.schema_version <> s.schema_version OR r.payload <> s.payload OR r.source_id <> s.source_id) THEN RAISE EXCEPTION 'company_record identity conflict'; END IF; IF EXISTS (SELECT 1 FROM staging_company_record s JOIN company_record r ON r.source_id = s.source_id WHERE r.record_type <> s.record_type OR r.record_id <> s.record_id) THEN RAISE EXCEPTION 'company_record source conflict'; END IF; END $$;\n" +
    "WITH inserted AS (INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) SELECT record_type, record_id, schema_version, payload, source_id FROM staging_company_record ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  @fs.write_string_to_file(sql_path, sql) catch {
    error => raise PostgresTargetApplyError::Io(error)
  }
  let output = @postgres.run_file(connection, sql_path) catch {
    error => raise PostgresTargetApplyError::Database(error)
  }
  parse_last_count(output)
}

///|
fn parse_last_count(output : String) -> Int raise PostgresTargetApplyError {
  let mut result : Int? = None
  for line_view in output.split("\n") {
    let line = line_view.trim().to_owned()
    if !line.is_empty() {
      let value = parse_decimal(line) catch { _ => continue }
      if value >= 0 {
        result = Some(value)
      }
    }
  }
  match result {
    Some(value) => value
    None => raise fail("PostgreSQL apply did not return an inserted-row count")
  }
}

///|
async fn finalize_receipt(
  connection : @postgres.Connection,
  run_id : String,
  source_snapshot_id : String,
  baseline_hash : String,
  applied_hash : String,
) -> Bool raise PostgresTargetApplyError {
  let sql = "BEGIN;\n" +
    "DO $$ DECLARE existing company_migration_receipt%ROWTYPE; BEGIN SELECT * INTO existing FROM company_migration_receipt WHERE run_id = " +
    @postgres.sql_literal(run_id) +
    "; IF FOUND THEN IF existing.source_snapshot_id <> " +
    @postgres.sql_literal(source_snapshot_id) +
    " OR existing.target_schema_version <> 4 OR existing.mapping_version <> 'erp-raw-staging-v1' OR existing.state <> 'Applied' OR existing.applied_hash <> " +
    @postgres.sql_literal(applied_hash) +
    " THEN RAISE EXCEPTION 'migration receipt conflict'; END IF; END IF; END $$;\n" +
    "WITH inserted AS (INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) VALUES (" +
    @postgres.sql_literal(run_id) +
    ", " +
    @postgres.sql_literal(source_snapshot_id) +
    ", 4, 'erp-raw-staging-v1', 'Applied', " +
    @postgres.sql_literal(baseline_hash) +
    ", " +
    @postgres.sql_literal(applied_hash) +
    ", CURRENT_TIMESTAMP) ON CONFLICT (run_id) DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  let output = @postgres.run_sql(connection, sql) catch {
    error => raise PostgresTargetApplyError::Database(error)
  }
  parse_last_count(output) == 1
}

///|
async fn verify(
  connection : @postgres.Connection,
  run_id : String,
  expected_records : Int,
) -> (Int, Int, Int, Int, Int) raise PostgresTargetApplyError {
  let output = @postgres.run_sql(
    connection,
    "SELECT (SELECT max(version) FROM company_schema)::text, (SELECT count(*) FROM company_schema)::text, (SELECT count(*) FROM company_record)::text, (SELECT count(DISTINCT source_id) FROM company_record)::text, (SELECT count(*) FROM company_migration_receipt WHERE run_id = " +
    @postgres.sql_literal(run_id) +
    ");",
  ) catch {
    error => raise PostgresTargetApplyError::Database(error)
  }
  let line = output.trim().to_owned()
  let row = fields(line, 5)
  let values : Array[Int] = []
  for item in row {
    values.push(parse_decimal(item.trim().to_owned()))
  }
  if values[0] != 4 ||
    values[1] != 4 ||
    values[2] != expected_records ||
    values[3] != values[2] ||
    values[4] != 1 {
    raise fail("PostgreSQL durability verification failed")
  }
  (values[0], values[1], values[2], values[3], values[4])
}

///|
fn option(
  args : Array[String],
  name : String,
) -> String? raise PostgresTargetApplyError {
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
async fn run(
  stage_path : String,
  schema_path : String,
  connection : @postgres.Connection,
  run_id_override : String?,
) -> Json raise PostgresTargetApplyError {
  let stage = load_stage(stage_path)
  let run_id = run_id_override.unwrap_or(
    "raw-staging-" + stage.source_hash[:16].to_owned(),
  )
  schema(connection, schema_path)
  let result = @fsx.with_temporary_directory("moonproj-postgres-XXXXXX", directory => {
    apply_in_directory(stage, connection, run_id, directory)
  }) catch {
    error =>
      raise fail(
        "temporary PostgreSQL apply workspace failed: \{to_repr(error)}",
      )
  }
  result
}

///|
async fn apply_in_directory(
  stage : Stage,
  connection : @postgres.Connection,
  run_id : String,
  directory : String,
) -> Json raise PostgresTargetApplyError {
  let csv_path = directory + "/company-records.csv"
  let sql_path = directory + "/apply-company-records.sql"
  write_stage_csv(stage, csv_path)
  let baseline_hash = logical_record_hash(connection)
  let inserted = apply_rows(connection, csv_path, sql_path)
  let applied_hash = logical_record_hash(connection)
  let receipt_inserted = finalize_receipt(
    connection,
    run_id,
    "erp-snapshot:" + stage.source_hash,
    baseline_hash,
    applied_hash,
  )
  let (schema_version, _, record_count, unique_sources, _) = verify(
    connection,
    run_id,
    stage.records.length(),
  )
  Json::object({
    "target": Json::string("postgresql"),
    "source_sha256": Json::string(stage.source_hash),
    "run_id": Json::string(run_id),
    "schema_version": Json::number(schema_version.to_double()),
    "staged_rows": Json::number(stage.records.length().to_double()),
    "inserted_rows": Json::number(inserted.to_double()),
    "receipt_inserted": Json::boolean(receipt_inserted),
    "reopened_record_count": Json::number(record_count.to_double()),
    "unique_sources": Json::number(unique_sources.to_double()),
    "baseline_hash": Json::string(baseline_hash),
    "applied_hash": Json::string(applied_hash),
  })
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(
      "usage: postgres_target_apply <stage> [--schema path] [--psql path] [--host host] [--port port] [--user user] [--database database] [--run-id id]",
    )
    @sys.exit(2)
  }
  let schema_path = option(args, "--schema").unwrap_or(
    "scripts/postgres_target_schema.sql",
  )
  let connection = @postgres.connection_from_env().with_overrides(
    psql=option(args, "--psql"),
    host=option(args, "--host"),
    port=option(args, "--port"),
    user=option(args, "--user"),
    database=option(args, "--database"),
  )
  let report = run(args[1], schema_path, connection, option(args, "--run-id")) catch {
    error => {
      println("company PostgreSQL target apply failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
