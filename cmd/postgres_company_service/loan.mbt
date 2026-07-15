///|
/// Native employee-advance/loan read and command boundary.
fn loan_number(value : Json, key : String, fallback : Double) -> Double {
  match json_field(value, key) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    _ => fallback
  }
}

///|
fn loan_integer(
  value : Json,
  key : String,
  required : Bool,
) -> Int raise CompanyServiceError {
  let number = match json_field(value, key) {
    Some(Number(value, ..)) => value
    Some(String(text)) => parse_number(text.trim().to_owned())
    None if !required => 0.0
    _ => raise reject(422, key + " must be an integer amount in minor units")
  }
  if number != number || number != number.to_int().to_double() {
    raise reject(422, key + " must be an integer amount in minor units")
  }
  let result = number.to_int()
  if required && result <= 0 {
    raise reject(422, key + " must be > 0")
  }
  result
}

///|
fn loan_amount_minor(
  body : Json,
  key : String,
  required : Bool,
) -> Int raise CompanyServiceError {
  match json_field(body, key) {
    Some(_) => loan_integer(body, key, required)
    None if key == "amount_minor" =>
      match json_field(body, "loan_amount") {
        Some(Number(number, ..)) => {
          let minor = (number * 100.0 + 0.5).to_int()
          if minor <= 0 {
            raise reject(422, "loan_amount must be > 0")
          }
          minor
        }
        Some(String(number)) => {
          let minor = (parse_number(number.trim().to_owned()) * 100.0 + 0.5).to_int()
          if minor <= 0 {
            raise reject(422, "loan_amount must be > 0")
          }
          minor
        }
        None if !required => 0
        _ => raise reject(422, "loan_amount must be a decimal number")
      }
    None if !required => 0
    _ => raise reject(422, key + " is required")
  }
}

///|
fn loan_required_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, key) {
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, key + " is required")
  }
  if value.is_empty() {
    raise reject(422, key + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn loan_optional_text(
  body : Json,
  key : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match json_field(body, key) {
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    None | Some(Null) => ""
    _ => raise reject(422, key + " must be text")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, key + " contains unsupported characters")
  }
  value
}

///|
fn loan_date(body : Json, key : String) -> String raise CompanyServiceError {
  let value = loan_required_text(body, key, false)
  if value.length() != 10 || value[4:5] != "-" || value[7:8] != "-" {
    raise reject(422, key + " must be an ISO date")
  }
  value
}

///|
fn loan_evidence(body : Json) -> Json raise CompanyServiceError {
  match json_field(body, "evidence_ids") {
    None => Json::array([])
    Some(Array(values)) => {
      let result : Array[Json] = []
      for value in values {
        match value {
          String(text) if valid_identifier(text) =>
            result.push(Json::string(text))
          _ => raise reject(422, "evidence_ids must be identifier strings")
        }
      }
      Json::array(result)
    }
    _ => raise reject(422, "evidence_ids must be identifier strings")
  }
}

///|
fn loan_authority(
  body : Json,
  actor_id : String,
  principal_id : String,
  employee_id : String,
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
  if json_text(grant, "principal_id", "") != principal_id {
    raise reject(403, "authority grant principal does not match loan")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(403, "authority grant actor does not match signed actor")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "authority grant must allow " + capability)
  }
  let scope = "employee:" + employee_id
  if json_text(grant, "scope", "") != scope {
    raise reject(403, "authority grant scope must be employee-scoped")
  }
  let max_amount = loan_integer(grant, "max_amount_minor", true)
  if max_amount < amount_minor {
    raise reject(403, "authority grant amount is exceeded")
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
async fn loan_projection_latest(
  loan_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'employee_advance' AND aggregate_id = " +
    @postgres.sql_literal(loan_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid employee advance projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn loan_projection_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
    "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, source_event_id, revision " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'employee_advance' " +
    "AND payload->>'source_kind' = 'command' ORDER BY aggregate_id, revision DESC) latest " +
    "ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid employee advance projection JSON")
      }
      match payload {
        Object(payload_fields) => {
          payload_fields.set(
            "__revision",
            Json::number(parse_decimal(row[3]).to_double()),
          )
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[2]),
            payload: Json::object(payload_fields),
          })
        }
        _ => raise fail("employee advance projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn loan_offset_projection_rows() -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
    "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, source_event_id, revision " +
    "FROM company_aggregate_projection WHERE aggregate_type = 'loan_offset' " +
    "AND payload->>'source_kind' = 'command' ORDER BY aggregate_id, revision DESC) latest " +
    "ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid loan offset projection JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[2]),
            payload,
          })
        _ => raise fail("loan offset projection payload is not an object")
      }
    }
  }
  result
}

