///|
/// Native MoonBit authenticated PostgreSQL company service.
///
/// This is the first service slice in the Python-to-MoonBit migration. It
/// keeps the bearer-token and forwarded-TLS boundary, then exposes fixed
/// read-only contracts for health, summary, receipts, projections, and the
/// imported profile/preferences/initiated-document observations. Commands and
/// the wider ERP route families remain separate migration gates.
pub(all) suberror CompanyServiceError {
  InvalidInput(String)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
fn fail(message : String) -> CompanyServiceError {
  CompanyServiceError::InvalidInput(message)
}

///|
struct SourceRow {
  record_id : String
  payload : Json
}

///|
struct InitiatedItem {
  id : String
  code : String
  subject : String
  amount : Json
  state : String
  date : String
  biz : String
}

///|
async fn run_sql(sql : String) -> String raise CompanyServiceError {
  @postgres.run_sql(@postgres.connection_from_env(), sql) catch {
    error => raise CompanyServiceError::Database(error)
  }
}

///|
fn decode_hex(value : String) -> String raise CompanyServiceError {
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
) -> Array[String] raise CompanyServiceError {
  let values = line.split("|").map(fn(value) { value.to_owned() }).to_array()
  if values.length() != expected {
    raise fail("unexpected PostgreSQL row shape")
  }
  values
}

///|
fn parse_decimal(value : String) -> Int raise CompanyServiceError {
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
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn json_text(value : Json, key : String, fallback : String) -> String {
  match json_field(value, key) {
    Some(String(text)) => text
    Some(Number(number, ..)) => number.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => fallback
  }
}

///|
fn json_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match json_field(value, key) {
    Some(True) => true
    Some(False) => false
    Some(Number(number, ..)) => number != 0
    _ => fallback
  }
}

///|
async fn raw_source_rows(
  table : String,
  max_rows : Int,
) -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_record WHERE record_type = " +
    @postgres.sql_literal("legacy/raw/" + table) +
    " ORDER BY record_id LIMIT " +
    max_rows.to_string(),
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 2)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid source row JSON")
      }
      match payload {
        Object(_) => result.push({ record_id: decode_hex(row[0]), payload })
        _ => raise fail("source row payload is not an object")
      }
    }
  }
  result
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
fn find_user(users : Array[SourceRow], user_code : String) -> SourceRow? {
  for row in users {
    if json_text(row.payload, "user_code", "") == user_code {
      return Some(row)
    }
  }
  None
}

///|
fn unit_name(units : Array[SourceRow], unit_id : String) -> String {
  if unit_id.is_empty() {
    return ""
  }
  for row in units {
    let payload_id = json_text(row.payload, "bu_guid", "")
    if row.record_id == unit_id || payload_id == unit_id {
      return json_text(row.payload, "bu_name", "")
    }
  }
  ""
}

///|
async fn auth_current_user(
  user_code : String,
) -> Json? raise CompanyServiceError {
  if !valid_identifier(user_code) {
    raise fail("invalid user_code")
  }
  let users = raw_source_rows("sys_user", 100)
  let units = raw_source_rows("mu_business_unit", 100)
  let selected = find_user(users, user_code)
  match selected {
    None => None
    Some(row) => {
      let payload = row.payload
      let bu_guid = json_text(payload, "bu_guid", "")
      let dept_guid = json_text(payload, "dept_guid", "")
      Some(
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "userId": Json::string(json_text(payload, "user_id", row.record_id)),
            "userCode": Json::string(user_code),
            "userName": Json::string(json_text(payload, "user_name", "")),
            "empName": Json::string(
              json_text(
                payload,
                "emp_name",
                json_text(payload, "user_name", ""),
              ),
            ),
            "buGuid": Json::string(bu_guid),
            "buName": Json::string(unit_name(units, bu_guid)),
            "deptGuid": Json::string(dept_guid),
            "deptName": Json::string(unit_name(units, dept_guid)),
            "isSuperUser": Json::boolean(
              json_bool(payload, "is_super_user", false),
            ),
            "enabled": Json::boolean(json_bool(payload, "enabled", false)),
            "lastLoginTime": Json::string(
              json_text(payload, "last_login_time", ""),
            ),
            "sourceKind": Json::string("imported"),
          }),
          "source_kind": Json::string("imported"),
          "source_coverage": Json::object({
            "sys_user": Json::number(users.length().to_double()),
            "mu_business_unit": Json::number(units.length().to_double()),
          }),
        }),
      )
    }
  }
}

///|
fn preference_value(payload : Json) -> Json {
  match json_field(payload, "pref_value") {
    Some(String(value)) => @json.parse(value) catch { _ => Json::string(value) }
    Some(value) => value
    None => Json::null()
  }
}

