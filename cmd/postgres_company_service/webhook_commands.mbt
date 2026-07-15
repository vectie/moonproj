///|
/// Native webhook configuration candidates.
///
/// The ERP stores three platform configurations in sys_param and can deliver
/// real messages from them.  This native boundary preserves the configuration
/// shape and update semantics, but stores only redacted candidate state: it
/// never binds credentials, calls a provider, or sends a webhook.

///|
fn webhook_platforms() -> Array[String] {
  ["feishu", "dingtalk", "wecom"]
}

///|
fn webhook_platform_label(platform : String) -> String {
  if platform == "feishu" {
    "飞书"
  } else if platform == "dingtalk" {
    "钉钉"
  } else {
    "企微"
  }
}

///|
fn webhook_platform_valid(platform : String) -> Bool {
  webhook_platforms().contains(platform)
}

///|
fn webhook_config_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Put {
    let canonical_prefix = "/api/company/webhook/config/"
    let source_prefix = "/api/company/source/webhook/config/"
    let platform = if path.has_prefix(canonical_prefix) {
      path[canonical_prefix.length():].to_owned()
    } else if path.has_prefix(source_prefix) {
      path[source_prefix.length():].to_owned()
    } else {
      ""
    }
    if !platform.is_empty() && !platform.contains("/") {
      return Some(platform)
    }
  }
  None
}

