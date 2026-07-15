///|
/// Email outbox command candidates.
///
/// The source ERP queues or re-delivers email through the outbox worker. The
/// native migration boundary records the requested operation and source row
/// evidence, but never inserts/updates an outbox row or opens SMTP.
fn notification_email_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/notify/email-outbox/test" ||
      path == "/api/company/source/notify/email-outbox/test"
    ) {
    return Some(("email_test", None))
  }
  let prefixes = [
    "/api/company/notify/email-outbox/", "/api/company/source/notify/email-outbox/",
  ]
  if request_method is @http.Post {
    for prefix in prefixes {
      if path.has_prefix(prefix) {
        let suffix = path[prefix.length():].to_owned()
        if suffix.has_suffix("/redeliver") {
          let eid = suffix[:suffix.length() - "/redeliver".length()].to_owned()
          if valid_identifier(eid) {
            return Some(("email_redeliver", Some(eid)))
          }
        }
      }
    }
  }
  None
}

///|
fn notification_email_text(value : String) -> String {
  value.trim().to_owned()
}

///|
fn notification_email_mask(value : String) -> String {
  if value.is_empty() {
    ""
  } else {
    "已配置（已脱敏）"
  }
}

///|
fn notification_email_enabled(value : String) -> Bool {
  let lowered = value.to_lower()
  lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on"
}

///|
async fn notification_email_source_row(
  eid : String,
) -> Json? raise CompanyServiceError {
  for row in raw_source_rows("sys_email_outbox", 500) {
    let row_eid = json_text(row.payload, "eid", row.record_id)
    if row_eid == eid {
      return Some(row.payload)
    }
  }
  None
}

///|
async fn notification_email_command(
  command_type : String,
  target_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let target = target_id.unwrap_or("")
  let fields : Map[String, Json] = match body {
    Object(values) => values
    _ if command_type == "email_test" =>
      raise reject(422, "email test body must be an object")
    _ => {}
  }
  let requested_to = notification_email_text(
    notification_value_text(fields.get("to").unwrap_or(Json::null())),
  )
  let to = if command_type == "email_test" {
    if requested_to.is_empty() {
      actor + "@example.com"
    } else {
      requested_to
    }
  } else {
    ""
  }
  if command_type == "email_test" && to.length() > 320 {
    raise reject(422, "email recipient is too long")
  }
  if command_type == "email_redeliver" &&
    notification_email_source_row(target) is None {
    raise reject(404, "email outbox record not found")
  }
  let request = Json::object({
    "command_type": Json::string(command_type),
    "actor_id": Json::string(actor),
    "target_id": Json::string(target),
    "to": if command_type == "email_test" {
      Json::string(to)
    } else {
      Json::null()
    },
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
  let event_id = "notification:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let email_enabled_value = notification_effective_config(
    "notify.email.enabled",
  )
  let email_enabled = notification_email_enabled(email_enabled_value.0)
  let result = if command_type == "email_test" {
    Json::object({
      "commandType": Json::string("email_test"),
      "queued": Json::boolean(false),
      "wouldQueue": Json::boolean(true),
      "dryRun": Json::boolean(true),
      "to": Json::string(notification_email_mask(to)),
      "toConfigured": Json::boolean(true),
      "emailEnabled": Json::boolean(email_enabled),
      "reason": Json::string("provider_execution_disabled"),
      "sourceKind": Json::string("command_candidate"),
      "persisted": Json::boolean(true),
      "authorizing": Json::boolean(false),
      "providerExecution": Json::boolean(false),
      "delivery_effect": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    })
  } else {
    let source = notification_email_source_row(target).unwrap_or(
      Json::object({}),
    )
    let status = json_text(source, "status", "")
    let eligible = status == "queued" || status == "failed"
    Json::object({
      "commandType": Json::string("email_redeliver"),
      "eid": Json::string(target),
      "found": Json::boolean(true),
      "status": Json::string(status),
      "queued": Json::boolean(false),
      "wouldRedeliver": Json::boolean(eligible),
      "dryRun": Json::boolean(true),
      "reason": Json::string(
        if eligible {
          "provider_execution_disabled"
        } else if status == "sent" {
          "already_sent"
        } else {
          "not_redeliverable"
        },
      ),
      "sourceKind": Json::string("command_candidate"),
      "persisted": Json::boolean(true),
      "authorizing": Json::boolean(false),
      "providerExecution": Json::boolean(false),
      "delivery_effect": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    })
  }
  let aggregate_type = if command_type == "email_test" {
    "notification_email_test"
  } else {
    "notification_email_redeliver"
  }
  let aggregate_id = if command_type == "email_test" {
    idempotency_key
  } else {
    target
  }
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("notification"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let projection = Json::object({
    "aggregate_id": Json::string(aggregate_id),
    "command_type": Json::string(command_type),
    "target_id": Json::string(target),
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "dry_run": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("notification." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(aggregate_type) +
    ", " +
    @postgres.sql_literal(aggregate_id) +
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