///|
async fn preference_command_payloads(
  user_code : String,
) -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload, source_event_id FROM company_aggregate_projection WHERE aggregate_type = 'user_preference' AND payload->>'user_code' = " +
    @postgres.sql_literal(user_code) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 100",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid preference command projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ =>
          raise fail("preference command projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn auth_preferences(
  user_code : String,
) -> Json? raise CompanyServiceError {
  if !valid_identifier(user_code) {
    raise fail("invalid user_code")
  }
  let users = raw_source_rows("sys_user", 100)
  let selected = find_user(users, user_code)
  match selected {
    None => None
    Some(user) => {
      let user_id = json_text(user.payload, "user_id", user.record_id)
      let preferences = raw_source_rows("sys_user_pref", 100)
      let values : Array[(String, Json)] = []
      for row in preferences {
        if json_text(row.payload, "user_id", "") == user_id {
          let key = json_text(row.payload, "pref_key", "")
          if !key.is_empty() {
            values.push((key, preference_value(row.payload)))
          }
        }
      }
      let command_rows = preference_command_payloads(user_code)
      for payload in command_rows {
        let key = json_text(payload, "pref_key", "")
        if !key.is_empty() && json_text(payload, "state", "") != "deleted" {
          values.push(
            (key, json_field(payload, "value").unwrap_or(Json::null())),
          )
        }
      }
      let missing : Array[Json] = []
      if preferences.is_empty() {
        missing.push(Json::string("sys_user_pref"))
      }
      Some(
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object(Map::Map(values)),
          "source_kind": Json::string(
            if command_rows.length() > 0 {
              "imported_or_command"
            } else {
              "imported_or_empty"
            },
          ),
          "command_projection": Json::boolean(command_rows.length() > 0),
          "source_coverage": Json::object({
            "sys_user": Json::number(users.length().to_double()),
            "sys_user_pref": Json::number(preferences.length().to_double()),
          }),
          "missing_or_empty_source_tables": Json::array(missing),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(command_rows.length() > 0),
        }),
      )
    }
  }
}

///|
fn initiated_rows(
  rows : Array[SourceRow],
  table : String,
  id_key : String,
  code_key : String,
  amount_key : String,
  user_id : String,
  max_rows : Int,
) -> Array[InitiatedItem] {
  let result : Array[InitiatedItem] = []
  for row in rows {
    let payload = row.payload
    if json_text(payload, "applied_by", "") == user_id {
      result.push({
        id: json_text(payload, id_key, row.record_id),
        code: json_text(payload, code_key, ""),
        subject: json_text(payload, "subject", ""),
        amount: json_field(payload, amount_key).unwrap_or(Json::null()),
        state: json_text(payload, "apply_state", ""),
        date: json_text(payload, "apply_date", ""),
        biz: table,
      })
    }
  }
  result.sort_by(fn(left, right) {
    let date_order = right.date.lexical_compare(left.date)
    if date_order == 0 {
      right.id.lexical_compare(left.id)
    } else {
      date_order
    }
  })
  if result.length() > max_rows {
    result[max_rows:].to_owned()
  } else {
    result
  }
}

///|
fn initiated_json(items : Array[InitiatedItem]) -> Json {
  Json::array(
    items.map(fn(item) {
      Json::object({
        "id": Json::string(item.id),
        "code": Json::string(item.code),
        "subject": Json::string(item.subject),
        "amount": item.amount,
        "state": Json::string(item.state),
        "date": Json::string(item.date),
        "biz": Json::string(item.biz),
        "sourceKind": Json::string("imported"),
      })
    }),
  )
}

///|
async fn auth_my_initiated(
  user_code : String,
) -> Json? raise CompanyServiceError {
  if !valid_identifier(user_code) {
    raise fail("invalid user_code")
  }
  let users = raw_source_rows("sys_user", 100)
  let selected = find_user(users, user_code)
  match selected {
    None => None
    Some(user) => {
      let user_id = json_text(user.payload, "user_id", user.record_id)
      let expenses = raw_source_rows("vcb_expense", 100)
      let loans = raw_source_rows("vcb_loan_simple", 100)
      let applies = raw_source_rows("cb_htfk_apply", 100)
      let expense_items = initiated_rows(
        expenses, "vcb_expense", "expense_guid", "expense_code", "pay_amount", user_id,
        500,
      )
      let loan_items = initiated_rows(
        loans, "vcb_loan_simple", "loan_guid", "loan_code", "loan_amount", user_id,
        500,
      )
      let apply_items = initiated_rows(
        applies, "cb_htfk_apply", "htfk_apply_guid", "apply_code", "apply_amount",
        user_id, 500,
      )
      Some(
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "expenses": initiated_json(expense_items),
            "loans": initiated_json(loan_items),
            "applies": initiated_json(apply_items),
          }),
          "source_kind": Json::string("imported_or_empty"),
          "source_coverage": Json::object({
            "cb_htfk_apply": Json::number(applies.length().to_double()),
            "sys_user": Json::number(users.length().to_double()),
            "vcb_expense": Json::number(expenses.length().to_double()),
            "vcb_loan_simple": Json::number(loans.length().to_double()),
          }),
          "matched_coverage": Json::object({
            "vcb_expense": Json::number(expense_items.length().to_double()),
            "vcb_loan_simple": Json::number(loan_items.length().to_double()),
            "cb_htfk_apply": Json::number(apply_items.length().to_double()),
          }),
        }),
      )
    }
  }
}

