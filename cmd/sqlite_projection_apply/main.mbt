///|
pub(all) suberror SqliteProjectionApplyError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct ProjectionItem {
  source_table : String
  source_id : String
  target_type : String
  target_id : String
  candidate : Json
  event_id : String
}

///|
struct Receipt {
  source_snapshot_id : String
  mapping_version : String
  items : Array[ProjectionItem]
}

///|
struct ProjectionRow {
  aggregate_type : String
  aggregate_id : String
  revision : Int
  payload : String
  source_event_id : String
}

///|
fn fail(message : String) -> SqliteProjectionApplyError {
  SqliteProjectionApplyError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteProjectionApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteProjectionApplyError {
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
) -> Json raise SqliteProjectionApplyError {
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
) -> String raise SqliteProjectionApplyError {
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
) -> Array[Json] raise SqliteProjectionApplyError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
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
) -> Unit raise SqliteProjectionApplyError {
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
fn event_id(
  snapshot : String,
  mapping : String,
  source_table : String,
  source_id : String,
  target_type : String,
  target_id : String,
) -> String {
  let raw = snapshot +
    "|" +
    mapping +
    "|" +
    source_table +
    "|" +
    source_id +
    "|" +
    target_type +
    "|" +
    target_id
  "erp-promotion:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(raw)))
}

///|
fn load_receipt(path : String) -> Receipt raise SqliteProjectionApplyError {
  let root = object(read_json(path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected promotion receipt format")
  }
  if required_string(root, "state", "receipt") !=
    "promoted_through_domain_importers" {
    raise fail("promotion receipt is not domain-validated")
  }
  let snapshot = required_string(root, "source_snapshot_id", "receipt")
  let mapping = required_string(root, "mapping_version", "receipt")
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
    let candidate = required(item, "target_candidate", path)
    match candidate {
      Object(_) => ()
      _ => raise fail("accepted item candidate is not an object at " + path)
    }
    reject_secrets(candidate, path + ".target_candidate")
    items.push({
      source_table,
      source_id,
      target_type,
      target_id,
      candidate,
      event_id: event_id(
        snapshot, mapping, source_table, source_id, target_type, target_id,
      ),
    })
  }
  { source_snapshot_id: snapshot, mapping_version: mapping, items }
}

///|
fn canonical_payload(receipt : Receipt, item : ProjectionItem) -> String {
  canonical(
    Json::object({
      "format": Json::string("moonproj.company.aggregate-projection.v1"),
      "source_snapshot_id": Json::string(receipt.source_snapshot_id),
      "mapping_version": Json::string(receipt.mapping_version),
      "source_table": Json::string(item.source_table),
      "source_id": Json::string(item.source_id),
      "aggregate_type": Json::string(item.target_type),
      "aggregate_id": Json::string(item.target_id),
      "candidate": item.candidate,
    }),
  )
}

///|
fn decode_hex(value : String) -> String raise SqliteProjectionApplyError {
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
fn parse_rows(
  path : String,
) -> Array[ProjectionRow] raise SqliteProjectionApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  let result : Array[ProjectionRow] = []
  for line_view in content.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 5 {
        raise fail("unexpected SQLite projection row")
      }
      let revision = parse_int(values[2])
      result.push({
        aggregate_type: decode_hex(values[0]),
        aggregate_id: decode_hex(values[1]),
        revision,
        payload: decode_hex(values[3]),
        source_event_id: decode_hex(values[4]),
      })
    }
  }
  result
}

///|
fn parse_revisions(
  path : String,
) -> Map[String, Int] raise SqliteProjectionApplyError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  let result : Map[String, Int] = {}
  for line_view in content.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 3 {
        raise fail("unexpected SQLite revision row")
      }
      result.set(
        decode_hex(values[0]) + "\u{1f}" + decode_hex(values[1]),
        parse_int(values[2]),
      )
    }
  }
  result
}

///|
fn parse_int(value : String) -> Int raise SqliteProjectionApplyError {
  let source = value.trim().to_owned()
  if source.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  let mut index = 0
  let mut sign = 1
  if source.get_char(0) == Some('-') {
    sign = -1
    index = 1
  }
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      raise fail("invalid integer: " + source)
    }
    result = result * 10 + char.to_int() - '0'.to_int()
    index += 1
  }
  result * sign
}

