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
            Json::string("contract_read"),
            Json::string("payment_application_read"),
            Json::string("payment_eligibility_read"),
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
