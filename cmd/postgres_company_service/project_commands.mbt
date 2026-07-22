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
    "FROM company_aggregate_projection WHERE aggregate_type = 'project' " +
    "AND payload->>'source_kind' = 'command' AND aggregate_id = " +
    @postgres.sql_literal(project_id) +
    " ORDER BY revision DESC LIMIT 1",
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
    " WHERE coalesce(payload->>'state', '') <> 'deleted'"
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
    "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, " +
    "source_event_id, revision FROM company_aggregate_projection WHERE " +
    "aggregate_type = 'project' AND payload->>'source_kind' = 'command' " +
    "ORDER BY aggregate_id, revision DESC) latest" +
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
  let row = match latest_project_command_payload(project_id) {
    Some((payload, _)) => project_source_row_from_payload(project_id, payload)
    None => project_source_row_from_payload(project_id, project)
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
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
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
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored_request = json_field(existing, "request").unwrap_or(
        Json::null(),
      )
      if !json_equal(stored_request, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        project_source_alias_result(
          Json::object({
            "command": existing,
            "project": json_field(existing, "result").unwrap_or(Json::null()),
            "idempotent_replay": Json::boolean(true),
          }),
        ),
      )
    }
    None => ()
  }
  let id = json_text(request, "project_id", "")
  let current = latest_project_command_payload(id)
  if command_type == "create" {
    if current is Some(_) {
      raise reject(409, "project already exists")
    }
    for row in raw_source_rows("ep_project", 500) {
      if json_text(row.payload, "proj_guid", row.record_id) == id {
        raise reject(409, "project already exists")
      }
    }
  } else {
    match current {
      Some((payload, _)) if json_text(payload, "state", "active") == "deleted" =>
        raise reject(409, "project is deleted")
      Some(_) => ()
      None => {
        let imported = raw_source_rows("ep_project", 500).any(fn(row) {
          json_text(row.payload, "proj_guid", row.record_id) == id
        })
        if imported {
          raise reject(
            409, "imported project is read-only; use a distinct local identity",
          )
        } else {
          raise reject(404, "project not found")
        }
      }
    }
  }
  let (current_payload, current_revision) = match current {
    Some(value) => value
    None => (Json::object({}), 0)
  }
  let next_revision = current_revision + 1
  let next_payload = if command_type == "create" {
    let fields = project_copy_fields(request)
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string("project:create:" + idempotency_key))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else {
    match current_payload {
      Object(fields) => {
        if command_type == "update" {
          match json_field(request, "changes") {
            Some(Object(changes)) =>
              for key, value in changes {
                fields.set(key, value)
              }
            _ => ()
          }
        }
        fields.set(
          "state",
          Json::string(
            if command_type == "delete" {
              "deleted"
            } else {
              "active"
            },
          ),
        )
        fields.set("source_kind", Json::string("command"))
        fields.set(
          "event_id",
          Json::string("project:" + command_type + ":" + idempotency_key),
        )
        fields.set("updated_by", Json::string(actor_id))
        Json::object(fields)
      }
      _ => raise fail("invalid project command projection")
    }
  }
  let event_id = "project:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + idempotency_key
  let state = if command_type == "delete" { "deleted" } else { "active" }
  let result = Json::object({
    "project_id": Json::string(id),
    "project_code": Json::string(json_text(next_payload, "proj_code", id)),
    "state": Json::string(state),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "source_kind": Json::string("command"),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("project"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("project"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("project." + command_type),
    "aggregate_type": Json::string("project"),
    "aggregate_id": Json::string(id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(state),
    "revision": Json::number(next_revision.to_double()),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; " +
    "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('project', " +
    @postgres.sql_literal(id) +
    ", " +
    next_revision.to_string() +
    ", " +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    "); " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    "); " +
    "UPDATE company_record SET payload = payload || jsonb_build_object('result', " +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb) WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; COMMIT;"
  let _ = run_sql(sql)
  let response = Json::object({
    "command": command_payload,
    "project": result,
    "idempotent_replay": Json::boolean(false),
  })
  (200, project_source_alias_result(response))
}
