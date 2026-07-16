///|
/// Native command-owned overlay for the ERP `my_biz_param_option` CRUD.
/// Imported dictionary rows remain read-only; local rows carry explicit
/// command provenance and never imply provider, cash, accounting, or tax work.

///|
fn admin_dict_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/admin/dict/options" ||
      path == "/api/company/source/admin/dict/options"
    ) {
    return Some(("create", None))
  }
  let prefixes = [
    "/api/company/admin/dict/options/", "/api/company/source/admin/dict/options/",
  ]
  for prefix in prefixes {
    if request_method is @http.Patch && path.has_prefix(prefix) {
      let guid = path[prefix.length():].to_owned()
      if valid_identifier(guid) {
        return Some(("update", Some(guid)))
      }
    }
  }
  None
}

///|
fn admin_dict_body_text(
  body : Json,
  key : String,
  alternate : String,
) -> String {
  let value = json_text(body, key, "")
  if value.is_empty() {
    json_text(body, alternate, "")
  } else {
    value
  }
}

///|
fn admin_dict_field(body : Json, key : String, alternate : String) -> Json? {
  match json_field(body, key) {
    Some(value) => Some(value)
    None => json_field(body, alternate)
  }
}

///|
fn admin_dict_sensitive(group_name : String, code : String) -> Bool {
  admin_sys_param_sensitive(group_name + "." + code)
}

///|
fn admin_dict_display_order(body : Json) -> Int raise CompanyServiceError {
  match admin_dict_field(body, "displayOrder", "display_order") {
    None | Some(Null) => 0
    Some(Number(value, ..)) if value == value.trunc() && value >= 0.0 =>
      value.to_int()
    _ => raise reject(422, "displayOrder must be a non-negative integer")
  }
}

///|
fn admin_dict_enabled(body : Json) -> Bool? {
  match json_field(body, "enabled") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Number(value, ..)) => Some(value != 0.0)
    None | Some(Null) => None
    _ => None
  }
}

///|
async fn admin_dict_latest_projection(
  guid : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'admin_dict_option' AND aggregate_id = " +
    @postgres.sql_literal(guid) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid dictionary projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn admin_dict_imported_guid(
  guid : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows("my_biz_param_option", 500)
  rows.any(fn(row) {
    json_text(row.payload, "param_guid", row.record_id) == guid ||
    json_text(row.payload, "id", "") == guid
  })
}

///|
async fn admin_dict_duplicate(
  group_name : String,
  code : String,
) -> Bool raise CompanyServiceError {
  let imported = raw_source_rows("my_biz_param_option", 500)
  if imported.any(fn(row) {
      json_text(row.payload, "param_name", "") == group_name &&
      json_text(row.payload, "param_code", "") == code
    }) {
    return true
  }
  let output = run_sql(
    "SELECT 1 FROM company_aggregate_projection WHERE aggregate_type = 'admin_dict_option' AND payload->>'param_name' = " +
    @postgres.sql_literal(group_name) +
    " AND payload->>'param_code' = " +
    @postgres.sql_literal(code) +
    " AND payload->>'state' <> 'deleted' LIMIT 1",
  )
  !output.trim().is_empty()
}

///|
fn admin_dict_value_payload(value : String, sensitive : Bool) -> (Json, Json) {
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(value)),
  )
  if sensitive {
    (
      Json::object({
        "value_digest": Json::string(digest),
        "value_length": Json::number(value.length().to_double()),
      }),
      Json::object({
        "value": Json::null(),
        "valueDigest": Json::string(digest),
        "valueLength": Json::number(value.length().to_double()),
        "valueRedacted": Json::boolean(true),
      }),
    )
  } else {
    (
      Json::object({ "value": Json::string(value) }),
      Json::object({
        "value": Json::string(value),
        "valueDigest": Json::string(digest),
        "valueLength": Json::number(value.length().to_double()),
        "valueRedacted": Json::boolean(false),
      }),
    )
  }
}

