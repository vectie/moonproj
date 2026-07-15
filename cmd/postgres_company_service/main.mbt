///|
/// Native MoonBit authenticated PostgreSQL company service.
///
/// This is the first service slice in the Python-to-MoonBit migration. It
/// keeps the bearer-token and forwarded-TLS boundary, then exposes fixed
/// fixed contracts for health, summary, receipts, projections, imported
/// profile/preferences/initiated-document observations, source-shaped cost
/// observations, and the expense read/command boundary. The wider ERP route
/// families remain separate migration gates.
pub(all) suberror CompanyServiceError {
  InvalidInput(String)
  CommandRejected(Int, String)
  Database(@postgres.PostgresError)
} derive(Debug)

///|
fn fail(message : String) -> CompanyServiceError {
  CompanyServiceError::InvalidInput(message)
}

///|
fn reject(status : Int, message : String) -> CompanyServiceError {
  CompanyServiceError::CommandRejected(status, message)
}

///|
struct SourceRow {
  record_id : String
  source_id : String
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
    "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_record WHERE record_type = " +
    @postgres.sql_literal("legacy/raw/" + table) +
    " ORDER BY record_id LIMIT " +
    max_rows.to_string(),
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid source row JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
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
      Json::string("contract_read"),
      Json::string("payment_application_read"),
      Json::string("payment_eligibility_read"),
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
fn json_array_output(output : String) -> Array[Json] raise CompanyServiceError {
  let parsed = @json.parse(output.trim()) catch {
    _ => raise fail("invalid PostgreSQL JSON array")
  }
  match parsed {
    Array(values) => values
    _ => raise fail("PostgreSQL result is not a JSON array")
  }
}

///|
fn json_double(value : Json, key : String, fallback : Double) -> Double {
  match json_field(value, key) {
    Some(Number(number, ..)) => number
    _ => fallback
  }
}

///|
fn json_int(value : Json, key : String, fallback : Int) -> Int {
  json_double(value, key, fallback.to_double()).to_int()
}

///|
fn parse_number(value : String) -> Double {
  if value.is_empty() {
    return 0.0
  }
  let mut sign = 1.0
  let mut index = 0
  match value.get_char(0) {
    Some('-') => {
      sign = -1.0
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut whole = 0.0
  let mut fraction = 0.0
  let mut divisor = 1.0
  let mut after_decimal = false
  while index < value.length() {
    let char = match value.get_char(index) {
      Some(value) => value
      None => return 0.0
    }
    if char == '.' {
      if after_decimal {
        return 0.0
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      let digit = (char.to_int() - '0'.to_int()).to_double()
      if after_decimal {
        divisor *= 10.0
        fraction += digit / divisor
      } else {
        whole = whole * 10.0 + digit
      }
    } else {
      return 0.0
    }
    index += 1
  }
  sign * (whole + fraction)
}

///|
fn json_number(value : Json, key : String, fallback : Double) -> Double {
  match json_field(value, key) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text)
    _ => fallback
  }
}

///|
struct ExpenseSourceRows {
  expenses : Array[SourceRow]
  details : Array[SourceRow]
  splits : Array[SourceRow]
  users : Array[SourceRow]
  units : Array[SourceRow]
  options : Array[SourceRow]
  proceedings : Array[SourceRow]
}

///|
async fn expense_source_rows() -> ExpenseSourceRows raise CompanyServiceError {
  {
    expenses: raw_source_rows("vcb_expense", 500),
    details: raw_source_rows("cb_expense_detail", 500),
    splits: raw_source_rows("cb_expense_split", 500),
    users: raw_source_rows("sys_user", 500),
    units: raw_source_rows("mu_business_unit", 500),
    options: raw_source_rows("my_biz_param_option", 500),
    proceedings: raw_source_rows("vys_proceeding", 500),
  }
}

///|
fn expense_id(row : SourceRow) -> String {
  json_text(row.payload, "expense_guid", row.record_id)
}

///|
fn expense_user_name(users : Array[SourceRow], user_id : String) -> String {
  for row in users {
    if json_text(row.payload, "user_id", row.record_id) == user_id {
      return json_text(
        row.payload,
        "emp_name",
        json_text(row.payload, "user_name", user_id),
      )
    }
  }
  user_id
}

///|
fn expense_unit_name(units : Array[SourceRow], unit_id : String) -> String {
  if unit_id.is_empty() {
    return ""
  }
  for row in units {
    if json_text(row.payload, "bu_guid", row.record_id) == unit_id {
      return json_text(row.payload, "bu_name", unit_id)
    }
  }
  unit_id
}

///|
fn expense_option_name(options : Array[SourceRow], code : String) -> String {
  for option in options {
    if json_text(option.payload, "param_name", "") == "cost_subject" &&
      json_text(option.payload, "param_code", "") == code {
      return json_text(option.payload, "param_value", code)
    }
  }
  code
}

///|
fn expense_proceeding_name(
  proceedings : Array[SourceRow],
  proceeding_id : String,
) -> String {
  for proceeding in proceedings {
    if proceeding.record_id == proceeding_id ||
      json_text(proceeding.payload, "proceeding_guid", "") == proceeding_id {
      return json_text(proceeding.payload, "proceeding_name", proceeding_id)
    }
  }
  proceeding_id
}

///|
fn expense_list_item(
  row : SourceRow,
  users : Array[SourceRow],
  units : Array[SourceRow],
) -> Json {
  let payload = row.payload
  let applied_by = json_text(payload, "applied_by", "")
  let apply_dept = json_text(
    payload,
    "apply_dept_guid",
    json_text(payload, "dept_guid", ""),
  )
  Json::object({
    "expenseGuid": Json::string(expense_id(row)),
    "expenseCode": Json::string(json_text(payload, "expense_code", "")),
    "subject": Json::string(json_text(payload, "subject", "")),
    "applyState": Json::string(json_text(payload, "apply_state", "")),
    "payState": Json::string(json_text(payload, "pay_state", "")),
    "expenseAmount": Json::number(json_number(payload, "expense_amount", 0.0)),
    "offsetAmount": Json::number(json_number(payload, "offset_amount", 0.0)),
    "payAmount": Json::number(json_number(payload, "pay_amount", 0.0)),
    "appliedByName": Json::string(expense_user_name(users, applied_by)),
    "applyDeptName": Json::string(expense_unit_name(units, apply_dept)),
    "applyDate": Json::string(json_text(payload, "apply_date", "")),
    "payUnit": Json::string(json_text(payload, "pay_unit", "")),
    "processInstanceGuid": Json::string(
      json_text(payload, "process_instance_guid", ""),
    ),
    "createdAt": Json::string(json_text(payload, "created_at", "")),
    "sourceKind": Json::string("imported"),
  })
}

///|
fn expense_coverage(rows : ExpenseSourceRows) -> Json {
  Json::object({
    "vcb_expense": Json::number(rows.expenses.length().to_double()),
    "cb_expense_detail": Json::number(rows.details.length().to_double()),
    "cb_expense_split": Json::number(rows.splits.length().to_double()),
    "sys_user": Json::number(rows.users.length().to_double()),
    "mu_business_unit": Json::number(rows.units.length().to_double()),
    "my_biz_param_option": Json::number(rows.options.length().to_double()),
    "vys_proceeding": Json::number(rows.proceedings.length().to_double()),
  })
}

///|
fn expense_list_coverage(rows : ExpenseSourceRows) -> Json {
  Json::object({
    "vcb_expense": Json::number(rows.expenses.length().to_double()),
    "cb_expense_detail": Json::number(rows.details.length().to_double()),
    "cb_expense_split": Json::number(rows.splits.length().to_double()),
    "sys_user": Json::number(rows.users.length().to_double()),
    "mu_business_unit": Json::number(rows.units.length().to_double()),
  })
}

///|
fn expense_list_missing(rows : ExpenseSourceRows) -> Array[Json] {
  let missing : Array[Json] = []
  if rows.expenses.is_empty() {
    missing.push(Json::string("vcb_expense"))
  }
  if rows.details.is_empty() {
    missing.push(Json::string("cb_expense_detail"))
  }
  if rows.splits.is_empty() {
    missing.push(Json::string("cb_expense_split"))
  }
  if rows.users.is_empty() {
    missing.push(Json::string("sys_user"))
  }
  if rows.units.is_empty() {
    missing.push(Json::string("mu_business_unit"))
  }
  missing
}

///|
fn expense_missing(rows : ExpenseSourceRows) -> Array[Json] {
  let missing : Array[Json] = []
  if rows.expenses.is_empty() {
    missing.push(Json::string("vcb_expense"))
  }
  if rows.details.is_empty() {
    missing.push(Json::string("cb_expense_detail"))
  }
  if rows.splits.is_empty() {
    missing.push(Json::string("cb_expense_split"))
  }
  if rows.users.is_empty() {
    missing.push(Json::string("sys_user"))
  }
  if rows.units.is_empty() {
    missing.push(Json::string("mu_business_unit"))
  }
  if rows.options.is_empty() {
    missing.push(Json::string("my_biz_param_option"))
  }
  if rows.proceedings.is_empty() {
    missing.push(Json::string("vys_proceeding"))
  }
  missing
}

///|
async fn budget_expenses_response(
  expense_guid : String?,
  user_code : String?,
  apply_state : String?,
) -> Json? raise CompanyServiceError {
  let rows = expense_source_rows()
  let selected_user_id = match user_code {
    None => None
    Some(value) if value.is_empty() => None
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid user_code")
      }
      match find_user(rows.users, value) {
        Some(user) => Some(json_text(user.payload, "user_id", user.record_id))
        None => return None
      }
    }
  }
  let result : Array[Json] = []
  for row in rows.expenses {
    let payload = row.payload
    if !json_text(payload, "deleted_at", "").is_empty() {
      continue
    }
    let id = expense_id(row)
    if expense_guid is Some(id_filter) && id != id_filter {
      continue
    }
    if selected_user_id is Some(user_id) &&
      json_text(payload, "applied_by", "") != user_id {
      continue
    }
    if apply_state is Some(state) &&
      json_text(payload, "apply_state", "") != state {
      continue
    }
    result.push(expense_list_item(row, rows.users, rows.units))
  }
  result.sort_by(fn(left, right) {
    let date_order = json_text(right, "createdAt", "").lexical_compare(
      json_text(left, "createdAt", ""),
    )
    if date_order == 0 {
      json_text(right, "expenseGuid", "").lexical_compare(
        json_text(left, "expenseGuid", ""),
      )
    } else {
      date_order
    }
  })
  Some(
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::array(result),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": expense_list_coverage(rows),
      "missing_or_empty_source_tables": Json::array(expense_list_missing(rows)),
    }),
  )
}

///|
fn expense_detail_item(
  row : SourceRow,
  users : Array[SourceRow],
  units : Array[SourceRow],
  options : Array[SourceRow],
  proceedings : Array[SourceRow],
) -> Json {
  let payload = row.payload
  let user_id = json_text(payload, "user_guid", "")
  let dept_id = json_text(payload, "dept_guid", "")
  let cost_code = json_text(payload, "cost_subject_code", "")
  let proceeding_id = json_text(payload, "proceeding_guid", "")
  let cost_name = expense_option_name(options, cost_code)
  let proceeding_name = expense_proceeding_name(proceedings, proceeding_id)
  Json::object({
    "splitGuid": Json::string(json_text(payload, "split_guid", row.record_id)),
    "user": Json::object({
      "userGuid": Json::string(user_id),
      "userName": Json::string(expense_user_name(users, user_id)),
    }),
    "dept": Json::object({
      "deptGuid": Json::string(dept_id),
      "deptName": Json::string(expense_unit_name(units, dept_id)),
    }),
    "costSubject": Json::object({
      "code": Json::string(cost_code),
      "name": Json::string(cost_name),
    }),
    "proceeding": if proceeding_id.is_empty() {
      Json::null()
    } else {
      Json::object({
        "guid": Json::string(proceeding_id),
        "name": Json::string(proceeding_name),
      })
    },
    "amount": Json::number(json_number(payload, "amount", 0.0)),
  })
}

///|
async fn budget_expense_detail_response(
  expense_guid : String,
  user_code : String?,
) -> Json? raise CompanyServiceError {
  if !valid_identifier(expense_guid) {
    raise fail("invalid expense_guid")
  }
  let rows = expense_source_rows()
  let list = budget_expenses_response(Some(expense_guid), user_code, None)
  let expense = match list {
    None => return None
    Some(value) =>
      match json_field(value, "data") {
        Some(Array(values)) if values.length() > 0 => Some(values[0])
        _ => None
      }
  }
  let details : Array[Json] = []
  for row in rows.details {
    if json_text(row.payload, "expense_guid", "") == expense_guid {
      details.push(
        Json::object({
          "detailGuid": Json::string(
            json_text(row.payload, "detail_guid", row.record_id),
          ),
          "summary": Json::string(json_text(row.payload, "summary", "")),
          "amount": Json::number(json_number(row.payload, "amount", 0.0)),
          "occurDate": Json::string(json_text(row.payload, "occur_date", "")),
        }),
      )
    }
  }
  let splits : Array[Json] = []
  for row in rows.splits {
    if json_text(row.payload, "expense_guid", "") == expense_guid {
      splits.push(
        expense_detail_item(
          row,
          rows.users,
          rows.units,
          rows.options,
          rows.proceedings,
        ),
      )
    }
  }
  Some(
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "expense": expense.unwrap_or(Json::null()),
        "details": Json::array(details),
        "splits": Json::array(splits),
      }),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": expense_coverage(rows),
      "missing_or_empty_source_tables": Json::array(expense_missing(rows)),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
    }),
  )
}

///|
async fn expense_projection_items(
  expense_guid : String?,
  max_rows : Int,
) -> Array[Json] raise CompanyServiceError {
  let query = if expense_guid is None {
    "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_type, aggregate_id, revision, payload, source_event_id FROM company_aggregate_projection WHERE aggregate_type = 'expense_claim' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT " +
    max_rows.to_string()
  } else {
    let value = expense_guid.unwrap()
    if !valid_identifier(value) {
      raise fail("invalid expense_id")
    }
    "SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'), encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'expense_claim' AND aggregate_id = " +
    @postgres.sql_literal(value) +
    " ORDER BY revision DESC LIMIT " +
    max_rows.to_string()
  }
  let result : Array[Json] = []
  for line_view in run_sql(query).split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 5)
      let payload = @json.parse(decode_hex(row[3])) catch {
        _ => raise fail("invalid expense projection JSON")
      }
      result.push(
        Json::object({
          "aggregate_type": Json::string(decode_hex(row[0])),
          "expense_id": Json::string(decode_hex(row[1])),
          "revision": Json::number(parse_decimal(row[2]).to_double()),
          "payload": payload,
          "source_event_id": Json::string(decode_hex(row[4])),
        }),
      )
    }
  }
  result
}

///|
async fn expense_projection_response(
  expense_guid : String?,
) -> (Int, Json) raise CompanyServiceError {
  let items = expense_projection_items(expense_guid, 500)
  match expense_guid {
    None => (200, Json::object({ "items": Json::array(items) }))
    Some(_) if items.is_empty() =>
      (404, Json::object({ "error": Json::string("expense not found") }))
    Some(_) => (200, items[0])
  }
}

///|
fn budget_check_amount(value : Json) -> Double raise CompanyServiceError {
  match value {
    Number(number, ..) => number
    String(text) => parse_number(text)
    _ => raise reject(422, "split amount must be a decimal number")
  }
}

///|
async fn budget_check_response(body : Json) -> Json raise CompanyServiceError {
  let splits = match json_field(body, "splits") {
    Some(Array(values)) => values
    _ => raise reject(422, "splits must be an array")
  }
  let raw = raw_source_rows("cb_cost", 500)
  let data : Array[Json] = []
  for split in splits {
    let code = json_text(
      split,
      "costSubjectCode",
      json_text(split, "cost_subject", ""),
    )
    if code.trim().is_empty() {
      raise reject(422, "costSubjectCode is required")
    }
    let amount = match json_field(split, "amount") {
      Some(value) => budget_check_amount(value)
      None => {
        let amount_minor = json_int(split, "amount_minor", -1)
        if amount_minor < 0 {
          raise reject(422, "split amount must be non-negative")
        }
        amount_minor.to_double() / 100.0
      }
    }
    if amount < 0.0 {
      raise reject(422, "split amount must be non-negative")
    }
    let mut matched : SourceRow? = None
    for row in raw {
      let cost_code = json_text(
        row.payload,
        "cost_code",
        json_text(row.payload, "costCode", ""),
      )
      let match_prefix = if code.length() < 6 {
        code
      } else {
        code[:6].to_owned()
      }
      if cost_code == code || cost_code.has_prefix(match_prefix) {
        matched = Some(row)
        break
      }
    }
    match matched {
      None =>
        data.push(
          Json::object({
            "code": Json::string(code),
            "amount": Json::number(amount),
            "matched": Json::boolean(false),
          }),
        )
      Some(row) => {
        let target = json_number(row.payload, "target_cost", 0.0)
        let used = json_number(row.payload, "zt_cost", 0.0) +
          json_number(row.payload, "ht_alter_amount", 0.0) +
          json_number(row.payload, "dfs_budget", 0.0)
        let remain = target - used
        let over = amount > remain
        data.push(
          Json::object({
            "code": Json::string(code),
            "amount": Json::number(amount),
            "matched": Json::boolean(true),
            "costGuid": Json::string(json_text(row.payload, "cost_guid", "")),
            "costName": Json::string(json_text(row.payload, "cost_name", "")),
            "target": Json::number(target),
            "used": Json::number(used),
            "remain": Json::number(remain),
            "willOver": Json::boolean(over),
            "overAmount": Json::number(if over { amount - remain } else { 0.0 }),
          }),
        )
      }
    }
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(data),
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": Json::object({
      "cb_cost": Json::number(raw.length().to_double()),
    }),
    "missing_or_empty_source_tables": Json::array(
      if raw.is_empty() {
        [Json::string("cb_cost")]
      } else {
        []
      },
    ),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "calculation_only": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
  })
}

///|
fn expense_required_text(
  body : Json,
  key : String,
  free_text : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if !free_text && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn expense_optional_identifier(
  body : Json,
  key : String,
) -> Json raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => Json::null()
    Some(String(value)) => {
      if !value.is_empty() && !valid_identifier(value) {
        raise reject(422, key + " contains unsupported characters")
      }
      Json::string(value)
    }
    _ => raise reject(422, key + " must be text")
  }
}

///|
fn expense_positive_amount(body : Json) -> Int raise CompanyServiceError {
  match json_field(body, "amount_minor") {
    Some(Number(number, ..)) =>
      if number > 0.0 && number == number.to_int().to_double() {
        number.to_int()
      } else {
        raise reject(422, "amount_minor must be a positive integer")
      }
    _ => raise reject(422, "amount_minor must be a positive integer")
  }
}

///|
fn expense_command_request(
  command_type : String,
  expense_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  if command_type == "create" {
    let requested_id = json_text(body, "expense_id", "").trim().to_owned()
    let id = if requested_id.is_empty() {
      "EXP-" + idempotency_key
    } else {
      requested_id
    }
    if !valid_identifier(id) {
      raise reject(422, "expense_id contains unsupported characters")
    }
    let employee_id = expense_required_text(body, "employee_id", false)
    let summary = expense_required_text(body, "summary", true)
    let currency = expense_required_text(body, "currency", false).to_upper()
    if currency.length() != 3 {
      raise reject(422, "currency must be a three-letter code")
    }
    for char in currency.iter() {
      if char < 'A' || char > 'Z' {
        raise reject(422, "currency must be a three-letter code")
      }
    }
    let amount_minor = expense_positive_amount(body)
    let request = Json::object({
      "command_type": Json::string(command_type),
      "expense_id": Json::string(id),
      "employee_id": Json::string(employee_id),
      "summary": Json::string(summary),
      "amount_minor": Json::number(amount_minor.to_double()),
      "currency": Json::string(currency),
      "project_id": expense_optional_identifier(body, "project_id"),
      "cost_subject": expense_optional_identifier(body, "cost_subject"),
      "actor_id": Json::string(actor_id),
    })
    return (id, request)
  }
  let id = match expense_guid {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "expense_id is required")
  }
  let changes : Map[String, Json] = {}
  match json_field(body, "subject") {
    Some(String(value)) if !value.trim().is_empty() =>
      changes.set("summary", Json::string(value.trim().to_owned()))
    Some(_) => raise reject(422, "subject must be non-empty text")
    None =>
      match json_field(body, "summary") {
        Some(String(value)) if !value.trim().is_empty() =>
          changes.set("summary", Json::string(value.trim().to_owned()))
        Some(_) => raise reject(422, "summary must be non-empty text")
        None => ()
      }
  }
  match json_field(body, "amount_minor") {
    Some(Number(number, ..)) =>
      if number > 0.0 && number == number.to_int().to_double() {
        changes.set("amount_minor", Json::number(number.to_int().to_double()))
      } else {
        raise reject(422, "amount_minor must be a positive integer")
      }
    Some(_) => raise reject(422, "amount_minor must be a positive integer")
    None => ()
  }
  for key in ["project_id", "cost_subject"] {
    match json_field(body, key) {
      None => ()
      Some(Null) => changes.set(key, Json::null())
      Some(String(value)) => {
        if !value.is_empty() && !valid_identifier(value) {
          raise reject(422, key + " contains unsupported characters")
        }
        changes.set(key, Json::string(value))
      }
      Some(_) => raise reject(422, key + " must be text")
    }
  }
  if command_type == "update" && changes.is_empty() {
    raise reject(422, "expense update requires a mutable field")
  }
  let request = Json::object({
    "command_type": Json::string(command_type),
    "expense_id": Json::string(id),
    "reason": Json::string(json_text(body, "reason", "")),
    "actor_id": Json::string(actor_id),
    "changes": Json::object(changes),
  })
  (id, request)
}

///|
async fn existing_expense_command(
  idempotency_key : String,
) -> Json? raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_record WHERE record_type = 'company_command' AND source_id = " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    " LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  Some(
    @json.parse(decode_hex(value)) catch {
      _ => raise fail("invalid stored company command receipt")
    },
  )
}

///|
async fn latest_expense_payload(
  expense_guid : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'expense_claim' AND aggregate_id = " +
    @postgres.sql_literal(expense_guid) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid expense projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (String(left), String(right)) => left == right
    (Number(left, ..), Number(right, ..)) => left == right
    (Array(left), Array(right)) =>
      if left.length() != right.length() {
        false
      } else {
        let mut equal = true
        for index in 0..<left.length() {
          if !json_equal(left[index], right[index]) {
            equal = false
          }
        }
        equal
      }
    (Object(left), Object(right)) =>
      if left.length() != right.length() {
        false
      } else {
        let mut equal = true
        left.each((key, value) => {
          match right.get(key) {
            Some(other) if json_equal(value, other) => ()
            _ => equal = false
          }
        })
        equal
      }
    _ => false
  }
}

