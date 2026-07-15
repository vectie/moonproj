///|
/// Native report-share links.
///
/// Share links are local, source-shaped projections. The token is an opaque
/// SHA-256-derived 48-hex identifier for deterministic replay; production
/// credential acceptance and managed public serving remain deployment gates.
/// Public data is still limited to the five allow-listed core reports.

///|
fn report_share_public_path(path : String) -> Bool {
  let prefix = "/api/company/share/"
  path.has_prefix(prefix) &&
  (path.has_suffix("/meta") || path.has_suffix("/data"))
}

///|
fn report_share_label(report_key : String) -> String? {
  if report_key == "cost" {
    Some("R1 集团成本汇总")
  } else if report_key == "contract" {
    Some("R2 合同付款台账")
  } else if report_key == "supplier" {
    Some("R3 供应商合作分析")
  } else if report_key == "approval" {
    Some("R4 审批效率分析")
  } else if report_key == "stage" {
    Some("R5 项目阶段大盘")
  } else {
    None
  }
}

///|
fn report_share_token_valid(value : String) -> Bool {
  value.length() == 48 &&
  value
  .iter()
  .all(fn(char) {
    (char >= '0' && char <= '9') ||
    (char >= 'a' && char <= 'f') ||
    (char >= 'A' && char <= 'F')
  })
}

///|
fn report_share_text(
  body : Json,
  key : String,
  fallback : String,
  max_length : Int,
) -> String raise CompanyServiceError {
  let value = match json_field(body, key) {
    Some(String(text)) => text
    Some(Null) | None => fallback
    Some(_) => raise reject(400, key + " must be text")
  }
  let trimmed = value.trim().to_owned()
  if trimmed.length() > max_length {
    raise reject(400, key + " is too long")
  }
  trimmed
}

///|
async fn report_share_now() -> String raise CompanyServiceError {
  run_sql(
    "SELECT to_char(current_timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')",
  )
  .trim()
  .to_owned()
}

///|
async fn report_share_expiry(days : Int?) -> String? raise CompanyServiceError {
  match days {
    None => None
    Some(value) => {
      let result = run_sql(
          "SELECT to_char((current_timestamp AT TIME ZONE 'UTC') + interval '" +
          value.to_string() +
          " days', 'YYYY-MM-DD HH24:MI:SS')",
        )
        .trim()
        .to_owned()
      Some(result)
    }
  }
}

///|
fn report_share_days(body : Json) -> Int? {
  match json_field(body, "expiresInDays") {
    None => Some(7)
    Some(Null) => None
    Some(Number(number, ..)) => {
      let days = number.to_int()
      if days == 0 {
        None
      } else if [1, 7, 30].contains(days) {
        Some(days)
      } else {
        Some(7)
      }
    }
    Some(String(text)) => {
      let days = parse_number(text).to_int()
      if days == 0 {
        None
      } else if [1, 7, 30].contains(days) {
        Some(days)
      } else {
        Some(7)
      }
    }
    Some(_) => Some(7)
  }
}

///|
fn report_share_token(
  idempotency_key : String,
  actor_id : String,
  report_key : String,
) -> String {
  let seed = actor_id + ":" + report_key + ":" + idempotency_key
  @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(seed)))[:48].to_owned()
}

///|
async fn report_share_projection_payloads() -> Array[(String, Json, Int)] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'report_share' ORDER BY aggregate_id, revision LIMIT 4000",
  )
  let latest : Map[String, (Json, Int)] = {}
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let token = decode_hex(row[0])
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid report share projection JSON")
      }
      latest.set(token, (payload, parse_decimal(row[1])))
    }
  }
  let result : Array[(String, Json, Int)] = []
  for token, pair in latest {
    result.push((token, pair.0, pair.1))
  }
  result
}

