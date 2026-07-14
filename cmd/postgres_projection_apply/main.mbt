///|
/// Native MoonBit persistence boundary for a validated domain-promotion receipt.
///
/// This command does not promote or infer business state. It accepts only the
/// already validated native receipt, persists immutable aggregate revisions,
/// and records a cohort-scoped replay-safe migration receipt in PostgreSQL.
pub(all) suberror PostgresProjectionApplyError {
  InvalidInput(String)
  Io(@fs.IOError)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
struct ProjectionItem {
  source_table : String
  source_id : String
  target_type : String
  target_id : String
  target_candidate : Json
}

///|
struct ProjectionReceipt {
  source_snapshot_id : String
  mapping_version : String
  items : Array[ProjectionItem]
}

///|
fn fail(message : String) -> PostgresProjectionApplyError {
  PostgresProjectionApplyError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresProjectionApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresProjectionApplyError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse promotion receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresProjectionApplyError {
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
) -> Json raise PostgresProjectionApplyError {
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
) -> String raise PostgresProjectionApplyError {
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
) -> Array[Json] raise PostgresProjectionApplyError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
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
) -> Unit raise PostgresProjectionApplyError {
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
fn load_receipt(
  path : String,
) -> ProjectionReceipt raise PostgresProjectionApplyError {
  let root = object(read_json(path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected promotion receipt format")
  }
  if required_string(root, "state", "receipt") !=
    "promoted_through_domain_importers" {
    raise fail("promotion receipt is not domain-validated")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "receipt",
  )
  let mapping_version = required_string(root, "mapping_version", "receipt")
  let values = required_array(root, "accepted_items", "receipt")
  if values.is_empty() {
    raise fail("promotion receipt has no accepted items")
  }
  let items : Array[ProjectionItem] = []
  for index in 0..<values.length() {
    let path = "accepted_items[" + index.to_string() + "]"
    let item = object(values[index], path)
    let source_table = required_string(item, "source_table", path)
    let source_id = required_string(item, "source_id", path)
    let target_type = required_string(item, "target_type", path)
    let target_id = required_string(item, "target_id", path)
    let target_candidate = required(item, "target_candidate", path)
    match target_candidate {
      Object(_) => ()
      _ => raise fail("accepted item candidate is not an object at " + path)
    }
    reject_secrets(target_candidate, path + ".target_candidate")
    items.push({
      source_table,
      source_id,
      target_type,
      target_id,
      target_candidate,
    })
  }
  { source_snapshot_id, mapping_version, items }
}

///|
fn canonical_payload(
  receipt : ProjectionReceipt,
  item : ProjectionItem,
) -> Json {
  Json::object({
    "format": Json::string("moonproj.company.aggregate-projection.v1"),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "source_table": Json::string(item.source_table),
    "source_id": Json::string(item.source_id),
    "aggregate_type": Json::string(item.target_type),
    "aggregate_id": Json::string(item.target_id),
    "candidate": item.target_candidate,
  })
}

///|
fn event_id(receipt : ProjectionReceipt, item : ProjectionItem) -> String {
  let raw = receipt.source_snapshot_id +
    "|" +
    receipt.mapping_version +
    "|" +
    item.source_table +
    "|" +
    item.source_id +
    "|" +
    item.target_type +
    "|" +
    item.target_id
  "erp-promotion:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(raw)))
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
  receipt : ProjectionReceipt,
  path : String,
) -> Unit raise PostgresProjectionApplyError {
  let mut content = "aggregate_type,aggregate_id,payload,source_event_id\n"
  for item in receipt.items {
    content += csv_cell(item.target_type) +
      "," +
      csv_cell(item.target_id) +
      "," +
      csv_cell(canonical_payload(receipt, item).stringify()) +
      "," +
      csv_cell(event_id(receipt, item)) +
      "\n"
  }
  @fs.write_string_to_file(path, content) catch {
    error => raise PostgresProjectionApplyError::Io(error)
  }
}

///|
fn decode_hex(value : String) -> String raise PostgresProjectionApplyError {
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
fn parse_decimal(value : String) -> Int raise PostgresProjectionApplyError {
  if value.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  let mut start = 0
  let mut sign = 1
  if value.get_char(0) == Some('-') {
    sign = -1
    start = 1
  }
  if start == value.length() {
    raise fail("invalid integer: " + value)
  }
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
fn fields(
  line : String,
  expected : Int,
) -> Array[String] raise PostgresProjectionApplyError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  values
}

///|
fn filtered_hash_text(
  output : String,
  expected : Int,
) -> String raise PostgresProjectionApplyError {
  let mut text = ""
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, expected)
      let values : Array[Json] = []
      for index in 0..<row.length() {
        if index == 2 {
          values.push(
            Json::number(
              parse_decimal(row[index].trim().to_owned()).to_double(),
            ),
          )
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
async fn logical_projection_hash(
  connection : @postgres.Connection,
  receipt : ProjectionReceipt,
) -> String raise PostgresProjectionApplyError {
  let output = @postgres.run_sql(
    connection,
    "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE payload->>'source_snapshot_id' = " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    " AND payload->>'mapping_version' = " +
    @postgres.sql_literal(receipt.mapping_version) +
    " ORDER BY aggregate_type, aggregate_id, revision",
  ) catch {
    error => raise PostgresProjectionApplyError::Database(error)
  }
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(filtered_hash_text(output, 5))),
  )
}

///|
fn parse_last_count(output : String) -> Int raise PostgresProjectionApplyError {
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
    None =>
      raise fail(
        "PostgreSQL projection apply did not return an inserted-row count",
      )
  }
}

///|
async fn apply_rows(
  connection : @postgres.Connection,
  csv_path : String,
  sql_path : String,
) -> Int raise PostgresProjectionApplyError {
  let sql = "BEGIN;\nLOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE;\nCREATE TEMP TABLE staging_company_projection (aggregate_type VARCHAR(128) NOT NULL, aggregate_id VARCHAR(255) NOT NULL, payload JSONB NOT NULL, source_event_id VARCHAR(255) NOT NULL) ON COMMIT DROP;\n\\copy staging_company_projection(aggregate_type, aggregate_id, payload, source_event_id) FROM " +
    @postgres.sql_literal(csv_path) +
    " WITH (FORMAT csv, HEADER true);\nDO $$ BEGIN IF EXISTS (SELECT 1 FROM staging_company_projection s JOIN company_aggregate_projection p ON p.source_event_id = s.source_event_id WHERE p.aggregate_type <> s.aggregate_type OR p.aggregate_id <> s.aggregate_id OR p.payload <> s.payload) THEN RAISE EXCEPTION 'company aggregate projection event conflict'; END IF; END $$;\nWITH pending AS (SELECT s.aggregate_type, s.aggregate_id, s.payload, s.source_event_id, COALESCE(existing.max_revision, 0) + row_number() OVER (PARTITION BY s.aggregate_type, s.aggregate_id ORDER BY s.source_event_id)::integer AS revision FROM staging_company_projection s LEFT JOIN (SELECT aggregate_type, aggregate_id, max(revision) AS max_revision FROM company_aggregate_projection GROUP BY aggregate_type, aggregate_id) existing ON existing.aggregate_type = s.aggregate_type AND existing.aggregate_id = s.aggregate_id WHERE NOT EXISTS (SELECT 1 FROM company_aggregate_projection p WHERE p.source_event_id = s.source_event_id)), inserted AS (INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT aggregate_type, aggregate_id, revision, payload, source_event_id FROM pending ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  @fs.write_string_to_file(sql_path, sql) catch {
    error => raise PostgresProjectionApplyError::Io(error)
  }
  let output = @postgres.run_file(connection, sql_path) catch {
    error => raise PostgresProjectionApplyError::Database(error)
  }
  parse_last_count(output)
}

///|
async fn finalize_receipt(
  connection : @postgres.Connection,
  receipt : ProjectionReceipt,
  run_id : String,
  baseline_hash : String,
  applied_hash : String,
) -> Bool raise PostgresProjectionApplyError {
  let mapping = "domain:" + receipt.mapping_version
  let sql = "BEGIN;\nDO $$ DECLARE existing company_migration_receipt%ROWTYPE; BEGIN SELECT * INTO existing FROM company_migration_receipt WHERE run_id = " +
    @postgres.sql_literal(run_id) +
    "; IF FOUND THEN IF existing.source_snapshot_id <> " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    " OR existing.target_schema_version <> 4 OR existing.mapping_version <> " +
    @postgres.sql_literal(mapping) +
    " OR existing.state <> 'Projected' OR existing.applied_hash <> " +
    @postgres.sql_literal(applied_hash) +
    " THEN RAISE EXCEPTION 'projection migration receipt conflict'; END IF; END IF; END $$;\nWITH inserted AS (INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) VALUES (" +
    @postgres.sql_literal(run_id) +
    ", " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    ", 4, " +
    @postgres.sql_literal(mapping) +
    ", 'Projected', " +
    @postgres.sql_literal(baseline_hash) +
    ", " +
    @postgres.sql_literal(applied_hash) +
    ", CURRENT_TIMESTAMP) ON CONFLICT (run_id) DO NOTHING RETURNING 1) SELECT count(*)::text FROM inserted;\nCOMMIT;\n"
  let output = @postgres.run_sql(connection, sql) catch {
    error => raise PostgresProjectionApplyError::Database(error)
  }
  parse_last_count(output) == 1
}

///|
async fn verify(
  connection : @postgres.Connection,
  run_id : String,
) -> (Int, Int) raise PostgresProjectionApplyError {
  let output = @postgres.run_sql(
    connection,
    "SELECT (SELECT count(*) FROM company_aggregate_projection)::text, (SELECT count(*) FROM company_migration_receipt WHERE run_id = " +
    @postgres.sql_literal(run_id) +
    ");",
  ) catch {
    error => raise PostgresProjectionApplyError::Database(error)
  }
  let row = fields(output.trim().to_owned(), 2)
  let count = parse_decimal(row[0].trim().to_owned())
  let receipts = parse_decimal(row[1].trim().to_owned())
  if receipts != 1 {
    raise fail("PostgreSQL projection durability verification failed")
  }
  (count, receipts)
}

///|
fn option(
  args : Array[String],
  name : String,
) -> String? raise PostgresProjectionApplyError {
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
  receipt_path : String,
  schema_path : String,
  connection : @postgres.Connection,
  database : String,
) -> Json raise PostgresProjectionApplyError {
  let receipt = load_receipt(receipt_path)
  let seed = receipt.source_snapshot_id + "|" + receipt.mapping_version
  let run_id = "postgres-domain-projection-" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(seed)))[:16].to_owned()
  let _ = @postgres.run_file(connection, schema_path) catch {
    error => raise PostgresProjectionApplyError::Database(error)
  }
  let result = @fsx.with_temporary_directory(
    "moonproj-postgres-projection-XXXXXX",
    directory => {
      let csv_path = directory + "/projection.csv"
      let sql_path = directory + "/apply-company-projections.sql"
      write_stage_csv(receipt, csv_path)
      let baseline_hash = logical_projection_hash(connection, receipt)
      let inserted = apply_rows(connection, csv_path, sql_path)
      let applied_hash = logical_projection_hash(connection, receipt)
      let receipt_inserted = finalize_receipt(
        connection, receipt, run_id, baseline_hash, applied_hash,
      )
      let (projection_count, _) = verify(connection, run_id)
      Json::object({
        "database": Json::string(database),
        "run_id": Json::string(run_id),
        "source_snapshot_id": Json::string(receipt.source_snapshot_id),
        "mapping_version": Json::string(receipt.mapping_version),
        "inserted_projections": Json::number(inserted.to_double()),
        "projection_count": Json::number(projection_count.to_double()),
        "receipt_inserted": Json::boolean(receipt_inserted),
        "baseline_hash": Json::string(baseline_hash),
        "applied_hash": Json::string(applied_hash),
      })
    },
  ) catch {
    error =>
      raise fail(
        "temporary PostgreSQL projection workspace failed: \{to_repr(error)}",
      )
  }
  result
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(
      "usage: postgres_projection_apply <receipt> [--schema path] [--psql path] [--host host] [--port port] [--user user] [--database database]",
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
      println("company PostgreSQL projection apply failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