///|
async fn webhook_projection_payloads() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload FROM company_aggregate_projection WHERE aggregate_type = 'webhook_config' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 20",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid webhook projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("webhook projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn webhook_latest_projection(
  platform : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'webhook_config' AND aggregate_id = " +
    @postgres.sql_literal(platform) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid webhook projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn webhook_body_text(
  body : Map[String, Json],
  key : String,
  max_length : Int,
  trim_value : Bool,
) -> String? raise CompanyServiceError {
  match body.get(key) {
    None | Some(Null) => None
    Some(String(value)) => {
      let result = if trim_value { value.trim().to_owned() } else { value }
      if result.length() > max_length {
        raise reject(422, key + " is too long")
      }
      Some(result)
    }
    Some(_) => raise reject(422, key + " must be text")
  }
}

///|
fn webhook_body_enabled(
  body : Map[String, Json],
) -> Bool raise CompanyServiceError {
  match body.get("enabled") {
    Some(True) => true
    Some(False) => false
    None | Some(Null) => false
    _ => raise reject(422, "enabled must be boolean")
  }
}

///|
fn webhook_param_value(payload : Json, key : String) -> String {
  let first = json_text(payload, key, "")
  if !first.is_empty() {
    return first
  }
  let alternate = if key == "pk" { "key" } else { "value" }
  let second = json_text(payload, alternate, "")
  if !second.is_empty() {
    return second
  }
  if key == "pk" {
    json_text(payload, "param_key", "")
  } else {
    json_text(payload, "param_value", "")
  }
}

///|
fn webhook_text_bool(value : String) -> Bool {
  let lowered = value.to_lower()
  lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on"
}

///|
fn webhook_mask_url(value : String) -> String {
  if value.is_empty() {
    ""
  } else {
    "已配置（已脱敏）"
  }
}

///|
fn webhook_mask_secret(value : String) -> String {
  if value.is_empty() {
    ""
  } else if value.length() <= 6 {
    "****"
  } else {
    value[:3].to_owned() + "****" + value[value.length() - 3:].to_owned()
  }
}

///|
async fn webhook_source_params() -> Map[String, String] raise CompanyServiceError {
  let values : Map[String, String] = {}
  for row in raw_source_rows("sys_param", 500) {
    let key = webhook_param_value(row.payload, "pk")
    if !key.is_empty() {
      values.set(key, webhook_param_value(row.payload, "pv"))
    }
  }
  values
}

///|
fn webhook_config_entry(
  platform : String,
  enabled : Bool,
  url : String,
  url_configured : Bool,
  secret : String,
  secret_configured : Bool,
  source_kind : String,
) -> Json {
  Json::object({
    "label": Json::string(webhook_platform_label(platform)),
    "enabled": Json::boolean(enabled),
    // URLs and secrets are intentionally never returned by the native path.
    "url": Json::string(url),
    "secret": Json::string(secret),
    "hasSecret": Json::boolean(secret_configured),
    "urlConfigured": Json::boolean(url_configured),
    "secretRedacted": Json::boolean(true),
    "sourceKind": Json::string(source_kind),
    "authorizing": Json::boolean(false),
    "credentialsBound": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
  })
}

///|
async fn webhook_config_response_native() -> Json raise CompanyServiceError {
  let latest = webhook_projection_payloads()
  let by_platform : Map[String, Json] = {}
  let source_values = webhook_source_params()
  for payload in latest {
    let platform = json_text(payload, "platform", "")
    if webhook_platform_valid(platform) {
      by_platform.set(
        platform,
        webhook_config_entry(
          platform,
          json_bool(payload, "enabled", false),
          "",
          json_bool(payload, "url_configured", false),
          if json_bool(payload, "secret_configured", false) {
            "****"
          } else {
            ""
          },
          json_bool(payload, "secret_configured", false),
          "command_candidate",
        ),
      )
    }
  }
  let data : Map[String, Json] = {}
  for platform in webhook_platforms() {
    let imported_enabled = webhook_text_bool(
      source_values.get("notify.webhook." + platform + ".enabled").unwrap_or(""),
    )
    let imported_url = source_values
      .get("notify.webhook." + platform + ".url")
      .unwrap_or("")
    let imported_secret = source_values
      .get("notify.webhook." + platform + ".secret")
      .unwrap_or("")
    let imported = webhook_config_entry(
      platform,
      imported_enabled,
      webhook_mask_url(imported_url),
      !imported_url.is_empty(),
      webhook_mask_secret(imported_secret),
      !imported_secret.is_empty(),
      if imported_url.is_empty() &&
        imported_secret.is_empty() &&
        !imported_enabled {
        "imported_or_empty"
      } else {
        "imported"
      },
    )
    data.set(platform, by_platform.get(platform).unwrap_or(imported))
  }
  let coverage = observation_coverage(["sys_param"])
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object(data),
    "source_kind": Json::string(
      if latest.is_empty() && source_values.is_empty() {
        "imported_or_empty"
      } else {
        "imported_or_command"
      },
    ),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(!latest.is_empty()),
    "provider_execution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "secret_values_redacted": Json::boolean(true),
  })
}

