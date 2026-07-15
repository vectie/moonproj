///|
/// Source-shaped budget expense commands.
///
/// These commands own local expense, detail, and four-dimension split
/// projections. Imported `vcb_expense`/detail/split rows remain read-only.
/// Budget reservation, automatic loan offset, and source workflow-engine
/// synchronization are deliberately not inferred by this boundary.

///|
async fn budget_projection_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "budget_expense" &&
    aggregate_type != "budget_expense_detail" &&
    aggregate_type != "budget_expense_split" {
    raise fail("unsupported budget projection type")
  }
  let output = run_sql(
    "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 2000",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let payload = @json.parse(decode_hex(line)) catch {
        _ => raise fail("invalid budget projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("budget projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn budget_latest_projection(
  aggregate_type : String,
  aggregate_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(aggregate_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid budget projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn budget_local_source_rows(
  aggregate_type : String,
) -> Array[SourceRow] raise CompanyServiceError {
  let payloads = budget_projection_payloads(aggregate_type)
  let result : Array[SourceRow] = []
  for payload in payloads {
    result.push({
      record_id: json_text(
        payload,
        if aggregate_type == "budget_expense" {
          "expense_guid"
        } else if aggregate_type == "budget_expense_detail" {
          "detail_guid"
        } else {
          "split_guid"
        },
        "",
      ),
      source_id: json_text(payload, "event_id", ""),
      payload,
    })
  }
  result
}

///|
fn budget_copy_fields(payload : Json) -> Map[String, Json] {
  let result : Map[String, Json] = {}
  match payload {
    Object(values) => values.each((key, value) => result.set(key, value))
    _ => ()
  }
  result
}

///|
fn budget_text(body : Json, primary : String, alternate : String) -> String {
  let value = json_text(body, primary, "").trim().to_owned()
  if value.is_empty() {
    json_text(body, alternate, "").trim().to_owned()
  } else {
    value
  }
}

///|
fn budget_required_text(
  body : Json,
  primary : String,
  alternate : String,
) -> String raise CompanyServiceError {
  let value = budget_text(body, primary, alternate)
  if value.is_empty() {
    raise reject(400, primary + " is required")
  }
  value
}

///|
fn budget_identifier(
  body : Json,
  primary : String,
  alternate : String,
) -> String raise CompanyServiceError {
  let value = budget_required_text(body, primary, alternate)
  if !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn budget_json_array(
  body : Json,
  key : String,
) -> Array[Json] raise CompanyServiceError {
  match json_field(body, key) {
    Some(Array(values)) => values
    Some(_) => raise reject(422, key + " must be an array")
    None => []
  }
}

///|
fn budget_amount_value(
  value : Json,
  key : String,
) -> Double raise CompanyServiceError {
  match value {
    Number(number, ..) if number >= 0.0 => number
    String(text) => {
      let number = parse_number(text)
      if number < 0.0 {
        raise reject(422, key + " must be non-negative")
      }
      number
    }
    _ => raise reject(422, key + " must be a decimal number")
  }
}

///|
fn budget_amount(
  body : Json,
  primary : String,
  alternate : String,
  fallback : Double,
) -> Double raise CompanyServiceError {
  match json_field(body, primary) {
    Some(value) => budget_amount_value(value, primary)
    None =>
      match json_field(body, alternate) {
        Some(value) => budget_amount_value(value, alternate)
        None => fallback
      }
  }
}

///|
async fn budget_actor(
  actor_id : String,
) -> (String, String) raise CompanyServiceError {
  match auth_current_user(actor_id) {
    Some(value) => {
      let data = json_field(value, "data").unwrap_or(Json::null())
      if !json_bool(data, "enabled", false) {
        raise reject(403, "user not found or disabled")
      }
      (json_text(data, "userId", actor_id), json_text(data, "buGuid", ""))
    }
    None => raise reject(403, "user not found or disabled")
  }
}

///|
fn budget_normalize_detail(
  value : Json,
  ordinal : Int,
  expense_id : String,
) -> Json raise CompanyServiceError {
  let summary = budget_required_text(value, "summary", "")
  let occur_date = budget_required_text(value, "occurDate", "occur_date")
  let amount = budget_amount(value, "amount", "", 0.0)
  if amount <= 0.0 {
    raise reject(422, "detail amount must be positive")
  }
  Json::object({
    "detail_guid": Json::string(expense_id + "-detail-" + ordinal.to_string()),
    "expense_guid": Json::string(expense_id),
    "summary": Json::string(summary),
    "amount": Json::number(amount),
    "occur_date": Json::string(occur_date),
  })
}

///|
fn budget_normalize_split(
  value : Json,
  ordinal : Int,
  expense_id : String,
) -> Json raise CompanyServiceError {
  let user_guid = budget_identifier(value, "userGuid", "user_guid")
  let dept_guid = budget_identifier(value, "deptGuid", "dept_guid")
  let cost_subject = budget_identifier(
    value, "costSubjectCode", "cost_subject_code",
  )
  let proceeding_guid = budget_text(value, "proceedingGuid", "proceeding_guid")
  if !proceeding_guid.is_empty() && !valid_identifier(proceeding_guid) {
    raise reject(422, "proceedingGuid contains unsupported characters")
  }
  let r_code = budget_text(value, "rCode", "r_code")
  let l3_code = budget_text(value, "l3Code", "l3_code")
  let amount = budget_amount(value, "amount", "", 0.0)
  if amount <= 0.0 {
    raise reject(422, "split amount must be positive")
  }
  Json::object({
    "split_guid": Json::string(expense_id + "-split-" + ordinal.to_string()),
    "expense_guid": Json::string(expense_id),
    "user_guid": Json::string(user_guid),
    "dept_guid": Json::string(dept_guid),
    "cost_subject_code": Json::string(cost_subject),
    "proceeding_guid": Json::string(proceeding_guid),
    "amount": Json::number(amount),
    "r_code": Json::string(r_code),
    "l3_code": Json::string(l3_code),
  })
}

///|
fn budget_command_envelope(data : Json, command : Json, replay : Bool) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "command": command,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("imported_or_command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "expense_effect": Json::boolean(true),
    "budget_effect": Json::boolean(false),
    "budget_consumption": Json::boolean(false),
    "workflow_synchronization": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn budget_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/budget/expenses" {
    return Some(("create", None))
  }
  let prefix = "/api/company/budget/expenses/"
  if path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 1 && valid_identifier(rest[0].to_owned()) {
      if request_method is @http.Put {
        return Some(("update", Some(rest[0].to_owned())))
      }
      if request_method is @http.Delete {
        return Some(("void", Some(rest[0].to_owned())))
      }
    }
    if request_method is @http.Post &&
      rest.length() == 2 &&
      valid_identifier(rest[0].to_owned()) &&
      rest[1].to_owned() == "submit-for-approval" {
      return Some(("submit", Some(rest[0].to_owned())))
    }
  }
  None
}

///|
async fn budget_command(
  command_type : String,
  expense_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (actor_user_id, actor_bu_guid) = budget_actor(actor_id)
  let (request, aggregate_id, result_data) = if command_type == "create" {
    let subject = budget_required_text(body, "subject", "")
    let apply_dept_guid = budget_identifier(
      body, "applyDeptGuid", "apply_dept_guid",
    )
    let apply_date = budget_required_text(body, "applyDate", "apply_date")
    let expense_amount = budget_amount(
      body, "expenseAmount", "expense_amount", 0.0,
    )
    let offset_amount = budget_amount(
      body, "offsetAmount", "offset_amount", 0.0,
    )
    if expense_amount <= 0.0 || offset_amount > expense_amount {
      raise reject(422, "expenseAmount and offsetAmount are invalid")
    }
    let requested = budget_text(body, "expenseGuid", "expense_guid")
    let id = if requested.is_empty() {
      "budget-expense-" + idempotency_key
    } else {
      requested
    }
    if !valid_identifier(id) {
      raise reject(422, "expenseGuid contains unsupported characters")
    }
    let details_raw = budget_json_array(body, "details")
    let splits_raw = budget_json_array(body, "splits")
    if splits_raw.is_empty() {
      raise reject(400, "splits must contain at least one item")
    }
    let details : Array[Json] = []
    for index in 0..<details_raw.length() {
      details.push(budget_normalize_detail(details_raw[index], index + 1, id))
    }
    let splits : Array[Json] = []
    let mut split_total = 0.0
    for index in 0..<splits_raw.length() {
      let normalized = budget_normalize_split(splits_raw[index], index + 1, id)
      split_total = split_total + json_number(normalized, "amount", 0.0)
      splits.push(normalized)
    }
    if (split_total - (expense_amount - offset_amount)).abs() > 0.001 {
      raise reject(400, "split amount total does not equal payable amount")
    }
    let expense_code = budget_text(body, "expenseCode", "expense_code")
    let code = if expense_code.is_empty() {
      "BX-" + idempotency_key
    } else {
      expense_code
    }
    let request = Json::object({
      "command_type": Json::string(command_type),
      "expense_guid": Json::string(id),
      "expense_code": Json::string(code),
      "subject": Json::string(subject),
      "apply_state": Json::string("Draft"),
      "pay_state": Json::string("未支付"),
      "expense_amount": Json::number(expense_amount),
      "offset_amount": Json::number(offset_amount),
      "pay_amount": Json::number(expense_amount - offset_amount),
      "apply_dept_guid": Json::string(apply_dept_guid),
      "applied_by": Json::string(actor_user_id),
      "apply_date": Json::string(apply_date),
      "pay_unit": Json::string(budget_text(body, "payUnit", "pay_unit")),
      "bu_guid": Json::string(actor_bu_guid),
      "details": Json::array(details),
      "splits": Json::array(splits),
      "actor_id": Json::string(actor_id),
    })
    (
      request,
      id,
      Json::object({
        "expenseGuid": Json::string(id),
        "expenseCode": Json::string(code),
        "applyState": Json::string("Draft"),
      }),
    )
  } else {
    let id = match expense_guid {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "expenseGuid is required")
    }
    let request = Json::object({
      "command_type": Json::string(command_type),
      "expense_guid": Json::string(id),
      "subject": json_field(body, "subject").unwrap_or(
        json_field(body, "summary").unwrap_or(Json::null()),
      ),
      "expense_amount": json_field(body, "expenseAmount").unwrap_or(
        json_field(body, "expense_amount").unwrap_or(Json::null()),
      ),
      "offset_amount": json_field(body, "offsetAmount").unwrap_or(
        json_field(body, "offset_amount").unwrap_or(Json::null()),
      ),
      "pay_unit": json_field(body, "payUnit").unwrap_or(
        json_field(body, "pay_unit").unwrap_or(Json::null()),
      ),
      "reason": Json::string(json_text(body, "reason", "")),
      "actor_id": Json::string(actor_id),
    })
    (
      request,
      id,
      Json::object({
        "expenseGuid": Json::string(id),
        "applyState": Json::string(
          if command_type == "submit" {
            "Approving"
          } else if command_type == "void" {
            "Voided"
          } else {
            "Draft"
          },
        ),
      }),
    )
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        budget_command_envelope(
          json_field(existing, "result").unwrap_or(result_data),
          existing,
          true,
        ),
      )
    }
    None => ()
  }
  let imported = raw_source_rows("vcb_expense", 1000)
  if command_type == "create" &&
    imported.any(fn(row) {
      expense_id(row) == aggregate_id &&
      json_field(row.payload, "deleted_at") is None
    }) {
    raise reject(409, "imported expense rows are read-only")
  }
  let current = budget_latest_projection("budget_expense", aggregate_id)
  if command_type == "create" && current is Some(_) {
    raise reject(409, "budget expense already exists")
  }
  let current_payload = match current {
    Some((value, _)) => value
    None if command_type != "create" =>
      raise reject(404, "budget expense not found")
    None => Json::null()
  }
  if command_type != "create" {
    let state = json_text(current_payload, "apply_state", "")
    let owner = json_text(current_payload, "applied_by", "")
    if (command_type == "update" || command_type == "void") &&
      owner != actor_user_id {
      raise reject(403, "only the expense applicant may modify this expense")
    }
    if command_type == "update" && state != "Draft" {
      raise reject(409, "only Draft expenses may be updated")
    }
    if command_type == "submit" && (state != "Draft" || owner != actor_user_id) {
      raise reject(409, "only the applicant may submit a Draft expense")
    }
    if command_type == "void" && state != "Draft" && state != "Rejected" {
      raise reject(409, "only Draft or Rejected expenses may be voided")
    }
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_revision = if command_type == "create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "budget-expense:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_state = if command_type == "submit" {
    "Approving"
  } else if command_type == "void" {
    "Voided"
  } else if command_type == "create" {
    "Draft"
  } else {
    "Draft"
  }
  let next_payload = if command_type == "create" {
    let fields = budget_copy_fields(request)
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("created_at", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "update" {
    let fields = budget_copy_fields(current_payload)
    match json_field(request, "subject") {
      Some(value) if value is String(_) => fields.set("subject", value)
      _ => ()
    }
    match json_field(request, "expense_amount") {
      Some(value) if value is Number(_, ..) || value is String(_) => {
        fields.set("expense_amount", value)
        let offset = json_number(current_payload, "offset_amount", 0.0)
        fields.set(
          "pay_amount",
          Json::number(
            json_number(
              request,
              "expense_amount",
              json_number(current_payload, "expense_amount", 0.0),
            ) -
            offset,
          ),
        )
      }
      _ => ()
    }
    match json_field(request, "offset_amount") {
      Some(value) if value is Number(_, ..) || value is String(_) => {
        fields.set("offset_amount", value)
        let amount = json_number(current_payload, "expense_amount", 0.0)
        fields.set(
          "pay_amount",
          Json::number(amount - json_number(request, "offset_amount", 0.0)),
        )
      }
      _ => ()
    }
    match json_field(request, "pay_unit") {
      Some(value) if value is String(_) => fields.set("pay_unit", value)
      _ => ()
    }
    fields.set("apply_state", Json::string("Draft"))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else {
    let fields = budget_copy_fields(current_payload)
    fields.set("apply_state", Json::string(next_state))
    fields.set(
      "state",
      Json::string(if command_type == "void" { "deleted" } else { "active" }),
    )
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    if command_type == "void" {
      fields.set("deleted_at", Json::string(event_id))
    }
    Json::object(fields)
  }
  let result = Json::object({
    "expenseGuid": Json::string(aggregate_id),
    "expenseCode": Json::string(json_text(next_payload, "expense_code", "")),
    "applyState": Json::string(
      json_text(next_payload, "apply_state", next_state),
    ),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "expense_effect": Json::boolean(true),
    "budget_effect": Json::boolean(false),
    "budget_consumption": Json::boolean(false),
    "workflow_synchronization": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("budget_expense"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("budget_expense"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("budget_expense." + command_type),
    "aggregate_type": Json::string("budget_expense"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(next_revision.to_double()),
    "expense_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
  })
  let mut extra_sql = ""
  if command_type == "create" {
    match json_field(request, "details") {
      Some(Array(values)) =>
        for value in values {
          let detail_id = json_text(value, "detail_guid", "")
          let detail_event = event_id + ":detail:" + detail_id
          let fields = budget_copy_fields(value)
          fields.set("source_kind", Json::string("command"))
          fields.set("event_id", Json::string(detail_event))
          extra_sql = extra_sql +
            " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('budget_expense_detail'," +
            @postgres.sql_literal(detail_id) +
            ",1," +
            @postgres.sql_literal(Json::object(fields).stringify()) +
            "::jsonb," +
            @postgres.sql_literal(detail_event) +
            ") ON CONFLICT DO NOTHING;"
        }
      _ => ()
    }
    match json_field(request, "splits") {
      Some(Array(values)) =>
        for value in values {
          let split_id = json_text(value, "split_guid", "")
          let split_event = event_id + ":split:" + split_id
          let fields = budget_copy_fields(value)
          fields.set("source_kind", Json::string("command"))
          fields.set("event_id", Json::string(split_event))
          extra_sql = extra_sql +
            " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('budget_expense_split'," +
            @postgres.sql_literal(split_id) +
            ",1," +
            @postgres.sql_literal(Json::object(fields).stringify()) +
            "::jsonb," +
            @postgres.sql_literal(split_event) +
            ") ON CONFLICT DO NOTHING;"
        }
      _ => ()
    }
  }
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('budget_expense'," +
    @postgres.sql_literal(aggregate_id) +
    "," +
    next_revision.to_string() +
    "," +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING;" +
    extra_sql +
    " INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "create" {
      201
    } else {
      200
    },
    budget_command_envelope(result, command, false),
  )
}