///|
async fn report_share_latest_projection(
  token : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'report_share' AND aggregate_id = " +
    @postgres.sql_literal(token) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid report share projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn report_share_expired(payload : Json, now : String) -> Bool {
  let expires_at = json_text(payload, "expires_at", "")
  !expires_at.is_empty() && expires_at < now
}

///|
fn report_share_list_item(payload : Json, now : String) -> Json {
  let report_key = json_text(payload, "report_key", "")
  let expires_at = json_text(payload, "expires_at", "")
  let report_label = report_share_label(report_key).unwrap_or(report_key)
  Json::object({
    "token": Json::string(json_text(payload, "token", "")),
    "reportKey": Json::string(report_key),
    "reportLabel": Json::string(report_label),
    "title": Json::string(json_text(payload, "title", report_label)),
    "createdAt": Json::string(json_text(payload, "created_at", "")),
    "expiresAt": if expires_at.is_empty() {
      Json::null()
    } else {
      Json::string(expires_at)
    },
    "neverExpires": Json::boolean(expires_at.is_empty()),
    "accessCount": Json::number(json_number(payload, "access_count", 0.0)),
    "lastAccessAt": {
      let value = json_text(payload, "last_access_at", "")
      if value.is_empty() {
        Json::null()
      } else {
        Json::string(value)
      }
    },
    "revoked": Json::boolean(json_bool(payload, "revoked", false)),
    "expired": Json::boolean(report_share_expired(payload, now)),
    "sourceKind": Json::string("command"),
  })
}

///|
async fn report_share_list_response(
  actor_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(actor_id) {
    raise reject(403, "signed actor is required")
  }
  match auth_current_user(actor_id) {
    Some(value) if json_bool(
        json_field(value, "data").unwrap_or(Json::null()),
        "enabled",
        false,
      ) => ()
    _ => raise reject(403, "user not found or disabled")
  }
  let now = report_share_now()
  let rows = report_share_projection_payloads()
  let items : Array[Json] = []
  for item in rows {
    let payload = item.1
    if json_text(payload, "created_by", "") == actor_id {
      items.push(report_share_list_item(payload, now))
    }
  }
  items.sort_by(fn(left, right) {
    json_text(right, "createdAt", "").compare(json_text(left, "createdAt", ""))
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(items),
    "source_kind": Json::string("command"),
    "source_coverage": Json::object({ "report_share_link": Json::number(0) }),
    "missing_or_empty_source_tables": Json::array([
      Json::string("report_share_link"),
    ]),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
  })
}

///|
async fn report_share_public_payload(
  token : String,
) -> (Int, Json, Json, Int)? raise CompanyServiceError {
  if !report_share_token_valid(token) {
    return None
  }
  let current = report_share_latest_projection(token)
  let (payload, revision) = match current {
    Some(value) => value
    None => return None
  }
  if json_bool(payload, "revoked", false) {
    return Some(
      (410, Json::number(40300), Json::string("链接已撤销"), revision),
    )
  }
  let now = report_share_now()
  if report_share_expired(payload, now) {
    return Some(
      (410, Json::number(41000), Json::string("链接已过期"), revision),
    )
  }
  let report_key = json_text(payload, "report_key", "")
  if report_share_label(report_key) is None {
    return Some(
      (410, Json::number(50000), Json::string("报表已下线"), revision),
    )
  }
  Some((200, payload, Json::null(), revision))
}

///|
async fn report_share_bump_access(
  token : String,
  payload : Json,
  revision : Int,
) -> Unit raise CompanyServiceError {
  let now = report_share_now()
  let fields = match payload {
    Object(values) => values
    _ => return
  }
  fields.set(
    "access_count",
    Json::number(json_number(payload, "access_count", 0.0) + 1.0),
  )
  fields.set("last_access_at", Json::string(now))
  fields.set(
    "event_id",
    Json::string(
      "report_share:access:" + token + ":" + (revision + 1).to_string(),
    ),
  )
  let next_revision = revision + 1
  let source_event = "report_share:access:" +
    token +
    ":" +
    next_revision.to_string()
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('report_share', " +
    @postgres.sql_literal(token) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(Json::object(fields).stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(source_event) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
}

///|
async fn report_share_data_for_key(
  report_key : String,
) -> Json raise CompanyServiceError {
  if report_key == "cost" {
    report_cost_summary()
  } else if report_key == "contract" {
    Json::array(report_contract_payment_ledger())
  } else if report_key == "supplier" {
    Json::array(report_supplier_analysis())
  } else if report_key == "approval" {
    report_approval_efficiency()
  } else if report_key == "stage" {
    report_project_stage_matrix()
  } else {
    raise reject(410, "报表已下线")
  }
}

///|
async fn report_share_meta_response(
  token : String,
) -> (Int, Json) raise CompanyServiceError {
  match report_share_public_payload(token) {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(40400),
          "message": Json::string("链接不存在"),
        }),
      )
    Some((status, payload, error, _)) =>
      if status != 200 {
        (
          status,
          Json::object({
            "success": Json::boolean(false),
            "code": payload,
            "message": Json::string(
              match error {
                String(value) => value
                _ => "链接不可用"
              },
            ),
          }),
        )
      } else {
        let report_key = json_text(payload, "report_key", "")
        (
          200,
          Json::object({
            "success": Json::boolean(true),
            "code": Json::number(0),
            "data": Json::object({
              "reportKey": Json::string(report_key),
              "reportLabel": Json::string(
                report_share_label(report_key).unwrap(),
              ),
              "title": Json::string(json_text(payload, "title", "")),
              "expiresAt": {
                let value = json_text(payload, "expires_at", "")
                if value.is_empty() {
                  Json::null()
                } else {
                  Json::string(value)
                }
              },
              "neverExpires": Json::boolean(
                json_text(payload, "expires_at", "").is_empty(),
              ),
            }),
            "source_kind": Json::string("command"),
            "authorizing": Json::boolean(false),
            "persisted": Json::boolean(false),
            "provider_execution": Json::boolean(false),
          }),
        )
      }
  }
}