///|
async fn webhook_config_command(
  body : Json,
  platform : String,
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
    _ => raise reject(422, "webhook config must be an object")
  }
  let enabled = webhook_body_enabled(fields)
  let url = webhook_body_text(fields, "url", 2048, true)
  let secret = webhook_body_text(fields, "secret", 4096, false)
  let secret_is_keep = match secret {
    Some(value) if value == "__keep__" => true
    _ => false
  }
  let current = webhook_latest_projection(platform)
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::object({})
  }
  let url_configured = match url {
    Some(value) => !value.is_empty()
    None => json_bool(current_payload, "url_configured", false)
  }
  let secret_configured = match secret {
    Some(value) if !secret_is_keep => !value.is_empty()
    _ => json_bool(current_payload, "secret_configured", false)
  }
  let url_digest = match url {
    Some(value) =>
      Json::string(
        @crypto.bytes_to_hex_string(
          @crypto.sha256(@encoding/utf8.encode(value)),
        ),
      )
    None => Json::null()
  }
  let secret_digest = match secret {
    Some(value) if !secret_is_keep =>
      Json::string(
        @crypto.bytes_to_hex_string(
          @crypto.sha256(@encoding/utf8.encode(value)),
        ),
      )
    _ => Json::null()
  }
  let secret_action = match secret {
    None => "unchanged"
    Some(value) if value == "__keep__" => "unchanged"
    Some(value) if value.is_empty() => "clear"
    Some(_) => "set"
  }
  let request = Json::object({
    "command_type": Json::string("config_update"),
    "actor_id": Json::string(actor),
    "platform": Json::string(platform),
    "enabled": Json::boolean(enabled),
    "url_digest": url_digest,
    "secret_action": Json::string(secret_action),
    "secret_digest": secret_digest,
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
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "webhook:config_update:" + platform + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let updated_fields : Array[Json] = [Json::string("enabled")]
  if url is Some(_) {
    updated_fields.push(Json::string("url"))
  }
  if secret_action != "unchanged" {
    updated_fields.push(Json::string("secret"))
  }
  let result = Json::object({
    "platform": Json::string(platform),
    "label": Json::string(webhook_platform_label(platform)),
    "ok": Json::boolean(true),
    "enabled": Json::boolean(enabled),
    "urlConfigured": Json::boolean(url_configured),
    "hasSecret": Json::boolean(secret_configured),
    "secretRedacted": Json::boolean(true),
    "updatedFields": Json::array(updated_fields),
    "revision": Json::number(revision.to_double()),
    "actorId": Json::string(actor),
    "sourceKind": Json::string("command_candidate"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "credentialsBound": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("webhook_config"),
    "command_type": Json::string("config_update"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("webhook_config"),
    "aggregate_id": Json::string(platform),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let payload = Json::object({
    "aggregate_id": Json::string(platform),
    "platform": Json::string(platform),
    "enabled": Json::boolean(enabled),
    "url_configured": Json::boolean(url_configured),
    "url_digest": url_digest,
    "secret_configured": Json::boolean(secret_configured),
    "secret_digest": secret_digest,
    "source_kind": Json::string("command_candidate"),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("webhook.config_update"),
    "aggregate_type": Json::string("webhook_config"),
    "aggregate_id": Json::string(platform),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "revision": Json::number(revision.to_double()),
    "credentials_bound": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('webhook_config', " +
    @postgres.sql_literal(platform) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(payload.stringify()) +
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

///|
struct WebhookOverdueTicket {
  ticket_id : String
  title : String
  assignee : String
  due_date : String
  days_overdue : Int
}

///|
fn webhook_scan_overdue_preview_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/webhook/scan-overdue/preview" ||
    path == "/api/company/source/webhook/scan-overdue/preview"
  )
}

///|
fn webhook_payload_text(
  payload : Json,
  key : String,
  alternate : String,
) -> String {
  let value = json_text(payload, key, "")
  if value.is_empty() {
    json_text(payload, alternate, "")
  } else {
    value
  }
}

///|
fn webhook_positive_int(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for char in value.iter() {
    if char < '0' || char > '9' {
      return None
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  Some(result)
}

///|
fn webhook_civil_days(year : Int, month : Int, day : Int) -> Int {
  let mut adjusted_year = year
  if month <= 2 {
    adjusted_year -= 1
  }
  let era = adjusted_year / 400
  let year_of_era = adjusted_year - era * 400
  let month_prime = month + (if month > 2 { -3 } else { 9 })
  let day_of_year = (153 * month_prime + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era
}

///|
fn webhook_date_days(value : String) -> Int? {
  if value.length() < 10 {
    return None
  }
  let parts = value[:10]
    .to_owned()
    .split("-")
    .map(fn(part) { part.to_owned() })
    .to_array()
  if parts.length() != 3 {
    return None
  }
  let year = webhook_positive_int(parts[0])
  let month = webhook_positive_int(parts[1])
  let day = webhook_positive_int(parts[2])
  match (year, month, day) {
    (Some(y), Some(m), Some(d)) if m >= 1 && m <= 12 && d >= 1 && d <= 31 =>
      Some(webhook_civil_days(y, m, d))
    _ => None
  }
}

///|
fn webhook_overdue_days(today : String, due_date : String) -> Int {
  match (webhook_date_days(today), webhook_date_days(due_date)) {
    (Some(today_days), Some(due_days)) if today_days > due_days =>
      today_days - due_days
    _ => 0
  }
}

///|
async fn webhook_overdue_tickets() -> Array[WebhookOverdueTicket] raise CompanyServiceError {
  let time_row = fields(
    run_sql(
      "SELECT to_char(current_date, 'YYYY-MM-DD'), to_char(current_timestamp - interval '24 hours', 'YYYY-MM-DD HH24:MI:SS')",
    )
    .trim()
    .to_owned(),
    2,
  )
  let today : String = time_row[0]
  let cutoff : String = time_row[1]
  let warnings : Map[String, Json] = {}
  for row in raw_source_rows("sys_warning", 500) {
    let guid = webhook_payload_text(row.payload, "warning_guid", "guid")
    if !guid.is_empty() {
      warnings.set(guid, row.payload)
    }
  }
  let users : Map[String, Json] = {}
  for row in raw_source_rows("sys_user", 500) {
    let user_id = webhook_payload_text(row.payload, "user_id", "userId")
    if !user_id.is_empty() {
      users.set(user_id, row.payload)
    }
  }
  let result : Array[WebhookOverdueTicket] = []
  for row in raw_source_rows("sys_warning_ticket", 500) {
    let status = webhook_payload_text(row.payload, "status", "state")
    let due_date = webhook_payload_text(row.payload, "due_date", "dueDate")
    let last_notified = webhook_payload_text(
      row.payload,
      "last_webhook_notified_at",
      "lastWebhookNotifiedAt",
    )
    if status != "done" &&
      due_date.length() >= 10 &&
      due_date[:10] < today &&
      (last_notified.is_empty() || last_notified < cutoff) {
      let warning_guid = webhook_payload_text(
        row.payload,
        "warning_guid",
        "warningGuid",
      )
      let warning = warnings.get(warning_guid).unwrap_or(Json::object({}))
      let assignee_id = webhook_payload_text(
        row.payload,
        "assignee_user_id",
        "assigneeUserId",
      )
      let user = users.get(assignee_id).unwrap_or(Json::object({}))
      let ticket_id = webhook_payload_text(row.payload, "ticket_id", "ticketId")
      let resolved_ticket_id = if ticket_id.is_empty() {
        row.record_id
      } else {
        ticket_id
      }
      let title = webhook_payload_text(warning, "title", "name")
      let assignee = {
        let emp = webhook_payload_text(user, "emp_name", "empName")
        if !emp.is_empty() {
          emp
        } else {
          let name = webhook_payload_text(user, "user_name", "userName")
          if !name.is_empty() {
            name
          } else {
            assignee_id
          }
        }
      }
      if result.length() < 50 {
        result.push({
          ticket_id: resolved_ticket_id,
          title: if title.is_empty() {
            "(无标题)"
          } else {
            title
          },
          assignee,
          due_date: due_date[:10].to_owned(),
          days_overdue: webhook_overdue_days(today, due_date),
        })
      }
    }
  }
  result.sort_by(fn(left, right) { left.due_date.compare(right.due_date) })
  result
}

///|
async fn webhook_scan_overdue_preview_response() -> Json raise CompanyServiceError {
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
      "reason": Json::string("no_overdue"),
    })
  } else if enabled_platforms.is_empty() {
    Json::object({
      "scanned": Json::number(tickets.length().to_double()),
      "sent": Json::boolean(false),
      "reason": Json::string("no_platform_enabled"),
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
  let coverage = observation_coverage([
    "sys_warning_ticket", "sys_warning", "sys_user", "sys_param",
  ])
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "query_execution": Json::boolean(false),
  })
}
