///|
/// Native admin configuration candidates.
///
/// The ERP writes arbitrary `sys_param` values. The native target records a
/// reviewed, replayable configuration candidate while keeping the value out of
/// command/audit payloads; production parameter binding remains a deployment
/// and security-owner decision.

///|
fn admin_sys_param_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/admin/sys-param" ||
    path == "/api/company/source/admin/sys-param"
  )
}

///|
fn admin_sys_param_value(body : Json) -> String raise CompanyServiceError {
  match json_field(body, "value") {
    Some(String(value)) => value
    Some(Null) | None => ""
    Some(value) => value.stringify()
  }
}

///|
fn admin_sys_param_sensitive(code : String) -> Bool {
  let lowered = code.to_lower()
  lowered.contains("key") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("password") ||
  lowered.contains("credential") ||
  lowered.contains("private")
}

///|
async fn admin_sys_param_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let _ = rbac_require_super(actor_id)
  let code = json_text(body, "code", "").trim().to_owned()
  if !valid_identifier(code) {
    raise reject(400, "code is required and must be a valid parameter key")
  }
  let value = admin_sys_param_value(body)
  if value.length() > 16384 {
    raise reject(422, "value is too large")
  }
  let sensitive = admin_sys_param_sensitive(code)
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(value)),
  )
  let request = Json::object({
    "code": Json::string(code),
    "value_digest": Json::string(digest),
    "value_length": Json::number(value.length().to_double()),
    "sensitive": Json::boolean(sensitive),
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
      return (
        200,
        Json::object({
          "command": existing,
          "admin": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let event_id = "admin:sys_param:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "code": Json::string(code),
    "valueConfigured": Json::boolean(!value.is_empty()),
    "valueDigest": Json::string(digest),
    "valueLength": Json::number(value.length().to_double()),
    "sensitive": Json::boolean(sensitive),
    "sourceKind": Json::string("command"),
    "commandProjection": Json::boolean(true),
    "persisted": Json::boolean(true),
    "authorization_candidate": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
    "valueRedacted": Json::boolean(true),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("admin"),
    "command_type": Json::string("sys_param"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("admin_sys_param"),
    "aggregate_id": Json::string(code),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let projection = Json::object({
    "code": Json::string(code),
    "value_digest": Json::string(digest),
    "value_length": Json::number(value.length().to_double()),
    "sensitive": Json::boolean(sensitive),
    "value_configured": Json::boolean(!value.is_empty()),
    "source_kind": Json::string("command"),
    "event_id": Json::string(event_id),
    "updated_by": Json::string(actor_id),
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("admin.sys_param"),
    "aggregate_type": Json::string("admin_sys_param"),
    "aggregate_id": Json::string(code),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "value_digest": Json::string(digest),
    "value_length": Json::number(value.length().to_double()),
    "value_redacted": Json::boolean(true),
    "authorization_candidate": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
  })
  let sql = "BEGIN; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT 'admin_sys_param', " +
    @postgres.sql_literal(code) +
    ", coalesce(max(revision), 0) + 1, " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    " FROM company_aggregate_projection WHERE aggregate_type = 'admin_sys_param' AND aggregate_id = " +
    @postgres.sql_literal(code) +
    "; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  let receipt = existing_company_command(idempotency_key)
  let receipt = match receipt {
    Some(value) => value
    None => raise fail("admin sys-param command receipt was not persisted")
  }
  (
    200,
    Json::object({
      "command": receipt,
      "admin": json_field(receipt, "result").unwrap_or(result),
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
