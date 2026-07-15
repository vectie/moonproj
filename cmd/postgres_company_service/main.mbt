///|
/// Native MoonBit authenticated PostgreSQL company service.
///
/// This is the first service slice in the Python-to-MoonBit migration. It
/// keeps the bearer-token and forwarded-TLS boundary, then exposes fixed
/// read-only contracts for health, summary, receipts, projections, imported
/// profile/preferences/initiated-document observations, and the source-shaped
/// cost contract/payment observations. Commands and the wider ERP route
/// families remain separate migration gates.
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
      let instance = workflow_instance_json({ record_id: instance_id, payload })
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
async fn route(
  path : String,
  query : String,
  expected_schema_version : Int,
) -> (Int, Json) raise CompanyServiceError {
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
          "read_only": Json::boolean(true),
          "capabilities": Json::array([
            Json::string("read_model"),
            Json::string("profile_observation_read"),
            Json::string("preference_observation_read"),
            Json::string("initiated_document_observation_read"),
            Json::string("budget_scope_observation_read"),
            Json::string("workflow_observation_read"),
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
