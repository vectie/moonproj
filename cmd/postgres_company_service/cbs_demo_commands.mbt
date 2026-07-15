///|
/// Signed local CBS demo-contract creation.
///
/// This ports the source demo form into an auditable command projection.  It
/// never writes imported `cb_contract` rows, reserves budget, or applies
/// accounting/cash/tax effects.  R0/non-R0 classification is retained as a
/// local intent; complete budget and workflow enforcement remains gated.

///|
fn cbs_demo_contract_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/cbs/demo/contracts" ||
    path == "/api/company/source/cbs/demo/contracts"
  )
}

///|
fn cbs_demo_legacy_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/cbs/demo/legacy" ||
    path == "/api/company/source/cbs/demo/legacy"
  )
}

///|
fn cbs_demo_clear_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Delete &&
  (
    path == "/api/company/cbs/demo/clear" ||
    path == "/api/company/source/cbs/demo/clear"
  )
}

///|
fn cbs_demo_contract_state_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = [
    "/api/company/cbs/demo/contracts/", "/api/company/source/cbs/demo/contracts/",
  ]
  for prefix in prefixes {
    if request_method is @http.Put &&
      path.has_prefix(prefix) &&
      path.has_suffix("/state") {
      let id = path[prefix.length():path.length() - "/state".length()].to_owned()
      if valid_identifier(id) {
        return Some(id)
      }
    }
  }
  None
}

///|
fn cbs_demo_contract_text(
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
fn cbs_demo_contract_amount(body : Json) -> Double raise CompanyServiceError {
  let value = match json_field(body, "amount") {
    Some(value) => value
    None => json_field(body, "htAmount").unwrap_or(Json::null())
  }
  let amount = match value {
    Number(value, ..) => value
    String(value) => parse_number(value.trim().to_owned())
    _ => raise reject(400, "amount is required")
  }
  if amount <= 0.0 || amount != amount {
    raise reject(422, "amount must be positive")
  }
  amount
}

///|
fn cbs_demo_contract_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  let contract_id = {
    let value = cbs_demo_contract_text(
      body, "contract_guid", "contractGuid", false, true,
    )
    if value.is_empty() {
      if json_bool(body, "legacy", false) {
        "legacy-" + idempotency_key
      } else {
        "demo-" + idempotency_key
      }
    } else {
      value
    }
  }
  let contract_code = {
    let value = cbs_demo_contract_text(
      body, "contract_code", "contractCode", false, true,
    )
    if value.is_empty() {
      if json_bool(body, "legacy", false) {
        "LEGACY-" + idempotency_key
      } else {
        "DEMO-" + idempotency_key
      }
    } else {
      value
    }
  }
  if !valid_identifier(contract_id) || !valid_identifier(contract_code) {
    raise reject(422, "contract identity contains unsupported characters")
  }
  let proj_guid = cbs_demo_contract_text(
    body, "proj_guid", "projGuid", false, true,
  )
  let project = if proj_guid.is_empty() { "proj-0001" } else { proj_guid }
  let r_code = cbs_demo_contract_text(body, "r_code", "rCode", false, true)
  let classification = if r_code.is_empty() { "R0" } else { r_code }
  let l3_code = cbs_demo_contract_text(body, "l3_code", "l3Code", false, true)
  if classification != "R0" && l3_code.is_empty() {
    raise reject(400, "selected R code requires l3Code")
  }
  let amount = cbs_demo_contract_amount(body)
  let state = if classification == "R0" { "signed" } else { "draft" }
  Json::object({
    "command_type": Json::string("create"),
    "contract_guid": Json::string(contract_id),
    "contract_code": Json::string(contract_code),
    "contract_name": Json::string(
      cbs_demo_contract_text(body, "name", "contractName", true, false),
    ),
    "proj_guid": Json::string(project),
    "r_code": Json::string(classification),
    "l3_code": Json::string(l3_code),
    "ht_amount": Json::number((amount * 10000.0).to_int().to_double()),
    "sum_alter_amount": Json::number(0.0),
    "cb_state": Json::string(state),
    "state": Json::string(state),
    "budget_check_pending": Json::boolean(true),
    "actor_id": Json::string(actor_id),
  })
}

