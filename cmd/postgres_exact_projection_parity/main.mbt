///|
pub(all) suberror PostgresExactProjectionParityError {
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
struct Expected {
  key : Key
  candidate : String
}

///|
struct Actual {
  key : Key
  candidate : String
}

///|
struct Receipt {
  source_snapshot_id : String
  mapping_version : String
  cohort : String
  expected : Array[Expected]
}

///|
fn fail(message : String) -> PostgresExactProjectionParityError {
  PostgresExactProjectionParityError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PostgresExactProjectionParityError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise PostgresExactProjectionParityError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot parse promotion receipt: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PostgresExactProjectionParityError {
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
) -> Json raise PostgresExactProjectionParityError {
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
) -> String raise PostgresExactProjectionParityError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn values(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise PostgresExactProjectionParityError {
  match required(fields, key, path) {
    Array(items) => items
    _ => raise fail("expected array at " + path + "." + key)
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
    Array(items) => "[" + items.map(canonical).join(",") + "]"
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
fn cohort_spec(cohort : String) -> (String, Array[String]) {
  match cohort {
    "opening-control-v1" =>
      ("moonproj.erp.opening-control-parity.v1", ["opening_control_total"])
    "tax-filing-v1" => ("moonproj.erp.tax-filing-parity.v1", ["tax_filing"])
    "bank-statement-v1" =>
      ("moonproj.erp.bank-statement-parity.v1", ["bank_statement"])
    "financing-facility-v1" =>
      ("moonproj.erp.financing-facility-parity.v1", ["financing_facility"])
    "asset-lifecycle-v1" =>
      ("moonproj.erp.asset-lifecycle-parity.v1", ["asset"])
    "treasury-plan-dispatch-v1" =>
      (
        "moonproj.erp.treasury-plan-dispatch-parity.v1",
        ["cash_plan", "fund_dispatch"],
      )
    "invoice-subledger-v1" =>
      (
        "moonproj.erp.invoice-subledger-parity.v1",
        ["invoice", "receivable", "payable"],
      )
    "procurement-cohort-v1" =>
      (
        "moonproj.erp.procurement-cohort-parity.v1",
        ["supplier", "tender", "commitment"],
      )
    "investment-performance-v1" =>
      (
        "moonproj.erp.investment-performance-parity.v1",
        [
          "investment_portfolio", "investment_performance", "investment_benchmark_reconciliation",
        ],
      )
    _ => ("moonproj.erp.exact-projection-parity.v1", [])
  }
}

///|
fn load_receipt(
  path : String,
) -> Receipt raise PostgresExactProjectionParityError {
  let root = object(read_json(path), "receipt")
  if string(root, "format", "receipt") != "moonproj.erp.domain-promotion.v1" {
    raise fail("unexpected promotion receipt format")
  }
  if string(root, "state", "receipt") != "promoted_through_domain_importers" {
    raise fail("promotion receipt is not domain-validated")
  }
  let cohort = root
    .get("cohort")
    .map(fn(value) {
      match value {
        String(text) => text
        _ => ""
      }
    })
    .unwrap_or("")
  let (_, allowed) = cohort_spec(cohort)
  let snapshot = string(root, "source_snapshot_id", "receipt")
  let mapping = string(root, "mapping_version", "receipt")
  let expected : Array[Expected] = []
  for index in 0..<values(root, "accepted_items", "receipt").length() {
    let path = "receipt.accepted_items[" + index.to_string() + "]"
    let item = object(values(root, "accepted_items", "receipt")[index], path)
    let target_type = string(item, "target_type", path)
    if !allowed.is_empty() && !allowed.contains(target_type) {
      raise fail("receipt contains an invalid target type: " + target_type)
    }
    let candidate = required(item, "target_candidate", path)
    let _ = object(candidate, path + ".target_candidate")
    expected.push({
      key: {
        aggregate_type: target_type,
        aggregate_id: string(item, "target_id", path),
        source_table: string(item, "source_table", path),
        source_id: string(item, "source_id", path),
      },
      candidate: canonical(candidate),
    })
  }
  if expected.is_empty() {
    raise fail("receipt contains no accepted items")
  }
  { source_snapshot_id: snapshot, mapping_version: mapping, cohort, expected }
}

///|
fn decode_hex(
  value : String,
) -> String raise PostgresExactProjectionParityError {
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
    let high = digit(value.get_char(index * 2).unwrap()).unwrap_or(-1)
    let low = digit(value.get_char(index * 2 + 1).unwrap()).unwrap_or(-1)
    if high < 0 || low < 0 {
      raise fail("invalid PostgreSQL hexadecimal field")
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
fn fields(
  line : String,
) -> Array[String] raise PostgresExactProjectionParityError {
  let result = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if result.length() != 3 {
    raise fail("unexpected PostgreSQL exact parity output")
  }
  result
}

///|
fn token(key : Key) -> String {
  key.aggregate_type +
  "\u{1f}" +
  key.aggregate_id +
  "\u{1f}" +
  key.source_table +
  "\u{1f}" +
  key.source_id
}

///|
fn key_json(key : Key, count : Int) -> Json {
  Json::array([
    Json::string(key.aggregate_type),
    Json::string(key.aggregate_id),
    Json::string(key.source_table),
    Json::string(key.source_id),
    Json::number(count.to_double(), repr=count.to_string()),
  ])
}

///|
async fn actual(
  receipt : Receipt,
  connection : @postgres.Connection,
) -> Array[Actual] raise PostgresExactProjectionParityError {
  let output = @postgres.run_sql(
    connection,
    "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE payload->>'source_snapshot_id'=" +
    @postgres.sql_literal(receipt.source_snapshot_id) +
    " AND payload->>'mapping_version'=" +
    @postgres.sql_literal(receipt.mapping_version) +
    " ORDER BY aggregate_type, aggregate_id, revision",
  ) catch {
    error => raise PostgresExactProjectionParityError::Database(error)
  }
  let result : Array[Actual] = []
  for view in output.split("\n") {
    let line = view.to_owned()
    if !line.is_empty() {
      let row = fields(line)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("projection payload is invalid JSON")
      }
      let payload_object = object(payload, "projection payload")
      let candidate = required(
        payload_object, "candidate", "projection payload",
      )
      let _ = object(candidate, "projection payload.candidate")
      result.push({
        key: {
          aggregate_type: decode_hex(row[0]),
          aggregate_id: decode_hex(row[1]),
          source_table: string(
            payload_object, "source_table", "projection payload",
          ),
          source_id: string(payload_object, "source_id", "projection payload"),
        },
        candidate: canonical(candidate),
      })
    }
  }
  result
}

///|
fn count_expected(values : Array[Expected]) -> Map[String, Int] {
  let result : Map[String, Int] = {}
  for value in values {
    let k = token(value.key)
    result.set(k, result.get(k).unwrap_or(0) + 1)
  }
  result
}

///|
fn count_actual(values : Array[Actual]) -> Map[String, Int] {
  let result : Map[String, Int] = {}
  for value in values {
    let k = token(value.key)
    result.set(k, result.get(k).unwrap_or(0) + 1)
  }
  result
}

///|
fn key_from_token(token_value : String) -> Key {
  let values = token_value
    .split("\u{1f}")
    .map(fn(value) { value.to_owned() })
    .to_array()
  {
    aggregate_type: values[0],
    aggregate_id: values[1],
    source_table: values[2],
    source_id: values[3],
  }
}

///|
fn sorted_strings(values : Array[String]) -> Array[String] {
  let result = values.copy()
  result.sort_by(fn(left, right) { left.lexical_compare(right) })
  result
}

///|
fn json_strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
async fn compare(
  receipt : Receipt,
  connection : @postgres.Connection,
) -> Json raise PostgresExactProjectionParityError {
  let actual_values = actual(receipt, connection)
  let expected_counts = count_expected(receipt.expected)
  let actual_counts = count_actual(actual_values)
  let missing : Array[Json] = []
  let extra : Array[Json] = []
  for key_string, count in expected_counts {
    let remaining = count - actual_counts.get(key_string).unwrap_or(0)
    if remaining > 0 {
      missing.push(key_json(key_from_token(key_string), remaining))
    }
  }
  for key_string, count in actual_counts {
    let remaining = count - expected_counts.get(key_string).unwrap_or(0)
    if remaining > 0 {
      extra.push(key_json(key_from_token(key_string), remaining))
    }
  }
  let mismatches : Array[Json] = []
  let expected_candidates : Map[String, Array[String]] = {}
  let actual_candidates : Map[String, Array[String]] = {}
  for value in receipt.expected {
    let k = token(value.key)
    let current = expected_candidates.get(k).unwrap_or([])
    current.push(value.candidate)
    expected_candidates.set(k, current)
  }
  for value in actual_values {
    let k = token(value.key)
    let current = actual_candidates.get(k).unwrap_or([])
    current.push(value.candidate)
    actual_candidates.set(k, current)
  }
  for key_string, want in expected_candidates {
    match actual_candidates.get(key_string) {
      Some(got) => {
        let left = sorted_strings(want)
        let right = sorted_strings(got)
        if left != right {
          mismatches.push(
            Json::object({
              "key": Json::array(key_from_token(key_string).as_array()),
              "expected": json_strings(left),
              "actual": json_strings(right),
            }),
          )
        }
      }
      None => ()
    }
  }
  let exact = missing.is_empty() && extra.is_empty() && mismatches.is_empty()
  let (format, _) = cohort_spec(receipt.cohort)
  Json::object({
    "format": Json::string(format),
    "source_snapshot_id": Json::string(receipt.source_snapshot_id),
    "mapping_version": Json::string(receipt.mapping_version),
    "state": Json::string(if exact { "shadow_verified" } else { "mismatch" }),
    "integrity": Json::string("ok"),
    "expected_items": Json::number(
      receipt.expected.length().to_double(),
      repr=receipt.expected.length().to_string(),
    ),
    "actual_items": Json::number(
      actual_values.length().to_double(),
      repr=actual_values.length().to_string(),
    ),
    "missing": Json::array(missing),
    "extra": Json::array(extra),
    "candidate_mismatches": Json::array(mismatches),
  })
}

///|
fn Key::as_array(self : Key) -> Array[Json] {
  [
    Json::string(self.aggregate_type),
    Json::string(self.aggregate_id),
    Json::string(self.source_table),
    Json::string(self.source_id),
  ]
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
fn json_state(value : Json) -> String {
  match value {
    Object(fields) =>
      match fields.get("state") {
        Some(String(text)) => text
        _ => ""
      }
    _ => ""
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println(
      "usage: postgres_exact_projection_parity <receipt> <output> [--psql path] [--host host] [--port port] [--user user] [--database database]",
    )
    @sys.exit(2)
  }
  let receipt = load_receipt(args[1]) catch {
    error => {
      println(
        "company PostgreSQL exact projection parity failed: \\{to_repr(error)}",
      )
      @sys.exit(1)
      { source_snapshot_id: "", mapping_version: "", cohort: "", expected: [] }
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
        "company PostgreSQL exact projection parity failed: \\{to_repr(error)}",
      )
      @sys.exit(1)
      Json::null()
    }
  }
  @fs.write_string_to_file(args[2], report.stringify(indent=2) + "\n") catch {
    error => {
      println(
        "company PostgreSQL exact projection parity failed: \\{to_repr(error)}",
      )
      @sys.exit(1)
    }
  }
  println(report.stringify())
  if json_state(report) != "shadow_verified" {
    @sys.exit(1)
  }
}