///|
async fn summary(
  expected_schema_version : Int,
) -> Json raise CompanyServiceError {
  let output = run_sql(
    "SELECT (SELECT count(*) FROM company_record), (SELECT count(*) FROM company_aggregate_projection), (SELECT count(*) FROM company_accounting_event_link), (SELECT count(*) FROM company_migration_receipt), (SELECT coalesce(max(version), 0) FROM company_schema)",
  )
  let row = fields(output.trim().to_owned(), 5)
  let schema_version = parse_decimal(row[4])
  if schema_version != expected_schema_version {
    raise fail("company schema version is not ready")
  }
  Json::object({
    "product": Json::string("moonproj-company"),
    "target": Json::string("postgresql"),
    "read_only": Json::boolean(true),
    "capabilities": Json::array([
      Json::string("read_model"),
      Json::string("profile_observation_read"),
      Json::string("preference_observation_read"),
      Json::string("initiated_document_observation_read"),
      Json::string("authenticated_http_read"),
    ]),
    "schema_version": Json::number(schema_version.to_double()),
    "raw_records": Json::number(parse_decimal(row[0]).to_double()),
    "aggregate_projections": Json::number(parse_decimal(row[1]).to_double()),
    "accounting_links": Json::number(parse_decimal(row[2]).to_double()),
    "receipts": Json::number(parse_decimal(row[3]).to_double()),
  })
}