///|
async fn report_share_data_response(
  token : String,
) -> (Int, Json) raise CompanyServiceError {
  match report_share_public_payload(token) {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(40400),
          "message": Json::string("链接不存在"),
        }),
      )
    Some((status, payload, error, revision)) =>
      if status != 200 {
        (
          status,
          Json::object({
            "success": Json::boolean(false),
            "code": payload,
            "message": Json::string(
              match error {
                String(value) => value
                _ => "链接不可用"
              },
            ),
          }),
        )
      } else {
        let data = report_share_data_for_key(
          json_text(payload, "report_key", ""),
        )
        report_share_bump_access(token, payload, revision)
        (
          200,
          Json::object({
            "success": Json::boolean(true),
            "code": Json::number(0),
            "data": data,
            "source_kind": Json::string("imported_or_command"),
            "authorizing": Json::boolean(false),
            "persisted": Json::boolean(false),
            "provider_execution": Json::boolean(false),
            "cash_effect": Json::boolean(false),
            "accounting_effect": Json::boolean(false),
            "tax_effect": Json::boolean(false),
          }),
        )
      }
  }
}

///|
fn report_share_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if path == "/api/company/reports/shares" && request_method is @http.Post {
    return Some(("create", None))
  }
  let prefix = "/api/company/reports/shares/"
  if path.has_prefix(prefix) && request_method is @http.Delete {
    let token = path[prefix.length():].to_owned()
    if report_share_token_valid(token) {
      return Some(("delete", Some(token)))
    }
  }
  None
}

///|
fn report_share_copy_fields(value : Json) -> Map[String, Json] {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = {}
      fields.each((key, item) => result.set(key, item))
      result
    }
    _ => {}
  }
}