///|
async fn admin_dict_command(
  command_type : String,
  target_guid : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor = rbac_require_super(actor_id)
  let (aggregate_id, request, current, next_payload, updated) = if command_type ==
    "create" {
    let group_name = admin_dict_body_text(body, "groupName", "group_name")
      .trim()
      .to_owned()
    let code = admin_dict_body_text(body, "code", "param_code")
      .trim()
      .to_owned()
    let value = admin_dict_body_text(body, "value", "param_value")
    if !valid_identifier(group_name) ||
      !valid_identifier(code) ||
      value.is_empty() {
      raise reject(400, "字典分组/编码/值都必填")
    }
    let already_recorded = match existing_company_command(idempotency_key) {
      Some(_) => true
      None => false
    }
    if admin_dict_duplicate(group_name, code) && !already_recorded {
      raise reject(400, "同分组内编码重复")
    }
    let display_order = admin_dict_display_order(body)
    let guid = "local-" + idempotency_key
    let sensitive = admin_dict_sensitive(group_name, code)
    let (request_value, _) = admin_dict_value_payload(value, sensitive)
    let request = Json::object({
      "command_type": Json::string("create"),
      "aggregate_type": Json::string("admin_dict_option"),
      "aggregate_id": Json::string(guid),
      "actor_id": Json::string(actor),
      "group_name": Json::string(group_name),
      "code": Json::string(code),
      "display_order": Json::number(display_order.to_double()),
      "value": request_value,
    })
    let payload = Json::object({
      "param_guid": Json::string(guid),
      "param_name": Json::string(group_name),
      "param_code": Json::string(code),
      "param_value": if sensitive {
        Json::null()
      } else {
        Json::string(value)
      },
      "value_digest": json_field(request_value, "value_digest").unwrap_or(
        Json::null(),
      ),
      "value_length": Json::number(value.length().to_double()),
      "display_order": Json::number(display_order.to_double()),
      "enabled": Json::boolean(true),
    })
    (guid, request, None, payload, 0)
  } else {
    let guid = match target_guid {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "字典项标识不能为空")
    }
    if admin_dict_imported_guid(guid) {
      raise reject(
        409, "导入字典项为只读，请使用本地字典编码",
      )
    }
    let current = match admin_dict_latest_projection(guid) {
      Some(value) => value
      None => raise reject(404, "字典项不存在")
    }
    let current_payload = current.0
    let group_name = json_text(current_payload, "param_name", "")
    let code = json_text(current_payload, "param_code", "")
    let sensitive = admin_dict_sensitive(group_name, code)
    let request_fields : Map[String, Json] = {
      "command_type": Json::string("update"),
      "aggregate_type": Json::string("admin_dict_option"),
      "aggregate_id": Json::string(guid),
      "actor_id": Json::string(actor),
    }
    let next_fields : Map[String, Json] = match current_payload {
      Object(fields) => fields
      _ => {}
    }
    let mut changed = 0
    match json_field(body, "value") {
      Some(String(value)) => {
        if value.is_empty() {
          raise reject(400, "字典值不能为空")
        }
        let (request_value, _) = admin_dict_value_payload(value, sensitive)
        request_fields.set("value", request_value)
        next_fields.set(
          "param_value",
          if sensitive {
            Json::null()
          } else {
            Json::string(value)
          },
        )
        next_fields.set(
          "value_digest",
          json_field(request_fields.get("value").unwrap(), "value_digest").unwrap_or(
            Json::null(),
          ),
        )
        next_fields.set(
          "value_length",
          Json::number(value.length().to_double()),
        )
        changed += 1
      }
      None | Some(Null) => ()
      _ => raise reject(422, "value must be a string")
    }
    match admin_dict_enabled(body) {
      Some(enabled) => {
        request_fields.set("enabled", Json::boolean(enabled))
        next_fields.set("enabled", Json::boolean(enabled))
        changed += 1
      }
      None => ()
    }
    match admin_dict_field(body, "displayOrder", "display_order") {
      Some(_) => {
        let display_order = admin_dict_display_order(body)
        request_fields.set(
          "display_order",
          Json::number(display_order.to_double()),
        )
        next_fields.set(
          "display_order",
          Json::number(display_order.to_double()),
        )
        changed += 1
      }
      None => ()
    }
    if changed == 0 {
      request_fields.set("noop", Json::boolean(true))
    }
    (
      guid,
      Json::object(request_fields),
      Some(current),
      Json::object(next_fields),
      changed,
    )
  }
  let request = request
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
          "dictionary": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_revision = current_revision + 1
  let event_id = "admin:dict:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let payload_fields : Map[String, Json] = match next_payload {
    Object(fields) => fields
    _ => {}
  }
  payload_fields.set("source_kind", Json::string("command"))
  payload_fields.set("event_id", Json::string(event_id))
  payload_fields.set("updated_by", Json::string(actor))
  payload_fields.set("state", Json::string("active"))
  let persisted_payload = Json::object(payload_fields)
  let value_output = if (match json_field(persisted_payload, "value_digest") {
      Some(Null) | None => false
      Some(_) => true
    }) {
    Json::object({
      "value": Json::null(),
      "valueDigest": json_field(persisted_payload, "value_digest").unwrap_or(
        Json::null(),
      ),
      "valueLength": json_field(persisted_payload, "value_length").unwrap_or(
        Json::number(0),
      ),
      "valueRedacted": Json::boolean(true),
    })
  } else {
    Json::object({
      "value": json_field(persisted_payload, "param_value").unwrap_or(
        Json::string(""),
      ),
      "valueRedacted": Json::boolean(false),
    })
  }
  let result = Json::object({
    "paramGuid": Json::string(aggregate_id),
    "groupName": Json::string(json_text(persisted_payload, "param_name", "")),
    "code": Json::string(json_text(persisted_payload, "param_code", "")),
    "displayOrder": json_field(persisted_payload, "display_order").unwrap_or(
      Json::number(0),
    ),
    "enabled": json_field(persisted_payload, "enabled").unwrap_or(
      Json::boolean(true),
    ),
    "updated": Json::number(updated.to_double()),
    "sourceKind": Json::string("command"),
    "commandProjection": Json::boolean(true),
    "persisted": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "authorizationCandidate": Json::boolean(true),
    "providerExecution": Json::boolean(false),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
    "eventId": Json::string(event_id),
    "auditId": Json::string(audit_id),
    "revision": Json::number(next_revision.to_double()),
    "value": value_output,
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("admin_dictionary"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("admin_dict_option"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("admin.dictionary." + command_type),
    "aggregate_type": Json::string("admin_dict_option"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "revision": Json::number(next_revision.to_double()),
    "authorizing": Json::boolean(false),
    "authorization_candidate": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('admin_dict_option', " +
    @postgres.sql_literal(aggregate_id) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(persisted_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
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
    Json::object({
      "command": command_payload,
      "dictionary": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
async fn admin_dict_command_payloads() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'admin_dict_option' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let rows : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let payload = @json.parse(decode_hex(line)) catch {
        _ => raise fail("invalid dictionary projection JSON")
      }
      rows.push(payload)
    }
  }
  rows
}