///|
fn loan_offset_items(
  loan_id : String,
  imported : Array[SourceRow],
  command : Array[SourceRow],
  users : Array[SourceRow],
) -> Array[Json] {
  let result : Array[Json] = []
  for row in imported {
    let payload = row.payload
    if json_text(payload, "loan_guid", "") == loan_id {
      let operator_id = json_text(payload, "operator_guid", "")
      result.push(
        Json::object({
          "offset_id": Json::string(
            json_text(payload, "offset_guid", row.record_id),
          ),
          "offset_amount": Json::number(
            loan_number(payload, "offset_amount", 0.0),
          ),
          "offset_date": Json::string(json_text(payload, "offset_date", "")),
          "related_expense_id": Json::string(
            json_text(payload, "related_expense_guid", ""),
          ),
          "remark": Json::string(json_text(payload, "remark", "")),
          "operator_name": Json::string(
            project_task_user_name(users, operator_id),
          ),
          "source_kind": Json::string("imported"),
          "source_id": Json::string(row.source_id),
        }),
      )
    }
  }
  for row in command {
    let payload = row.payload
    if json_text(payload, "loan_id", "") == loan_id {
      let amount_minor = json_int(payload, "offset_amount_minor", 0)
      result.push(
        Json::object({
          "offset_id": Json::string(row.record_id),
          "offset_amount": Json::number(amount_minor.to_double() / 100.0),
          "offset_date": Json::string(json_text(payload, "offset_date", "")),
          "related_expense_id": Json::string(
            json_text(payload, "related_expense_id", ""),
          ),
          "remark": Json::string(json_text(payload, "remark", "")),
          "operator_name": Json::string(json_text(payload, "operator_id", "")),
          "source_kind": Json::string("command"),
          "source_id": Json::string(row.source_id),
        }),
      )
    }
  }
  result.sort_by(fn(left, right) {
    json_text(right, "offset_date", "").lexical_compare(
      json_text(left, "offset_date", ""),
    )
  })
  result
}

