///|
/// Native MoonBit authenticated PostgreSQL company service.
///
/// This is the first service slice in the Python-to-MoonBit migration. It
/// keeps the bearer-token and forwarded-TLS boundary, then exposes fixed
/// fixed contracts for health, summary, receipts, projections, imported
/// profile/preferences/initiated-document observations, source-shaped cost
/// observations, and the expense/contract/payment-application read/command
/// boundaries. The wider ERP route families remain separate migration gates.
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
      let payload = auth_profile_overlay(row.payload, user_code)
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
      Json::string("auth_profile_command"),
      Json::string("import_project_command"),
      Json::string("preference_observation_read"),
      Json::string("preference_command"),
      Json::string("workflow_command"),
      Json::string("rbac_command"),
      Json::string("rbac_user_command_candidate"),
      Json::string("warning_rule_command_candidate"),
      Json::string("warning_custom_rule_command_candidate"),
      Json::string("warning_scan_preview_read"),
      Json::string("warning_ticket_command_candidate"),
      Json::string("warning_ticket_transition_candidate"),
      Json::string("webhook_test_delivery_candidate"),
      Json::string("webhook_overdue_scan_candidate"),
      Json::string("notification_digest_dispatch_candidate"),
      Json::string("notification_webhook_test_candidate"),
      Json::string("notification_email_command_candidate"),
      Json::string("ai_provider_test_candidate"),
      Json::string("admin_sys_param_command_candidate"),
      Json::string("investment_command"),
      Json::string("cbs_command"),
      Json::string("budget_expense_command"),
      Json::string("cbs_approval_command"),
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
    "sourceKind": Json::string(json_text(payload, "source_kind", "imported")),
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
  let local_expenses = budget_local_source_rows("budget_expense")
  for row in local_expenses {
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
      "source_kind": Json::string(
        if local_expenses.is_empty() {
          "imported_or_empty"
        } else {
          "imported_or_command"
        },
      ),
      "command_projection": Json::boolean(!local_expenses.is_empty()),
      "persisted": Json::boolean(!local_expenses.is_empty()),
      "authorizing": Json::boolean(false),
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
  let local_expenses = budget_local_source_rows("budget_expense")
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
  let local_details = budget_local_source_rows("budget_expense_detail")
  for row in local_details {
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
  let local_splits = budget_local_source_rows("budget_expense_split")
  for row in local_splits {
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
      "source_kind": Json::string(
        if local_expenses.is_empty() {
          "imported_or_empty"
        } else {
          "imported_or_command"
        },
      ),
      "command_projection": Json::boolean(!local_expenses.is_empty()),
      "source_coverage": expense_coverage(rows),
      "missing_or_empty_source_tables": Json::array(expense_missing(rows)),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(!local_expenses.is_empty()),
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
fn contract_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn contract_currency(
  body : Json,
  key : String,
) -> String raise CompanyServiceError {
  let value = contract_required_text(body, key, false).to_upper()
  if value.length() != 3 {
    raise reject(422, "currency must be a three-letter code")
  }
  for char in value.iter() {
    if char < 'A' || char > 'Z' {
      raise reject(422, "currency must be a three-letter code")
    }
  }
  value
}

///|
fn contract_positive_amount(
  body : Json,
  key : String,
) -> Int raise CompanyServiceError {
  match json_field(body, key) {
    Some(Number(number, ..)) if number > 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => raise reject(422, key + " must be a positive integer")
  }
}

///|
fn contract_nonnegative_amount(
  body : Json,
  key : String,
) -> Int raise CompanyServiceError {
  match json_field(body, key) {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => raise reject(422, key + " must be a non-negative integer")
  }
}

///|
fn contract_optional_text(
  body : Json,
  key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() =>
      request.set(key, Json::string(value.trim().to_owned()))
    _ => raise reject(422, key + " must be non-empty text")
  }
}

///|
fn source_contract_optional_text(
  body : Json,
  source_key : String,
  target_key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, source_key) {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() =>
      request.set(target_key, Json::string(value.trim().to_owned()))
    _ => raise reject(422, source_key + " must be non-empty text")
  }
}

///|
fn contract_create_request(
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("create"))
  request.set(
    "contract_id",
    Json::string(contract_required_text(body, "contract_id", true)),
  )
  request.set(
    "contract_code",
    Json::string(contract_required_text(body, "contract_code", false)),
  )
  request.set(
    "contract_name",
    Json::string(contract_required_text(body, "contract_name", false)),
  )
  request.set(
    "project_id",
    Json::string(contract_required_text(body, "project_id", true)),
  )
  request.set(
    "project_name",
    Json::string(contract_required_text(body, "project_name", false)),
  )
  request.set(
    "supplier_id",
    Json::string(contract_required_text(body, "supplier_id", true)),
  )
  request.set(
    "supplier_name",
    Json::string(contract_required_text(body, "supplier_name", false)),
  )
  request.set(
    "sign_date",
    Json::string(contract_required_text(body, "sign_date", false)),
  )
  request.set(
    "amount_minor",
    Json::number(contract_positive_amount(body, "amount_minor").to_double()),
  )
  request.set("currency", Json::string(contract_currency(body, "currency")))
  for
    key in [
      "bu_guid", "bu_name", "ht_type_code", "supplier_corporation", "ht_cf_state",
      "js_state", "cost_code", "r_code", "l3_code",
    ] {
    contract_optional_text(body, key, request)
  }
  match json_field(body, "ht_class") {
    None | Some(Null) => ()
    Some(Number(number, ..)) =>
      if number >= 0.0 && number == number.to_int().to_double() {
        request.set("ht_class", Json::number(number.to_int().to_double()))
      } else {
        raise reject(422, "ht_class must be a non-negative integer")
      }
    _ => raise reject(422, "ht_class must be a non-negative integer")
  }
  request.set("actor_id", Json::string(actor_id))
  Json::object(request)
}

///|
fn contract_update_request(
  contract_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(contract_id) {
    raise reject(422, "contract_id is required")
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("update"))
  request.set("contract_id", Json::string(contract_id))
  request.set("actor_id", Json::string(actor_id))
  for
    key in [
      "contract_name", "project_name", "supplier_id", "supplier_name", "sign_date",
      "ht_type_code", "supplier_corporation", "ht_cf_state", "js_state", "cost_code",
    ] {
    contract_optional_text(body, key, request)
  }
  match json_field(body, "currency") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() => {
      let currency = value.trim().to_owned().to_upper()
      if currency.length() != 3 {
        raise reject(422, "currency must be a three-letter code")
      }
      for char in currency.iter() {
        if char < 'A' || char > 'Z' {
          raise reject(422, "currency must be a three-letter code")
        }
      }
      request.set("currency", Json::string(currency))
    }
    _ => raise reject(422, "currency must be a three-letter code")
  }
  for key in ["amount_minor", "sum_alter_amount_minor", "ht_class"] {
    match json_field(body, key) {
      None | Some(Null) => ()
      Some(_) =>
        request.set(
          key,
          Json::number(contract_nonnegative_amount(body, key).to_double()),
        )
    }
  }
  if request.length() == 3 {
    raise reject(422, "contract update requires a mutable field")
  }
  Json::object(request)
}

///|
fn contract_transition_request(
  command_type : String,
  contract_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(contract_id) {
    raise reject(422, "contract_id is required")
  }
  match json_field(body, "reason") {
    None => ()
    Some(String(_)) => ()
    _ => raise reject(422, "reason must be text")
  }
  Json::object({
    "command_type": Json::string(command_type),
    "contract_id": Json::string(contract_id),
    "reason": Json::string(json_text(body, "reason", "").trim().to_owned()),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn source_decimal_minor(
  body : Json,
  key : String,
  minimum : Int,
) -> Int raise CompanyServiceError {
  let value = match json_field(body, key) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text)
    _ => raise reject(422, key + " must be a decimal number")
  }
  if value < minimum.to_double() {
    raise reject(422, key + " must be a positive decimal number")
  }
  let minor = (value * 100.0 + 0.5).to_int()
  if minor < minimum * 100 {
    raise reject(422, key + " must be a positive decimal number")
  }
  minor
}

///|
fn source_contract_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let canonical : Map[String, Json] = {}
  let contract_id = json_text(body, "contractGuid", "").trim().to_owned()
  canonical.set(
    "contract_id",
    Json::string(
      if contract_id.is_empty() {
        "CT-SRC-" + idempotency_key
      } else {
        contract_id
      },
    ),
  )
  canonical.set(
    "contract_code",
    Json::string(contract_required_text(body, "contractCode", false)),
  )
  canonical.set(
    "contract_name",
    Json::string(contract_required_text(body, "contractName", false)),
  )
  canonical.set(
    "project_id",
    Json::string(contract_required_text(body, "projGuid", true)),
  )
  canonical.set(
    "project_name",
    Json::string(
      if json_text(body, "projName", "").trim().is_empty() {
        json_text(body, "projGuid", "")
      } else {
        json_text(body, "projName", "").trim().to_owned()
      },
    ),
  )
  let provider_id = json_text(body, "providerGuid", "").trim().to_owned()
  let supplier_id = if provider_id.is_empty() {
    "source-supplier-" + idempotency_key
  } else {
    provider_id
  }
  canonical.set("supplier_id", Json::string(supplier_id))
  canonical.set(
    "supplier_name",
    Json::string(
      if json_text(body, "yfProviderName", "").trim().is_empty() {
        supplier_id
      } else {
        json_text(body, "yfProviderName", "").trim().to_owned()
      },
    ),
  )
  canonical.set(
    "bu_guid",
    Json::string(contract_required_text(body, "buGuid", true)),
  )
  canonical.set(
    "bu_name",
    Json::string(
      if json_text(body, "buName", "").trim().is_empty() {
        json_text(body, "buGuid", "")
      } else {
        json_text(body, "buName", "").trim().to_owned()
      },
    ),
  )
  canonical.set(
    "sign_date",
    Json::string(contract_required_text(body, "signDate", false)),
  )
  canonical.set(
    "amount_minor",
    Json::number(
      if json_field(body, "htAmount") is Some(_) {
        source_decimal_minor(body, "htAmount", 1).to_double()
      } else {
        contract_positive_amount(body, "amount_minor").to_double()
      },
    ),
  )
  canonical.set(
    "currency",
    Json::string(
      if json_field(body, "currency") is Some(_) {
        contract_currency(body, "currency")
      } else {
        "CNY"
      },
    ),
  )
  source_contract_optional_text(body, "htTypeCode", "ht_type_code", canonical)
  source_contract_optional_text(
    body, "yfCorporation", "supplier_corporation", canonical,
  )
  source_contract_optional_text(body, "htCfState", "ht_cf_state", canonical)
  source_contract_optional_text(body, "jsState", "js_state", canonical)
  source_contract_optional_text(body, "costCode", "cost_code", canonical)
  source_contract_optional_text(body, "rCode", "r_code", canonical)
  source_contract_optional_text(body, "l3Code", "l3_code", canonical)
  match json_field(body, "htClass") {
    None | Some(Null) => ()
    Some(Number(number, ..)) =>
      if number >= 0.0 && number == number.to_int().to_double() {
        canonical.set("ht_class", Json::number(number.to_int().to_double()))
      } else {
        raise reject(422, "htClass must be a non-negative integer")
      }
    _ => raise reject(422, "htClass must be a non-negative integer")
  }
  contract_create_request(Json::object(canonical), actor_id)
}

///|
fn source_contract_update_request(
  contract_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let canonical : Map[String, Json] = {}
  source_contract_optional_text(
    body, "contractName", "contract_name", canonical,
  )
  source_contract_optional_text(body, "htTypeCode", "ht_type_code", canonical)
  source_contract_optional_text(
    body, "yfProviderName", "supplier_name", canonical,
  )
  source_contract_optional_text(
    body, "yfCorporation", "supplier_corporation", canonical,
  )
  source_contract_optional_text(body, "signDate", "sign_date", canonical)
  source_contract_optional_text(body, "htCfState", "ht_cf_state", canonical)
  source_contract_optional_text(body, "jsState", "js_state", canonical)
  source_contract_optional_text(body, "costCode", "cost_code", canonical)
  match json_field(body, "htAmount") {
    None | Some(Null) => ()
    Some(_) =>
      canonical.set(
        "amount_minor",
        Json::number(source_decimal_minor(body, "htAmount", 0).to_double()),
      )
  }
  match json_field(body, "sumAlterAmount") {
    None | Some(Null) => ()
    Some(_) =>
      canonical.set(
        "sum_alter_amount_minor",
        Json::number(
          source_decimal_minor(body, "sumAlterAmount", 0).to_double(),
        ),
      )
  }
  match json_field(body, "htClass") {
    None | Some(Null) => ()
    Some(Number(number, ..)) =>
      if number >= 0.0 && number == number.to_int().to_double() {
        canonical.set("ht_class", Json::number(number.to_int().to_double()))
      } else {
        raise reject(422, "htClass must be a non-negative integer")
      }
    _ => raise reject(422, "htClass must be a non-negative integer")
  }
  match json_field(body, "currency") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() => {
      let currency = value.trim().to_owned().to_upper()
      if currency.length() != 3 {
        raise reject(422, "currency must be a three-letter code")
      }
      for char in currency.iter() {
        if char < 'A' || char > 'Z' {
          raise reject(422, "currency must be a three-letter code")
        }
      }
      canonical.set("currency", Json::string(currency))
    }
    _ => raise reject(422, "currency must be a three-letter code")
  }
  contract_update_request(contract_id, Json::object(canonical), actor_id)
}

///|
async fn latest_contract_payload(
  contract_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'contract' AND aggregate_id = " +
    @postgres.sql_literal(contract_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid contract projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn existing_company_command(
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
async fn contract_command(
  command_type : String,
  contract_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    let request = contract_create_request(body, actor_id)
    (json_text(request, "contract_id", ""), request)
  } else {
    let id = match contract_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "contract_id is required")
    }
    let request = if command_type == "update" {
      contract_update_request(id, body, actor_id)
    } else {
      contract_transition_request(command_type, id, body, actor_id)
    }
    (id, request)
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "contract": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_contract_payload(id)
  let visible = contract_items(Some(id))
  if command_type == "create" {
    if current is Some(_) || !visible.is_empty() {
      raise reject(409, "contract already exists")
    }
  } else {
    match current {
      None => {
        if !visible.is_empty() {
          raise reject(
            409, "source contract is read-only; create a local command contract first",
          )
        }
        raise reject(404, "contract not found")
      }
      Some((payload, _)) => {
        let state = json_text(payload, "state", "")
        if command_type == "update" {
          if state != "draft" && state != "submitted" {
            raise reject(
              409,
              "contract update requires draft or submitted, found " + state,
            )
          }
        } else if command_type == "void" {
          if state == "deleted" {
            raise reject(409, "contract is already voided")
          }
        } else {
          let expected = if command_type == "submit" {
            "draft"
          } else if command_type == "approve" || command_type == "reject" {
            "submitted"
          } else if command_type == "resubmit" {
            "rejected"
          } else {
            ""
          }
          if expected.is_empty() || state != expected {
            raise reject(
              409,
              "contract transition " +
              command_type +
              " requires " +
              expected +
              ", found " +
              state,
            )
          }
        }
      }
    }
  }
  let event_id = "contract:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    "draft"
  } else if command_type == "submit" || command_type == "resubmit" {
    "submitted"
  } else if command_type == "approve" {
    "approved"
  } else if command_type == "reject" {
    "rejected"
  } else if command_type == "void" {
    "deleted"
  } else {
    json_text(current_payload, "state", "draft")
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "contract_id": Json::string(id),
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
    "contract_id": Json::string(id),
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
    "::jsonb - 'command_type' - 'contract_id' - 'actor_id') || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "void" {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', 'deleted', 'deleted_at', " +
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
    "action": Json::string("contract." + command_type),
    "aggregate_type": Json::string("contract"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('contract', " +
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
      "contract": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
async fn source_contract_alias_result(
  result : Json,
  contract_code : String?,
) -> Json raise CompanyServiceError {
  let contract = json_field(result, "contract").unwrap_or(Json::null())
  let contract_id = json_text(contract, "contract_id", "")
  let command = json_field(result, "command").unwrap_or(Json::null())
  let request = json_field(command, "request").unwrap_or(Json::null())
  let resolved_code = contract_code.unwrap_or(
    json_text(request, "contract_code", contract_id),
  )
  let rows = contract_items(Some(contract_id))
  let source_contract = if !rows.is_empty() &&
    json_text(rows[0], "source_kind", "") == "command" {
    let item = source_command_contract(rows[0])
    match item {
      Object(fields) => {
        match contract {
          Object(contract_fields) =>
            contract_fields.each((key, value) => fields.set(key, value))
          _ => ()
        }
        Json::object(fields)
      }
      _ => contract
    }
  } else {
    contract
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "contractGuid": Json::string(contract_id),
      "contractCode": Json::string(resolved_code),
    }),
    "contract": source_contract,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn payment_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn payment_currency(body : Json) -> String raise CompanyServiceError {
  let value = payment_required_text(body, "currency", false).to_upper()
  if value.length() != 3 {
    raise reject(422, "currency must be a three-letter code")
  }
  for char in value.iter() {
    if char < 'A' || char > 'Z' {
      raise reject(422, "currency must be a three-letter code")
    }
  }
  value
}

///|
fn payment_positive_amount(body : Json) -> Int raise CompanyServiceError {
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
fn payment_optional_text(
  body : Json,
  key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => ()
    Some(String(value)) =>
      request.set(key, Json::string(value.trim().to_owned()))
    _ => raise reject(422, key + " must be text")
  }
}

///|
async fn payment_create_request(
  body : Json,
  actor_id : String,
) -> (String, Json) raise CompanyServiceError {
  let requested_id = json_text(body, "apply_id", "").trim().to_owned()
  let apply_id = if requested_id.is_empty() {
    "PAY-" +
    actor_id +
    "-" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@encoding/utf8.encode(body.stringify())),
    )[:20].to_owned()
  } else {
    requested_id
  }
  if !valid_identifier(apply_id) {
    raise reject(422, "apply_id contains unsupported characters")
  }
  let apply_code = payment_required_text(body, "apply_code", true)
  let contract_id = payment_required_text(body, "contract_id", true)
  let subject = payment_required_text(body, "subject", false)
  let amount_minor = payment_positive_amount(body)
  let currency = payment_currency(body)
  let contracts = contract_items(Some(contract_id))
  if contracts.is_empty() {
    raise reject(404, "contract not found")
  }
  let contract_amount = json_int(contracts[0], "amount_minor", 0)
  if contract_amount <= 0 {
    raise reject(409, "contract has no payable amount")
  }
  let raw_applies = raw_source_rows("cb_htfk_apply", 500)
  let mut existing_amount = 0
  for row in raw_applies {
    if json_text(row.payload, "contract_guid", "") == contract_id &&
      json_text(row.payload, "apply_state", "") != "已驳回" {
      existing_amount += (json_double(row.payload, "apply_amount", 0.0) * 100.0).to_int()
    }
  }
  if existing_amount + amount_minor > contract_amount {
    raise reject(409, "payment application exceeds contract amount")
  }
  let plan_id = json_text(body, "plan_id", "").trim().to_owned()
  if !plan_id.is_empty() {
    let plans = raw_source_rows("cb_htfkplan", 500)
    let belongs = plans.any(fn(row) {
      row.record_id == plan_id &&
      json_text(row.payload, "contract_guid", "") == contract_id
    })
    if !belongs {
      raise reject(422, "plan_id does not belong to contract")
    }
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("create"))
  request.set("apply_id", Json::string(apply_id))
  request.set("apply_code", Json::string(apply_code))
  request.set("contract_id", Json::string(contract_id))
  request.set("plan_id", Json::string(plan_id))
  request.set(
    "apply_class",
    Json::number(json_int(body, "apply_class", 0).to_double()),
  )
  request.set(
    "apply_type_code",
    Json::string(json_text(body, "apply_type_code", "WORK_PROGRESS")),
  )
  request.set("subject", Json::string(subject))
  request.set("amount_minor", Json::number(amount_minor.to_double()))
  request.set("currency", Json::string(currency))
  request.set("apply_date", Json::string(json_text(body, "apply_date", "")))
  request.set("applied_by", Json::string(actor_id))
  request.set(
    "project_id",
    Json::string(json_text(contracts[0], "project_id", "")),
  )
  for key in ["milestone_id", "early_pay_reason"] {
    payment_optional_text(body, key, request)
  }
  match json_field(body, "force_early") {
    None | Some(False) => ()
    Some(True) => request.set("force_early", Json::boolean(true))
    _ => raise reject(422, "force_early must be boolean")
  }
  (apply_id, Json::object(request))
}

///|
fn payment_update_request(
  apply_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(apply_id) {
    raise reject(422, "apply_id is required")
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("update"))
  request.set("apply_id", Json::string(apply_id))
  request.set("actor_id", Json::string(actor_id))
  let mut changed = false
  match json_field(body, "subject") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() => {
      request.set("subject", Json::string(value.trim().to_owned()))
      changed = true
    }
    _ => raise reject(422, "subject must be non-empty text")
  }
  match json_field(body, "amount_minor") {
    None | Some(Null) => ()
    Some(_) => {
      request.set(
        "amount_minor",
        Json::number(payment_positive_amount(body).to_double()),
      )
      changed = true
    }
  }
  match json_field(body, "apply_type_code") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() => {
      request.set("apply_type_code", Json::string(value.trim().to_owned()))
      changed = true
    }
    _ => raise reject(422, "apply_type_code must be non-empty text")
  }
  if !changed {
    raise reject(
      422, "update requires subject, amount_minor, or apply_type_code",
    )
  }
  Json::object(request)
}

///|
fn payment_transition_request(
  command_type : String,
  apply_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(apply_id) {
    raise reject(422, "apply_id is required")
  }
  match json_field(body, "reason") {
    None | Some(String(_)) => ()
    _ => raise reject(422, "reason must be text")
  }
  Json::object({
    "command_type": Json::string(command_type),
    "apply_id": Json::string(apply_id),
    "reason": Json::string(json_text(body, "reason", "").trim().to_owned()),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn source_payment_create_request(
  body : Json,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let apply_id_value = json_text(body, "htfkApplyGuid", "").trim().to_owned()
  let apply_id = if apply_id_value.is_empty() {
    "PAY-SRC-" + idempotency_key
  } else {
    apply_id_value
  }
  let apply_code = payment_required_text(body, "applyCode", true)
  let contract_id = payment_required_text(body, "contractGuid", true)
  let amount_minor = source_decimal_minor(body, "applyAmount", 1)
  let subject = if json_text(body, "subject", "").trim().is_empty() {
    apply_code
  } else {
    json_text(body, "subject", "").trim().to_owned()
  }
  let canonical : Map[String, Json] = {}
  canonical.set("apply_id", Json::string(apply_id))
  canonical.set("apply_code", Json::string(apply_code))
  canonical.set("contract_id", Json::string(contract_id))
  canonical.set(
    "plan_id",
    Json::string(json_text(body, "htfkPlanGuid", "").trim().to_owned()),
  )
  canonical.set(
    "milestone_id",
    Json::string(json_text(body, "milestoneGuid", "").trim().to_owned()),
  )
  canonical.set(
    "apply_class",
    Json::number(json_int(body, "applyClass", 0).to_double()),
  )
  canonical.set(
    "apply_type_code",
    Json::string(json_text(body, "applyTypeCode", "WORK_PROGRESS")),
  )
  canonical.set("subject", Json::string(subject))
  canonical.set("amount_minor", Json::number(amount_minor.to_double()))
  canonical.set(
    "currency",
    Json::string(
      if json_field(body, "currency") is Some(_) {
        payment_currency(body)
      } else {
        "CNY"
      },
    ),
  )
  canonical.set("apply_date", Json::string(json_text(body, "applyDate", "")))
  match json_field(body, "earlyPayReason") {
    None | Some(Null) => ()
    Some(String(value)) =>
      canonical.set("early_pay_reason", Json::string(value.trim().to_owned()))
    _ => raise reject(422, "earlyPayReason must be text")
  }
  match json_field(body, "forceEarly") {
    None | Some(False) => ()
    Some(True) => canonical.set("force_early", Json::boolean(true))
    _ => raise reject(422, "forceEarly must be boolean")
  }
  Json::object(canonical)
}

///|
fn source_payment_update_request(
  apply_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let canonical : Map[String, Json] = {}
  match json_field(body, "subject") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() =>
      canonical.set("subject", Json::string(value.trim().to_owned()))
    _ => raise reject(422, "subject must be non-empty text")
  }
  match json_field(body, "applyAmount") {
    None | Some(Null) => ()
    Some(_) =>
      canonical.set(
        "amount_minor",
        Json::number(source_decimal_minor(body, "applyAmount", 1).to_double()),
      )
  }
  match json_field(body, "applyTypeCode") {
    None | Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() =>
      canonical.set("apply_type_code", Json::string(value.trim().to_owned()))
    _ => raise reject(422, "applyTypeCode must be non-empty text")
  }
  payment_update_request(apply_id, Json::object(canonical), actor_id)
}

///|
async fn latest_payment_payload(
  apply_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'payment_application_command' AND aggregate_id = " +
    @postgres.sql_literal(apply_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid payment application projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn payment_command(
  command_type : String,
  apply_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    payment_create_request(body, actor_id)
  } else {
    let id = match apply_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "apply_id is required")
    }
    let request = if command_type == "update" {
      payment_update_request(id, body, actor_id)
    } else {
      payment_transition_request(command_type, id, body, actor_id)
    }
    (id, request)
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "payment_application": json_field(existing, "result").unwrap_or(
            Json::null(),
          ),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_payment_payload(id)
  let visible = payment_items(Some(id), "all")
  if command_type == "create" {
    if current is Some(_) || !visible.is_empty() {
      raise reject(409, "payment application already exists")
    }
  } else {
    match current {
      None => {
        if !visible.is_empty() {
          raise reject(
            409, "source payment application is read-only; create a local command draft first",
          )
        }
        raise reject(404, "payment application not found")
      }
      Some((payload, _)) => {
        let state = json_text(payload, "state", "")
        let payment_payload = json_field(payload, "payment_application").unwrap_or(
          Json::object({}),
        )
        let pay_state = json_text(payment_payload, "pay_state", "未支付")
        if command_type == "update" {
          if state != "submitted" {
            raise reject(
              409,
              "payment application transition update requires submitted, found " +
              state,
            )
          }
        } else if command_type == "void" {
          if pay_state != "未支付" {
            raise reject(409, "paid payment application cannot be voided")
          }
          if state == "voided" {
            raise reject(409, "payment application is already voided")
          }
        } else {
          let expected = if command_type == "submit" {
            "draft"
          } else if command_type == "approve" || command_type == "reject" {
            "submitted"
          } else if command_type == "resubmit" {
            "rejected"
          } else {
            ""
          }
          if expected.is_empty() || state != expected {
            raise reject(
              409,
              "payment application transition " +
              command_type +
              " requires " +
              expected +
              ", found " +
              state,
            )
          }
        }
      }
    }
  }
  let event_id = "payment-application:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    "draft"
  } else if command_type == "submit" || command_type == "resubmit" {
    "submitted"
  } else if command_type == "approve" {
    "approved"
  } else if command_type == "reject" {
    "rejected"
  } else if command_type == "void" {
    "voided"
  } else {
    "submitted"
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "apply_id": Json::string(id),
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
    "apply_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    "jsonb_build_object('format', 'moonproj.company.payment-application-command.v1', 'state', 'draft', 'payment_application', " +
    @postgres.sql_literal(request_json) +
    "::jsonb, 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "update" {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', 'submitted', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'payment_application', (" +
    @postgres.sql_literal(current_json) +
    "::jsonb->'payment_application') || (" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'command_type' - 'apply_id' - 'actor_id'))"
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
    "action": Json::string("payment_application." + command_type),
    "aggregate_type": Json::string("payment_application"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('payment_application_command', " +
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
      "payment_application": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn source_payment_alias_result(result : Json, apply_code : String?) -> Json {
  let payment = json_field(result, "payment_application").unwrap_or(
    Json::null(),
  )
  let apply_id = json_text(payment, "apply_id", "")
  let command = json_field(result, "command").unwrap_or(Json::null())
  let request = json_field(command, "request").unwrap_or(Json::null())
  let resolved_code = apply_code.unwrap_or(
    json_text(request, "apply_code", apply_id),
  )
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "htfkApplyGuid": Json::string(apply_id),
      "applyCode": Json::string(resolved_code),
    }),
    "payment_application": payment,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn milestone_text(
  body : Json,
  primary : String,
  fallback : String,
  required : Bool,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    None => json_text(body, fallback, "").trim().to_owned()
    _ => raise reject(422, primary + " must be text")
  }
  if required && value.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn milestone_plan_pct_bps(body : Json) -> Int raise CompanyServiceError {
  match json_field(body, "plan_pct_bps") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number <= 10000.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(_) => raise reject(422, "plan_pct_bps must be between 0 and 10000")
    None =>
      match json_field(body, "plan_pct") {
        Some(_) => source_decimal_minor(body, "plan_pct", 0)
        None => source_decimal_minor(body, "planPct", 0)
      }
  }
}

///|
fn milestone_plan_amount_minor(body : Json) -> Int raise CompanyServiceError {
  match json_field(body, "plan_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(_) =>
      raise reject(422, "plan_amount_minor must be a non-negative integer")
    None =>
      match json_field(body, "plan_amount") {
        Some(_) => source_decimal_minor(body, "plan_amount", 0)
        None =>
          match json_field(body, "planAmount") {
            Some(_) => source_decimal_minor(body, "planAmount", 0)
            None => 0
          }
      }
  }
}

///|
async fn contract_milestone_items(
  contract_id : String?,
  include_deleted : Bool,
) -> Array[Json] raise CompanyServiceError {
  let contract_clause = match contract_id {
    Some(value) => {
      if !valid_identifier(value) {
        raise fail("invalid contract_id")
      }
      " AND coalesce(CASE WHEN aggregate_type = 'contract_milestone_command' THEN payload->>'contract_id' END, payload->'candidate'->'milestone'->>'contract_guid', '') = " +
      @postgres.sql_literal(value)
    }
    None => ""
  }
  let deleted_clause = if include_deleted {
    ""
  } else {
    " WHERE coalesce(payload->>'state', payload->'candidate'->'milestone'->>'state', 'pending') <> 'deleted'"
  }
  let contract_filter = if contract_clause.is_empty() {
    ""
  } else if deleted_clause.is_empty() {
    " WHERE " + contract_clause[5:].to_owned()
  } else {
    contract_clause
  }
  let sql = [
    "SELECT aggregate_type, aggregate_id, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (",
    "  SELECT DISTINCT ON (aggregate_type, aggregate_id) aggregate_type, aggregate_id, payload",
    "  FROM company_aggregate_projection", "  WHERE aggregate_type IN ('contract_milestone', 'contract_milestone_command')",
    "  ORDER BY aggregate_type, aggregate_id, revision DESC", ") latest", deleted_clause,
    contract_filter, " ORDER BY aggregate_id LIMIT 500",
  ].join("\n")
  let result : Array[Json] = []
  for line_view in run_sql(sql).split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 3)
    let payload = @json.parse(decode_hex(row[2])) catch {
      _ => raise fail("invalid contract milestone projection JSON")
    }
    let is_command = row[0] == "contract_milestone_command"
    let candidate = json_field(payload, "candidate").unwrap_or(Json::object({}))
    let source = if is_command {
      payload
    } else {
      json_field(candidate, "milestone").unwrap_or(Json::object({}))
    }
    let source_kind = if is_command { "command" } else { "imported" }
    let source_id = if is_command {
      "moonproj:command:contract_milestone:" + row[1]
    } else {
      json_text(payload, "source_id", row[1])
    }
    let normalized_contract = if is_command {
      json_text(source, "contract_id", "")
    } else {
      json_text(source, "contract_guid", "")
    }
    if contract_id is Some(_) && normalized_contract != contract_id.unwrap() {
      continue
    }
    result.push(
      Json::object({
        "milestone_id": Json::string(
          if is_command {
            json_text(source, "milestone_id", row[1])
          } else {
            json_text(source, "milestone_guid", row[1])
          },
        ),
        "contract_id": Json::string(normalized_contract),
        "sequence": Json::number(
          json_int(source, "sequence", json_int(source, "seq", 0)).to_double(),
        ),
        "node_name": Json::string(json_text(source, "node_name", "")),
        "trigger_type": Json::string(json_text(source, "trigger_type", "")),
        "trigger_value": Json::string(json_text(source, "trigger_value", "")),
        "plan_date": Json::string(json_text(source, "plan_date", "")),
        "plan_amount_minor": Json::number(
          json_int(source, "plan_amount_minor", 0).to_double(),
        ),
        "plan_pct_bps": Json::number(
          json_int(source, "plan_pct_bps", 0).to_double(),
        ),
        "actual_amount_minor": Json::number(
          json_int(source, "actual_amount_minor", 0).to_double(),
        ),
        "state": Json::string(
          json_text(payload, "state", json_text(source, "state", "pending")),
        ),
        "reached_at": Json::string(
          json_text(payload, "reached_at", json_text(source, "reached_at", "")),
        ),
        "notes": Json::string(
          json_text(source, "notes", json_text(payload, "notes", "")),
        ),
        "source_kind": Json::string(source_kind),
        "source_id": Json::string(source_id),
        "command_projection": Json::boolean(is_command),
        "persisted": Json::boolean(is_command),
        "provider_execution": Json::boolean(false),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      }),
    )
  }
  result
}

