///|
pub(all) suberror SqliteProjectionParityError {
  InvalidInput(String)
  Io(@fs.IOError)
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
fn fail(message : String) -> SqliteProjectionParityError {
  SqliteProjectionParityError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SqliteProjectionParityError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteProjectionParityError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteProjectionParityError {
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
) -> Json raise SqliteProjectionParityError {
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
) -> String raise SqliteProjectionParityError {
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
) -> Array[Json] raise SqliteProjectionParityError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn load_receipt(path : String) -> Receipt raise SqliteProjectionParityError {
  let root = object(read_json(path), "receipt")
  if required_string(root, "format", "receipt") !=
    "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected promotion receipt format")
  }
  let snapshot = required_string(root, "source_snapshot_id", "receipt")
  let mapping = required_string(root, "mapping_version", "receipt")
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
  { source_snapshot_id: snapshot, mapping_version: mapping, expected }
}

///|
fn key_token(key : Key) -> String {
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
    Json::number(count.to_double(), repr=count.to_string()),
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
    let left = expected.get(key_token(key)).unwrap_or(0)
    let right = actual.get(key_token(key)).unwrap_or(0)
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
    result.set(
      value.aggregate_type,
      result.get(value.aggregate_type).unwrap_or(0) + 1,
    )
  }
  result
}

///|
fn counts_json(values : Map[String, Int]) -> Json {
  let result : Map[String, Json] = {}
  for key, value in values {
    result.set(key, Json::number(value.to_double(), repr=value.to_string()))
  }
  Json::object(result)
}

///|
fn decode_hex(value : String) -> String raise SqliteProjectionParityError {
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
fn load_actual(path : String) -> Array[Key] raise SqliteProjectionParityError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SqliteProjectionParityError::Io(error)
  }
  let result : Array[Key] = []
  for line_view in content.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 4 {
        raise fail("unexpected SQLite projection parity output")
      }
      result.push({
        aggregate_type: decode_hex(values[0]),
        aggregate_id: decode_hex(values[1]),
        source_table: decode_hex(values[2]),
        source_id: decode_hex(values[3]),
      })
    }
  }
  result
}

///|
fn compare(receipt : Receipt, actual : Array[Key], integrity : String) -> Json {
  let (expected_counts, expected_unique) = counter(receipt.expected)
  let (actual_counts, actual_unique) = counter(actual)
  let missing = differences(expected_counts, actual_counts, expected_unique)
  let extra = differences(actual_counts, expected_counts, actual_unique)
  let duplicate_expected = duplicates(expected_counts, expected_unique)
  let state = if integrity == "ok" &&
    missing.is_empty() &&
    extra.is_empty() &&
    duplicate_expected.is_empty() {
    "shadow_verified"
  } else {
    "mismatch"
  }
  Json::object({
    "format": Json::string("moonproj.erp.projection-parity.v1"),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string(state),
    "integrity": Json::string(integrity),
    "expected_items": Json::number(
      receipt.expected.length().to_double(),
      repr=receipt.expected.length().to_string(),
    ),
    "actual_items": Json::number(
      actual.length().to_double(),
      repr=actual.length().to_string(),
    ),
    "expected_counts": counts_json(type_counts(receipt.expected)),
    "actual_counts": counts_json(type_counts(actual)),
    "duplicate_expected": Json::array(duplicate_expected),
    "missing": Json::array(missing),
    "extra": Json::array(extra),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 5 {
    println(
      "usage: sqlite_projection_parity <receipt> <output> <rows> <integrity>",
    )
    @sys.exit(2)
  }
  let receipt = load_receipt(args[1]) catch {
    error => {
      println("company SQLite projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
      { source_snapshot_id: "", mapping_version: "", expected: [] }
    }
  }
  let actual = load_actual(args[3]) catch {
    error => {
      println("company SQLite projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
      []
    }
  }
  let report = compare(receipt, actual, args[4])
  @fs.write_string_to_file(args[2], report.stringify(indent=2) + "\n") catch {
    error => {
      println("company SQLite projection parity failed: \{to_repr(error)}")
      @sys.exit(1)
    }
  }
  println(report.stringify())
  match report {
    Object(fields) =>
      if fields
        .get("state")
        .map(fn(value) { value == Json::string("shadow_verified") })
        .unwrap_or(false) {
        ()
      } else {
        @sys.exit(1)
      }
    _ => @sys.exit(1)
  }
}