///|
async fn receipts() -> Json raise CompanyServiceError {
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
async fn projections(
  aggregate_type : String?,
) -> Json raise CompanyServiceError {
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
        let pieces = part_view
          .to_owned()
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
fn header(request : @http.Request, key : String) -> String {
  request.headers
  .get(key.to_lower())
  .unwrap_or(request.headers.get(key).unwrap_or(""))
  .trim()
  .to_owned()
}

///|
fn auth_status(
  request : @http.Request,
  token : String,
  require_forwarded_tls : Bool,
) -> Int {
  if require_forwarded_tls &&
    header(request, "X-Forwarded-Proto").to_lower() != "https" {
    return 400
  }
  let authorization = header(request, "Authorization")
  if authorization != "Bearer " + token {
    return 401
  }
  0
}

///|
fn status_reason(status : Int) -> String {
  match status {
    200 => "OK"
    204 => "No Content"
    400 => "Bad Request"
    401 => "Unauthorized"
    404 => "Not Found"
    405 => "Method Not Allowed"
    500 => "Internal Server Error"
    _ => "Error"
  }
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  request_method : @http.RequestMethod,
  status : Int,
  payload : Json,
  challenge : Bool,
) -> Unit {
  if challenge {
    conn.send_response(status, status_reason(status), extra_headers={
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "WWW-Authenticate": "Bearer",
    })
  } else {
    conn.send_response(status, status_reason(status), extra_headers={
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    })
  }
  if request_method is @http.Head {
    conn.end_response()
    return
  }
  conn.write(payload.stringify())
  conn.end_response()
}

///|
async fn route(
  path : String,
  query : String,
  expected_schema_version : Int,
) -> (Int, Json) raise CompanyServiceError {
  match path {
    "/api/session" =>
      (
        200,
        Json::object({
          "authenticated": Json::boolean(true),
          "adapter": Json::string("company_service_native"),
        }),
      )
    "/api/health" =>
      (
        200,
        Json::object({
          "ok": Json::boolean(true),
          "target": Json::string("postgresql"),
          "read_only": Json::boolean(true),
          "capabilities": Json::array([
            Json::string("read_model"),
            Json::string("profile_observation_read"),
            Json::string("preference_observation_read"),
            Json::string("initiated_document_observation_read"),
            Json::string("authenticated_http_read"),
          ]),
          "schema_version": Json::number(expected_schema_version.to_double()),
        }),
      )
    "/api/company/summary" => (200, summary(expected_schema_version))
    "/api/company/receipts" => (200, receipts())
    "/api/company/projections" =>
      (200, projections(query_value(query, "aggregate_type")))
    "/api/company/auth/me" => {
      let user_code = query_value(query, "userCode").unwrap_or("")
      match auth_current_user(user_code) {
        Some(value) => (200, value)
        None => (404, Json::object({ "error": Json::string("user not found") }))
      }
    }
    "/api/company/auth/prefs" => {
      let user_code = query_value(query, "userCode").unwrap_or("")
      match auth_preferences(user_code) {
        Some(value) => (200, value)
        None => (404, Json::object({ "error": Json::string("user not found") }))
      }
    }
    "/api/company/auth/my-initiated" => {
      let user_code = query_value(query, "userCode").unwrap_or("")
      match auth_my_initiated(user_code) {
        Some(value) => (200, value)
        None => (404, Json::object({ "error": Json::string("user not found") }))
      }
    }
    _ => (404, Json::object({ "error": Json::string("not found") }))
  }
}

///|
async fn handle(
  request : @http.Request,
  conn : @http.ServerConnection,
  token : String,
  require_forwarded_tls : Bool,
  expected_schema_version : Int,
) -> Unit {
  if request.meth is @http.Options {
    send_json(conn, request.meth, 204, Json::null(), false)
    return
  }
  if !(request.meth is @http.Get) && !(request.meth is @http.Head) {
    send_json(
      conn,
      request.meth,
      405,
      Json::object({
        "error": Json::string("read-only authenticated GET surface"),
      }),
      false,
    )
    return
  }
  let authorization_status = auth_status(request, token, require_forwarded_tls)
  if authorization_status != 0 {
    send_json(
      conn,
      request.meth,
      authorization_status,
      Json::object({
        "error": Json::string(
          if authorization_status == 401 {
            "bearer authentication required"
          } else {
            "forwarded TLS is required"
          },
        ),
      }),
      authorization_status == 401,
    )
    return
  }
  let result = route(
    path_only(request.path),
    request.path,
    expected_schema_version,
  ) catch {
    error => {
      println("company native service request failed: \{to_repr(error)}")
      (
        500,
        Json::object({ "error": Json::string("company service query failed") }),
      )
    }
  }
  send_json(conn, request.meth, result.0, result.1, false)
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
fn has_flag(args : Array[String], name : String) -> Bool {
  for index in 1..<args.length() {
    if args[index] == name {
      return true
    }
  }
  false
}

///|
fn parse_int_option(args : Array[String], name : String, fallback : Int) -> Int {
  match option(args, name) {
    None => fallback
    Some(value) => {
      if value.is_empty() {
        return fallback
      }
      let mut result = 0
      for char in value.iter() {
        if char < '0' || char > '9' {
          return fallback
        }
        result = result * 10 + char.to_int() - '0'.to_int()
      }
      result
    }
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  let token_env = option(args, "--token-env").unwrap_or(
    "MOONPROJ_SERVICE_TOKEN",
  )
  let token = @env.get_env_var(token_env).unwrap_or("")
  if token.is_empty() {
    println("company service token environment variable is not set")
    @sys.exit(2)
  }
  let host = option(args, "--host").unwrap_or(
    @env.get_env_var("COMPANY_SERVICE_HOST").unwrap_or("127.0.0.1"),
  )
  let port = option(args, "--port").unwrap_or(
    @env.get_env_var("COMPANY_SERVICE_PORT").unwrap_or("4174"),
  )
  let schema_version = parse_int_option(args, "--schema-version", 4)
  let require_forwarded_tls = has_flag(args, "--require-forwarded-tls") ||
    @env.get_env_var("COMPANY_SERVICE_REQUIRE_FORWARDED_TLS").unwrap_or("") ==
    "1"
  let address = @socket.Addr::parse(host + ":" + port) catch {
    _ => {
      println("invalid company service listen address")
      @sys.exit(2)
      @socket.Addr::parse("127.0.0.1:4174")
    }
  }
  let server = @http.Server::new(address, reuse_addr=true) catch {
    _ => {
      println("cannot start company native service")
      @sys.exit(1)
      @http.Server::new(@socket.Addr::parse("127.0.0.1:4174"), reuse_addr=true) catch {
        _ => panic()
      }
    }
  }
  println("company MoonBit service listening on http://" + host + ":" + port)
  server.run_forever(
    (request, _body, conn) => {
      handle(request, conn, token, require_forwarded_tls, schema_version)
    },
    allow_failure=true,
  )
}
