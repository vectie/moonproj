///|
/// Authenticated overdue-scan command candidate.
///
/// The source route scans and delivers to configured providers. The native
/// boundary evaluates the same imported ticket window, persists an auditable
/// dry-run receipt, and keeps provider delivery/ticket mutation disabled.
fn webhook_overdue_scan_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/webhook/scan-overdue" ||
    path == "/api/company/source/webhook/scan-overdue"
  )
}

///|
async fn webhook_overdue_scan_command(
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let request = Json::object({
    "command_type": Json::string("scan_overdue"),
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
  let tickets = webhook_overdue_tickets()
  let params = webhook_source_params()
  let enabled_platforms : Array[Json] = []
  for platform in webhook_platforms() {
    let enabled = webhook_text_bool(
      params.get("notify.webhook." + platform + ".enabled").unwrap_or(""),
    )
    let url = params.get("notify.webhook." + platform + ".url").unwrap_or("")
    if enabled && !url.is_empty() {
      enabled_platforms.push(Json::string(platform))
    }
  }
  let data = if tickets.is_empty() {
    Json::object({
      "scanned": Json::number(0),
      "sent": Json::boolean(false),
      "dryRun": Json::boolean(true),
      "reason": Json::string("no_overdue"),
      "platforms": Json::array([]),
    })
  } else if enabled_platforms.is_empty() {
    Json::object({
      "scanned": Json::number(tickets.length().to_double()),
      "sent": Json::boolean(false),
      "dryRun": Json::boolean(true),
      "reason": Json::string("no_platform_enabled"),
      "platforms": Json::array([]),
    })
  } else {
    let mut lines = ""
    for ticket in tickets {
      if !lines.is_empty() {
        lines += "\n"
      }
      lines += "- #" +
        ticket.ticket_id +
        " " +
        ticket.title +
        " | 负责人 " +
        ticket.assignee +
        " | 截止 " +
        ticket.due_date +
        " | 已超 " +
        ticket.days_overdue.to_string() +
        " 天"
    }
    Json::object({
      "scanned": Json::number(tickets.length().to_double()),
      "sent": Json::boolean(false),
      "dryRun": Json::boolean(true),
      "reason": Json::string("provider_execution_disabled"),
      "payload": Json::object({
        "title": Json::string(
          "ERP 工单超期通知 — 共 " +
          tickets.length().to_string() +
          " 条",
        ),
        "content": Json::string(lines),
      }),
      "platforms": Json::array(enabled_platforms),
    })
  }
  let event_id = "webhook:scan_overdue:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "commandType": Json::string("scan_overdue"),
    "data": data,
    "scanned": Json::number(tickets.length().to_double()),
    "sent": Json::boolean(false),
    "dryRun": Json::boolean(true),
    "persisted": Json::boolean(true),
    "sourceKind": Json::string("command_candidate"),
    "authorizing": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "ticketMutation": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let projection = Json::object({
    "scan_id": Json::string(idempotency_key),
    "scanned": Json::number(tickets.length().to_double()),
    "sent": Json::boolean(false),
    "dry_run": Json::boolean(true),
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("webhook"),
    "command_type": Json::string("scan_overdue"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("webhook_overdue_scan"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("webhook.scan_overdue"),
    "aggregate_type": Json::string("webhook_overdue_scan"),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('webhook_overdue_scan', " +
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