///|
fn row_sort(left : ProjectionRow, right : ProjectionRow) -> Int {
  let first = left.aggregate_type.lexical_compare(right.aggregate_type)
  if first != 0 {
    first
  } else {
    let second = left.aggregate_id.lexical_compare(right.aggregate_id)
    if second != 0 {
      second
    } else {
      left.revision.compare(right.revision)
    }
  }
}

///|
fn hash_rows(rows : Array[ProjectionRow]) -> String {
  let sorted = rows.copy()
  sorted.sort_by(row_sort)
  let mut text = ""
  for row in sorted {
    text += Json::array([
        Json::string(row.aggregate_type),
        Json::string(row.aggregate_id),
        Json::number(row.revision.to_double(), repr=row.revision.to_string()),
        Json::string(row.payload),
        Json::string(row.source_event_id),
      ]).stringify() +
      "\n"
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(text)))
}

///|
fn json_metadata(
  receipt : Receipt,
  run_id : String,
  baseline_hash : String,
  applied_hash : String,
) -> Json {
  Json::object({
    "run_id": Json::string(run_id),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "baseline_hash": Json::string(baseline_hash),
    "applied_hash": Json::string(applied_hash),
  })
}

///|
fn write_query_files(
  receipt : Receipt,
  work_dir : String,
) -> Unit raise SqliteProjectionApplyError {
  let mut preflight = "SELECT source_event_id FROM company_aggregate_projection WHERE source_event_id IN ("
  let mut first = true
  for item in receipt.items {
    if !first {
      preflight += ","
    }
    preflight += sql_literal(item.event_id)
    first = false
  }
  preflight += ") AND ("
  first = true
  for item in receipt.items {
    if !first {
      preflight += " OR "
    }
    let payload = canonical_payload(receipt, item)
    preflight += "(source_event_id=" +
      sql_literal(item.event_id) +
      " AND (aggregate_type<>" +
      sql_literal(item.target_type) +
      " OR aggregate_id<>" +
      sql_literal(item.target_id) +
      " OR payload<>" +
      sql_literal(payload) +
      "))"
    first = false
  }
  preflight += ");\n"
  let before = "SELECT coalesce(hex(aggregate_type), ''), coalesce(hex(aggregate_id), ''), revision, coalesce(hex(payload), ''), coalesce(hex(source_event_id), '') FROM company_aggregate_projection WHERE json_extract(payload, '$.source_snapshot_id')=" +
    sql_literal(receipt.source_snapshot_id) +
    " AND json_extract(payload, '$.mapping_version')=" +
    sql_literal(receipt.mapping_version) +
    " ORDER BY aggregate_type, aggregate_id, revision;\n"
  let revisions = "SELECT coalesce(hex(aggregate_type), ''), coalesce(hex(aggregate_id), ''), coalesce(max(revision), 0) FROM company_aggregate_projection GROUP BY aggregate_type, aggregate_id ORDER BY aggregate_type, aggregate_id;\n"
  @fs.write_string_to_file(work_dir + "/preflight.sql", preflight) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/before.sql", before) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  @fs.write_string_to_file(work_dir + "/revisions.sql", revisions) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
}

