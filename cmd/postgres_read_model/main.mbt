///|
/// Native MoonBit PostgreSQL read-model adapter.
///
/// The command owns the fixed query contract for the first read-only slice.
/// `psql` remains an operational PostgreSQL utility; no arbitrary SQL or
/// credentials are accepted from the caller.
pub(all) suberror PostgresReadModelError {
  InvalidInput(String)
  QueryFailed(String)
} derive(Debug)

///|
fn fail(message : String) -> PostgresReadModelError {
  PostgresReadModelError::InvalidInput(message)
}

///|
fn env_or(key : String, fallback : String) -> String {
  @env.get_env_var(key).unwrap_or(fallback)
}

///|
fn connection_args() -> Array[String] {
  [
    "-X",
    "-v",
    "ON_ERROR_STOP=1",
    "-A",
    "-t",
    "-F",
    "|",
    "-h",
    env_or("PGHOST", "/tmp"),
    "-p",
    env_or("PGPORT", "5432"),
    "-U",
    env_or("PGUSER", "moonproj"),
    "-d",
    env_or("PGDATABASE", "moonproj"),
  ]
}

///|
fn sql_literal(value : String) -> String {
  "'" + value.replace(old="'", new="''") + "'"
}

///|
fn process_text(process : @spawn.CompletedProcess, key : String) -> String {
  match process.to_json() {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn process_status(process : @spawn.CompletedProcess) -> Int {
  match process.to_json() {
    Object(fields) =>
      match fields.get("status") {
        Some(Number(value, ..)) => value.to_int()
        _ => -1
      }
    _ => -1
  }
}

///|
async fn run_psql(sql : String) -> String raise PostgresReadModelError {
  let arguments = connection_args()
  arguments.append(["-c", sql])
  let process = @spawn.spawn(
    env_or("PSQL_BIN", "psql"),
    arguments.map(fn(value) { value.to_string_view() }),
    timeout=30_000,
  ) catch {
    error => raise PostgresReadModelError::QueryFailed("\{to_repr(error)}")
  }
  let status = process_status(process)
  if status != 0 {
    let detail = process_text(process, "stderr")
    raise PostgresReadModelError::QueryFailed(
      if detail.is_empty() {
        "psql failed"
      } else {
        detail.trim().to_owned()
      },
    )
  } else {
    process_text(process, "stdout")
  }
}

///|
fn hex_digit(value : Char) -> Int? {
  if value >= '0' && value <= '9' {
    Some(value.to_int() - '0'.to_int())
  } else if value >= 'a' && value <= 'f' {
    Some(value.to_int() - 'a'.to_int() + 10)
  } else if value >= 'A' && value <= 'F' {
    Some(value.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn decode_hex(value : String) -> String raise PostgresReadModelError {
  if value.length() % 2 != 0 {
    raise fail("invalid hexadecimal PostgreSQL field")
  }
  let bytes : FixedArray[Byte] = FixedArray::make(value.length() / 2, 0)
  for index in 0..<(value.length() / 2) {
    let high = match value.get_char(index * 2) {
      None => raise fail("invalid hexadecimal PostgreSQL field")
      Some(char) =>
        match hex_digit(char) {
          Some(digit) => digit
          None => raise fail("invalid hexadecimal PostgreSQL field")
        }
    }
    let low = match value.get_char(index * 2 + 1) {
      None => raise fail("invalid hexadecimal PostgreSQL field")
      Some(char) =>
        match hex_digit(char) {
          Some(digit) => digit
          None => raise fail("invalid hexadecimal PostgreSQL field")
        }
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
fn parse_int(value : String) -> Int raise PostgresReadModelError {
  let trimmed = value.trim().to_owned()
  if trimmed.is_empty() {
    raise fail("expected integer field")
  }
  let mut sign = 1
  let mut start = 0
  if trimmed.get_char(0) == Some('-') {
    sign = -1
    start = 1
  }
  let mut result = 0
  for index in start..<trimmed.length() {
    let digit = match trimmed.get_char(index) {
      Some(value) => value
      None => raise fail("invalid integer field: " + trimmed)
    }
    if digit < '0' || digit > '9' {
      raise fail("invalid integer field: " + trimmed)
    }
    result = result * 10 + digit.to_int() - '0'.to_int()
  }
  result * sign
}

///|
fn fields(
  line : String,
  expected : Int,
) -> Array[String] raise PostgresReadModelError {
  let result = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if result.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  result
}

///|
async fn summary() -> Json raise PostgresReadModelError {
  let output = run_psql(
    "SELECT (SELECT count(*) FROM company_record), (SELECT count(*) FROM company_aggregate_projection), (SELECT count(*) FROM company_accounting_event_link), (SELECT count(*) FROM company_migration_receipt), (SELECT coalesce(max(version), 0) FROM company_schema)",
  )
  let line = output.trim().to_owned()
  let row = fields(line, 5)
  Json::object({
    "product": Json::string("moonproj-company"),
    "target": Json::string("postgresql"),
    "read_only": Json::boolean(true),
    "schema_version": Json::number(parse_int(row[4]).to_double()),
    "raw_records": Json::number(parse_int(row[0]).to_double()),
    "aggregate_projections": Json::number(parse_int(row[1]).to_double()),
    "accounting_links": Json::number(parse_int(row[2]).to_double()),
    "receipts": Json::number(parse_int(row[3]).to_double()),
  })
}

///|
async fn receipts() -> Json raise PostgresReadModelError {
  let output = run_psql(
    "SELECT encode(convert_to(run_id, 'UTF8'), 'hex'), encode(convert_to(source_snapshot_id, 'UTF8'), 'hex'), target_schema_version::text, encode(convert_to(mapping_version, 'UTF8'), 'hex'), encode(convert_to(state, 'UTF8'), 'hex'), encode(convert_to(coalesce(applied_hash, ''), 'UTF8'), 'hex') FROM company_migration_receipt ORDER BY certified_at NULLS LAST, run_id",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 6)
      result.push(
        Json::object({
          "run_id": Json::string(decode_hex(row[0])),
          "source_snapshot_id": Json::string(decode_hex(row[1])),
          "target_schema_version": Json::number(parse_int(row[2]).to_double()),
          "mapping_version": Json::string(decode_hex(row[3])),
          "state": Json::string(decode_hex(row[4])),
          "applied_hash": Json::string(decode_hex(row[5])),
        }),
      )
    }
  }
  Json::object({ "items": Json::array(result) })
}

///|
fn valid_identifier(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(fn(char) {
    char.is_ascii_alphabetic() ||
    char.is_ascii_digit() ||
    char == '_' ||
    char == '.' ||
    char == ':' ||
    char == '-'
  })
}

///|
async fn projections(
  aggregate_type : String?,
) -> Json raise PostgresReadModelError {
  let clause = match aggregate_type {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid aggregate_type")
      }
      " WHERE aggregate_type = " + sql_literal(value)
    }
    None => ""
  }
  let output = run_psql(
    "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM company_aggregate_projection" +
    clause +
    " ORDER BY aggregate_type, aggregate_id, revision LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 5)
      let payload = @json.parse(decode_hex(row[3])) catch {
        _ => raise fail("invalid projection payload")
      }
      result.push(
        Json::object({
          "aggregate_type": Json::string(decode_hex(row[0])),
          "aggregate_id": Json::string(decode_hex(row[1])),
          "revision": Json::number(parse_int(row[2]).to_double()),
          "payload": payload,
          "source_event_id": Json::string(decode_hex(row[4])),
        }),
      )
    }
  }
  Json::object({ "items": Json::array(result) })
}

///|
async fn run(args : Array[String]) -> Json raise PostgresReadModelError {
  match args.get(1) {
    Some("summary") => summary()
    Some("receipts") => receipts()
    Some("projections") => projections(args.get(2))
    Some(route) => raise fail("unsupported fixed read: " + route)
    None =>
      raise fail(
        "usage: postgres_read_model <summary|receipts|projections> [aggregate_type]",
      )
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  let report = run(args) catch {
    error => {
      println("MoonBit PostgreSQL read model failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  println(report.stringify())
}
