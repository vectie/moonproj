///|
/// Signed local notification commands.
///
/// Imported messages/subscriptions remain read-only.  These projections record
/// the user's read state and subscription intent without delivering messages,
/// invoking webhooks/email/LLM providers, or changing financial state.
fn notification_projection_type(value : String) -> Bool {
  value == "notification_message" ||
  value == "notification_subscription" ||
  value == "notification_config"
}

///|
async fn notification_projection_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if !notification_projection_type(aggregate_type) {
    raise fail("unsupported notification projection type")
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 1000",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid notification projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("notification projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn notification_latest_projection(
  aggregate_type : String,
  aggregate_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(aggregate_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid notification projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn notification_actor(
  actor_id : String,
) -> String raise CompanyServiceError {
  let profile = auth_current_user(actor_id)
  match profile {
    Some(value) => {
      let data = json_field(value, "data").unwrap_or(Json::null())
      if !json_bool(data, "enabled", false) {
        raise reject(403, "user not found or disabled")
      }
      json_text(data, "userId", actor_id)
    }
    None => raise reject(403, "user not found or disabled")
  }
}

///|
fn notification_channels(body : Json) -> Array[Json] raise CompanyServiceError {
  match json_field(body, "channels") {
    Some(Array(values)) if !values.is_empty() => {
      let result : Array[Json] = []
      for value in values {
        match value {
          String(channel) if channel == "in_app" ||
            channel == "webhook" ||
            channel == "email" => result.push(Json::string(channel))
          _ => raise reject(400, "非法通道")
        }
      }
      result
    }
    _ => raise reject(400, "至少选一个通道")
  }
}

///|
fn notification_optional_text(body : Json, key : String) -> String {
  json_text(body, key, "").trim().to_owned()
}

///|
fn notification_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/notify/messages/read-all" ||
      path == "/api/company/source/notify/messages/read-all"
    ) {
    return Some(("message_read_all", None))
  }
  let message_prefixes = [
    "/api/company/notify/messages/", "/api/company/source/notify/messages/",
  ]
  if request_method is @http.Post {
    for message_prefix in message_prefixes {
      if path.has_prefix(message_prefix) {
        let rest = path[message_prefix.length():]
          .to_owned()
          .split("/")
          .to_array()
        if rest.length() == 2 &&
          rest[1] == "read" &&
          valid_identifier(rest[0].to_owned()) {
          return Some(("message_read", Some(rest[0].to_owned())))
        }
      }
    }
  }
  if request_method is @http.Post &&
    (
      path == "/api/company/notify/subscriptions" ||
      path == "/api/company/source/notify/subscriptions"
    ) {
    return Some(("subscription_create", None))
  }
  let subscription_prefixes = [
    "/api/company/notify/subscriptions/", "/api/company/source/notify/subscriptions/",
  ]
  for subscription_prefix in subscription_prefixes {
    if path.has_prefix(subscription_prefix) {
      let id = path[subscription_prefix.length():].to_owned()
      if valid_identifier(id) {
        if request_method is @http.Patch {
          return Some(("subscription_update", Some(id)))
        }
        if request_method is @http.Delete {
          return Some(("subscription_delete", Some(id)))
        }
      }
    }
  }
  None
}

///|
fn notification_request(
  command_type : String,
  actor_id : String,
  target_id : String,
  body : Json,
) -> Json raise CompanyServiceError {
  let channels = if command_type == "subscription_create" ||
    command_type == "subscription_update" {
    if command_type == "subscription_update" &&
      json_field(body, "channels") is None {
      []
    } else {
      notification_channels(body)
    }
  } else {
    []
  }
  let request : Map[String, Json] = {}
  request.set("command_type", Json::string(command_type))
  request.set("actor_id", Json::string(actor_id))
  request.set("target_id", Json::string(target_id))
  if command_type == "subscription_create" ||
    command_type == "subscription_update" {
    request.set(
      "rule_code",
      Json::string(notification_optional_text(body, "ruleCode")),
    )
    request.set(
      "biz_type",
      Json::string(notification_optional_text(body, "bizType")),
    )
    request.set(
      "severity_min",
      json_field(body, "severityMin").unwrap_or(Json::null()),
    )
    request.set("channels", Json::array(channels))
    request.set("enabled", Json::boolean(json_bool(body, "enabled", true)))
  }
  Json::object(request)
}

///|
fn notification_command_result(
  command_type : String,
  actor_id : String,
  target_id : String,
  state : String,
  revision : Int,
  event_id : String,
  audit_id : String,
  body : Json,
  current : Json,
) -> Json {
  let mut result = Json::object({
    "commandType": Json::string(command_type),
    "targetId": Json::string(target_id),
    "actorId": Json::string(actor_id),
    "state": Json::string(state),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "sourceKind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "providerExecution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  if command_type == "message_read" {
    let fields : Map[String, Json] = match result {
      Object(values) => values
      _ => {}
    }
    fields.set("messageGuid", Json::string(target_id))
    fields.set("isRead", Json::boolean(true))
    result = Json::object(fields)
  }
  if command_type == "subscription_create" ||
    command_type == "subscription_update" {
    let fields : Map[String, Json] = match result {
      Object(values) => values
      _ => {}
    }
    fields.set("subId", Json::string(target_id))
    fields.set("userId", Json::string(actor_id))
    let current_result = json_field(current, "result").unwrap_or(current)
    fields.set(
      "ruleCode",
      Json::string(
        if json_field(body, "ruleCode") is None {
          json_text(current_result, "ruleCode", "")
        } else {
          notification_optional_text(body, "ruleCode")
        },
      ),
    )
    fields.set(
      "bizType",
      Json::string(
        if json_field(body, "bizType") is None {
          json_text(current_result, "bizType", "")
        } else {
          notification_optional_text(body, "bizType")
        },
      ),
    )
    fields.set(
      "severityMin",
      if json_field(body, "severityMin") is None {
        json_field(current_result, "severityMin").unwrap_or(Json::null())
      } else {
        json_field(body, "severityMin").unwrap_or(Json::null())
      },
    )
    fields.set(
      "channels",
      if json_field(body, "channels") is None {
        json_field(current_result, "channels").unwrap_or(Json::array([]))
      } else {
        json_field(body, "channels").unwrap_or(Json::array([]))
      },
    )
    fields.set(
      "enabled",
      if json_field(body, "enabled") is None {
        json_field(current_result, "enabled").unwrap_or(Json::boolean(true))
      } else {
        Json::boolean(json_bool(body, "enabled", true))
      },
    )
    result = Json::object(fields)
  }
  result
}

///|
async fn notification_command(
  command_type : String,
  target_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = notification_actor(actor_id)
  let target = match target_id {
    Some(value) => value
    None => ""
  }
  let request = notification_request(command_type, actor, target, body)
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
  let aggregate_type = if command_type == "message_read" ||
    command_type == "message_read_all" {
    "notification_message"
  } else {
    "notification_subscription"
  }
  let aggregate_id = if command_type == "message_read_all" {
    "message-all:" + actor
  } else if command_type == "message_read" {
    "message:" + actor + ":" + target
  } else if command_type == "subscription_create" {
    "sub-" + idempotency_key
  } else {
    target
  }
  if command_type == "subscription_update" ||
    command_type == "subscription_delete" {
    if notification_latest_projection(aggregate_type, aggregate_id) is None {
      raise reject(404, "订阅不存在")
    }
  }
  let current = notification_latest_projection(aggregate_type, aggregate_id)
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_revision = current_revision + 1
  let state = if command_type == "subscription_delete" {
    "deleted"
  } else if command_type == "message_read" || command_type == "message_read_all" {
    "read"
  } else {
    "active"
  }
  let event_id = "notification:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let changed_at = report_share_now()
  let result_target = if command_type == "message_read" {
    target
  } else {
    aggregate_id
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let result = notification_command_result(
    command_type, actor, result_target, state, next_revision, event_id, audit_id,
    body, current_payload,
  )
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
  let next_payload = Json::object({
    "aggregate_id": Json::string(aggregate_id),
    "messageGuid": if command_type == "message_read" {
      Json::string(target)
    } else {
      Json::string("")
    },
    "subId": if aggregate_type == "notification_subscription" {
      Json::string(aggregate_id)
    } else {
      Json::string("")
    },
    "userId": Json::string(actor),
    "state": Json::string(state),
    "status": Json::string(state),
    "sourceKind": Json::string("command"),
    "changedAt": Json::string(changed_at),
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("notification." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "state": Json::string(state),
    "revision": Json::number(next_revision.to_double()),
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
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(next_payload.stringify()) +
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
async fn notification_messages_response_native(
  actor_id : String,
) -> Json raise CompanyServiceError {
  let effective_actor = if actor_id.is_empty() {
    ""
  } else {
    notification_actor(actor_id)
  }
  let coverage = observation_coverage(notification_tables())
  let message_states : Map[String, Json] = {}
  let mut read_all = false
  let mut command_count = 0
  for command in notification_projection_payloads("notification_message") {
    if json_text(command, "userId", "") == effective_actor &&
      json_text(command, "state", "") == "read" {
      command_count += 1
      let message_guid = json_text(command, "messageGuid", "")
      if message_guid.is_empty() {
        read_all = true
      } else {
        message_states.set(message_guid, command)
      }
    }
  }
  let rows : Array[Json] = []
  for source in raw_source_rows("sys_message", 500) {
    let user = json_text(
      source.payload,
      "user_id",
      json_text(source.payload, "userId", ""),
    )
    if effective_actor.is_empty() || user == effective_actor || user == actor_id {
      let message_guid = json_text(
        source.payload,
        "message_guid",
        json_text(source.payload, "messageGuid", source.record_id),
      )
      match message_states.get(message_guid) {
        Some(command) => {
          let fields : Map[String, Json] = match source.payload {
            Object(values) => values
            _ => {}
          }
          fields.set("is_read", Json::number(1))
          fields.set("isRead", Json::boolean(true))
          fields.set(
            "read_at",
            json_field(command, "changedAt").unwrap_or(Json::null()),
          )
          fields.set("sourceKind", Json::string("imported_or_command"))
          rows.push(Json::object(fields))
        }
        None if read_all => {
          let fields : Map[String, Json] = match source.payload {
            Object(values) => values
            _ => {}
          }
          fields.set("is_read", Json::number(1))
          fields.set("isRead", Json::boolean(true))
          fields.set("sourceKind", Json::string("imported_or_command"))
          rows.push(Json::object(fields))
        }
        None => rows.push(source.payload)
      }
    }
  }
  notification_command_envelope(
    Json::object({
      "total": Json::number(rows.length().to_double()),
      "rows": Json::array(rows),
    }),
    coverage,
    command_count,
  )
}

///|
async fn notification_unread_response_native(
  actor_id : String,
) -> Json raise CompanyServiceError {
  let effective_actor = if actor_id.is_empty() {
    ""
  } else {
    notification_actor(actor_id)
  }
  let coverage = observation_coverage(notification_tables())
  let message_states : Map[String, Bool] = {}
  let mut read_all = false
  let mut command_count = 0
  for command in notification_projection_payloads("notification_message") {
    if json_text(command, "userId", "") == effective_actor &&
      json_text(command, "state", "") == "read" {
      command_count += 1
      let message_guid = json_text(command, "messageGuid", "")
      if message_guid.is_empty() {
        read_all = true
      } else {
        message_states.set(message_guid, true)
      }
    }
  }
  let mut count = 0
  for source in raw_source_rows("sys_message", 500) {
    let user = json_text(
      source.payload,
      "user_id",
      json_text(source.payload, "userId", ""),
    )
    let message_guid = json_text(
      source.payload,
      "message_guid",
      json_text(source.payload, "messageGuid", source.record_id),
    )
    if (
        effective_actor.is_empty() ||
        user == effective_actor ||
        user == actor_id
      ) &&
      !json_bool(
        source.payload,
        "is_read",
        json_bool(source.payload, "isRead", false),
      ) &&
      !read_all &&
      message_states.get(message_guid) is None {
      count += 1
    }
  }
  notification_command_envelope(
    Json::object({ "count": Json::number(count.to_double()) }),
    coverage,
    command_count,
  )
}

///|
async fn notification_subscriptions_response_native(
  actor_id : String,
) -> Json raise CompanyServiceError {
  let effective_actor = if actor_id.is_empty() {
    ""
  } else {
    notification_actor(actor_id)
  }
  let coverage = observation_coverage(notification_tables())
  let mut command_count = 0
  let rows : Array[Json] = []
  for source in raw_source_rows("sys_warning_subscription", 500) {
    let user = json_text(
      source.payload,
      "user_id",
      json_text(source.payload, "userId", ""),
    )
    if effective_actor.is_empty() || user == effective_actor || user == actor_id {
      rows.push(source.payload)
    }
  }
  for command in notification_projection_payloads("notification_subscription") {
    if json_text(command, "userId", "") == effective_actor &&
      json_text(command, "state", "active") != "deleted" {
      command_count += 1
      rows.push(json_field(command, "result").unwrap_or(command))
    }
  }
  notification_command_envelope(Json::array(rows), coverage, command_count)
}

///|
fn notification_command_envelope(
  data : Json,
  coverage : Map[String, Int],
  count : Int,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(count > 0),
    "provider_execution": Json::boolean(false),
    "delivery_effect": Json::boolean(false),
    "query_execution": Json::boolean(false),
  })
}

///|
/// Configuration candidates are allow-listed and redacted.  They do not
/// replace the managed provider secret store or enable delivery.
fn notification_config_keys() -> Array[String] {
  [
    "notify.webhook.url", "notify.webhook.kind", "notify.email.from", "notify.email.enabled",
    "notify.email.smtp.host", "notify.email.smtp.port", "notify.email.smtp.user",
    "notify.email.smtp.pass", "notify.email.smtp.secure", "ai.ocr.provider", "ai.ocr.http.url",
    "ai.llm.provider", "ai.llm.key", "ai.llm.model", "ai.llm.endpoint", "ai.llm.fallback_providers",
    "notify.digest.enabled", "notify.digest.hour", "notify.ticket_email.enabled",
    "notify.ticket_webhook.enabled",
  ]
}

///|
fn notification_config_secret(key : String) -> Bool {
  key.has_suffix(".pass") ||
  key.has_suffix(".key") ||
  key.has_suffix(".secret") ||
  key.has_suffix(".token")
}

///|
fn notification_value_text(value : Json) -> String {
  match value {
    String(text) => text
    Number(number, ..) => number.to_string()
    True => "true"
    False => "false"
    Null => ""
    _ => value.stringify()
  }
}

///|
fn notification_config_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Put &&
  (
    path == "/api/company/notify/config" ||
    path == "/api/company/source/notify/config"
  )
}

///|
async fn notification_config_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let values : Map[String, Json] = match body {
    Object(fields) => fields
    _ => raise reject(422, "notification config must be an object")
  }
  let entries : Array[Json] = []
  let request_entries : Array[Json] = []
  for key, value in values {
    if notification_config_keys().contains(key) {
      let text = notification_value_text(value)
      if text.length() > 4096 {
        raise reject(422, "notification config value is too large")
      }
      let digest = @crypto.bytes_to_hex_string(
        @crypto.sha256(@encoding/utf8.encode(text)),
      )
      let secret = notification_config_secret(key)
      entries.push(
        Json::object({
          "key": Json::string(key),
          "configured": Json::boolean(!text.is_empty()),
          "redacted": Json::boolean(secret),
          "value": if secret {
            Json::null()
          } else {
            Json::string(text)
          },
        }),
      )
      request_entries.push(
        Json::object({
          "key": Json::string(key),
          "digest": Json::string(digest),
          "configured": Json::boolean(!text.is_empty()),
        }),
      )
    }
  }
  let request = Json::object({
    "command_type": Json::string("config_update"),
    "actor_id": Json::string(actor),
    "entries": Json::array(request_entries),
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
  let aggregate_id = "notification-config"
  let current = notification_latest_projection(
    "notification_config", aggregate_id,
  )
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "notification:config_update:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "updated": Json::number(entries.length().to_double()),
    "entries": Json::array(entries),
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
    "command_family": Json::string("notification_config"),
    "command_type": Json::string("config_update"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("notification_config"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let payload = Json::object({
    "aggregate_id": Json::string(aggregate_id),
    "state": Json::string("active"),
    "sourceKind": Json::string("command_candidate"),
    "actorId": Json::string(actor),
    "entries": Json::array(entries),
    "credentialsBound": Json::boolean(false),
    "event_id": Json::string(event_id),
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("notification.config_update"),
    "aggregate_type": Json::string("notification_config"),
    "aggregate_id": Json::string(aggregate_id),
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
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('notification_config', " +
    @postgres.sql_literal(aggregate_id) +
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
async fn notification_config_response_native() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(notification_tables())
  let mut configured : Array[Json] = []
  let mut command_count = 0
  for payload in notification_projection_payloads("notification_config") {
    command_count += 1
    match json_field(payload, "entries") {
      Some(Array(entries)) => configured = entries
      _ => ()
    }
  }
  notification_command_envelope(
    Json::object({ "configured": Json::array(configured) }),
    coverage,
    command_count,
  )
}
