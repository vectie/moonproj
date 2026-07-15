///|
/// Command-owned CBS plan-version and subject-dictionary lifecycle.
///
/// Imported CBS rows stay read-only.  Local commands provide the source
/// system's draft/clone/freeze/activate workflow without mutating imported
/// records or consuming budget.

///|
async fn cbs_projection_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "cbs_plan_version" &&
    aggregate_type != "cbs_subject_dict" &&
    aggregate_type != "cbs_approval_rule" &&
    aggregate_type != "cbs_demo_contract" &&
    aggregate_type != "cbs_change" {
    raise fail("unsupported CBS projection type")
  }
  let output = run_sql(
    "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 2000",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let payload = @json.parse(decode_hex(line)) catch {
        _ => raise fail("invalid CBS projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("CBS projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn cbs_latest_projection(
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
    _ => raise fail("invalid CBS projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn cbs_command_envelope(data : Json, command : Json, replay : Bool) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "command": command,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("imported_or_command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn cbs_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if path == "/api/company/cbs/dict/batch-adjust" &&
    request_method is @http.Post {
    return Some("dict_batch_adjust")
  }
  if path == "/api/company/cbs/dict" && request_method is @http.Post {
    return Some("dict_add")
  }
  if path == "/api/company/cbs/versions/clone" && request_method is @http.Post {
    return Some("version_clone")
  }
  if path == "/api/company/cbs/versions/freeze" && request_method is @http.Post {
    return Some("version_freeze")
  }
  if path == "/api/company/cbs/versions/activate" &&
    request_method is @http.Post {
    return Some("version_activate")
  }
  None
}

///|
fn cbs_body_text(body : Json, primary : String, alternate : String) -> String {
  let value = json_text(body, primary, "").trim().to_owned()
  if value.is_empty() {
    json_text(body, alternate, "").trim().to_owned()
  } else {
    value
  }
}

///|
async fn cbs_require_user(
  actor_id : String,
) -> String raise CompanyServiceError {
  match auth_current_user(actor_id) {
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
async fn cbs_version_payload(
  proj_guid : String,
  plan_version : String,
) -> Json? raise CompanyServiceError {
  match cbs_latest_projection("cbs_plan_version", plan_version) {
    Some((payload, _)) if json_text(payload, "state", "active") != "deleted" =>
      Some(payload)
    _ => {
      let rows = raw_source_rows("cb_plan_version", 1000)
      for row in rows {
        if report_text(row.payload, "proj_guid", "") == proj_guid &&
          report_text(row.payload, "plan_version", row.record_id) ==
          plan_version &&
          json_field(row.payload, "deleted_at") is None {
          return Some(row.payload)
        }
      }
      None
    }
  }
}

///|
async fn cbs_dict_payloads(
  proj_guid : String,
  plan_version : String,
) -> Array[Json] raise CompanyServiceError {
  let mut result : Array[Json] = []
  let imported = raw_source_rows("cb_subject_dict", 5000)
  for row in imported {
    if report_text(row.payload, "proj_guid", "") == proj_guid &&
      report_text(row.payload, "plan_version", "baseline") == plan_version &&
      json_field(row.payload, "deleted_at") is None {
      result.push(row.payload)
    }
  }
  let local_rows = cbs_projection_payloads("cbs_subject_dict")
  for payload in local_rows {
    if report_text(payload, "proj_guid", "") == proj_guid &&
      report_text(payload, "plan_version", "") == plan_version &&
      json_text(payload, "state", "active") != "deleted" {
      let id = report_text(payload, "dict_guid", "")
      result = result.filter(fn(value) {
        report_text(value, "dict_guid", "") != id
      })
      result.push(payload)
    }
  }
  result
}

///|
fn cbs_copy_fields(payload : Json) -> Map[String, Json] {
  let result : Map[String, Json] = {}
  match payload {
    Object(values) => values.each((key, value) => result.set(key, value))
    _ => ()
  }
  result
}

///|
async fn cbs_command(
  command_type : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user_id = cbs_require_user(actor_id)
  let proj_guid = cbs_body_text(body, "projGuid", "proj_guid")
  if proj_guid.is_empty() || !valid_identifier(proj_guid) {
    raise reject(400, "projGuid is required")
  }
  let plan_version = cbs_body_text(body, "planVersion", "plan_version")
  let (aggregate_type, aggregate_id, request, result_data) = if command_type ==
    "version_clone" {
    let base = cbs_body_text(body, "basePlanVersion", "base_plan_version")
    let name = cbs_body_text(body, "newName", "new_name")
    if base.is_empty() || name.is_empty() {
      raise reject(400, "basePlanVersion and newName are required")
    }
    if cbs_version_payload(proj_guid, base) is None {
      raise reject(404, "base CBS version not found")
    }
    let id = "cbs-version-" + idempotency_key
    if cbs_version_payload(proj_guid, id) is Some(_) {
      raise reject(409, "CBS version already exists")
    }
    (
      "cbs_plan_version",
      id,
      Json::object({
        "command_type": Json::string(command_type),
        "proj_guid": Json::string(proj_guid),
        "plan_version": Json::string(id),
        "version_name": Json::string(name),
        "parent_version": Json::string(base),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      Json::object({
        "planVersion": Json::string(id),
        "versionName": Json::string(name),
      }),
    )
  } else if command_type == "version_freeze" ||
    command_type == "version_activate" {
    if plan_version.is_empty() {
      raise reject(400, "planVersion is required")
    }
    let current = match
      cbs_latest_projection("cbs_plan_version", plan_version) {
      Some((value, _)) => value
      None => {
        if cbs_version_payload(proj_guid, plan_version) is Some(_) {
          raise reject(409, "imported CBS versions are read-only")
        }
        raise reject(404, "CBS version not found")
      }
    }
    if report_text(current, "proj_guid", "") != proj_guid {
      raise reject(409, "CBS version does not belong to project")
    }
    if command_type == "version_freeze" &&
      !json_text(current, "frozen_at", "").is_empty() {
      raise reject(409, "CBS version is already frozen")
    }
    (
      "cbs_plan_version",
      plan_version,
      Json::object({
        "command_type": Json::string(command_type),
        "proj_guid": Json::string(proj_guid),
        "plan_version": Json::string(plan_version),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      Json::object({ "planVersion": Json::string(plan_version) }),
    )
  } else if command_type == "dict_add" {
    if plan_version.is_empty() {
      raise reject(400, "planVersion is required")
    }
    let version = match
      cbs_latest_projection("cbs_plan_version", plan_version) {
      Some((value, _)) => value
      None => {
        if cbs_version_payload(proj_guid, plan_version) is Some(_) {
          raise reject(409, "imported CBS versions are read-only")
        }
        raise reject(404, "CBS version not found")
      }
    }
    if !json_text(version, "frozen_at", "").is_empty() {
      raise reject(409, "CBS version is frozen")
    }
    let l2_code = cbs_body_text(body, "l2Code", "l2_code")
    let subject = cbs_body_text(body, "subject", "")
    if l2_code.is_empty() || subject.is_empty() {
      raise reject(400, "l2Code and subject are required")
    }
    let peers = cbs_dict_payloads(proj_guid, plan_version)
    let mut max_num = 0
    let prefix = l2_code + "."
    for value in peers {
      let code = report_text(value, "l3_code", "")
      if code.has_prefix(prefix) {
        let suffix = code[prefix.length():].to_owned()
        let n = parse_decimal(suffix)
        if n > max_num {
          max_num = n
        }
      }
    }
    let next_leaf = (max_num + 1).to_string()
    let padded_leaf = if next_leaf.length() < 2 {
      "0" + next_leaf
    } else {
      next_leaf
    }
    let l3_code = prefix + padded_leaf
    let id = "cbs-dict-" + idempotency_key
    let l2_name = cbs_body_text(body, "l2Name", "l2_name")
    let r_code = l2_code.split(".").to_array()[0].to_owned()
    (
      "cbs_subject_dict",
      id,
      Json::object({
        "command_type": Json::string(command_type),
        "dict_guid": Json::string(id),
        "proj_guid": Json::string(proj_guid),
        "plan_version": Json::string(plan_version),
        "l3_code": Json::string(l3_code),
        "r_code": Json::string(r_code),
        "l2_code": Json::string(l2_code),
        "l2_name": Json::string(l2_name),
        "subject": Json::string(subject),
        "plan_amount": Json::number(
          json_number(body, "planAmount", json_number(body, "plan_amount", 0.0)),
        ),
        "src": Json::string("manual"),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      Json::object({
        "dictGuid": Json::string(id),
        "l3Code": Json::string(l3_code),
      }),
    )
  } else {
    raise reject(404, "unsupported CBS command")
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
        cbs_command_envelope(
          json_field(existing, "result").unwrap_or(result_data),
          existing,
          true,
        ),
      )
    }
    None => ()
  }
  let current = cbs_latest_projection(aggregate_type, aggregate_id)
  if command_type == "dict_add" && current is Some(_) {
    raise reject(409, "CBS dictionary row already exists")
  }
  let current_payload = match current {
    Some((value, _)) => value
    None => Json::null()
  }
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "cbs:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "version_clone" ||
    command_type == "dict_add" {
    let fields = cbs_copy_fields(request)
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("created_at", Json::string(event_id))
    fields.set("created_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "version_freeze" {
    let fields = cbs_copy_fields(current_payload)
    fields.set("frozen_at", Json::string(event_id))
    fields.set("frozen_by", Json::string(actor_id))
    fields.set("is_active", Json::boolean(false))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    Json::object(fields)
  } else {
    let fields = cbs_copy_fields(current_payload)
    fields.set("is_active", Json::boolean(true))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  }
  let command_result = Json::object({
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "projGuid": Json::string(proj_guid),
    "planVersion": Json::string(
      if aggregate_type == "cbs_plan_version" {
        aggregate_id
      } else {
        plan_version
      },
    ),
    "dictGuid": json_field(result_data, "dictGuid").unwrap_or(Json::null()),
    "l3Code": json_field(result_data, "l3Code").unwrap_or(Json::null()),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "actor_id": Json::string(actor_id),
    "authorizing": Json::boolean(false),
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("cbs"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result_data,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("cbs." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(revision.to_double()),
    "cbs_effect": Json::boolean(true),
    "budget_consumption": Json::boolean(false),
  })
  let mut extra_projection_sql = ""
  if command_type == "version_activate" {
    let local_versions = cbs_projection_payloads("cbs_plan_version")
    for other in local_versions {
      let other_id = report_text(other, "plan_version", "")
      if report_text(other, "proj_guid", "") == proj_guid &&
        other_id != aggregate_id &&
        json_bool(other, "is_active", false) {
        let other_revision = match
          cbs_latest_projection("cbs_plan_version", other_id) {
          Some((_, value)) => value + 1
          None => 1
        }
        let fields = cbs_copy_fields(other)
        fields.set("is_active", Json::boolean(false))
        fields.set("source_kind", Json::string("command"))
        fields.set(
          "event_id",
          Json::string(event_id + ":deactivate:" + other_id),
        )
        extra_projection_sql = extra_projection_sql +
          " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_plan_version'," +
          @postgres.sql_literal(other_id) +
          "," +
          other_revision.to_string() +
          "," +
          @postgres.sql_literal(Json::object(fields).stringify()) +
          "::jsonb," +
          @postgres.sql_literal(event_id + ":deactivate:" + other_id) +
          ") ON CONFLICT DO NOTHING;"
      }
    }
  }
  if command_type == "version_clone" {
    let base = cbs_body_text(body, "basePlanVersion", "base_plan_version")
    let source_items = cbs_dict_payloads(proj_guid, base)
    let mut ordinal = 0
    for source in source_items {
      ordinal = ordinal + 1
      let dict_id = aggregate_id + "-dict-" + ordinal.to_string()
      let fields = cbs_copy_fields(source)
      fields.set("dict_guid", Json::string(dict_id))
      fields.set("proj_guid", Json::string(proj_guid))
      fields.set("plan_version", Json::string(aggregate_id))
      fields.set("src", Json::string("cloned"))
      fields.set("source_kind", Json::string("command"))
      fields.set(
        "event_id",
        Json::string(event_id + ":dict:" + ordinal.to_string()),
      )
      extra_projection_sql = extra_projection_sql +
        " INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('cbs_subject_dict'," +
        @postgres.sql_literal(dict_id) +
        ",1," +
        @postgres.sql_literal(Json::object(fields).stringify()) +
        "::jsonb," +
        @postgres.sql_literal(event_id + ":dict:" + ordinal.to_string()) +
        ") ON CONFLICT DO NOTHING;"
    }
  }
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES (" +
    @postgres.sql_literal(aggregate_type) +
    "," +
    @postgres.sql_literal(aggregate_id) +
    "," +
    revision.to_string() +
    "," +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING;" +
    extra_projection_sql +
    " INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "version_clone" || command_type == "dict_add" {
      201
    } else {
      200
    },
    cbs_command_envelope(command_result, command, false),
  )
}