///|
fn report_share_envelope(command : Json, data : Json, replay : Bool) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "command": command,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn report_share_command(
  command_type : String,
  token : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  match auth_current_user(actor_id) {
    Some(value) if json_bool(
        json_field(value, "data").unwrap_or(Json::null()),
        "enabled",
        false,
      ) => ()
    _ => raise reject(403, "user not found or disabled")
  }
  let request = if command_type == "create" {
    let report_key = report_share_text(body, "reportKey", "", 64)
    let label = match report_share_label(report_key) {
      Some(value) => value
      None => raise reject(400, "报表 key 无效")
    }
    let days = report_share_days(body)
    let title_value = report_share_text(body, "title", label, 255)
    let token_value = report_share_token(idempotency_key, actor_id, report_key)
    Json::object({
      "command_type": Json::string("create"),
      "token": Json::string(token_value),
      "report_key": Json::string(report_key),
      "title": Json::string(title_value),
      "expires_in_days": match days {
        Some(value) => Json::number(value.to_double())
        None => Json::null()
      },
      "actor_id": Json::string(actor_id),
    })
  } else {
    let token_value = match token {
      Some(value) if report_share_token_valid(value) => value
      _ => raise reject(422, "token is required")
    }
    Json::object({
      "command_type": Json::string("delete"),
      "token": Json::string(token_value),
      "reason": Json::string(report_share_text(body, "reason", "", 1024)),
      "actor_id": Json::string(actor_id),
    })
  }
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
        report_share_envelope(
          existing,
          json_field(existing, "result").unwrap_or(Json::null()),
          true,
        ),
      )
    }
    None => ()
  }
  let aggregate_id = json_text(request, "token", "")
  let current = report_share_latest_projection(aggregate_id)
  if command_type == "create" && current is Some(_) {
    raise reject(409, "share token already exists")
  }
  if command_type == "delete" {
    let current_payload = match current {
      Some((value, _)) => value
      None => raise reject(404, "链接不存在")
    }
    let owner = json_text(current_payload, "created_by", "")
    let profile = auth_current_user(actor_id).unwrap()
    let data = json_field(profile, "data").unwrap_or(Json::null())
    if owner != actor_id && !json_bool(data, "isSuperUser", false) {
      raise reject(403, "只能撤销自己创建的链接")
    }
  }
  let created_at = report_share_now()
  let expires_in_days = match json_field(request, "expires_in_days") {
    Some(Number(number, ..)) => Some(number.to_int())
    _ => None
  }
  let expires_at = if command_type == "create" {
    report_share_expiry(expires_in_days)
  } else {
    None
  }
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "report_share:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    Json::object({
      "token": Json::string(aggregate_id),
      "report_key": json_field(request, "report_key").unwrap(),
      "title": json_field(request, "title").unwrap(),
      "created_by": Json::string(actor_id),
      "created_at": Json::string(created_at),
      "expires_at": match expires_at {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "access_count": Json::number(0.0),
      "last_access_at": Json::null(),
      "revoked": Json::boolean(false),
      "state": Json::string("active"),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
    })
  } else {
    let fields = report_share_copy_fields(current.unwrap().0)
    fields.set("revoked", Json::boolean(true))
    fields.set("state", Json::string("revoked"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    fields.set("reason", json_field(request, "reason").unwrap())
    Json::object(fields)
  }
  let report_key = json_text(next_payload, "report_key", "")
  let data = if command_type == "create" {
    Json::object({
      "token": Json::string(aggregate_id),
      "expiresAt": match expires_at {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "reportKey": Json::string(report_key),
      "title": Json::string(json_text(next_payload, "title", "")),
      "neverExpires": Json::boolean(expires_at is None),
    })
  } else {
    Json::object({
      "token": Json::string(aggregate_id),
      "revoked": Json::boolean(true),
    })
  }
  let result = Json::object({
    "token": Json::string(aggregate_id),
    "report_key": Json::string(report_key),
    "state": Json::string(
      if command_type == "create" {
        "active"
      } else {
        "revoked"
      },
    ),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("report_share"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("report_share"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("report_share." + command_type),
    "aggregate_type": Json::string("report_share"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(revision.to_double()),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('report_share', " +
    @postgres.sql_literal(aggregate_id) +
    ", " +
    revision.to_string() +
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
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "create" {
      201
    } else {
      200
    },
    report_share_envelope(command, data, false),
  )
}