///|
async fn expense_command(
  command_type : String,
  expense_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let (id, request) = expense_command_request(
    command_type, expense_guid, body, actor_id, idempotency_key,
  )
  match existing_expense_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let result = json_field(existing, "result").unwrap_or(Json::null())
      return (
        200,
        Json::object({
          "command": existing,
          "expense": result,
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_expense_payload(id)
  if command_type == "create" && current is Some(_) {
    raise reject(409, "expense already exists")
  }
  let (current_payload, current_revision) = match current {
    Some(value) => value
    None if command_type != "create" => raise reject(404, "expense not found")
    None => (Json::null(), 0)
  }
  if command_type != "create" {
    let current_state = json_text(current_payload, "state", "")
    let expected = if command_type == "update" || command_type == "submit" {
      "draft"
    } else if command_type == "approve" || command_type == "reject" {
      "submitted"
    } else if command_type == "resubmit" {
      "rejected"
    } else {
      "draft,rejected"
    }
    let state_ok = current_state == expected ||
      (
        command_type == "void" &&
        (current_state == "draft" || current_state == "rejected")
      )
    if !state_ok {
      raise reject(
        409,
        "expense transition " +
        command_type +
        " requires " +
        expected +
        ", found " +
        current_state,
      )
    }
    if command_type == "update" || command_type == "void" {
      let owner = json_text(current_payload, "employee_id", "")
      if !owner.is_empty() && owner != actor_id {
        raise reject(
          403, "only the expense applicant may update or void this expense",
        )
      }
    }
  }
  let event_id = "expense:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_state = if command_type == "create" || command_type == "update" {
    "draft"
  } else if command_type == "submit" || command_type == "resubmit" {
    "submitted"
  } else if command_type == "approve" {
    "approved"
  } else if command_type == "reject" {
    "rejected"
  } else {
    "voided"
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "expense_id": Json::string(id),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "expense_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    @postgres.sql_literal(request_json) +
    "::jsonb || jsonb_build_object('state', 'draft', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "update" {
    @postgres.sql_literal(current_json) +
    "::jsonb || (" +
    @postgres.sql_literal(request_json) +
    "::jsonb->'changes') || jsonb_build_object('state', 'draft', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    ")"
  } else if command_type == "void" {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', 'voided', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("expense." + command_type),
    "aggregate_type": Json::string("expense_claim"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('expense_claim', " +
    @postgres.sql_literal(id) +
    ", " +
    next_revision.to_string() +
    ", " +
    next_payload_sql +
    ", " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "create" {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "expense": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn invoice_money_display(value : Double) -> String {
  let negative = value < 0.0
  let scaled = (if negative { -value } else { value }) * 100.0 + 0.5
  let cents_total = scaled.to_int()
  let whole = cents_total / 100
  let cents = cents_total % 100
  let digits = whole.to_string()
  let mut grouped = ""
  for index in 0..<digits.length() {
    if index > 0 && (digits.length() - index) % 3 == 0 {
      grouped += ","
    }
    grouped += match digits.get_char(index) {
      Some(char) => char.to_string()
      None => ""
    }
  }
  let cents_text = if cents < 10 {
    "0" + cents.to_string()
  } else {
    cents.to_string()
  }
  (if negative { "-" } else { "" }) + "¥" + grouped + "." + cents_text
}

///|
fn round_places(value : Double, places : Int) -> Double {
  let factor = if places == 2 {
    100.0
  } else if places == 4 {
    10000.0
  } else {
    1.0
  }
  let adjusted = if value >= 0.0 {
    value * factor + 0.5
  } else {
    value * factor - 0.5
  }
  if adjusted > 2140000000.0 || adjusted < -2140000000.0 {
    value
  } else {
    adjusted.to_int().to_double() / factor
  }
}

///|
struct CostSourceRows {
  contracts : Array[SourceRow]
  applies : Array[SourceRow]
  plans : Array[SourceRow]
  milestones : Array[SourceRow]
  projects : Array[SourceRow]
  units : Array[SourceRow]
  users : Array[SourceRow]
  tasks : Array[SourceRow]
}

///|
async fn cost_source_rows() -> CostSourceRows raise CompanyServiceError {
  let contracts = raw_source_rows("cb_contract", 500)
  let applies = raw_source_rows("cb_htfk_apply", 500)
  let plans = raw_source_rows("cb_htfkplan", 500)
  let milestones = raw_source_rows("cb_contract_milestone", 500)
  let projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let users = raw_source_rows("sys_user", 500)
  let tasks = raw_source_rows("jd_task", 500)
  { contracts, applies, plans, milestones, projects, units, users, tasks }
}

///|
fn source_payload(
  rows : Array[SourceRow],
  key : String,
  value : String,
) -> Json? {
  for row in rows {
    if row.record_id == value || json_text(row.payload, key, "") == value {
      return Some(row.payload)
    }
  }
  None
}

///|
fn source_name(
  rows : Array[SourceRow],
  key : String,
  id_key : String,
  id : String,
) -> String {
  match source_payload(rows, id_key, id) {
    Some(payload) => json_text(payload, key, id)
    None => id
  }
}

///|
fn source_coverage(rows : CostSourceRows) -> Json {
  Json::object({
    "cb_contract": Json::number(rows.contracts.length().to_double()),
    "cb_contract_milestone": Json::number(rows.milestones.length().to_double()),
    "cb_htfk_apply": Json::number(rows.applies.length().to_double()),
    "cb_htfkplan": Json::number(rows.plans.length().to_double()),
    "ep_project": Json::number(rows.projects.length().to_double()),
    "jd_task": Json::number(rows.tasks.length().to_double()),
    "mu_business_unit": Json::number(rows.units.length().to_double()),
    "sys_user": Json::number(rows.users.length().to_double()),
  })
}

///|
fn source_missing(rows : CostSourceRows) -> Array[Json] {
  let missing : Array[Json] = []
  if rows.contracts.is_empty() {
    missing.push(Json::string("cb_contract"))
  }
  if rows.milestones.is_empty() {
    missing.push(Json::string("cb_contract_milestone"))
  }
  if rows.applies.is_empty() {
    missing.push(Json::string("cb_htfk_apply"))
  }
  if rows.plans.is_empty() {
    missing.push(Json::string("cb_htfkplan"))
  }
  if rows.projects.is_empty() {
    missing.push(Json::string("ep_project"))
  }
  if rows.tasks.is_empty() {
    missing.push(Json::string("jd_task"))
  }
  if rows.units.is_empty() {
    missing.push(Json::string("mu_business_unit"))
  }
  if rows.users.is_empty() {
    missing.push(Json::string("sys_user"))
  }
  missing
}

///|
fn source_metadata(rows : CostSourceRows, command_projection : Bool) -> Json {
  Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": source_coverage(rows),
    "missing_or_empty_source_tables": Json::array(source_missing(rows)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(command_projection),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn source_money(value : Double) -> String raise CompanyServiceError {
  money_display((value * 100.0).to_int())
}

///|
async fn source_contract_row(
  row : SourceRow,
  rows : CostSourceRows,
  paid : Double,
  milestone_count : Int,
) -> Json raise CompanyServiceError {
  let payload = row.payload
  let contract_id = json_text(payload, "contract_guid", row.record_id)
  let project_id = json_text(payload, "proj_guid", "")
  let bu_id = json_text(payload, "bu_guid", "")
  let amount = json_double(payload, "ht_amount", 0.0)
  let alteration = json_double(payload, "sum_alter_amount", 0.0)
  let amount_minor = (amount * 100.0).to_int()
  Json::object({
    "contractGuid": Json::string(contract_id),
    "contractCode": Json::string(
      json_text(payload, "contract_code", contract_id),
    ),
    "contractName": Json::string(
      json_text(payload, "contract_name", contract_id),
    ),
    "buGuid": Json::string(bu_id),
    "buName": Json::string(source_name(rows.units, "bu_name", "bu_guid", bu_id)),
    "projGuid": Json::string(project_id),
    "projName": Json::string(
      source_name(rows.projects, "proj_name", "proj_guid", project_id),
    ),
    "htTypeCode": Json::string(json_text(payload, "ht_type_code", "")),
    "htClass": Json::number(json_int(payload, "ht_class", 0).to_double()),
    "yfProviderName": Json::string(json_text(payload, "yf_provider_name", "")),
    "yfCorporation": Json::string(json_text(payload, "yf_corporation", "")),
    "htAmount": Json::number(amount),
    "sumAlterAmount": Json::number(alteration),
    "currentAmount": Json::number(amount + alteration),
    "signDate": Json::string(json_text(payload, "sign_date", "")),
    "htCfState": Json::string(json_text(payload, "ht_cf_state", "")),
    "jsState": Json::string(json_text(payload, "js_state", "")),
    "costCode": Json::string(json_text(payload, "cost_code", "")),
    "rCode": Json::string(json_text(payload, "r_code", "")),
    "l3Code": Json::string(json_text(payload, "l3_code", "")),
    "cbState": Json::string(json_text(payload, "cb_state", "")),
    "sourceKind": Json::string("imported"),
    "sourceId": Json::string("erp:cb_contract:" + row.record_id),
    "contract_id": Json::string(contract_id),
    "contract_code": Json::string(
      json_text(payload, "contract_code", contract_id),
    ),
    "contract_name": Json::string(
      json_text(payload, "contract_name", contract_id),
    ),
    "project_id": Json::string(project_id),
    "project_name": Json::string(
      source_name(rows.projects, "proj_name", "proj_guid", project_id),
    ),
    "supplier_id": Json::string(json_text(payload, "yf_provider_name", "")),
    "supplier_name": Json::string(json_text(payload, "yf_provider_name", "")),
    "amount_minor": Json::number(amount_minor.to_double()),
    "amount_display": Json::string(source_money(amount)),
    "currency": Json::string("CNY"),
    "sign_date": Json::string(json_text(payload, "sign_date", "")),
    "state": Json::string(
      if json_text(payload, "ht_cf_state", "") == "已终止" ||
        json_text(payload, "ht_cf_state", "") == "作废" {
        "voided"
      } else {
        "active"
      },
    ),
    "paid_amount_display": Json::string(source_money(paid)),
    "milestone_count": Json::string(milestone_count.to_string()),
    "source_kind": Json::string("imported"),
    "paidAmount": Json::number(paid),
    "milestoneCount": Json::number(milestone_count.to_double()),
  })
}

///|
fn source_command_contract(item : Json) -> Json {
  let contract_id = json_text(item, "contract_id", "")
  let amount_minor = json_int(item, "amount_minor", 0)
  let sum_alter_minor = json_int(item, "sum_alter_amount_minor", 0)
  let state = json_text(item, "state", "draft")
  let project_id = json_text(item, "project_id", "")
  let supplier_id = json_text(item, "supplier_id", "")
  let contract_code = json_text(item, "contract_code", contract_id)
  let contract_name = json_text(item, "contract_name", contract_id)
  let supplier_name = json_text(item, "supplier_name", supplier_id)
  let project_name = json_text(item, "project_name", project_id)
  Json::object({
    "contractGuid": Json::string(contract_id),
    "contractCode": Json::string(contract_code),
    "contractName": Json::string(contract_name),
    "buGuid": Json::string(json_text(item, "bu_guid", "")),
    "buName": Json::string(json_text(item, "bu_name", "")),
    "projGuid": Json::string(project_id),
    "projName": Json::string(project_name),
    "htTypeCode": Json::string(json_text(item, "ht_type_code", "")),
    "htClass": Json::number(json_int(item, "ht_class", 0).to_double()),
    "yfProviderName": Json::string(supplier_name),
    "yfCorporation": Json::string(json_text(item, "supplier_corporation", "")),
    "htAmount": Json::number(amount_minor.to_double() / 100.0),
    "sumAlterAmount": Json::number(sum_alter_minor.to_double() / 100.0),
    "currentAmount": Json::number(
      (amount_minor + sum_alter_minor).to_double() / 100.0,
    ),
    "signDate": Json::string(json_text(item, "sign_date", "")),
    "htCfState": Json::string(json_text(item, "ht_cf_state", "")),
    "jsState": Json::string(json_text(item, "js_state", "")),
    "costCode": Json::string(json_text(item, "cost_code", "")),
    "rCode": Json::string(json_text(item, "r_code", "")),
    "l3Code": Json::string(json_text(item, "l3_code", "")),
    "cbState": Json::string(state),
    "sourceKind": Json::string("command"),
    "sourceId": Json::string("moonproj:command:contract:" + contract_id),
    "contract_id": Json::string(contract_id),
    "contract_code": Json::string(contract_code),
    "contract_name": Json::string(contract_name),
    "project_id": Json::string(project_id),
    "project_name": Json::string(project_name),
    "supplier_id": Json::string(supplier_id),
    "supplier_name": Json::string(supplier_name),
    "amount_minor": Json::number(amount_minor.to_double()),
    "amount_display": Json::string(json_text(item, "amount_display", "¥0.00")),
    "currency": Json::string(json_text(item, "currency", "CNY")),
    "sign_date": Json::string(json_text(item, "sign_date", "")),
    "state": Json::string(state),
    "paid_amount_display": Json::string(
      json_text(item, "paid_amount_display", "¥0.00"),
    ),
    "milestoneCount": Json::number(
      json_int(item, "milestone_count", 0).to_double(),
    ),
    "milestone_count": Json::string(json_text(item, "milestone_count", "0")),
    "source_kind": Json::string("command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn source_contract_matches(
  item : Json,
  contract_id : String?,
  bu_guid : String?,
  proj_guid : String?,
  keyword : String?,
) -> Bool {
  if contract_id is Some(value) && json_text(item, "contractGuid", "") != value {
    return false
  }
  if bu_guid is Some(value) && json_text(item, "buGuid", "") != value {
    return false
  }
  if proj_guid is Some(value) && json_text(item, "projGuid", "") != value {
    return false
  }
  match keyword {
    Some(value) => {
      let needle = value.to_lower()
      let haystack = (json_text(item, "contractName", "") +
      " " +
      json_text(item, "contractCode", "") +
      " " +
      json_text(item, "yfProviderName", "")).to_lower()
      haystack.contains(needle)
    }
    None => true
  }
}

///|
async fn source_contract_list(
  contract_id : String?,
  bu_guid : String?,
  proj_guid : String?,
  keyword : String?,
) -> Json raise CompanyServiceError {
  let rows = cost_source_rows()
  let result : Array[Json] = []
  for row in rows.contracts {
    let contract_id_value = json_text(
      row.payload,
      "contract_guid",
      row.record_id,
    )
    let mut paid = 0.0
    for apply in rows.applies {
      if json_text(apply.payload, "contract_guid", "") == contract_id_value {
        let state = json_text(apply.payload, "pay_state", "")
        if state == "完全支付" || state == "部分支付" {
          paid = paid + json_double(apply.payload, "apply_amount", 0.0)
        }
      }
    }
    let mut milestone_count = 0
    for milestone in rows.milestones {
      if json_text(milestone.payload, "contract_guid", "") == contract_id_value {
        milestone_count += 1
      }
    }
    let base = source_contract_row(row, rows, paid, milestone_count)
    if source_contract_matches(base, contract_id, bu_guid, proj_guid, keyword) {
      result.push(base)
    }
  }
  let command_items = contract_items(None)
  for item in command_items {
    if json_text(item, "source_kind", "") == "command" {
      let command = source_command_contract(item)
      if source_contract_matches(
          command, contract_id, bu_guid, proj_guid, keyword,
        ) {
        result.push(command)
      }
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "signDate", "").lexical_compare(
      json_text(left, "signDate", ""),
    )
    if order == 0 {
      json_text(right, "contractGuid", "").lexical_compare(
        json_text(left, "contractGuid", ""),
      )
    } else {
      order
    }
  })
  match
    source_metadata(
      rows,
      result.any(fn(item) { json_text(item, "sourceKind", "") == "command" }),
    ) {
    Object(fields) => {
      fields.set("success", Json::boolean(true))
      fields.set("code", Json::number(0))
      fields.set("data", Json::array(result))
      Json::object(fields)
    }
    _ => raise fail("invalid source metadata")
  }
}

///|
fn source_user_name(rows : Array[SourceRow], user_id : String) -> String {
  match source_payload(rows, "user_id", user_id) {
    Some(payload) =>
      json_text(payload, "emp_name", json_text(payload, "user_name", user_id))
    None => user_id
  }
}

///|
fn source_contract_plans(
  rows : CostSourceRows,
  contract_id : String,
  bu_guid : String,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in rows.plans {
    let payload = row.payload
    if json_text(payload, "contract_guid", "") == contract_id &&
      json_text(payload, "bu_guid", "") == bu_guid {
      let jbr = json_text(payload, "jbr_guid", "")
      result.push(
        Json::object({
          "htfkPlanGuid": Json::string(
            json_text(payload, "htfk_plan_guid", row.record_id),
          ),
          "planPeriod": Json::string(json_text(payload, "plan_period", "")),
          "jhfkDate": Json::string(json_text(payload, "jhfk_date", "")),
          "jhfkAmount": Json::number(json_double(payload, "jhfk_amount", 0.0)),
          "approveState": Json::string(json_text(payload, "approve_state", "")),
          "jbrName": Json::string(source_user_name(rows.users, jbr)),
        }),
      )
    }
  }
  result
}

///|
fn source_contract_applies(
  rows : CostSourceRows,
  contract_id : String,
  bu_guid : String,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in rows.applies {
    let payload = row.payload
    if json_text(payload, "contract_guid", "") == contract_id &&
      json_text(payload, "bu_guid", "") == bu_guid {
      let state = json_text(payload, "pay_state", "")
      let applied_by = json_text(payload, "applied_by", "")
      result.push(
        Json::object({
          "htfkApplyGuid": Json::string(
            json_text(payload, "htfk_apply_guid", row.record_id),
          ),
          "applyCode": Json::string(json_text(payload, "apply_code", "")),
          "subject": Json::string(json_text(payload, "subject", "")),
          "applyState": Json::string(json_text(payload, "apply_state", "")),
          "payState": Json::string(state),
          "applyAmount": Json::number(json_double(payload, "apply_amount", 0.0)),
          "applyDate": Json::string(json_text(payload, "apply_date", "")),
          "appliedByName": Json::string(
            source_user_name(rows.users, applied_by),
          ),
          "milestoneGuid": Json::string(
            json_text(payload, "milestone_guid", ""),
          ),
          "earlyPayFlag": json_field(payload, "early_pay_flag").unwrap_or(
            Json::number(0),
          ),
          "operationState": Json::string(
            if state == "未支付" {
              json_text(payload, "apply_state", "")
            } else {
              state
            },
          ),
        }),
      )
    }
  }
  result
}

///|
fn source_contract_milestones(
  rows : CostSourceRows,
  contract_id : String,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in rows.milestones {
    let payload = row.payload
    if json_text(payload, "contract_guid", "") == contract_id {
      let trigger_value = json_text(payload, "trigger_value", "")
      let task = source_payload(rows.tasks, "task_guid", trigger_value)
      let task_name = match task {
        Some(value) => json_text(value, "task_name", "")
        None => ""
      }
      let task_status = match task {
        Some(value) => json_text(value, "status", "")
        None => ""
      }
      result.push(
        Json::object({
          "milestoneGuid": Json::string(
            json_text(payload, "milestone_guid", row.record_id),
          ),
          "seq": Json::number(json_int(payload, "seq", 0).to_double()),
          "nodeName": Json::string(json_text(payload, "node_name", "")),
          "triggerType": Json::string(json_text(payload, "trigger_type", "")),
          "triggerValue": Json::string(trigger_value),
          "triggerTaskName": Json::string(task_name),
          "triggerTaskStatus": Json::string(task_status),
          "planDate": Json::string(json_text(payload, "plan_date", "")),
          "planAmount": Json::number(json_double(payload, "plan_amount", 0.0)),
          "planPct": Json::number(json_double(payload, "plan_pct", 0.0)),
          "actualAmount": Json::number(
            json_double(payload, "actual_amount", 0.0),
          ),
          "state": Json::string(json_text(payload, "state", "")),
          "reachedAt": Json::string(json_text(payload, "reached_at", "")),
          "notes": Json::string(json_text(payload, "notes", "")),
        }),
      )
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_int(left, "seq", 0) - json_int(right, "seq", 0)
    if order == 0 {
      json_text(left, "milestoneGuid", "").lexical_compare(
        json_text(right, "milestoneGuid", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
async fn source_contract_detail(
  contract_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(contract_id) {
    raise fail("invalid contract_id")
  }
  let rows = cost_source_rows()
  let list = source_contract_list(Some(contract_id), None, None, None)
  let contract = match json_field(list, "data") {
    Some(Array(items)) if !items.is_empty() => items[0]
    _ =>
      return (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("合同不存在"),
        }),
      )
  }
  let bu_guid = json_text(contract, "buGuid", "")
  let plans = source_contract_plans(rows, contract_id, bu_guid)
  let applies = source_contract_applies(rows, contract_id, bu_guid)
  let milestones = source_contract_milestones(rows, contract_id)
  let (command_status, command_detail) = contract_detail_response(contract_id)
  if command_status == 200 {
    match json_field(command_detail, "milestones") {
      Some(Array(items)) =>
        for item in items {
          if json_bool(item, "command_projection", false) {
            milestones.push(item)
          }
        }
      _ => ()
    }
  }
  let paid : Double = applies.fold(init=0.0, fn(total, item) {
    if json_text(item, "payState", "") == "完全支付" ||
      json_text(item, "payState", "") == "部分支付" {
      total + json_double(item, "applyAmount", 0.0)
    } else {
      total
    }
  })
  milestones.sort_by(fn(left, right) {
    let order = json_int(left, "seq", 0) - json_int(right, "seq", 0)
    if order == 0 {
      json_text(left, "milestoneGuid", "").lexical_compare(
        json_text(right, "milestoneGuid", ""),
      )
    } else {
      order
    }
  })
  match contract {
    Object(fields) => {
      fields.set("plans", Json::array(plans))
      fields.set("applies", Json::array(applies))
      fields.set("milestones", Json::array(milestones))
      fields.set("paidAmount", Json::number(paid))
      fields.set("paid_amount_display", Json::string(source_money(paid)))
      fields.set(
        "milestoneCount",
        Json::number(milestones.length().to_double()),
      )
      fields.set(
        "milestone_count",
        Json::string(milestones.length().to_string()),
      )
      let contract_json = Json::object(fields)
      match
        source_metadata(
          rows,
          json_text(contract_json, "sourceKind", "") == "command",
        ) {
        Object(metadata) => {
          metadata.set("success", Json::boolean(true))
          metadata.set("code", Json::number(0))
          metadata.set(
            "data",
            Json::object({
              "contract": contract_json,
              "plans": Json::array(plans),
              "applies": Json::array(applies),
              "milestones": Json::array(milestones),
            }),
          )
          (200, Json::object(metadata))
        }
        _ =>
          (
            500,
            Json::object({ "error": Json::string("invalid source metadata") }),
          )
      }
    }
    _ =>
      (500, Json::object({ "error": Json::string("invalid source contract") }))
  }
}

///|
fn source_payment_matches_view(
  apply_state : String,
  pay_state : String,
  view : String,
  user_id : String,
  applied_by : String,
) -> Bool {
  if view == "mine" && (user_id.is_empty() || applied_by != user_id) {
    return false
  }
  if view == "approving" &&
    !(apply_state == "申请审批中" ||
    apply_state == "Approving" ||
    apply_state == "submitted") {
    return false
  }
  if view == "approved" &&
    !(apply_state == "已审核" ||
    apply_state == "Approved" ||
    apply_state == "approved") {
    return false
  }
  if view == "fullpaid" && pay_state != "完全支付" {
    return false
  }
  true
}

///|
async fn source_payment_row(
  row : SourceRow,
  rows : CostSourceRows,
  contract : Json,
) -> Json raise CompanyServiceError {
  let payload = row.payload
  let apply_id = json_text(payload, "htfk_apply_guid", row.record_id)
  let contract_id = json_text(payload, "contract_guid", "")
  let project_id = json_text(
    payload,
    "proj_guid",
    json_text(contract, "proj_guid", ""),
  )
  let apply_dept = json_text(payload, "apply_dept_guid", "")
  let applied_by = json_text(payload, "applied_by", "")
  let apply_state = json_text(payload, "apply_state", "")
  let pay_state = json_text(payload, "pay_state", "")
  let amount = json_double(payload, "apply_amount", 0.0)
  Json::object({
    "htfkApplyGuid": Json::string(apply_id),
    "applyCode": Json::string(json_text(payload, "apply_code", "")),
    "contractGuid": Json::string(contract_id),
    "contractName": Json::string(
      json_text(contract, "contract_name", contract_id),
    ),
    "yfProviderName": Json::string(json_text(contract, "yf_provider_name", "")),
    "projGuid": Json::string(project_id),
    "projName": Json::string(
      source_name(rows.projects, "proj_name", "proj_guid", project_id),
    ),
    "payClass": Json::string(
      if json_text(payload, "apply_class", "0") == "0" {
        "合同"
      } else {
        "非合同"
      },
    ),
    "operationState": Json::string(
      if pay_state == "未支付" {
        apply_state
      } else {
        pay_state
      },
    ),
    "applyState": Json::string(apply_state),
    "payState": Json::string(pay_state),
    "subject": Json::string(json_text(payload, "subject", "")),
    "applyDeptName": Json::string(
      source_name(rows.units, "bu_name", "bu_guid", apply_dept),
    ),
    "appliedBy": Json::string(applied_by),
    "appliedByName": Json::string(source_user_name(rows.users, applied_by)),
    "applyDate": Json::string(json_text(payload, "apply_date", "")),
    "applyAmount": Json::number(amount),
    "applyTypeCode": Json::string(json_text(payload, "apply_type_code", "")),
    "htfkPlanGuid": Json::string(json_text(payload, "htfk_plan_guid", "")),
    "milestoneGuid": Json::string(json_text(payload, "milestone_guid", "")),
    "sourceKind": Json::string("imported"),
    "sourceId": Json::string("erp:cb_htfk_apply:" + row.record_id),
    "apply_id": Json::string(apply_id),
    "apply_code": Json::string(json_text(payload, "apply_code", "")),
    "contract_id": Json::string(contract_id),
    "contract_name": Json::string(
      json_text(contract, "contract_name", contract_id),
    ),
    "project_name": Json::string(
      source_name(rows.projects, "proj_name", "proj_guid", project_id),
    ),
    "supplier_name": Json::string(json_text(contract, "yf_provider_name", "")),
    "amount_minor": Json::number((amount * 100.0).to_int().to_double()),
    "amount_display": Json::string(source_money(amount)),
    "currency": Json::string("CNY"),
    "apply_date": Json::string(json_text(payload, "apply_date", "")),
    "operation_state": Json::string(
      if pay_state == "未支付" {
        apply_state
      } else {
        pay_state
      },
    ),
    "apply_state": Json::string(apply_state),
    "pay_state": Json::string(pay_state),
    "apply_type_code": Json::string(json_text(payload, "apply_type_code", "")),
    "pay_class": Json::string(
      if json_text(payload, "apply_class", "0") == "0" {
        "合同"
      } else {
        "非合同"
      },
    ),
    "applied_by": Json::string(applied_by),
    "applied_by_name": Json::string(source_user_name(rows.users, applied_by)),
    "source_kind": Json::string("imported"),
    "plan_id": Json::string(json_text(payload, "htfk_plan_guid", "")),
    "milestone_id": Json::string(json_text(payload, "milestone_guid", "")),
  })
}

///|
fn source_command_payment(item : Json) -> Json {
  let apply_id = json_text(item, "apply_id", "")
  let amount_minor = json_int(item, "amount_minor", 0)
  let operation_state = json_text(
    item,
    "operation_state",
    json_text(item, "apply_state", "draft"),
  )
  let apply_state = json_text(item, "apply_state", operation_state)
  let pay_state = json_text(item, "pay_state", "未支付")
  let contract_id = json_text(item, "contract_id", "")
  let project_id = json_text(item, "project_id", "")
  let applied_by = json_text(item, "applied_by", "")
  let applied_by_name = json_text(item, "applied_by_name", applied_by)
  let apply_code = json_text(item, "apply_code", apply_id)
  Json::object({
    "htfkApplyGuid": Json::string(apply_id),
    "applyCode": Json::string(apply_code),
    "contractGuid": Json::string(contract_id),
    "contractName": Json::string(json_text(item, "contract_name", contract_id)),
    "yfProviderName": Json::string(json_text(item, "supplier_name", "")),
    "projGuid": Json::string(project_id),
    "projName": Json::string(json_text(item, "project_name", project_id)),
    "payClass": Json::string(json_text(item, "pay_class", "合同")),
    "operationState": Json::string(operation_state),
    "applyState": Json::string(apply_state),
    "payState": Json::string(pay_state),
    "subject": Json::string(json_text(item, "subject", "")),
    "applyDeptName": Json::string(""),
    "appliedBy": Json::string(applied_by),
    "appliedByName": Json::string(applied_by_name),
    "applyDate": Json::string(json_text(item, "apply_date", "")),
    "applyAmount": Json::number(amount_minor.to_double() / 100.0),
    "applyTypeCode": Json::string(json_text(item, "apply_type_code", "")),
    "htfkPlanGuid": Json::string(json_text(item, "plan_id", "")),
    "milestoneGuid": Json::string(json_text(item, "milestone_id", "")),
    "sourceKind": Json::string("command"),
    "sourceId": Json::string("moonproj:command:payment_application:" + apply_id),
    "apply_id": Json::string(apply_id),
    "apply_code": Json::string(apply_code),
    "contract_id": Json::string(contract_id),
    "contract_name": Json::string(json_text(item, "contract_name", contract_id)),
    "project_name": Json::string(json_text(item, "project_name", project_id)),
    "supplier_name": Json::string(json_text(item, "supplier_name", "")),
    "amount_minor": Json::number(amount_minor.to_double()),
    "amount_display": Json::string(json_text(item, "amount_display", "¥0.00")),
    "currency": Json::string(json_text(item, "currency", "CNY")),
    "apply_date": Json::string(json_text(item, "apply_date", "")),
    "operation_state": Json::string(operation_state),
    "apply_state": Json::string(apply_state),
    "pay_state": Json::string(pay_state),
    "apply_type_code": Json::string(json_text(item, "apply_type_code", "")),
    "pay_class": Json::string(json_text(item, "pay_class", "合同")),
    "applied_by": Json::string(applied_by),
    "applied_by_name": Json::string(applied_by_name),
    "source_kind": Json::string("command"),
    "plan_id": Json::string(json_text(item, "plan_id", "")),
    "milestone_id": Json::string(json_text(item, "milestone_id", "")),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn source_payment_list(
  view : String,
  bu_guid : String?,
  user_id : String?,
) -> Json raise CompanyServiceError {
  if !(view == "all" ||
    view == "mine" ||
    view == "approving" ||
    view == "approved" ||
    view == "fullpaid") {
    raise fail("unsupported payment application view")
  }
  let rows = cost_source_rows()
  let result : Array[Json] = []
  for row in rows.applies {
    let payload = row.payload
    let contract_id = json_text(payload, "contract_guid", "")
    let contract = source_payload(rows.contracts, "contract_guid", contract_id)
    match contract {
      Some(contract_payload) => {
        let applied_by = json_text(payload, "applied_by", "")
        let apply_state = json_text(payload, "apply_state", "")
        let pay_state = json_text(payload, "pay_state", "")
        if json_field(payload, "deleted_at") is None &&
          (
            bu_guid is None ||
            json_text(payload, "bu_guid", "") == bu_guid.unwrap()
          ) &&
          (user_id is None || applied_by == user_id.unwrap()) &&
          source_payment_matches_view(
            apply_state,
            pay_state,
            view,
            user_id.unwrap_or(""),
            applied_by,
          ) {
          result.push(source_payment_row(row, rows, contract_payload))
        }
      }
      None => ()
    }
  }
  let command_items = payment_items(None, "all")
  for item in command_items {
    if json_text(item, "source_kind", "") == "command" {
      let operation_state = json_text(item, "operation_state", "")
      let pay_state = json_text(item, "pay_state", "")
      let applied_by = json_text(item, "applied_by", "")
      let contract_id = json_text(item, "contract_id", "")
      let contract = source_payload(
        rows.contracts,
        "contract_guid",
        contract_id,
      )
      let bu_match = match bu_guid {
        Some(value) =>
          match contract {
            Some(payload) => json_text(payload, "bu_guid", "") == value
            None => false
          }
        None => true
      }
      if bu_match &&
        (user_id is None || applied_by == user_id.unwrap()) &&
        source_payment_matches_view(
          operation_state,
          pay_state,
          view,
          user_id.unwrap_or(""),
          applied_by,
        ) {
        result.push(source_command_payment(item))
      }
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "applyDate", "").lexical_compare(
      json_text(left, "applyDate", ""),
    )
    if order == 0 {
      json_text(right, "htfkApplyGuid", "").lexical_compare(
        json_text(left, "htfkApplyGuid", ""),
      )
    } else {
      order
    }
  })
  match source_metadata(rows, true) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid source metadata")
  }
}

///|
struct BudgetSourceRows {
  users : Array[SourceRow]
  units : Array[SourceRow]
  loans : Array[SourceRow]
  projects : Array[SourceRow]
}

///|
async fn budget_source_rows() -> BudgetSourceRows raise CompanyServiceError {
  let users = raw_source_rows("sys_user", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let loans = raw_source_rows("vcb_loan_simple", 500)
  let projects = raw_source_rows("ep_project", 500)
  { users, units, loans, projects }
}

///|
fn budget_source_coverage(rows : BudgetSourceRows) -> Json {
  Json::object({
    "ep_project": Json::number(rows.projects.length().to_double()),
    "mu_business_unit": Json::number(rows.units.length().to_double()),
    "sys_user": Json::number(rows.users.length().to_double()),
    "vcb_loan_simple": Json::number(rows.loans.length().to_double()),
  })
}

///|
fn budget_source_missing(rows : BudgetSourceRows) -> Array[Json] {
  let missing : Array[Json] = []
  if rows.projects.is_empty() {
    missing.push(Json::string("ep_project"))
  }
  if rows.units.is_empty() {
    missing.push(Json::string("mu_business_unit"))
  }
  if rows.users.is_empty() {
    missing.push(Json::string("sys_user"))
  }
  if rows.loans.is_empty() {
    missing.push(Json::string("vcb_loan_simple"))
  }
  missing
}

///|
fn budget_source_metadata(
  rows : BudgetSourceRows,
  scope_applied : Bool,
) -> Json {
  Json::object({
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": budget_source_coverage(rows),
    "missing_or_empty_source_tables": Json::array(budget_source_missing(rows)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "scope_applied": Json::boolean(scope_applied),
    "scope_required": Json::boolean(!scope_applied),
  })
}

///|
fn budget_unit_hierarchy(rows : Array[SourceRow], bu_guid : String) -> String {
  match source_payload(rows, "bu_guid", bu_guid) {
    Some(payload) => json_text(payload, "hierarchy_code", "")
    None => ""
  }
}

///|
fn budget_unit_allowed(
  rows : Array[SourceRow],
  selected_guid : String,
  user_bu : String,
  user_dept : String,
) -> Bool {
  if selected_guid.is_empty() {
    return true
  }
  let selected_hierarchy = budget_unit_hierarchy(rows, selected_guid)
  for row in rows {
    let guid = json_text(row.payload, "bu_guid", row.record_id)
    let hierarchy = json_text(row.payload, "hierarchy_code", "")
    if guid == selected_guid ||
      (
        !selected_hierarchy.is_empty() &&
        hierarchy.has_prefix(selected_hierarchy + ".")
      ) {
      if user_bu == guid || user_dept == guid {
        return true
      }
    }
  }
  false
}

///|
async fn budget_source_users(
  bu_guid : String?,
) -> Json raise CompanyServiceError {
  match bu_guid {
    Some(value) if !valid_identifier(value) => raise fail("invalid bu_guid")
    _ => ()
  }
  let rows = budget_source_rows()
  let selected_guid = bu_guid.unwrap_or("")
  let result : Array[Json] = []
  for row in rows.users {
    let payload = row.payload
    if json_bool(payload, "enabled", false) {
      let user_bu = json_text(payload, "bu_guid", "")
      let user_dept = json_text(payload, "dept_guid", "")
      if budget_unit_allowed(rows.units, selected_guid, user_bu, user_dept) {
        result.push(
          Json::object({
            "userId": Json::string(json_text(payload, "user_id", row.record_id)),
            "empName": Json::string(
              json_text(
                payload,
                "emp_name",
                json_text(payload, "user_name", ""),
              ),
            ),
            "deptGuid": Json::string(user_dept),
            "buGuid": Json::string(user_bu),
            "sourceKind": Json::string("imported"),
            "sourceId": Json::string("erp:sys_user:" + row.record_id),
          }),
        )
      }
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(left, "empName", "").lexical_compare(
      json_text(right, "empName", ""),
    )
    if order == 0 {
      json_text(left, "userId", "").lexical_compare(
        json_text(right, "userId", ""),
      )
    } else {
      order
    }
  })
  match budget_source_metadata(rows, !selected_guid.is_empty()) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid budget metadata")
  }
}

///|
async fn budget_source_loan_balance(
  user_code : String?,
  user_id : String?,
) -> (Int, Json) raise CompanyServiceError {
  match user_code {
    Some(value) if !valid_identifier(value) => raise fail("invalid user_code")
    _ => ()
  }
  match user_id {
    Some(value) if !valid_identifier(value) => raise fail("invalid user_id")
    _ => ()
  }
  let rows = budget_source_rows()
  let mut selected_id = user_id.unwrap_or("")
  match user_code {
    Some(code) =>
      match find_user(rows.users, code) {
        Some(row) =>
          selected_id = json_text(row.payload, "user_id", row.record_id)
        None =>
          return (
            404,
            Json::object({
              "success": Json::boolean(false),
              "code": Json::number(43001),
              "message": Json::string("用户不存在"),
            }),
          )
      }
    None => ()
  }
  let result : Array[Json] = []
  for row in rows.loans {
    let payload = row.payload
    let applied_by = json_text(payload, "applied_by", "")
    let apply_state = json_text(payload, "apply_state", "")
    let remain = json_double(payload, "remain_amount", 0.0)
    if (selected_id.is_empty() || applied_by == selected_id) &&
      (
        apply_state == "Approved" ||
        apply_state == "已审核" ||
        apply_state == "approved"
      ) &&
      remain > 0.0 &&
      json_field(payload, "deleted_at") is None {
      result.push(
        Json::object({
          "loanGuid": Json::string(
            json_text(payload, "loan_guid", row.record_id),
          ),
          "loanCode": Json::string(json_text(payload, "loan_code", "")),
          "subject": Json::string(json_text(payload, "subject", "")),
          "remainAmount": Json::number(remain),
          "loanAmount": Json::number(json_double(payload, "loan_amount", 0.0)),
          "applyDate": Json::string(json_text(payload, "apply_date", "")),
          "sourceKind": Json::string("imported"),
          "sourceId": Json::string("erp:vcb_loan_simple:" + row.record_id),
        }),
      )
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(left, "applyDate", "").lexical_compare(
      json_text(right, "applyDate", ""),
    )
    if order == 0 {
      json_text(left, "loanGuid", "").lexical_compare(
        json_text(right, "loanGuid", ""),
      )
    } else {
      order
    }
  })
  let total = result.fold(init=0.0, fn(sum, item) {
    sum + json_double(item, "remainAmount", 0.0)
  })
  match budget_source_metadata(rows, !selected_id.is_empty()) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set(
        "data",
        Json::object({
          "total": Json::number(total),
          "loans": Json::array(result),
        }),
      )
      (200, Json::object(metadata))
    }
    _ =>
      (500, Json::object({ "error": Json::string("invalid budget metadata") }))
  }
}

///|
struct WorkflowSourceRows {
  process_defs : Array[SourceRow]
  step_defs : Array[SourceRow]
  step_assignees : Array[SourceRow]
  users : Array[SourceRow]
  instances : Array[SourceRow]
  actions : Array[SourceRow]
}

///|
async fn workflow_source_rows() -> WorkflowSourceRows raise CompanyServiceError {
  let process_defs = raw_source_rows("wf_process_def", 500)
  let step_defs = raw_source_rows("wf_step_def", 500)
  let step_assignees = raw_source_rows("wf_step_assignee", 500)
  let users = raw_source_rows("sys_user", 500)
  let instances = raw_source_rows("wf_process_instance", 500)
  let actions = raw_source_rows("wf_step_action", 500)
  { process_defs, step_defs, step_assignees, users, instances, actions }
}

///|
fn workflow_source_coverage(rows : WorkflowSourceRows) -> Json {
  Json::object({
    "sys_user": Json::number(rows.users.length().to_double()),
    "wf_process_def": Json::number(rows.process_defs.length().to_double()),
    "wf_process_instance": Json::number(rows.instances.length().to_double()),
    "wf_step_action": Json::number(rows.actions.length().to_double()),
    "wf_step_assignee": Json::number(rows.step_assignees.length().to_double()),
    "wf_step_def": Json::number(rows.step_defs.length().to_double()),
  })
}

///|
fn workflow_source_missing(rows : WorkflowSourceRows) -> Array[Json] {
  let missing : Array[Json] = []
  if rows.users.is_empty() {
    missing.push(Json::string("sys_user"))
  }
  if rows.process_defs.is_empty() {
    missing.push(Json::string("wf_process_def"))
  }
  if rows.instances.is_empty() {
    missing.push(Json::string("wf_process_instance"))
  }
  if rows.actions.is_empty() {
    missing.push(Json::string("wf_step_action"))
  }
  if rows.step_assignees.is_empty() {
    missing.push(Json::string("wf_step_assignee"))
  }
  if rows.step_defs.is_empty() {
    missing.push(Json::string("wf_step_def"))
  }
  missing
}

///|
fn workflow_source_metadata(rows : WorkflowSourceRows) -> Json {
  Json::object({
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": workflow_source_coverage(rows),
    "missing_or_empty_source_tables": Json::array(workflow_source_missing(rows)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn workflow_resolve_user_id(
  rows : WorkflowSourceRows,
  user_id : String?,
  user_code : String?,
) -> String? raise CompanyServiceError {
  match user_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid user_id")
      }
      Some(value)
    }
    None =>
      match user_code {
        Some(value) => {
          if !valid_identifier(value) {
            raise fail("invalid user_code")
          }
          match find_user(rows.users, value) {
            Some(row) => Some(json_text(row.payload, "user_id", row.record_id))
            None => None
          }
        }
        None => None
      }
  }
}

///|
fn workflow_instance_value(
  payload : Json,
  key : String,
  fallback : String,
) -> String {
  json_text(payload, key, fallback)
}

///|
fn workflow_instance_json(row : SourceRow) -> Json {
  let payload = row.payload
  Json::object({
    "processInstanceGuid": Json::string(
      workflow_instance_value(payload, "process_instance_guid", row.record_id),
    ),
    "processGuid": Json::string(
      workflow_instance_value(payload, "process_guid", ""),
    ),
    "processName": Json::string(
      workflow_instance_value(payload, "process_name", ""),
    ),
    "processKey": Json::string(
      workflow_instance_value(payload, "process_key", ""),
    ),
    "bizType": Json::string(workflow_instance_value(payload, "biz_type", "")),
    "bizDataGuid": Json::string(
      workflow_instance_value(payload, "biz_data_guid", ""),
    ),
    "status": Json::string(workflow_instance_value(payload, "status", "")),
    "initiatorGuid": Json::string(
      workflow_instance_value(payload, "initiator_guid", ""),
    ),
    "buGuid": Json::string(workflow_instance_value(payload, "bu_guid", "")),
    "initiatedAt": Json::string(
      workflow_instance_value(payload, "initiated_at", ""),
    ),
    "completedAt": Json::string(
      workflow_instance_value(payload, "completed_at", ""),
    ),
    "currentStepOrder": json_field(payload, "current_step_order").unwrap_or(
      Json::number(0),
    ),
    "sourceId": Json::string("erp:wf_process_instance:" + row.record_id),
  })
}

///|
fn workflow_action_json(row : SourceRow) -> Json {
  let payload = row.payload
  Json::object({
    "actionGuid": Json::string(
      workflow_instance_value(payload, "action_guid", row.record_id),
    ),
    "processInstanceGuid": Json::string(
      workflow_instance_value(payload, "process_instance_guid", ""),
    ),
    "stepOrder": json_field(payload, "step_order").unwrap_or(Json::number(0)),
    "stepName": Json::string(workflow_instance_value(payload, "step_name", "")),
    "assigneeGuid": Json::string(
      workflow_instance_value(
        payload,
        "assignee_guid",
        workflow_instance_value(payload, "operator_guid", ""),
      ),
    ),
    "decision": Json::string(workflow_instance_value(payload, "decision", "")),
    "comment": Json::string(workflow_instance_value(payload, "comment", "")),
    "actionTime": Json::string(
      workflow_instance_value(
        payload,
        "action_time",
        workflow_instance_value(payload, "created_at", ""),
      ),
    ),
    "sourceId": Json::string("erp:wf_step_action:" + row.record_id),
  })
}

///|
fn workflow_action_list(
  rows : Array[SourceRow],
  instance_id : String?,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in rows {
    let item = workflow_action_json(row)
    let current_instance = json_text(item, "processInstanceGuid", "")
    if instance_id is None || current_instance == instance_id.unwrap() {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(left, "actionTime", "").lexical_compare(
      json_text(right, "actionTime", ""),
    )
    if order == 0 {
      json_text(left, "actionGuid", "").lexical_compare(
        json_text(right, "actionGuid", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
fn workflow_user_name(rows : Array[SourceRow], user_id : String) -> String {
  match source_payload(rows, "user_id", user_id) {
    Some(payload) =>
      json_text(payload, "emp_name", json_text(payload, "user_name", user_id))
    None => user_id
  }
}

///|
async fn workflow_tasks_mine(
  user_id : String?,
  user_code : String?,
) -> Json raise CompanyServiceError {
  let rows = workflow_source_rows()
  let selected = workflow_resolve_user_id(rows, user_id, user_code)
  let actions = workflow_action_list(rows.actions, None)
  let result : Array[Json] = []
  for source_row in rows.instances {
    let instance = workflow_instance_json(source_row)
    let status = json_text(instance, "status", "")
    if status == "Running" ||
      status == "Approving" ||
      status == "running" ||
      status == "submitted" {
      let instance_id = json_text(instance, "processInstanceGuid", "")
      let instance_actions = actions.filter(fn(action) {
        json_text(action, "processInstanceGuid", "") == instance_id
      })
      let assigned = match selected {
        Some(value) =>
          instance_actions.is_empty() ||
          instance_actions.any(fn(action) {
            json_text(action, "assigneeGuid", "") == value
          })
        None => true
      }
      if assigned {
        result.push(
          Json::object({
            "processInstanceGuid": Json::string(instance_id),
            "processName": Json::string(json_text(instance, "processName", "")),
            "bizType": Json::string(json_text(instance, "bizType", "")),
            "bizDataGuid": Json::string(json_text(instance, "bizDataGuid", "")),
            "currentStep": Json::object({
              "stepOrder": json_field(instance, "currentStepOrder").unwrap_or(
                Json::number(0),
              ),
              "stepName": Json::string(""),
            }),
            "initiator": Json::object({
              "userId": Json::string(json_text(instance, "initiatorGuid", "")),
              "empName": Json::string(""),
            }),
            "initiatedAt": Json::string(json_text(instance, "initiatedAt", "")),
          }),
        )
      }
    }
  }
  workflow_task_envelope(rows, result, selected is Some(_))
}

///|
async fn workflow_tasks_initiated(
  user_id : String?,
  user_code : String?,
) -> Json raise CompanyServiceError {
  let rows = workflow_source_rows()
  let selected = workflow_resolve_user_id(rows, user_id, user_code)
  let result : Array[Json] = []
  for source_row in rows.instances {
    let instance = workflow_instance_json(source_row)
    if selected is None ||
      json_text(instance, "initiatorGuid", "") == selected.unwrap() {
      result.push(
        Json::object({
          "processInstanceGuid": json_field(instance, "processInstanceGuid").unwrap_or(
            Json::string(""),
          ),
          "processName": json_field(instance, "processName").unwrap_or(
            Json::string(""),
          ),
          "bizType": json_field(instance, "bizType").unwrap_or(Json::string("")),
          "bizDataGuid": json_field(instance, "bizDataGuid").unwrap_or(
            Json::string(""),
          ),
          "status": json_field(instance, "status").unwrap_or(Json::string("")),
          "initiatedAt": json_field(instance, "initiatedAt").unwrap_or(
            Json::string(""),
          ),
          "completedAt": json_field(instance, "completedAt").unwrap_or(
            Json::string(""),
          ),
          "currentStepOrder": json_field(instance, "currentStepOrder").unwrap_or(
            Json::number(0),
          ),
        }),
      )
    }
  }
  workflow_task_envelope(rows, result, selected is Some(_))
}

///|
async fn workflow_history(
  user_id : String?,
  user_code : String?,
) -> Json raise CompanyServiceError {
  let rows = workflow_source_rows()
  let selected = workflow_resolve_user_id(rows, user_id, user_code)
  let result : Array[Json] = []
  let actions = workflow_action_list(rows.actions, None)
  for action in actions {
    let assignee = json_text(action, "assigneeGuid", "")
    if selected is None || assignee == selected.unwrap() {
      let instance_id = json_text(action, "processInstanceGuid", "")
      match
        source_payload(rows.instances, "process_instance_guid", instance_id) {
        Some(payload) => {
          let instance = workflow_instance_json({
            record_id: instance_id,
            source_id: "",
            payload,
          })
          result.push(
            Json::object({
              "processInstanceGuid": json_field(instance, "processInstanceGuid").unwrap_or(
                Json::string(""),
              ),
              "processName": json_field(instance, "processName").unwrap_or(
                Json::string(""),
              ),
              "bizType": json_field(instance, "bizType").unwrap_or(
                Json::string(""),
              ),
              "bizDataGuid": json_field(instance, "bizDataGuid").unwrap_or(
                Json::string(""),
              ),
              "status": json_field(instance, "status").unwrap_or(
                Json::string(""),
              ),
              "initiatedAt": json_field(instance, "initiatedAt").unwrap_or(
                Json::string(""),
              ),
              "completedAt": json_field(instance, "completedAt").unwrap_or(
                Json::string(""),
              ),
              "currentStepOrder": json_field(instance, "currentStepOrder").unwrap_or(
                Json::number(0),
              ),
              "initiator": Json::object({
                "empName": Json::string(
                  workflow_user_name(
                    rows.users,
                    json_text(instance, "initiatorGuid", ""),
                  ),
                ),
              }),
              "myLastActionTime": json_field(action, "actionTime").unwrap_or(
                Json::string(""),
              ),
              "myLastDecision": json_field(action, "decision").unwrap_or(
                Json::string(""),
              ),
            }),
          )
        }
        None => ()
      }
    }
  }
  workflow_task_envelope(rows, result, selected is Some(_))
}

///|
fn workflow_task_envelope(
  rows : WorkflowSourceRows,
  result : Array[Json],
  scope_applied : Bool,
) -> Json raise CompanyServiceError {
  match workflow_source_metadata(rows) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      metadata.set("scope_applied", Json::boolean(scope_applied))
      Json::object(metadata)
    }
    _ => raise fail("invalid workflow metadata")
  }
}

///|
fn workflow_detail_data(rows : WorkflowSourceRows, instance : Json) -> Json {
  let process_id = json_text(instance, "processGuid", "")
  let steps : Array[Json] = []
  for row in rows.step_defs {
    let payload = row.payload
    if json_text(payload, "process_guid", "") == process_id {
      let step_id = json_text(payload, "step_guid", row.record_id)
      let assignees : Array[Json] = []
      for assignee_row in rows.step_assignees {
        let assignee = assignee_row.payload
        if json_text(assignee, "step_guid", "") == step_id {
          let user_id = json_text(assignee, "assignee_user_guid", "")
          assignees.push(
            Json::object({
              "assigneeGuid": Json::string(
                json_text(assignee, "assignee_guid", assignee_row.record_id),
              ),
              "userGuid": Json::string(user_id),
              "userCode": Json::string(
                match source_payload(rows.users, "user_id", user_id) {
                  Some(user) => json_text(user, "user_code", "")
                  None => ""
                },
              ),
              "userName": Json::string(workflow_user_name(rows.users, user_id)),
              "weight": json_field(assignee, "weight").unwrap_or(
                Json::number(1),
              ),
            }),
          )
        }
      }
      steps.push(
        Json::object({
          "stepGuid": Json::string(step_id),
          "stepOrder": json_field(payload, "step_order").unwrap_or(
            Json::number(0),
          ),
          "stepName": Json::string(json_text(payload, "step_name", "")),
          "threshold": json_field(payload, "threshold").unwrap_or(
            Json::number(1),
          ),
          "stepKey": Json::string(json_text(payload, "step_key", "")),
          "stepStatus": Json::string(json_text(payload, "status", "")),
          "assignees": Json::array(assignees),
        }),
      )
    }
  }
  steps.sort_by(fn(left, right) {
    let order = json_int(left, "stepOrder", 0) - json_int(right, "stepOrder", 0)
    if order == 0 {
      json_text(left, "stepGuid", "").lexical_compare(
        json_text(right, "stepGuid", ""),
      )
    } else {
      order
    }
  })
  let process = source_payload(rows.process_defs, "process_guid", process_id)
  let initiator_id = json_text(instance, "initiatorGuid", "")
  let actions = workflow_action_list(
    rows.actions,
    Some(json_text(instance, "processInstanceGuid", "")),
  )
  let action_items : Array[Json] = []
  for action in actions {
    let assignee_id = json_text(action, "assigneeGuid", "")
    action_items.push(
      Json::object({
        "actionGuid": json_field(action, "actionGuid").unwrap_or(
          Json::string(""),
        ),
        "processInstanceGuid": json_field(action, "processInstanceGuid").unwrap_or(
          Json::string(""),
        ),
        "stepOrder": json_field(action, "stepOrder").unwrap_or(Json::number(0)),
        "stepName": json_field(action, "stepName").unwrap_or(Json::string("")),
        "assigneeGuid": json_field(action, "assigneeGuid").unwrap_or(
          Json::string(""),
        ),
        "decision": json_field(action, "decision").unwrap_or(Json::string("")),
        "comment": json_field(action, "comment").unwrap_or(Json::string("")),
        "actionTime": json_field(action, "actionTime").unwrap_or(
          Json::string(""),
        ),
        "sourceId": json_field(action, "sourceId").unwrap_or(Json::string("")),
        "assigneeEmpName": Json::string(
          workflow_user_name(rows.users, assignee_id),
        ),
      }),
    )
  }
  Json::object({
    "instance": Json::object({
      "processInstanceGuid": json_field(instance, "processInstanceGuid").unwrap_or(
        Json::string(""),
      ),
      "bizType": json_field(instance, "bizType").unwrap_or(Json::string("")),
      "bizDataGuid": json_field(instance, "bizDataGuid").unwrap_or(
        Json::string(""),
      ),
      "status": json_field(instance, "status").unwrap_or(Json::string("")),
      "initiatorGuid": json_field(instance, "initiatorGuid").unwrap_or(
        Json::string(""),
      ),
      "initiatedAt": json_field(instance, "initiatedAt").unwrap_or(
        Json::string(""),
      ),
      "completedAt": json_field(instance, "completedAt").unwrap_or(
        Json::string(""),
      ),
      "currentStepOrder": json_field(instance, "currentStepOrder").unwrap_or(
        Json::number(0),
      ),
    }),
    "processName": Json::string(
      match process {
        Some(value) =>
          json_text(
            value,
            "process_name",
            json_text(instance, "processKey", ""),
          )
        None =>
          json_text(
            instance,
            "processName",
            json_text(instance, "processKey", ""),
          )
      },
    ),
    "initiator": Json::object({
      "userId": Json::string(initiator_id),
      "empName": Json::string(workflow_user_name(rows.users, initiator_id)),
    }),
    "steps": Json::array(steps),
    "actions": Json::array(action_items),
  })
}

///|
async fn workflow_instance_detail(
  instance_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(instance_id) {
    raise fail("invalid process_instance_id")
  }
  let rows = workflow_source_rows()
  match source_payload(rows.instances, "process_instance_guid", instance_id) {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("流程实例不存在"),
        }),
      )
    Some(payload) => {
      let instance = workflow_instance_json({
        record_id: instance_id,
        source_id: "",
        payload,
      })
      match workflow_source_metadata(rows) {
        Object(metadata) => {
          metadata.set("success", Json::boolean(true))
          metadata.set("code", Json::number(0))
          metadata.set("data", workflow_detail_data(rows, instance))
          (200, Json::object(metadata))
        }
        _ =>
          (
            500,
            Json::object({ "error": Json::string("invalid workflow metadata") }),
          )
      }
    }
  }
}

///|
async fn workflow_instance_by_biz(
  biz_type : String,
  biz_data_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(biz_type) || !valid_identifier(biz_data_guid) {
    raise fail("invalid workflow business identity")
  }
  let rows = workflow_source_rows()
  let mut selected : SourceRow? = None
  for row in rows.instances {
    let payload = row.payload
    if json_text(payload, "biz_type", "") == biz_type &&
      json_text(payload, "biz_data_guid", "") == biz_data_guid {
      match selected {
        None => selected = Some(row)
        Some(current) =>
          if json_text(payload, "initiated_at", "") >
            json_text(current.payload, "initiated_at", "") {
            selected = Some(row)
          }
      }
    }
  }
  let data = match selected {
    None => Json::null()
    Some(row) => {
      let instance = workflow_instance_json(row)
      workflow_detail_data(rows, instance)
    }
  }
  match workflow_source_metadata(rows) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", data)
      Json::object(metadata)
    }
    _ => raise fail("invalid workflow metadata")
  }
}

///|
struct DynamicSourceRows {
  costs : Array[SourceRow]
  projects : Array[SourceRow]
}

///|
async fn dynamic_source_rows() -> DynamicSourceRows raise CompanyServiceError {
  let costs = raw_source_rows("cb_cost", 500)
  let projects = raw_source_rows("ep_project", 500)
  { costs, projects }
}

///|
fn dynamic_project_name(rows : Array[SourceRow], project_id : String) -> String {
  source_name(rows, "proj_name", "proj_guid", project_id)
}

///|
fn dynamic_item(
  payload : Json,
  project_name : String,
  source_kind : String,
  source_id : String,
) -> Json {
  let command = source_kind == "command"
  let target = if command {
    json_int(payload, "target_cost_minor", 0).to_double() / 100.0
  } else {
    json_double(payload, "target_cost", 0.0)
  }
  let alteration = if command {
    json_int(payload, "ht_alter_amount_minor", 0).to_double() / 100.0
  } else {
    json_double(payload, "ht_alter_amount", 0.0)
  }
  let committed = if command {
    json_int(payload, "zt_cost_minor", 0).to_double() / 100.0
  } else {
    json_double(payload, "zt_cost", 0.0)
  }
  let budget = if command {
    json_int(payload, "dfs_budget_minor", 0).to_double() / 100.0
  } else {
    json_double(payload, "dfs_budget", 0.0)
  }
  let change = if command {
    json_int(payload, "yg_alter_minor", 0).to_double() / 100.0
  } else {
    json_double(payload, "yg_alter", 0.0)
  }
  let dynamic = round_places(alteration + committed + budget + change, 2)
  let deviation = if target > 0.0 {
    Json::number(round_places((target - dynamic) / target * 100.0, 4))
  } else {
    Json::null()
  }
  let cost_id = json_text(
    payload,
    if command {
      "cost_id"
    } else {
      "cost_guid"
    },
    source_id,
  )
  let cost_code = json_text(payload, "cost_code", cost_id)
  let source_fields : Map[String, Json] = {
    "costGuid": Json::string(cost_id),
    "costCode": Json::string(cost_code),
    "costName": Json::string(json_text(payload, "cost_name", cost_id)),
    "costLevel": Json::number(json_int(payload, "cost_level", 0).to_double()),
    "parentCostGuid": Json::string(
      json_text(
        payload,
        if command {
          "parent_cost_id"
        } else {
          "parent_cost_guid"
        },
        "",
      ),
    ),
    "isEndCost": Json::boolean(json_bool(payload, "is_end_cost", true)),
    "A_targetCost": Json::number(target),
    "B_dtCost": Json::number(dynamic),
    "C_deviationPct": deviation,
    "D_htAlterAmount": Json::number(alteration),
    "E_ztCost": Json::number(committed),
    "F_dfsBudget": Json::number(budget),
    "G_ygAlter": Json::number(change),
    "H_layoutSpare": Json::number(round_places(target - dynamic, 2)),
    "remarks": Json::string(json_text(payload, "remarks", "")),
    "projectName": Json::string(project_name),
    "sourceKind": Json::string(source_kind),
  }
  if command {
    source_fields.set(
      "sourceId",
      Json::string("moonproj:command:dynamic_cost:" + cost_id),
    )
    source_fields.set("command_projection", Json::boolean(true))
    source_fields.set("authorizing", Json::boolean(false))
    source_fields.set("persisted", Json::boolean(true))
    source_fields.set("provider_execution", Json::boolean(false))
    source_fields.set("cash_effect", Json::boolean(false))
    source_fields.set("accounting_effect", Json::boolean(false))
    source_fields.set("tax_effect", Json::boolean(false))
  }
  Json::object(source_fields)
}

///|
async fn dynamic_command_items(
  project_id : String,
  project_name : String,
) -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    [
      "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex')",
      "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload",
      "FROM company_aggregate_projection WHERE aggregate_type = 'dynamic_cost_command'",
      "ORDER BY aggregate_id, revision DESC) latest",
      "WHERE coalesce(payload->>'state', '') <> 'deleted' AND payload->>'project_id' = " +
      @postgres.sql_literal(project_id),
      "ORDER BY aggregate_id LIMIT 500",
    ].join("\n"),
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 2)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid dynamic-cost command projection JSON")
      }
      result.push(
        dynamic_item(payload, project_name, "command", decode_hex(row[0])),
      )
    }
  }
  result
}

///|
async fn dynamic_cost_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise fail("invalid project_id")
  }
  let rows = dynamic_source_rows()
  let project_name = dynamic_project_name(rows.projects, project_id)
  let items : Array[Json] = []
  for row in rows.costs {
    let payload = row.payload
    if json_text(payload, "proj_guid", "") == project_id &&
      json_field(payload, "deleted_at") is None {
      items.push(dynamic_item(payload, project_name, "imported", row.record_id))
    }
  }
  let command_items = dynamic_command_items(project_id, project_name)
  for item in command_items {
    items.push(item)
  }
  items.sort_by(fn(left, right) {
    let order = json_text(left, "costCode", "").lexical_compare(
      json_text(right, "costCode", ""),
    )
    if order == 0 {
      json_text(left, "costGuid", "").lexical_compare(
        json_text(right, "costGuid", ""),
      )
    } else {
      order
    }
  })
  let end_rows = items.filter(fn(item) { json_bool(item, "isEndCost", false) })
  let target_total = round_places(
    end_rows.fold(init=0.0, fn(sum, item) {
      sum + json_double(item, "A_targetCost", 0.0)
    }),
    2,
  )
  let dynamic_total = round_places(
    end_rows.fold(init=0.0, fn(sum, item) {
      sum + json_double(item, "B_dtCost", 0.0)
    }),
    2,
  )
  let deviation = if target_total > 0.0 {
    Json::number(
      round_places((target_total - dynamic_total) / target_total * 100.0, 4),
    )
  } else {
    Json::null()
  }
  let coverage = Json::object({
    "cb_cost": Json::number(rows.costs.length().to_double()),
    "ep_project": Json::number(rows.projects.length().to_double()),
  })
  let missing : Array[Json] = []
  if rows.costs.is_empty() {
    missing.push(Json::string("cb_cost"))
  }
  if rows.projects.is_empty() {
    missing.push(Json::string("ep_project"))
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "items": Json::array(items),
      "summary": Json::object({
        "A_targetCost": Json::number(target_total),
        "B_dtCost": Json::number(dynamic_total),
        "C_deviationPct": deviation,
        "H_layoutSpare": Json::number(
          round_places(target_total - dynamic_total, 2),
        ),
        "endCount": Json::number(end_rows.length().to_double()),
        "projectName": Json::string(project_name),
      }),
    }),
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(!command_items.is_empty()),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn dynamic_cost_remarks_response(
  cost_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(cost_id) {
    raise fail("invalid cost_id")
  }
  let rows = dynamic_source_rows()
  let mut selected : (Json, String)? = None
  for row in rows.costs {
    let payload = row.payload
    if json_text(payload, "cost_guid", row.record_id) == cost_id &&
      json_field(payload, "deleted_at") is None {
      selected = Some((payload, "imported"))
    }
  }
  if selected is None {
    let output = run_sql(
      "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'dynamic_cost_command' AND aggregate_id = " +
      @postgres.sql_literal(cost_id) +
      " ORDER BY revision DESC LIMIT 1",
    )
    let trimmed = output.trim().to_owned()
    if !trimmed.is_empty() {
      let payload = @json.parse(decode_hex(trimmed)) catch {
        _ => raise fail("invalid dynamic-cost command projection JSON")
      }
      if json_text(payload, "state", "") != "deleted" {
        selected = Some((payload, "command"))
      }
    }
  }
  match selected {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("科目不存在"),
        }),
      )
    Some((payload, source_kind)) => {
      let project_id = json_text(
        payload,
        if source_kind == "command" {
          "project_id"
        } else {
          "proj_guid"
        },
        "",
      )
      let project_name = dynamic_project_name(rows.projects, project_id)
      let command = source_kind == "command"
      (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "costCode": Json::string(json_text(payload, "cost_code", "")),
            "costName": Json::string(json_text(payload, "cost_name", "")),
            "remarks": Json::string(json_text(payload, "remarks", "")),
            "projectName": Json::string(project_name),
            "sourceKind": Json::string(source_kind),
          }),
          "source_kind": Json::string(source_kind),
          "source_coverage": Json::object({
            "cb_cost": Json::number(rows.costs.length().to_double()),
            "ep_project": Json::number(rows.projects.length().to_double()),
          }),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(command),
          "command_projection": Json::boolean(command),
          "provider_execution": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
  }
}

///|
fn delivery_source_metadata(coverage : Json, missing : Array[Json]) -> Json {
  Json::object({
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn delivery_progress_item(row : SourceRow) -> Json {
  let payload = row.payload
  let progress_id = row.record_id
  let project_id = json_text(payload, "proj_guid", "")
  let value : Map[String, Json] = {
    "progress_id": Json::string(progress_id),
    "project_id": Json::string(project_id),
    "building_no": Json::string(json_text(payload, "building_no", "")),
    "stage": Json::string(json_text(payload, "stage", "")),
    "plan_date": Json::string(json_text(payload, "plan_date", "")),
    "plan_pct": Json::string(json_text(payload, "plan_pct", "0")),
    "actual_pct": Json::string(json_text(payload, "actual_pct", "0")),
    "actual_date": Json::string(json_text(payload, "actual_date", "")),
    "contract_id": Json::string(json_text(payload, "contract_guid", "")),
    "milestone_id": Json::string(json_text(payload, "milestone_guid", "")),
    "state": Json::string(json_text(payload, "state", "pending")),
    "remark": Json::string(json_text(payload, "remark", "")),
    "reported_by": Json::string(json_text(payload, "reported_by", "")),
    "evidence_ids": Json::array([]),
    "completed_value_minor": Json::number(0),
    "source_kind": Json::string("imported"),
    "source_id": Json::string("erp:proj_progress:" + row.record_id),
    "source_table": Json::string("proj_progress"),
  }
  value.set("progress_guid", Json::string(progress_id))
  value.set("proj_guid", Json::string(project_id))
  value.set("bu_guid", Json::string(""))
  value.set("progressGuid", Json::string(progress_id))
  value.set("projGuid", Json::string(project_id))
  value.set("planDate", Json::string(json_text(payload, "plan_date", "")))
  value.set("planPct", Json::string(json_text(payload, "plan_pct", "0")))
  value.set("actualPct", Json::string(json_text(payload, "actual_pct", "0")))
  value.set("actualDate", Json::string(json_text(payload, "actual_date", "")))
  value.set(
    "contractGuid",
    Json::string(json_text(payload, "contract_guid", "")),
  )
  value.set(
    "milestoneGuid",
    Json::string(json_text(payload, "milestone_guid", "")),
  )
  Json::object(value)
}

///|
fn delivery_output_item(row : SourceRow, contract_name : String) -> Json {
  let payload = row.payload
  let output_id = row.record_id
  let project_id = json_text(payload, "proj_guid", "")
  let contract_id = json_text(payload, "contract_guid", "")
  let value : Map[String, Json] = {
    "output_id": Json::string(output_id),
    "output_code": Json::string(json_text(payload, "output_code", "")),
    "project_id": Json::string(project_id),
    "contract_id": Json::string(contract_id),
    "period": Json::string(json_text(payload, "period", "")),
    "output_amount": Json::string(json_text(payload, "output_amount", "0")),
    "confirm_amount": Json::string(json_text(payload, "confirm_amount", "0")),
    "state": Json::string(json_text(payload, "state", "reported")),
    "remark": Json::string(json_text(payload, "remark", "")),
    "confirmed_by": Json::string(json_text(payload, "confirmed_by", "")),
    "confirmed_at": Json::string(json_text(payload, "confirmed_at", "")),
    "evidence_ids": Json::array([]),
    "source_kind": Json::string("imported"),
    "source_id": Json::string("erp:proj_output:" + row.record_id),
    "source_table": Json::string("proj_output"),
    "contract_name": Json::string(contract_name),
  }
  value.set("output_guid", Json::string(output_id))
  value.set("proj_guid", Json::string(project_id))
  value.set("contract_guid", Json::string(contract_id))
  value.set("outputGuid", Json::string(output_id))
  value.set("outputCode", Json::string(json_text(payload, "output_code", "")))
  value.set("projGuid", Json::string(project_id))
  value.set("contractGuid", Json::string(contract_id))
  value.set(
    "outputAmount",
    Json::string(json_text(payload, "output_amount", "0")),
  )
  value.set(
    "confirmAmount",
    Json::string(json_text(payload, "confirm_amount", "0")),
  )
  Json::object(value)
}

///|
async fn delivery_progress_response(
  project_id : String?,
) -> Json raise CompanyServiceError {
  match project_id {
    Some(value) if !valid_identifier(value) => raise fail("invalid project_id")
    _ => ()
  }
  let raw = raw_source_rows("proj_progress", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = delivery_progress_item(row)
    if project_id is None ||
      json_text(item, "project_id", "") == project_id.unwrap() {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(left, "plan_date", "").lexical_compare(
      json_text(right, "plan_date", ""),
    )
    if order == 0 {
      json_text(left, "progress_id", "").lexical_compare(
        json_text(right, "progress_id", ""),
      )
    } else {
      order
    }
  })
  let missing : Array[Json] = []
  if raw.is_empty() {
    missing.push(Json::string("proj_progress"))
  }
  match
    delivery_source_metadata(
      Json::object({ "proj_progress": Json::number(raw.length().to_double()) }),
      missing,
    ) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery metadata")
  }
}

///|
async fn delivery_outputs_response(
  project_id : String?,
  period : String?,
  state : String?,
) -> Json raise CompanyServiceError {
  match project_id {
    Some(value) if !valid_identifier(value) => raise fail("invalid project_id")
    _ => ()
  }
  match period {
    Some(value) if value.length() > 64 => raise fail("invalid period")
    _ => ()
  }
  match state {
    Some(value) if value.length() > 64 => raise fail("invalid state")
    _ => ()
  }
  let raw = raw_source_rows("proj_output", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let result : Array[Json] = []
  for row in raw {
    let item_project = json_text(row.payload, "proj_guid", "")
    let item_period = json_text(row.payload, "period", "")
    let item_state = json_text(row.payload, "state", "reported")
    let project_ok = match project_id {
      Some(value) => item_project == value
      None => true
    }
    let period_ok = match period {
      Some(value) => item_period == value
      None => true
    }
    let state_ok = match state {
      Some(value) => item_state == value
      None => true
    }
    if project_ok && period_ok && state_ok {
      let contract_id = json_text(row.payload, "contract_guid", "")
      let contract_name = match
        source_payload(contracts, "contract_guid", contract_id) {
        Some(payload) =>
          json_text(payload, "contract_name", json_text(payload, "ht_name", ""))
        None => ""
      }
      result.push(delivery_output_item(row, contract_name))
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "period", "").lexical_compare(
      json_text(left, "period", ""),
    )
    if order == 0 {
      json_text(right, "output_id", "").lexical_compare(
        json_text(left, "output_id", ""),
      )
    } else {
      order
    }
  })
  let missing : Array[Json] = []
  if raw.is_empty() {
    missing.push(Json::string("proj_output"))
  }
  let coverage = Json::object({
    "proj_output": Json::number(raw.length().to_double()),
    "cb_contract": Json::number(contracts.length().to_double()),
  })
  match delivery_source_metadata(coverage, missing) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery metadata")
  }
}

///|
fn projection_value_expr(key : String, fallback : String) -> String {
  "coalesce(payload->'candidate'->>'" +
  key +
  "', payload->>'" +
  key +
  "', " +
  fallback +
  ")"
}

///|
fn projection_text_expr(key : String, fallback : String) -> String {
  projection_value_expr(key, @postgres.sql_literal(fallback))
}

///|
async fn sales_projection_items(
  aggregate_type : String,
  aggregate_id : String?,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "receivable" && aggregate_type != "invoice" {
    raise fail("unsupported sales aggregate type")
  }
  let where_clause = match aggregate_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid sales aggregate id")
      }
      " AND aggregate_id = " + @postgres.sql_literal(value)
    }
    None => ""
  }
  let identifier_key = if aggregate_type == "receivable" {
    "receivable_id"
  } else {
    "invoice_id"
  }
  let identifier = projection_value_expr(identifier_key, "aggregate_id")
  let amount = projection_value_expr("amount_minor", "'0'")
  let outstanding = projection_value_expr(
    "outstanding_minor",
    if aggregate_type == "receivable" {
      "'0'"
    } else {
      "'0'"
    },
  )
  let source_kind = "CASE WHEN jsonb_typeof(payload->'candidate') = 'object' THEN 'imported' ELSE coalesce(payload->>'source_kind', 'command') END"
  let state_default = if aggregate_type == "receivable" {
    "open"
  } else {
    "draft"
  }
  let body = if aggregate_type == "receivable" {
    [
      "'receivable_id', " + identifier,
      "'source_id', " + projection_text_expr("source_id", ""),
      "'invoice_id', " + projection_text_expr("invoice_id", ""),
      "'customer_id', " + projection_text_expr("customer_id", ""),
      "'principal_id', " + projection_text_expr("principal_id", ""),
      "'scope', " + projection_text_expr("scope", ""),
      "'amount_minor', (" + amount + ")::bigint",
      "'collected_minor', (" +
      projection_value_expr("collected_minor", "'0'") +
      ")::bigint",
      "'outstanding_minor', (" + outstanding + ")::bigint",
      "'currency', " + projection_text_expr("currency", "CNY"),
      "'state', " + projection_text_expr("state", state_default),
      "'amount_display', concat('¥', to_char((" +
      amount +
      ")::numeric / 100, 'FM999,999,999,990.00'))",
      "'outstanding_display', concat('¥', to_char((" +
      outstanding +
      ")::numeric / 100, 'FM999,999,999,990.00'))",
    ].join(", ")
  } else {
    [
      "'invoice_id', " + identifier,
      "'receivable_id', " + projection_text_expr("receivable_id", ""),
      "'principal_id', " + projection_text_expr("principal_id", ""),
      "'customer_id', " + projection_text_expr("customer_id", ""),
      "'source_id', " + projection_text_expr("source_id", ""),
      "'amount_minor', (" + amount + ")::bigint",
      "'paid_minor', (" +
      projection_value_expr("paid_minor", "'0'") +
      ")::bigint",
      "'outstanding_minor', (" + outstanding + ")::bigint",
      "'currency', " + projection_text_expr("currency", "CNY"),
      "'state', " + projection_text_expr("state", state_default),
      "'amount_display', concat('¥', to_char((" +
      amount +
      ")::numeric / 100, 'FM999,999,999,990.00'))",
      "'outstanding_display', concat('¥', to_char((" +
      outstanding +
      ")::numeric / 100, 'FM999,999,999,990.00'))",
    ].join(", ")
  }
  let sql = [
    "SELECT coalesce(jsonb_agg(jsonb_build_object(",
    "  'aggregate_type', " + @postgres.sql_literal(aggregate_type) + ",",
    "  'aggregate_id', aggregate_id,",
    "  'revision', revision,",
    "  'source_event_id', source_event_id,",
    "  'source_kind', " + source_kind + ",",
    "  'source_snapshot_id', " +
    projection_text_expr("source_snapshot_id", "") +
    ",",
    "  'mapping_version', " + projection_text_expr("mapping_version", "") + ",",
    "  " + body,
    ") ORDER BY aggregate_id), '[]'::jsonb)::text",
    "FROM (",
    "  SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload, source_event_id",
    "  FROM company_aggregate_projection",
    "  WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    where_clause,
    "  ORDER BY aggregate_id, revision DESC",
    ") latest",
  ].join("\n")
  json_array_output(run_sql(sql))
}

///|
async fn sales_projection_response(
  family : String,
  aggregate_id : String?,
) -> (Int, Json) raise CompanyServiceError {
  let aggregate_type = if family == "receivables" {
    "receivable"
  } else if family == "invoices" {
    "invoice"
  } else {
    raise fail("unsupported sales read family")
  }
  let items = sales_projection_items(aggregate_type, aggregate_id)
  match aggregate_id {
    Some(_) if items.is_empty() =>
      (
        404,
        Json::object({
          "error": Json::string(
            if family == "receivables" {
              "receivable not found"
            } else {
              "invoice not found"
            },
          ),
        }),
      )
    Some(_) => (200, items[0])
    None => (200, Json::object({ "items": Json::array(items) }))
  }
}

///|
fn invoice_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for table in ["invoice_in", "invoice_out"] {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn invoice_source_item(
  row : SourceRow,
  direction : String,
  projects : Array[SourceRow],
  source_kind : String,
) -> Json {
  let payload = row.payload
  let invoice_id = json_text(payload, "invoice_guid", row.record_id)
  let invoice_no = json_text(payload, "invoice_no", invoice_id)
  let project_id = json_text(payload, "proj_guid", "")
  let project_name = match source_payload(projects, "proj_guid", project_id) {
    Some(value) => json_text(value, "proj_name", project_id)
    None => project_id
  }
  let total = json_number(payload, "total_amount", 0.0)
  Json::object({
    "invoiceGuid": Json::string(invoice_id),
    "invoiceNo": Json::string(invoice_no),
    "projGuid": Json::string(project_id),
    "projName": Json::string(project_name),
    "buGuid": Json::string(json_text(payload, "bu_guid", "")),
    "contractGuid": Json::string(json_text(payload, "contract_guid", "")),
    "providerName": Json::string(json_text(payload, "provider_name", "")),
    "customerName": Json::string(json_text(payload, "customer_name", "")),
    "scontractGuid": Json::string(json_text(payload, "scontract_guid", "")),
    "revenueGuid": Json::string(json_text(payload, "revenue_guid", "")),
    "invoiceDate": Json::string(json_text(payload, "invoice_date", "")),
    "totalAmount": Json::number(total),
    "taxAmount": Json::number(json_number(payload, "tax_amount", 0.0)),
    "taxRate": Json::number(json_number(payload, "tax_rate", 0.0)),
    "invoiceType": Json::string(json_text(payload, "invoice_type", "")),
    "state": Json::string(json_text(payload, "state", "")),
    "remark": Json::string(json_text(payload, "remark", "")),
    "direction": Json::string(direction),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(
      if row.source_id.is_empty() {
        row.record_id
      } else {
        row.source_id
      },
    ),
    "aggregate_type": Json::string("invoice"),
    "aggregate_id": Json::string(invoice_id),
    "name": Json::string(invoice_no),
    "amount_display": Json::string(invoice_money_display(total)),
    "source_kind": Json::string(source_kind),
  })
}

///|
async fn invoice_command_rows(
  direction : String,
) -> Array[SourceRow] raise CompanyServiceError {
  let aggregate_type = "invoice_" + direction
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, source_event_id, payload FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND payload->>'source_kind' = 'command' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid invoice projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("invoice projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn invoice_source_items(
  direction : String,
  proj_guid : String?,
  contract_guid : String?,
) -> Array[Json] raise CompanyServiceError {
  match (proj_guid, contract_guid) {
    (Some(value), _) if !valid_identifier(value) =>
      raise fail("invalid proj_guid")
    (_, Some(value)) if !valid_identifier(value) =>
      raise fail("invalid contract_guid")
    _ => ()
  }
  let raw = raw_source_rows("invoice_" + direction, 500)
  let command = invoice_command_rows(direction)
  let projects = raw_source_rows("ep_project", 500)
  let result : Array[Json] = []
  for row in raw {
    let payload = row.payload
    if json_text(payload, "deleted_at", "").is_empty() &&
      json_text(payload, "state", "") != "deleted" {
      let project_ok = match proj_guid {
        Some(value) => json_text(payload, "proj_guid", "") == value
        None => true
      }
      let contract_ok = match contract_guid {
        Some(value) => json_text(payload, "contract_guid", "") == value
        None => true
      }
      if project_ok && contract_ok {
        result.push(invoice_source_item(row, direction, projects, "imported"))
      }
    }
  }
  for row in command {
    let payload = row.payload
    if json_text(payload, "deleted_at", "").is_empty() &&
      json_text(payload, "state", "") != "deleted" {
      let project_ok = match proj_guid {
        Some(value) => json_text(payload, "proj_guid", "") == value
        None => true
      }
      let contract_ok = match contract_guid {
        Some(value) => json_text(payload, "contract_guid", "") == value
        None => true
      }
      if project_ok && contract_ok {
        result.push(invoice_source_item(row, direction, projects, "command"))
      }
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "invoiceDate", "").lexical_compare(
      json_text(left, "invoiceDate", ""),
    )
    if order == 0 {
      json_text(right, "invoiceGuid", "").lexical_compare(
        json_text(left, "invoiceGuid", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
async fn invoice_source_response(
  direction : String,
  proj_guid : String?,
  contract_guid : String?,
) -> Json raise CompanyServiceError {
  let rows = invoice_source_items(direction, proj_guid, contract_guid)
  let incoming = raw_source_rows("invoice_in", 500)
  let outgoing = raw_source_rows("invoice_out", 500)
  let projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = Json::object({
    "ep_project": Json::number(projects.length().to_double()),
    "invoice_in": Json::number(incoming.length().to_double()),
    "invoice_out": Json::number(outgoing.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
  })
  match invoice_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(rows))
      Json::object(metadata)
    }
    _ => raise fail("invalid invoice metadata")
  }
}

///|
async fn invoice_tax_ledger_response(
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  match proj_guid {
    Some(value) if !valid_identifier(value) => raise fail("invalid proj_guid")
    _ => ()
  }
  let incoming = invoice_source_items("in", proj_guid, None)
  let outgoing = invoice_source_items("out", proj_guid, None)
  let grouped : Array[Json] = []
  for batch in [("in", incoming), ("out", outgoing)] {
    let direction = batch.0
    let rows = batch.1
    for row in rows {
      let date = json_text(row, "invoiceDate", "")
      if date.length() >= 7 {
        let period = date[:7].to_owned()
        let mut selected : Json? = None
        for existing in grouped {
          if json_text(existing, "period", "") == period {
            selected = Some(existing)
            break
          }
        }
        let entry = match selected {
          Some(value) => value
          None => {
            let value = Json::object({
              "period": Json::string(period),
              "totalIn": Json::number(0),
              "taxIn": Json::number(0),
              "totalOut": Json::number(0),
              "taxOut": Json::number(0),
            })
            grouped.push(value)
            value
          }
        }
        match entry {
          Object(fields) => {
            let total_key = if direction == "in" {
              "totalIn"
            } else {
              "totalOut"
            }
            let tax_key = if direction == "in" { "taxIn" } else { "taxOut" }
            fields.set(
              total_key,
              Json::number(
                json_double(entry, total_key, 0.0) +
                json_number(row, "totalAmount", 0.0),
              ),
            )
            fields.set(
              tax_key,
              Json::number(
                json_double(entry, tax_key, 0.0) +
                json_number(row, "taxAmount", 0.0),
              ),
            )
            fields.set(
              "netTax",
              Json::number(
                round_places(
                  json_double(entry, "taxOut", 0.0) -
                  json_double(entry, "taxIn", 0.0),
                  2,
                ),
              ),
            )
          }
          _ => ()
        }
      }
    }
  }
  grouped.sort_by(fn(left, right) {
    json_text(right, "period", "").lexical_compare(
      json_text(left, "period", ""),
    )
  })
  let projects = raw_source_rows("ep_project", 500)
  let incoming_raw = raw_source_rows("invoice_in", 500)
  let outgoing_raw = raw_source_rows("invoice_out", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = Json::object({
    "ep_project": Json::number(projects.length().to_double()),
    "invoice_in": Json::number(incoming_raw.length().to_double()),
    "invoice_out": Json::number(outgoing_raw.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
  })
  match invoice_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::object({ "rows": Json::array(grouped) }))
      Json::object(metadata)
    }
    _ => raise fail("invalid invoice metadata")
  }
}

///|
fn sales_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for
    table in [
      "sale_contract", "sale_customer", "sale_mortgage", "sale_refund", "sale_revenue",
      "sale_subscription",
    ] {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn sales_source_amount_display(payload : Json, key : String) -> String {
  match json_field(payload, key) {
    Some(Number(value, ..)) => invoice_money_display(value)
    Some(String(value)) if !value.is_empty() =>
      invoice_money_display(parse_number(value))
    _ => "—"
  }
}

///|
fn set_default_field(
  fields : Map[String, Json],
  key : String,
  value : Json,
) -> Unit {
  if fields.get(key) is None {
    fields.set(key, value)
  }
}

///|
fn sales_source_identity(
  payload : Json,
  family : String,
  fallback : String,
) -> String {
  let primary = match family {
    "customers" => json_text(payload, "customer_guid", "")
    "subscriptions" => json_text(payload, "sub_guid", "")
    "contracts" => json_text(payload, "scontract_guid", "")
    "mortgages" => json_text(payload, "mortgage_guid", "")
    "refunds" => json_text(payload, "refund_guid", "")
    _ => json_text(payload, "revenue_guid", "")
  }
  if !primary.is_empty() {
    return primary
  }
  if family == "subscriptions" {
    let value = json_text(payload, "subscription_guid", "")
    if !value.is_empty() {
      return value
    }
  }
  if family == "contracts" {
    let value = json_text(payload, "contract_guid", "")
    if !value.is_empty() {
      return value
    }
  }
  fallback
}

///|
fn sales_source_item(
  row : SourceRow,
  family : String,
  source_kind : String,
) -> Json {
  let payload = row.payload
  let table = match family {
    "customers" => "sale_customer"
    "subscriptions" => "sale_subscription"
    "contracts" => "sale_contract"
    "mortgages" => "sale_mortgage"
    "refunds" => "sale_refund"
    _ => "sale_revenue"
  }
  let aggregate_type = match family {
    "customers" => "customer"
    "subscriptions" => "subscription"
    "contracts" => "sales_agreement"
    "mortgages" => "mortgage"
    "refunds" => "refund"
    _ => "sale_revenue"
  }
  let identity = sales_source_identity(payload, family, row.record_id)
  let source_id = if row.source_id.is_empty() {
    row.record_id
  } else {
    row.source_id
  }
  let amount_key = if family == "subscriptions" || family == "contracts" {
    "total_price"
  } else if family == "mortgages" {
    "loan_amount"
  } else if family == "refunds" {
    "refund_amount"
  } else {
    "amount"
  }
  match payload {
    Object(fields) => {
      set_default_field(fields, "source_id", Json::string(source_id))
      set_default_field(fields, "source_kind", Json::string(source_kind))
      set_default_field(fields, "source_table", Json::string(table))
      fields.set("aggregate_type", Json::string(aggregate_type))
      fields.set("aggregate_id", Json::string(identity))
      if family == "customers" {
        set_default_field(fields, "customer_id", Json::string(identity))
        set_default_field(
          fields,
          "name",
          Json::string(json_text(payload, "customer_name", identity)),
        )
        set_default_field(
          fields,
          "contact_reference",
          Json::string(json_text(payload, "phone", "")),
        )
        set_default_field(fields, "state", Json::string("active"))
      } else if family == "subscriptions" {
        set_default_field(fields, "subscription_id", Json::string(identity))
        let building = json_text(payload, "building_no", "")
        let unit = json_text(payload, "unit_no", "")
        let unit_reference = if !building.is_empty() && !unit.is_empty() {
          building + "-" + unit
        } else if !building.is_empty() {
          building
        } else {
          unit
        }
        set_default_field(
          fields,
          "unit_reference",
          Json::string(unit_reference),
        )
        set_default_field(fields, "state", Json::string("reserved"))
      } else if family == "contracts" {
        set_default_field(fields, "agreement_id", Json::string(identity))
        set_default_field(fields, "state", Json::string("draft"))
      } else if family == "mortgages" {
        set_default_field(fields, "mortgage_id", Json::string(identity))
        set_default_field(
          fields,
          "bank_reference",
          Json::string(json_text(payload, "bank_name", "")),
        )
        set_default_field(fields, "state", Json::string("applying"))
      } else if family == "refunds" {
        set_default_field(fields, "refund_id", Json::string(identity))
        set_default_field(fields, "state", Json::string("requested"))
      } else {
        set_default_field(fields, "revenue_id", Json::string(identity))
        set_default_field(fields, "status", Json::string("expected"))
        set_default_field(
          fields,
          "state",
          Json::string(json_text(payload, "status", "expected")),
        )
      }
      set_default_field(
        fields,
        "amount_display",
        Json::string(sales_source_amount_display(payload, amount_key)),
      )
      Json::object(fields)
    }
    _ => payload
  }
}

///|
fn sales_source_matches(
  payload : Json,
  family : String,
  proj_guid : String?,
  state : String?,
  keyword : String?,
) -> Bool {
  if !json_text(payload, "deleted_at", "").is_empty() ||
    json_text(payload, "state", "") == "deleted" ||
    json_text(payload, "status", "") == "deleted" {
    return false
  }
  if proj_guid is Some(value) && json_text(payload, "proj_guid", "") != value {
    return false
  }
  let row_state = if family == "revenues" {
    json_text(payload, "status", "")
  } else {
    json_text(payload, "state", "")
  }
  if state is Some(value) && row_state != value {
    return false
  }
  match keyword {
    Some(value) => payload.stringify().to_lower().contains(value.to_lower())
    None => true
  }
}

///|
fn sales_source_sort_date(payload : Json) -> String {
  let created = json_text(payload, "created_at", "")
  if !created.is_empty() {
    return created
  }
  let received = json_text(payload, "receive_date", "")
  if !received.is_empty() {
    return received
  }
  json_text(payload, "signed_date", "")
}

///|
async fn sales_revenue_command_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(source_event_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, source_event_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'sale_revenue' AND payload->>'source_kind' = 'command' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid sales revenue projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("sales revenue projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn sales_source_response(
  family : String,
  proj_guid : String?,
  state : String?,
  keyword : String?,
) -> Json raise CompanyServiceError {
  if ![
      "customers", "subscriptions", "contracts", "mortgages", "refunds", "revenues",
    ].contains(family) {
    raise fail("unsupported sales source family")
  }
  for value in [proj_guid, state, keyword] {
    match value {
      Some(text) if text.length() > 128 =>
        raise fail("sales filter is too long")
      _ => ()
    }
  }
  let customers = raw_source_rows("sale_customer", 500)
  let subscriptions = raw_source_rows("sale_subscription", 500)
  let contracts = raw_source_rows("sale_contract", 500)
  let mortgages = raw_source_rows("sale_mortgage", 500)
  let refunds = raw_source_rows("sale_refund", 500)
  let revenues = raw_source_rows("sale_revenue", 500)
  let revenue_commands = if family == "revenues" {
    sales_revenue_command_rows()
  } else {
    []
  }
  let coverage = Json::object({
    "sale_contract": Json::number(contracts.length().to_double()),
    "sale_customer": Json::number(customers.length().to_double()),
    "sale_mortgage": Json::number(mortgages.length().to_double()),
    "sale_refund": Json::number(refunds.length().to_double()),
    "sale_revenue": Json::number(revenues.length().to_double()),
    "sale_subscription": Json::number(subscriptions.length().to_double()),
  })
  let raw = match family {
    "customers" => customers
    "subscriptions" => subscriptions
    "contracts" => contracts
    "mortgages" => mortgages
    "refunds" => refunds
    _ => revenues
  }
  let result : Array[Json] = []
  for row in raw {
    if sales_source_matches(row.payload, family, proj_guid, state, keyword) {
      result.push(sales_source_item(row, family, "imported"))
    }
  }
  if family == "revenues" {
    for row in revenue_commands {
      if sales_source_matches(row.payload, family, proj_guid, state, keyword) {
        result.push(sales_source_item(row, family, "command"))
      }
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "created_at", "").lexical_compare(
      json_text(left, "created_at", ""),
    )
    let left_date = sales_source_sort_date(left)
    let right_date = sales_source_sort_date(right)
    let date_order = right_date.lexical_compare(left_date)
    if date_order != 0 {
      date_order
    } else if order != 0 {
      order
    } else {
      json_text(right, "aggregate_id", "").lexical_compare(
        json_text(left, "aggregate_id", ""),
      )
    }
  })
  match sales_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid sales source metadata")
  }
}

///|
fn tender_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for table in ["contract_split", "tender_award", "tender_plan"] {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn tender_raw_item(row : SourceRow, family : String) -> Json {
  let payload = row.payload
  let source_id = if row.source_id.is_empty() {
    row.record_id
  } else {
    row.source_id
  }
  match payload {
    Object(fields) => {
      if family == "tenders" {
        let tender_id = json_text(payload, "tender_guid", row.record_id)
        let amount = json_number(payload, "estimated_amount", 0.0)
        set_default_field(fields, "tender_guid", Json::string(tender_id))
        set_default_field(fields, "tender_id", Json::string(tender_id))
        set_default_field(
          fields,
          "name",
          Json::string(json_text(payload, "tender_name", tender_id)),
        )
        set_default_field(
          fields,
          "project_scope",
          Json::string("project:" + json_text(payload, "proj_guid", "")),
        )
        set_default_field(
          fields,
          "estimated_amount_minor",
          Json::number((amount * 100.0).to_int().to_double()),
        )
        set_default_field(
          fields,
          "estimated_amount_display",
          Json::string(
            if amount == 0.0 {
              "—"
            } else {
              invoice_money_display(amount)
            },
          ),
        )
        set_default_field(fields, "currency", Json::string("CNY"))
        set_default_field(fields, "state", Json::string("planning"))
        set_default_field(fields, "bids", Json::array([]))
        fields.set("aggregate_type", Json::string("tender"))
        fields.set("aggregate_id", Json::string(tender_id))
        fields.set("source_id", Json::string(source_id))
        fields.set("source_table", Json::string("tender_plan"))
      } else if family == "awards" {
        let award_id = json_text(payload, "award_guid", row.record_id)
        let amount = json_number(payload, "award_amount", 0.0)
        set_default_field(fields, "award_guid", Json::string(award_id))
        set_default_field(fields, "award_id", Json::string(award_id))
        set_default_field(
          fields,
          "award_amount_display",
          Json::string(
            if amount == 0.0 {
              "—"
            } else {
              invoice_money_display(amount)
            },
          ),
        )
        set_default_field(fields, "state", Json::string("awarded"))
        fields.set("aggregate_type", Json::string("tender_award"))
        fields.set("aggregate_id", Json::string(award_id))
        fields.set("source_id", Json::string(source_id))
        fields.set("source_table", Json::string("tender_award"))
      } else {
        let split_id = json_text(payload, "split_guid", row.record_id)
        let amount = json_number(payload, "split_amount", 0.0)
        set_default_field(fields, "split_guid", Json::string(split_id))
        set_default_field(fields, "split_id", Json::string(split_id))
        set_default_field(
          fields,
          "split_amount_display",
          Json::string(
            if amount == 0.0 {
              "—"
            } else {
              invoice_money_display(amount)
            },
          ),
        )
        set_default_field(fields, "state", Json::string("planned"))
        fields.set("aggregate_type", Json::string("contract_split"))
        fields.set("aggregate_id", Json::string(split_id))
        fields.set("source_id", Json::string(source_id))
        fields.set("source_table", Json::string("contract_split"))
      }
      set_default_field(fields, "source_kind", Json::string("imported"))
      Json::object(fields)
    }
    _ => payload
  }
}

///|
async fn tender_command_items() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(" +
    "'tender_guid', aggregate_id, 'tender_id', aggregate_id, " +
    "'tender_code', coalesce(payload->>'tender_code', payload->'candidate'->>'tender_code', 'TD-' || right(aggregate_id, 24)), " +
    "'proj_guid', CASE WHEN coalesce(payload->>'project_scope', payload->'candidate'->>'project_scope', '') LIKE 'project:%' THEN substring(coalesce(payload->>'project_scope', payload->'candidate'->>'project_scope', '') from 9) ELSE coalesce(payload->>'project_scope', payload->'candidate'->>'project_scope', '') END, " +
    "'project_scope', coalesce(payload->>'project_scope', payload->'candidate'->>'project_scope', ''), " +
    "'tender_name', coalesce(payload->>'name', payload->'candidate'->>'name', aggregate_id), " +
    "'name', coalesce(payload->>'name', payload->'candidate'->>'name', aggregate_id), " +
    "'category', coalesce(payload->>'category', payload->'candidate'->>'category', 'uncategorized'), " +
    "'estimated_amount', (coalesce(payload->>'estimated_amount_minor', payload->'candidate'->>'estimated_amount_minor', '0')::numeric / 100), " +
    "'estimated_amount_minor', coalesce(payload->>'estimated_amount_minor', payload->'candidate'->>'estimated_amount_minor', '0')::bigint, " +
    "'estimated_amount_display', CASE WHEN coalesce(payload->>'estimated_amount_minor', payload->'candidate'->>'estimated_amount_minor', '0')::bigint = 0 THEN '—' ELSE concat('¥', to_char(coalesce(payload->>'estimated_amount_minor', payload->'candidate'->>'estimated_amount_minor', '0')::numeric / 100, 'FM999,999,999,990.00')) END, " +
    "'currency', coalesce(payload->>'currency', payload->'candidate'->>'currency', 'CNY'), " +
    "'state', coalesce(payload->>'state', payload->'candidate'->>'state', 'planning'), " +
    "'plan_publish_date', coalesce(payload->>'plan_publish_date', payload->'candidate'->>'plan_publish_date', ''), " +
    "'plan_award_date', coalesce(payload->>'plan_award_date', payload->'candidate'->>'plan_award_date', ''), " +
    "'remark', '', " +
    "'bids', coalesce(payload->'bids', payload->'candidate'->'bids', '[]'::jsonb), " +
    "'source_kind', 'command', 'command_projection', true, 'authorizing', false, 'persisted', true, 'provider_execution', false, " +
    "'cash_effect', false, 'accounting_effect', false, 'tax_effect', false, 'aggregate_type', 'tender', 'aggregate_id', aggregate_id, " +
    "'source_id', 'moonproj:command:tender:' || aggregate_id, 'source_table', 'tender_plan'" +
    ") ORDER BY aggregate_id), '[]'::jsonb)::text FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, source_event_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'tender' ORDER BY aggregate_id, revision DESC) latest WHERE coalesce(payload->>'state', payload->'candidate'->>'state', '') <> 'deleted'",
  )
  json_array_output(output)
}

///|
async fn split_command_items() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(" +
    "'split_guid', aggregate_id, 'split_id', aggregate_id, " +
    "'parent_contract_guid', coalesce(payload->>'parent_contract_id', payload->'candidate'->>'parent_contract_id', ''), " +
    "'parent_contract_id', coalesce(payload->>'parent_contract_id', payload->'candidate'->>'parent_contract_id', ''), " +
    "'split_name', coalesce(payload->>'split_name', payload->'candidate'->>'split_name', aggregate_id), " +
    "'split_amount', (coalesce(payload->>'split_amount_minor', payload->'candidate'->>'split_amount_minor', '0')::numeric / 100), " +
    "'split_amount_minor', coalesce(payload->>'split_amount_minor', payload->'candidate'->>'split_amount_minor', '0')::bigint, " +
    "'split_amount_display', CASE WHEN coalesce(payload->>'split_amount_minor', payload->'candidate'->>'split_amount_minor', '0')::bigint = 0 THEN '—' ELSE concat('¥', to_char(coalesce(payload->>'split_amount_minor', payload->'candidate'->>'split_amount_minor', '0')::numeric / 100, 'FM999,999,999,990.00')) END, " +
    "'split_pct', (coalesce(payload->>'split_pct_bps', payload->'candidate'->>'split_pct_bps', '0')::numeric / 100), " +
    "'split_pct_bps', coalesce(payload->>'split_pct_bps', payload->'candidate'->>'split_pct_bps', '0')::bigint, " +
    "'scope', coalesce(payload->>'scope', payload->'candidate'->>'scope', ''), " +
    "'state', coalesce(payload->>'state', payload->'candidate'->>'state', 'planned'), " +
    "'source_kind', 'command', 'command_projection', true, 'authorizing', false, 'persisted', true, 'provider_execution', false, " +
    "'cash_effect', false, 'accounting_effect', false, 'tax_effect', false, 'aggregate_type', 'contract_split', 'aggregate_id', aggregate_id, " +
    "'source_id', 'moonproj:command:contract_split:' || aggregate_id, 'source_table', 'contract_split'" +
    ") ORDER BY aggregate_id), '[]'::jsonb)::text FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, source_event_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'contract_split' ORDER BY aggregate_id, revision DESC) latest WHERE coalesce(payload->>'state', payload->'candidate'->>'state', '') <> 'deleted'",
  )
  json_array_output(output)
}

///|
fn tender_source_matches(
  item : Json,
  family : String,
  proj_guid : String?,
  state : String?,
  tender_guid : String?,
  parent_contract_guid : String?,
) -> Bool {
  if proj_guid is Some(value) {
    if family == "splits" || json_text(item, "proj_guid", "") != value {
      return false
    }
  }
  if state is Some(value) && json_text(item, "state", "") != value {
    return false
  }
  if tender_guid is Some(value) && json_text(item, "tender_guid", "") != value {
    return false
  }
  if parent_contract_guid is Some(value) &&
    json_text(item, "parent_contract_guid", "") != value {
    return false
  }
  true
}

///|
fn tender_source_sort_date(item : Json) -> String {
  let publish = json_text(item, "plan_publish_date", "")
  if !publish.is_empty() {
    return publish
  }
  let award = json_text(item, "award_date", "")
  if !award.is_empty() {
    return award
  }
  json_text(item, "created_at", "")
}

///|
async fn tender_source_response(
  family : String,
  proj_guid : String?,
  state : String?,
  tender_guid : String?,
  parent_contract_guid : String?,
) -> Json raise CompanyServiceError {
  if !["tenders", "awards", "splits"].contains(family) {
    raise fail("unsupported tender source family")
  }
  for value in [proj_guid, state, tender_guid, parent_contract_guid] {
    match value {
      Some(text) if text.length() > 128 =>
        raise fail("tender filter is too long")
      _ => ()
    }
  }
  let plans = raw_source_rows("tender_plan", 500)
  let awards = raw_source_rows("tender_award", 500)
  let splits = raw_source_rows("contract_split", 500)
  let coverage = Json::object({
    "contract_split": Json::number(splits.length().to_double()),
    "tender_award": Json::number(awards.length().to_double()),
    "tender_plan": Json::number(plans.length().to_double()),
  })
  let raw = if family == "tenders" {
    plans
  } else if family == "awards" {
    awards
  } else {
    splits
  }
  let result : Array[Json] = []
  for row in raw {
    let item = tender_raw_item(row, family)
    if tender_source_matches(
        item, family, proj_guid, state, tender_guid, parent_contract_guid,
      ) {
      result.push(item)
    }
  }
  if family == "tenders" {
    for item in tender_command_items() {
      if tender_source_matches(
          item, family, proj_guid, state, tender_guid, parent_contract_guid,
        ) {
        result.push(item)
      }
    }
  } else if family == "splits" {
    for item in split_command_items() {
      if tender_source_matches(
          item, family, proj_guid, state, tender_guid, parent_contract_guid,
        ) {
        result.push(item)
      }
    }
  }
  result.sort_by(fn(left, right) {
    let date_order = tender_source_sort_date(right).lexical_compare(
      tender_source_sort_date(left),
    )
    if date_order != 0 {
      date_order
    } else {
      json_text(right, "aggregate_id", "").lexical_compare(
        json_text(left, "aggregate_id", ""),
      )
    }
  })
  match tender_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid tender source metadata")
  }
}

///|
fn supplier_dictionary_metadata(coverage : Json, source_kind : String) -> Json {
  let missing : Array[Json] = []
  if source_kind == "imported_or_empty" &&
    json_int(coverage, "srm_category", 0) == 0 {
    missing.push(Json::string("srm_category"))
  }
  Json::object({
    "source_kind": Json::string(source_kind),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
async fn supplier_categories_response() -> Json raise CompanyServiceError {
  let raw = raw_source_rows("srm_category", 500)
  let rows : Array[Json] = []
  for row in raw {
    let payload = row.payload
    rows.push(
      Json::object({
        "code": Json::string(json_text(payload, "category_code", row.record_id)),
        "name": Json::string(json_text(payload, "category_name", "")),
        "sortOrder": Json::number(
          json_int(payload, "sort_order", 0).to_double(),
        ),
        "sourceKind": Json::string("imported"),
        "sourceId": Json::string(
          if row.source_id.is_empty() {
            row.record_id
          } else {
            row.source_id
          },
        ),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    let order = json_int(left, "sortOrder", 0) - json_int(right, "sortOrder", 0)
    if order == 0 {
      json_text(left, "code", "").lexical_compare(json_text(right, "code", ""))
    } else {
      order
    }
  })
  let coverage = Json::object({
    "srm_category": Json::number(raw.length().to_double()),
  })
  match supplier_dictionary_metadata(coverage, "imported_or_empty") {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(rows))
      Json::object(metadata)
    }
    _ => raise fail("invalid supplier category metadata")
  }
}

///|
fn supplier_definition_response(values : Array[String]) -> Json {
  let rows : Array[Json] = []
  for value in values {
    rows.push(
      Json::object({
        "code": Json::string(value),
        "name": Json::string(value),
        "sourceKind": Json::string("definition"),
      }),
    )
  }
  match supplier_dictionary_metadata(Json::object({}), "definition") {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(rows))
      Json::object(metadata)
    }
    _ => Json::null()
  }
}

///|
fn supplier_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for
    table in [
      "cb_contract", "mu_business_unit", "srm_category", "srm_provider", "srm_provider_bu",
    ] {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn supplier_command_items() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(" +
    "'providerGuid', aggregate_id, " +
    "'providerCode', coalesce(payload->>'supplier_code', aggregate_id), " +
    "'providerName', coalesce(payload->>'name', aggregate_id), " +
    "'shortName', coalesce(payload->>'short_name', ''), " +
    "'legalPerson', coalesce(payload->>'legal_person', ''), " +
    "'registerCapital', CASE WHEN coalesce(payload->>'register_capital', '') = '' THEN NULL ELSE coalesce(payload->>'register_capital', '')::numeric END, " +
    "'businessScope', coalesce(payload->>'business_scope', payload->>'scope', ''), " +
    "'mainCategory', jsonb_build_object('code', coalesce(payload->>'category_code', ''), 'name', coalesce(payload->>'category_code', '')), " +
    "'evalResult', CASE coalesce(payload->>'evaluation', 'unrated') WHEN 'unrated' THEN '未定级' WHEN 'reviewed' THEN '已评审' WHEN 'qualified' THEN '合格' WHEN 'unqualified' THEN '不合格' WHEN 'strategic' THEN '战略' ELSE coalesce(payload->>'evaluation', '未定级') END, " +
    "'inspectState', '', 'auditState', coalesce(payload->>'state', 'draft'), " +
    "'source', coalesce(payload->>'source', '内部收集'), " +
    "'contactPerson', coalesce(payload->>'contact_person', ''), 'contactPhone', coalesce(payload->>'contact_phone', ''), " +
    "'address', coalesce(payload->>'address', ''), " +
    "'enabled', CASE WHEN coalesce(payload->>'state', 'draft') IN ('voided', 'blacklisted') THEN false ELSE coalesce((payload->>'enabled')::boolean, true) END, " +
    "'buCount', 0, 'contractCount', 0, 'sourceKind', 'command', 'source_kind', 'command', 'commandProjection', true, " +
    "'authorizing', false, 'persisted', true, 'providerExecution', false, 'cashEffect', false, 'accountingEffect', false, 'taxEffect', false, " +
    "'sourceId', 'moonproj:command:supplier:' || aggregate_id, 'aggregate_type', 'supplier', 'aggregate_id', aggregate_id" +
    ") ORDER BY aggregate_id), '[]'::jsonb)::text FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'supplier' ORDER BY aggregate_id, revision DESC) latest WHERE coalesce(payload->>'state', 'draft') NOT IN ('voided', 'blacklisted')",
  )
  json_array_output(output)
}

///|
fn supplier_raw_item(
  row : SourceRow,
  categories : Array[SourceRow],
  links : Array[SourceRow],
  contracts : Array[SourceRow],
) -> Json {
  let payload = row.payload
  let provider_guid = json_text(payload, "provider_guid", row.record_id)
  let provider_name = json_text(payload, "provider_name", "")
  let short_name = json_text(payload, "short_name", "")
  let category_code = json_text(payload, "main_category_code", "")
  let category_name = match
    source_payload(categories, "category_code", category_code) {
    Some(value) => json_text(value, "category_name", "")
    None => ""
  }
  let bu_count = links.fold(init=0, fn(count, link) {
    if json_text(link.payload, "provider_guid", "") == provider_guid {
      count + 1
    } else {
      count
    }
  })
  let contract_count = contracts.fold(init=0, fn(count, contract) {
    let name = json_text(contract.payload, "yf_provider_name", "")
    if json_text(contract.payload, "deleted_at", "").is_empty() &&
      (
        name == provider_name ||
        (short_name != "" && (name == short_name || name.contains(short_name)))
      ) {
      count + 1
    } else {
      count
    }
  })
  let source_id = if row.source_id.is_empty() {
    row.record_id
  } else {
    row.source_id
  }
  Json::object({
    "providerGuid": Json::string(provider_guid),
    "providerCode": Json::string(json_text(payload, "provider_code", "")),
    "providerName": Json::string(provider_name),
    "shortName": Json::string(short_name),
    "legalPerson": Json::string(json_text(payload, "legal_person", "")),
    "registerCapital": json_field(payload, "register_capital").unwrap_or(
      Json::null(),
    ),
    "businessScope": Json::string(json_text(payload, "business_scope", "")),
    "mainCategory": Json::object({
      "code": Json::string(category_code),
      "name": Json::string(category_name),
    }),
    "evalResult": Json::string(json_text(payload, "eval_result", "未定级")),
    "inspectState": Json::string(json_text(payload, "inspect_state", "")),
    "auditState": Json::string(json_text(payload, "audit_state", "")),
    "source": Json::string(json_text(payload, "source", "")),
    "contactPerson": Json::string(json_text(payload, "contact_person", "")),
    "contactPhone": Json::string(json_text(payload, "contact_phone", "")),
    "enabled": Json::boolean(json_bool(payload, "enabled", true)),
    "buCount": Json::number(bu_count.to_double()),
    "contractCount": Json::number(contract_count.to_double()),
    "sourceKind": Json::string("imported"),
    "source_id": Json::string(source_id),
    "source_kind": Json::string("imported"),
  })
}

///|
async fn supplier_source_list_response() -> Json raise CompanyServiceError {
  let providers = raw_source_rows("srm_provider", 500)
  let links = raw_source_rows("srm_provider_bu", 500)
  let categories = raw_source_rows("srm_category", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = Json::object({
    "cb_contract": Json::number(contracts.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
    "srm_category": Json::number(categories.length().to_double()),
    "srm_provider": Json::number(providers.length().to_double()),
    "srm_provider_bu": Json::number(links.length().to_double()),
  })
  let result : Array[Json] = []
  for row in providers {
    if json_text(row.payload, "deleted_at", "").is_empty() {
      result.push(supplier_raw_item(row, categories, links, contracts))
    }
  }
  for item in supplier_command_items() {
    result.push(item)
  }
  result.sort_by(fn(left, right) {
    let eval_order = json_text(right, "evalResult", "").lexical_compare(
      json_text(left, "evalResult", ""),
    )
    if eval_order == 0 {
      json_text(right, "providerCode", "").lexical_compare(
        json_text(left, "providerCode", ""),
      )
    } else {
      eval_order
    }
  })
  match supplier_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid supplier metadata")
  }
}

///|
async fn supplier_command_principal(
  provider_guid : String,
) -> String raise CompanyServiceError {
  let output = run_sql(
    "SELECT coalesce(payload->>'principal_id', '') FROM (SELECT DISTINCT ON (aggregate_id) payload FROM company_aggregate_projection WHERE aggregate_type = 'supplier' AND aggregate_id = " +
    @postgres.sql_literal(provider_guid) +
    " ORDER BY aggregate_id, revision DESC) latest LIMIT 1",
  )
  output.trim().to_owned()
}

///|
async fn supplier_detail_response(
  provider_guid : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(provider_guid) {
    raise fail("invalid provider_guid")
  }
  let list = supplier_source_list_response()
  let selected : Json? = match json_field(list, "data") {
    Some(Array(items)) => {
      let mut found : Json? = None
      for item in items {
        if json_text(item, "providerGuid", "") == provider_guid {
          found = Some(item)
          break
        }
      }
      found
    }
    _ => None
  }
  match selected {
    Some(item) if json_text(item, "sourceKind", "") == "command" => {
      let provider = Json::object({
        "providerGuid": Json::string(
          json_text(item, "providerGuid", provider_guid),
        ),
        "providerCode": Json::string(
          json_text(item, "providerCode", provider_guid),
        ),
        "providerName": Json::string(
          json_text(item, "providerName", provider_guid),
        ),
        "shortName": Json::string(json_text(item, "shortName", "")),
        "legalPerson": Json::string(json_text(item, "legalPerson", "")),
        "businessLicense": Json::string(""),
        "registerCapital": json_field(item, "registerCapital").unwrap_or(
          Json::null(),
        ),
        "businessScope": Json::string(json_text(item, "businessScope", "")),
        "mainCategory": json_field(item, "mainCategory").unwrap_or(
          Json::object({}),
        ),
        "evalResult": Json::string(json_text(item, "evalResult", "未定级")),
        "inspectState": Json::string(json_text(item, "inspectState", "")),
        "auditState": Json::string(json_text(item, "auditState", "")),
        "source": Json::string(json_text(item, "source", "")),
        "contactPerson": Json::string(json_text(item, "contactPerson", "")),
        "contactPhone": Json::string(json_text(item, "contactPhone", "")),
        "address": Json::string(""),
        "qualifications": Json::string(""),
        "enabled": Json::boolean(json_bool(item, "enabled", true)),
        "createdBy": Json::string(supplier_command_principal(provider_guid)),
        "createdAt": Json::string(""),
        "processInstanceGuid": Json::string(""),
        "sourceKind": Json::string("command"),
      })
      match list {
        Object(fields) => {
          fields.set(
            "data",
            Json::object({
              "provider": provider,
              "serviceBus": Json::array([]),
              "contracts": Json::array([]),
            }),
          )
          (200, Json::object(fields))
        }
        _ =>
          (
            500,
            Json::object({ "error": Json::string("invalid supplier metadata") }),
          )
      }
    }
    Some(_) =>
      (404, Json::object({ "error": Json::string("供应商不存在") }))
    None =>
      match list {
        Object(fields) => {
          fields.set("success", Json::boolean(false))
          fields.set("code", Json::number(43001))
          fields.set("message", Json::string("供应商不存在"))
          fields.set("data", Json::null())
          (404, Json::object(fields))
        }
        _ =>
          (404, Json::object({ "error": Json::string("供应商不存在") }))
      }
  }
}

///|
async fn supplier_risk_response(
  provider_guid : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(provider_guid) {
    raise fail("invalid provider_guid")
  }
  let providers = raw_source_rows("srm_provider", 500)
  let provider_links = raw_source_rows("srm_provider_bu", 500)
  let categories = raw_source_rows("srm_category", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let milestones = raw_source_rows("cb_contract_milestone", 500)
  let coverage = Json::object({
    "cb_contract": Json::number(contracts.length().to_double()),
    "cb_contract_milestone": Json::number(milestones.length().to_double()),
    "srm_category": Json::number(categories.length().to_double()),
    "srm_provider": Json::number(providers.length().to_double()),
    "srm_provider_bu": Json::number(provider_links.length().to_double()),
  })
  let missing : Array[Json] = []
  for
    table in [
      "cb_contract_milestone", "srm_category", "srm_provider", "srm_provider_bu",
    ] {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  let metadata = Json::object({
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let selected = source_payload(providers, "provider_guid", provider_guid)
  match selected {
    None =>
      match metadata {
        Object(fields) => {
          fields.set("success", Json::boolean(false))
          fields.set("code", Json::number(43001))
          fields.set("message", Json::string("供应商不存在"))
          fields.set("data", Json::null())
          (404, Json::object(fields))
        }
        _ =>
          (404, Json::object({ "error": Json::string("供应商不存在") }))
      }
    Some(payload) => {
      let state = json_text(payload, "state", "")
      let evaluation = json_text(
        payload,
        "evaluation",
        json_text(payload, "eval_result", ""),
      )
      let score = if state == "voided" ||
        state == "blacklisted" ||
        evaluation == "unqualified" {
        0
      } else if state == "active" && evaluation == "strategic" {
        95
      } else if state == "active" && evaluation == "qualified" {
        85
      } else if state == "pending_review" {
        60
      } else if state == "suspended" {
        35
      } else {
        50
      }
      let rating = if score >= 95 {
        "A"
      } else if score >= 85 {
        "B"
      } else if score == 0 {
        "E"
      } else if score == 35 {
        "D"
      } else {
        "C"
      }
      let tags : Array[Json] = []
      if state == "pending_review" {
        tags.push(Json::string("pending_review"))
      }
      if state == "suspended" {
        tags.push(Json::string("suspended"))
      }
      if state == "blacklisted" {
        tags.push(Json::string("blacklist"))
      }
      if evaluation == "unqualified" {
        tags.push(Json::string("unqualified"))
      }
      match metadata {
        Object(fields) => {
          fields.set("success", Json::boolean(true))
          fields.set("code", Json::number(0))
          fields.set(
            "data",
            Json::object({
              "supplier_id": Json::string(provider_guid),
              "score": Json::number(score.to_double()),
              "rating": Json::string(rating),
              "tags": Json::array(tags),
              "state": Json::string(state),
              "evaluation": Json::string(evaluation),
              "source_kind": Json::string("imported"),
            }),
          )
          (200, Json::object(fields))
        }
        _ =>
          (
            500,
            Json::object({
              "error": Json::string("invalid supplier risk metadata"),
            }),
          )
      }
    }
  }
}

///|
async fn contract_items(
  contract_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let where_clause = match contract_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid contract_id")
      }
      "WHERE base.contract_id = " + @postgres.sql_literal(value)
    }
    None => ""
  }
  let sql = [
    "WITH commitment_latest AS (", "  SELECT DISTINCT ON (aggregate_id) aggregate_id AS contract_id, payload, 'imported' AS source_kind",
    "  FROM company_aggregate_projection WHERE aggregate_type = 'commitment' ORDER BY aggregate_id, revision DESC",
    "), contract_latest AS (", "  SELECT contract_id, payload, source_kind FROM (",
    "    SELECT DISTINCT ON (aggregate_id) aggregate_id AS contract_id, payload, 'command' AS source_kind",
    "    FROM company_aggregate_projection WHERE aggregate_type = 'contract' ORDER BY aggregate_id, revision DESC",
    "  ) latest WHERE coalesce(payload->>'state', '') <> 'deleted'", "), base AS (",
    "  SELECT contract_id, payload, source_kind FROM commitment_latest", "  UNION ALL SELECT contract_id, payload, source_kind FROM contract_latest",
    "), deduped AS (", "  SELECT DISTINCT ON (contract_id) contract_id, payload, source_kind FROM base",
    "  ORDER BY contract_id, CASE WHEN source_kind = 'command' THEN 1 ELSE 0 END DESC",
    "), raw_contract AS (", "  SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/cb_contract'",
    "), raw_project AS (", "  SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/ep_project'",
    "), raw_payment AS (", "  SELECT payload FROM company_record WHERE record_type = 'legacy/raw/cb_htfk_apply'",
    "), milestone_counts AS (", "  SELECT contract_id, count(*)::text AS milestone_count FROM (",
    "    SELECT payload->'candidate'->'milestone'->>'contract_guid' AS contract_id, payload->>'state' AS state",
    "    FROM company_aggregate_projection WHERE aggregate_type = 'contract_milestone'",
    "    UNION ALL SELECT payload->>'contract_id' AS contract_id, payload->>'state' AS state FROM (",
    "      SELECT DISTINCT ON (aggregate_id) payload FROM company_aggregate_projection",
    "      WHERE aggregate_type = 'contract_milestone_command' ORDER BY aggregate_id, revision DESC",
    "    ) latest_command", "  ) milestones WHERE coalesce(state, '') <> 'deleted' GROUP BY contract_id",
    "), payment_totals AS (", "  SELECT payload->>'contract_guid' AS contract_id, coalesce(sum(CASE WHEN payload->>'pay_state' = '完全支付' THEN round((payload->>'apply_amount')::numeric * 100)::bigint ELSE 0 END), 0)::text AS paid_amount_minor",
    "  FROM raw_payment GROUP BY payload->>'contract_guid'", ")", "SELECT coalesce(jsonb_agg(jsonb_build_object(",
    "  'contract_id', base.contract_id,", "  'contract_code', coalesce(raw.payload->>'contract_code', base.payload->>'contract_code', base.contract_id),",
    "  'contract_name', coalesce(raw.payload->>'contract_name', base.payload->>'contract_name', base.contract_id),",
    "  'project_id', coalesce(raw.payload->>'proj_guid', base.payload->>'project_id', ''),",
    "  'project_name', coalesce(project.payload->>'proj_name', base.payload->>'project_name', ''),",
    "  'supplier_id', coalesce(base.payload->'candidate'->>'counterparty_id', base.payload->>'supplier_id', ''),",
    "  'supplier_name', coalesce(raw.payload->>'yf_provider_name', base.payload->>'supplier_name', base.payload->>'supplier_id', ''),",
    "  'amount_minor', coalesce(base.payload->'candidate'->>'amount_minor', base.payload->>'amount_minor', round(coalesce((raw.payload->>'ht_amount')::numeric, 0) * 100)::bigint::text, '0')::bigint,",
    "  'currency', coalesce(base.payload->'candidate'->>'currency', base.payload->>'currency', 'CNY'),",
    "  'sign_date', coalesce(raw.payload->>'sign_date', base.payload->>'sign_date', ''),",
    "  'state', coalesce(base.payload->>'state', 'active'),", "  'paid_amount_minor', coalesce(payment.paid_amount_minor, '0')::bigint,",
    "  'milestone_count', coalesce(milestone.milestone_count, '0')::integer,", "  'source_kind', base.source_kind,",
    "  'bu_guid', coalesce(raw.payload->>'bu_guid', base.payload->>'bu_guid', ''),",
    "  'bu_name', coalesce(raw.payload->>'bu_name', base.payload->>'bu_name', ''),",
    "  'ht_type_code', coalesce(raw.payload->>'ht_type_code', base.payload->>'ht_type_code', ''),",
    "  'ht_class', coalesce(raw.payload->>'ht_class', base.payload->>'ht_class', '0')::integer,",
    "  'supplier_corporation', coalesce(raw.payload->>'yf_corporation', base.payload->>'supplier_corporation', ''),",
    "  'ht_cf_state', coalesce(raw.payload->>'ht_cf_state', base.payload->>'ht_cf_state', ''),",
    "  'js_state', coalesce(raw.payload->>'js_state', base.payload->>'js_state', ''),",
    "  'cost_code', coalesce(raw.payload->>'cost_code', base.payload->>'cost_code', ''),",
    "  'r_code', coalesce(raw.payload->>'r_code', base.payload->>'r_code', ''),",
    "  'l3_code', coalesce(raw.payload->>'l3_code', base.payload->>'l3_code', ''),",
    "  'amount_display', concat('¥', to_char((coalesce(base.payload->'candidate'->>'amount_minor', base.payload->>'amount_minor', round(coalesce((raw.payload->>'ht_amount')::numeric, 0) * 100)::bigint::text, '0')::numeric / 100), 'FM999,999,999,990.00')),",
    "  'paid_amount_display', concat('¥', to_char((coalesce(payment.paid_amount_minor, '0')::numeric / 100), 'FM999,999,999,990.00'))",
    ") ORDER BY base.contract_id), '[]'::jsonb)::text", "FROM deduped base", "LEFT JOIN raw_contract raw ON raw.record_id = base.contract_id",
    "LEFT JOIN raw_project project ON project.record_id = raw.payload->>'proj_guid'",
    "LEFT JOIN milestone_counts milestone ON milestone.contract_id = base.contract_id",
    "LEFT JOIN payment_totals payment ON payment.contract_id = base.contract_id",
    where_clause,
  ].join("\n")
  json_array_output(run_sql(sql))
}

///|
async fn contract_response(
  contract_id : String?,
) -> Json raise CompanyServiceError {
  Json::object({ "items": Json::array(contract_items(contract_id)) })
}

///|
async fn contract_detail_response(
  contract_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(contract_id) {
    raise fail("invalid contract_id")
  }
  let items = contract_items(Some(contract_id))
  if items.is_empty() {
    return (404, Json::object({ "error": Json::string("contract not found") }))
  }
  let milestone_sql = [
    "WITH latest AS (",
    "  SELECT DISTINCT ON (aggregate_type, aggregate_id) aggregate_type, aggregate_id, payload",
    "  FROM company_aggregate_projection",
    "  WHERE aggregate_type IN ('contract_milestone', 'contract_milestone_command')",
    "  ORDER BY aggregate_type, aggregate_id, revision DESC",
    ")",
    "SELECT coalesce(jsonb_agg(jsonb_build_object(",
    "  'milestoneGuid', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'milestone_id' END, payload->'candidate'->'milestone'->>'milestone_guid', aggregate_id),",
    "  'seq', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'sequence' END, payload->'candidate'->'milestone'->>'sequence', payload->'candidate'->'milestone'->>'seq', '0')::integer,",
    "  'nodeName', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'node_name' END, payload->'candidate'->'milestone'->>'node_name', ''),",
    "  'triggerType', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'trigger_type' END, payload->'candidate'->'milestone'->>'trigger_type', ''),",
    "  'triggerValue', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'trigger_value' END, payload->'candidate'->'milestone'->>'trigger_value', ''),",
    "  'triggerTaskName', '', 'triggerTaskStatus', '',",
    "  'planDate', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_date' END, payload->'candidate'->'milestone'->>'plan_date', ''),",
    "  'planAmount', (coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_amount_minor' END, payload->'candidate'->'milestone'->>'plan_amount_minor', '0')::numeric / 100),",
    "  'planPct', (coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_pct_bps' END, payload->'candidate'->'milestone'->>'plan_pct_bps', '0')::numeric / 100),",
    "  'actualAmount', (coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'actual_amount_minor' END, payload->'candidate'->'milestone'->>'actual_amount_minor', '0')::numeric / 100),",
    "  'state', coalesce(payload->>'state', payload->'candidate'->'milestone'->>'state', 'pending'),",
    "  'reachedAt', coalesce(payload->>'reached_at', payload->'candidate'->'milestone'->>'reached_at', ''),",
    "  'notes', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'notes' END, payload->'candidate'->'milestone'->>'notes', ''),",
    "  'sourceKind', CASE WHEN aggregate_type = 'contract_milestone_command' THEN 'command' ELSE 'imported' END,",
    "  'sourceId', CASE WHEN aggregate_type = 'contract_milestone_command' THEN 'moonproj:command:contract_milestone:' || aggregate_id ELSE coalesce(payload->>'source_id', aggregate_id) END,",
    "  'command_projection', aggregate_type = 'contract_milestone_command',",
    "  'authorizing', false, 'persisted', aggregate_type = 'contract_milestone_command', 'provider_execution', false, 'cash_effect', false, 'accounting_effect', false, 'tax_effect', false,",
    "  'milestone_id', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'milestone_id' END, payload->'candidate'->'milestone'->>'milestone_guid', aggregate_id),",
    "  'node_name', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'node_name' END, payload->'candidate'->'milestone'->>'node_name', ''),",
    "  'plan_amount_minor', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_amount_minor' END, payload->'candidate'->'milestone'->>'plan_amount_minor', '0')::bigint,",
    "  'plan_amount_display', concat('¥', to_char((coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_amount_minor' END, payload->'candidate'->'milestone'->>'plan_amount_minor', '0')::numeric / 100), 'FM999,999,999,990.00')),",
    "  'plan_pct_bps', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'plan_pct_bps' END, payload->'candidate'->'milestone'->>'plan_pct_bps', '0'),",
    "  'trigger_type', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'trigger_type' END, payload->'candidate'->'milestone'->>'trigger_type', ''),",
    "  'contract_id', coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'contract_id' END, payload->'candidate'->'milestone'->>'contract_guid', '')",
    ") ORDER BY aggregate_id), '[]'::jsonb)::text",
    "FROM latest",
    "WHERE coalesce(payload->>'state', '') <> 'deleted'",
    "  AND coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'contract_id' END, payload->'candidate'->'milestone'->>'contract_guid', '') = " +
    @postgres.sql_literal(contract_id),
  ].join("\n")
  let milestones = json_array_output(run_sql(milestone_sql))
  match items[0] {
    Object(fields) => {
      fields.set("milestones", Json::array(milestones))
      (200, Json::object(fields))
    }
    _ =>
      (
        500,
        Json::object({ "error": Json::string("invalid contract response") }),
      )
  }
}

///|
async fn payment_items(
  apply_id : String?,
  view : String,
) -> Array[Json] raise CompanyServiceError {
  if !["all", "approving", "approved", "fullpaid"].contains(view) {
    raise fail("unsupported payment application view")
  }
  let where_clause = match apply_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid payment application id")
      }
      "WHERE base.apply_id = " + @postgres.sql_literal(value)
    }
    None => ""
  }
  let sql = [
    "WITH imported AS (", "  SELECT DISTINCT ON (aggregate_id) aggregate_id AS apply_id, payload, 'imported' AS source_kind",
    "  FROM company_aggregate_projection WHERE aggregate_type = 'payment_application' ORDER BY aggregate_id, revision DESC",
    "), command AS (", "  SELECT DISTINCT ON (aggregate_id) aggregate_id AS apply_id, payload, 'command' AS source_kind",
    "  FROM company_aggregate_projection WHERE aggregate_type = 'payment_application_command' ORDER BY aggregate_id, revision DESC",
    "), base AS (", "  SELECT apply_id, payload, source_kind FROM imported UNION ALL SELECT apply_id, payload, source_kind FROM command",
    "), deduped AS (", "  SELECT DISTINCT ON (apply_id) apply_id, payload, source_kind FROM base",
    "  ORDER BY apply_id, CASE WHEN source_kind = 'command' THEN 1 ELSE 0 END DESC",
    "), raw_apply AS (SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/cb_htfk_apply'),",
    "raw_contract AS (SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/cb_contract'),",
    "raw_project AS (SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/ep_project'),",
    "raw_user AS (SELECT record_id, payload FROM company_record WHERE record_type = 'legacy/raw/sys_user')",
    "SELECT coalesce(jsonb_agg(jsonb_build_object(", "  'apply_id', base.apply_id,",
    "  'apply_code', coalesce(base.payload->'payment_application'->>'apply_code', base.payload->'candidate'->'application'->>'apply_code', raw_apply.payload->>'apply_code', base.apply_id),",
    "  'contract_id', coalesce(base.payload->'payment_application'->>'contract_id', base.payload->'candidate'->'application'->>'contract_guid', raw_apply.payload->>'contract_guid', ''),",
    "  'contract_name', coalesce(raw_contract.payload->>'contract_name', ''),", "  'project_id', coalesce(base.payload->'payment_application'->>'project_id', base.payload->'candidate'->'application'->>'proj_guid', raw_apply.payload->>'proj_guid', ''),",
    "  'project_name', coalesce(raw_project.payload->>'proj_name', ''),", "  'supplier_name', coalesce(raw_contract.payload->>'yf_provider_name', ''),",
    "  'subject', coalesce(base.payload->'payment_application'->>'subject', base.payload->'candidate'->'application'->>'subject', raw_apply.payload->>'subject', ''),",
    "  'amount_minor', coalesce(base.payload->'payment_application'->>'amount_minor', base.payload->'candidate'->'application'->>'amount_minor', round(coalesce((raw_apply.payload->>'apply_amount')::numeric, 0) * 100)::bigint::text, '0')::bigint,",
    "  'currency', coalesce(base.payload->>'currency', base.payload->'candidate'->>'currency', 'CNY'),",
    "  'apply_date', coalesce(base.payload->'payment_application'->>'apply_date', base.payload->'candidate'->'application'->>'apply_date', raw_apply.payload->>'apply_date', ''),",
    "  'operation_state', CASE WHEN base.source_kind = 'command' THEN coalesce(base.payload->>'state', 'draft') WHEN coalesce(raw_apply.payload->>'pay_state', '') = '完全支付' THEN 'paid' WHEN coalesce(raw_apply.payload->>'pay_state', '') = '部分支付' THEN 'partially_paid' WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('已审核', 'approved', 'Approved') THEN 'approved' WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('已驳回', 'rejected', 'Rejected') THEN 'rejected' WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('申请审批中', 'submitted', 'Approving') THEN 'submitted' ELSE 'draft' END,",
    "  'apply_state', CASE WHEN base.source_kind = 'command' THEN CASE base.payload->>'state' WHEN 'draft' THEN '草稿' WHEN 'submitted' THEN '申请审批中' WHEN 'rejected' THEN '已驳回' WHEN 'approved' THEN '已审核' WHEN 'voided' THEN '已作废' ELSE coalesce(base.payload->>'state', '草稿') END ELSE coalesce(base.payload->'candidate'->'application'->>'apply_state', raw_apply.payload->>'apply_state', '') END,",
    "  'pay_state', CASE WHEN base.source_kind = 'command' THEN coalesce(base.payload->'payment_application'->>'pay_state', '未支付') ELSE coalesce(base.payload->'candidate'->'application'->>'pay_state', raw_apply.payload->>'pay_state', '') END,",
    "  'apply_type_code', coalesce(base.payload->'payment_application'->>'apply_type_code', base.payload->'candidate'->'application'->>'apply_type_code', raw_apply.payload->>'apply_type_code', ''),",
    "  'pay_class', CASE WHEN coalesce(base.payload->'payment_application'->>'apply_class', base.payload->'candidate'->'application'->>'apply_class', raw_apply.payload->>'apply_class', '0') = '0' THEN '合同' ELSE '非合同' END,",
    "  'applied_by', coalesce(base.payload->'payment_application'->>'applied_by', base.payload->'candidate'->'application'->>'applied_by', raw_apply.payload->>'applied_by', ''),",
    "  'applied_by_name', coalesce(raw_user.payload->>'emp_name', raw_user.payload->>'user_name', base.payload->'payment_application'->>'applied_by', base.payload->'candidate'->'application'->>'applied_by', ''),",
    "  'source_kind', base.source_kind,", "  'plan_id', coalesce(base.payload->'payment_application'->>'plan_id', base.payload->'candidate'->'application'->>'plan_guid', raw_apply.payload->>'htfk_plan_guid', ''),",
    "  'milestone_id', coalesce(base.payload->'payment_application'->>'milestone_id', base.payload->'candidate'->'application'->>'milestone_guid', raw_apply.payload->>'milestone_guid', ''),",
    "  'amount_display', concat('¥', to_char((coalesce(base.payload->'payment_application'->>'amount_minor', base.payload->'candidate'->'application'->>'amount_minor', round(coalesce((raw_apply.payload->>'apply_amount')::numeric, 0) * 100)::bigint::text, '0')::numeric / 100), 'FM999,999,999,990.00'))",
    ") ORDER BY base.apply_id), '[]'::jsonb)::text", "FROM deduped base", "LEFT JOIN raw_apply ON raw_apply.record_id = base.apply_id",
    "LEFT JOIN raw_contract ON raw_contract.record_id = coalesce(base.payload->'payment_application'->>'contract_id', base.payload->'candidate'->'application'->>'contract_guid', raw_apply.payload->>'contract_guid')",
    "LEFT JOIN raw_project ON raw_project.record_id = coalesce(base.payload->'payment_application'->>'project_id', base.payload->'candidate'->'application'->>'proj_guid', raw_apply.payload->>'proj_guid')",
    "LEFT JOIN raw_user ON raw_user.record_id = coalesce(base.payload->'payment_application'->>'applied_by', base.payload->'candidate'->'application'->>'applied_by', raw_apply.payload->>'applied_by')",
    where_clause,
  ].join("\n")
  let all_items = json_array_output(run_sql(sql))
  if view == "all" {
    return all_items
  }
  all_items.filter(fn(value) {
    let state = json_text(value, "operation_state", "")
    if view == "approving" {
      state == "submitted"
    } else if view == "approved" {
      state == "approved"
    } else {
      state == "paid"
    }
  })
}

///|
async fn payment_response(
  apply_id : String?,
  view : String,
) -> Json raise CompanyServiceError {
  Json::object({ "items": Json::array(payment_items(apply_id, view)) })
}

///|
async fn money_display(minor : Int) -> String raise CompanyServiceError {
  run_sql(
    "SELECT concat('¥', to_char((" +
    minor.to_string() +
    "::numeric / 100), 'FM999,999,999,990.00'))",
  )
  .trim()
  .to_owned()
}

///|
async fn payment_eligibility_response(
  plan_id : String,
  amount_minor : Int,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(plan_id) {
    raise fail("invalid payment plan id")
  }
  if amount_minor <= 0 {
    raise fail("amount_minor must be a positive integer")
  }
  let output = run_sql(
    "SELECT p.aggregate_id, coalesce(p.payload->'candidate'->'milestone'->>'contract_guid', ''), coalesce(p.payload->'candidate'->'milestone'->>'plan_amount_minor', '0'), coalesce(p.payload->'candidate'->'milestone'->>'trigger_type', ''), coalesce(raw.payload->>'jhfk_date', ''), coalesce(raw.payload->>'plan_period', ''), coalesce((SELECT sum(round((a.payload->>'apply_amount')::numeric * 100)) FROM company_record a WHERE a.record_type = 'legacy/raw/cb_htfk_apply' AND a.payload->>'htfk_plan_guid' = p.aggregate_id AND coalesce(a.payload->>'pay_state', '') IN ('完全支付', '部分支付')), 0)::bigint, (coalesce(p.payload->'candidate'->'milestone'->>'trigger_type', '') = 'time' AND coalesce(raw.payload->>'jhfk_date', '') <> '' AND coalesce(raw.payload->>'jhfk_date', '') > CURRENT_DATE::text)::text FROM company_aggregate_projection p LEFT JOIN company_record raw ON raw.record_type = 'legacy/raw/cb_htfkplan' AND raw.record_id = p.aggregate_id WHERE p.aggregate_type = 'contract_milestone' AND p.aggregate_id = " +
    @postgres.sql_literal(plan_id) +
    " ORDER BY p.revision DESC LIMIT 1",
  )
  let trimmed = output.trim().to_owned()
  if trimmed.is_empty() {
    return (
      404,
      Json::object({ "error": Json::string("payment plan not found") }),
    )
  }
  let row = fields(trimmed, 8)
  let contract_id = row[1]
  let planned_minor = parse_decimal(row[2])
  let trigger_type = row[3]
  let plan_date = row[4]
  let plan_period = row[5]
  let actual_minor = parse_decimal(row[6])
  let early_flag = row[7] == "true"
  let over_pay = planned_minor > 0 &&
    actual_minor + amount_minor > planned_minor
  let warnings : Array[Json] = []
  if early_flag {
    warnings.push(
      Json::object({
        "level": Json::string("warn"),
        "code": Json::string("early_time"),
        "message": Json::string(
          "节点计划付款日 " + plan_date + ", 尚未到达",
        ),
      }),
    )
  }
  if trigger_type == "progress" || trigger_type == "event" {
    warnings.push(
      Json::object({
        "level": Json::string("warn"),
        "code": Json::string("trigger_review"),
        "message": Json::string(
          "节点触发类型 " + trigger_type + " 需要履约证据复核",
        ),
      }),
    )
  }
  if over_pay {
    warnings.push(
      Json::object({
        "level": Json::string("error"),
        "code": Json::string("over_pay"),
        "message": Json::string("本次申请会超过付款节点计划金额"),
      }),
    )
  }
  (
    200,
    Json::object({
      "plan_id": Json::string(plan_id),
      "contract_id": Json::string(contract_id),
      "plan_period": Json::string(plan_period),
      "plan_date": Json::string(plan_date),
      "trigger_type": Json::string(trigger_type),
      "planned_amount_minor": Json::number(planned_minor.to_double()),
      "planned_amount_display": Json::string(money_display(planned_minor)),
      "actual_amount_minor": Json::number(actual_minor.to_double()),
      "actual_amount_display": Json::string(money_display(actual_minor)),
      "requested_amount_minor": Json::number(amount_minor.to_double()),
      "requested_amount_display": Json::string(money_display(amount_minor)),
      "early_flag": Json::boolean(early_flag),
      "over_pay": Json::boolean(over_pay),
      "warnings": Json::array(warnings),
    }),
  )
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
fn hex_digit(value : Int) -> Char {
  match "0123456789ABCDEF".get_char(value) {
    Some(char) => char
    None => '0'
  }
}

///|
fn query_encoded_hex(value : String) -> String {
  let mut result = ""
  let mut index = 0
  while index < value.length() {
    match value.get_char(index) {
      Some('%') if index + 2 < value.length() =>
        match (value.get_char(index + 1), value.get_char(index + 2)) {
          (Some(high), Some(low)) => {
            result += high.to_string()
            result += low.to_string()
            index += 3
          }
          _ => {
            result += "25"
            index += 1
          }
        }
      Some('+') => {
        result += "20"
        index += 1
      }
      Some(char) => {
        let code = char.to_int()
        result += hex_digit(code / 16).to_string()
        result += hex_digit(code % 16).to_string()
        index += 1
      }
      None => index = value.length()
    }
  }
  result
}

///|
async fn query_decoded(
  path : String,
  key : String,
) -> String? raise CompanyServiceError {
  match query_value(path, key) {
    None => None
    Some(value) if !value.contains("%") && !value.contains("+") => Some(value)
    Some(value) =>
      Some(
        run_sql(
          "SELECT convert_from(decode(" +
          @postgres.sql_literal(query_encoded_hex(value)) +
          ", 'hex'), 'UTF8')",
        )
        .trim()
        .to_owned(),
      )
  }
}

///|
async fn query_alias_decoded(
  path : String,
  primary : String,
  secondary : String,
) -> String? raise CompanyServiceError {
  match query_decoded(path, primary) {
    Some(value) => Some(value)
    None => query_decoded(path, secondary)
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
async fn read_json_body(body : &@io.Reader) -> Json raise CompanyServiceError {
  let bytes = body.read_all() catch {
    _ => raise reject(400, "unable to read request body")
  }
  let data = bytes.binary()
  if data.length() > 128 * 1024 {
    raise reject(413, "request body is too large")
  }
  if data.is_empty() {
    return Json::object({})
  }
  @json.parse(@encoding/utf8.decode(data)) catch {
    _ => raise reject(400, "request body must be valid JSON")
  }
}

///|
fn actor_hmac_hex(secret : String, actor : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @encoding/utf8.encode(secret),
      @encoding/utf8.encode(actor),
    ),
  )
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference |
      (
        left.get_char(index).unwrap_or('\u0000').to_int() ^
        right.get_char(index).unwrap_or('\u0000').to_int()
      )
  }
  difference == 0
}

///|
fn command_actor(
  request : @http.Request,
  actor_signing_secret : String,
) -> String raise CompanyServiceError {
  let actor = header(request, "X-Moonproj-Actor")
  let signature = header(request, "X-Moonproj-Actor-Signature")
  if !valid_identifier(actor) ||
    actor_signing_secret.is_empty() ||
    !constant_time_equal(signature, actor_hmac_hex(actor_signing_secret, actor)) {
    raise reject(403, "signed actor assertion is required")
  }
  actor
}

///|
fn expense_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/expenses" {
    return Some(("create", None))
  }
  let prefix = "/api/company/expenses/"
  if request_method is @http.Put && path.has_prefix(prefix) {
    let id = path[prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(("update", Some(id)))
    }
  }
  if request_method is @http.Delete && path.has_prefix(prefix) {
    let id = path[prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(("void", Some(id)))
    }
  }
  if request_method is @http.Post && path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "submit" | "submit-for-approval" => "submit"
        "approve" => "approve"
        "reject" => "reject"
        "resubmit" => "resubmit"
        "void" => "void"
        _ => ""
      }
      if !command.is_empty() {
        return Some((command, Some(rest[0].to_owned())))
      }
    }
  }
  None
}

