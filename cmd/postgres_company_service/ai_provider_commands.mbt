///|
/// OCR/LLM provider-test candidates.
///
/// The source ERP performs a live provider call. The native target preserves
/// the request/configuration evidence and returns a deterministic dry-run
/// result; credentials and external execution stay outside this migration
/// boundary.
fn ai_provider_test_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let pairs = [
      ("/api/company/admin/ocr/test", "ocr_test"),
      ("/api/company/source/admin/ocr/test", "ocr_test"),
      ("/api/company/admin/llm/test", "llm_test"),
      ("/api/company/source/admin/llm/test", "llm_test"),
      ("/api/company/notify/llm-test", "llm_test"),
      ("/api/company/source/notify/llm-test", "llm_test"),
    ]
    for pair in pairs {
      if path == pair.0 {
        return Some(pair.1)
      }
    }
  }
  None
}

///|
fn ai_provider_test_digest(value : String) -> String {
  if value.is_empty() {
    ""
  } else {
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(value)))
  }
}

///|
async fn ai_provider_test_command(
  command_type : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let fields : Map[String, Json] = match body {
    Object(values) => values
    _ => {}
  }
  let default_provider_key = if command_type == "ocr_test" {
    "ai.ocr.provider"
  } else {
    "ai.llm.provider"
  }
  let default_provider = notification_effective_config(default_provider_key)
  let provider_value = notification_value_text(
      fields.get("provider").unwrap_or(Json::null()),
    )
    .trim()
    .to_owned()
  let provider = if provider_value.is_empty() {
    if default_provider.0.is_empty() {
      "mock"
    } else {
      default_provider.0
    }
  } else {
    provider_value
  }
  let key_value = notification_value_text(
    fields.get("key").unwrap_or(Json::null()),
  )
  let model_value = notification_value_text(
    fields.get("model").unwrap_or(Json::null()),
  )
  let endpoint_value = notification_value_text(
    fields.get("endpoint").unwrap_or(Json::null()),
  )
  let configured_key = if key_value.is_empty() {
    notification_effective_config("ai.llm.key").1
  } else {
    true
  }
  let configured_endpoint = if endpoint_value.is_empty() {
    notification_effective_config("ai.llm.endpoint").1
  } else {
    true
  }
  let request = Json::object({
    "command_type": Json::string(command_type),
    "actor_id": Json::string(actor),
    "provider": Json::string(provider),
    "key_digest": Json::string(ai_provider_test_digest(key_value)),
    "model": Json::string(model_value),
    "endpoint_digest": Json::string(ai_provider_test_digest(endpoint_value)),
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
          "command": existing,
          "data": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let event_id = "ai:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "commandType": Json::string(command_type),
    "provider": Json::string(provider),
    "ok": Json::boolean(false),
    "tested": Json::boolean(false),
    "reason": Json::string("provider_execution_disabled"),
    "keyConfigured": Json::boolean(configured_key),
    "modelConfigured": Json::boolean(!model_value.is_empty()),
    "endpointConfigured": Json::boolean(configured_endpoint),
    "sourceKind": Json::string("command_candidate"),
    "persisted": Json::boolean(true),
    "dryRun": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("ai_provider"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("ai_provider_test"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let projection = Json::object({
    "test_id": Json::string(idempotency_key),
    "command_type": Json::string(command_type),
    "provider": Json::string(provider),
    "key_configured": Json::boolean(configured_key),
    "endpoint_configured": Json::boolean(configured_endpoint),
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "dry_run": Json::boolean(true),
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("ai." + command_type),
    "aggregate_type": Json::string("ai_provider_test"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "dry_run": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('ai_provider_test', " +
    @postgres.sql_literal(idempotency_key) +
    ", 1, " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "command": command_payload,
      "data": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
