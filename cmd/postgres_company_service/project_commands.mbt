///|
/// Individual MDM project source aliases.  These commands own a separate
/// PostgreSQL projection and never mutate imported ERP project rows.

///|
fn project_source_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  let prefix = "/api/company/source/mdm/projects/"
  if request_method is @http.Post && path == "/api/company/source/mdm/projects" {
    return Some(("create", None))
  }
  if path.has_prefix(prefix) {
    let project_id = path[prefix.length():].to_owned()
    if valid_identifier(project_id) {
      if request_method is @http.Put {
        return Some(("update", Some(project_id)))
      }
      if request_method is @http.Delete {
        return Some(("delete", Some(project_id)))
      }
    }
  }
  None
}

///|
async fn latest_project_command_payload(
  project_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') " +
    "FROM (SELECT revision, payload FROM company_aggregate_projection WHERE aggregate_type = 'project' " +
    "AND aggregate_id = " +
    @postgres.sql_literal(project_id) +
    " ORDER BY revision DESC LIMIT 1) latest WHERE payload->>'source_kind' = 'command'",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid project command projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn project_command_projection_rows(
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
  let deleted_clause = if include_deleted {
    ""
  } else {
    " AND coalesce(payload->>'state', '') <> 'deleted'"
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
    "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, " +
    "source_event_id, revision FROM company_aggregate_projection WHERE " +
    "aggregate_type = 'project' " +
    "ORDER BY aggregate_id, revision DESC) latest WHERE payload->>'source_kind' = 'command'" +
    deleted_clause +
    " ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 4)
    let payload = @json.parse(decode_hex(row[1])) catch {
      _ => raise fail("invalid project command projection JSON")
    }
    match payload {
      Object(values) => {
        values.set(
          "__revision",
          Json::number(parse_decimal(row[3]).to_double()),
        )
        result.push({
          record_id: decode_hex(row[0]),
          source_id: decode_hex(row[2]),
          payload: Json::object(values),
        })
      }
      _ => raise fail("project command projection payload is not an object")
    }
  }
  result
}

///|
fn project_source_value(body : Json, camel : String, snake : String) -> String {
  json_text(body, camel, json_text(body, snake, "")).trim().to_owned()
}

///|
fn project_json_text(value : Json) -> String {
  match value {
    String(text) => text
    Number(number, ..) => number.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn project_copy_fields(payload : Json) -> Map[String, Json] {
  let result : Map[String, Json] = {}
  match payload {
    Object(values) => values.each((key, value) => result.set(key, value))
    _ => ()
  }
  result
}

///|
fn project_required_value(
  body : Json,
  camel : String,
  snake : String,
) -> String raise CompanyServiceError {
  let value = project_source_value(body, camel, snake)
  if value.is_empty() {
    raise reject(422, camel + " is required")
  }
  value
}

///|
fn project_source_create_request(
  body : Json,
  idempotency_key : String,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let project_id = project_source_value(body, "projGuid", "proj_guid")
  let project_guid = if project_id.is_empty() {
    "PRJ-SRC-" + idempotency_key
  } else {
    project_id
  }
  if !valid_identifier(project_guid) {
    raise reject(422, "projGuid contains unsupported characters")
  }
  let project_code = project_required_value(body, "projCode", "proj_code")
  let project_name = project_required_value(body, "projName", "proj_name")
  if project_code.length() > 128 || project_name.length() > 256 {
    raise reject(
      422, "projCode must fit 128 characters and projName must fit 256 characters",
    )
  }
  let bu_guid = project_required_value(body, "buGuid", "bu_guid")
  if !valid_identifier(bu_guid) {
    raise reject(422, "buGuid contains unsupported characters")
  }
  let project_short_name = project_source_value(
    body, "projShortName", "proj_short_name",
  )
  let short_name = if project_short_name.is_empty() {
    project_name
  } else {
    project_short_name
  }
  let level_code = project_source_value(body, "levelCode", "level_code")
  let begin_date = project_source_value(body, "beginDate", "begin_date")
  let end_date = project_source_value(body, "endDate", "end_date")
  let project_status = project_source_value(body, "projStatus", "proj_status")
  let status = if project_status.is_empty() {
    "initiation"
  } else {
    project_status
  }
  Json::object({
    "command_type": Json::string("create"),
    "project_id": Json::string(project_guid),
    "proj_guid": Json::string(project_guid),
    "proj_code": Json::string(project_code),
    "proj_name": Json::string(project_name),
    "proj_short_name": Json::string(short_name),
    "bu_guid": Json::string(bu_guid),
    "bu_name": Json::string(
      if project_source_value(body, "buName", "bu_name").is_empty() {
        bu_guid
      } else {
        project_source_value(body, "buName", "bu_name")
      },
    ),
    "level": Json::number(1),
    "level_code": Json::string(
      if level_code.is_empty() {
        "001"
      } else {
        level_code
      },
    ),
    "if_end": Json::boolean(true),
    "begin_date": Json::string(begin_date),
    "end_date": Json::string(end_date),
    "proj_status": Json::string(status),
    "created_at": Json::string(""),
    "actor_id": Json::string(actor_id),
    "source_alias": Json::boolean(true),
  })
}

///|
fn project_source_update_request(
  project_id : String,
  body : Json,
  actor_id : String,
) -> Json raise CompanyServiceError {
  let changes : Map[String, Json] = {}
  let mappings : Map[String, String] = {
    "projName": "proj_name",
    "projShortName": "proj_short_name",
    "buGuid": "bu_guid",
    "beginDate": "begin_date",
    "projStatus": "proj_status",
  }
  for camel, snake in mappings {
    match json_field(body, camel) {
      Some(value) => {
        let text = project_json_text(value).trim().to_owned()
        if text.is_empty() && snake == "proj_name" {
          raise reject(422, "projName is required")
        }
        if snake == "bu_guid" && !valid_identifier(text) {
          raise reject(422, "buGuid contains unsupported characters")
        }
        changes.set(snake, Json::string(text))
      }
      None =>
        match json_field(body, snake) {
          Some(value) => {
            let text = project_json_text(value).trim().to_owned()
            if text.is_empty() && snake == "proj_name" {
              raise reject(422, "projName is required")
            }
            if snake == "bu_guid" && !valid_identifier(text) {
              raise reject(422, "buGuid contains unsupported characters")
            }
            changes.set(snake, Json::string(text))
          }
          None => ()
        }
    }
  }
  if changes.is_empty() {
    raise reject(422, "project update requires a mutable field")
  }
  Json::object({
    "command_type": Json::string("update"),
    "project_id": Json::string(project_id),
    "actor_id": Json::string(actor_id),
    "changes": Json::object(changes),
  })
}

///|
fn project_source_delete_request(
  project_id : String,
  body : Json,
  actor_id : String,
) -> Json {
  let reason = json_text(body, "reason", "").trim().to_owned()
  Json::object({
    "command_type": Json::string("delete"),
    "project_id": Json::string(project_id),
    "actor_id": Json::string(actor_id),
    "reason": Json::string(reason),
  })
}

///|
fn project_source_row_from_payload(project_id : String, payload : Json) -> Json {
  Json::object({
    "projGuid": Json::string(project_id),
    "projCode": Json::string(json_text(payload, "proj_code", project_id)),
    "projName": Json::string(json_text(payload, "proj_name", project_id)),
    "projShortName": Json::string(json_text(payload, "proj_short_name", "")),
    "buGuid": Json::string(json_text(payload, "bu_guid", "")),
    "buName": Json::string(
      json_text(payload, "bu_name", json_text(payload, "bu_guid", "")),
    ),
    "level": Json::number(json_int(payload, "level", 0).to_double()),
    "levelCode": Json::string(json_text(payload, "level_code", "")),
    "ifEnd": Json::boolean(json_bool(payload, "if_end", false)),
    "bgnSaleDate": Json::string(json_text(payload, "bgn_sale_date", "")),
    "endSaleDate": Json::string(json_text(payload, "end_sale_date", "")),
    "beginDate": Json::string(json_text(payload, "begin_date", "")),
    "endDate": Json::string(json_text(payload, "end_date", "")),
    "projStatus": Json::string(json_text(payload, "proj_status", "")),
    "createdAt": Json::string(json_text(payload, "created_at", "")),
    "sourceKind": Json::string("command"),
    "sourceId": Json::string("moonproj:command:project:" + project_id),
  })
}

///|
async fn project_source_alias_result(
  result : Json,
) -> Json raise CompanyServiceError {
  let project = json_field(result, "project").unwrap_or(Json::null())
  let project_id = json_text(project, "project_id", "")
  let snapshot = json_field(result, "project_snapshot").unwrap_or(Json::null())
  let row = if snapshot is Object(_) {
    project_source_row_from_payload(project_id, snapshot)
  } else {
    match latest_project_command_payload(project_id) {
      Some((payload, _)) => project_source_row_from_payload(project_id, payload)
      None => project_source_row_from_payload(project_id, project)
    }
  }
  let command = json_field(result, "command").unwrap_or(Json::null())
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "projGuid": Json::string(project_id),
      "projCode": Json::string(json_text(row, "projCode", project_id)),
    }),
    "project": row,
    "command": command,
    "idempotent_replay": Json::boolean(
      json_bool(result, "idempotent_replay", false),
    ),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn project_source_command(
  command_type : String,
  project_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  company_command_validate_ids("project:" + command_type + ":", idempotency_key)
  let request = if command_type == "create" {
    project_source_create_request(body, idempotency_key, actor_id)
  } else {
    let id = match project_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "project_id is required")
    }
    if command_type == "update" {
      project_source_update_request(id, body, actor_id)
    } else if command_type == "delete" {
      project_source_delete_request(id, body, actor_id)
    } else {
      raise reject(404, "unsupported project command")
    }
  }
  let (status, response) = try {
    let output = run_sql(
      project_source_atomic_sql(command_type, request, idempotency_key),
    )
    company_command_parse_response(output)
  } catch {
    _ => {
      let persisted = existing_company_command(idempotency_key) catch {
        _ => None
      }
      let canonical = company_command_recovery_receipt(persisted, request)
      return (
        200,
        project_source_alias_result(
          Json::object({
            "command": canonical,
            "project": json_field(canonical, "result").unwrap_or(Json::null()),
            "project_snapshot": json_field(canonical, "project_snapshot").unwrap_or(
              Json::null(),
            ),
            "idempotent_replay": true,
          }),
        ),
      )
    }
  }
  if status != 200 {
    return (status, response)
  }
  (200, project_source_alias_result(response))
}