///|
fn write_plan(
  receipt : Receipt,
  work_dir : String,
  before_path : String,
  revisions_path : String,
) -> Unit raise SqliteProjectionApplyError {
  let before = parse_rows(before_path)
  let revisions = parse_revisions(revisions_path)
  let baseline_hash = hash_rows(before)
  let existing_events : Map[String, Bool] = {}
  for row in before {
    existing_events.set(row.source_event_id, true)
  }
  let simulated = before.copy()
  let next_revisions = revisions.copy()
  let mut sql = "BEGIN IMMEDIATE;\nPRAGMA foreign_keys=ON;\n"
  for item in receipt.items {
    let already = existing_events.get(item.event_id) is Some(_)
    let revision_key = item.target_type + "\u{1f}" + item.target_id
    let revision = next_revisions.get(revision_key).unwrap_or(0) + 1
    let payload = canonical_payload(receipt, item)
    sql += "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id, created_at) SELECT " +
      sql_literal(item.target_type) +
      "," +
      sql_literal(item.target_id) +
      "," +
      revision.to_string() +
      "," +
      sql_literal(payload) +
      "," +
      sql_literal(item.event_id) +
      ",CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM company_aggregate_projection WHERE source_event_id=" +
      sql_literal(item.event_id) +
      ");\n"
    if !already {
      simulated.push({
        aggregate_type: item.target_type,
        aggregate_id: item.target_id,
        revision,
        payload,
        source_event_id: item.event_id,
      })
      existing_events.set(item.event_id, true)
      next_revisions.set(revision_key, revision)
    }
  }
  let applied_hash = hash_rows(simulated)
  let seed = receipt.source_snapshot_id + "|" + receipt.mapping_version
  let run_id = "domain-projection-" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(seed)))[:16].to_owned()
  let mapping = "domain:" + receipt.mapping_version
  let receipt_check = "SELECT run_id FROM company_migration_receipt WHERE run_id=" +
    sql_literal(run_id) +
    " AND (source_snapshot_id<>" +
    sql_literal(receipt.source_snapshot_id) +
    " OR target_schema_version<>4 OR mapping_version<>" +
    sql_literal(mapping) +
    " OR state<>'Projected' OR applied_hash<>" +
    sql_literal(applied_hash) +
    ");\n"
  @fs.write_string_to_file(work_dir + "/receipt-check.sql", receipt_check) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  sql += "INSERT INTO company_migration_receipt(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) SELECT " +
    sql_literal(run_id) +
    "," +
    sql_literal(receipt.source_snapshot_id) +
    ",4," +
    sql_literal(mapping) +
    ",'Projected'," +
    sql_literal(baseline_hash) +
    "," +
    sql_literal(applied_hash) +
    ",CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM company_migration_receipt WHERE run_id=" +
    sql_literal(run_id) +
    ");\nSELECT changes();\nCOMMIT;\n"
  @fs.write_string_to_file(work_dir + "/apply.sql", sql) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  @fs.write_string_to_file(
    work_dir + "/metadata.json",
    json_metadata(receipt, run_id, baseline_hash, applied_hash).stringify(
      indent=2,
    ) +
    "\n",
  ) catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
}

///|
fn report(
  work_dir : String,
  after_path : String,
  integrity : String,
  projection_count : Int,
  receipt_count : Int,
  receipt_inserted : Bool,
  database : String,
  output_path : String,
) -> Unit raise SqliteProjectionApplyError {
  let metadata = object(read_json(work_dir + "/metadata.json"), "metadata")
  let after = parse_rows(after_path)
  let applied_hash = required_string(metadata, "applied_hash", "metadata")
  if integrity != "ok" {
    raise fail("projection durability verification failed")
  }
  if receipt_count != 1 {
    raise fail("projection durability verification failed")
  }
  if hash_rows(after) != applied_hash {
    raise fail("projection hash verification failed")
  }
  let before = parse_rows(work_dir + "/before.rows")
  let run_id = required_string(metadata, "run_id", "metadata")
  let source = required_string(metadata, "source_snapshot_id", "metadata")
  let mapping = required_string(metadata, "mapping_version", "metadata")
  let report = Json::object({
    "database": Json::string(database),
    "run_id": Json::string(run_id),
    "source_snapshot_id": Json::string(source),
    "mapping_version": Json::string(mapping),
    "inserted_projections": Json::number(
      (after.length() - before.length()).to_double(),
      repr=(after.length() - before.length()).to_string(),
    ),
    "projection_count": Json::number(
      projection_count.to_double(),
      repr=projection_count.to_string(),
    ),
    "receipt_inserted": Json::boolean(receipt_inserted),
    "integrity": Json::string(integrity),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise SqliteProjectionApplyError::Io(error)
  }
  println(report.stringify())
}

///|
fn parse_bool(value : String) -> Bool {
  value.trim() == "1"
}

///|
fn run(args : Array[String]) -> Unit raise SqliteProjectionApplyError {
  if args.length() < 2 {
    raise fail("usage: sqlite_projection_apply <prepare|plan|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 => {
      let receipt = load_receipt(args[2])
      write_query_files(receipt, args[3])
    }
    "plan" if args.length() >= 6 => {
      let receipt = load_receipt(args[2])
      write_plan(receipt, args[3], args[4], args[5])
    }
    "report" if args.length() >= 10 => {
      let integrity = args[4]
      let projection_count = parse_int(args[5])
      let receipt_count = parse_int(args[6])
      report(
        args[2],
        args[3],
        integrity,
        projection_count,
        receipt_count,
        parse_bool(args[7]),
        args[8],
        args[9],
      )
    }
    _ => raise fail("invalid sqlite projection apply arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteProjectionApplyError::InvalidInput(message) => {
      println("company SQLite projection apply failed: " + message)
      @sys.exit(1)
    }
    SqliteProjectionApplyError::Io(_) => {
      println("company SQLite projection apply failed: filesystem error")
      @sys.exit(1)
    }
  }
}
