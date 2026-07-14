///|
/// Native MoonBit HTTP read-model adapter.
///
/// This first server slice owns the same fixed read contracts as the native
/// CLI (`health`, `session`, `summary`, `receipts`, and `projections`). It is
/// deliberately read-only and bounded; the broader authenticated company
/// service/gateway remains a later migration gate.
pub(all) suberror PostgresReadModelServerError {
  InvalidInput(String)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
fn fail(message : String) -> PostgresReadModelServerError {
  PostgresReadModelServerError::InvalidInput(message)
}

///|
async fn run_sql(sql : String) -> String raise PostgresReadModelServerError {
  @postgres.run_sql(@postgres.connection_from_env(), sql) catch {
    error => raise PostgresReadModelServerError::Database(error)
  }
}

///|
fn decode_hex(value : String) -> String raise PostgresReadModelServerError {
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
fn parse_decimal(value : String) -> Int raise PostgresReadModelServerError {
  if value.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  let mut sign = 1
  let mut start = 0
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
) -> Array[String] raise PostgresReadModelServerError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  values
}

///|
async fn summary() -> Json raise PostgresReadModelServerError {
  let output = run_sql(
    "SELECT (SELECT count(*) FROM company_record), (SELECT count(*) FROM company_aggregate_projection), (SELECT count(*) FROM company_accounting_event_link), (SELECT count(*) FROM company_migration_receipt), (SELECT coalesce(max(version), 0) FROM company_schema)",
  )
  let row = fields(output.trim().to_owned(), 5)
  Json::object({
    "product": Json::string("moonproj-company"),
    "target": Json::string("postgresql"),
    "read_only": Json::boolean(true),
    "schema_version": Json::number(parse_decimal(row[4]).to_double()),
    "raw_records": Json::number(parse_decimal(row[0]).to_double()),
    "aggregate_projections": Json::number(parse_decimal(row[1]).to_double()),
    "accounting_links": Json::number(parse_decimal(row[2]).to_double()),
    "receipts": Json::number(parse_decimal(row[3]).to_double()),
  })
}

///|
async fn receipts() -> Json raise PostgresReadModelServerError {
  let output = run_sql(
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
          "target_schema_version": Json::number(
            parse_decimal(row[2]).to_double(),
          ),
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
) -> Json raise PostgresReadModelServerError {
  let clause = match aggregate_type {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid aggregate_type")
      }
      " WHERE aggregate_type = " + @postgres.sql_literal(value)
    }
    None => ""
  }
  let output = run_sql(
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
          "revision": Json::number(parse_decimal(row[2]).to_double()),
          "payload": payload,
          "source_event_id": Json::string(decode_hex(row[4])),
        }),
      )
    }
  }
  Json::object({ "items": Json::array(result) })
}

///|
fn query_value(path : String, key : String) -> String? {
  match path.find("?") {
    Some(index) => {
      let query = path[index + 1:]
      for part_view in query.split("&") {
        let part = part_view.to_owned()
        let pieces = part
          .split("=")
          .map(fn(value) { value.to_owned() })
          .to_array()
        if pieces.length() == 2 && pieces[0] == key {
          return Some(pieces[1])
        }
      }
      None
    }
    None => None
  }
}

///|
fn path_only(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  status : Int,
  payload : Json,
) -> Unit {
  let reason = if status == 200 {
    "OK"
  } else if status == 204 {
    "No Content"
  } else if status == 404 {
    "Not Found"
  } else {
    "Bad Request"
  }
  conn
  ..send_response(status, reason, extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
  })
  ..write(payload.stringify())
  .end_response()
}

///|
async fn route(
  path : String,
  query : String,
) -> (Int, Json) raise PostgresReadModelServerError {
  match path {
    "/api/session" =>
      (
        200,
        Json::object({
          "authenticated": Json::boolean(true),
          "adapter": Json::string("read_only"),
        }),
      )
    "/api/health" =>
      (
        200,
        Json::object({
          "ok": Json::boolean(true),
          "target": Json::string("postgresql"),
          "read_only": Json::boolean(true),
        }),
      )
    "/api/company/summary" => (200, summary())
    "/api/company/receipts" => (200, receipts())
    "/api/company/projections" =>
      (200, projections(query_value(query, "aggregate_type")))
    _ => (404, Json::object({ "error": Json::string("not found") }))
  }
}

///|
async fn handle(request : @http.Request, conn : @http.ServerConnection) -> Unit {
  if request.meth is @http.Options {
    send_json(conn, 204, Json::null())
    return
  }
  if !(request.meth is @http.Get) && !(request.meth is @http.Head) {
    send_json(
      conn,
      405,
      Json::object({ "error": Json::string("read-only GET surface") }),
    )
    return
  }
  let path = path_only(request.path)
  let result = route(path, request.path) catch {
    error => {
      println("read-model request failed: \{to_repr(error)}")
      (500, Json::object({ "error": Json::string("read-model query failed") }))
    }
  }
  send_json(conn, result.0, result.1)
}

///|
fn option(args : Array[String], name : String) -> String? {
  for index in 1..<args.length() {
    if args[index] == name {
      match args.get(index + 1) {
        Some(value) => return Some(value)
        None => return None
      }
    }
  }
  None
}

///|
async fn main {
  let args = @sys.get_cli_args()
  let host = option(args, "--host").unwrap_or(
    @env.get_env_var("COMPANY_READ_MODEL_HOST").unwrap_or("127.0.0.1"),
  )
  let port = option(args, "--port").unwrap_or(
    @env.get_env_var("COMPANY_READ_MODEL_PORT").unwrap_or("4173"),
  )
  let address = @socket.Addr::parse(host + ":" + port) catch {
    _ => {
      println("invalid read-model listen address")
      @sys.exit(2)
      @socket.Addr::parse("127.0.0.1:4173")
    }
  }
  let server = @http.Server::new(address, reuse_addr=true) catch {
    _ => {
      println("cannot start read-model server")
      @sys.exit(1)
      @http.Server::new(@socket.Addr::parse("127.0.0.1:4173"), reuse_addr=true) catch {
        _ => panic()
      }
    }
  }
  println("company MoonBit read model listening on http://" + host + ":" + port)
  server.run_forever(
    (request, _body, conn) => handle(request, conn),
    allow_failure=true,
  )
}