///|
fn milestone_create_items(
  body : Json,
  contract_id : String,
  contract_amount_minor : Int,
  first_sequence : Int,
  idempotency_key : String,
) -> Array[Json] raise CompanyServiceError {
  let raw_list = match json_field(body, "milestones") {
    Some(Array(items)) => items
    None => [body]
    _ => raise reject(422, "milestones must contain objects")
  }
  if raw_list.is_empty() || raw_list.length() > 100 {
    raise reject(422, "milestones must contain between 1 and 100 objects")
  }
  let result : Array[Json] = []
  for index in 0..<raw_list.length() {
    let raw = raw_list[index]
    match raw {
      Object(_) => ()
      _ => raise reject(422, "milestones must contain objects")
    }
    let milestone_id = milestone_text(
      raw, "milestoneGuid", "milestone_id", false, true,
    )
    let resolved_id = if milestone_id.is_empty() {
      "MS-SRC-" + idempotency_key + "-" + (index + 1).to_string()
    } else {
      milestone_id
    }
    let node_name = milestone_text(raw, "nodeName", "node_name", true, false)
    let trigger_type = milestone_text(
      raw, "triggerType", "trigger_type", true, false,
    ).to_lower()
    if trigger_type != "time" &&
      trigger_type != "progress" &&
      trigger_type != "event" {
      raise reject(400, "triggerType 非法")
    }
    let plan_pct_bps = match json_field(raw, "plan_pct_bps") {
      Some(_) => milestone_plan_pct_bps(raw)
      None =>
        match json_field(raw, "planPct") {
          Some(_) => milestone_plan_pct_bps(raw)
          None => 0
        }
    }
    let mut plan_amount_minor = milestone_plan_amount_minor(raw)
    if plan_amount_minor == 0 && plan_pct_bps > 0 && contract_amount_minor > 0 {
      plan_amount_minor = (contract_amount_minor.to_double() *
      plan_pct_bps.to_double() /
      10000.0 +
      0.5).to_int()
    }
    let sequence = match json_field(raw, "sequence") {
      Some(Number(number, ..)) if number > 0.0 &&
        number == number.to_int().to_double() => number.to_int()
      Some(_) => raise reject(422, "sequence must be a positive integer")
      None =>
        match json_field(raw, "seq") {
          Some(Number(number, ..)) if number > 0.0 &&
            number == number.to_int().to_double() => number.to_int()
          Some(_) => raise reject(422, "seq must be a positive integer")
          None => first_sequence + index
        }
    }
    result.push(
      Json::object({
        "milestone_id": Json::string(resolved_id),
        "contract_id": Json::string(contract_id),
        "sequence": Json::number(sequence.to_double()),
        "node_name": Json::string(node_name),
        "trigger_type": Json::string(trigger_type),
        "trigger_value": Json::string(
          milestone_text(raw, "triggerValue", "trigger_value", false, false),
        ),
        "plan_date": Json::string(
          milestone_text(raw, "planDate", "plan_date", false, false),
        ),
        "plan_amount_minor": Json::number(plan_amount_minor.to_double()),
        "plan_pct_bps": Json::number(plan_pct_bps.to_double()),
        "actual_amount_minor": Json::number(0.0),
        "state": Json::string("pending"),
        "reached_at": Json::string(""),
        "notes": Json::string(
          milestone_text(raw, "notes", "notes", false, false),
        ),
      }),
    )
  }
  result
}

///|
fn milestone_update_request(
  milestone_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("update"))
  request.set("milestone_id", Json::string(milestone_id))
  request.set("actor_id", Json::string(actor_id))
  let mut changed = false
  for primary in ["nodeName", "triggerValue", "planDate", "notes"] {
    let fallback = if primary == "nodeName" {
      "node_name"
    } else if primary == "triggerValue" {
      "trigger_value"
    } else if primary == "planDate" {
      "plan_date"
    } else {
      "notes"
    }
    let target = fallback
    match json_field(body, primary) {
      None =>
        match json_field(body, fallback) {
          None => ()
          Some(String(value)) => {
            request.set(target, Json::string(value.trim().to_owned()))
            changed = true
          }
          _ => raise reject(422, primary + " must be text")
        }
      Some(String(value)) => {
        request.set(target, Json::string(value.trim().to_owned()))
        changed = true
      }
      _ => raise reject(422, primary + " must be text")
    }
  }
  match json_field(body, "triggerType") {
    None =>
      match json_field(body, "trigger_type") {
        None => ()
        Some(String(value)) => {
          let trigger = value.trim().to_lower().to_owned()
          if trigger != "time" && trigger != "progress" && trigger != "event" {
            raise reject(400, "triggerType 非法")
          }
          request.set("trigger_type", Json::string(trigger))
          changed = true
        }
        _ => raise reject(422, "triggerType must be text")
      }
    Some(String(value)) => {
      let trigger = value.trim().to_lower().to_owned()
      if trigger != "time" && trigger != "progress" && trigger != "event" {
        raise reject(400, "triggerType 非法")
      }
      request.set("trigger_type", Json::string(trigger))
      changed = true
    }
    _ => raise reject(422, "triggerType must be text")
  }
  match json_field(body, "planAmount") {
    None =>
      match json_field(body, "plan_amount_minor") {
        None => ()
        Some(_) => {
          request.set(
            "plan_amount_minor",
            Json::number(milestone_plan_amount_minor(body).to_double()),
          )
          changed = true
        }
      }
    Some(_) => {
      request.set(
        "plan_amount_minor",
        Json::number(milestone_plan_amount_minor(body).to_double()),
      )
      changed = true
    }
  }
  match json_field(body, "plan_amount") {
    None => ()
    Some(_) => {
      request.set(
        "plan_amount_minor",
        Json::number(milestone_plan_amount_minor(body).to_double()),
      )
      changed = true
    }
  }
  match json_field(body, "planPct") {
    None =>
      match json_field(body, "plan_pct_bps") {
        None => ()
        Some(_) => {
          request.set(
            "plan_pct_bps",
            Json::number(milestone_plan_pct_bps(body).to_double()),
          )
          changed = true
        }
      }
    Some(_) => {
      request.set(
        "plan_pct_bps",
        Json::number(milestone_plan_pct_bps(body).to_double()),
      )
      changed = true
    }
  }
  match json_field(body, "plan_pct") {
    None => ()
    Some(_) => {
      request.set(
        "plan_pct_bps",
        Json::number(milestone_plan_pct_bps(body).to_double()),
      )
      changed = true
    }
  }
  match json_field(body, "state") {
    None => ()
    Some(String(value)) if [
        "pending", "reached", "paid", "overdue", "over_paid",
      ].contains(value) => {
      request.set("state", Json::string(value))
      changed = true
    }
    Some(_) => raise reject(400, "state 非法")
  }
  if !changed {
    raise reject(422, "milestone update requires a mutable field")
  }
  Json::object(request)
}

///|
fn source_milestone_create_request(
  body : Json,
  contract_id : String?,
) -> (String, Json) raise CompanyServiceError {
  let resolved_contract = match contract_id {
    Some(value) if valid_identifier(value) => value
    Some(_) => raise reject(422, "contractGuid contains unsupported characters")
    None => milestone_text(body, "contractGuid", "contract_id", true, true)
  }
  (resolved_contract, body)
}

///|
fn milestone_create_request_matches(
  stored : Json,
  contract_id : String,
  items : Array[Json],
  actor_id : String,
) -> Bool {
  if json_text(stored, "contract_id", "") != contract_id ||
    json_text(stored, "actor_id", "") != actor_id ||
    json_text(stored, "command_type", "") != "create" {
    return false
  }
  let stored_items = match json_field(stored, "milestones") {
    Some(Array(values)) => values
    _ => return false
  }
  if stored_items.length() != items.length() {
    return false
  }
  let keys = [
    "milestone_id", "contract_id", "node_name", "trigger_type", "trigger_value",
    "plan_date", "plan_amount_minor", "plan_pct_bps", "actual_amount_minor", "state",
    "reached_at", "notes",
  ]
  for index in 0..<items.length() {
    for key in keys {
      if !json_equal(
          json_field(stored_items[index], key).unwrap_or(Json::null()),
          json_field(items[index], key).unwrap_or(Json::null()),
        ) {
        return false
      }
    }
  }
  true
}

///|
async fn contract_milestone_command(
  command_type : String,
  contract_id : String?,
  milestone_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let existing = existing_company_command(idempotency_key)
  if command_type == "create" {
    let (resolved_contract, _) = source_milestone_create_request(
      body, contract_id,
    )
    let contracts = contract_items(Some(resolved_contract))
    if contracts.is_empty() {
      raise reject(404, "合同不存在")
    }
    if json_text(contracts[0], "source_kind", "") != "command" {
      raise reject(
        409, "imported contract is read-only; create a local command contract first",
      )
    }
    if json_text(contracts[0], "state", "") == "deleted" {
      raise reject(409, "contract is voided")
    }
    let current = contract_milestone_items(Some(resolved_contract), true)
    let mut max_sequence = 0
    for item in current {
      if json_text(item, "source_kind", "") == "command" {
        let sequence = json_int(item, "sequence", 0)
        if sequence > max_sequence {
          max_sequence = sequence
        }
      }
    }
    let raw_source = raw_source_rows("cb_contract_milestone", 500)
    for row in raw_source {
      if json_text(row.payload, "contract_guid", "") == resolved_contract {
        let sequence = json_int(row.payload, "seq", 0)
        if sequence > max_sequence {
          max_sequence = sequence
        }
      }
    }
    let items = milestone_create_items(
      body,
      resolved_contract,
      json_int(contracts[0], "amount_minor", 0),
      max_sequence + 1,
      idempotency_key,
    )
    match existing {
      Some(command) => {
        let stored_request = json_field(command, "request").unwrap_or(
          Json::null(),
        )
        if !milestone_create_request_matches(
            stored_request, resolved_contract, items, actor_id,
          ) {
          raise reject(
            409, "Idempotency-Key was already used for another request",
          )
        }
        return (
          200,
          Json::object({
            "command": command,
            "milestone": json_field(command, "result").unwrap_or(Json::null()),
            "idempotent_replay": Json::boolean(true),
          }),
        )
      }
      None => {
        let active = contract_milestone_items(Some(resolved_contract), false)
        for item in items {
          let current_id = json_text(item, "milestone_id", "")
          for visible in active {
            if json_text(visible, "milestone_id", "") == current_id {
              raise reject(409, "milestone already exists")
            }
          }
          for row in raw_source_rows("cb_contract_milestone", 500) {
            if json_text(row.payload, "contract_guid", "") == resolved_contract &&
              json_text(row.payload, "milestone_guid", row.record_id) ==
              current_id {
              raise reject(
                409, "imported milestone is read-only; use a new local milestone id",
              )
            }
          }
        }
        let event_id = "contract-milestone:create:" + idempotency_key
        let command_source = "moonproj:command:" + idempotency_key
        let audit_id = event_id + ":audit"
        let created_ids : Array[Json] = []
        for item in items {
          created_ids.push(Json::string(json_text(item, "milestone_id", "")))
        }
        let result = Json::object({
          "contract_id": Json::string(resolved_contract),
          "created": Json::array(created_ids),
          "state": Json::string("pending"),
          "event_id": Json::string(event_id),
          "audit_id": Json::string(audit_id),
          "actor_id": Json::string(actor_id),
        })
        let request = Json::object({
          "command_type": Json::string("create"),
          "contract_id": Json::string(resolved_contract),
          "milestones": Json::array(items),
          "actor_id": Json::string(actor_id),
        })
        let command_payload = Json::object({
          "kind": Json::string("company_command"),
          "command_type": Json::string("create"),
          "idempotency_key": Json::string(idempotency_key),
          "contract_id": Json::string(resolved_contract),
          "milestone_id": Json::string(""),
          "actor_id": Json::string(actor_id),
          "request": request,
          "result": result,
        })
        let mut statements = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
          @postgres.sql_literal(event_id) +
          ", 4, " +
          @postgres.sql_literal(command_payload.stringify()) +
          "::jsonb, " +
          @postgres.sql_literal(command_source) +
          ") ON CONFLICT (source_id) DO NOTHING;"
        for item in items {
          let item_json = item.stringify()
          let item_id = json_text(item, "milestone_id", "")
          statements = statements +
            " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('contract_milestone_command', " +
            @postgres.sql_literal(item_id) +
            ", 1, " +
            @postgres.sql_literal(item_json) +
            "::jsonb, " +
            @postgres.sql_literal(event_id + ":" + item_id) +
            ") ON CONFLICT DO NOTHING;"
        }
        statements = statements +
          " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
          @postgres.sql_literal(audit_id) +
          ", 4, " +
          @postgres.sql_literal(
            Json::object({
              "audit_id": Json::string(audit_id),
              "action": Json::string("contract_milestone.create"),
              "aggregate_type": Json::string("contract_milestone"),
              "contract_id": Json::string(resolved_contract),
              "actor_id": Json::string(actor_id),
              "event_id": Json::string(event_id),
              "state": Json::string("pending"),
            }).stringify(),
          ) +
          "::jsonb, " +
          @postgres.sql_literal("moonproj:audit:" + event_id) +
          ") ON CONFLICT DO NOTHING; COMMIT;"
        let _ = run_sql(statements)
        return (
          201,
          Json::object({
            "command": command_payload,
            "milestone": result,
            "idempotent_replay": Json::boolean(false),
          }),
        )
      }
    }
  }
  let resolved_id = match milestone_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "milestoneGuid is required")
  }
  let rows = contract_milestone_items(None, true)
  let mut current : Json? = None
  for item in rows {
    if json_text(item, "milestone_id", "") == resolved_id {
      current = Some(item)
      if json_text(item, "source_kind", "") == "command" {
        break
      }
    }
  }
  let current = match current {
    Some(value) => value
    None => raise reject(404, "节点不存在")
  }
  if json_text(current, "source_kind", "") != "command" {
    raise reject(
      409, "imported milestone is read-only; create a local milestone first",
    )
  }
  let contract_for_milestone = json_text(current, "contract_id", "")
  let current_state = json_text(current, "state", "pending")
  let request = if command_type == "update" {
    if current_state == "deleted" {
      raise reject(409, "节点已作废")
    }
    milestone_update_request(resolved_id, body, actor_id)
  } else if command_type == "delete" {
    if current_state == "deleted" {
      raise reject(409, "节点已作废")
    }
    if json_int(current, "actual_amount_minor", 0) > 0 {
      raise reject(400, "该节点已有付款,不可删除")
    }
    match json_field(body, "reason") {
      None | Some(String(_)) => ()
      _ => raise reject(422, "reason must be text")
    }
    Json::object({
      "command_type": Json::string("delete"),
      "milestone_id": Json::string(resolved_id),
      "reason": Json::string(json_text(body, "reason", "").trim().to_owned()),
      "actor_id": Json::string(actor_id),
    })
  } else if command_type == "trigger_event" {
    if current_state != "pending" ||
      json_text(current, "trigger_type", "") != "event" {
      raise reject(400, "仅 pending event 类节点支持手工打点")
    }
    Json::object({
      "command_type": Json::string("trigger_event"),
      "milestone_id": Json::string(resolved_id),
      "reached_at": Json::string("today"),
      "actor_id": Json::string(actor_id),
    })
  } else {
    raise reject(404, "unsupported contract milestone command")
  }
  match existing {
    Some(command) => {
      let stored_request = json_field(command, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": command,
          "milestone": json_field(command, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let revision_output = run_sql(
    "SELECT coalesce(max(revision), 0)::text FROM company_aggregate_projection WHERE aggregate_type = 'contract_milestone_command' AND aggregate_id = " +
    @postgres.sql_literal(resolved_id),
  )
  let next_revision = parse_decimal(revision_output.trim().to_owned()) + 1
  let event_id = "contract-milestone:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_state = if command_type == "delete" {
    "deleted"
  } else if command_type == "trigger_event" {
    "reached"
  } else {
    json_text(request, "state", current_state)
  }
  let result = Json::object({
    "milestone_id": Json::string(resolved_id),
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
    "contract_id": Json::string(contract_for_milestone),
    "milestone_id": Json::string(resolved_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let current_json = current.stringify()
  let request_json = request.stringify()
  let patch_sql = if command_type == "delete" {
    "jsonb_build_object('state', 'deleted', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "trigger_event" {
    "jsonb_build_object('state', 'reached', 'reached_at', CURRENT_DATE::text, 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(request_json) +
    "::jsonb - 'command_type' - 'milestone_id' - 'actor_id'"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("contract_milestone." + command_type),
    "aggregate_type": Json::string("contract_milestone"),
    "aggregate_id": Json::string(resolved_id),
    "contract_id": Json::string(contract_for_milestone),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('contract_milestone_command', " +
    @postgres.sql_literal(resolved_id) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    patch_sql +
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
    200,
    Json::object({
      "command": command_payload,
      "milestone": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn source_milestone_alias_result(result : Json) -> Json {
  let milestone = json_field(result, "milestone").unwrap_or(Json::null())
  let command = json_field(result, "command").unwrap_or(Json::null())
  let created = json_field(milestone, "created")
  let data = match created {
    Some(Array(items)) =>
      Json::object({
        "created": Json::array(items),
        "milestoneGuid": Json::string(
          if items.length() == 1 {
            match items[0] {
              String(value) => value
              _ => ""
            }
          } else {
            ""
          },
        ),
      })
    _ =>
      Json::object({
        "milestoneGuid": Json::string(json_text(milestone, "milestone_id", "")),
      })
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0.0),
    "data": data,
    "milestone": milestone,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn dynamic_cost_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn dynamic_cost_nonnegative_minor(
  body : Json,
  key : String,
) -> Int raise CompanyServiceError {
  match json_field(body, key) {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => raise reject(422, key + " must be a non-negative integer")
  }
}

///|
fn dynamic_cost_level(
  body : Json,
  key : String,
  fallback : Int,
) -> Int raise CompanyServiceError {
  match json_field(body, key) {
    None => fallback
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => raise reject(422, key + " must be a non-negative integer")
  }
}

///|
fn dynamic_cost_source_value(
  body : Json,
  primary : String,
  fallback : String,
) -> Json? {
  match json_field(body, primary) {
    Some(value) => Some(value)
    None => json_field(body, fallback)
  }
}

///|
fn dynamic_cost_source_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
  required : Bool,
) -> String raise CompanyServiceError {
  let value = match dynamic_cost_source_value(body, primary, fallback) {
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => ""
  }
  if required && value.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn dynamic_cost_source_bool(
  body : Json,
  primary : String,
  fallback : String,
  default : Bool,
) -> Bool raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None => default
    Some(True) => true
    Some(False) => false
    _ => raise reject(422, primary + " must be boolean")
  }
}

///|
fn dynamic_cost_source_level(
  body : Json,
  primary : String,
  fallback : String,
  default : Int,
) -> Int raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None => default
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => raise reject(422, primary + " must be a non-negative integer")
  }
}

///|
fn dynamic_cost_source_minor(
  body : Json,
  primary : String,
  fallback : String,
  default : Int,
) -> Int raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None => default
    Some(Number(number, ..)) if number >= 0.0 => {
      let minor = (number * 100.0 + 0.5).to_int()
      if minor >= 0 {
        minor
      } else {
        raise reject(422, primary + " must be a positive decimal number")
      }
    }
    Some(String(text)) => {
      let value = parse_number(text)
      if value < 0.0 {
        raise reject(422, primary + " must be a positive decimal number")
      }
      (value * 100.0 + 0.5).to_int()
    }
    _ => raise reject(422, primary + " must be a decimal number")
  }
}

///|
async fn dynamic_cost_request(
  command_type : String,
  cost_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  if command_type == "create" {
    let requested_id = json_text(body, "cost_id", "").trim().to_owned()
    let cost_id = if requested_id.is_empty() {
      "COST-SRC-" + idempotency_key
    } else {
      requested_id
    }
    if !valid_identifier(cost_id) {
      raise reject(422, "cost_id contains unsupported characters")
    }
    let project_id = dynamic_cost_required_text(body, "project_id", true)
    let projects = raw_source_rows("ep_project", 500)
    let project_exists = projects.any(fn(row) {
      row.record_id == project_id ||
      json_text(row.payload, "proj_guid", "") == project_id
    })
    if !project_exists {
      raise reject(404, "project not found")
    }
    let cost_code = dynamic_cost_required_text(body, "cost_code", true)
    let cost_name = dynamic_cost_required_text(body, "cost_name", false)
    let request : Map[String, Json] = {}
    request.set("command_type", Json::string(command_type))
    request.set("cost_id", Json::string(cost_id))
    request.set("project_id", Json::string(project_id))
    request.set("cost_code", Json::string(cost_code))
    request.set("cost_name", Json::string(cost_name))
    request.set(
      "cost_level",
      Json::number(dynamic_cost_level(body, "cost_level", 2).to_double()),
    )
    request.set(
      "parent_cost_id",
      Json::string(json_text(body, "parent_cost_id", "").trim().to_owned()),
    )
    match json_field(body, "is_end_cost") {
      None => request.set("is_end_cost", Json::boolean(true))
      Some(True) => request.set("is_end_cost", Json::boolean(true))
      Some(False) => request.set("is_end_cost", Json::boolean(false))
      _ => raise reject(422, "is_end_cost must be boolean")
    }
    for
      key in [
        "target_cost_minor", "ht_alter_amount_minor", "zt_cost_minor", "dfs_budget_minor",
        "yg_alter_minor",
      ] {
      request.set(
        key,
        Json::number(dynamic_cost_nonnegative_minor(body, key).to_double()),
      )
    }
    request.set("remarks", Json::string(json_text(body, "remarks", "")))
    request.set("actor_id", Json::string(actor_id))
    return (cost_id, Json::object(request))
  }
  let cost_id = match cost_guid {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "cost_id is required")
  }
  if command_type == "update" {
    let request : Map[String, Json] = {}
    request.set("command_type", Json::string(command_type))
    request.set("cost_id", Json::string(cost_id))
    request.set("actor_id", Json::string(actor_id))
    let mut changed = false
    for key in ["cost_name", "parent_cost_id", "remarks"] {
      match json_field(body, key) {
        None | Some(Null) => ()
        Some(String(value)) => {
          request.set(key, Json::string(value.trim().to_owned()))
          changed = true
        }
        _ => raise reject(422, key + " must be text")
      }
    }
    match json_field(body, "cost_level") {
      None | Some(Null) => ()
      Some(_) => {
        request.set(
          "cost_level",
          Json::number(dynamic_cost_level(body, "cost_level", 0).to_double()),
        )
        changed = true
      }
    }
    match json_field(body, "is_end_cost") {
      None | Some(Null) => ()
      Some(True) => {
        request.set("is_end_cost", Json::boolean(true))
        changed = true
      }
      Some(False) => {
        request.set("is_end_cost", Json::boolean(false))
        changed = true
      }
      _ => raise reject(422, "is_end_cost must be boolean")
    }
    for
      key in [
        "target_cost_minor", "ht_alter_amount_minor", "zt_cost_minor", "dfs_budget_minor",
        "yg_alter_minor",
      ] {
      match json_field(body, key) {
        None | Some(Null) => ()
        Some(_) => {
          request.set(
            key,
            Json::number(dynamic_cost_nonnegative_minor(body, key).to_double()),
          )
          changed = true
        }
      }
    }
    if !changed {
      raise reject(422, "dynamic-cost update requires a mutable field")
    }
    return (cost_id, Json::object(request))
  }
  if command_type == "void" {
    match json_field(body, "reason") {
      None | Some(Null) => ()
      Some(String(_)) => ()
      _ => raise reject(422, "reason must be text")
    }
    return (
      cost_id,
      Json::object({
        "command_type": Json::string(command_type),
        "cost_id": Json::string(cost_id),
        "reason": Json::string(json_text(body, "reason", "").trim().to_owned()),
        "actor_id": Json::string(actor_id),
      }),
    )
  }
  raise reject(404, "unsupported dynamic-cost command")
}

///|
fn source_dynamic_cost_create_request(
  body : Json,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let cost_id_value = dynamic_cost_source_text(
    body, "costGuid", "cost_guid", true, false,
  )
  let cost_id = if cost_id_value.is_empty() {
    "COST-SRC-" + idempotency_key
  } else {
    cost_id_value
  }
  let project_id = dynamic_cost_source_text(
    body, "projGuid", "proj_guid", true, true,
  )
  let cost_code = dynamic_cost_source_text(
    body, "costCode", "cost_code", true, true,
  )
  let cost_name = dynamic_cost_source_text(
    body, "costName", "cost_name", false, true,
  )
  Json::object({
    "cost_id": Json::string(cost_id),
    "project_id": Json::string(project_id),
    "cost_code": Json::string(cost_code),
    "cost_name": Json::string(cost_name),
    "cost_level": Json::number(
      dynamic_cost_source_level(body, "costLevel", "cost_level", 2).to_double(),
    ),
    "parent_cost_id": Json::string(
      dynamic_cost_source_text(
        body, "parentCostGuid", "parent_cost_id", false, false,
      ),
    ),
    "is_end_cost": Json::boolean(
      dynamic_cost_source_bool(body, "isEndCost", "is_end_cost", true),
    ),
    "target_cost_minor": Json::number(
      dynamic_cost_source_minor(body, "targetCost", "target_cost", 0).to_double(),
    ),
    "ht_alter_amount_minor": Json::number(
      dynamic_cost_source_minor(body, "htAlterAmount", "ht_alter_amount", 0).to_double(),
    ),
    "zt_cost_minor": Json::number(
      dynamic_cost_source_minor(body, "ztCost", "zt_cost", 0).to_double(),
    ),
    "dfs_budget_minor": Json::number(
      dynamic_cost_source_minor(body, "dfsBudget", "dfs_budget", 0).to_double(),
    ),
    "yg_alter_minor": Json::number(
      dynamic_cost_source_minor(body, "ygAlter", "yg_alter", 0).to_double(),
    ),
    "remarks": Json::string(json_text(body, "remarks", "")),
  })
}

///|
fn dynamic_cost_update_text(
  body : Json,
  primary : String,
  fallback : String,
  target : String,
  request : Map[String, Json],
) -> Bool raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None | Some(Null) => false
    Some(String(value)) => {
      request.set(target, Json::string(value.trim().to_owned()))
      true
    }
    _ => raise reject(422, primary + " must be text")
  }
}

///|
fn dynamic_cost_update_level(
  body : Json,
  primary : String,
  fallback : String,
  target : String,
  request : Map[String, Json],
) -> Bool raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None | Some(Null) => false
    Some(_) => {
      request.set(
        target,
        Json::number(
          dynamic_cost_source_level(body, primary, fallback, 0).to_double(),
        ),
      )
      true
    }
  }
}

///|
fn dynamic_cost_update_minor(
  body : Json,
  primary : String,
  fallback : String,
  target : String,
  request : Map[String, Json],
) -> Bool raise CompanyServiceError {
  match dynamic_cost_source_value(body, primary, fallback) {
    None | Some(Null) => false
    Some(_) => {
      request.set(
        target,
        Json::number(
          dynamic_cost_source_minor(body, primary, fallback, 0).to_double(),
        ),
      )
      true
    }
  }
}

///|
fn source_dynamic_cost_update_request(
  body : Json,
) -> Json raise CompanyServiceError {
  let request : Map[String, Json] = {}
  let mut changed = false
  changed = dynamic_cost_update_text(
      body, "costName", "cost_name", "cost_name", request,
    ) ||
    changed
  changed = dynamic_cost_update_text(
      body, "parentCostGuid", "parent_cost_id", "parent_cost_id", request,
    ) ||
    changed
  changed = dynamic_cost_update_text(
      body, "remarks", "remarks", "remarks", request,
    ) ||
    changed
  changed = dynamic_cost_update_level(
      body, "costLevel", "cost_level", "cost_level", request,
    ) ||
    changed
  match dynamic_cost_source_value(body, "isEndCost", "is_end_cost") {
    None | Some(Null) => ()
    Some(True) => {
      request.set("is_end_cost", Json::boolean(true))
      changed = true
    }
    Some(False) => {
      request.set("is_end_cost", Json::boolean(false))
      changed = true
    }
    _ => raise reject(422, "isEndCost must be boolean")
  }
  changed = dynamic_cost_update_minor(
      body, "targetCost", "target_cost", "target_cost_minor", request,
    ) ||
    changed
  changed = dynamic_cost_update_minor(
      body, "htAlterAmount", "ht_alter_amount", "ht_alter_amount_minor", request,
    ) ||
    changed
  changed = dynamic_cost_update_minor(
      body, "ztCost", "zt_cost", "zt_cost_minor", request,
    ) ||
    changed
  changed = dynamic_cost_update_minor(
      body, "dfsBudget", "dfs_budget", "dfs_budget_minor", request,
    ) ||
    changed
  changed = dynamic_cost_update_minor(
      body, "ygAlter", "yg_alter", "yg_alter_minor", request,
    ) ||
    changed
  if !changed {
    raise reject(422, "dynamic-cost update requires a mutable field")
  }
  Json::object(request)
}