///|
/// Recheck the canonical receipt, every authoritative identity, and the current
/// revision inside one transaction. A waiting identical create observes the
/// first receipt and cannot attempt a second aggregate/audit insert.
fn project_source_atomic_sql(
  command_type : String,
  request : Json,
  key : String,
) -> String {
  let id = json_text(request, "project_id", "")
  let event_id = "project:" + command_type + ":" + key
  let audit_id = event_id + ":audit"
  let source = "moonproj:command:" + key
  let create_mode = command_type == "create"
  let changes = json_field(request, "changes").unwrap_or(Json::null())
  let unit_id = if create_mode {
    json_text(request, "bu_guid", "")
  } else {
    json_text(changes, "bu_guid", "")
  }
  let check_unit = create_mode || !unit_id.is_empty()
  let next_state = if command_type == "delete" { "deleted" } else { "active" }
  let body = "DECLARE canonical jsonb; current_payload jsonb; current_revision integer; identity_count integer; " +
    "unit_count integer; selected_unit jsonb; next_payload jsonb; result jsonb; receipt jsonb; response jsonb; request jsonb := " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb; BEGIN " +
    "SELECT payload INTO canonical FROM company_record WHERE source_id = " +
    @postgres.sql_literal(source) +
    "; " +
    "SELECT payload, revision INTO current_payload, current_revision FROM company_aggregate_projection WHERE aggregate_type = 'project' AND aggregate_id = " +
    @postgres.sql_literal(id) +
    " ORDER BY revision DESC LIMIT 1; " +
    "SELECT count(*) INTO identity_count FROM (" +
    project_identity_sql(id, true) +
    ") identities; " +
    (if check_unit {
      "SELECT count(*) INTO unit_count FROM (" +
      business_unit_candidates_sql(Some(unit_id)) +
      ") units; " +
      "SELECT payload INTO selected_unit FROM (" +
      business_unit_candidates_sql(Some(unit_id)) +
      ") units WHERE " +
      business_unit_active_sql() +
      " LIMIT 1; "
    } else {
      ""
    }) +
    "IF canonical IS NOT NULL THEN IF canonical->'request' IS DISTINCT FROM request THEN " +
    "response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'Idempotency-Key was already used for another request')); " +
    "ELSE response := jsonb_build_object('status', 200, 'body', jsonb_build_object('command', canonical, 'project', canonical->'result', 'project_snapshot', canonical->'project_snapshot', 'idempotent_replay', true)); END IF; " +
    (if create_mode {
      "ELSIF identity_count <> 0 OR current_payload IS NOT NULL THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'project identity already exists')); "
    } else {
      "ELSIF identity_count > 1 THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'project identity is ambiguous across authoritative sources')); " +
      "ELSIF current_payload IS NULL OR current_payload->>'source_kind' IS DISTINCT FROM 'command' THEN " +
      "response := jsonb_build_object('status', CASE WHEN identity_count > 0 THEN 409 ELSE 404 END, 'body', jsonb_build_object('error', CASE WHEN identity_count > 0 THEN 'imported project is read-only; use a distinct local identity' ELSE 'project not found' END)); " +
      "ELSIF current_payload->>'state' = 'deleted' THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'project is deleted')); "
    }) +
    (if check_unit {
      "ELSIF unit_count <> 1 OR selected_unit IS NULL THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'business unit is missing, deleted, or ambiguous')); "
    } else {
      ""
    }) +
    "ELSE current_revision := coalesce(current_revision, 0) + 1; " +
    (if create_mode {
      "next_payload := request; "
    } else {
      "next_payload := current_payload || coalesce(request->'changes', '{}'::jsonb); "
    }) +
    "next_payload := next_payload || jsonb_build_object('state', " +
    @postgres.sql_literal(next_state) +
    ", 'source_kind', 'command', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'updated_by', request->>'actor_id'); " +
    (if check_unit {
      "next_payload := next_payload || jsonb_build_object('bu_name', coalesce(selected_unit->>'bu_name', '')); "
    } else {
      ""
    }) +
    "result := jsonb_build_object('project_id', request->>'project_id', 'project_code', next_payload->>'proj_code', 'state', " +
    @postgres.sql_literal(next_state) +
    ", 'revision', current_revision, 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'audit_id', " +
    @postgres.sql_literal(audit_id) +
    ", 'actor_id', request->>'actor_id', 'source_kind', 'command', 'cash_effect', false, 'accounting_effect', false, 'tax_effect', false); " +
    "receipt := jsonb_build_object('kind', 'company_command', 'command_family', 'project', 'command_type', " +
    @postgres.sql_literal(command_type) +
    ", 'idempotency_key', " +
    @postgres.sql_literal(key) +
    ", 'aggregate_type', 'project', 'aggregate_id', request->>'project_id', 'actor_id', request->>'actor_id', 'request', request, 'result', result, 'project_snapshot', next_payload); " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, receipt, " +
    @postgres.sql_literal(source) +
    "); " +
    "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('project', " +
    @postgres.sql_literal(id) +
    ", current_revision, next_payload, " +
    @postgres.sql_literal(event_id) +
    "); " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, result || jsonb_build_object('action', " +
    @postgres.sql_literal("project." + command_type) +
    ", 'aggregate_type', 'project', 'aggregate_id', request->>'project_id'), " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    "); " +
    "response := jsonb_build_object('status', 200, 'body', jsonb_build_object('command', receipt, 'project', result, 'project_snapshot', next_payload, 'idempotent_replay', false)); " +
    "END IF; INSERT INTO moonproj_command_response VALUES(response); END;"
  company_command_transaction_sql(body)
}