///|
async fn loan_item(
  payload : Json,
  record_id : String,
  source_id : String,
  source_kind : String,
  users : Array[SourceRow],
  units : Array[SourceRow],
  projects : Array[SourceRow],
  imported_offsets : Array[SourceRow],
  command_offsets : Array[SourceRow],
) -> Json raise CompanyServiceError {
  let command = source_kind == "command"
  let loan_id = if command {
    record_id
  } else {
    json_text(payload, "loan_guid", record_id)
  }
  let employee_id = if command {
    json_text(payload, "employee_id", json_text(payload, "applied_by", ""))
  } else {
    json_text(payload, "applied_by", "")
  }
  let dept_id = json_text(payload, "apply_dept_guid", "")
  let project_id = json_text(
    payload,
    if command {
      "proj_guid"
    } else {
      "proj_guid"
    },
    "",
  )
  let amount_minor = if command {
    json_int(payload, "loan_amount_minor", 0)
  } else {
    (loan_number(payload, "loan_amount", 0.0) * 100.0 + 0.5).to_int()
  }
  let balance_minor = if command {
    json_int(payload, "balance_amount_minor", 0)
  } else {
    (loan_number(payload, "balance_amount", 0.0) * 100.0 + 0.5).to_int()
  }
  let remain_minor = if command {
    json_int(payload, "remain_amount_minor", amount_minor - balance_minor)
  } else {
    let value = loan_number(payload, "remain_amount", -1.0)
    if value < 0.0 {
      amount_minor - balance_minor
    } else {
      (value * 100.0 + 0.5).to_int()
    }
  }
  let offsets = loan_offset_items(
    loan_id, imported_offsets, command_offsets, users,
  )
  Json::object({
    "loan_id": Json::string(loan_id),
    "loan_code": Json::string(json_text(payload, "loan_code", loan_id)),
    "subject": Json::string(json_text(payload, "subject", "")),
    "apply_state": Json::string(
      if command {
        json_text(payload, "apply_state", "Draft")
      } else {
        json_text(payload, "apply_state", "")
      },
    ),
    "loan_amount": Json::number(amount_minor.to_double() / 100.0),
    "balance_amount": Json::number(balance_minor.to_double() / 100.0),
    "remain_amount": Json::number(remain_minor.to_double() / 100.0),
    "amount_display": Json::string(money_display(amount_minor)),
    "remain_amount_display": Json::string(money_display(remain_minor)),
    "applied_by": Json::string(employee_id),
    "applied_by_name": Json::string(
      if command {
        employee_id
      } else {
        project_task_user_name(users, employee_id)
      },
    ),
    "apply_dept_guid": Json::string(dept_id),
    "apply_dept_name": Json::string(
      if command {
        dept_id
      } else {
        unit_name(units, dept_id)
      },
    ),
    "project_id": Json::string(project_id),
    "project_name": Json::string(
      if command {
        project_id
      } else {
        project_name(projects, project_id)
      },
    ),
    "apply_date": Json::string(json_text(payload, "apply_date", "")),
    "pay_unit": Json::string(json_text(payload, "pay_unit", "")),
    "process_instance_id": Json::string(
      json_text(payload, "process_instance_guid", ""),
    ),
    "offsets": Json::array(offsets),
    "source_kind": Json::string(source_kind),
    "source_id": Json::string(source_id),
    "source_table": Json::string(
      if command {
        "employee_advance"
      } else {
        "vcb_loan_simple"
      },
    ),
    "currency": Json::string(json_text(payload, "currency", "CNY")),
  })
}

///|
fn project_name(projects : Array[SourceRow], project_id : String) -> String {
  for row in projects {
    if json_text(row.payload, "proj_guid", row.record_id) == project_id {
      return json_text(row.payload, "proj_name", project_id)
    }
  }
  project_id
}

