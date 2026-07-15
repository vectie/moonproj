///|
/// Webhook test-delivery candidate.
///
/// The ERP sends a real provider request here. The native migration boundary
/// validates the same platform/configuration state and records a deterministic
/// dry-run receipt without exposing credentials or making a network call.
fn webhook_test_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let canonical_prefix = "/api/company/webhook/test/"
    let source_prefix = "/api/company/source/webhook/test/"
    let platform = if path.has_prefix(canonical_prefix) {
      path[canonical_prefix.length():].to_owned()
    } else if path.has_prefix(source_prefix) {
      path[source_prefix.length():].to_owned()
    } else {
      ""
    }
    if webhook_platform_valid(platform) {
      return Some(platform)
    }
  }
  None
}

///|
async fn webhook_test_delivery_command(
  platform : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  if !webhook_platform_valid(platform) {
    raise reject(400, "platform is invalid")
  }
  let actor = rbac_require_super(actor_id)
  let fields : Map[String, Json] = match body {
    Object(values) => values
    _ => raise reject(422, "webhook test body must be an object")
  }
  let title = webhook_body_text(fields, "title", 256, true).unwrap_or(
    "[ERP test] " + webhook_platform_label(platform) + " webhook",
  )
  let content = webhook_body_text(fields, "content", 2048, true).unwrap_or(
    "Native PostgreSQL dry-run webhook test",
  )
  let request = Json::object({
    "command_type": Json::string("test_delivery"),
    "actor_id": Json::string(actor),
    "platform": Json::string(platform),
    "title": Json::string(title),
    "content": Json::string(content),
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
  let source_values = webhook_source_params()
  let imported_enabled = webhook_text_bool(
    source_values.get("notify.webhook." + platform + ".enabled").unwrap_or(""),
  )
  let imported_url = source_values
    .get("notify.webhook." + platform + ".url")
    .unwrap_or("")
  let imported_secret = source_values
    .get("notify.webhook." + platform + ".secret")
    .unwrap_or("")
  let current = webhook_latest_projection(platform)
  let enabled = match current {
    Some((payload, _)) => json_bool(payload, "enabled", false)
    None => imported_enabled
  }
  let url_configured = match current {
    Some((payload, _)) => json_bool(payload, "url_configured", false)
    None => !imported_url.is_empty()
  }
  let secret_configured = match current {
    Some((payload, _)) => json_bool(payload, "secret_configured", false)
    None => !imported_secret.is_empty()
  }
  let would_send = enabled && url_configured
  let reason = if !enabled {
    "disabled"
  } else if !url_configured {
    "no_url"
  } else {
    "provider_execution_disabled"
  }
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "webhook:test_delivery:" + platform + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "platform": Json::string(platform),
    "label": Json::string(webhook_platform_label(platform)),
    "ok": Json::boolean(false),
    "skipped": Json::string(reason),
    "reason": Json::string(reason),
    "dryRun": Json::boolean(true),
    "wouldSend": Json::boolean(would_send),
    "enabled": Json::boolean(enabled),
    "urlConfigured": Json::boolean(url_configured),
    "hasSecret": Json::boolean(secret_configured),
    "title": Json::string(title),
    "contentLength": Json::number(content.length().to_double()),
    "revision": Json::number(revision.to_double()),
    "actorId": Json::string(actor),
    "sourceKind": Json::string("command_candidate"),
    "persisted": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "credentialsBound": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let projection = Json::object({
    "aggregate_id": Json::string(platform),
    "platform": Json::string(platform),
    "enabled": Json::boolean(enabled),
    "url_configured": Json::boolean(url_configured),
    "secret_configured": Json::boolean(secret_configured),
    "would_send": Json::boolean(would_send),
    "reason": Json::string(reason),
    "title": Json::string(title),
    "content_length": Json::number(content.length().to_double()),
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("webhook"),
    "command_type": Json::string("test_delivery"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("webhook_test_delivery"),
    "aggregate_id": Json::string(platform),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("webhook.test_delivery"),
    "aggregate_type": Json::string("webhook_test_delivery"),
    "aggregate_id": Json::string(platform),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('webhook_test_delivery', " +
    @postgres.sql_literal(platform) +
    ", " +
    revision.to_string() +
    ", " +
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
