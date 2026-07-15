///|
/// Native port of the source CBS dictionary percentage adjustment.
///
/// The source updates every matching leaf in a draft version. Imported
/// PostgreSQL rows are immutable in Moonproj, so this command applies only to
/// command-owned draft projections and records a durable command/audit receipt.
/// It changes CBS configuration only; it never consumes budget or posts money.

///|
fn cbs_batch_adjust_number(
  body : Json,
  key : String,
) -> Double raise CompanyServiceError {
  match json_field(body, key) {
    Some(Number(value, ..)) => value
    Some(String(value)) => parse_number(value)
    Some(_) => raise reject(422, key + " must be a decimal number")
    None => raise reject(400, key + " is required")
  }
}

///|
fn cbs_batch_adjust_round(value : Double) -> Double {
  let scaled = value * 100.0
  if scaled >= 0.0 {
    (scaled + 0.5).to_int().to_double() / 100.0
  } else {
    (scaled - 0.5).to_int().to_double() / 100.0
  }
}

///|
fn cbs_batch_adjust_envelope(
  data : Json,
  command : Json,
  replay : Bool,
) -> Json {
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
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
    "workflow_synchronization": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn cbs_batch_adjust_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user_id = cbs_require_user(actor_id)
  let proj_guid = cbs_body_text(body, "projGuid", "proj_guid")
  let plan_version = cbs_body_text(body, "planVersion", "plan_version")
  let r_code = cbs_body_text(body, "rCode", "r_code")
  if proj_guid.is_empty() || !valid_identifier(proj_guid) {
    raise reject(400, "projGuid is required")
  }
  if plan_version.is_empty() || !valid_identifier(plan_version) {
    raise reject(400, "planVersion is required")
  }
  if r_code.is_empty() || !valid_identifier(r_code) {
    raise reject(400, "rCode is required")
  }
  let pct = cbs_batch_adjust_number(body, "pct")
  let factor = 1.0 + pct / 100.0
  let version = match cbs_version_payload(proj_guid, plan_version) {
    Some(value) => value
    None => raise reject(404, "CBS version not found")
  }
  if !json_text(version, "frozen_at", "").is_empty() {
    raise reject(400, "版本已冻结")
  }
  match cbs_latest_projection("cbs_plan_version", plan_version) {
    Some(_) => ()
    None => raise reject(409, "imported CBS versions are read-only")
  }
  let all_items = cbs_dict_payloads(proj_guid, plan_version)
  let mut matching_count = 0
  let local_items : Array[Json] = []
  for item in all_items {
    if report_text(item, "r_code", "") == r_code &&
      json_text(item, "state", "active") != "deleted" {
      matching_count += 1
      if json_text(item, "source_kind", "") == "command" {
        local_items.push(item)
      }
    }
  }
  if matching_count > local_items.length() {
    raise reject(409, "imported CBS dictionary rows are read-only")
  }
  let request = Json::object({
    "command_type": Json::string("dict_batch_adjust"),
    "proj_guid": Json::string(proj_guid),
    "plan_version": Json::string(plan_version),
    "r_code": Json::string(r_code),
    "pct": Json::number(pct),
    "actor_id": Json::string(actor_id),
    "actor_user_id": Json::string(actor_user_id),
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
        cbs_batch_adjust_envelope(
          json_field(existing, "result").unwrap_or(Json::null()),
          existing,
          true,
        ),
      )
    }
    None => ()
  }
  let event_id = "cbs:dict_batch_adjust:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "projGuid": Json::string(proj_guid),
    "planVersion": Json::string(plan_version),
    "rCode": Json::string(r_code),
    "affected": Json::number(local_items.length().to_double()),
    "factor": Json::number(factor),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
    "authorizing": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs"),
    "command_type": Json::string("dict_batch_adjust"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("cbs_subject_dict_batch"),
    "aggregate_id": Json::string(proj_guid + "|" + plan_version + "|" + r_code),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs.dict_batch_adjust"),
    "aggregate_type": Json::string("cbs_subject_dict"),
    "aggregate_id": Json::string(proj_guid + "|" + plan_version + "|" + r_code),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(1),
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
  })
  let mut projection_sql = ""
  for item in local_items {
    let dict_guid = report_text(item, "dict_guid", "")
    if dict_guid.is_empty() {
      raise fail("CBS dictionary row is missing dict_guid")
    }
    let current_revision = match
      cbs_latest_projection("cbs_subject_dict", dict_guid) {
      Some((_, revision)) => revision
      None => raise fail("CBS dictionary projection disappeared")
    }
    let fields = cbs_copy_fields(item)
    fields.set(
      "plan_amount",
      Json::number(
        cbs_batch_adjust_round(json_number(item, "plan_amount", 0.0) * factor),
      ),
    )
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id + ":" + dict_guid))
    fields.set("updated_by", Json::string(actor_id))
    projection_sql = projection_sql +
      " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_subject_dict'," +
      @postgres.sql_literal(dict_guid) +
      "," +
      (current_revision + 1).to_string() +
      "," +
      @postgres.sql_literal(Json::object(fields).stringify()) +
      "::jsonb," +
      @postgres.sql_literal(event_id + ":" + dict_guid) +
      ") ON CONFLICT DO NOTHING;"
  }
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING;" +
    projection_sql +
    " INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (200, cbs_batch_adjust_envelope(result, command, false))
}
