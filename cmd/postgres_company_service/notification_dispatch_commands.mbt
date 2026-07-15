///|
/// Authenticated digest-dispatch candidate.
///
/// The source route sends in-app/email messages and writes a daily log. The
/// native boundary evaluates the same warning summary and recipient evidence,
/// persists an idempotent receipt, and keeps delivery/provider effects off.
fn notification_digest_dispatch_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/notify/digest/dispatch" ||
    path == "/api/company/source/notify/digest/dispatch"
  )
}

///|
async fn notification_digest_dispatch_command(
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let request = Json::object({
    "command_type": Json::string("digest_dispatch"),
    "actor_id": Json::string(actor),
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
  let rows = warning_context()
  let findings = warning_findings(rows)
  let mut error_total = 0
  let mut warning_total = 0
  let open_rows : Array[Json] = []
  let bounded_rows : Array[Json] = []
  for finding in findings {
    if report_text(finding, "status", "open") == "open" {
      open_rows.push(finding)
      if bounded_rows.length() < 50 {
        bounded_rows.push(finding)
      }
      if report_text(finding, "severity", "") == "error" {
        error_total += 1
      } else if report_text(finding, "severity", "") == "warning" {
        warning_total += 1
      }
    }
  }
  let recipient_count = raw_source_rows("sys_warning_subscription", 500).length()
  let recipients = if recipient_count > 0 {
    recipient_count
  } else {
    raw_source_rows("sys_user", 500).fold(init=0, fn(total, row) {
      total +
      (if json_bool(row.payload, "is_super_user", false) &&
        json_bool(row.payload, "enabled", true) {
        1
      } else {
        0
      })
    })
  }
  let result = Json::object({
    "commandType": Json::string("digest_dispatch"),
    "sent": Json::boolean(false),
    "dryRun": Json::boolean(true),
    "userCount": Json::number(recipients.to_double()),
    "errorTotal": Json::number(error_total.to_double()),
    "warningTotal": Json::number(warning_total.to_double()),
    "newCount": Json::number(0),
    "rows": Json::array(bounded_rows),
    "sourceKind": Json::string("command_candidate"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let event_id = "notification:digest_dispatch:" + idempotency_key
  let audit_id = event_id + ":audit"
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("notification"),
    "command_type": Json::string("digest_dispatch"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("notification_digest_dispatch"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let projection = Json::object({
    "dispatch_id": Json::string(idempotency_key),
    "user_count": Json::number(recipients.to_double()),
    "error_total": Json::number(error_total.to_double()),
    "warning_total": Json::number(warning_total.to_double()),
    "new_count": Json::number(0),
    "sent": Json::boolean(false),
    "dry_run": Json::boolean(true),
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("notification.digest_dispatch"),
    "aggregate_type": Json::string("notification_digest_dispatch"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('notification_digest_dispatch', " +
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