///|
async fn loan_read_items(
  loan_id : String?,
  apply_state : String?,
) -> Array[Json] raise CompanyServiceError {
  match loan_id {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid loan_id")
    _ => ()
  }
  match apply_state {
    Some(value) if value.length() > 64 =>
      raise reject(422, "invalid apply_state")
    _ => ()
  }
  let raw_loans = raw_source_rows("vcb_loan_simple", 500)
  let raw_offsets = raw_source_rows("cb_loan_offset", 500)
  let users = raw_source_rows("sys_user", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let projects = raw_source_rows("ep_project", 500)
  let command_offsets = loan_offset_projection_rows()
  let result : Array[Json] = []
  for row in raw_loans {
    let item = loan_item(
      row.payload,
      row.record_id,
      row.source_id,
      "imported",
      users,
      units,
      projects,
      raw_offsets,
      command_offsets,
    )
    let id_ok = match loan_id {
      Some(value) => json_text(item, "loan_id", "") == value
      None => true
    }
    let state_ok = match apply_state {
      Some(value) => json_text(item, "apply_state", "") == value
      None => true
    }
    if id_ok && state_ok {
      result.push(item)
    }
  }
  for row in loan_projection_rows() {
    let item = loan_item(
      row.payload,
      row.record_id,
      row.source_id,
      "command",
      users,
      units,
      projects,
      raw_offsets,
      command_offsets,
    )
    let state = json_text(item, "apply_state", "Draft")
    let id_ok = match loan_id {
      Some(value) => json_text(item, "loan_id", "") == value
      None => true
    }
    let state_ok = match apply_state {
      Some(value) => state == value
      None => true
    }
    if id_ok && state_ok && state != "deleted" {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    json_text(right, "apply_date", "").lexical_compare(
      json_text(left, "apply_date", ""),
    )
  })
  result
}

///|
async fn loan_read_response(
  loan_id : String?,
  apply_state : String?,
) -> Json raise CompanyServiceError {
  Json::object({ "items": Json::array(loan_read_items(loan_id, apply_state)) })
}

///|
async fn loan_detail_response(
  loan_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let items = loan_read_items(Some(loan_id), None)
  if items.is_empty() {
    return (404, Json::object({ "error": Json::string("loan not found") }))
  }
  let item = items[0]
  let offsets = json_field(item, "offsets").unwrap_or(Json::array([]))
  (200, Json::object({ "loan": item, "offsets": offsets }))
}

///|
async fn loan_imported_exists(
  loan_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("vcb_loan_simple", 500) {
    if json_text(row.payload, "loan_guid", row.record_id) == loan_id ||
      row.record_id == loan_id {
      return true
    }
  }
  false
}

///|
async fn loan_command_request(
  command_type : String,
  loan_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json, Bool, String, String, Json?) raise CompanyServiceError {
  if command_type == "sync_from_workflow" {
    raise reject(
      409, "workflow synchronization is gated until wf_process_instance source rows are available",
    )
  }
  if command_type == "create" {
    let requested = loan_optional_text(body, "loan_id", true)
    let id = if requested.is_empty() {
      "loan-" + idempotency_key
    } else {
      requested
    }
    let employee_id = loan_required_text(body, "employee_id", true)
    let principal_id = loan_required_text(body, "principal_id", true)
    let scope = loan_required_text(body, "scope", true)
    if scope != "employee:" + employee_id {
      raise reject(422, "scope must equal employee:<employee_id>")
    }
    let amount_minor = loan_amount_minor(body, "amount_minor", true)
    let authority = loan_authority(
      body, actor_id, principal_id, employee_id, "advance:create", amount_minor,
    )
    let currency = match json_field(body, "currency") {
      None => "CNY"
      _ => loan_required_text(body, "currency", true).to_upper()
    }
    if currency.length() != 3 {
      raise reject(422, "currency must be a three-letter code")
    }
    let loan_code = match json_field(body, "loan_code") {
      None => "JK-" + id
      _ => loan_required_text(body, "loan_code", false)
    }
    let request = Json::object({
      "command_type": Json::string("create"),
      "loan_id": Json::string(id),
      "loan_code": Json::string(loan_code),
      "subject": Json::string(loan_required_text(body, "subject", false)),
      "employee_id": Json::string(employee_id),
      "principal_id": Json::string(principal_id),
      "scope": Json::string(scope),
      "currency": Json::string(currency),
      "loan_amount_minor": Json::number(amount_minor.to_double()),
      "balance_amount_minor": Json::number(0),
      "remain_amount_minor": Json::number(amount_minor.to_double()),
      "apply_dept_guid": Json::string(
        loan_required_text(body, "apply_dept_guid", true),
      ),
      "applied_by": Json::string(actor_id),
      "apply_date": Json::string(loan_date(body, "apply_date")),
      "pay_unit": Json::string(loan_optional_text(body, "pay_unit", false)),
      "proj_guid": Json::string(loan_optional_text(body, "proj_guid", true)),
      "process_instance_guid": Json::string(""),
      "evidence_ids": loan_evidence(body),
      "authority": authority,
      "state": Json::string("Draft"),
      "source_kind": Json::string("command"),
    })
    return (id, request, true, "", "Draft", None)
  }
  let id = match loan_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "loan_id is required")
  }
  let current = match loan_projection_latest(id) {
    Some((payload, _)) => payload
    None => {
      if loan_imported_exists(id) {
        raise reject(
          409, "imported loans are read-only; create a local loan first",
        )
      }
      raise reject(404, "loan not found")
    }
  }
  let current_state = json_text(current, "apply_state", "Draft")
  let employee_id = json_text(
    current,
    "employee_id",
    json_text(current, "applied_by", ""),
  )
  if (
      command_type == "submit" ||
      command_type == "update" ||
      command_type == "void"
    ) &&
    json_text(current, "applied_by", "") != actor_id {
    raise reject(403, "only the loan applicant may change this loan")
  }
  if command_type == "submit" && current_state != "Draft" {
    raise reject(
      409,
      "loan transition submit requires Draft, found " + current_state,
    )
  }
  if command_type == "offset" && current_state != "Approved" {
    raise reject(
      409,
      "loan transition offset requires Approved, found " + current_state,
    )
  }
  if command_type == "update" && current_state != "Draft" {
    raise reject(
      409,
      "loan transition update requires Draft, found " + current_state,
    )
  }
  if command_type == "void" &&
    current_state != "Draft" &&
    current_state != "Rejected" {
    raise reject(
      409,
      "loan transition void requires Draft,Rejected, found " + current_state,
    )
  }
  let base_request = Json::object({
    "command_type": Json::string(command_type),
    "loan_id": Json::string(id),
    "actor_id": Json::string(actor_id),
  })
  if command_type == "offset" {
    let principal_id = json_text(current, "principal_id", "")
    let amount_minor = loan_amount_minor(body, "offset_amount_minor", true)
    let remain_minor = json_int(current, "remain_amount_minor", 0)
    if amount_minor > remain_minor {
      raise reject(422, "offset amount exceeds remaining loan balance")
    }
    let authority = loan_authority(
      body, actor_id, principal_id, employee_id, "advance:offset", amount_minor,
    )
    match base_request {
      Object(fields) => {
        fields.set("offset_id", Json::string("offset-" + idempotency_key))
        fields.set(
          "offset_amount_minor",
          Json::number(amount_minor.to_double()),
        )
        fields.set("offset_date", Json::string(loan_date(body, "offset_date")))
        fields.set(
          "related_expense_id",
          Json::string(loan_optional_text(body, "related_expense_id", true)),
        )
        fields.set(
          "remark",
          Json::string(loan_optional_text(body, "remark", false)),
        )
        fields.set("authority", authority)
      }
      _ => ()
    }
    return (id, base_request, false, "Approved", "Approved", Some(current))
  }
  if command_type == "update" {
    let changes : Map[String, Json] = {}
    if json_field(body, "subject") is Some(_) {
      changes.set(
        "subject",
        Json::string(loan_required_text(body, "subject", false)),
      )
    }
    if json_field(body, "pay_unit") is Some(_) {
      changes.set(
        "pay_unit",
        Json::string(loan_optional_text(body, "pay_unit", false)),
      )
    }
    if json_field(body, "proj_guid") is Some(_) {
      changes.set(
        "proj_guid",
        Json::string(loan_optional_text(body, "proj_guid", true)),
      )
    }
    if json_field(body, "amount_minor") is Some(_) ||
      json_field(body, "loan_amount") is Some(_) {
      let amount_minor = loan_amount_minor(body, "amount_minor", true)
      let balance_minor = json_int(current, "balance_amount_minor", 0)
      if amount_minor <= balance_minor {
        raise reject(422, "loan amount must exceed already offset balance")
      }
      changes.set("loan_amount_minor", Json::number(amount_minor.to_double()))
      changes.set(
        "remain_amount_minor",
        Json::number((amount_minor - balance_minor).to_double()),
      )
    }
    if changes.is_empty() {
      raise reject(422, "update requires at least one mutable field")
    }
    match base_request {
      Object(fields) => fields.set("changes", Json::object(changes))
      _ => ()
    }
    return (id, base_request, false, "Draft", "Draft", Some(current))
  }
  if command_type == "void" {
    match base_request {
      Object(fields) =>
        fields.set(
          "reason",
          Json::string(loan_optional_text(body, "reason", false)),
        )
      _ => ()
    }
    return (id, base_request, false, "Draft,Rejected", "Voided", Some(current))
  }
  (id, base_request, false, "Draft", "Approving", Some(current))
}

