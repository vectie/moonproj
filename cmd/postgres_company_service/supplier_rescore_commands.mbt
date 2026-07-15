///|
/// Signed supplier risk rescore command.
///
/// The source route mutates every supplier rating. Native rescore updates only
/// command-owned supplier projections, while imported provider rows remain
/// immutable. The calculation mirrors the source contract/milestone formula
/// and records an auditable replayable command receipt.

///|
fn supplier_rescore_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/srm/providers/rescore-all" ||
    path == "/api/company/source/srm/providers/rescore-all"
  )
}

///|
fn supplier_rescore_evaluation(item : Json) -> String {
  let state = json_text(item, "auditState", "")
  if state == "blacklisted" {
    return "黑名单"
  }
  match json_text(item, "evalResult", "") {
    "战略" => "战略"
    "合格" => "合格"
    "不合格" => "不合格"
    "已评审" => "已评审"
    _ => "未定级"
  }
}

///|
async fn supplier_rescore_command(
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let request = Json::object({
    "command_type": Json::string("rescore_all"),
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
      return Json::object({
        "success": Json::boolean(true),
        "code": Json::number(0),
        "data": result,
        "command": existing,
        "idempotent_replay": Json::boolean(true),
        "source_kind": Json::string("command"),
        "persisted": Json::boolean(true),
        "authorizing": Json::boolean(false),
        "provider_execution": Json::boolean(false),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      })
    }
    None => ()
  }
  let imported = raw_source_rows("srm_provider", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let milestones = raw_source_rows("cb_contract_milestone", 500)
  let command_items = supplier_command_items()
  let total = imported.length() + command_items.length()
  let event_id = "supplier:rescore-all:" + idempotency_key
  let audit_id = event_id + ":audit"
  let mut updated = 0
  let updates : Array[(String, SupplierRiskMetrics, Int, Json)] = []
  for item in command_items {
    let supplier_id = json_text(item, "providerGuid", "")
    if supplier_id.is_empty() {
      continue
    }
    let provider = SourceRow::{
      record_id: supplier_id,
      source_id: "",
      payload: Json::object({
        "provider_name": Json::string(
          json_text(item, "providerName", supplier_id),
        ),
        "short_name": Json::string(json_text(item, "shortName", "")),
        "eval_result": Json::string(supplier_rescore_evaluation(item)),
        "inspect_state": Json::string(json_text(item, "inspectState", "")),
      }),
    }
    let metrics = supplier_source_risk_metrics(provider, contracts, milestones)
    match latest_supplier_payload(supplier_id) {
      Some((payload, revision)) => {
        updates.push((supplier_id, metrics, revision, payload))
        updated += 1
      }
      None => ()
    }
  }
  let result = Json::object({
    "total": Json::number(total.to_double()),
    "updated": Json::number(updated.to_double()),
    "wouldUpdate": Json::number(updated.to_double()),
    "importedProtected": Json::number(imported.length().to_double()),
    "dryRun": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "persisted": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("supplier_rescore"),
    "command_type": Json::string("rescore_all"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("supplier_rescore"),
    "aggregate_id": Json::string(event_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("supplier.rescore_all"),
    "aggregate_type": Json::string("supplier_rescore"),
    "aggregate_id": Json::string(event_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "updated": Json::number(updated.to_double()),
    "imported_protected": Json::number(imported.length().to_double()),
  })
  let command_source = "moonproj:command:" + idempotency_key
  let mut sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING;"
  for update in updates {
    let supplier_id = update.0
    let metrics = update.1
    let revision = update.2
    let payload = update.3
    let supplier_event = event_id + ":" + supplier_id
    let tags = metrics.tags.join(",")
    let next_payload = @postgres.sql_literal(payload.stringify()) +
      "::jsonb || jsonb_build_object('risk_score'," +
      metrics.score.to_string() +
      ",'risk_rating'," +
      @postgres.sql_literal(metrics.rating) +
      ",'risk_tags'," +
      @postgres.sql_literal(tags) +
      ",'risk_contract_count'," +
      metrics.contract_count.to_string() +
      ",'risk_contract_total'," +
      metrics.contract_total.to_string() +
      ",'risk_overdue_count'," +
      metrics.overdue_count.to_string() +
      ",'risk_overdue_amount'," +
      metrics.overdue_amount.to_string() +
      ",'risk_updated_at'," +
      @postgres.sql_literal(event_id) +
      ")"
    sql += " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('supplier'," +
      @postgres.sql_literal(supplier_id) +
      "," +
      (revision + 1).to_string() +
      "," +
      next_payload +
      "," +
      @postgres.sql_literal(supplier_event) +
      ") ON CONFLICT DO NOTHING;"
  }
  sql += " INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; UPDATE company_record SET payload = payload || jsonb_build_object('result'," +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb) WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; COMMIT;"
  let _ = run_sql(sql)
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": result,
    "command": command_payload,
    "idempotent_replay": Json::boolean(false),
    "source_kind": Json::string("command"),
    "persisted": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}
