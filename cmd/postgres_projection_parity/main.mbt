///|
/// Native PostgreSQL projection-parity verifier.
///
/// This replaces the historical Python parity helper for the PostgreSQL
/// target. It reopens the immutable projection rows for one promotion receipt,
/// compares source/target identities and multiplicities, and writes the same
/// machine-readable parity envelope without changing the database.
pub(all) suberror PostgresProjectionParityError {
  InvalidInput(String)
  Io(@fs.IOError)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
struct Key {
  aggregate_type : String
  aggregate_id : String
  source_table : String
  source_id : String
}

///|
struct Receipt {
  source_snapshot_id : String
  mapping_version : String
  expected : Array[Key]
}

///|
fn fail(message : String) -> PostgresProjectionParityError {
  PostgresProjectionParityError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresProjectionParityError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostgresProjectionParityError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse promotion receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresProjectionParityError {
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
) -> Json raise PostgresProjectionParityError {
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
) -> String raise PostgresProjectionParityError {
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
) -> Array[Json] raise PostgresProjectionParityError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn load_receipt(path : String) -> Receipt raise PostgresProjectionParityError {
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
  let accepted = required_array(root, "accepted_items", "receipt")
  if accepted.is_empty() {
    raise fail("promotion receipt has no accepted items")
  }
  let expected : Array[Key] = []
  for index in 0..<accepted.length() {
    let path = "receipt.accepted_items[" + index.to_string() + "]"
    let item = object(accepted[index], path)
    expected.push({
      aggregate_type: required_string(item, "target_type", path),
      aggregate_id: required_string(item, "target_id", path),
      source_table: required_string(item, "source_table", path),
      source_id: required_string(item, "source_id", path),
    })
  }
  { source_snapshot_id, mapping_version, expected }
}

///|
fn key_token(key : Key) -> String {
  // Unit-separator is not a valid source identifier character in the export
  // contract, so it is safe and keeps the counter implementation deterministic.
  key.aggregate_type +
  "\u{1f}" +
  key.aggregate_id +
  "\u{1f}" +
  key.source_table +
  "\u{1f}" +
  key.source_id
}

///|
fn counter(values : Array[Key]) -> (Map[String, Int], Array[Key]) {
  let counts : Map[String, Int] = {}
  let unique : Array[Key] = []
  for value in values {
    let token = key_token(value)
    let next = counts.get(token).unwrap_or(0) + 1
    counts.set(token, next)
    if next == 1 {
      unique.push(value)
    }
  }
  (counts, unique)
}

///|
fn sorted_keys(values : Array[Key]) -> Array[Key] {
  let result = values.copy()
  result.sort_by(fn(left, right) { key_token(left).compare(key_token(right)) })
  result
}

///|
fn key_count_json(key : Key, count : Int) -> Json {
  Json::array([
    Json::string(key.aggregate_type),
    Json::string(key.aggregate_id),
    Json::string(key.source_table),
    Json::string(key.source_id),
    Json::number(count.to_double()),
  ])
}

///|
fn differences(
  expected : Map[String, Int],
  actual : Map[String, Int],
  keys : Array[Key],
) -> Array[Json] {
  let result : Array[Json] = []
  for key in sorted_keys(keys) {
    let token = key_token(key)
    let left = expected.get(token).unwrap_or(0)
    let right = actual.get(token).unwrap_or(0)
    if left > right {
      result.push(key_count_json(key, left - right))
    }
  }
  result
}

///|
fn duplicates(counts : Map[String, Int], keys : Array[Key]) -> Array[Json] {
  let result : Array[Json] = []
  for key in sorted_keys(keys) {
    let count = counts.get(key_token(key)).unwrap_or(0)
    if count > 1 {
      result.push(key_count_json(key, count))
    }
  }
  result
}

///|
fn type_counts(values : Array[Key]) -> Map[String, Int] {
  let result : Map[String, Int] = {}
  for value in values {
    let key = value.aggregate_type
    result.set(key, result.get(key).unwrap_or(0) + 1)
  }
  result
}

///|
fn counts_json(values : Map[String, Int]) -> Json {
  let result : Map[String, Json] = {}
  values.each((key, value) => result.set(key, Json::number(value.to_double())))
  Json::object(result)
}

///|
fn decode_hex(value : String) -> String raise PostgresProjectionParityError {
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
) -> Array[String] raise PostgresProjectionParityError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL projection parity output")
  }
  values
}

///|
fn json_text(value : Json, key : String) -> String {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => text
        Some(Number(number, ..)) => number.to_string()
        _ => ""
      }
    _ => ""
  }
}

///|
async fn query_actual(
  connection : @postgres.Connection,
  receipt : Receipt,
) -> Array[Key] raise PostgresProjectionParityError {
  let sql = "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE payload->>'source_snapshot_id' = " +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    " AND payload->>'mapping_version' = " +
    @postgres.sql_literal(receipt.mapping_version) +
    " ORDER BY aggregate_type, aggregate_id, revision"
  let output = @postgres.run_sql(connection, sql) catch {
    error => raise PostgresProjectionParityError::Database(error)
  }
  let result : Array[Key] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("projection payload is invalid JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            aggregate_type: decode_hex(row[0]),
            aggregate_id: decode_hex(row[1]),
            source_table: json_text(payload, "source_table"),
            source_id: json_text(payload, "source_id"),
          })
        _ => raise fail("projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn compare(
  receipt : Receipt,
  connection : @postgres.Connection,
) -> Json raise PostgresProjectionParityError {
  let actual = query_actual(connection, receipt)
  let (expected_counts, expected_unique) = counter(receipt.expected)
  let (actual_counts, actual_unique) = counter(actual)
  let missing = differences(expected_counts, actual_counts, expected_unique)
  let extra = differences(actual_counts, expected_counts, actual_unique)
  let duplicate_expected = duplicates(expected_counts, expected_unique)
  let expected_types = type_counts(receipt.expected)
  let actual_types = type_counts(actual)
  let state = if missing.is_empty() &&
    extra.is_empty() &&
    duplicate_expected.is_empty() {
    "shadow_verified"
  } else {
    "mismatch"
  }
  Json::object({
    "format": Json::string("moonproj.erp.postgres-projection-parity.v1"),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string(state),
    "expected_items": Json::number(receipt.expected.length().to_double()),
    "actual_items": Json::number(actual.length().to_double()),
    "expected_counts": counts_json(expected_types),
    "actual_counts": counts_json(actual_types),
    "duplicate_expected": Json::array(duplicate_expected),
    "missing": Json::array(missing),
    "extra": Json::array(extra),
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
  if args.length() < 3 {
    println(
      "usage: postgres_projection_parity <receipt> <output> [--psql path] [--host host] [--port port] [--user user] [--database database]",
    )
    @sys.exit(2)
  }
  let receipt = load_receipt(args[1]) catch {
    error => {
      println("company PostgreSQL projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
      { source_snapshot_id: "", mapping_version: "", expected: [] }
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
      println("company PostgreSQL projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  @fs.write_string_to_file(args[2], report.stringify(indent=2) + "\n") catch {
    error => {
      println("company PostgreSQL projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
    }
  }
  println(report.stringify())
  if json_text(report, "state") != "shadow_verified" {
    @sys.exit(1)
  }
}
