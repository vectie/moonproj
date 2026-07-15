///|
/// Signed local CBS change registration.
///
/// Change registration is source-shaped and auditable for command-owned demo
/// contracts.  Imported contracts remain immutable; workflow approval and
/// budget/accounting/cash/tax effects are deliberately separate boundaries.

///|
fn cbs_change_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/cbs/changes" ||
    path == "/api/company/source/cbs/changes"
  )
}

///|
fn cbs_change_text(
  body : Json,
  primary : String,
  fallback : String,
  required : Bool,
  identifier : Bool,
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
  if required && text.is_empty() {
    raise reject(400, primary + " is required")
  }
  if identifier && !text.is_empty() && !valid_identifier(text) {
    raise reject(422, primary + " contains unsupported characters")
  }
  text
}

///|
fn cbs_change_amount(body : Json) -> Double raise CompanyServiceError {
  let value = match json_field(body, "change_amount") {
    Some(value) => value
    None => json_field(body, "changeAmount").unwrap_or(Json::null())
  }
  let amount = match value {
    Number(value, ..) => value
    String(value) => parse_number(value.trim().to_owned())
    _ => raise reject(400, "changeAmount is required")
  }
  if amount != amount {
    raise reject(422, "changeAmount must be finite")
  }
  amount
}

///|
async fn cbs_change_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let contract_id = cbs_change_text(
    body, "contract_guid", "contractGuid", true, true,
  )
  let reason = cbs_change_text(body, "reason", "reason", true, false)
  let amount = cbs_change_amount(body)
  let contract = cbs_latest_projection("cbs_demo_contract", contract_id)
  let current = match contract {
    Some((payload, _)) => payload
    None => {
      if cbs_demo_contract_imported_exists(contract_id, "") {
        raise reject(409, "imported CBS contract is read-only")
      }
      raise reject(404, "contract not found")
    }
  }
  let contract_state = json_text(
    current,
    "cb_state",
    json_text(current, "state", "draft"),
  )
  if contract_state != "signed" && contract_state != "paid" {
    raise reject(400, "only signed or paid contracts accept changes")
  }
  let change_id = "change-" + idempotency_key
  let change_code = "CHG-" + idempotency_key
  let request = Json::object({
    "command_type": Json::string("create"),
    "change_guid": Json::string(change_id),
    "change_code": Json::string(change_code),
    "contract_guid": Json::string(contract_id),
    "proj_guid": Json::string(json_text(current, "proj_guid", "")),
    "r_code": Json::string(json_text(current, "r_code", "R0")),
    "l3_code": Json::string(json_text(current, "l3_code", "")),
    "reason": Json::string(reason),
    "change_amount": Json::number(amount),
    "state": Json::string("estimated"),
    "actor_id": Json::string(actor_id),
  })
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
      let result = json_field(existing, "result").unwrap_or(Json::null())
      return (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": result,
          "change": result,
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
          "workflow_effect": Json::boolean(false),
          "budget_consumption": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
    None => ()
  }
  if cbs_latest_projection("cbs_change", change_id) is Some(_) {
    raise reject(409, "change already exists")
  }
  let event_id = "cbs_change:create:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "changeGuid": Json::string(change_id),
    "changeCode": Json::string(change_code),
    "contractGuid": Json::string(contract_id),
    "reason": Json::string(reason),
    "changeAmount": Json::number(amount),
    "state": Json::string("estimated"),
    "workflowPending": Json::boolean(true),
    "revision": Json::number(1.0),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_change"),
    "command_type": Json::string("create"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_change"),
    "aggregate_id": Json::string(change_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.change.create"),
    "aggregate_type": Json::string("cbs_change"),
    "aggregate_id": Json::string(change_id),
    "contract_guid": Json::string(contract_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_change'," +
    @postgres.sql_literal(change_id) +
    ",1," +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'workflow_pending',true)," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": result,
      "change": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "workflow_effect": Json::boolean(false),
      "budget_consumption": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}