///|
fn loan_merge_payload(
  base : Json,
  extra : Json,
) -> Json raise CompanyServiceError {
  match (base, extra) {
    (Object(base_fields), Object(extra_fields)) => {
      for key, value in extra_fields {
        base_fields.set(key, value)
      }
      Json::object(base_fields)
    }
    _ => raise fail("loan projection payload must be an object")
  }
}

///|
async fn loan_command(
  command_type : String,
  loan_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["create", "submit", "offset", "sync_from_workflow", "update", "void"].contains(
      command_type,
    ) {
    raise reject(404, "unsupported loan command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request, create_mode, _, next_state, current_from_request) = loan_command_request(
    command_type, loan_id, body, actor_id, idempotency_key,
  )
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
      (
        200,
        Json::object({
          "command": existing,
          "loan": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => {
      if create_mode &&
        (loan_imported_exists(id) || loan_projection_latest(id) is Some(_)) {
        raise reject(409, "loan already exists")
      }
      let current_payload = current_from_request.unwrap_or(Json::null())
      let current_revision = match loan_projection_latest(id) {
        Some((_, revision)) => revision
        None => 0
      }
      let next_revision = if create_mode { 1 } else { current_revision + 1 }
      let event_id = "employee_advance:" + command_type + ":" + idempotency_key
      let command_source = "moonproj:command:" + idempotency_key
      let audit_id = event_id + ":audit"
      // `loan_merge_payload` mutates its base object; preserve the canonical
      // request before building the next aggregate projection so replay
      // compares the caller's request rather than the derived state.
      let request_for_receipt = @json.parse(request.stringify()) catch {
        _ => raise fail("invalid loan command request JSON")
      }
      let next_payload_base = if create_mode {
        loan_merge_payload(
          request,
          Json::object({
            "apply_state": Json::string("Draft"),
            "source_kind": Json::string("command"),
            "event_id": Json::string(event_id),
            "updated_by": Json::string(actor_id),
          }),
        )
      } else if command_type == "offset" {
        let amount_minor = json_int(request, "offset_amount_minor", 0)
        let balance_minor = json_int(current_payload, "balance_amount_minor", 0) +
          amount_minor
        let remain_minor = json_int(current_payload, "loan_amount_minor", 0) -
          balance_minor
        loan_merge_payload(
          current_payload,
          Json::object({
            "balance_amount_minor": Json::number(balance_minor.to_double()),
            "remain_amount_minor": Json::number(remain_minor.to_double()),
            "apply_state": Json::string("Approved"),
            "event_id": Json::string(event_id),
            "updated_by": Json::string(actor_id),
          }),
        )
      } else if command_type == "update" {
        let changes = json_field(request, "changes").unwrap_or(Json::object({}))
        loan_merge_payload(
          loan_merge_payload(current_payload, changes),
          Json::object({
            "apply_state": Json::string("Draft"),
            "event_id": Json::string(event_id),
            "updated_by": Json::string(actor_id),
          }),
        )
      } else {
        loan_merge_payload(
          current_payload,
          Json::object({
            "apply_state": Json::string(next_state),
            "event_id": Json::string(event_id),
            "updated_by": Json::string(actor_id),
            "reason": Json::string(json_text(request, "reason", "")),
          }),
        )
      }
      let result = Json::object({
        "loan_id": Json::string(id),
        "state": Json::string(next_state),
        "revision": Json::number(next_revision.to_double()),
        "event_id": Json::string(event_id),
        "audit_id": Json::string(audit_id),
        "actor_id": Json::string(actor_id),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      })
      let result = if command_type == "offset" {
        match result {
          Object(fields) => {
            fields.set(
              "offset_id",
              Json::string(json_text(request, "offset_id", "")),
            )
            fields.set(
              "balance_amount_minor",
              Json::number(
                json_int(next_payload_base, "balance_amount_minor", 0).to_double(),
              ),
            )
            fields.set(
              "remain_amount_minor",
              Json::number(
                json_int(next_payload_base, "remain_amount_minor", 0).to_double(),
              ),
            )
            Json::object(fields)
          }
          _ => result
        }
      } else {
        result
      }
      let command_payload = Json::object({
        "kind": Json::string("company_command"),
        "command_family": Json::string("loan"),
        "command_type": Json::string(command_type),
        "idempotency_key": Json::string(idempotency_key),
        "aggregate_type": Json::string("employee_advance"),
        "aggregate_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "request": request_for_receipt,
        "result": result,
      })
      let audit_payload = Json::object({
        "audit_id": Json::string(audit_id),
        "action": Json::string("loan." + command_type),
        "aggregate_type": Json::string("employee_advance"),
        "aggregate_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "event_id": Json::string(event_id),
        "state": Json::string(next_state),
        "revision": Json::number(next_revision.to_double()),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      })
      let offset_sql = if command_type == "offset" {
        " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('loan_offset', " +
        @postgres.sql_literal(json_text(request, "offset_id", "")) +
        ", 1, " +
        @postgres.sql_literal(request.stringify()) +
        "::jsonb || jsonb_build_object('loan_id', " +
        @postgres.sql_literal(id) +
        ", 'source_kind', 'command', 'source_id', " +
        @postgres.sql_literal(event_id) +
        "), " +
        @postgres.sql_literal(event_id + ":offset") +
        ") ON CONFLICT DO NOTHING;"
      } else {
        ""
      }
      let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
        @postgres.sql_literal(event_id) +
        ", 4, " +
        @postgres.sql_literal(command_payload.stringify()) +
        "::jsonb, " +
        @postgres.sql_literal(command_source) +
        ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('employee_advance', " +
        @postgres.sql_literal(id) +
        ", " +
        next_revision.to_string() +
        ", " +
        @postgres.sql_literal(next_payload_base.stringify()) +
        "::jsonb, " +
        @postgres.sql_literal(event_id) +
        ") ON CONFLICT DO NOTHING;" +
        offset_sql +
        " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
        @postgres.sql_literal(audit_id) +
        ", 4, " +
        @postgres.sql_literal(audit_payload.stringify()) +
        "::jsonb, " +
        @postgres.sql_literal("moonproj:audit:" + event_id) +
        ") ON CONFLICT DO NOTHING; COMMIT;"
      let _ = run_sql(sql)
      (
        if create_mode {
          201
        } else {
          200
        },
        Json::object({
          "command": command_payload,
          "loan": result,
          "idempotent_replay": Json::boolean(false),
        }),
      )
    }
  }
}

///|
fn loan_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/loans" {
    return Some(("create", None))
  }
  let prefix = "/api/company/loans/"
  if path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = rest[1].to_owned()
      if request_method is @http.Post {
        if command == "submit-for-approval" {
          return Some(("submit", Some(rest[0].to_owned())))
        }
        if command == "offset" {
          return Some(("offset", Some(rest[0].to_owned())))
        }
        if command == "sync-from-workflow" {
          return Some(("sync_from_workflow", Some(rest[0].to_owned())))
        }
        if command == "update" {
          return Some(("update", Some(rest[0].to_owned())))
        }
        if command == "void" {
          return Some(("void", Some(rest[0].to_owned())))
        }
      }
    }
    if rest.length() == 1 && valid_identifier(rest[0].to_owned()) {
      if request_method is @http.Put {
        return Some(("update", Some(rest[0].to_owned())))
      }
      if request_method is @http.Delete {
        return Some(("void", Some(rest[0].to_owned())))
      }
    }
  }
  None
}