///|
async fn cbs_demo_contract_state_command(
  contract_id : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(contract_id) {
    raise reject(422, "contract id is invalid")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let to_state = cbs_demo_contract_text(body, "to_state", "toState", true, true)
  let valid_state = to_state == "draft" ||
    to_state == "approving" ||
    to_state == "signed" ||
    to_state == "paid"
  if !valid_state {
    raise reject(400, "invalid demo contract state")
  }
  let remark = cbs_demo_contract_text(body, "remark", "remark", false, false)
  let request = Json::object({
    "command_type": Json::string("state"),
    "contract_guid": Json::string(contract_id),
    "to_state": Json::string(to_state),
    "remark": Json::string(remark),
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
          "contract": result,
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
          "budget_consumption": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
    None => ()
  }
  let current = match cbs_latest_projection("cbs_demo_contract", contract_id) {
    Some((payload, revision)) => (payload, revision)
    None => {
      if cbs_demo_contract_imported_exists(contract_id, "") {
        raise reject(409, "imported CBS contract is read-only")
      }
      raise reject(404, "demo contract not found")
    }
  }
  let from_state = json_text(
    current.0,
    "cb_state",
    json_text(current.0, "state", "draft"),
  )
  let from_index = match from_state {
    "draft" => 0
    "approving" => 1
    "signed" => 2
    "paid" => 3
    _ => -1
  }
  let to_index = match to_state {
    "draft" => 0
    "approving" => 1
    "signed" => 2
    _ => 3
  }
  if to_index != from_index + 1 {
    raise reject(400, "demo contract state transition is not forward-only")
  }
  let event_id = "cbs_demo_contract_state:" + idempotency_key
  let audit_id = event_id + ":audit"
  let fields = cbs_copy_fields(current.0)
  fields.set("cb_state", Json::string(to_state))
  fields.set("state", Json::string(to_state))
  fields.set("source_kind", Json::string("command"))
  fields.set("event_id", Json::string(event_id))
  fields.set("updated_by", Json::string(actor_id))
  fields.set("remark", Json::string(remark))
  let next_payload = Json::object(fields)
  let result = Json::object({
    "id": Json::string(contract_id),
    "fromState": Json::string(from_state),
    "toState": Json::string(to_state),
    "actor": Json::string(actor_id),
    "remark": Json::string(remark),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "budget_consumption": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_demo_contract"),
    "command_type": Json::string("state"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string(contract_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.demo.contract.state"),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string(contract_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "from_state": Json::string(from_state),
    "to_state": Json::string(to_state),
  })
  let next_revision = current.1 + 1
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_demo_contract'," +
    @postgres.sql_literal(contract_id) +
    "," +
    next_revision.to_string() +
    "," +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb," +
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
      "contract": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "budget_consumption": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
async fn cbs_demo_contract_imported_exists(
  contract_id : String,
  contract_code : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("cb_contract", 500) {
    let payload = row.payload
    if json_text(payload, "contract_guid", row.record_id) == contract_id ||
      json_text(payload, "contract_code", "") == contract_code {
      return true
    }
  }
  false
}

///|
async fn cbs_demo_contract_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = cbs_demo_contract_request(body, actor_id, idempotency_key)
  let contract_id = json_text(request, "contract_guid", "")
  let contract_code = json_text(request, "contract_code", "")
  if cbs_demo_contract_imported_exists(contract_id, contract_code) {
    raise reject(409, "imported CBS contract is read-only")
  }
  match cbs_latest_projection("cbs_demo_contract", contract_id) {
    Some(_) => raise reject(409, "CBS demo contract already exists")
    None => ()
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
      let result = json_field(existing, "result").unwrap_or(Json::null())
      return (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": result,
          "contract": result,
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
          "budget_consumption": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
    None => ()
  }
  let event_id = "cbs_demo_contract:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "id": Json::string(contract_id),
    "code": Json::string(contract_code),
    "name": json_field(request, "contract_name").unwrap_or(Json::null()),
    "rCode": Json::string(json_text(request, "r_code", "R0")),
    "l3Code": Json::string(json_text(request, "l3_code", "")),
    "amount": Json::number(json_number(request, "ht_amount", 0.0) / 10000.0),
    "state": Json::string(json_text(request, "cb_state", "draft")),
    "budgetCheckPending": Json::boolean(true),
    "importedContractProtected": Json::boolean(true),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_demo_contract"),
    "command_type": Json::string("create"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string(contract_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.demo.contract.create"),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string(contract_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_demo_contract'," +
    @postgres.sql_literal(contract_id) +
    ",1," +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'budget_check_pending',true)," +
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
      "contract": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "budget_consumption": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
async fn cbs_demo_legacy_command(
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let source_body = Json::object({
    "name": Json::string("Legacy contract backfill"),
    "amount": Json::number(8.2),
    "projGuid": Json::string("proj-0001"),
    "rCode": Json::string("R0"),
    "legacy": Json::boolean(true),
  })
  cbs_demo_contract_command(source_body, actor_id, idempotency_key)
}

///|
async fn cbs_demo_clear_command(
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = Json::object({
    "command_type": Json::string("clear"),
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
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
          "budget_consumption": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
    None => ()
  }
  let count_output = run_sql(
    "SELECT count(*) FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,payload FROM company_aggregate_projection WHERE aggregate_type='cbs_demo_contract' ORDER BY aggregate_id,revision DESC) latest WHERE coalesce(payload->>'state','') <> 'deleted' AND (coalesce(payload->>'contract_code','') LIKE 'DEMO-%' OR coalesce(payload->>'contract_code','') LIKE 'LEGACY-%')",
  )
  let deleted_count = parse_decimal(count_output.trim().to_owned())
  let event_id = "cbs_demo_clear:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "deleted": Json::number(deleted_count.to_double()),
    "commandOwnedOnly": Json::boolean(true),
    "importedProtected": Json::boolean(true),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_demo_contract"),
    "command_type": Json::string("clear"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string("demo-clear"),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.demo.clear"),
    "aggregate_type": Json::string("cbs_demo_contract"),
    "aggregate_id": Json::string("demo-clear"),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "deleted": Json::number(deleted_count.to_double()),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) SELECT 'cbs_demo_contract',aggregate_id,revision+1,payload || jsonb_build_object('state','deleted','cb_state','deleted','deleted_at'," +
    @postgres.sql_literal(event_id) +
    ",'source_kind','command','event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ")," +
    @postgres.sql_literal(event_id) +
    " FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,revision,payload FROM company_aggregate_projection WHERE aggregate_type='cbs_demo_contract' ORDER BY aggregate_id,revision DESC) latest WHERE coalesce(payload->>'state','') <> 'deleted' AND (coalesce(payload->>'contract_code','') LIKE 'DEMO-%' OR coalesce(payload->>'contract_code','') LIKE 'LEGACY-%') ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
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
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "budget_consumption": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}
