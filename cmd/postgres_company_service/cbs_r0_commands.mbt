///|
/// Local CBS R0-resolution intent.
///
/// The source route writes an R0 contract classification.  Native PostgreSQL
/// records that decision as an auditable command-owned resolution projection,
/// but does not rewrite imported contracts or consume budget.  When the source
/// dictionary is present, the leaf/R-code is verified; otherwise the intent is
/// retained as `resolution_pending` until the missing source cohort arrives.

///|
fn cbs_r0_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/cbs/r0/resolve" ||
    path == "/api/company/source/cbs/r0/resolve"
  )
}

///|
fn cbs_r0_text(
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
async fn cbs_r0_dictionary_match(
  l3_code : String,
) -> (Bool, String) raise CompanyServiceError {
  let imported = raw_source_rows("cb_subject_dict", 5000)
  for row in imported {
    if report_text(row.payload, "l3_code", "") == l3_code {
      return (true, report_text(row.payload, "r_code", ""))
    }
  }
  let projected = cbs_projection_payloads("cbs_subject_dict")
  for payload in projected {
    if report_text(payload, "l3_code", "") == l3_code &&
      json_text(payload, "state", "active") != "deleted" {
      return (true, report_text(payload, "r_code", ""))
    }
  }
  (false, "")
}

///|
async fn cbs_r0_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let ref_kind = cbs_r0_text(body, "refKind", "ref_kind", true, false)
  if ref_kind != "contract" {
    raise reject(400, "refKind must be contract")
  }
  let ref_id = cbs_r0_text(body, "refId", "ref_id", true, true)
  let l3_code = cbs_r0_text(body, "l3Code", "l3_code", true, true)
  let proj_guid = cbs_r0_text(body, "projGuid", "proj_guid", false, true)
  let dictionary = cbs_r0_dictionary_match(l3_code)
  let r_code_value = if !dictionary.1.is_empty() {
    dictionary.1
  } else {
    cbs_r0_text(body, "rCode", "r_code", false, true)
  }
  let resolution_id = "r0-" + idempotency_key
  let request = Json::object({
    "command_type": Json::string("r0_resolve"),
    "resolution_id": Json::string(resolution_id),
    "ref_kind": Json::string(ref_kind),
    "ref_id": Json::string(ref_id),
    "l3_code": Json::string(l3_code),
    "r_code": Json::string(r_code_value),
    "proj_guid": Json::string(proj_guid),
    "actor_id": Json::string(actor_id),
    "dictionary_verified": Json::boolean(dictionary.0),
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
      return (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": json_field(existing, "result").unwrap_or(Json::null()),
          "resolution": json_field(existing, "result").unwrap_or(Json::null()),
          "command": existing,
          "idempotent_replay": Json::boolean(true),
          "source_kind": Json::string("command"),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(true),
          "cbs_effect": Json::boolean(false),
          "resolution_projection": Json::boolean(true),
          "budget_consumption": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
    }
    None => ()
  }
  let event_id = "cbs_r0:" + idempotency_key
  let audit_id = event_id + ":audit"
  let resolution_state = if dictionary.0 {
    "resolved"
  } else {
    "resolution_pending"
  }
  let result = Json::object({
    "resolutionId": Json::string(resolution_id),
    "refKind": Json::string(ref_kind),
    "refId": Json::string(ref_id),
    "l3Code": Json::string(l3_code),
    "rCode": Json::string(r_code_value),
    "state": Json::string(resolution_state),
    "dictionaryVerified": Json::boolean(dictionary.0),
    "targetMutated": Json::boolean(false),
    "importedContractProtected": Json::boolean(true),
    "revision": Json::number(1.0),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs_r0"),
    "command_type": Json::string("r0_resolve"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_r0_resolution"),
    "aggregate_id": Json::string(resolution_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.r0.resolve"),
    "aggregate_type": Json::string("cbs_r0_resolution"),
    "aggregate_id": Json::string(resolution_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "dictionary_verified": Json::boolean(dictionary.0),
  })
  let payload = request
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_r0_resolution'," +
    @postgres.sql_literal(resolution_id) +
    ",1," +
    @postgres.sql_literal(payload.stringify()) +
    "::jsonb || jsonb_build_object('source_kind','command','state'," +
    @postgres.sql_literal(resolution_state) +
    ",'event_id'," +
    @postgres.sql_literal(event_id) +
    ",'updated_by'," +
    @postgres.sql_literal(actor_id) +
    ",'target_mutated',false)," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": result,
      "resolution": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("command"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(true),
      "cbs_effect": Json::boolean(false),
      "resolution_projection": Json::boolean(true),
      "budget_consumption": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
async fn cbs_r0_resolution_rows() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(payload::text,'UTF8'),'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id,payload FROM company_aggregate_projection WHERE aggregate_type='cbs_r0_resolution' ORDER BY aggregate_id,revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let payload = @json.parse(decode_hex(line)) catch {
        _ => raise fail("invalid CBS R0 resolution JSON")
      }
      result.push(payload)
    }
  }
  result
}