///|
fn source_dynamic_cost_alias_result(result : Json) -> Json {
  let dynamic = json_field(result, "dynamic_cost").unwrap_or(Json::null())
  let cost_id = json_text(dynamic, "cost_id", "")
  let command = json_field(result, "command").unwrap_or(Json::null())
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "costGuid": Json::string(cost_id),
      "costCode": Json::string(json_text(dynamic, "cost_code", cost_id)),
    }),
    "dynamic_cost": dynamic,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn latest_dynamic_cost_payload(
  cost_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'dynamic_cost_command' AND aggregate_id = " +
    @postgres.sql_literal(cost_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid dynamic-cost command projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn dynamic_cost_command(
  command_type : String,
  cost_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let (cost_id, request) = dynamic_cost_request(
    command_type, cost_guid, body, actor_id, idempotency_key,
  )
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "dynamic_cost": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_dynamic_cost_payload(cost_id)
  let raw_costs = raw_source_rows("cb_cost", 500)
  let imported = raw_costs.any(fn(row) {
    json_text(row.payload, "cost_guid", row.record_id) == cost_id
  })
  if imported && command_type == "create" {
    raise reject(
      409, "source dynamic-cost row is read-only; create a new local cost id",
    )
  }
  if imported && command_type != "create" && current is None {
    raise reject(
      409, "source dynamic-cost row is read-only; create a local command row first",
    )
  }
  if command_type == "create" &&
    current is Some((payload, _)) &&
    json_text(payload, "state", "") != "deleted" {
    raise reject(409, "dynamic-cost already exists")
  }
  if command_type != "create" {
    match current {
      None => raise reject(404, "dynamic-cost not found")
      Some((payload, _)) => {
        if json_text(payload, "source_kind", "") != "command" {
          raise reject(
            409, "source dynamic-cost row is read-only; create a local command row first",
          )
        }
        if json_text(payload, "state", "") == "deleted" {
          raise reject(409, "dynamic-cost is already voided")
        }
      }
    }
  }
  let event_id = "dynamic-cost:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    "active"
  } else if command_type == "void" {
    "deleted"
  } else {
    json_text(current_payload, "state", "active")
  }
  let next_revision = if command_type == "create" && current is None {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "cost_id": Json::string(cost_id),
    "cost_code": Json::string(
      json_text(
        request,
        "cost_code",
        json_text(current_payload, "cost_code", cost_id),
      ),
    ),
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
    "cost_id": Json::string(cost_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    @postgres.sql_literal(request_json) +
    "::jsonb || jsonb_build_object('state', 'active', 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "update" {
    @postgres.sql_literal(current_json) +
    "::jsonb || (" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'command_type' - 'cost_id' - 'actor_id') || jsonb_build_object('event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', 'deleted', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
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
    "action": Json::string("dynamic_cost." + command_type),
    "aggregate_type": Json::string("dynamic_cost"),
    "aggregate_id": Json::string(cost_id),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('dynamic_cost_command', " +
    @postgres.sql_literal(cost_id) +
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
    if command_type == "create" && current is None {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "dynamic_cost": result,
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
  source_instance_count : Int
  source_action_count : Int
  command_projection_count : Int
}

///|
async fn workflow_source_rows() -> WorkflowSourceRows raise CompanyServiceError {
  let process_defs = raw_source_rows("wf_process_def", 500)
  let step_defs = raw_source_rows("wf_step_def", 500)
  let step_assignees = raw_source_rows("wf_step_assignee", 500)
  let users = raw_source_rows("sys_user", 500)
  let instances = raw_source_rows("wf_process_instance", 500)
  let actions = raw_source_rows("wf_step_action", 500)
  let source_instance_count = instances.length()
  let source_action_count = actions.length()
  let command_instances = workflow_command_payloads("workflow_instance")
  for payload in command_instances {
    let aggregate_id = json_text(payload, "process_instance_guid", "")
    if valid_identifier(aggregate_id) {
      instances.push({
        record_id: aggregate_id,
        source_id: "moonproj:command:workflow:" + aggregate_id,
        payload,
      })
    }
  }
  let command_actions = workflow_command_payloads("workflow_action")
  for payload in command_actions {
    let aggregate_id = json_text(payload, "action_guid", "")
    if valid_identifier(aggregate_id) {
      actions.push({
        record_id: aggregate_id,
        source_id: "moonproj:command:workflow-action:" + aggregate_id,
        payload,
      })
    }
  }
  {
    process_defs,
    step_defs,
    step_assignees,
    users,
    instances,
    actions,
    source_instance_count,
    source_action_count,
    command_projection_count: command_instances.length() +
    command_actions.length(),
  }
}

///|
fn workflow_source_coverage(rows : WorkflowSourceRows) -> Json {
  Json::object({
    "sys_user": Json::number(rows.users.length().to_double()),
    "wf_process_def": Json::number(rows.process_defs.length().to_double()),
    "wf_process_instance": Json::number(rows.source_instance_count.to_double()),
    "wf_step_action": Json::number(rows.source_action_count.to_double()),
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
  if rows.source_instance_count == 0 {
    missing.push(Json::string("wf_process_instance"))
  }
  if rows.source_action_count == 0 {
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
    "source_kind": Json::string(
      if rows.command_projection_count > 0 {
        "imported_or_command"
      } else {
        "imported_or_empty"
      },
    ),
    "source_coverage": workflow_source_coverage(rows),
    "missing_or_empty_source_tables": Json::array(workflow_source_missing(rows)),
    "command_projection": Json::boolean(rows.command_projection_count > 0),
    "command_projection_count": Json::number(
      rows.command_projection_count.to_double(),
    ),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(rows.command_projection_count > 0),
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
    "sourceId": Json::string(row.source_id),
    "sourceKind": Json::string(
      if row.source_id.has_prefix("moonproj:") {
        "command"
      } else {
        "imported"
      },
    ),
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
    "sourceId": Json::string(row.source_id),
    "sourceKind": Json::string(
      if row.source_id.has_prefix("moonproj:") {
        "command"
      } else {
        "imported"
      },
    ),
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
fn invoice_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn invoice_optional_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let field = match json_field(body, primary) {
    Some(value) => Some(value)
    None => json_field(body, fallback)
  }
  let value = match field {
    None | Some(Null) => ""
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn invoice_numeric_minor(
  value : Json,
  key : String,
  minimum : Int,
) -> Int raise CompanyServiceError {
  let number = match value {
    Number(number, ..) => number
    String(text) => {
      let cleaned = text.trim().to_owned()
      if cleaned.is_empty() {
        raise reject(422, key + " must be a decimal number")
      }
      parse_number(cleaned)
    }
    _ => raise reject(422, key + " must be a decimal number")
  }
  if number < minimum.to_double() {
    raise reject(422, key + " must be a positive decimal number")
  }
  let minor = (number * 100.0 + 0.5).to_int()
  if minor < minimum * 100 {
    raise reject(422, key + " must be a positive decimal number")
  }
  minor
}

///|
fn invoice_body_minor(
  body : Json,
  primary : String,
  fallback : String,
  default : Int,
  minimum : Int,
) -> Int raise CompanyServiceError {
  match json_field(body, primary) {
    Some(value) => invoice_numeric_minor(value, primary, minimum)
    None =>
      match json_field(body, fallback) {
        Some(value) => invoice_numeric_minor(value, primary, minimum)
        None => default
      }
  }
}

///|
fn invoice_minor_text(minor : Int) -> String {
  let negative = minor < 0
  let value = if negative { -minor } else { minor }
  let whole = value / 100
  let cents = value % 100
  let cents_text = if cents < 10 {
    "0" + cents.to_string()
  } else {
    cents.to_string()
  }
  (if negative { "-" } else { "" }) + whole.to_string() + "." + cents_text
}

///|
fn invoice_authority(
  body : Json,
  actor_id : String,
  principal_id : String,
  scope : String,
  capability : String,
  amount_minor : Int,
) -> Json raise CompanyServiceError {
  let grant = match json_field(body, "authority") {
    Some(Object(_)) => json_field(body, "authority").unwrap()
    _ => raise reject(403, "active invoice authority grant is required")
  }
  if !json_bool(grant, "active", false) {
    raise reject(403, "active invoice authority grant is required")
  }
  if json_text(grant, "principal_id", "") != principal_id {
    raise reject(403, "invoice authority principal does not match")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(403, "invoice authority actor does not match signed actor")
  }
  if json_text(grant, "scope", "") != scope {
    raise reject(403, "invoice authority scope does not match")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "invoice authority must allow " + capability)
  }
  let max_amount_minor = match json_field(grant, "max_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(String(text)) => parse_decimal(text.trim().to_owned())
    _ => raise reject(403, "invoice authority max_amount_minor is required")
  }
  if max_amount_minor < amount_minor {
    raise reject(403, "invoice authority amount is exceeded")
  }
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string(principal_id),
    "actor_id": Json::string(actor_id),
    "scope": Json::string(scope),
    "capability": Json::string(capability),
    "max_amount_minor": Json::number(max_amount_minor.to_double()),
  })
}

///|
fn invoice_create_request(
  direction : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let requested_id = invoice_optional_text(
    body, "invoiceGuid", "invoice_guid", true,
  )
  let generated_id = "INV-" + direction.to_upper() + "-" + idempotency_key
  let invoice_id = if requested_id.is_empty() {
    if generated_id.length() > 128 {
      generated_id[:128].to_owned()
    } else {
      generated_id
    }
  } else {
    requested_id
  }
  let invoice_no = invoice_required_text(body, "invoiceNo", false)
  let total_minor = invoice_body_minor(
    body, "totalAmount", "total_amount", 0, 1,
  )
  let tax_rate_minor = invoice_body_minor(body, "taxRate", "tax_rate", 0, 0)
  let total = total_minor.to_double() / 100.0
  let tax_rate = tax_rate_minor.to_double() / 100.0
  let tax_minor = (round_places(total * tax_rate / (1.0 + tax_rate), 2) * 100.0 +
  0.5).to_int()
  let principal_id = invoice_required_text(body, "principal_id", true)
  let scope = invoice_required_text(body, "scope", true)
  let authority = invoice_authority(
    body,
    actor_id,
    principal_id,
    scope,
    "invoice:" + direction + ":create",
    total_minor,
  )
  Json::object({
    "invoice_guid": Json::string(invoice_id),
    "invoice_no": Json::string(invoice_no),
    "proj_guid": Json::string(
      invoice_optional_text(body, "projGuid", "proj_guid", true),
    ),
    "bu_guid": Json::string(
      invoice_optional_text(body, "buGuid", "bu_guid", true),
    ),
    "contract_guid": Json::string(
      invoice_optional_text(body, "contractGuid", "contract_guid", true),
    ),
    "provider_name": Json::string(
      invoice_optional_text(body, "providerName", "provider_name", false),
    ),
    "customer_name": Json::string(
      invoice_optional_text(body, "customerName", "customer_name", false),
    ),
    "scontract_guid": Json::string(
      invoice_optional_text(body, "scontractGuid", "scontract_guid", true),
    ),
    "revenue_guid": Json::string(
      invoice_optional_text(body, "revenueGuid", "revenue_guid", true),
    ),
    "invoice_date": Json::string(
      invoice_optional_text(body, "invoiceDate", "invoice_date", false),
    ),
    "total_amount": Json::string(invoice_minor_text(total_minor)),
    "tax_amount": Json::string(invoice_minor_text(tax_minor)),
    "tax_rate": Json::string(invoice_minor_text(tax_rate_minor)),
    "invoice_type": Json::string(
      if invoice_optional_text(body, "invoiceType", "invoice_type", false).is_empty() {
        if direction == "in" {
          "增值税专用发票"
        } else {
          "增值税普通发票"
        }
      } else {
        invoice_optional_text(body, "invoiceType", "invoice_type", false)
      },
    ),
    "remark": Json::string(
      invoice_optional_text(body, "remark", "remark", false),
    ),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "actor_id": Json::string(actor_id),
    "command_type": Json::string("create"),
    "direction": Json::string(direction),
    "authority": authority,
    "state": Json::string(if direction == "in" { "received" } else { "issued" }),
  })
}

///|
fn invoice_delete_request(
  direction : String,
  invoice_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(invoice_id) {
    raise reject(422, "invoice_id is required")
  }
  let principal_id = invoice_required_text(body, "principal_id", true)
  let scope = invoice_required_text(body, "scope", true)
  let authority = invoice_authority(
    body,
    actor_id,
    principal_id,
    scope,
    "invoice:" + direction + ":delete",
    0,
  )
  Json::object({
    "invoice_guid": Json::string(invoice_id),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "actor_id": Json::string(actor_id),
    "command_type": Json::string("delete"),
    "direction": Json::string(direction),
    "authority": authority,
  })
}

///|
async fn latest_invoice_payload(
  direction : String,
  invoice_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let aggregate_type = "invoice_" + direction
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(invoice_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid invoice projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn invoice_imported_exists(
  direction : String,
  invoice_id : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows("invoice_" + direction, 500)
  for row in rows {
    if json_text(row.payload, "invoice_guid", row.record_id) == invoice_id &&
      json_text(row.payload, "deleted_at", "").is_empty() &&
      json_text(row.payload, "state", "") != "deleted" {
      return true
    }
  }
  false
}

///|
async fn invoice_command(
  direction : String,
  command_type : String,
  invoice_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if (direction != "in" && direction != "out") ||
    (command_type != "create" && command_type != "delete") {
    raise reject(404, "unsupported invoice command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    let request = invoice_create_request(
      direction, body, actor_id, idempotency_key,
    )
    (json_text(request, "invoice_guid", ""), request)
  } else {
    let id = match invoice_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "invoice_id is required")
    }
    (id, invoice_delete_request(direction, id, body, actor_id))
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "invoice": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_invoice_payload(direction, id)
  let imported = invoice_imported_exists(direction, id)
  let aggregate_type = "invoice_" + direction
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "invoice already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported invoice is read-only; create a local invoice first",
          )
        }
        raise reject(404, "invoice not found")
      }
      Some((payload, _)) => {
        if json_text(payload, "principal_id", "") !=
          json_text(request, "principal_id", "") {
          raise reject(403, "invoice principal does not match")
        }
        if json_text(payload, "scope", "") != json_text(request, "scope", "") {
          raise reject(403, "invoice scope does not match")
        }
        if json_text(payload, "state", "") == "deleted" {
          raise reject(409, "invoice is already deleted")
        }
      }
    }
  }
  let event_id = "invoice:" +
    direction +
    ":" +
    command_type +
    ":" +
    idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    if direction == "in" {
      "received"
    } else {
      "issued"
    }
  } else {
    "deleted"
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "invoiceGuid": Json::string(id),
    "direction": Json::string(direction),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("invoice"),
    "direction": Json::string(direction),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    "(" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'authority') || jsonb_build_object('source_kind', 'command', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('source_kind', 'command', 'state', 'deleted', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("invoice." + direction + "." + command_type),
    "aggregate_type": Json::string(aggregate_type),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(aggregate_type) +
    ", " +
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
      "invoice": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn sales_revenue_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
  allow_empty : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::null())
  }
  let text = match value {
    Null => ""
    String(value) => value.trim().to_owned()
    Number(value, ..) => value.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if !allow_empty && text.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !text.is_empty() && !valid_identifier(text) {
    raise reject(422, primary + " contains unsupported characters")
  }
  text
}

///|
fn sales_revenue_amount_minor(body : Json) -> Int raise CompanyServiceError {
  match json_field(body, "amount_minor") {
    Some(Number(value, ..)) if value > 0.0 &&
      value == value.to_int().to_double() => value.to_int()
    Some(_) => raise reject(422, "amount_minor must be a positive integer")
    None =>
      match json_field(body, "amount") {
        Some(Number(value, ..)) => {
          if value <= 0.0 {
            raise reject(422, "amount must be a positive decimal number")
          }
          let minor = (value * 100.0 + 0.5).to_int()
          if minor <= 0 {
            raise reject(422, "amount must be a positive decimal number")
          }
          minor
        }
        Some(String(value)) => {
          let parsed = parse_number(value.trim().to_owned())
          if parsed <= 0.0 {
            raise reject(422, "amount must be a positive decimal number")
          }
          let minor = (parsed * 100.0 + 0.5).to_int()
          if minor <= 0 {
            raise reject(422, "amount must be a positive decimal number")
          }
          minor
        }
        _ => raise reject(422, "amount is required")
      }
  }
}

///|
fn sales_revenue_authority(
  body : Json,
  actor_id : String,
  principal_id : String,
  scope : String,
  capability : String,
  amount_minor : Int,
) -> Json raise CompanyServiceError {
  let grant = match json_field(body, "authority") {
    Some(Object(_)) => json_field(body, "authority").unwrap()
    _ => raise reject(403, "active sales revenue authority grant is required")
  }
  if !json_bool(grant, "active", false) {
    raise reject(403, "active sales revenue authority grant is required")
  }
  if json_text(grant, "principal_id", "") != principal_id {
    raise reject(403, "sales revenue authority principal does not match")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(
      403, "sales revenue authority actor does not match signed actor",
    )
  }
  if json_text(grant, "scope", "") != scope {
    raise reject(403, "sales revenue authority scope does not match")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "sales revenue authority must allow " + capability)
  }
  let max_amount_minor = match json_field(grant, "max_amount_minor") {
    Some(Number(value, ..)) if value >= 0.0 &&
      value == value.to_int().to_double() => value.to_int()
    Some(String(value)) => parse_decimal(value.trim().to_owned())
    _ =>
      raise reject(403, "sales revenue authority max_amount_minor is required")
  }
  if max_amount_minor < amount_minor {
    raise reject(403, "sales revenue authority amount is exceeded")
  }
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string(principal_id),
    "actor_id": Json::string(actor_id),
    "scope": Json::string(scope),
    "capability": Json::string(capability),
    "max_amount_minor": Json::number(max_amount_minor.to_double()),
  })
}

///|
fn sales_revenue_create_request(
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let revenue_id = sales_revenue_text(
    body, "revenue_id", "revenueGuid", true, false,
  )
  let revenue_code = {
    let value = sales_revenue_text(
      body, "revenue_code", "revenueCode", true, true,
    )
    if value.is_empty() {
      "SR-" + revenue_id
    } else {
      value
    }
  }
  if !valid_identifier(revenue_code) {
    raise reject(422, "revenue_code contains unsupported characters")
  }
  let principal_id = sales_revenue_text(body, "principal_id", "", true, false)
  let scope = sales_revenue_text(body, "scope", "", true, false)
  let amount_minor = sales_revenue_amount_minor(body)
  let authority = sales_revenue_authority(
    body, actor_id, principal_id, scope, "sales:revenue:create", amount_minor,
  )
  let status = sales_revenue_text(body, "status", "", false, true)
  let normalized_status = if status.is_empty() { "expected" } else { status }
  if normalized_status != "expected" && normalized_status != "received" {
    raise reject(422, "status must be expected or received")
  }
  let state = if normalized_status == "received" {
    "received"
  } else {
    "expected"
  }
  Json::object({
    "command_type": Json::string("create"),
    "revenue_id": Json::string(revenue_id),
    "revenue_guid": Json::string(revenue_id),
    "revenue_code": Json::string(revenue_code),
    "proj_guid": Json::string(
      sales_revenue_text(body, "proj_guid", "projGuid", true, false),
    ),
    "bu_guid": Json::string(
      sales_revenue_text(body, "bu_guid", "buGuid", true, true),
    ),
    "customer_name": Json::string(
      sales_revenue_text(body, "customer_name", "customerName", false, false),
    ),
    "amount_minor": Json::number(amount_minor.to_double()),
    "amount": Json::string(invoice_minor_text(amount_minor)),
    "receive_date": Json::string(
      sales_revenue_text(body, "receive_date", "receiveDate", false, true),
    ),
    "status": Json::string(normalized_status),
    "payment_type": Json::string(
      sales_revenue_text(body, "payment_type", "paymentType", false, true),
    ),
    "contract_no": Json::string(
      sales_revenue_text(body, "contract_no", "contractNo", false, true),
    ),
    "remark": Json::string(sales_revenue_text(body, "remark", "", false, true)),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "authority": authority,
    "actor_id": Json::string(actor_id),
    "state": Json::string(state),
  })
}

///|
fn sales_revenue_update_request(
  revenue_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(revenue_id) {
    raise reject(422, "revenue_id is required")
  }
  let principal_id = sales_revenue_text(body, "principal_id", "", true, false)
  let scope = sales_revenue_text(body, "scope", "", true, false)
  let amount_minor = if json_field(body, "amount_minor") is Some(_) ||
    json_field(body, "amount") is Some(_) {
    sales_revenue_amount_minor(body)
  } else {
    0
  }
  let authority = sales_revenue_authority(
    body, actor_id, principal_id, scope, "sales:revenue:update", amount_minor,
  )
  let changes : Map[String, Json] = {}
  let mut changed = false
  let add_text = fn(
    primary : String,
    fallback : String,
  ) raise CompanyServiceError {
    if json_field(body, primary) is Some(_) ||
      json_field(body, fallback) is Some(_) {
      changes.set(
        primary,
        Json::string(sales_revenue_text(body, primary, fallback, false, true)),
      )
      changed = true
    }
  }
  add_text("customer_name", "customerName")
  add_text("receive_date", "receiveDate")
  add_text("payment_type", "paymentType")
  add_text("contract_no", "contractNo")
  add_text("remark", "remark")
  if amount_minor > 0 {
    changes.set("amount_minor", Json::number(amount_minor.to_double()))
    changes.set("amount", Json::string(invoice_minor_text(amount_minor)))
    changed = true
  }
  if !changed {
    raise reject(422, "update requires at least one mutable revenue field")
  }
  Json::object({
    "command_type": Json::string("update"),
    "revenue_id": Json::string(revenue_id),
    "actor_id": Json::string(actor_id),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "authority": authority,
    "changes": Json::object(changes),
  })
}