///|
fn service_error_response(error : CompanyServiceError) -> (Int, Json) {
  match error {
    CompanyServiceError::CommandRejected(status, message) =>
      (status, Json::object({ "error": Json::string(message) }))
    CompanyServiceError::InvalidInput(message) =>
      (400, Json::object({ "error": Json::string(message) }))
    CompanyServiceError::Database(_) =>
      (
        503,
        Json::object({ "error": Json::string("company service query failed") }),
      )
  }
}

///|
async fn route(
  path : String,
  query : String,
  expected_schema_version : Int,
) -> (Int, Json) raise CompanyServiceError {
  if path == "/api/company/expenses" {
    let expense_guid = query_alias_decoded(query, "expenseGuid", "expense_id")
    return expense_projection_response(expense_guid)
  }
  let expense_prefix = "/api/company/expenses/"
  if path.has_prefix(expense_prefix) {
    let expense_guid = path[expense_prefix.length():].to_owned()
    return expense_projection_response(Some(expense_guid))
  }
  if path == "/api/company/budget/expenses" {
    let result = budget_expenses_response(
      query_alias_decoded(query, "expenseGuid", "expense_guid"),
      query_alias_decoded(query, "userCode", "user_code"),
      query_alias_decoded(query, "applyState", "apply_state"),
    )
    return match result {
      Some(value) => (200, value)
      None => (404, Json::object({ "error": Json::string("user not found") }))
    }
  }
  let budget_expense_prefix = "/api/company/budget/expenses/"
  if path.has_prefix(budget_expense_prefix) {
    let expense_guid = path[budget_expense_prefix.length():].to_owned()
    let result = budget_expense_detail_response(
      expense_guid,
      query_alias_decoded(query, "userCode", "user_code"),
    )
    return match result {
      Some(value) => (200, value)
      None => (404, Json::object({ "error": Json::string("user not found") }))
    }
  }
  if path == "/api/company/source/budget/users-in-bu" {
    let bu_guid = query_alias_decoded(query, "buGuid", "bu_guid")
    return (200, budget_source_users(bu_guid))
  }
  if path == "/api/company/source/budget/my-loan-balance" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return budget_source_loan_balance(user_code, user_id)
  }
  if path == "/api/company/source/workflow/tasks/mine" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_tasks_mine(user_id, user_code))
  }
  if path == "/api/company/source/workflow/tasks/initiated" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_tasks_initiated(user_id, user_code))
  }
  if path == "/api/company/source/workflow/tasks/my-history" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_history(user_id, user_code))
  }
  if path == "/api/company/source/workflow/instances/by-biz" {
    let biz_type = query_alias_decoded(query, "bizType", "biz_type").unwrap_or(
      "",
    )
    let biz_data_guid = query_alias_decoded(
      query, "bizDataGuid", "biz_data_guid",
    ).unwrap_or("")
    return (200, workflow_instance_by_biz(biz_type, biz_data_guid))
  }
  let workflow_instance_prefix = "/api/company/source/workflow/instances/"
  if path.has_prefix(workflow_instance_prefix) {
    let instance_id = path[workflow_instance_prefix.length():].to_owned()
    return workflow_instance_detail(instance_id)
  }
  let dynamic_remarks_prefix = "/api/company/source/cost/dynamic-cost/"
  if path.has_prefix(dynamic_remarks_prefix) && path.has_suffix("/remarks") {
    let cost_id = path[dynamic_remarks_prefix.length():path.length() -
    "/remarks".length()].to_owned()
    return dynamic_cost_remarks_response(cost_id)
  }
  if path == "/api/company/cost/dynamic-cost" {
    let project_id = query_decoded(query, "projGuid").unwrap_or("")
    if project_id.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("projGuid is required") }),
      )
    }
    return (200, dynamic_cost_response(project_id))
  }
  if path == "/api/company/source/delivery/progress" {
    let project_id = query_alias_decoded(query, "projGuid", "project_id")
    return (200, delivery_progress_response(project_id))
  }
  if path == "/api/company/source/delivery/outputs" {
    let project_id = query_alias_decoded(query, "projGuid", "project_id")
    let period = query_decoded(query, "period")
    let state = query_decoded(query, "state")
    return (200, delivery_outputs_response(project_id, period, state))
  }
  if path == "/api/company/source/invoice/in" ||
    path == "/api/company/source/invoice/out" {
    let direction = if path.has_suffix("/in") { "in" } else { "out" }
    let project_id = query_alias_decoded(query, "projGuid", "proj_guid")
    let contract_id = query_alias_decoded(
      query, "contractGuid", "contract_guid",
    )
    return (200, invoice_source_response(direction, project_id, contract_id))
  }
  if path == "/api/company/source/invoice/tax-ledger" {
    let project_id = query_alias_decoded(query, "projGuid", "proj_guid")
    return (200, invoice_tax_ledger_response(project_id))
  }
  let sales_source_prefix = "/api/company/source/sales/"
  if path.has_prefix(sales_source_prefix) {
    let family = path[sales_source_prefix.length():].to_owned()
    let project_id = query_alias_decoded(query, "projGuid", "proj_guid")
    let state = query_alias_decoded(query, "state", "status")
    let keyword = query_decoded(query, "keyword")
    return (200, sales_source_response(family, project_id, state, keyword))
  }
  let tender_source_prefix = "/api/company/source/tender/"
  if path.has_prefix(tender_source_prefix) {
    let family = path[tender_source_prefix.length():].to_owned()
    let project_id = query_alias_decoded(query, "projGuid", "proj_guid")
    let state = query_decoded(query, "state")
    let tender_id = query_alias_decoded(query, "tenderGuid", "tender_guid")
    let parent_contract_id = query_alias_decoded(
      query, "parentContractGuid", "parent_contract_guid",
    )
    return (
      200,
      tender_source_response(
        family, project_id, state, tender_id, parent_contract_id,
      ),
    )
  }
  if path == "/api/company/source/srm/categories" {
    return (200, supplier_categories_response())
  }
  if path == "/api/company/source/srm/dict/eval-results" {
    return (
      200,
      supplier_definition_response([
        "已评审", "合格", "不合格", "战略", "黑名单", "未定级",
      ]),
    )
  }
  if path == "/api/company/source/srm/dict/sources" {
    return (
      200,
      supplier_definition_response([
        "云采购", "内部收集", "外网注册", "其他",
      ]),
    )
  }
  if path == "/api/company/srm/providers" {
    return (200, supplier_source_list_response())
  }
  let supplier_prefix = "/api/company/srm/providers/"
  if path.has_prefix(supplier_prefix) && path.has_suffix("/risk") {
    let provider_guid = path[supplier_prefix.length():path.length() -
    "/risk".length()].to_owned()
    return supplier_risk_response(provider_guid)
  }
  if path.has_prefix(supplier_prefix) {
    let provider_guid = path[supplier_prefix.length():].to_owned()
    return supplier_detail_response(provider_guid)
  }
  let source_contract_prefix = "/api/company/source/cost/contracts/"
  if path == "/api/company/source/cost/contracts" {
    let contract_id = query_alias_decoded(query, "contractGuid", "contract_id")
    let bu_guid = query_alias_decoded(query, "buGuid", "bu_guid")
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid")
    let keyword = query_decoded(query, "keyword")
    return (200, source_contract_list(contract_id, bu_guid, proj_guid, keyword))
  }
  if path.has_prefix(source_contract_prefix) && path.has_suffix("/milestones") {
    let contract_id = path[source_contract_prefix.length():path.length() -
    "/milestones".length()].to_owned()
    let detail = source_contract_detail(contract_id)
    return match detail.0 {
      200 =>
        match json_field(detail.1, "data") {
          Some(data) =>
            match data {
              Object(data_fields) => {
                let milestones = data_fields
                  .get("milestones")
                  .unwrap_or(Json::array([]))
                match
                  source_contract_list(Some(contract_id), None, None, None) {
                  Object(meta) => {
                    meta.set("data", milestones)
                    (200, Json::object(meta))
                  }
                  _ => detail
                }
              }
              _ => detail
            }
          None => detail
        }
      _ => detail
    }
  }
  if path.has_prefix(source_contract_prefix) {
    let contract_id = path[source_contract_prefix.length():].to_owned()
    return source_contract_detail(contract_id)
  }
  if path == "/api/company/source/cost/payment-applies" {
    let view = query_value(query, "view").unwrap_or("all")
    let bu_guid = query_alias_decoded(query, "buGuid", "bu_guid")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, source_payment_list(view, bu_guid, user_id))
  }
  let receivable_prefix = "/api/company/receivables/"
  if path.has_prefix(receivable_prefix) {
    let receivable_id = path[receivable_prefix.length():].to_owned()
    return sales_projection_response("receivables", Some(receivable_id))
  }
  let invoice_prefix = "/api/company/invoices/"
  if path.has_prefix(invoice_prefix) {
    let invoice_id = path[invoice_prefix.length():].to_owned()
    return sales_projection_response("invoices", Some(invoice_id))
  }
  let payment_prefix = "/api/company/payment-applies/"
  if path.has_prefix(payment_prefix) &&
    path != "/api/company/payment-applies/eligibility" {
    let apply_id = path[payment_prefix.length():].to_owned()
    let items = payment_items(Some(apply_id), "all")
    if items.is_empty() {
      return (
        404,
        Json::object({ "error": Json::string("payment application not found") }),
      )
    }
    return (200, items[0])
  }
  let contract_prefix = "/api/company/contracts/"
  if path.has_prefix(contract_prefix) {
    let contract_id = path[contract_prefix.length():].to_owned()
    return contract_detail_response(contract_id)
  }
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
          "read_only": Json::boolean(false),
          "capabilities": Json::array([
            Json::string("read_model"),
            Json::string("expense_command"),
            Json::string("expense_detail_read"),
            Json::string("budget_check_preview"),
            Json::string("profile_observation_read"),
            Json::string("preference_observation_read"),
            Json::string("initiated_document_observation_read"),
            Json::string("budget_scope_observation_read"),
            Json::string("workflow_observation_read"),
            Json::string("dynamic_cost_observation_read"),
            Json::string("delivery_observation_read"),
            Json::string("receivable_read"),
            Json::string("invoice_observation_read"),
            Json::string("sales_observation_read"),
            Json::string("tender_observation_read"),
            Json::string("supplier_dictionary_observation_read"),
            Json::string("supplier_observation_read"),
            Json::string("contract_read"),
            Json::string("payment_application_read"),
            Json::string("payment_eligibility_read"),
            Json::string("source_contract_observation_read"),
            Json::string("source_payment_observation_read"),
            Json::string("authenticated_http_read"),
          ]),
          "schema_version": Json::number(expected_schema_version.to_double()),
        }),
      )
    "/api/company/summary" => (200, summary(expected_schema_version))
    "/api/company/receipts" => (200, receipts())
    "/api/company/projections" =>
      (200, projections(query_value(query, "aggregate_type")))
    "/api/company/contracts" =>
      (200, contract_response(query_value(query, "contract_id")))
    "/api/company/payment-applies/eligibility" => {
      let plan_id = query_value(query, "plan_id").unwrap_or("")
      let amount_minor = parse_decimal(
        query_value(query, "amount_minor").unwrap_or("0"),
      )
      payment_eligibility_response(plan_id, amount_minor)
    }
    "/api/company/payment-applies" =>
      (
        200,
        payment_response(
          query_value(query, "apply_id"),
          query_value(query, "view").unwrap_or("all"),
        ),
      )
    "/api/company/receivables" => sales_projection_response("receivables", None)
    "/api/company/invoices" => sales_projection_response("invoices", None)
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
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  token : String,
  actor_signing_secret : String,
  require_forwarded_tls : Bool,
  expected_schema_version : Int,
) -> Unit {
  if request.meth is @http.Options {
    send_json(conn, request.meth, 204, Json::null(), false)
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
  let path = path_only(request.path)
  if request.meth is @http.Get || request.meth is @http.Head {
    let result = route(path, request.path, expected_schema_version) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  if request.meth is @http.Post && path == "/api/company/budget-check" {
    let _ = command_actor(request, actor_signing_secret) catch {
      error => {
        let result = service_error_response(error)
        send_json(conn, request.meth, result.0, result.1, false)
        return
      }
    }
    let body = read_json_body(body_reader) catch {
      error => {
        let result = service_error_response(error)
        send_json(conn, request.meth, result.0, result.1, false)
        return
      }
    }
    let result = budget_check_response(body) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  match expense_command_spec(request.meth, path) {
    Some((command_type, expense_guid)) => {
      let idempotency_key = header(request, "Idempotency-Key")
      if idempotency_key.is_empty() {
        send_json(
          conn,
          request.meth,
          400,
          Json::object({ "error": Json::string("Idempotency-Key is required") }),
          false,
        )
        return
      }
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let result = service_error_response(error)
          send_json(conn, request.meth, result.0, result.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let result = service_error_response(error)
          send_json(conn, request.meth, result.0, result.1, false)
          return
        }
      }
      let result = expense_command(
        command_type, expense_guid, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
    }
    None =>
      send_json(
        conn,
        request.meth,
        405,
        Json::object({
          "error": Json::string(
            "authenticated company command is not implemented",
          ),
        }),
        false,
      )
  }
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
  let actor_signing_secret_env = option(args, "--actor-signing-secret-env").unwrap_or(
    "MOONPROJ_ACTOR_SIGNING_SECRET",
  )
  let actor_signing_secret = @env.get_env_var(actor_signing_secret_env).unwrap_or(
    "",
  )
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
    (request, body, conn) => {
      handle(
        request, body, conn, token, actor_signing_secret, require_forwarded_tls,
        schema_version,
      )
    },
    allow_failure=true,
  )
}