///|
fn sales_revenue_transition_request(
  command_type : String,
  revenue_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(revenue_id) {
    raise reject(422, "revenue_id is required")
  }
  let principal_id = sales_revenue_text(body, "principal_id", "", true, false)
  let scope = sales_revenue_text(body, "scope", "", true, false)
  let authority = sales_revenue_authority(
    body,
    actor_id,
    principal_id,
    scope,
    "sales:revenue:" + command_type,
    0,
  )
  Json::object({
    "command_type": Json::string(command_type),
    "revenue_id": Json::string(revenue_id),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "authority": authority,
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_sales_revenue_payload(
  revenue_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'sale_revenue' AND aggregate_id = " +
    @postgres.sql_literal(revenue_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid sales revenue projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn sales_revenue_imported_exists(
  revenue_id : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows("sale_revenue", 500)
  for row in rows {
    let identity = json_text(row.payload, "revenue_guid", row.record_id)
    if identity == revenue_id {
      return true
    }
  }
  false
}

///|
async fn sales_revenue_command(
  command_type : String,
  revenue_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "create" &&
    command_type != "update" &&
    command_type != "confirm_received" &&
    command_type != "delete" {
    raise reject(404, "unsupported sales revenue command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    let request = sales_revenue_create_request(body, actor_id)
    (json_text(request, "revenue_id", ""), request)
  } else {
    let id = match revenue_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "revenue_id is required")
    }
    let request = if command_type == "update" {
      sales_revenue_update_request(id, body, actor_id)
    } else {
      sales_revenue_transition_request(command_type, id, body, actor_id)
    }
    (id, request)
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "revenue": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_sales_revenue_payload(id)
  let imported = sales_revenue_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "revenue already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported revenue is read-only; create a local revenue first",
          )
        }
        raise reject(404, "revenue not found")
      }
      Some((payload, _)) => {
        if json_text(payload, "source_kind", "") != "command" {
          raise reject(
            409, "imported revenue is read-only; create a local revenue first",
          )
        }
        let state = json_text(
          payload,
          "status",
          json_text(payload, "state", ""),
        )
        let allowed = if command_type == "update" {
          state == "expected" || state == "received"
        } else if command_type == "confirm_received" {
          state == "expected"
        } else {
          state == "expected" || state == "received"
        }
        if !allowed {
          raise reject(
            409,
            "revenue transition " +
            command_type +
            " is not allowed from " +
            state,
          )
        }
      }
    }
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let current_state = json_text(
    current_payload,
    "status",
    json_text(current_payload, "state", "expected"),
  )
  let next_state = if command_type == "create" {
    json_text(request, "state", "expected")
  } else if command_type == "confirm_received" {
    "received"
  } else if command_type == "delete" {
    "deleted"
  } else {
    current_state
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "sale_revenue:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "aggregate_id": Json::string(id),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("revenues"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("sale_revenue"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let request_projection = "(" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'authority' - 'changes') || coalesce(" +
    @postgres.sql_literal(request_json) +
    "::jsonb->'changes', '{}'::jsonb)"
  let next_payload_sql = if command_type == "create" {
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'status', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "delete" {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', 'deleted', 'status', 'deleted', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'status', " +
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
    "action": Json::string("revenues." + command_type),
    "aggregate_type": Json::string("sale_revenue"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('sale_revenue', " +
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
      "revenue": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn tender_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
  allow_empty : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::null())
  }
  let text = match value {
    Null => ""
    String(value) => value.trim().to_owned()
    Number(value, ..) => value.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if !allow_empty && text.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !text.is_empty() && !valid_identifier(text) {
    raise reject(422, primary + " contains unsupported characters")
  }
  text
}

///|
fn tender_decimal_minor(
  body : Json,
  primary : String,
  fallback : String,
  default : Int,
  allow_zero : Bool,
) -> Int raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(value) => value
    None => json_field(body, fallback).unwrap_or(Json::null())
  }
  let parsed = match value {
    Null => {
      if default >= 0 {
        return default
      }
      raise reject(422, primary + " must be a decimal number")
    }
    Number(number, ..) => number
    String(text) => parse_number(text.trim().to_owned())
    _ => raise reject(422, primary + " must be a decimal number")
  }
  if parsed < 0.0 || (!allow_zero && parsed == 0.0) {
    raise reject(422, primary + " is below the minimum")
  }
  let minor = (parsed * 100.0 + 0.5).to_int()
  if !allow_zero && minor <= 0 {
    raise reject(422, primary + " is below the minimum")
  }
  minor
}

///|
fn tender_currency(
  body : Json,
  primary : String,
  fallback : String,
  default : String,
) -> String raise CompanyServiceError {
  let value = tender_text(body, primary, fallback, true, true)
  let normalized = if value.is_empty() { default } else { value.to_upper() }
  if normalized.length() != 3 {
    raise reject(422, "currency must be a three-letter code")
  }
  for char in normalized.iter() {
    if char < 'A' || char > 'Z' {
      raise reject(422, "currency must be a three-letter code")
    }
  }
  normalized
}

///|
fn tender_bids(
  body : Json,
  estimated_amount_minor : Int,
  currency : String,
) -> Json raise CompanyServiceError {
  match json_field(body, "bids") {
    None | Some(Null) => Json::array([])
    Some(Array(values)) => {
      let result : Array[Json] = []
      let seen : Array[String] = []
      for value in values {
        let supplier_id = tender_text(
          value, "supplier_id", "supplierId", true, false,
        )
        if seen.contains(supplier_id) {
          raise reject(422, "a supplier may bid only once")
        }
        let amount_minor = match json_field(value, "amount_minor") {
          Some(Number(number, ..)) if number > 0.0 &&
            number == number.to_int().to_double() => number.to_int()
          _ => raise reject(422, "bid amount_minor must be a positive integer")
        }
        if amount_minor > estimated_amount_minor {
          raise reject(422, "bid amount exceeds tender estimate")
        }
        seen.push(supplier_id)
        result.push(
          Json::object({
            "supplier_id": Json::string(supplier_id),
            "amount_minor": Json::number(amount_minor.to_double()),
            "currency": Json::string(currency),
          }),
        )
      }
      Json::array(result)
    }
    Some(_) => raise reject(422, "bids must be an array")
  }
}

///|
fn tender_create_request(
  body : Json,
  actor_id : String,
  source_alias : Bool,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let requested_id = tender_text(body, "tender_id", "tenderGuid", true, true)
  let tender_id = if requested_id.is_empty() {
    (if source_alias { "TD-SRC-" } else { "TD-" }) + idempotency_key
  } else {
    requested_id
  }
  if !valid_identifier(tender_id) {
    raise reject(422, "tender_id contains unsupported characters")
  }
  let project_guid = if source_alias {
    tender_text(body, "proj_guid", "projGuid", true, false)
  } else {
    ""
  }
  let project_scope = if source_alias {
    if project_guid.is_empty() {
      raise reject(422, "projGuid is required")
    }
    "project:" + project_guid
  } else {
    tender_text(body, "project_scope", "", true, false)
  }
  let name = tender_text(body, "name", "tenderName", false, false)
  let category = tender_text(body, "category", "", false, source_alias)
  let normalized_category = if category.is_empty() {
    "uncategorized"
  } else {
    category
  }
  let estimated_amount_minor = match
    json_field(body, "estimated_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(_) =>
      raise reject(422, "estimated_amount_minor must be a non-negative integer")
    None =>
      tender_decimal_minor(
        body,
        "estimated_amount",
        "estimatedAmount",
        if source_alias {
          0
        } else {
          -1
        },
        source_alias,
      )
  }
  let currency = tender_currency(body, "currency", "", "CNY")
  let tender_code_value = tender_text(
    body, "tender_code", "tenderCode", true, true,
  )
  let tender_code = if tender_code_value.is_empty() {
    let start = if tender_id.length() > 24 {
      tender_id.length() - 24
    } else {
      0
    }
    "TD-" + tender_id[start:].to_owned()
  } else {
    tender_code_value
  }
  if !valid_identifier(tender_code) || tender_code.length() > 128 {
    raise reject(422, "tenderCode is invalid")
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("create"))
  request.set("tender_id", Json::string(tender_id))
  request.set("tender_code", Json::string(tender_code))
  request.set("project_scope", Json::string(project_scope))
  request.set("name", Json::string(name))
  request.set("category", Json::string(normalized_category))
  request.set(
    "estimated_amount_minor",
    Json::number(estimated_amount_minor.to_double()),
  )
  request.set("currency", Json::string(currency))
  request.set("bids", tender_bids(body, estimated_amount_minor, currency))
  request.set("actor_id", Json::string(actor_id))
  for
    pair in [
      ("plan_publish_date", "planPublishDate"),
      ("plan_award_date", "planAwardDate"),
      ("remark", "remark"),
    ] {
    let value = tender_text(body, pair.0, pair.1, false, true)
    if !value.is_empty() {
      if value.length() > 256 {
        raise reject(422, pair.1 + " is too long")
      }
      request.set(pair.0, Json::string(value))
    }
  }
  Json::object(request)
}

///|
fn tender_transition_request(
  command_type : String,
  tender_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(tender_id) {
    raise reject(422, "tender_id is required")
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string(command_type))
  request.set("tender_id", Json::string(tender_id))
  request.set("actor_id", Json::string(actor_id))
  if command_type == "award" {
    request.set(
      "awarded_supplier_id",
      Json::string(
        tender_text(
          body, "awarded_supplier_id", "awardedSupplierId", true, false,
        ),
      ),
    )
    let amount = match json_field(body, "awarded_amount_minor") {
      Some(Number(number, ..)) if number > 0.0 &&
        number == number.to_int().to_double() => number.to_int()
      _ => raise reject(422, "awarded_amount_minor must be a positive integer")
    }
    request.set("awarded_amount_minor", Json::number(amount.to_double()))
    let provider_name = tender_text(
      body, "providerName", "provider_name", false, true,
    )
    if !provider_name.is_empty() {
      request.set("awarded_supplier_name", Json::string(provider_name))
    }
  }
  let reason = tender_text(body, "reason", "", false, true)
  request.set("reason", Json::string(reason))
  Json::object(request)
}

///|
/// Translate the ERP tender award body into the native, qualification-gated
/// award command.  The source route permits a provider name without a
/// provider identity; the native boundary requires the identity so it can
/// prove an active qualified supplier projection before changing state.
fn tender_source_award_request(
  body : Json,
  actor_id : String,
) -> (String, Json) raise CompanyServiceError {
  let tender_id = tender_text(body, "tenderGuid", "tender_guid", true, false)
  let supplier_id = tender_text(
    body, "providerGuid", "provider_guid", true, false,
  )
  let amount_minor = tender_decimal_minor(
    body, "awardAmount", "award_amount", -1, false,
  )
  let request : Map[String, Json] = {}
  request.set("awarded_supplier_id", Json::string(supplier_id))
  request.set("awarded_amount_minor", Json::number(amount_minor.to_double()))
  request.set("actor_id", Json::string(actor_id))
  let provider_name = tender_text(
    body, "providerName", "provider_name", false, true,
  )
  if !provider_name.is_empty() {
    request.set("awarded_supplier_name", Json::string(provider_name))
  }
  let award_date = tender_text(body, "awardDate", "award_date", false, true)
  if !award_date.is_empty() {
    request.set("award_date", Json::string(award_date))
  }
  let remark = tender_text(body, "remark", "", false, true)
  if !remark.is_empty() {
    request.set("reason", Json::string(remark))
  }
  (tender_id, Json::object(request))
}

///|
fn tender_source_state_command(
  body : Json,
  actor_id : String,
) -> (String, Json) raise CompanyServiceError {
  let state = tender_text(body, "state", "", false, false)
  if state == "planning" {
    raise reject(
      409, "source tender state cannot move a command tender backwards",
    )
  }
  if state == "publishing" {
    return ("publish", body)
  }
  if state == "bidding" {
    return ("open_bidding", body)
  }
  if state == "completed" {
    return ("complete", body)
  }
  if state == "awarded" {
    return tender_source_award_request(body, actor_id)
  }
  raise reject(422, "unsupported source tender state")
}

///|
async fn latest_tender_payload(
  tender_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'tender' AND aggregate_id = " +
    @postgres.sql_literal(tender_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid tender projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn tender_imported_exists(
  tender_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("tender_plan", 500) {
    if json_text(row.payload, "tender_guid", row.record_id) == tender_id {
      return true
    }
  }
  false
}

///|
fn tender_next_state(
  command_type : String,
  current_state : String,
) -> String raise CompanyServiceError {
  if command_type == "publish" {
    if current_state != "planning" {
      raise reject(
        409,
        "tender transition publish requires planning, found " + current_state,
      )
    }
    "publishing"
  } else if command_type == "open_bidding" {
    if current_state != "publishing" {
      raise reject(
        409,
        "tender transition open_bidding requires publishing, found " +
        current_state,
      )
    }
    "bidding"
  } else if command_type == "award" {
    if current_state != "bidding" {
      raise reject(
        409,
        "tender transition award requires bidding, found " + current_state,
      )
    }
    "awarded"
  } else if command_type == "complete" {
    if current_state != "awarded" {
      raise reject(
        409,
        "tender transition complete requires awarded, found " + current_state,
      )
    }
    "completed"
  } else if command_type == "cancel" {
    if !["planning", "publishing", "bidding"].contains(current_state) {
      raise reject(
        409,
        "tender cancellation requires an active planning state, found " +
        current_state,
      )
    }
    "cancelled"
  } else if command_type == "delete" {
    if current_state == "deleted" {
      raise reject(409, "tender is already deleted")
    }
    "deleted"
  } else {
    raise reject(404, "unsupported tender command")
  }
}

///|
fn tender_award_matches(payload : Json, request : Json) -> Bool {
  let supplier_id = json_text(request, "awarded_supplier_id", "")
  let amount = json_int(request, "awarded_amount_minor", 0)
  match json_field(payload, "bids") {
    Some(Array(bids)) =>
      for bid in bids {
        if json_text(bid, "supplier_id", "") == supplier_id &&
          json_int(bid, "amount_minor", 0) == amount {
          return true
        }
      }
    _ => ()
  }
  false
}

///|
async fn tender_supplier_qualified(
  supplier_id : String,
) -> Bool raise CompanyServiceError {
  let output = run_sql(
    "SELECT CASE WHEN coalesce(payload->>'state', '') = 'active' AND coalesce(payload->>'evaluation', '') IN ('qualified', 'strategic') THEN 'true' ELSE 'false' END FROM (SELECT DISTINCT ON (aggregate_id) payload FROM company_aggregate_projection WHERE aggregate_type = 'supplier' AND aggregate_id = " +
    @postgres.sql_literal(supplier_id) +
    " ORDER BY aggregate_id, revision DESC) latest",
  )
  output.trim() == "true"
}

///|
async fn tender_command(
  command_type : String,
  tender_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if ![
      "create", "publish", "open_bidding", "award", "complete", "cancel", "delete",
    ].contains(command_type) {
    raise reject(404, "unsupported tender command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    let request = if json_text(body, "command_type", "") == "create" {
      body
    } else {
      tender_create_request(body, actor_id, false, idempotency_key)
    }
    (json_text(request, "tender_id", ""), request)
  } else {
    let id = match tender_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "tender_id is required")
    }
    (id, tender_transition_request(command_type, id, body, actor_id))
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "tender": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_tender_payload(id)
  let imported = tender_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "tender already exists")
    }
  } else {
    let payload = match current {
      Some((payload, _)) => payload
      None => {
        if imported {
          raise reject(
            409, "imported tender is read-only; create a local planning draft first",
          )
        }
        raise reject(404, "tender not found")
      }
    }
    if json_text(payload, "source_kind", "") != "command" {
      raise reject(
        409, "imported tender is read-only; create a local planning draft first",
      )
    }
    if command_type == "award" && !tender_award_matches(payload, request) {
      raise reject(422, "award must match an existing bid")
    }
    if command_type == "award" &&
      !tender_supplier_qualified(json_text(request, "awarded_supplier_id", "")) {
      raise reject(
        409, "award requires an active qualified supplier projection",
      )
    }
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let current_state = json_text(current_payload, "state", "planning")
  let next_state = if command_type == "create" {
    "planning"
  } else {
    tender_next_state(command_type, current_state)
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "tender:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "tender_id": Json::string(id),
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
    "tender_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    @postgres.sql_literal(request_json) +
    "::jsonb || jsonb_build_object('state', 'planning', 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    let award_fields = if command_type == "award" {
      ", 'award_guid', " +
      @postgres.sql_literal("AW-" + idempotency_key) +
      ", 'award_code', " +
      @postgres.sql_literal("AW-" + idempotency_key) +
      ", 'awarded_supplier_id', " +
      @postgres.sql_literal(json_text(request, "awarded_supplier_id", "")) +
      ", 'provider_guid', " +
      @postgres.sql_literal(json_text(request, "awarded_supplier_id", "")) +
      ", 'provider_name', " +
      @postgres.sql_literal(json_text(request, "awarded_supplier_name", "")) +
      ", 'awarded_amount_minor', " +
      json_int(request, "awarded_amount_minor", 0).to_string()
    } else {
      ""
    }
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    award_fields +
    (if command_type == "delete" {
      ", 'deleted_at', " + @postgres.sql_literal(event_id)
    } else {
      ""
    }) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("tender." + command_type),
    "aggregate_type": Json::string("tender"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('tender', " +
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
    ") ON CONFLICT DO NOTHING; UPDATE company_record SET payload = payload || jsonb_build_object('result', " +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb) WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "create" {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "tender": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn source_tender_alias_result(result : Json) -> Json {
  let tender = json_field(result, "tender").unwrap_or(Json::null())
  let command = json_field(result, "command").unwrap_or(Json::null())
  let request = json_field(command, "request").unwrap_or(Json::null())
  let tender_id = json_text(
    tender,
    "tender_id",
    json_text(request, "tender_id", ""),
  )
  let tender_code = json_text(request, "tender_code", "TD-" + tender_id)
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "tenderGuid": Json::string(tender_id),
      "tenderCode": Json::string(tender_code),
    }),
    "tender": tender,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn source_tender_award_alias_result(
  result : Json,
  idempotency_key : String,
) -> Json {
  let tender = json_field(result, "tender").unwrap_or(Json::null())
  let command = json_field(result, "command").unwrap_or(Json::null())
  let request = json_field(command, "request").unwrap_or(Json::null())
  let tender_id = json_text(tender, "tender_id", "")
  let award_id = "AW-" + idempotency_key
  let award_code = award_id
  let amount_minor = json_int(request, "awarded_amount_minor", 0)
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "awardGuid": Json::string(award_id),
      "awardCode": Json::string(award_code),
      "tenderGuid": Json::string(tender_id),
      "providerGuid": Json::string(
        json_text(request, "awarded_supplier_id", ""),
      ),
      "awardAmount": Json::number(amount_minor.to_double() / 100.0),
    }),
    "award": Json::object({
      "award_guid": Json::string(award_id),
      "award_code": Json::string(award_code),
      "tender_guid": Json::string(tender_id),
      "provider_guid": Json::string(
        json_text(request, "awarded_supplier_id", ""),
      ),
      "award_amount_minor": Json::number(amount_minor.to_double()),
      "award_amount": Json::number(amount_minor.to_double() / 100.0),
      "state": Json::string("awarded"),
      "source_kind": Json::string("command"),
    }),
    "tender": tender,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn split_create_request(
  body : Json,
  actor_id : String,
  source_alias : Bool,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let requested_id = tender_text(body, "split_id", "splitGuid", true, true)
  let split_id = if requested_id.is_empty() {
    (if source_alias { "SPLIT-SRC-" } else { "SPLIT-" }) + idempotency_key
  } else {
    requested_id
  }
  if !valid_identifier(split_id) {
    raise reject(422, "splitGuid contains unsupported characters")
  }
  let parent_contract_id = tender_text(
    body, "parent_contract_id", "parentContractGuid", true, false,
  )
  let split_name = tender_text(body, "split_name", "splitName", false, false)
  let amount_minor = match json_field(body, "split_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(_) =>
      raise reject(422, "split_amount_minor must be a non-negative integer")
    None => tender_decimal_minor(body, "splitAmount", "splitAmount", 0, true)
  }
  let pct = match json_field(body, "split_pct_bps") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(_) => raise reject(422, "split_pct_bps must be a non-negative integer")
    None => tender_decimal_minor(body, "splitPct", "splitPct", 0, true)
  }
  if pct > 10000 {
    raise reject(422, "splitPct exceeds the maximum")
  }
  let scope = tender_text(body, "scope", "", false, true)
  Json::object({
    "command_type": Json::string("create"),
    "split_id": Json::string(split_id),
    "parent_contract_id": Json::string(parent_contract_id),
    "split_name": Json::string(split_name),
    "split_amount_minor": Json::number(amount_minor.to_double()),
    "split_pct_bps": Json::number(pct.to_double()),
    "scope": Json::string(scope),
    "state": Json::string("planned"),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn latest_split_payload(
  split_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'contract_split' AND aggregate_id = " +
    @postgres.sql_literal(split_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid contract split projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn split_imported_exists(
  split_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("contract_split", 500) {
    if json_text(row.payload, "split_guid", row.record_id) == split_id {
      return true
    }
  }
  false
}

///|
async fn split_command(
  body : Json,
  actor_id : String,
  source_alias : Bool,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = split_create_request(
    body, actor_id, source_alias, idempotency_key,
  )
  let id = json_text(request, "split_id", "")
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let result = Json::object({
        "command": existing,
        "split": json_field(existing, "result").unwrap_or(Json::null()),
        "idempotent_replay": Json::boolean(true),
      })
      return (
        200,
        if source_alias {
          source_split_alias_result(result)
        } else {
          result
        },
      )
    }
    None => ()
  }
  if latest_split_payload(id) is Some(_) || split_imported_exists(id) {
    raise reject(409, "contract split already exists")
  }
  let parent_contract_id = json_text(request, "parent_contract_id", "")
  if contract_items(Some(parent_contract_id)).is_empty() {
    raise reject(404, "parent contract not found")
  }
  let event_id = "contract_split:create:" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "split_id": Json::string(id),
    "parent_contract_id": Json::string(parent_contract_id),
    "state": Json::string("planned"),
    "revision": Json::number(1),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_type": Json::string("create"),
    "idempotency_key": Json::string(idempotency_key),
    "split_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("contract_split.create"),
    "aggregate_type": Json::string("contract_split"),
    "aggregate_id": Json::string(id),
    "parent_contract_id": Json::string(parent_contract_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string("planned"),
    "revision": Json::number(1),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('contract_split', " +
    @postgres.sql_literal(id) +
    ", 1, " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    "), " +
    @postgres.sql_literal(event_id) +
    "); INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    "); UPDATE company_record SET payload = payload || jsonb_build_object('result', " +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb) WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; COMMIT;"
  let _ = run_sql(sql)
  let response = Json::object({
    "command": command_payload,
    "split": result,
    "idempotent_replay": Json::boolean(false),
  })
  (
    201,
    if source_alias {
      source_split_alias_result(response)
    } else {
      response
    },
  )
}

///|
fn source_split_alias_result(result : Json) -> Json {
  let split = json_field(result, "split").unwrap_or(Json::null())
  let command = json_field(result, "command").unwrap_or(Json::null())
  let split_id = json_text(split, "split_id", "")
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({ "splitGuid": Json::string(split_id) }),
    "split": split,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
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
  let subscription_commands = if family == "subscriptions" {
    sales_subscription_command_rows()
  } else {
    []
  }
  let contracts = raw_source_rows("sale_contract", 500)
  let mortgages = raw_source_rows("sale_mortgage", 500)
  let mortgage_commands = if family == "mortgages" {
    sales_mortgage_command_rows()
  } else {
    []
  }
  let refunds = raw_source_rows("sale_refund", 500)
  let refund_commands = if family == "refunds" {
    sales_refund_command_rows()
  } else {
    []
  }
  let revenues = raw_source_rows("sale_revenue", 500)
  let customer_commands = if family == "customers" {
    sales_customer_command_rows()
  } else {
    []
  }
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
  if family == "customers" {
    for row in customer_commands {
      if sales_source_matches(row.payload, family, proj_guid, state, keyword) {
        result.push(sales_source_item(row, family, "command"))
      }
    }
  }
  if family == "subscriptions" {
    for row in subscription_commands {
      if sales_source_matches(row.payload, family, proj_guid, state, keyword) {
        result.push(sales_source_item(row, family, "command"))
      }
    }
  }
  if family == "mortgages" {
    for row in mortgage_commands {
      if sales_source_matches(row.payload, family, proj_guid, state, keyword) {
        result.push(sales_source_item(row, family, "command"))
      }
    }
  }
  if family == "refunds" {
    for row in refund_commands {
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
/// Expose command-owned awards through the same source-shaped family as
/// imported `tender_award` rows.  Award creation remains qualification-gated;
/// this readback only merges the durable tender projection and has no cash or
/// commitment effect.
async fn tender_command_award_items() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(" +
    "'award_guid', coalesce(payload->>'award_guid', 'AW-' || aggregate_id), " +
    "'award_id', coalesce(payload->>'award_guid', 'AW-' || aggregate_id), " +
    "'award_code', coalesce(payload->>'award_code', 'AW-' || aggregate_id), " +
    "'tender_guid', aggregate_id, 'tender_id', aggregate_id, " +
    "'provider_guid', coalesce(payload->>'provider_guid', payload->>'awarded_supplier_id', ''), " +
    "'provider_id', coalesce(payload->>'provider_guid', payload->>'awarded_supplier_id', ''), " +
    "'provider_name', coalesce(payload->>'provider_name', ''), " +
    "'award_amount_minor', coalesce(payload->>'awarded_amount_minor', '0')::bigint, " +
    "'award_amount', (coalesce(payload->>'awarded_amount_minor', '0')::numeric / 100), " +
    "'award_date', coalesce(payload->>'award_date', payload->>'plan_award_date', ''), " +
    "'remark', coalesce(payload->>'reason', ''), 'state', 'awarded', " +
    "'source_kind', 'command', 'command_projection', true, 'authorizing', false, 'persisted', true, " +
    "'provider_execution', false, 'cash_effect', false, 'accounting_effect', false, 'tax_effect', false, " +
    "'aggregate_type', 'tender_award', 'aggregate_id', coalesce(payload->>'award_guid', 'AW-' || aggregate_id), " +
    "'source_id', 'moonproj:command:tender-award:' || aggregate_id, 'source_table', 'tender_award'" +
    ") ORDER BY aggregate_id), '[]'::jsonb)::text FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'tender' ORDER BY aggregate_id, revision DESC) latest WHERE coalesce(payload->>'state', '') <> 'deleted' AND coalesce(payload->>'award_guid', '') <> ''",
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
  } else if family == "awards" {
    for item in tender_command_award_items() {
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
fn marketing_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for table in ["mkt_campaign", "mkt_placement", "mkt_channel", "mkt_material"] {
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
fn marketing_lookup(value : Json, primary : String, fallback : String) -> Json? {
  match json_field(value, primary) {
    Some(Null) if !fallback.is_empty() => json_field(value, fallback)
    Some(item) => Some(item)
    None if !fallback.is_empty() => json_field(value, fallback)
    None => None
  }
}

///|
fn marketing_text(
  value : Json,
  primary : String,
  fallback : String,
  default : String,
) -> String {
  match marketing_lookup(value, primary, fallback) {
    Some(String(text)) => text
    Some(Number(number, ..)) => number.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => default
  }
}

///|
fn marketing_number(
  value : Json,
  primary : String,
  fallback : String,
  default : Double,
) -> Double {
  match marketing_lookup(value, primary, fallback) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text)
    _ => default
  }
}

///|
fn marketing_command_aggregate(resource : String) -> String {
  match resource {
    "campaign" => "marketing_campaign"
    "placement" => "marketing_placement"
    "channel" => "marketing_channel"
    "material" => "marketing_material"
    _ => ""
  }
}

///|
fn marketing_source_table(resource : String) -> String {
  match resource {
    "campaign" => "mkt_campaign"
    "placement" => "mkt_placement"
    "channel" => "mkt_channel"
    "material" => "mkt_material"
    _ => ""
  }
}

///|
async fn marketing_command_rows(
  resource : String,
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
  let aggregate_type = marketing_command_aggregate(resource)
  if aggregate_type.is_empty() {
    raise fail("unsupported marketing resource")
  }
  let deleted_clause = if include_deleted {
    ""
  } else {
    " WHERE coalesce(payload->>'state', '') <> 'deleted'"
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM (" +
    "SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload, " +
    "source_event_id FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest" +
    deleted_clause +
    " ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid marketing projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[3]),
            payload,
          })
        _ => raise fail("marketing projection payload is not an object")
      }
    }
  }
  result
}

///|
fn marketing_source_kind(row : SourceRow) -> String {
  if json_text(row.payload, "source_kind", "") == "command" {
    "command"
  } else {
    "imported"
  }
}

///|
fn marketing_default(value : String, fallback : String) -> String {
  if value.is_empty() {
    fallback
  } else {
    value
  }
}

///|
fn marketing_source_id(row : SourceRow) -> String {
  if row.source_id.is_empty() {
    row.record_id
  } else {
    row.source_id
  }
}

///|
fn marketing_campaign_item(row : SourceRow) -> Json {
  let payload = row.payload
  let id = marketing_text(
    payload,
    "campaign_guid",
    "campaignGuid",
    row.record_id,
  )
  let source_kind = marketing_source_kind(row)
  Json::object({
    "campaignGuid": Json::string(id),
    "campaignCode": Json::string(
      marketing_text(payload, "campaign_code", "campaignCode", ""),
    ),
    "projGuid": Json::string(
      marketing_text(payload, "proj_guid", "projGuid", ""),
    ),
    "buGuid": Json::string(marketing_text(payload, "bu_guid", "buGuid", "")),
    "name": Json::string(marketing_text(payload, "name", "", "")),
    "campaignType": Json::string(
      marketing_text(payload, "campaign_type", "campaignType", ""),
    ),
    "budget": Json::number(
      marketing_number(payload, "budget", "budget_amount", 0.0),
    ),
    "actualCost": Json::number(
      marketing_number(payload, "actual_cost", "actualCost", 0.0),
    ),
    "startDate": Json::string(
      marketing_text(payload, "start_date", "startDate", ""),
    ),
    "endDate": Json::string(marketing_text(payload, "end_date", "endDate", "")),
    "state": Json::string(marketing_text(payload, "state", "", "planning")),
    "goal": Json::string(marketing_text(payload, "goal", "", "")),
    "remark": Json::string(marketing_text(payload, "remark", "", "")),
    "l3Code": Json::string(marketing_text(payload, "l3_code", "l3Code", "")),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(marketing_source_id(row)),
    "aggregate_type": Json::string("marketing_campaign"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn marketing_placement_item(
  row : SourceRow,
  campaign_names : Map[String, String],
) -> Json {
  let payload = row.payload
  let id = marketing_text(
    payload,
    "placement_guid",
    "placementGuid",
    row.record_id,
  )
  let campaign_id = marketing_text(payload, "campaign_guid", "campaignGuid", "")
  let source_kind = marketing_source_kind(row)
  Json::object({
    "placementGuid": Json::string(id),
    "placementCode": Json::string(
      marketing_text(payload, "placement_code", "placementCode", ""),
    ),
    "campaignGuid": Json::string(campaign_id),
    "campaignName": Json::string(campaign_names.get(campaign_id).unwrap_or("")),
    "channelGuid": Json::string(
      marketing_text(payload, "channel_guid", "channelGuid", ""),
    ),
    "channelName": Json::string(
      marketing_text(payload, "channel_name", "channelName", ""),
    ),
    "amount": Json::number(marketing_number(payload, "amount", "", 0.0)),
    "placeDate": Json::string(
      marketing_text(payload, "place_date", "placeDate", ""),
    ),
    "durationDays": Json::number(
      marketing_number(payload, "duration_days", "durationDays", 0.0),
    ),
    "state": Json::string(marketing_text(payload, "state", "", "placed")),
    "impressions": Json::number(
      marketing_number(payload, "impressions", "", 0.0),
    ),
    "clicks": Json::number(marketing_number(payload, "clicks", "", 0.0)),
    "leads": Json::number(marketing_number(payload, "leads", "", 0.0)),
    "l3Code": Json::string(marketing_text(payload, "l3_code", "l3Code", "")),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(marketing_source_id(row)),
    "aggregate_type": Json::string("marketing_placement"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn marketing_channel_item(
  row : SourceRow,
  placement_counts : Map[String, (Int, Double)],
) -> Json {
  let payload = row.payload
  let id = marketing_text(payload, "channel_guid", "channelGuid", row.record_id)
  let totals = placement_counts.get(id).unwrap_or((0, 0.0))
  let source_kind = marketing_source_kind(row)
  Json::object({
    "channelGuid": Json::string(id),
    "channelCode": Json::string(
      marketing_text(payload, "channel_code", "channelCode", ""),
    ),
    "name": Json::string(marketing_text(payload, "name", "", "")),
    "channelType": Json::string(
      marketing_text(payload, "channel_type", "channelType", ""),
    ),
    "contactPerson": Json::string(
      marketing_text(payload, "contact_person", "contactPerson", ""),
    ),
    "contactPhone": Json::string(
      marketing_text(payload, "contact_phone", "contactPhone", ""),
    ),
    "state": Json::string(marketing_text(payload, "state", "", "active")),
    "totalCost": Json::number(
      if totals.0 == 0 {
        marketing_number(payload, "total_cost", "totalCost", 0.0)
      } else {
        totals.1
      },
    ),
    "placementCount": Json::number(totals.0.to_double()),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(marketing_source_id(row)),
    "aggregate_type": Json::string("marketing_channel"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn marketing_material_item(row : SourceRow) -> Json {
  let payload = row.payload
  let id = marketing_text(
    payload,
    "material_guid",
    "materialGuid",
    row.record_id,
  )
  let source_kind = marketing_source_kind(row)
  Json::object({
    "materialGuid": Json::string(id),
    "materialCode": Json::string(
      marketing_text(payload, "material_code", "materialCode", ""),
    ),
    "projGuid": Json::string(
      marketing_text(payload, "proj_guid", "projGuid", ""),
    ),
    "name": Json::string(marketing_text(payload, "name", "", "")),
    "materialType": Json::string(
      marketing_text(payload, "material_type", "materialType", ""),
    ),
    "unitCost": Json::number(
      marketing_number(payload, "unit_cost", "unitCost", 0.0),
    ),
    "quantity": Json::number(marketing_number(payload, "quantity", "", 0.0)),
    "totalCost": Json::number(
      marketing_number(payload, "total_cost", "totalCost", 0.0),
    ),
    "usagePeriod": Json::string(
      marketing_text(payload, "usage_period", "usagePeriod", ""),
    ),
    "state": Json::string(marketing_text(payload, "state", "", "designing")),
    "remark": Json::string(marketing_text(payload, "remark", "", "")),
    "l3Code": Json::string(marketing_text(payload, "l3_code", "l3Code", "")),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(marketing_source_id(row)),
    "aggregate_type": Json::string("marketing_material"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn marketing_source_response(
  resource : String,
  proj_guid : String?,
  state : String?,
  campaign_guid : String?,
) -> Json raise CompanyServiceError {
  if !["campaign", "placement", "channel", "material"].contains(resource) {
    raise fail("unsupported marketing resource")
  }
  match proj_guid {
    Some(value) if !valid_identifier(value) => raise fail("invalid projGuid")
    _ => ()
  }
  match campaign_guid {
    Some(value) if !valid_identifier(value) =>
      raise fail("invalid campaignGuid")
    _ => ()
  }
  match state {
    Some(value) if value.length() > 64 => raise fail("invalid state")
    _ => ()
  }
  let campaign_raw = raw_source_rows("mkt_campaign", 500)
  let placement_raw = raw_source_rows("mkt_placement", 500)
  let channel_raw = raw_source_rows("mkt_channel", 500)
  let material_raw = raw_source_rows("mkt_material", 500)
  let campaign_commands = marketing_command_rows("campaign", false)
  let placement_commands = marketing_command_rows("placement", false)
  let channel_commands = marketing_command_rows("channel", false)
  let material_commands = marketing_command_rows("material", false)
  let coverage = Json::object({
    "mkt_campaign": Json::number(campaign_raw.length().to_double()),
    "mkt_placement": Json::number(placement_raw.length().to_double()),
    "mkt_channel": Json::number(channel_raw.length().to_double()),
    "mkt_material": Json::number(material_raw.length().to_double()),
  })
  let campaign_rows = campaign_raw + campaign_commands
  let placement_rows = placement_raw + placement_commands
  let channel_rows = channel_raw + channel_commands
  let material_rows = material_raw + material_commands
  let result : Array[Json] = []
  if resource == "campaign" {
    for row in campaign_rows {
      let item = marketing_campaign_item(row)
      let project = json_text(item, "projGuid", "")
      let current_state = json_text(item, "state", "")
      if (proj_guid is None || project == proj_guid.unwrap()) &&
        (state is None || current_state == state.unwrap()) &&
        current_state != "deleted" {
        result.push(item)
      }
    }
    result.sort_by(fn(left, right) {
      let order = json_text(right, "startDate", "").lexical_compare(
        json_text(left, "startDate", ""),
      )
      if order == 0 {
        json_text(right, "campaignCode", "").lexical_compare(
          json_text(left, "campaignCode", ""),
        )
      } else {
        order
      }
    })
  } else if resource == "placement" {
    let campaign_names : Map[String, String] = {}
    for row in campaign_rows {
      let item = marketing_campaign_item(row)
      let id = json_text(item, "campaignGuid", "")
      if json_text(item, "state", "") != "deleted" {
        campaign_names[id] = json_text(item, "name", "")
      }
    }
    for row in placement_rows {
      let item = marketing_placement_item(row, campaign_names)
      let current_campaign = json_text(item, "campaignGuid", "")
      if (campaign_guid is None || current_campaign == campaign_guid.unwrap()) &&
        json_text(item, "state", "") != "deleted" {
        result.push(item)
      }
    }
    result.sort_by(fn(left, right) {
      let order = json_text(right, "placeDate", "").lexical_compare(
        json_text(left, "placeDate", ""),
      )
      if order == 0 {
        json_text(right, "placementCode", "").lexical_compare(
          json_text(left, "placementCode", ""),
        )
      } else {
        order
      }
    })
  } else if resource == "channel" {
    let placement_counts : Map[String, (Int, Double)] = {}
    for row in placement_rows {
      let item = marketing_placement_item(row, {})
      if json_text(item, "state", "") != "deleted" {
        let id = json_text(item, "channelGuid", "")
        if !id.is_empty() {
          let current = placement_counts.get(id).unwrap_or((0, 0.0))
          placement_counts[id] = (
            current.0 + 1,
            current.1 + json_number(item, "amount", 0.0),
          )
        }
      }
    }
    for row in channel_rows {
      let item = marketing_channel_item(row, placement_counts)
      if json_text(item, "state", "") != "deleted" {
        result.push(item)
      }
    }
    result.sort_by(fn(left, right) {
      let order = json_number(right, "totalCost", 0.0).compare(
        json_number(left, "totalCost", 0.0),
      )
      if order == 0 {
        json_text(right, "channelCode", "").lexical_compare(
          json_text(left, "channelCode", ""),
        )
      } else {
        order
      }
    })
  } else {
    for row in material_rows {
      let item = marketing_material_item(row)
      let project = json_text(item, "projGuid", "")
      if (proj_guid is None || project == proj_guid.unwrap()) &&
        json_text(item, "state", "") != "deleted" {
        result.push(item)
      }
    }
    result.sort_by(fn(left, right) {
      let order = json_text(right, "materialCode", "").lexical_compare(
        json_text(left, "materialCode", ""),
      )
      if order == 0 {
        json_text(right, "materialGuid", "").lexical_compare(
          json_text(left, "materialGuid", ""),
        )
      } else {
        order
      }
    })
  }
  match marketing_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid marketing metadata")
  }
}

///|
fn marketing_required_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => raise reject(422, primary + " is required")
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if value.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn marketing_optional_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => ""
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn marketing_nonnegative_int(
  body : Json,
  primary : String,
  fallback : String,
) -> Int raise CompanyServiceError {
  match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => 0
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(String(text)) => {
      let parsed = parse_number(text.trim().to_owned())
      if parsed < 0.0 || parsed != parsed.to_int().to_double() {
        raise reject(422, primary + " must be a non-negative integer")
      }
      parsed.to_int()
    }
    _ => raise reject(422, primary + " must be a non-negative integer")
  }
}

///|
fn marketing_amount(
  body : Json,
  primary : String,
  fallback : String,
  positive : Bool,
) -> (String, Int) raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => raise reject(422, primary + " is required")
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    _ => raise reject(422, primary + " must be a decimal amount")
  }
  if value != value || value < 0.0 || (positive && value == 0.0) {
    raise reject(422, primary + " must be a non-negative decimal amount")
  }
  let minor = (value * 100.0 + 0.5).to_int()
  if positive && minor == 0 {
    raise reject(422, primary + " must be positive")
  }
  (invoice_minor_text(minor), minor)
}

///|
fn marketing_authority(
  body : Json,
  actor_id : String,
  principal_id : String,
  scope : String,
  capability : String,
  amount_minor : Int,
) -> Json raise CompanyServiceError {
  let grant = match json_field(body, "authority") {
    Some(Object(_)) => json_field(body, "authority").unwrap()
    _ => raise reject(403, "active marketing authority grant is required")
  }
  if !json_bool(grant, "active", false) {
    raise reject(403, "active marketing authority grant is required")
  }
  if json_text(grant, "principal_id", "") != principal_id {
    raise reject(403, "marketing authority principal does not match")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(403, "marketing authority actor does not match signed actor")
  }
  if json_text(grant, "scope", "") != scope {
    raise reject(403, "marketing authority scope does not match")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "marketing authority must allow " + capability)
  }
  let max_amount = match json_field(grant, "max_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(String(text)) => parse_decimal(text.trim().to_owned())
    _ => raise reject(403, "marketing authority max_amount_minor is required")
  }
  if max_amount < amount_minor {
    raise reject(403, "marketing authority amount is exceeded")
  }
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string(principal_id),
    "actor_id": Json::string(actor_id),
    "capability": Json::string(capability),
    "scope": Json::string(scope),
    "max_amount_minor": Json::number(max_amount.to_double()),
  })
}

///|
fn marketing_generated_id(prefix : String, idempotency_key : String) -> String {
  let suffix = if idempotency_key.length() > 110 {
    idempotency_key[0:110].to_owned()
  } else {
    idempotency_key
  }
  prefix + "-" + suffix
}

///|
fn marketing_create_request(
  resource : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json) raise CompanyServiceError {
  let principal_id = marketing_required_text(body, "principal_id", "", true)
  let scope = marketing_required_text(body, "scope", "", true)
  if resource == "campaign" {
    let id_value = marketing_optional_text(
      body, "campaignGuid", "campaign_guid", true,
    )
    let id = if id_value.is_empty() {
      marketing_generated_id("CAMP", idempotency_key)
    } else {
      id_value
    }
    let (_, budget_minor) = marketing_amount(body, "budget", "", false)
    let authority = marketing_authority(
      body, actor_id, principal_id, scope, "marketing:campaign:create", budget_minor,
    )
    (
      id,
      Json::object({
        "campaign_guid": Json::string(id),
        "campaign_code": Json::string(
          marketing_default(
            marketing_optional_text(
              body, "campaignCode", "campaign_code", false,
            ),
            marketing_generated_id("CAMP", idempotency_key),
          ),
        ),
        "proj_guid": Json::string(
          marketing_required_text(body, "projGuid", "proj_guid", true),
        ),
        "bu_guid": Json::string(
          marketing_optional_text(body, "buGuid", "bu_guid", true),
        ),
        "name": Json::string(marketing_required_text(body, "name", "", false)),
        "campaign_type": Json::string(
          marketing_default(
            marketing_optional_text(
              body, "campaignType", "campaign_type", false,
            ),
            "推广活动",
          ),
        ),
        "budget": Json::string(invoice_minor_text(budget_minor)),
        "budget_minor": Json::number(budget_minor.to_double()),
        "actual_cost": Json::string("0.00"),
        "actual_cost_minor": Json::number(0.0),
        "start_date": Json::string(
          marketing_default(
            marketing_optional_text(body, "startDate", "start_date", false),
            "2026-01-01",
          ),
        ),
        "end_date": Json::string(
          marketing_optional_text(body, "endDate", "end_date", false),
        ),
        "goal": Json::string(marketing_optional_text(body, "goal", "", false)),
        "remark": Json::string(
          marketing_optional_text(body, "remark", "", false),
        ),
        "l3_code": Json::string(
          marketing_default(
            marketing_optional_text(body, "l3Code", "l3_code", true),
            "R19.02.03",
          ),
        ),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "actor_id": Json::string(actor_id),
        "state": Json::string("planning"),
        "authority": authority,
        "command_type": Json::string("create"),
      }),
    )
  } else if resource == "placement" {
    let id_value = marketing_optional_text(
      body, "placementGuid", "placement_guid", true,
    )
    let id = if id_value.is_empty() {
      marketing_generated_id("PLAC", idempotency_key)
    } else {
      id_value
    }
    let (_, amount_minor) = marketing_amount(body, "amount", "", false)
    let authority = marketing_authority(
      body, actor_id, principal_id, scope, "marketing:placement:create", amount_minor,
    )
    (
      id,
      Json::object({
        "placement_guid": Json::string(id),
        "placement_code": Json::string(
          marketing_default(
            marketing_optional_text(
              body, "placementCode", "placement_code", false,
            ),
            marketing_generated_id("PLAC", idempotency_key),
          ),
        ),
        "campaign_guid": Json::string(
          marketing_optional_text(body, "campaignGuid", "campaign_guid", true),
        ),
        "channel_guid": Json::string(
          marketing_optional_text(body, "channelGuid", "channel_guid", true),
        ),
        "channel_name": Json::string(
          marketing_required_text(body, "channelName", "channel_name", false),
        ),
        "amount": Json::string(invoice_minor_text(amount_minor)),
        "amount_minor": Json::number(amount_minor.to_double()),
        "place_date": Json::string(
          marketing_default(
            marketing_optional_text(body, "placeDate", "place_date", false),
            "2026-01-01",
          ),
        ),
        "duration_days": Json::number(
          marketing_nonnegative_int(body, "durationDays", "duration_days").to_double(),
        ),
        "impressions": Json::number(0.0),
        "clicks": Json::number(0.0),
        "leads": Json::number(0.0),
        "state": Json::string("placed"),
        "remark": Json::string(
          marketing_optional_text(body, "remark", "", false),
        ),
        "l3_code": Json::string(
          marketing_default(
            marketing_optional_text(body, "l3Code", "l3_code", true),
            "R19.02.02",
          ),
        ),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "actor_id": Json::string(actor_id),
        "authority": authority,
        "command_type": Json::string("create"),
      }),
    )
  } else if resource == "channel" {
    let id_value = marketing_optional_text(
      body, "channelGuid", "channel_guid", true,
    )
    let id = if id_value.is_empty() {
      marketing_generated_id("CH", idempotency_key)
    } else {
      id_value
    }
    let authority = marketing_authority(
      body, actor_id, principal_id, scope, "marketing:channel:create", 0,
    )
    (
      id,
      Json::object({
        "channel_guid": Json::string(id),
        "channel_code": Json::string(
          marketing_default(
            marketing_optional_text(body, "channelCode", "channel_code", false),
            marketing_generated_id("CH", idempotency_key),
          ),
        ),
        "name": Json::string(marketing_required_text(body, "name", "", false)),
        "channel_type": Json::string(
          marketing_default(
            marketing_optional_text(body, "channelType", "channel_type", false),
            "线上",
          ),
        ),
        "contact_person": Json::string(
          marketing_optional_text(
            body, "contactPerson", "contact_person", false,
          ),
        ),
        "contact_phone": Json::string(
          marketing_optional_text(body, "contactPhone", "contact_phone", false),
        ),
        "state": Json::string("active"),
        "remark": Json::string(
          marketing_optional_text(body, "remark", "", false),
        ),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "actor_id": Json::string(actor_id),
        "authority": authority,
        "command_type": Json::string("create"),
      }),
    )
  } else if resource == "material" {
    let id_value = marketing_optional_text(
      body, "materialGuid", "material_guid", true,
    )
    let id = if id_value.is_empty() {
      marketing_generated_id("MAT", idempotency_key)
    } else {
      id_value
    }
    let (_, unit_cost_minor) = marketing_amount(
      body, "unitCost", "unit_cost", false,
    )
    let quantity = marketing_nonnegative_int(body, "quantity", "")
    let total_minor = unit_cost_minor * quantity
    let authority = marketing_authority(
      body, actor_id, principal_id, scope, "marketing:material:create", total_minor,
    )
    (
      id,
      Json::object({
        "material_guid": Json::string(id),
        "material_code": Json::string(
          marketing_default(
            marketing_optional_text(
              body, "materialCode", "material_code", false,
            ),
            marketing_generated_id("MAT", idempotency_key),
          ),
        ),
        "proj_guid": Json::string(
          marketing_optional_text(body, "projGuid", "proj_guid", true),
        ),
        "name": Json::string(marketing_required_text(body, "name", "", false)),
        "material_type": Json::string(
          marketing_default(
            marketing_optional_text(
              body, "materialType", "material_type", false,
            ),
            "现场包装",
          ),
        ),
        "unit_cost": Json::string(invoice_minor_text(unit_cost_minor)),
        "unit_cost_minor": Json::number(unit_cost_minor.to_double()),
        "quantity": Json::number(quantity.to_double()),
        "total_cost": Json::string(invoice_minor_text(total_minor)),
        "total_cost_minor": Json::number(total_minor.to_double()),
        "usage_period": Json::string(
          marketing_optional_text(body, "usagePeriod", "usage_period", false),
        ),
        "state": Json::string("designing"),
        "remark": Json::string(
          marketing_optional_text(body, "remark", "", false),
        ),
        "l3_code": Json::string(
          marketing_default(
            marketing_optional_text(body, "l3Code", "l3_code", true),
            "R19.02.07",
          ),
        ),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "actor_id": Json::string(actor_id),
        "authority": authority,
        "command_type": Json::string("create"),
      }),
    )
  } else {
    raise reject(404, "unsupported marketing resource")
  }
}

///|
fn marketing_command_request(
  resource : String,
  command_type : String,
  resource_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json) raise CompanyServiceError {
  if command_type == "create" {
    return marketing_create_request(resource, body, actor_id, idempotency_key)
  }
  let id = match resource_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "marketing resource id is required")
  }
  let principal_id = marketing_required_text(body, "principal_id", "", true)
  let scope = marketing_required_text(body, "scope", "", true)
  let capability = "marketing:" + resource + ":" + command_type
  let mut amount_minor = 0
  let changes : Map[String, Json] = {}
  if command_type == "update" && resource == "campaign" {
    let mut has_change = false
    let add_text = fn(
      key : String,
      primary : String,
      fallback : String,
    ) raise CompanyServiceError {
      match marketing_lookup(body, primary, fallback) {
        None | Some(Null) => ()
        Some(String(item)) => {
          changes.set(key, Json::string(item.trim().to_owned()))
          has_change = true
        }
        _ => raise reject(422, primary + " must be text")
      }
    }
    add_text("name", "name", "")
    add_text("campaign_type", "campaignType", "campaign_type")
    add_text("start_date", "startDate", "start_date")
    add_text("end_date", "endDate", "end_date")
    add_text("goal", "goal", "")
    add_text("remark", "remark", "")
    add_text("state", "state", "")
    match marketing_lookup(body, "budget", "") {
      Some(_) => {
        let (_, value) = marketing_amount(body, "budget", "", false)
        changes.set("budget", Json::string(invoice_minor_text(value)))
        changes.set("budget_minor", Json::number(value.to_double()))
        amount_minor = if value > amount_minor { value } else { amount_minor }
        has_change = true
      }
      None => ()
    }
    match marketing_lookup(body, "actualCost", "actual_cost") {
      Some(_) => {
        let (_, value) = marketing_amount(
          body, "actualCost", "actual_cost", false,
        )
        changes.set("actual_cost", Json::string(invoice_minor_text(value)))
        changes.set("actual_cost_minor", Json::number(value.to_double()))
        amount_minor = if value > amount_minor { value } else { amount_minor }
        has_change = true
      }
      None => ()
    }
    if !has_change {
      raise reject(422, "update requires at least one mutable field")
    }
  } else if command_type == "effect" && resource == "placement" {
    let impressions = marketing_nonnegative_int(body, "impressions", "")
    let clicks = marketing_nonnegative_int(body, "clicks", "")
    let leads = marketing_nonnegative_int(body, "leads", "")
    let state = marketing_default(
      marketing_optional_text(body, "state", "", false),
      "completed",
    )
    if state != "placed" && state != "completed" {
      raise reject(422, "effect state is invalid")
    }
    changes.set("impressions", Json::number(impressions.to_double()))
    changes.set("clicks", Json::number(clicks.to_double()))
    changes.set("leads", Json::number(leads.to_double()))
    changes.set("state", Json::string(state))
  } else if command_type != "delete" {
    raise reject(404, "unsupported marketing command")
  }
  let authority = marketing_authority(
    body, actor_id, principal_id, scope, capability, amount_minor,
  )
  (
    id,
    Json::object({
      "aggregate_id": Json::string(id),
      "principal_id": Json::string(principal_id),
      "scope": Json::string(scope),
      "actor_id": Json::string(actor_id),
      "authority": authority,
      "command_type": Json::string(command_type),
      "changes": Json::object(changes),
    }),
  )
}

///|
async fn marketing_latest_payload(
  resource : String,
  resource_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let aggregate_type = marketing_command_aggregate(resource)
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') " +
    "FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(resource_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid marketing projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn marketing_imported_exists(
  resource : String,
  resource_id : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows(marketing_source_table(resource), 500)
  let key = match resource {
    "campaign" => "campaign_guid"
    "placement" => "placement_guid"
    "channel" => "channel_guid"
    _ => "material_guid"
  }
  let alternate_key = match resource {
    "campaign" => "campaignGuid"
    "placement" => "placementGuid"
    "channel" => "channelGuid"
    _ => "materialGuid"
  }
  for row in rows {
    if marketing_text(row.payload, key, alternate_key, row.record_id) ==
      resource_id {
      return true
    }
  }
  false
}

///|
async fn marketing_command(
  resource : String,
  command_type : String,
  resource_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["campaign", "placement", "channel", "material"].contains(resource) {
    raise reject(404, "unsupported marketing resource")
  }
  if !["create", "update", "effect", "delete"].contains(command_type) {
    raise reject(404, "unsupported marketing command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = marketing_command_request(
    resource, command_type, resource_id, body, actor_id, idempotency_key,
  )
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let response = Json::object({
        "command": existing,
        "idempotent_replay": Json::boolean(true),
      })
      return match response {
        Object(fields) => {
          fields.set(
            resource,
            json_field(existing, "result").unwrap_or(Json::null()),
          )
          (200, response)
        }
        _ => raise fail("invalid marketing replay response")
      }
    }
    None => ()
  }
  let current = marketing_latest_payload(resource, id)
  let imported = marketing_imported_exists(resource, id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "marketing resource already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported marketing resource is read-only; create a local resource first",
          )
        }
        raise reject(404, "marketing resource not found")
      }
      Some((payload, _)) => {
        if json_text(payload, "source_kind", "") != "command" {
          raise reject(
            409, "imported marketing resource is read-only; create a local resource first",
          )
        }
        if json_text(payload, "principal_id", "") !=
          json_text(request, "principal_id", "") ||
          json_text(payload, "scope", "") != json_text(request, "scope", "") {
          raise reject(403, "marketing principal or scope does not match")
        }
        if json_text(payload, "state", "") == "deleted" {
          raise reject(409, "marketing resource is already deleted")
        }
      }
    }
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    json_text(request, "state", "planning")
  } else if command_type == "delete" {
    "deleted"
  } else {
    match json_field(request, "changes") {
      Some(changes) =>
        json_text(
          changes,
          "state",
          json_text(current_payload, "state", "planning"),
        )
      None => json_text(current_payload, "state", "planning")
    }
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "marketing:" +
    resource +
    ":" +
    command_type +
    ":" +
    idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "aggregate_id": Json::string(id),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("marketing"),
    "resource": Json::string(resource),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(marketing_command_aggregate(resource)),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let request_projection = "(" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'authority' - 'changes') || coalesce(" +
    @postgres.sql_literal(request_json) +
    "::jsonb->'changes', '{}'::jsonb)"
  let next_payload_sql = if command_type == "create" {
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "delete" {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', 'deleted', " +
    "'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('source_kind', 'command', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("marketing." + resource + "." + command_type),
    "aggregate_type": Json::string(marketing_command_aggregate(resource)),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(marketing_command_aggregate(resource)) +
    ", " +
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
  let response = Json::object({
    "command": command_payload,
    "idempotent_replay": Json::boolean(false),
  })
  match response {
    Object(fields) => {
      fields.set(resource, result)
      (if command_type == "create" { 201 } else { 200 }, response)
    }
    _ => raise fail("invalid marketing response")
  }
}

///|
fn fund_source_metadata(coverage : Json) -> Json {
  let missing : Array[Json] = []
  for table in ["ep_project", "fund_dispatch", "fund_plan", "mu_business_unit"] {
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
async fn fund_command_rows(
  resource : String,
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
  let aggregate_type = if resource == "plan" {
    "fund_plan"
  } else if resource == "dispatch" {
    "fund_dispatch"
  } else {
    raise fail("unsupported fund resource")
  }
  let deleted_clause = if include_deleted {
    ""
  } else {
    " WHERE coalesce(payload->>'state', '') <> 'deleted'"
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex') FROM (" +
    "SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, source_event_id " +
    "FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest" +
    deleted_clause +
    " ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid fund projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[2]),
            payload,
          })
        _ => raise fail("fund projection payload is not an object")
      }
    }
  }
  result
}

///|
fn fund_text(
  value : Json,
  primary : String,
  fallback : String,
  default : String,
) -> String {
  marketing_text(value, primary, fallback, default)
}

///|
fn fund_number(
  value : Json,
  primary : String,
  fallback : String,
  default : Double,
) -> Double {
  marketing_number(value, primary, fallback, default)
}

///|
fn fund_source_id(row : SourceRow) -> String {
  if row.source_id.is_empty() {
    row.record_id
  } else {
    row.source_id
  }
}

///|
fn fund_source_kind(row : SourceRow) -> String {
  let value = fund_text(row.payload, "source_kind", "sourceKind", "")
  if value.is_empty() {
    "imported"
  } else {
    value
  }
}

///|
fn fund_plan_item(row : SourceRow, project_names : Map[String, String]) -> Json {
  let payload = row.payload
  let id = fund_text(payload, "plan_guid", "planGuid", row.record_id)
  let project_id = fund_text(payload, "proj_guid", "projGuid", "")
  let source_kind = fund_source_kind(row)
  Json::object({
    "plan_guid": Json::string(id),
    "plan_code": Json::string(fund_text(payload, "plan_code", "planCode", "")),
    "proj_guid": Json::string(project_id),
    "proj_name": Json::string(project_names.get(project_id).unwrap_or("")),
    "bu_guid": Json::string(fund_text(payload, "bu_guid", "buGuid", "")),
    "plan_period": Json::string(fund_text(payload, "plan_period", "period", "")),
    "direction": Json::string(fund_text(payload, "direction", "", "")),
    "category": Json::string(fund_text(payload, "category", "", "")),
    "r_code": Json::string(fund_text(payload, "r_code", "rCode", "")),
    "plan_amount": Json::number(
      fund_number(payload, "plan_amount", "planAmount", 0.0),
    ),
    "actual_amount": Json::number(
      fund_number(payload, "actual_amount", "actualAmount", 0.0),
    ),
    "remark": Json::string(fund_text(payload, "remark", "", "")),
    "created_at": Json::string(
      fund_text(payload, "created_at", "createdAt", ""),
    ),
    "state": Json::string(fund_text(payload, "state", "", "source_read_only")),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(fund_source_id(row)),
    "aggregate_type": Json::string("fund_plan"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn fund_dispatch_item(row : SourceRow) -> Json {
  let payload = row.payload
  let id = fund_text(payload, "dispatch_guid", "dispatchGuid", row.record_id)
  let source_kind = fund_source_kind(row)
  Json::object({
    "dispatch_guid": Json::string(id),
    "dispatch_code": Json::string(
      fund_text(payload, "dispatch_code", "dispatchCode", ""),
    ),
    "proj_guid": Json::string(fund_text(payload, "proj_guid", "projGuid", "")),
    "bu_guid": Json::string(fund_text(payload, "bu_guid", "buGuid", "")),
    "from_proj": Json::string(
      fund_text(payload, "from_proj", "fromProjectId", ""),
    ),
    "to_proj": Json::string(fund_text(payload, "to_proj", "toProjectId", "")),
    "amount": Json::number(fund_number(payload, "amount", "amount_minor", 0.0)),
    "dispatch_date": Json::string(
      fund_text(payload, "dispatch_date", "dispatchDate", ""),
    ),
    "reason": Json::string(fund_text(payload, "reason", "", "")),
    "state": Json::string(fund_text(payload, "state", "", "pending")),
    "created_at": Json::string(
      fund_text(payload, "created_at", "createdAt", ""),
    ),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(fund_source_id(row)),
    "aggregate_type": Json::string("fund_dispatch"),
    "aggregate_id": Json::string(id),
    "source_kind": Json::string(source_kind),
    "command_projection": Json::boolean(source_kind == "command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(source_kind == "command"),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn fund_source_response(
  resource : String,
  proj_guid : String?,
  period : String?,
  direction : String?,
) -> Json raise CompanyServiceError {
  if resource != "plans" && resource != "dispatches" {
    raise fail("unsupported fund source resource")
  }
  for value in [proj_guid, period, direction] {
    match value {
      Some(item) if item.is_empty() || item.length() > 128 =>
        raise fail("invalid fund filter")
      _ => ()
    }
  }
  match direction {
    Some(item) if item != "in" && item != "out" =>
      raise fail("direction must be in or out")
    _ => ()
  }
  let projects = raw_source_rows("ep_project", 500)
  let plans = raw_source_rows("fund_plan", 500)
  let dispatches = raw_source_rows("fund_dispatch", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = Json::object({
    "ep_project": Json::number(projects.length().to_double()),
    "fund_dispatch": Json::number(dispatches.length().to_double()),
    "fund_plan": Json::number(plans.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
  })
  let project_names : Map[String, String] = {}
  for row in projects {
    let id = fund_text(row.payload, "proj_guid", "projGuid", row.record_id)
    project_names[id] = fund_text(row.payload, "proj_name", "projName", "")
  }
  let result : Array[Json] = []
  if resource == "plans" {
    let rows = plans + fund_command_rows("plan", false)
    for row in rows {
      let item = fund_plan_item(row, project_names)
      if (
          proj_guid is None ||
          json_text(item, "proj_guid", "") == proj_guid.unwrap()
        ) &&
        (
          period is None ||
          json_text(item, "plan_period", "") == period.unwrap()
        ) &&
        (
          direction is None ||
          json_text(item, "direction", "") == direction.unwrap()
        ) &&
        json_text(item, "state", "") != "deleted" {
        result.push(item)
      }
    }
    result.sort_by(fn(left, right) {
      let period_order = json_text(left, "plan_period", "").lexical_compare(
        json_text(right, "plan_period", ""),
      )
      if period_order == 0 {
        json_text(left, "direction", "").lexical_compare(
          json_text(right, "direction", ""),
        )
      } else {
        period_order
      }
    })
  } else {
    let rows = dispatches + fund_command_rows("dispatch", false)
    for row in rows {
      result.push(fund_dispatch_item(row))
    }
    result.sort_by(fn(left, right) {
      json_text(right, "created_at", "").lexical_compare(
        json_text(left, "created_at", ""),
      )
    })
  }
  match fund_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::array(result))
      Json::object(metadata)
    }
    _ => raise fail("invalid fund source metadata")
  }
}

///|
async fn fund_gap_response(
  proj_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(proj_guid) {
    raise fail("invalid proj_guid")
  }
  let projects = raw_source_rows("ep_project", 500)
  let plans = raw_source_rows("fund_plan", 500)
  let dispatches = raw_source_rows("fund_dispatch", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = Json::object({
    "ep_project": Json::number(projects.length().to_double()),
    "fund_dispatch": Json::number(dispatches.length().to_double()),
    "fund_plan": Json::number(plans.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
  })
  let rows = plans + fund_command_rows("plan", false)
  let periods : Map[String, (Double, Double, Double, Double)] = {}
  for row in rows {
    let payload = row.payload
    if json_text(payload, "proj_guid", json_text(payload, "projGuid", "")) ==
      proj_guid {
      let key = fund_text(payload, "plan_period", "period", "")
      let current = periods.get(key).unwrap_or((0.0, 0.0, 0.0, 0.0))
      let amount = fund_number(payload, "plan_amount", "planAmount", 0.0)
      let actual = fund_number(payload, "actual_amount", "actualAmount", 0.0)
      let direction = fund_text(payload, "direction", "", "")
      periods[key] = if direction == "in" {
        (current.0 + amount, current.1 + actual, current.2, current.3)
      } else if direction == "out" {
        (current.0, current.1, current.2 + amount, current.3 + actual)
      } else {
        current
      }
    }
  }
  let keys : Array[String] = []
  for key in periods.keys() {
    keys.push(key)
  }
  keys.sort()
  let series : Array[Json] = []
  let mut cumulative = 0.0
  for key in keys {
    let values = periods.get(key).unwrap()
    let net = values.0 - values.2
    cumulative += net
    series.push(
      Json::object({
        "period": Json::string(key),
        "planIn": Json::number(round_places(values.0, 2)),
        "actualIn": Json::number(round_places(values.1, 2)),
        "planOut": Json::number(round_places(values.2, 2)),
        "actualOut": Json::number(round_places(values.3, 2)),
        "net": Json::number(round_places(net, 2)),
        "cumNet": Json::number(round_places(cumulative, 2)),
        "gap": Json::number(
          round_places(if cumulative < 0.0 { -cumulative } else { 0.0 }, 2),
        ),
      }),
    )
  }
  match fund_source_metadata(coverage) {
    Object(metadata) => {
      metadata.set("success", Json::boolean(true))
      metadata.set("code", Json::number(0))
      metadata.set("data", Json::object({ "series": Json::array(series) }))
      Json::object(metadata)
    }
    _ => raise fail("invalid fund gap metadata")
  }
}

///|
fn fund_required_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => raise reject(422, primary + " is required")
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if value.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn fund_optional_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => ""
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn fund_amount_minor(
  body : Json,
  primary : String,
  fallback : String,
) -> Int raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => raise reject(422, primary + " is required")
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    _ => raise reject(422, primary + " must be a positive amount")
  }
  if value <= 0.0 || value != value {
    raise reject(422, primary + " must be a positive amount")
  }
  let minor = if primary.has_suffix("_minor") {
    if value != value.to_int().to_double() {
      raise reject(422, primary + " must be an integer amount in minor units")
    }
    value.to_int()
  } else {
    (value * 100.0 + 0.5).to_int()
  }
  if minor <= 0 {
    raise reject(422, primary + " must be a positive amount")
  }
  minor
}

///|
fn fund_authority(
  body : Json,
  actor_id : String,
  project_id : String,
  capability : String,
  amount_minor : Int,
) -> Json raise CompanyServiceError {
  let grant = match json_field(body, "authority") {
    Some(Object(_)) => json_field(body, "authority").unwrap()
    _ => raise reject(403, "authority grant is required")
  }
  if !json_bool(grant, "active", false) {
    raise reject(403, "authority grant is inactive")
  }
  let principal_id = json_text(grant, "principal_id", "")
  if !valid_identifier(principal_id) {
    raise reject(403, "authority grant principal_id is required")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(403, "authority grant actor does not match signed actor")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "authority grant must allow " + capability)
  }
  let expected_scope = "project:" + project_id
  if json_text(grant, "scope", "") != expected_scope {
    raise reject(403, "authority grant scope must be project-scoped")
  }
  let max_amount = match json_field(grant, "max_amount_minor") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    Some(String(text)) => parse_decimal(text.trim().to_owned())
    _ => raise reject(403, "authority grant max_amount_minor is required")
  }
  if max_amount < amount_minor {
    raise reject(403, "authority grant amount is exceeded")
  }
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string(principal_id),
    "actor_id": Json::string(actor_id),
    "capability": Json::string(capability),
    "scope": Json::string(expected_scope),
    "max_amount_minor": Json::number(max_amount.to_double()),
  })
}

///|
async fn fund_project_exists(
  project_id : String,
) -> Bool raise CompanyServiceError {
  let projects = raw_source_rows("ep_project", 500)
  for row in projects {
    if fund_text(row.payload, "proj_guid", "projGuid", row.record_id) ==
      project_id {
      return true
    }
  }
  false
}

///|
async fn fund_latest_payload(
  resource : String,
  resource_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let aggregate_type = if resource == "plan" {
    "fund_plan"
  } else {
    "fund_dispatch"
  }
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') " +
    "FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(resource_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid fund projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn fund_imported_exists(
  resource : String,
  resource_id : String,
) -> Bool raise CompanyServiceError {
  let table = if resource == "plan" { "fund_plan" } else { "fund_dispatch" }
  let key = if resource == "plan" { "plan_guid" } else { "dispatch_guid" }
  let alias_key = if resource == "plan" { "planGuid" } else { "dispatchGuid" }
  for row in raw_source_rows(table, 500) {
    if fund_text(row.payload, key, alias_key, row.record_id) == resource_id {
      return true
    }
  }
  false
}

///|
async fn fund_command_request(
  resource : String,
  command_type : String,
  resource_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
  current : Json?,
) -> (String, Json) raise CompanyServiceError {
  if resource == "plan" && command_type == "create" {
    let requested = fund_optional_text(body, "plan_id", "plan_guid", true)
    let id = if requested.is_empty() {
      marketing_generated_id("FP", idempotency_key)
    } else {
      requested
    }
    let project_id = fund_required_text(body, "project_id", "proj_guid", true)
    if !fund_project_exists(project_id) {
      raise reject(409, "fund plan requires an imported project identity")
    }
    let amount_minor = fund_amount_minor(body, "plan_amount_minor", "amount")
    let authority = fund_authority(
      body, actor_id, project_id, "fund:plan:create", amount_minor,
    )
    let direction = fund_required_text(body, "direction", "", false)
    if direction != "in" && direction != "out" {
      raise reject(422, "direction must be in or out")
    }
    let plan_period = fund_required_text(body, "plan_period", "period", false)
    let plan_code = marketing_default(
      fund_optional_text(body, "plan_code", "planCode", false),
      marketing_generated_id("FP", idempotency_key),
    )
    if !valid_identifier(plan_code) {
      raise reject(422, "plan_code contains unsupported characters")
    }
    (
      id,
      Json::object({
        "command_type": Json::string("create"),
        "plan_id": Json::string(id),
        "plan_guid": Json::string(id),
        "plan_code": Json::string(plan_code),
        "proj_guid": Json::string(project_id),
        "plan_period": Json::string(plan_period),
        "direction": Json::string(direction),
        "category": Json::string(
          fund_optional_text(body, "category", "", false),
        ),
        "r_code": Json::string(
          fund_optional_text(body, "r_code", "rCode", true),
        ),
        "plan_amount": Json::string(invoice_minor_text(amount_minor)),
        "plan_amount_minor": Json::number(amount_minor.to_double()),
        "actual_amount": Json::string("0.00"),
        "actual_amount_minor": Json::number(0.0),
        "remark": Json::string(fund_optional_text(body, "remark", "", false)),
        "created_by": Json::string(actor_id),
        "authority": authority,
      }),
    )
  } else if resource == "dispatch" && command_type == "create" {
    let requested = fund_optional_text(
      body, "dispatch_id", "dispatch_guid", true,
    )
    let id = if requested.is_empty() {
      marketing_generated_id("FD", idempotency_key)
    } else {
      requested
    }
    let project_id = fund_required_text(body, "project_id", "proj_guid", true)
    if !fund_project_exists(project_id) {
      raise reject(409, "fund dispatch requires an imported project identity")
    }
    let amount_minor = fund_amount_minor(body, "amount_minor", "amount")
    let authority = fund_authority(
      body, actor_id, project_id, "fund:dispatch:create", amount_minor,
    )
    let dispatch_code = marketing_default(
      fund_optional_text(body, "dispatch_code", "dispatchCode", false),
      marketing_generated_id("FD", idempotency_key),
    )
    if !valid_identifier(dispatch_code) {
      raise reject(422, "dispatch_code contains unsupported characters")
    }
    (
      id,
      Json::object({
        "command_type": Json::string("create"),
        "dispatch_id": Json::string(id),
        "dispatch_guid": Json::string(id),
        "dispatch_code": Json::string(dispatch_code),
        "proj_guid": Json::string(project_id),
        "from_proj": Json::string(
          fund_optional_text(body, "from_proj", "from_project_id", true),
        ),
        "to_proj": Json::string(
          fund_optional_text(body, "to_proj", "to_project_id", true),
        ),
        "amount": Json::string(invoice_minor_text(amount_minor)),
        "amount_minor": Json::number(amount_minor.to_double()),
        "reason": Json::string(fund_optional_text(body, "reason", "", false)),
        "dispatch_date": Json::string(
          marketing_default(
            fund_optional_text(body, "dispatch_date", "dispatchDate", false),
            "2026-01-01",
          ),
        ),
        "created_by": Json::string(actor_id),
        "authority": authority,
      }),
    )
  } else {
    let id = match resource_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, resource + "_id is required")
    }
    if resource == "plan" && command_type == "update" {
      let changes : Map[String, Json] = {}
      if marketing_lookup(body, "plan_amount_minor", "amount") is Some(_) {
        let amount_minor = fund_amount_minor(
          body, "plan_amount_minor", "amount",
        )
        changes.set(
          "plan_amount",
          Json::string(invoice_minor_text(amount_minor)),
        )
        changes.set("plan_amount_minor", Json::number(amount_minor.to_double()))
      }
      if json_field(body, "actual_amount_minor") is Some(_) {
        let amount_minor = fund_amount_minor(body, "actual_amount_minor", "")
        changes.set(
          "actual_amount",
          Json::string(invoice_minor_text(amount_minor)),
        )
        changes.set(
          "actual_amount_minor",
          Json::number(amount_minor.to_double()),
        )
      }
      if json_field(body, "remark") is Some(value) {
        match value {
          String(text) =>
            changes.set("remark", Json::string(text.trim().to_owned()))
          _ => raise reject(422, "remark must be text")
        }
      }
      if changes.is_empty() {
        raise reject(
          422, "update requires a plan amount, actual amount, or remark",
        )
      }
      (
        id,
        Json::object({
          "command_type": Json::string("update"),
          "plan_id": Json::string(id),
          "actor_id": Json::string(actor_id),
          "changes": Json::object(changes),
        }),
      )
    } else if resource == "plan" && command_type == "delete" {
      (
        id,
        Json::object({
          "command_type": Json::string("delete"),
          "plan_id": Json::string(id),
          "actor_id": Json::string(actor_id),
          "reason": Json::string(fund_optional_text(body, "reason", "", false)),
        }),
      )
    } else if resource == "dispatch" && command_type == "approve" {
      let current_payload = match current {
        Some(value) => value
        None => raise reject(404, "dispatch not found")
      }
      let project_id = fund_required_text(
        current_payload, "proj_guid", "projGuid", true,
      )
      let amount_minor = fund_amount_minor(
        current_payload, "amount_minor", "amount",
      )
      let authority = fund_authority(
        body, actor_id, project_id, "fund:dispatch:approve", amount_minor,
      )
      (
        id,
        Json::object({
          "command_type": Json::string("approve"),
          "dispatch_id": Json::string(id),
          "actor_id": Json::string(actor_id),
          "authority": authority,
        }),
      )
    } else {
      raise reject(404, "unsupported fund command")
    }
  }
}

///|
async fn fund_command(
  resource : String,
  command_type : String,
  resource_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["plan", "dispatch"].contains(resource) {
    raise reject(404, "unsupported fund resource")
  }
  if !["create", "update", "delete", "approve"].contains(command_type) {
    raise reject(404, "unsupported fund command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let current = match resource_id {
    Some(id) => fund_latest_payload(resource, id)
    None => None
  }
  let (id, request) = fund_command_request(
    resource,
    command_type,
    resource_id,
    body,
    actor_id,
    idempotency_key,
    match current {
      Some((payload, _)) => Some(payload)
      None => None
    },
  )
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored = json_field(existing, "request").unwrap_or(Json::null())
      if !json_equal(stored, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let response = Json::object({
        "command": existing,
        "idempotent_replay": Json::boolean(true),
      })
      return match response {
        Object(fields) => {
          fields.set(
            resource,
            json_field(existing, "result").unwrap_or(Json::null()),
          )
          (200, response)
        }
        _ => raise fail("invalid fund replay response")
      }
    }
    None => ()
  }
  let imported = fund_imported_exists(resource, id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "fund resource already exists")
    }
  } else {
    let current_payload = match current {
      Some((payload, _)) => payload
      None => {
        if imported {
          raise reject(
            409, "imported fund resource is read-only; create a local projection first",
          )
        }
        raise reject(404, "fund resource not found")
      }
    }
    if json_text(current_payload, "source_kind", "") != "command" {
      raise reject(409, "imported fund resource is read-only")
    }
    if command_type == "update" || command_type == "delete" {
      if json_text(current_payload, "created_by", "") != actor_id {
        raise reject(403, "only the fund-plan creator may change this plan")
      }
    }
    let state = json_text(current_payload, "state", "")
    if (
        resource == "plan" &&
        (command_type == "update" || command_type == "delete")
      ) &&
      state != "planned" &&
      state != "updated" {
      raise reject(409, "invalid fund plan state")
    }
    if resource == "dispatch" && command_type == "approve" && state != "pending" {
      raise reject(409, "invalid fund dispatch state")
    }
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    if resource == "plan" {
      "planned"
    } else {
      "pending"
    }
  } else if command_type == "approve" {
    "approved"
  } else if command_type == "delete" {
    "deleted"
  } else {
    "updated"
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "fund:" + resource + ":" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result_key = if resource == "plan" { "plan_id" } else { "dispatch_id" }
  let result = Json::object({
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  match result {
    Object(fields) => fields.set(result_key, Json::string(id))
    _ => ()
  }
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("fund"),
    "resource": Json::string(resource),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(
      if resource == "plan" {
        "fund_plan"
      } else {
        "fund_dispatch"
      },
    ),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let request_projection = "(" +
    @postgres.sql_literal(request_json) +
    "::jsonb - 'authority' - 'changes') || coalesce(" +
    @postgres.sql_literal(request_json) +
    "::jsonb->'changes', '{}'::jsonb)"
  let next_payload_sql = if command_type == "create" {
    request_projection +
    " || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "delete" {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('state', 'deleted', 'source_kind', 'command', 'deleted_at', " +
    @postgres.sql_literal(event_id) +
    ", 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || " +
    request_projection +
    " || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("fund." + resource + "." + command_type),
    "aggregate_type": Json::string(
      if resource == "plan" {
        "fund_plan"
      } else {
        "fund_dispatch"
      },
    ),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(next_state),
    "revision": Json::number(next_revision.to_double()),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(
      if resource == "plan" {
        "fund_plan"
      } else {
        "fund_dispatch"
      },
    ) +
    ", " +
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
  let response = Json::object({
    "command": command_payload,
    "idempotent_replay": Json::boolean(false),
  })
  match response {
    Object(fields) => {
      fields.set(resource, result)
      (if command_type == "create" { 201 } else { 200 }, response)
    }
    _ => raise fail("invalid fund response")
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
    ") ORDER BY aggregate_id), '[]'::jsonb)::text FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'supplier' ORDER BY aggregate_id, revision DESC) latest WHERE coalesce(payload->>'state', 'draft') <> 'voided'",
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
fn supplier_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = json_text(body, key, "").trim().to_owned()
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn supplier_optional_text(
  body : Json,
  key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => ()
    Some(String(value)) if value.trim().length() <= 256 =>
      request.set(key, Json::string(value.trim().to_owned()))
    Some(String(_)) => raise reject(422, key + " must be text")
    _ => raise reject(422, key + " must be text")
  }
}

///|
fn supplier_register_capital(
  body : Json,
  key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => ()
    Some(Number(number, ..)) =>
      request.set(key, Json::string(number.to_string()))
    Some(String(value)) =>
      request.set(key, Json::string(value.trim().to_owned()))
    _ => raise reject(422, key + " must be numeric")
  }
}

///|
fn supplier_enabled(
  body : Json,
  key : String,
  request : Map[String, Json],
) -> Unit raise CompanyServiceError {
  match json_field(body, key) {
    None | Some(Null) => ()
    Some(True) => request.set(key, Json::boolean(true))
    Some(False) => request.set(key, Json::boolean(false))
    _ => raise reject(422, key + " must be boolean")
  }
}

///|
fn supplier_create_request(
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string("create"))
  request.set(
    "supplier_id",
    Json::string(supplier_required_text(body, "supplier_id", true)),
  )
  request.set(
    "principal_id",
    Json::string(supplier_required_text(body, "principal_id", true)),
  )
  request.set(
    "scope",
    Json::string(supplier_required_text(body, "scope", true)),
  )
  request.set(
    "supplier_code",
    Json::string(supplier_required_text(body, "supplier_code", true)),
  )
  request.set("name", Json::string(supplier_required_text(body, "name", false)))
  request.set(
    "category_code",
    Json::string(supplier_required_text(body, "category_code", true)),
  )
  for
    key in [
      "short_name", "legal_person", "business_scope", "source", "contact_person",
      "contact_phone", "address",
    ] {
    supplier_optional_text(body, key, request)
  }
  supplier_register_capital(body, "register_capital", request)
  supplier_enabled(body, "enabled", request)
  request.set("actor_id", Json::string(actor_id))
  Json::object(request)
}

///|
fn supplier_source_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let provider_id_value = json_text(body, "providerGuid", "").trim().to_owned()
  let provider_id = if provider_id_value.is_empty() {
    "SUP-SRC-" + idempotency_key
  } else {
    provider_id_value
  }
  if !valid_identifier(provider_id) {
    raise reject(422, "providerGuid contains unsupported characters")
  }
  let provider_name = supplier_required_text(body, "providerName", false)
  let category_code = if json_text(body, "mainCategoryCode", "")
    .trim()
    .is_empty() {
    supplier_required_text(body, "category_code", true)
  } else {
    supplier_required_text(body, "mainCategoryCode", true)
  }
  let provider_code_value = json_text(body, "providerCode", "")
    .trim()
    .to_owned()
  let provider_code = if provider_code_value.is_empty() {
    "GYS-SRC-" + provider_id
  } else {
    provider_code_value
  }
  if !valid_identifier(provider_code) {
    raise reject(422, "providerCode contains unsupported characters")
  }
  let principal_id = if json_text(body, "principal_id", "").trim().is_empty() {
    actor_id
  } else {
    json_text(body, "principal_id", "").trim().to_owned()
  }
  let scope = if json_text(body, "scope", "").trim().is_empty() {
    "supplier:" + provider_id
  } else {
    json_text(body, "scope", "").trim().to_owned()
  }
  if !valid_identifier(principal_id) {
    raise reject(422, "principal_id contains unsupported characters")
  }
  if !valid_identifier(scope) {
    raise reject(422, "scope contains unsupported characters")
  }
  let canonical : Map[String, Json] = {}
  canonical.set("supplier_id", Json::string(provider_id))
  canonical.set("principal_id", Json::string(principal_id))
  canonical.set("scope", Json::string(scope))
  canonical.set("supplier_code", Json::string(provider_code))
  canonical.set("name", Json::string(provider_name))
  canonical.set("category_code", Json::string(category_code))
  for
    source_key in [
      "shortName", "legalPerson", "businessScope", "source", "contactPerson", "contactPhone",
      "address",
    ] {
    let target_key = if source_key == "shortName" {
      "short_name"
    } else if source_key == "legalPerson" {
      "legal_person"
    } else if source_key == "businessScope" {
      "business_scope"
    } else if source_key == "contactPerson" {
      "contact_person"
    } else if source_key == "contactPhone" {
      "contact_phone"
    } else {
      source_key
    }
    match json_field(body, source_key) {
      None => ()
      Some(String(value)) if value.trim().length() <= 256 =>
        canonical.set(target_key, Json::string(value.trim().to_owned()))
      Some(_) => raise reject(422, source_key + " must be text")
    }
  }
  match json_field(body, "registerCapital") {
    None => ()
    Some(Number(number, ..)) =>
      canonical.set("register_capital", Json::string(number.to_string()))
    Some(String(value)) =>
      canonical.set("register_capital", Json::string(value.trim().to_owned()))
    _ => raise reject(422, "registerCapital must be numeric")
  }
  match json_field(body, "enabled") {
    None => ()
    Some(True) => canonical.set("enabled", Json::boolean(true))
    Some(False) => canonical.set("enabled", Json::boolean(false))
    _ => raise reject(422, "enabled must be boolean")
  }
  supplier_create_request(Json::object(canonical), actor_id)
}

///|
fn supplier_update_request(
  supplier_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(supplier_id) {
    raise reject(422, "supplier_id is required")
  }
  let changes : Map[String, Json] = {}
  for
    key in [
      "scope", "supplier_code", "name", "category_code", "short_name", "legal_person",
      "business_scope", "source", "contact_person", "contact_phone", "address", "evaluation",
    ] {
    match json_field(body, key) {
      None | Some(Null) => ()
      Some(String(value)) if !value.trim().is_empty() => {
        let cleaned = value.trim().to_owned()
        if (key == "scope" || key == "supplier_code" || key == "category_code") &&
          !valid_identifier(cleaned) {
          raise reject(422, key + " contains unsupported characters")
        }
        changes.set(key, Json::string(cleaned))
      }
      _ => raise reject(422, key + " must be non-empty text")
    }
  }
  supplier_register_capital(body, "register_capital", changes)
  supplier_enabled(body, "enabled", changes)
  if changes.is_empty() {
    raise reject(422, "update requires at least one mutable field")
  }
  Json::object({
    "command_type": Json::string("update"),
    "supplier_id": Json::string(supplier_id),
    "changes": Json::object(changes),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn supplier_source_update_request(
  supplier_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let canonical : Map[String, Json] = {}
  for
    source_key in [
      "providerCode", "providerName", "shortName", "legalPerson", "businessScope",
      "mainCategoryCode", "evalResult", "source", "contactPerson", "contactPhone",
      "address",
    ] {
    let target_key = if source_key == "providerCode" {
      "supplier_code"
    } else if source_key == "providerName" {
      "name"
    } else if source_key == "shortName" {
      "short_name"
    } else if source_key == "legalPerson" {
      "legal_person"
    } else if source_key == "businessScope" {
      "business_scope"
    } else if source_key == "mainCategoryCode" {
      "category_code"
    } else if source_key == "evalResult" {
      "evaluation"
    } else if source_key == "contactPerson" {
      "contact_person"
    } else if source_key == "contactPhone" {
      "contact_phone"
    } else {
      source_key
    }
    match json_field(body, source_key) {
      None => ()
      Some(String(value)) =>
        canonical.set(target_key, Json::string(value.trim().to_owned()))
      Some(_) => raise reject(422, source_key + " must be text")
    }
  }
  match json_field(body, "registerCapital") {
    None => ()
    Some(Number(number, ..)) =>
      canonical.set("register_capital", Json::string(number.to_string()))
    Some(String(value)) =>
      canonical.set("register_capital", Json::string(value.trim().to_owned()))
    _ => raise reject(422, "registerCapital must be numeric")
  }
  match json_field(body, "enabled") {
    None => ()
    Some(True) => canonical.set("enabled", Json::boolean(true))
    Some(False) => canonical.set("enabled", Json::boolean(false))
    _ => raise reject(422, "enabled must be boolean")
  }
  supplier_update_request(supplier_id, Json::object(canonical), actor_id)
}

///|
fn supplier_transition_request(
  command_type : String,
  supplier_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(supplier_id) {
    raise reject(422, "supplier_id is required")
  }
  let reason = match json_field(body, "reason") {
    None => ""
    Some(String(value)) => value.trim().to_owned()
    _ => raise reject(422, "reason must be text")
  }
  if command_type == "review" {
    let evaluation = supplier_required_text(body, "evaluation", true).to_lower()
    if evaluation != "reviewed" &&
      evaluation != "qualified" &&
      evaluation != "unqualified" &&
      evaluation != "strategic" {
      raise reject(422, "evaluation is invalid")
    }
    Json::object({
      "command_type": Json::string(command_type),
      "supplier_id": Json::string(supplier_id),
      "evaluation": Json::string(evaluation),
      "reason": Json::string(reason),
      "actor_id": Json::string(actor_id),
    })
  } else {
    Json::object({
      "command_type": Json::string(command_type),
      "supplier_id": Json::string(supplier_id),
      "reason": Json::string(reason),
      "actor_id": Json::string(actor_id),
    })
  }
}

///|
async fn latest_supplier_payload(
  supplier_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'supplier' AND aggregate_id = " +
    @postgres.sql_literal(supplier_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid supplier projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn supplier_imported_exists(
  supplier_id : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows("srm_provider", 500)
  for row in rows {
    if json_text(row.payload, "provider_guid", row.record_id) == supplier_id &&
      json_text(row.payload, "deleted_at", "").is_empty() {
      return true
    }
  }
  false
}

///|
async fn supplier_command(
  command_type : String,
  supplier_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request) = if command_type == "create" {
    let request = supplier_create_request(body, actor_id)
    (json_text(request, "supplier_id", ""), request)
  } else {
    let id = match supplier_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "supplier_id is required")
    }
    let request = if command_type == "update" {
      match json_field(body, "changes") {
        Some(Object(_)) => body
        _ => supplier_update_request(id, body, actor_id)
      }
    } else {
      supplier_transition_request(command_type, id, body, actor_id)
    }
    (id, request)
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "supplier": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_supplier_payload(id)
  let imported = supplier_imported_exists(id)
  if command_type == "create" {
    if current is Some(_) || imported {
      raise reject(409, "supplier already exists")
    }
  } else {
    match current {
      None => {
        if imported {
          raise reject(
            409, "imported supplier is read-only; create a local supplier first",
          )
        }
        raise reject(404, "supplier not found")
      }
      Some((payload, _)) => {
        let state = json_text(payload, "state", "draft")
        if command_type == "update" && state == "voided" {
          raise reject(409, "voided supplier cannot be updated")
        }
        if command_type == "submit_review" && state != "draft" {
          raise reject(
            409,
            "supplier transition submit_review requires draft, found " + state,
          )
        }
        if command_type == "review" && state != "pending_review" {
          raise reject(
            409,
            "supplier transition review requires pending_review, found " + state,
          )
        }
        if (command_type == "blacklist" || command_type == "void") &&
          state == "voided" {
          raise reject(409, "voided supplier cannot change state")
        }
      }
    }
  }
  let event_id = "supplier:" + command_type + ":" + idempotency_key
  let command_source = "moonproj:command:" + idempotency_key
  let audit_id = event_id + ":audit"
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_state = if command_type == "create" {
    "draft"
  } else if command_type == "submit_review" {
    "pending_review"
  } else if command_type == "review" {
    let evaluation = json_text(request, "evaluation", "unqualified")
    if evaluation == "qualified" || evaluation == "strategic" {
      "active"
    } else {
      "suspended"
    }
  } else if command_type == "blacklist" {
    "blacklisted"
  } else if command_type == "void" {
    "voided"
  } else {
    json_text(current_payload, "state", "draft")
  }
  let next_evaluation = if command_type == "create" {
    "unrated"
  } else if command_type == "update" {
    json_text(
      json_field(request, "changes").unwrap_or(Json::object({})),
      "evaluation",
      json_text(current_payload, "evaluation", "unrated"),
    )
  } else {
    json_text(
      request,
      "evaluation",
      json_text(current_payload, "evaluation", "unrated"),
    )
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let result = Json::object({
    "supplier_id": Json::string(id),
    "state": Json::string(next_state),
    "evaluation": Json::string(next_evaluation),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "supplier_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let request_json = request.stringify()
  let current_json = current_payload.stringify()
  let next_payload_sql = if command_type == "create" {
    @postgres.sql_literal(request_json) +
    "::jsonb || jsonb_build_object('state', 'draft', 'evaluation', 'unrated', 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else if command_type == "update" {
    @postgres.sql_literal(current_json) +
    "::jsonb || (" +
    @postgres.sql_literal(request_json) +
    "::jsonb->'changes') || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'evaluation', " +
    @postgres.sql_literal(next_evaluation) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ")"
  } else {
    @postgres.sql_literal(current_json) +
    "::jsonb || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'evaluation', " +
    @postgres.sql_literal(next_evaluation) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', " +
    @postgres.sql_literal(actor_id) +
    ", 'reason', " +
    @postgres.sql_literal(json_text(request, "reason", "")) +
    ")"
  }
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("supplier." + command_type),
    "aggregate_type": Json::string("supplier"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(next_state),
    "evaluation": Json::string(next_evaluation),
    "revision": Json::number(next_revision.to_double()),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('supplier', " +
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
      "supplier": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
async fn source_supplier_alias_result(
  result : Json,
) -> Json raise CompanyServiceError {
  let supplier = json_field(result, "supplier").unwrap_or(Json::null())
  let command = json_field(result, "command").unwrap_or(Json::null())
  let request = json_field(command, "request").unwrap_or(Json::null())
  let changes = json_field(request, "changes").unwrap_or(Json::null())
  let supplier_id = json_text(supplier, "supplier_id", "")
  let provider_code = if !json_text(changes, "supplier_code", "").is_empty() {
    json_text(changes, "supplier_code", supplier_id)
  } else {
    json_text(request, "supplier_code", supplier_id)
  }
  let list = supplier_source_list_response()
  let mut provider = Json::null()
  match json_field(list, "data") {
    Some(Array(items)) =>
      for item in items {
        if json_text(item, "providerGuid", "") == supplier_id {
          provider = item
          break
        }
      }
    _ => ()
  }
  if provider is Null {
    provider = Json::object({
      "providerGuid": Json::string(supplier_id),
      "providerCode": Json::string(provider_code),
      "providerName": Json::string(supplier_id),
      "sourceKind": Json::string("command"),
      "source_kind": Json::string("command"),
      "auditState": Json::string(json_text(supplier, "state", "")),
      "evalResult": Json::string(json_text(supplier, "evaluation", "unrated")),
      "enabled": Json::boolean(json_text(supplier, "state", "") != "voided"),
    })
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "providerGuid": Json::string(supplier_id),
      "providerCode": Json::string(provider_code),
    }),
    "provider": provider,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
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
    "  'sum_alter_amount_minor', coalesce(base.payload->'candidate'->>'sum_alter_amount_minor', base.payload->>'sum_alter_amount_minor', '0')::bigint,",
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
async fn send_bytes(
  conn : @http.ServerConnection,
  request_method : @http.RequestMethod,
  status : Int,
  payload : Bytes,
  content_type : String,
  content_disposition : String,
) -> Unit {
  conn.send_response(status, status_reason(status), extra_headers={
    "Content-Type": content_type,
    "Content-Disposition": content_disposition,
    "Content-Length": payload.length().to_string(),
    "Cache-Control": "no-store",
  })
  if request_method is @http.Head {
    conn.end_response()
    return
  }
  conn.write(payload)
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
fn contract_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/contracts" {
    return Some(("create", None))
  }
  if request_method is @http.Post &&
    path == "/api/company/source/cost/contracts" {
    return Some(("source-create", None))
  }
  let contract_prefix = "/api/company/contracts/"
  if request_method is @http.Post && path.has_prefix(contract_prefix) {
    let rest = path[contract_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "submit" | "submit-for-approval" => "submit"
        "approve" => "approve"
        "reject" => "reject"
        "resubmit" => "resubmit"
        _ => ""
      }
      if !command.is_empty() {
        return Some((command, Some(rest[0].to_owned())))
      }
    }
  }
  let source_prefix = "/api/company/source/cost/contracts/"
  if path.has_prefix(source_prefix) {
    let id = path[source_prefix.length():].to_owned()
    if valid_identifier(id) {
      if request_method is @http.Put {
        return Some(("source-update", Some(id)))
      }
      if request_method is @http.Delete {
        return Some(("source-void", Some(id)))
      }
    }
  }
  None
}

///|
fn payment_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/payment-applies" {
    return Some(("create", None))
  }
  if request_method is @http.Post &&
    path == "/api/company/source/cost/payment-applies" {
    return Some(("source-create", None))
  }
  let prefix = "/api/company/payment-applies/"
  if request_method is @http.Post && path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "submit" => "submit"
        "approve" => "approve"
        "reject" => "reject"
        "resubmit" => "resubmit"
        "update" => "update"
        "void" => "void"
        _ => ""
      }
      if !command.is_empty() {
        return Some((command, Some(rest[0].to_owned())))
      }
    }
  }
  let source_prefix = "/api/company/source/cost/payment-applies/"
  if path.has_prefix(source_prefix) {
    let id = path[source_prefix.length():].to_owned()
    if valid_identifier(id) {
      if request_method is @http.Put {
        return Some(("source-update", Some(id)))
      }
      if request_method is @http.Delete {
        return Some(("source-void", Some(id)))
      }
    }
  }
  None
}

///|
fn dynamic_cost_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/cost/dynamic-cost" {
    return Some(("source-create", None))
  }
  let prefix = "/api/company/source/cost/dynamic-cost/"
  if path.has_prefix(prefix) {
    let id = path[prefix.length():].to_owned()
    if valid_identifier(id) {
      if request_method is @http.Put {
        return Some(("source-update", Some(id)))
      }
      if request_method is @http.Delete {
        return Some(("source-void", Some(id)))
      }
    }
  }
  None
}

///|
fn milestone_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?, String?)? {
  if request_method is @http.Post &&
    path == "/api/company/source/cost/milestones" {
    return Some(("source-create", None, None))
  }
  let contract_prefix = "/api/company/source/cost/contracts/"
  if request_method is @http.Post &&
    path.has_prefix(contract_prefix) &&
    path.has_suffix("/milestones") {
    let contract_id = path[contract_prefix.length():path.length() - 11].to_owned()
    if valid_identifier(contract_id) {
      return Some(("source-create", Some(contract_id), None))
    }
  }
  let milestone_prefix = "/api/company/source/cost/milestones/"
  if path.has_prefix(milestone_prefix) {
    let rest = path[milestone_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 1 && valid_identifier(rest[0].to_owned()) {
      if request_method is @http.Put {
        return Some(("update", None, Some(rest[0].to_owned())))
      }
      if request_method is @http.Delete {
        return Some(("delete", None, Some(rest[0].to_owned())))
      }
    }
    if request_method is @http.Post &&
      rest.length() == 2 &&
      rest[1].to_owned() == "trigger-event" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("trigger_event", None, Some(rest[0].to_owned())))
    }
  }
  None
}

///|
fn invoice_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String, String?)? {
  if request_method is @http.Post {
    if path == "/api/company/source/invoice/in" {
      return Some(("in", "create", None))
    }
    if path == "/api/company/source/invoice/out" {
      return Some(("out", "create", None))
    }
  }
  let prefix = "/api/company/source/invoice/"
  if request_method is @http.Delete && path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      (rest[0].to_owned() == "in" || rest[0].to_owned() == "out") &&
      valid_identifier(rest[1].to_owned()) {
      return Some((rest[0].to_owned(), "delete", Some(rest[1].to_owned())))
    }
  }
  None
}

///|
fn sales_revenue_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/sales/revenues" {
    return Some(("create", None))
  }
  let prefix = "/api/company/sales/revenues/"
  if request_method is @http.Post && path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      rest[1].to_owned() == "confirm-received" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("confirm_received", Some(rest[0].to_owned())))
    }
  }
  if (request_method is @http.Put || request_method is @http.Delete) &&
    path.has_prefix(prefix) {
    let id = path[prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(
        (
          if request_method is @http.Put {
            "update"
          } else {
            "delete"
          },
          Some(id),
        ),
      )
    }
  }
  None
}

///|
fn tender_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post {
    if path == "/api/company/tenders" {
      return Some(("create", None))
    }
    if path == "/api/company/source/tender/tenders" {
      return Some(("source-create", None))
    }
    if path == "/api/company/tender-splits" {
      return Some(("split-create", None))
    }
    if path == "/api/company/source/tender/splits" {
      return Some(("source-split-create", None))
    }
    if path == "/api/company/source/tender/awards" {
      return Some(("source-award", None))
    }
  }
  let tender_prefix = "/api/company/tenders/"
  if request_method is @http.Delete && path.has_prefix(tender_prefix) {
    let id = path[tender_prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(("delete", Some(id)))
    }
  }
  let source_prefix = "/api/company/source/tender/tenders/"
  if request_method is @http.Delete && path.has_prefix(source_prefix) {
    let id = path[source_prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(("source-delete", Some(id)))
    }
  }
  if request_method is @http.Put &&
    path.has_prefix(source_prefix) &&
    path.has_suffix("/state") {
    let id = path[source_prefix.length():path.length() - "/state".length()].to_owned()
    if valid_identifier(id) {
      return Some(("source-state", Some(id)))
    }
  }
  if request_method is @http.Post && path.has_prefix(tender_prefix) {
    let rest = path[tender_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "publish" => "publish"
        "open_bidding" => "open_bidding"
        "award" => "award"
        "complete" => "complete"
        "cancel" => "cancel"
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
fn marketing_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String, String?)? {
  if request_method is @http.Post {
    if path == "/api/company/marketing/campaigns" {
      return Some(("campaign", "create", None))
    }
    if path == "/api/company/marketing/placements" {
      return Some(("placement", "create", None))
    }
    if path == "/api/company/marketing/channels" {
      return Some(("channel", "create", None))
    }
    if path == "/api/company/marketing/materials" {
      return Some(("material", "create", None))
    }
  }
  let campaign_prefix = "/api/company/marketing/campaigns/"
  if request_method is @http.Put && path.has_prefix(campaign_prefix) {
    let id = path[campaign_prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(("campaign", "update", Some(id)))
    }
  }
  let effect_prefix = "/api/company/marketing/placements/"
  if request_method is @http.Put &&
    path.has_prefix(effect_prefix) &&
    path.has_suffix("/effect") {
    let id = path[effect_prefix.length():path.length() - "/effect".length()].to_owned()
    if valid_identifier(id) {
      return Some(("placement", "effect", Some(id)))
    }
  }
  let delete_prefixes = [
    "/api/company/marketing/campaigns/", "/api/company/marketing/channels/", "/api/company/marketing/materials/",
  ]
  let delete_resources = ["campaign", "channel", "material"]
  for index in 0..<delete_prefixes.length() {
    let prefix = delete_prefixes[index]
    if request_method is @http.Delete && path.has_prefix(prefix) {
      let id = path[prefix.length():].to_owned()
      if valid_identifier(id) {
        return Some((delete_resources[index], "delete", Some(id)))
      }
    }
  }
  None
}

///|
fn fund_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String, String?)? {
  if request_method is @http.Post {
    if path == "/api/company/fund/plans" {
      return Some(("plan", "create", None))
    }
    if path == "/api/company/fund/dispatches" {
      return Some(("dispatch", "create", None))
    }
  }
  let plan_prefix = "/api/company/fund/plans/"
  if path.has_prefix(plan_prefix) {
    let rest = path[plan_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 1 &&
      valid_identifier(rest[0].to_owned()) &&
      request_method is @http.Put {
      return Some(("plan", "update", Some(rest[0].to_owned())))
    }
    if rest.length() == 2 &&
      rest[1].to_owned() == "delete" &&
      valid_identifier(rest[0].to_owned()) &&
      request_method is @http.Post {
      return Some(("plan", "delete", Some(rest[0].to_owned())))
    }
  }
  let dispatch_prefix = "/api/company/fund/dispatches/"
  if request_method is @http.Post && path.has_prefix(dispatch_prefix) {
    let rest = path[dispatch_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      rest[1].to_owned() == "approve" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("dispatch", "approve", Some(rest[0].to_owned())))
    }
  }
  None
}

///|
fn supplier_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/suppliers" {
    return Some(("create", None))
  }
  if request_method is @http.Post && path == "/api/company/source/srm/providers" {
    return Some(("source-create", None))
  }
  let supplier_prefix = "/api/company/suppliers/"
  if request_method is @http.Post && path.has_prefix(supplier_prefix) {
    let rest = path[supplier_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "update" => "update"
        "submit_review" => "submit_review"
        "review" => "review"
        "blacklist" => "blacklist"
        "void" => "void"
        _ => ""
      }
      if !command.is_empty() {
        return Some((command, Some(rest[0].to_owned())))
      }
    }
  }
  let source_prefix = "/api/company/source/srm/providers/"
  if path.has_prefix(source_prefix) {
    let id = path[source_prefix.length():].to_owned()
    if valid_identifier(id) {
      if request_method is @http.Put || request_method is @http.Patch {
        return Some(("source-update", Some(id)))
      }
      if request_method is @http.Delete {
        return Some(("source-void", Some(id)))
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
  actor_id : String,
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
  if path == "/api/company/source/migration/schema-coverage" {
    return (200, migration_schema_coverage_response())
  }
  if path == "/api/company/business-units/tree" {
    return (200, business_units_tree_response())
  }
  if path == "/api/company/budget/dict/cost-subjects" {
    return (200, budget_cost_subjects_response())
  }
  if path == "/api/company/budget/proceedings" {
    return (200, budget_proceedings_response())
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
  if path == "/api/company/workflow/tasks/mine" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_tasks_mine(user_id, user_code))
  }
  if path == "/api/company/source/workflow/tasks/initiated" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_tasks_initiated(user_id, user_code))
  }
  if path == "/api/company/workflow/tasks/initiated" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_tasks_initiated(user_id, user_code))
  }
  if path == "/api/company/source/workflow/tasks/my-history" {
    let user_code = query_alias_decoded(query, "userCode", "user_code")
    let user_id = query_alias_decoded(query, "userId", "user_id")
    return (200, workflow_history(user_id, user_code))
  }
  if path == "/api/company/workflow/tasks/my-history" {
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
  if path == "/api/company/workflow/instances/by-biz" {
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
  let canonical_workflow_instance_prefix = "/api/company/workflow/instances/"
  if path.has_prefix(canonical_workflow_instance_prefix) {
    let instance_id = path[canonical_workflow_instance_prefix.length():].to_owned()
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
  if path == "/api/company/loans" {
    return (
      200,
      loan_read_response(
        query_alias_decoded(query, "loanId", "loan_id"),
        query_alias_decoded(query, "applyState", "apply_state"),
      ),
    )
  }
  let loan_prefix = "/api/company/loans/"
  if path.has_prefix(loan_prefix) {
    let loan_id = path[loan_prefix.length():].to_owned()
    if loan_id.is_empty() || loan_id.contains("/") {
      return (404, Json::object({ "error": Json::string("loan not found") }))
    }
    return loan_detail_response(loan_id)
  }
  if path == "/api/company/cashflow/forecast" {
    return (
      200,
      cashflow_forecast_response(
        parse_decimal(query_decoded(query, "months").unwrap_or("6")),
        query_alias_decoded(query, "buGuid", "bu_guid"),
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  if path == "/api/company/cashflow/forecast-v3" {
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    if proj_guid.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("projGuid is required") }),
      )
    }
    return (
      200,
      cashflow_v3_response(
        parse_decimal(query_decoded(query, "months").unwrap_or("6")),
        proj_guid,
      ),
    )
  }
  if path == "/api/company/cashflow/forecast/detail" {
    let ym = query_decoded(query, "ym").unwrap_or("")
    if ym.is_empty() {
      return (422, Json::object({ "error": Json::string("ym is required") }))
    }
    return (
      200,
      cashflow_detail_response(
        ym,
        query_alias_decoded(query, "buGuid", "bu_guid"),
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  if path == "/api/company/cashflow/inflow" {
    return (
      200,
      cashflow_inflow_response(
        parse_decimal(query_decoded(query, "months").unwrap_or("6")),
        query_alias_decoded(query, "buGuid", "bu_guid"),
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  if path == "/api/company/cashflow/net" {
    return (
      200,
      cashflow_net_response(
        parse_decimal(query_decoded(query, "months").unwrap_or("6")),
      ),
    )
  }
  if path == "/api/company/cashflow/gap-alert" {
    return (
      200,
      cashflow_gap_response(
        parse_decimal(query_decoded(query, "horizonDays").unwrap_or("90")),
      ),
    )
  }
  if path == "/api/company/cbs/r-master" {
    return (200, cbs_r_master_response())
  }
  if path == "/api/company/cbs/dict" {
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    if proj_guid.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("projGuid is required") }),
      )
    }
    return (
      200,
      cbs_dict_response(
        proj_guid,
        query_alias_decoded(query, "planVersion", "plan_version"),
        query_alias_decoded(query, "rCode", "r_code"),
      ),
    )
  }
  if path == "/api/company/cbs/dict/f-balance" {
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    let l3_code = query_alias_decoded(query, "l3Code", "l3_code").unwrap_or("")
    if proj_guid.is_empty() || l3_code.is_empty() {
      return (
        422,
        Json::object({
          "error": Json::string("projGuid and l3Code are required"),
        }),
      )
    }
    return cbs_f_balance_response(
      proj_guid,
      l3_code,
      query_alias_decoded(query, "planVersion", "plan_version"),
    )
  }
  if path == "/api/company/cbs/versions" {
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    if proj_guid.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("projGuid is required") }),
      )
    }
    return (200, cbs_versions_response(proj_guid))
  }
  if path == "/api/company/cbs/versions/compare" {
    let proj_guid = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    let version_a = query_decoded(query, "a").unwrap_or("")
    let version_b = query_decoded(query, "b").unwrap_or("")
    if proj_guid.is_empty() || version_a.is_empty() || version_b.is_empty() {
      return (
        422,
        Json::object({
          "error": Json::string("projGuid, a, and b are required"),
        }),
      )
    }
    return (200, cbs_compare_response(proj_guid, version_a, version_b))
  }
  if path == "/api/company/cbs/r0/queue" {
    return (
      200,
      cbs_r0_queue_response(query_alias_decoded(query, "projGuid", "proj_guid")),
    )
  }
  if path == "/api/company/cbs/approval-rules" {
    return (
      200,
      cbs_approval_rules_response(
        query_alias_decoded(query, "bizType", "biz_type"),
      ),
    )
  }
  if path == "/api/company/cbs/approval-rules/pick" {
    let biz_type = query_alias_decoded(query, "bizType", "biz_type").unwrap_or(
      "",
    )
    if biz_type.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("bizType is required") }),
      )
    }
    let amount = match query_decoded(query, "amount") {
      Some(value) => parse_number(value)
      None => 0.0
    }
    return (200, cbs_approval_pick_response(biz_type, amount))
  }
  if path == "/api/company/cbs/changes" {
    return (
      200,
      cbs_changes_response(
        query_alias_decoded(query, "projGuid", "proj_guid"),
        query_alias_decoded(query, "contractGuid", "contract_guid"),
      ),
    )
  }
  if path == "/api/company/cbs/demo/contracts" {
    return (
      200,
      cbs_demo_contracts_response(
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  if path == "/api/company/attachments/all" ||
    path == "/api/company/attachments" ||
    path == "/api/company/source/attachments/all" ||
    path == "/api/company/source/attachments" {
    return (
      200,
      attachment_all_response(
        query_alias_decoded(query, "uploadedBy", "uploaded_by"),
        query_alias_decoded(query, "aiStatus", "ai_status"),
        query_decoded(query, "keyword"),
      ),
    )
  }
  if path == "/api/company/attachments/list" ||
    path == "/api/company/source/attachments/list" {
    return (
      200,
      attachment_list_response(
        query_alias_decoded(query, "bizType", "biz_type"),
        query_alias_decoded(query, "bizGuid", "biz_guid"),
      ),
    )
  }
  if path == "/api/company/attachments/stats" ||
    path == "/api/company/source/attachments/stats" {
    return (200, attachment_stats_response())
  }
  let attachment_download_prefix = "/api/company/attachments/download/"
  if path.has_prefix(attachment_download_prefix) {
    return attachment_download_response(
      path[attachment_download_prefix.length():].to_owned(),
    )
  }
  if path == "/api/company/ai-stats/overview" {
    return (
      200,
      ai_stats_overview_response(
        query_decoded(query, "period").unwrap_or("month"),
      ),
    )
  }
  if path == "/api/company/ai-stats/activity" {
    return (
      200,
      ai_stats_activity_response(
        parse_decimal(query_decoded(query, "limit").unwrap_or("30")),
      ),
    )
  }
  if path == "/api/company/ai-stats/badge" {
    let biz_type = query_alias_decoded(query, "bizType", "biz_type").unwrap_or(
      "",
    )
    let biz_guid = query_alias_decoded(query, "bizGuid", "biz_guid").unwrap_or(
      "",
    )
    if biz_type.is_empty() || biz_guid.is_empty() {
      return (
        422,
        Json::object({
          "error": Json::string("bizType and bizGuid are required"),
        }),
      )
    }
    return (200, ai_stats_badge_response(biz_type, biz_guid))
  }
  if path == "/api/company/ai-hub/usage-stats" {
    return (200, ai_hub_usage_response())
  }
  if path == "/api/company/ai-hub/drafts" {
    return (
      200,
      ai_hub_drafts_response(
        query_alias_decoded(query, "userCode", "user_code"),
      ),
    )
  }
  let ai_draft_prefix = "/api/company/ai-hub/drafts/"
  if path.has_prefix(ai_draft_prefix) {
    return ai_hub_draft_response(
      path[ai_draft_prefix.length():].to_owned(),
      query_alias_decoded(query, "userCode", "user_code"),
    )
  }
  if path == "/api/company/ai-hub/query-log" {
    return (
      200,
      ai_hub_query_response(query_alias_decoded(query, "userCode", "user_code")),
    )
  }
  if path == "/api/company/ai-hub/correction-stats" {
    return (200, ai_hub_correction_stats_response())
  }
  if path == "/api/company/ai-hub/corrections" {
    return (
      200,
      ai_hub_corrections_response(
        parse_decimal(query_decoded(query, "limit").unwrap_or("50")),
        query_decoded(query, "bizType"),
        query_decoded(query, "field"),
        query_alias_decoded(query, "userCode", "user_code"),
      ),
    )
  }
  if path == "/api/company/webhook/config" {
    return (200, webhook_config_response_native())
  }
  if path == "/api/company/source/webhook/config" {
    return (200, webhook_config_response_native())
  }
  if path == "/api/company/notify/messages" ||
    path == "/api/company/source/notify/messages" {
    return (200, notification_messages_response_native(actor_id))
  }
  if path == "/api/company/notify/messages/unread-count" ||
    path == "/api/company/source/notify/messages/unread-count" {
    return (200, notification_unread_response_native(actor_id))
  }
  if path == "/api/company/notify/subscriptions" ||
    path == "/api/company/source/notify/subscriptions" {
    return (200, notification_subscriptions_response_native(actor_id))
  }
  if path == "/api/company/notify/config" {
    return (200, notification_config_response_native())
  }
  if path == "/api/company/source/notify/config" {
    return (200, notification_config_response_native())
  }
  if path == "/api/company/notify/digest/preview" {
    return (200, notification_digest_preview_response())
  }
  if path == "/api/company/notify/email-outbox" {
    return (200, notification_email_outbox_response())
  }
  if path == "/api/company/notify/digest/log" {
    return (200, notification_digest_log_response())
  }
  if path == "/api/company/notify/llm-providers" {
    return (200, notification_llm_providers_response())
  }
  if path == "/api/company/admin/ocr/status" {
    return (200, admin_ocr_response())
  }
  if path == "/api/company/admin/error-log" {
    return (
      200,
      admin_error_log_response(
        query_decoded(query, "keyword"),
        parse_decimal(query_decoded(query, "limit").unwrap_or("100")),
      ),
    )
  }
  if path == "/api/company/admin/dict/groups" {
    return (200, admin_dict_groups_response())
  }
  if path == "/api/company/admin/dict/options" {
    return (
      200,
      admin_dict_options_response(
        query_alias_decoded(query, "groupName", "group_name"),
      ),
    )
  }
  if path == "/api/company/admin/audit/logs" {
    return (
      200,
      admin_audit_logs_response(
        query_decoded(query, "action"),
        query_alias_decoded(query, "userId", "user_id"),
        query_alias_decoded(query, "targetType", "target_type"),
        parse_decimal(query_decoded(query, "limit").unwrap_or("100")),
        parse_decimal(query_decoded(query, "offset").unwrap_or("0")),
      ),
    )
  }
  if path == "/api/company/admin/audit/actions" {
    return (200, admin_audit_actions_response())
  }
  if path == "/api/company/admin/health/tables" {
    return (200, admin_health_tables_response())
  }
  if path == "/api/company/admin/health/bpm-pool" {
    return (200, admin_bpm_pool_response())
  }
  if path == "/api/company/admin/health/full" {
    return (
      200,
      admin_health_full_response(
        query_decoded(query, "database").unwrap_or("moonproj"),
      ),
    )
  }
  if path == "/api/company/admin/llm/status" {
    return (200, admin_llm_status_response())
  }
  if path == "/api/company/admin/ai/diag" {
    return (200, admin_ai_diag_response())
  }
  if path == "/api/company/admin/quality/overview" {
    return (200, admin_quality_response())
  }
  if path == "/api/company/admin/backup/db" {
    return (
      501,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(43032),
        "message": Json::string("database backup remains gated"),
        "backup_status": Json::string("gated"),
        "database": Json::string(
          query_decoded(query, "database").unwrap_or("moonproj"),
        ),
        "format": Json::string("postgresql"),
        "binary_storage": Json::string("not_exported"),
        "authorizing": Json::boolean(false),
        "provider_execution": Json::boolean(false),
      }),
    )
  }
  if path == "/api/company/rbac/users" {
    return (200, rbac_users_response())
  }
  if path == "/api/company/rbac/me" {
    let user_code = query_decoded(query, "userCode").unwrap_or("")
    if user_code.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("userCode is required") }),
      )
    }
    return rbac_me_response(user_code)
  }
  if path == "/api/company/rbac/roles" {
    return (200, rbac_roles_response())
  }
  let rbac_role_prefix = "/api/company/rbac/roles/"
  if path.has_prefix(rbac_role_prefix) {
    let role_code = path[rbac_role_prefix.length():].to_owned()
    if valid_identifier(role_code) {
      return rbac_role_detail_response(role_code)
    }
    return (404, Json::object({ "error": Json::string("role not found") }))
  }
  if path == "/api/company/rbac/permission-catalog" {
    return (200, rbac_permission_catalog_response())
  }
  if path == "/api/company/reports/templates" {
    return (200, report_templates_response())
  }
  if path == "/api/company/reports/templates/meta" {
    return (200, report_templates_meta_response())
  }
  if path == "/api/company/reports/templates/run" {
    return report_template_run_response()
  }
  if path == "/api/company/reports/shares" {
    return (200, report_share_list_response(actor_id))
  }
  let public_share_prefix = "/api/company/share/"
  if path.has_prefix(public_share_prefix) && path.has_suffix("/meta") {
    let token = path[public_share_prefix.length():path.length() -
    "/meta".length()].to_owned()
    return report_share_meta_response(token)
  }
  if path.has_prefix(public_share_prefix) && path.has_suffix("/data") {
    let token = path[public_share_prefix.length():path.length() -
    "/data".length()].to_owned()
    return report_share_data_response(token)
  }
  if path == "/api/company/warning" {
    return (
      200,
      warning_list_response(
        query_decoded(query, "status"),
        query_alias_decoded(query, "ruleCode", "rule_code"),
        query_decoded(query, "severity"),
        query_alias_decoded(query, "bizType", "biz_type"),
      ),
    )
  }
  if path == "/api/company/warning/badge" {
    return (200, warning_badge_response())
  }
  if path == "/api/company/warning/rules" {
    return (200, warning_rules_response())
  }
  if path == "/api/company/warning/custom-rules" ||
    path == "/api/company/source/warning/custom-rules" {
    return (200, warning_custom_rules_response())
  }
  if path == "/api/company/warning/tickets/mine" ||
    path == "/api/company/source/warning/tickets/mine" {
    return (200, warning_ticket_list_response(actor_id))
  }
  if path == "/api/company/warning/scans" ||
    path == "/api/company/warning/rule-templates" {
    return (200, warning_empty_response(path))
  }
  if path == "/api/company/reports/overview" {
    return (200, reports_overview_response())
  }
  if path == "/api/company/investment/meta/dimensions" {
    return (
      200,
      investment_envelope(Json::array(investment_dimension_rows()), {}),
    )
  }
  let investment_project_prefix = "/api/company/investment/projects/"
  if path.has_prefix(investment_project_prefix) {
    if path.has_suffix("/profit-actual-v2") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/profit-actual-v2".length()].to_owned()
      return investment_profit_actual_v2_response(
        project_id,
        query_alias_decoded(query, "planVersion", "plan_version"),
      )
    }
    if path.has_suffix("/versions") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/versions".length()].to_owned()
      return (200, investment_versions_response(project_id))
    }
    if path.has_suffix("/excel-imports") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/excel-imports".length()].to_owned()
      return (200, investment_imports_response(project_id))
    }
    if path.has_suffix("/plan-lines") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/plan-lines".length()].to_owned()
      return (
        200,
        investment_plan_lines_response(
          project_id,
          query_decoded(query, "versionGuid"),
          query_decoded(query, "moduleCode"),
          query_decoded(query, "sheet"),
          query_decoded(query, "department"),
          query_decoded(query, "status"),
          query_decoded(query, "keyword"),
        ),
      )
    }
    if path.has_suffix("/subject-mappings") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/subject-mappings".length()].to_owned()
      return investment_subject_mappings_response(project_id)
    }
    if path.has_suffix("/profit-cockpit") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/profit-cockpit".length()].to_owned()
      return investment_profit_cockpit_response(project_id)
    }
    if path.has_suffix("/profit-summary") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/profit-summary".length()].to_owned()
      return (200, investment_profit_summary_response(project_id))
    }
    if path.has_suffix("/sensitivity") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/sensitivity".length()].to_owned()
      return (200, investment_sensitivity_response(project_id))
    }
    if path.has_suffix("/profit-actual") {
      let project_id = path[investment_project_prefix.length():path.length() -
      "/profit-actual".length()].to_owned()
      return investment_profit_actual_response(project_id)
    }
  }
  let investment_import_prefix = "/api/company/investment/excel-imports/"
  if path.has_prefix(investment_import_prefix) {
    let rest = path[investment_import_prefix.length():].to_owned()
    if rest.has_suffix("/bridge-plan") {
      let import_id = rest[:rest.length() - "/bridge-plan".length()].to_owned()
      return investment_import_bridge_plan_response(import_id)
    }
    if rest.has_suffix("/index-upsert-preview") {
      let import_id = rest[:rest.length() - "/index-upsert-preview".length()].to_owned()
      return investment_index_upsert_preview_response(import_id)
    }
    if rest.has_suffix("/profit-table") {
      let import_id = rest[:rest.length() - "/profit-table".length()].to_owned()
      return investment_profit_table_response(import_id)
    }
    if rest.has_suffix("/plan-line-preview") {
      let import_id = rest[:rest.length() - "/plan-line-preview".length()].to_owned()
      return investment_plan_line_preview_response(import_id)
    }
    return investment_import_detail_response(rest)
  }
  let investment_indices_prefix = "/api/company/investment/versions/"
  if path.has_prefix(investment_indices_prefix) && path.has_suffix("/indices") {
    let version_id = path[investment_indices_prefix.length():path.length() -
    "/indices".length()].to_owned()
    return (
      200,
      investment_indices_response(
        version_id,
        query_alias_decoded(query, "dimension", "dimension"),
      ),
    )
  }
  if path == "/api/company/workflow/process-defs" {
    return (
      200,
      workflow_process_defs_response(
        query_alias_decoded(query, "processKey", "process_key"),
      ),
    )
  }
  let workflow_process_prefix = "/api/company/workflow/process-defs/"
  if path.has_prefix(workflow_process_prefix) && path.has_suffix("/preview") {
    let process_key = path[workflow_process_prefix.length():path.length() -
    "/preview".length()].to_owned()
    return workflow_process_preview_response(process_key)
  }
  if path == "/api/company/reports/cost-summary" {
    return (200, report_cost_summary())
  }
  if path == "/api/company/reports/contract-payment-ledger" {
    return (200, Json::array(report_contract_payment_ledger()))
  }
  if path == "/api/company/reports/supplier-analysis" {
    return (200, Json::array(report_supplier_analysis()))
  }
  if path == "/api/company/reports/approval-efficiency" {
    return (200, report_approval_efficiency())
  }
  if path == "/api/company/reports/project-stage-matrix" {
    return (200, report_project_stage_matrix())
  }
  if path == "/api/company/dashboard/group/overview" {
    return (200, dashboard_group_overview_response())
  }
  if path == "/api/company/dashboard/group/funnel" {
    return (200, dashboard_group_funnel_response())
  }
  if path == "/api/company/dashboard/group/top-anomalies" {
    let limit = parse_decimal(query_decoded(query, "limit").unwrap_or("10"))
    return (200, dashboard_group_anomalies_response(limit))
  }
  if path == "/api/company/dashboard/v2/group" {
    return (
      200,
      dashboard_v2_response(
        query_alias_decoded(query, "buGuid", "bu_guid"),
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  if path == "/api/company/dashboard/v3/group" {
    return (
      200,
      dashboard_v3_response(
        query_alias_decoded(query, "buGuid", "bu_guid"),
        query_alias_decoded(query, "projGuid", "proj_guid"),
      ),
    )
  }
  let dashboard_project_prefix = "/api/company/dashboard/project/"
  if path.has_prefix(dashboard_project_prefix) {
    let rest = path[dashboard_project_prefix.length():]
      .to_owned()
      .split("/")
      .to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let project_id = rest[0].to_owned()
      if rest[1] == "kpi" {
        return dashboard_project_kpi_response(project_id)
      }
      if rest[1] == "anomalies" {
        return dashboard_project_anomalies_response(project_id)
      }
    }
    return (
      404,
      Json::object({
        "error": Json::string("dashboard project route not found"),
      }),
    )
  }
  if path == "/api/company/projects" {
    return (
      200,
      project_runtime_response(
        query_alias_decoded(query, "projectId", "project_id"),
        query_decoded(query, "status"),
        query_decoded(query, "keyword"),
      ),
    )
  }
  let project_tasks_prefix = "/api/company/projects/"
  if path.has_prefix(project_tasks_prefix) && path.has_suffix("/tasks") {
    let project_id = path[project_tasks_prefix.length():path.length() -
    "/tasks".length()].to_owned()
    let task_items = project_plan_tasks(
      project_id,
      query_alias_decoded(query, "taskType", "type"),
    )
    return (
      200,
      Json::object({
        "success": Json::boolean(true),
        "code": Json::number(0),
        "data": Json::array(task_items),
        "items": Json::array(task_items),
        "source_kind": Json::string("imported_or_command"),
        "command_projection": Json::boolean(true),
        "authorizing": Json::boolean(false),
      }),
    )
  }
  let project_plan_summary_suffix = "/plan-summary"
  if path.has_prefix(project_tasks_prefix) &&
    path.has_suffix(project_plan_summary_suffix) {
    let project_id = path[project_tasks_prefix.length():path.length() -
    project_plan_summary_suffix.length()].to_owned()
    return project_plan_summary_response(project_id)
  }
  let project_lifecycle_suffix = "/lifecycle"
  if path.has_prefix(project_tasks_prefix) &&
    path.has_suffix(project_lifecycle_suffix) {
    let project_id = path[project_tasks_prefix.length():path.length() -
    project_lifecycle_suffix.length()].to_owned()
    return project_lifecycle_response(project_id)
  }
  if path.has_prefix(project_tasks_prefix) {
    let project_id = path[project_tasks_prefix.length():].to_owned()
    if project_id.is_empty() || project_id.contains("/") {
      return (404, Json::object({ "error": Json::string("project not found") }))
    }
    let response = project_runtime_response(Some(project_id), None, None)
    let items = json_field(response, "items").unwrap_or(Json::array([]))
    return match items {
      Array(values) if !values.is_empty() => (200, values[0])
      _ => (404, Json::object({ "error": Json::string("project not found") }))
    }
  }
  let task_delay_prefix = "/api/company/tasks/"
  if path.has_prefix(task_delay_prefix) && path.has_suffix("/delay-impact") {
    let task_id = path[task_delay_prefix.length():path.length() -
    "/delay-impact".length()].to_owned()
    let delay_days = parse_decimal(
      query_decoded(query, "delayDays").unwrap_or("0"),
    )
    return project_delay_impact_response(task_id, delay_days)
  }
  let task_detail_prefix = "/api/company/tasks/"
  if path.has_prefix(task_detail_prefix) {
    let task_id = path[task_detail_prefix.length():].to_owned()
    return project_task_detail_response(task_id)
  }
  if path == "/api/company/tasks" {
    return (200, Json::object({ "items": Json::array([]) }))
  }
  if path == "/api/company/delivery/progress" {
    return (
      200,
      delivery_progress_runtime_response(
        query_alias_decoded(query, "progressGuid", "progress_id"),
        query_alias_decoded(query, "projGuid", "project_id"),
      ),
    )
  }
  let delivery_progress_prefix = "/api/company/delivery/progress/"
  if path.has_prefix(delivery_progress_prefix) {
    let progress_id = path[delivery_progress_prefix.length():].to_owned()
    if !valid_identifier(progress_id) {
      return (
        404,
        Json::object({ "error": Json::string("delivery progress not found") }),
      )
    }
    let response = delivery_progress_runtime_response(Some(progress_id), None)
    let items = json_field(response, "items").unwrap_or(Json::array([]))
    return match items {
      Array(values) if !values.is_empty() => (200, values[0])
      _ =>
        (
          404,
          Json::object({ "error": Json::string("delivery progress not found") }),
        )
    }
  }
  if path == "/api/company/delivery/outputs" {
    return (
      200,
      delivery_outputs_runtime_response(
        query_alias_decoded(query, "outputGuid", "output_id"),
        query_alias_decoded(query, "projGuid", "project_id"),
        query_decoded(query, "period"),
        query_decoded(query, "state"),
      ),
    )
  }
  let delivery_output_prefix = "/api/company/delivery/outputs/"
  if path.has_prefix(delivery_output_prefix) {
    let output_id = path[delivery_output_prefix.length():].to_owned()
    if !valid_identifier(output_id) {
      return (
        404,
        Json::object({ "error": Json::string("delivery output not found") }),
      )
    }
    let response = delivery_outputs_runtime_response(
      Some(output_id),
      None,
      None,
      None,
    )
    let items = json_field(response, "items").unwrap_or(Json::array([]))
    return match items {
      Array(values) if !values.is_empty() => (200, values[0])
      _ =>
        (
          404,
          Json::object({ "error": Json::string("delivery output not found") }),
        )
    }
  }
  if path == "/api/company/delivery/tasks" {
    return (
      200,
      delivery_tasks_runtime_response(
        query_alias_decoded(query, "projGuid", "project_id"),
        query_alias_decoded(query, "taskGuid", "task_id"),
      ),
    )
  }
  let delivery_task_prefix = "/api/company/delivery/tasks/"
  if path.has_prefix(delivery_task_prefix) {
    let task_id = path[delivery_task_prefix.length():].to_owned()
    if !valid_identifier(task_id) {
      return (
        404,
        Json::object({ "error": Json::string("delivery task not found") }),
      )
    }
    let response = delivery_tasks_runtime_response(None, Some(task_id))
    let items = json_field(response, "items").unwrap_or(Json::array([]))
    return match items {
      Array(values) if !values.is_empty() => {
        let reports = delivery_task_report_items(
          None,
          Some(json_text(values[0], "task_id", "")),
        )
        (
          200,
          Json::object({ "task": values[0], "reports": Json::array(reports) }),
        )
      }
      _ =>
        (
          404,
          Json::object({ "error": Json::string("delivery task not found") }),
        )
    }
  }
  if path == "/api/company/delivery/task-reports" {
    return (
      200,
      delivery_reports_runtime_response(
        query_alias_decoded(query, "reportGuid", "report_id"),
        query_alias_decoded(query, "taskGuid", "task_id"),
      ),
    )
  }
  if path == "/api/company/delivery/plan-summary" {
    let project_id = query_alias_decoded(query, "projGuid", "project_id").unwrap_or(
      "",
    )
    return (200, delivery_plan_summary_response(project_id))
  }
  if path == "/api/company/delivery/overview" {
    let project_id = query_alias_decoded(query, "projGuid", "project_id").unwrap_or(
      "",
    )
    return (200, delivery_overview_response(project_id))
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
  if path == "/api/company/marketing/campaigns" {
    return (
      200,
      marketing_source_response(
        "campaign",
        query_alias_decoded(query, "projGuid", "proj_guid"),
        query_decoded(query, "state"),
        None,
      ),
    )
  }
  if path == "/api/company/marketing/placements" {
    return (
      200,
      marketing_source_response(
        "placement",
        None,
        None,
        query_alias_decoded(query, "campaignGuid", "campaign_guid"),
      ),
    )
  }
  if path == "/api/company/marketing/channels" {
    return (200, marketing_source_response("channel", None, None, None))
  }
  if path == "/api/company/marketing/materials" {
    return (
      200,
      marketing_source_response(
        "material",
        query_alias_decoded(query, "projGuid", "proj_guid"),
        None,
        None,
      ),
    )
  }
  if path == "/api/company/fund/plans" {
    return (
      200,
      fund_source_response(
        "plans",
        query_alias_decoded(query, "projGuid", "proj_guid"),
        query_alias_decoded(query, "period", "plan_period"),
        query_decoded(query, "direction"),
      ),
    )
  }
  if path == "/api/company/fund/gap-analysis" {
    let project_id = query_alias_decoded(query, "projGuid", "proj_guid").unwrap_or(
      "",
    )
    if project_id.is_empty() {
      return (
        422,
        Json::object({ "error": Json::string("projGuid is required") }),
      )
    }
    return (200, fund_gap_response(project_id))
  }
  if path == "/api/company/fund/dispatches" {
    return (200, fund_source_response("dispatches", None, None, None))
  }
  if path == "/api/company/tenders" {
    return (
      200,
      tender_read_response(query_alias_decoded(query, "tenderId", "tender_id")),
    )
  }
  let tender_read_prefix = "/api/company/tenders/"
  if path.has_prefix(tender_read_prefix) {
    let tender_id = path[tender_read_prefix.length():].to_owned()
    return tender_detail_response(tender_id)
  }
  if path == "/api/company/tender-splits" {
    return (
      200,
      tender_split_read_response(
        query_alias_decoded(query, "splitId", "split_id"),
        query_alias_decoded(query, "parentContractId", "parent_contract_id"),
      ),
    )
  }
  let tender_split_read_prefix = "/api/company/tender-splits/"
  if path.has_prefix(tender_split_read_prefix) {
    let split_id = path[tender_split_read_prefix.length():].to_owned()
    return tender_split_detail_response(split_id)
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
  if path == "/api/company/srm/stats/overview" {
    return (200, supplier_source_stats_response())
  }
  if path == "/api/company/srm/risk-board" {
    return (200, supplier_risk_board_source_response())
  }
  if path == "/api/company/supplier-risk-board" {
    return (200, supplier_command_risk_board_response())
  }
  if path == "/api/company/suppliers" {
    return (
      200,
      supplier_direct_read_response(
        query_alias_decoded(query, "supplierId", "supplier_id"),
      ),
    )
  }
  let supplier_read_prefix = "/api/company/suppliers/"
  if path.has_prefix(supplier_read_prefix) && path.has_suffix("/risk") {
    let supplier_id = path[supplier_read_prefix.length():path.length() -
    "/risk".length()].to_owned()
    return supplier_direct_risk_response(supplier_id)
  }
  if path.has_prefix(supplier_read_prefix) {
    let supplier_id = path[supplier_read_prefix.length():].to_owned()
    return supplier_direct_detail_response(supplier_id)
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
            Json::string("contract_command"),
            Json::string("source_contract_command"),
            Json::string("payment_application_command"),
            Json::string("source_payment_application_command"),
            Json::string("dynamic_cost_command"),
            Json::string("source_dynamic_cost_command"),
            Json::string("contract_milestone_command"),
            Json::string("source_contract_milestone_command"),
            Json::string("invoice_command"),
            Json::string("source_invoice_command"),
            Json::string("sales_revenue_command"),
            Json::string("source_sales_revenue_command"),
            Json::string("sales_customer_command"),
            Json::string("source_sales_customer_command"),
            Json::string("sales_subscription_command"),
            Json::string("source_sales_subscription_command"),
            Json::string("sales_mortgage_command"),
            Json::string("source_sales_mortgage_command"),
            Json::string("sales_refund_command"),
            Json::string("source_sales_refund_command"),
            Json::string("tender_command"),
            Json::string("source_tender_command"),
            Json::string("source_tender_state_command"),
            Json::string("source_tender_award_command"),
            Json::string("contract_split_command"),
            Json::string("source_contract_split_command"),
            Json::string("marketing_command"),
            Json::string("marketing_observation_read"),
            Json::string("fund_command"),
            Json::string("fund_observation_read"),
            Json::string("delivery_command"),
            Json::string("delivery_read"),
            Json::string("project_runtime_read"),
            Json::string("project_plan_task_command"),
            Json::string("plan_ai_suggestion_candidate"),
            Json::string("loan_read"),
            Json::string("loan_command"),
            Json::string("reports_read"),
            Json::string("dashboard_read"),
            Json::string("workflow_definition_read"),
            Json::string("investment_observation_read"),
            Json::string("cashflow_observation_read"),
            Json::string("cashflow_ai_explain_candidate"),
            Json::string("investment_ai_explain_candidate"),
            Json::string("cbs_observation_read"),
            Json::string("cbs_mutation_boundary_candidate"),
            Json::string("admin_observation_read"),
            Json::string("notification_observation_read"),
            Json::string("notification_message_command"),
            Json::string("notification_subscription_command"),
            Json::string("notification_config_command_candidate"),
            Json::string("notification_digest_dispatch_candidate"),
            Json::string("notification_webhook_test_candidate"),
            Json::string("notification_email_command_candidate"),
            Json::string("ai_provider_test_candidate"),
            Json::string("webhook_config_command_candidate"),
            Json::string("webhook_test_delivery_candidate"),
            Json::string("webhook_overdue_scan_candidate"),
            Json::string("webhook_overdue_preview_read"),
            Json::string("ai_analytics_read"),
            Json::string("ai_hub_explain_candidate"),
            Json::string("ai_hub_command_candidate"),
            Json::string("ai_stats_badge_batch_read"),
            Json::string("ai_hub_read"),
            Json::string("attachment_observation_read"),
            Json::string("attachment_re_extract_candidate"),
            Json::string("attachment_upload_candidate"),
            Json::string("attachment_delete_candidate"),
            Json::string("investment_excel_index_upsert_candidate"),
            Json::string("investment_excel_plan_line_import_candidate"),
            Json::string("investment_subject_mappings_candidate"),
            Json::string("investment_plan_line_update_candidate"),
            Json::string("investment_excel_upload_candidate"),
            Json::string("webhook_config_read"),
            Json::string("rbac_observation_read"),
            Json::string("report_template_read"),
            Json::string("report_template_command"),
            Json::string("report_template_run"),
            Json::string("report_export_xlsx"),
            Json::string("report_share_command"),
            Json::string("report_share_public_read"),
            Json::string("warning_observation_read"),
            Json::string("supplier_command"),
            Json::string("supplier_rescore_candidate"),
            Json::string("source_supplier_command"),
            Json::string("expense_detail_read"),
            Json::string("expense_workflow_sync_candidate"),
            Json::string("import_batch_candidate"),
            Json::string("import_project_command"),
            Json::string("source_project_command"),
            Json::string("budget_check_preview"),
            Json::string("profile_observation_read"),
            Json::string("auth_profile_command"),
            Json::string("preference_observation_read"),
            Json::string("preference_command"),
            Json::string("workflow_command"),
            Json::string("rbac_command"),
            Json::string("rbac_user_command_candidate"),
            Json::string("warning_rule_command_candidate"),
            Json::string("warning_custom_rule_command_candidate"),
            Json::string("warning_scan_preview_read"),
            Json::string("warning_custom_rule_preview_candidate"),
            Json::string("warning_ticket_command_candidate"),
            Json::string("warning_ticket_transition_candidate"),
            Json::string("admin_sys_param_command_candidate"),
            Json::string("investment_command"),
            Json::string("initiated_document_observation_read"),
            Json::string("budget_scope_observation_read"),
            Json::string("workflow_observation_read"),
            Json::string("dynamic_cost_observation_read"),
            Json::string("delivery_observation_read"),
            Json::string("receivable_read"),
            Json::string("invoice_observation_read"),
            Json::string("sales_observation_read"),
            Json::string("sales_customer_delete_candidate"),
            Json::string("tender_observation_read"),
            Json::string("supplier_dictionary_observation_read"),
            Json::string("supplier_observation_read"),
            Json::string("contract_read"),
            Json::string("payment_application_read"),
            Json::string("payment_eligibility_read"),
            Json::string("source_contract_observation_read"),
            Json::string("source_payment_observation_read"),
            Json::string("authenticated_http_read"),
            Json::string("auth_lifecycle_candidate"),
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
  let path = path_only(request.path)
  let public_share = (request.meth is @http.Get || request.meth is @http.Head) &&
    report_share_public_path(path)
  let auth_login_route = auth_lifecycle_spec(request.meth, path)
    is Some("login")
  let authorization_status = if public_share {
    if require_forwarded_tls &&
      header(request, "X-Forwarded-Proto").to_lower() != "https" {
      400
    } else {
      0
    }
  } else if auth_login_route {
    if require_forwarded_tls &&
      header(request, "X-Forwarded-Proto").to_lower() != "https" {
      400
    } else {
      0
    }
  } else {
    auth_status(request, token, require_forwarded_tls)
  }
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
  match auth_command_spec(request.meth, path) {
    Some(command_type) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = if command_type == "profile" {
        read_json_body(body_reader) catch {
          error => {
            let response = service_error_response(error)
            send_json(conn, request.meth, response.0, response.1, false)
            return
          }
        }
      } else {
        Json::object({})
      }
      let result = auth_command(command_type, body, actor, idempotency_key) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match auth_lifecycle_spec(request.meth, path) {
    Some(action) => {
      if action != "login" {
        let actor = command_actor(request, actor_signing_secret) catch {
          error => {
            let response = service_error_response(error)
            send_json(conn, request.meth, response.0, response.1, false)
            return
          }
        }
        let _ = actor
      }
      let result = auth_lifecycle_gate(action)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match ai_explain_spec(request.meth, path) {
    Some((kind, project_id)) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = if kind == "cashflow" {
        (200, cashflow_ai_explain(body))
      } else {
        investment_ai_explain_status(project_id.unwrap()) catch {
          error => service_error_response(error)
        }
      }
      // The actor is intentionally used only to enforce the signed request;
      // explanation candidates do not persist or authorize anything.
      let _ = actor
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  if plan_ai_suggest_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = actor
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = plan_ai_suggest_response(body) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  if supplier_rescore_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = actor
    let _ = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = supplier_rescore_response() catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  if ai_hub_explain_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = actor
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, ai_hub_explain_response(body), false)
    return
  }
  match ai_hub_command_spec(request.meth, path) {
    Some(command) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = ai_hub_command_gate(command)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match import_template_spec(request.meth, path) {
    Some(biz_type) => {
      match import_template_csv(biz_type) {
        Some(csv) =>
          send_bytes(
            conn,
            request.meth,
            200,
            @encoding/utf8.encode(csv),
            "text/csv; charset=utf-8",
            "attachment; filename=" + biz_type + "_template.csv",
          )
        None =>
          send_json(
            conn,
            request.meth,
            400,
            Json::object({
              "success": Json::boolean(false),
              "code": Json::number(40001),
              "message": Json::string("不支持的 bizType"),
            }),
            false,
          )
      }
      return
    }
    None => ()
  }
  match import_batch_spec(request.meth, path) {
    Some(biz_type) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = if biz_type == "project" {
        import_project_batch_command(body, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      } else if biz_type == "contract" {
        import_contract_batch_command(body, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      } else {
        import_batch_gate(biz_type)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match project_source_command_spec(request.meth, path) {
    Some((command_type, project_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = project_source_command(
        command_type, project_guid, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_customer_command_spec(request.meth, path) {
    Some((command_type, customer_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = sales_customer_command(
        command_type, customer_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_subscription_command_spec(request.meth, path) {
    Some((command_type, subscription_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = sales_subscription_command(
        command_type, subscription_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_mortgage_command_spec(request.meth, path) {
    Some((command_type, mortgage_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = sales_mortgage_command(
        command_type, mortgage_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_refund_command_spec(request.meth, path) {
    Some((command_type, refund_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = sales_refund_command(
        command_type, refund_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_customer_delete_spec(request.meth, path) {
    Some(customer_guid) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = sales_customer_delete_gate(customer_guid)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_index_upsert_spec(request.meth, path) {
    Some(import_id) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = investment_index_upsert_candidate(import_id, body) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_plan_line_import_spec(request.meth, path) {
    Some(import_id) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = investment_plan_line_import_candidate(import_id, body) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_subject_mappings_spec(request.meth, path) {
    Some(project_id) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = investment_subject_mappings_candidate(project_id, body) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_plan_line_update_spec(request.meth, path) {
    Some(line_id) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = investment_plan_line_update_candidate(line_id, body) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_excel_upload_spec(request.meth, path) {
    Some(project_id) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = investment_excel_upload_candidate(project_id)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match attachment_reextract_spec(request.meth, path) {
    Some(attachment_guid) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = attachment_reextract_response(attachment_guid) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  if attachment_upload_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = actor
    let result = attachment_upload_gate()
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  match attachment_delete_spec(request.meth, path) {
    Some(attachment_guid) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = attachment_delete_gate(attachment_guid)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  if request.meth is @http.Post && path == "/api/company/export/excel" {
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = xlsx_export(body) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_bytes(
      conn,
      request.meth,
      200,
      result.1,
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "attachment; filename=\"" + result.0 + "\"",
    )
    return
  }
  if request.meth is @http.Get || request.meth is @http.Head {
    let result = route(
      path,
      request.path,
      expected_schema_version,
      header(request, "X-Moonproj-Actor"),
    ) catch {
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
  if request.meth is @http.Post &&
    (
      path == "/api/company/ai-stats/badge/batch" ||
      path == "/api/company/source/ai-stats/badge/batch"
    ) {
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = ai_stats_badge_batch_response(body) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  if admin_sys_param_command_spec(request.meth, path) {
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
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = admin_sys_param_command(body, actor, idempotency_key) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  if warning_scan_preview_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = rbac_require_super(actor) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = warning_scan_preview_response() catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  if warning_custom_rule_preview_spec(request.meth, path) {
    let actor = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let _ = rbac_require_super(actor) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = warning_custom_rule_preview_response(body) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  match webhook_test_command_spec(request.meth, path) {
    Some(platform) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = webhook_test_delivery_command(
        platform, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match webhook_config_command_spec(request.meth, path) {
    Some(platform) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = webhook_config_command(
        body, platform, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  if webhook_overdue_scan_command_spec(request.meth, path) {
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
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = webhook_overdue_scan_command(actor, idempotency_key) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  if webhook_scan_overdue_preview_spec(request.meth, path) {
    let _ = command_actor(request, actor_signing_secret) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = webhook_scan_overdue_preview_response() catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    send_json(conn, request.meth, 200, result, false)
    return
  }
  if notification_config_spec(request.meth, path) {
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
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = notification_config_command(body, actor, idempotency_key) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  if notification_digest_dispatch_spec(request.meth, path) {
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
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = notification_digest_dispatch_command(actor, idempotency_key) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  if notification_webhook_test_spec(request.meth, path) {
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
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = notification_webhook_test_command(body, actor, idempotency_key) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  match notification_email_command_spec(request.meth, path) {
    Some((command_type, target_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = notification_email_command(
        command_type, target_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match ai_provider_test_command_spec(request.meth, path) {
    Some(command_type) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = ai_provider_test_command(
        command_type, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match notification_command_spec(request.meth, path) {
    Some((command_type, target_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = notification_command(
        command_type, target_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match preference_command_spec(request.meth, path) {
    Some((command_type, pref_key)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = preference_command(
        command_type, actor, pref_key, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match workflow_command_spec(request.meth, path) {
    Some((command_type, instance_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = workflow_command(
        command_type, instance_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match rbac_user_command_spec(request.meth, path) {
    Some((command_type, target_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = rbac_user_command(
        command_type, target_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match rbac_command_spec(request.meth, path) {
    Some((command_type, target_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = rbac_command(
        command_type, target_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match investment_command_spec(request.meth, path) {
    Some((command_type, project_id, target_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = investment_command(
        command_type, project_id, target_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match cbs_command_spec(request.meth, path) {
    Some(command_type) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = if command_type == "dict_batch_adjust" {
        cbs_batch_adjust_command(body, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      } else {
        cbs_command(command_type, body, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match budget_command_spec(request.meth, path) {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = if command_type == "auto_offset" {
        budget_auto_offset_command(expense_guid, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      } else {
        budget_command(command_type, expense_guid, body, actor, idempotency_key) catch {
          error => service_error_response(error)
        }
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  if request.meth is @http.Post && path == "/api/company/reports/templates/run" {
    let body = read_json_body(body_reader) catch {
      error => {
        let response = service_error_response(error)
        send_json(conn, request.meth, response.0, response.1, false)
        return
      }
    }
    let result = report_template_run_native(body) catch {
      error => service_error_response(error)
    }
    send_json(conn, request.meth, result.0, result.1, false)
    return
  }
  match report_template_command_spec(request.meth, path) {
    Some((command_type, template_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = report_template_command(
        command_type, template_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match report_share_command_spec(request.meth, path) {
    Some((command_type, token)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = report_share_command(
        command_type, token, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match cbs_approval_command_spec(request.meth, path) {
    Some((command_type, rule_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = cbs_approval_command(
        command_type, rule_guid, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match cbs_mutation_boundary_spec(request.meth, path) {
    Some(action) => {
      let actor = command_actor(request, actor_signing_secret) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let _ = actor
      let result = cbs_mutation_boundary_gate(action)
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match warning_ticket_command_spec(request.meth, path) {
    Some(warning_guid) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = warning_ticket_command(
        warning_guid, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match warning_ticket_transition_spec(request.meth, path) {
    Some((command_type, ticket_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = warning_ticket_transition(
        command_type, ticket_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match warning_custom_rule_command_spec(request.meth, path) {
    Some((command_type, target_code)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = warning_custom_rule_command(
        command_type, target_code, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match warning_rule_command_spec(request.meth, path) {
    Some(rule_code) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = warning_rule_config_command(
        rule_code, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match warning_command_spec(request.meth, path) {
    Some((command_type, warning_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = warning_state_command(
        command_type, warning_guid, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match invoice_command_spec(request.meth, path) {
    Some((direction, command_type, invoice_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = invoice_command(
        direction, command_type, invoice_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match sales_revenue_command_spec(request.meth, path) {
    Some((command_type, revenue_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = sales_revenue_command(
        command_type, revenue_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match tender_command_spec(request.meth, path) {
    Some((command_type, tender_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      if command_type == "split-create" || command_type == "source-split-create" {
        let result = split_command(
          body,
          actor,
          command_type == "source-split-create",
          idempotency_key,
        ) catch {
          error => service_error_response(error)
        }
        send_json(conn, request.meth, result.0, result.1, false)
        return
      }
      let source_alias = command_type == "source-create" ||
        command_type == "source-delete"
      let award_alias = command_type == "source-award"
      let state_alias = command_type == "source-state"
      let (native_command, resolved_tender_id, canonical_body) = if award_alias {
        let award = tender_source_award_request(body, actor)
        ("award", Some(award.0), award.1)
      } else if state_alias {
        let transition = tender_source_state_command(body, actor)
        (transition.0, tender_id, transition.1)
      } else {
        let native = if source_alias {
          if command_type == "source-create" {
            "create"
          } else {
            "delete"
          }
        } else {
          command_type
        }
        let canonical = if command_type == "source-create" {
          tender_create_request(body, actor, true, idempotency_key)
        } else if command_type == "create" {
          tender_create_request(body, actor, false, idempotency_key)
        } else {
          body
        }
        (native, tender_id, canonical)
      }
      let result = tender_command(
        native_command, resolved_tender_id, canonical_body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if award_alias && result.0 < 400 {
        send_json(
          conn,
          request.meth,
          result.0,
          source_tender_award_alias_result(result.1, idempotency_key),
          false,
        )
      } else if (source_alias || state_alias) && result.0 < 400 {
        send_json(
          conn,
          request.meth,
          result.0,
          source_tender_alias_result(result.1),
          false,
        )
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match marketing_command_spec(request.meth, path) {
    Some((resource, command_type, resource_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = marketing_command(
        resource, command_type, resource_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match fund_command_spec(request.meth, path) {
    Some((resource, command_type, resource_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = fund_command(
        resource, command_type, resource_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match loan_command_spec(request.meth, path) {
    Some((command_type, loan_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = loan_command(
        command_type, loan_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match delivery_command_spec(request.meth, path) {
    Some((family, command_type, aggregate_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = delivery_command(
        family, command_type, aggregate_id, body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      send_json(conn, request.meth, result.0, result.1, false)
      return
    }
    None => ()
  }
  match plan_task_command_spec(request.meth, path) {
    Some((command_type, task_id)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      if command_type == "report" {
        let report_body = match body {
          Object(fields) => {
            if json_field(body, "report_id") is None {
              fields.set("report_id", Json::string("TR-" + idempotency_key))
            }
            if json_field(body, "task_id") is None {
              fields.set("task_id", Json::string(task_id.unwrap_or("")))
            }
            Json::object(fields)
          }
          _ => body
        }
        let result = delivery_command(
          "task_report", "report", task_id, report_body, actor, idempotency_key,
        ) catch {
          error => service_error_response(error)
        }
        send_json(conn, request.meth, result.0, result.1, false)
      } else {
        let result = plan_task_command(
          command_type, task_id, body, actor, idempotency_key,
        ) catch {
          error => service_error_response(error)
        }
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match supplier_command_spec(request.meth, path) {
    Some((command_type, supplier_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let source_alias = command_type.has_prefix("source-")
      let native_command = if command_type == "source-create" {
        "create"
      } else if command_type == "source-update" {
        "update"
      } else if command_type == "source-void" {
        "void"
      } else {
        command_type
      }
      let canonical_body = if command_type == "source-create" {
        supplier_source_create_request(body, actor, idempotency_key)
      } else if command_type == "source-update" {
        supplier_source_update_request(supplier_guid.unwrap(), body, actor)
      } else if command_type == "source-void" {
        supplier_transition_request("void", supplier_guid.unwrap(), body, actor)
      } else {
        body
      }
      let result = supplier_command(
        native_command, supplier_guid, canonical_body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if source_alias && result.0 < 400 {
        let source_result = source_supplier_alias_result(result.1) catch {
          error => {
            let response = service_error_response(error)
            send_json(conn, request.meth, response.0, response.1, false)
            return
          }
        }
        send_json(conn, request.meth, result.0, source_result, false)
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match milestone_command_spec(request.meth, path) {
    Some((command_type, contract_guid, milestone_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let result = contract_milestone_command(
        if command_type == "source-create" {
          "create"
        } else {
          command_type
        },
        contract_guid,
        milestone_guid,
        body,
        actor,
        idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if result.0 < 400 {
        send_json(
          conn,
          request.meth,
          result.0,
          source_milestone_alias_result(result.1),
          false,
        )
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match dynamic_cost_command_spec(request.meth, path) {
    Some((command_type, cost_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let is_source_alias = command_type.has_prefix("source-")
      let native_command = if command_type == "source-create" {
        "create"
      } else if command_type == "source-update" {
        "update"
      } else {
        "void"
      }
      let canonical_body = if command_type == "source-create" {
        source_dynamic_cost_create_request(body, idempotency_key)
      } else if command_type == "source-update" {
        source_dynamic_cost_update_request(body)
      } else {
        body
      }
      let result = dynamic_cost_command(
        native_command, cost_guid, canonical_body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if is_source_alias && result.0 < 400 {
        send_json(
          conn,
          request.meth,
          result.0,
          source_dynamic_cost_alias_result(result.1),
          false,
        )
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match payment_command_spec(request.meth, path) {
    Some((command_type, apply_guid)) => {
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
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let body = read_json_body(body_reader) catch {
        error => {
          let response = service_error_response(error)
          send_json(conn, request.meth, response.0, response.1, false)
          return
        }
      }
      let source_alias = command_type.has_prefix("source-")
      let native_command = if command_type == "source-create" {
        "create"
      } else if command_type == "source-update" {
        "update"
      } else if command_type == "source-void" {
        "void"
      } else {
        command_type
      }
      let canonical_body = if command_type == "source-create" {
        source_payment_create_request(body, idempotency_key)
      } else if command_type == "source-update" {
        source_payment_update_request(apply_guid.unwrap(), body, actor)
      } else if command_type == "source-void" {
        payment_transition_request("void", apply_guid.unwrap(), body, actor)
      } else {
        body
      }
      let apply_code = if command_type == "source-update" ||
        command_type == "source-void" {
        match apply_guid {
          Some(id) => {
            let current = payment_items(Some(id), "all")
            if current.is_empty() {
              None
            } else {
              Some(json_text(current[0], "apply_code", ""))
            }
          }
          None => None
        }
      } else {
        None
      }
      let result = payment_command(
        native_command, apply_guid, canonical_body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if source_alias && command_type == "source-create" && result.0 < 400 {
        let created_payment = json_field(result.1, "payment_application").unwrap_or(
          Json::null(),
        )
        let created_id = json_text(created_payment, "apply_id", "")
        let submit_key = "source-payment-submit-" +
          @crypto.bytes_to_hex_string(
            @crypto.sha256(@encoding/utf8.encode(idempotency_key)),
          )[:32].to_owned()
        let submitted = payment_command(
          "submit",
          Some(created_id),
          Json::object({}),
          actor,
          submit_key,
        ) catch {
          error => service_error_response(error)
        }
        if submitted.0 >= 400 {
          send_json(conn, request.meth, submitted.0, submitted.1, false)
          return
        }
        let combined = Json::object({
          "command": json_field(result.1, "command").unwrap_or(Json::null()),
          "submit_command": json_field(submitted.1, "command").unwrap_or(
            Json::null(),
          ),
          "payment_application": json_field(submitted.1, "payment_application").unwrap_or(
            Json::null(),
          ),
          "idempotent_replay": json_field(result.1, "idempotent_replay").unwrap_or(
            Json::boolean(false),
          ),
        })
        let source_result = source_payment_alias_result(combined, None)
        send_json(conn, request.meth, result.0, source_result, false)
        return
      }
      if source_alias && result.0 < 400 {
        let source_result = source_payment_alias_result(result.1, apply_code)
        send_json(conn, request.meth, result.0, source_result, false)
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
      return
    }
    None => ()
  }
  match contract_command_spec(request.meth, path) {
    Some((command_type, contract_guid)) => {
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
      let is_source_alias = command_type.has_prefix("source-")
      let native_command = if command_type == "source-create" {
        "create"
      } else if command_type == "source-update" {
        "update"
      } else if command_type == "source-void" {
        "void"
      } else {
        command_type
      }
      let canonical_body = if command_type == "source-create" {
        source_contract_create_request(body, actor, idempotency_key)
      } else if command_type == "source-update" {
        source_contract_update_request(contract_guid.unwrap(), body, actor)
      } else if command_type == "source-void" {
        contract_transition_request("void", contract_guid.unwrap(), body, actor)
      } else {
        body
      }
      let source_contract_code = if command_type == "source-update" ||
        command_type == "source-void" {
        match contract_guid {
          Some(id) => {
            let current = contract_items(Some(id))
            if current.is_empty() {
              None
            } else {
              Some(json_text(current[0], "contract_code", ""))
            }
          }
          None => None
        }
      } else {
        None
      }
      let result = contract_command(
        native_command, contract_guid, canonical_body, actor, idempotency_key,
      ) catch {
        error => service_error_response(error)
      }
      if is_source_alias && result.0 < 400 {
        let source_result = source_contract_alias_result(
          result.1,
          source_contract_code,
        ) catch {
          error => {
            let response = service_error_response(error)
            send_json(conn, request.meth, response.0, response.1, false)
            return
          }
        }
        send_json(conn, request.meth, result.0, source_result, false)
      } else {
        send_json(conn, request.meth, result.0, result.1, false)
      }
    }
    None =>
      match expense_command_spec(request.meth, path) {
        Some((command_type, expense_guid)) => {
          let idempotency_key = header(request, "Idempotency-Key")
          if idempotency_key.is_empty() {
            send_json(
              conn,
              request.meth,
              400,
              Json::object({
                "error": Json::string("Idempotency-Key is required"),
              }),
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
