///|
/// Local investment version/index lifecycle commands.
///
/// Imported investment versions and indices remain read-only. These commands
/// create local command-owned projections for review and planning; they never
/// upload workbooks, call an AI/provider, release cash, post accounting, or
/// apply tax effects.

///|
async fn investment_projection_payloads(
  aggregate_type : String,
) -> Array[Json] raise CompanyServiceError {
  if aggregate_type != "investment_version" &&
    aggregate_type != "investment_index" {
    raise fail("unsupported investment projection type")
  }
  let output = run_sql(
    "SELECT encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 1000",
  )
  let result : Array[Json] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let payload = @json.parse(decode_hex(line)) catch {
        _ => raise fail("invalid investment projection JSON")
      }
      match payload {
        Object(_) => result.push(payload)
        _ => raise fail("investment projection payload is not an object")
      }
    }
  }
  result
}

///|
async fn investment_latest_projection(
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
    _ => raise fail("invalid investment projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn investment_command_envelope(
  data : Json,
  coverage : Map[String, Int],
  command_count : Int,
) -> Json {
  let missing : Array[Json] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(Json::string(table))
    }
  }
  missing.sort_by(fn(left, right) {
    left.stringify().compare(right.stringify())
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(missing),
    "command_projection": Json::boolean(true),
    "command_projection_count": Json::number(command_count.to_double()),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn investment_body_text(
  body : Json,
  primary : String,
  alternate : String,
) -> String {
  let value = json_text(body, primary, "").trim().to_owned()
  if value.is_empty() {
    json_text(body, alternate, "").trim().to_owned()
  } else {
    value
  }
}

///|
fn investment_dimension_valid(value : String) -> Bool {
  ["key_point", "tax", "financing", "investment", "carry_over"].contains(value)
}

///|
async fn investment_require_user(
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
async fn investment_project_exists(
  project_id : String,
) -> Bool raise CompanyServiceError {
  let rows = raw_source_rows("ep_project", 500)
  rows.any(fn(row) {
    report_text(row.payload, "proj_guid", row.record_id) == project_id &&
    json_field(row.payload, "deleted_at") is None
  })
}

///|
async fn investment_imported_version(
  version_id : String,
) -> Json? raise CompanyServiceError {
  let rows = raw_source_rows("tzsy_version", 1000)
  for row in rows {
    if report_text(row.payload, "version_guid", row.record_id) == version_id &&
      json_field(row.payload, "deleted_at") is None {
      return Some(row.payload)
    }
  }
  None
}

///|
async fn investment_imported_index(
  index_id : String,
) -> Json? raise CompanyServiceError {
  let rows = raw_source_rows("tzsy_plan_index", 2000)
  for row in rows {
    if report_text(row.payload, "index_guid", row.record_id) == index_id &&
      json_field(row.payload, "deleted_at") is None {
      return Some(row.payload)
    }
  }
  None
}

///|
async fn investment_version_payload(
  version_id : String,
) -> Json? raise CompanyServiceError {
  match investment_latest_projection("investment_version", version_id) {
    Some((payload, _)) if json_text(payload, "state", "active") != "deleted" =>
      Some(payload)
    _ => investment_imported_version(version_id)
  }
}

///|
async fn investment_current_version_payload(
  project_id : String,
) -> Json? raise CompanyServiceError {
  let imported = raw_source_rows("tzsy_version", 1000)
  let mut selected : Json? = None
  for row in imported {
    if report_text(row.payload, "proj_guid", row.record_id) == project_id &&
      json_bool(row.payload, "is_current", false) &&
      json_field(row.payload, "deleted_at") is None {
      selected = Some(row.payload)
    }
  }
  let local_versions = investment_projection_payloads("investment_version")
  for payload in local_versions {
    if report_text(payload, "proj_guid", "") == project_id &&
      json_bool(payload, "is_current", false) &&
      json_text(payload, "state", "active") != "deleted" {
      selected = Some(payload)
    }
  }
  selected
}

///|
async fn investment_index_payloads(
  version_id : String,
) -> Array[Json] raise CompanyServiceError {
  let result : Array[Json] = []
  for row in raw_source_rows("tzsy_plan_index", 2000) {
    if report_text(row.payload, "version_guid", "") == version_id &&
      json_field(row.payload, "deleted_at") is None {
      result.push(row.payload)
    }
  }
  for payload in investment_projection_payloads("investment_index") {
    if report_text(payload, "version_guid", "") == version_id &&
      json_text(payload, "state", "active") != "deleted" {
      result.push(payload)
    }
  }
  result
}

///|
async fn investment_max_version_no(
  project_id : String,
) -> Int raise CompanyServiceError {
  let mut maximum = 0
  for row in raw_source_rows("tzsy_version", 1000) {
    if report_text(row.payload, "proj_guid", "") == project_id {
      maximum = maximum.max(report_amount(row.payload, "version_no").to_int())
    }
  }
  for payload in investment_projection_payloads("investment_version") {
    if report_text(payload, "proj_guid", "") == project_id &&
      json_text(payload, "state", "active") != "deleted" {
      maximum = maximum.max(json_int(payload, "version_no", 0))
    }
  }
  maximum
}

///|
fn investment_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?, String?)? {
  let project_prefix = "/api/company/investment/projects/"
  if path.has_prefix(project_prefix) {
    let rest = path[project_prefix.length():].to_owned().split("/").to_array()
    if request_method is @http.Post &&
      rest.length() == 2 &&
      rest[1] == "versions" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("version_create", Some(rest[0].to_owned()), None))
    }
    if rest.length() == 4 &&
      rest[1] == "versions" &&
      rest[3] == "activate" &&
      valid_identifier(rest[0].to_owned()) &&
      valid_identifier(rest[2].to_owned()) {
      if request_method is @http.Post {
        return Some(
          (
            "version_activate",
            Some(rest[0].to_owned()),
            Some(rest[2].to_owned()),
          ),
        )
      }
    }
    if rest.length() == 3 &&
      rest[1] == "versions" &&
      valid_identifier(rest[0].to_owned()) &&
      valid_identifier(rest[2].to_owned()) {
      if request_method is @http.Delete {
        return Some(
          ("version_delete", Some(rest[0].to_owned()), Some(rest[2].to_owned())),
        )
      }
    }
  }
  let versions_prefix = "/api/company/investment/versions/"
  if request_method is @http.Post &&
    path.has_prefix(versions_prefix) &&
    path.has_suffix("/indices") {
    let version_id = path[versions_prefix.length():path.length() -
    "/indices".length()].to_owned()
    if valid_identifier(version_id) {
      return Some(("index_create", None, Some(version_id)))
    }
  }
  let indices_prefix = "/api/company/investment/indices/"
  if path.has_prefix(indices_prefix) {
    let index_id = path[indices_prefix.length():].to_owned()
    if valid_identifier(index_id) {
      if request_method is @http.Put {
        return Some(("index_update", None, Some(index_id)))
      }
      if request_method is @http.Delete {
        return Some(("index_delete", None, Some(index_id)))
      }
    }
  }
  None
}

///|
fn investment_copy_fields(payload : Json) -> Map[String, Json] {
  let result : Map[String, Json] = {}
  match payload {
    Object(values) => values.each((key, value) => result.set(key, value))
    _ => ()
  }
  result
}

///|
async fn investment_command(
  command_type : String,
  project_id : String?,
  target_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if ![
      "version_create", "version_activate", "version_delete", "index_create", "index_update",
      "index_delete",
    ].contains(command_type) {
    raise reject(404, "unsupported investment command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user_id = investment_require_user(actor_id)
  let (aggregate_type, aggregate_id, request, project_guid) = if command_type ==
    "version_create" {
    let project = match project_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "project id is required")
    }
    if !investment_project_exists(project) {
      raise reject(404, "project not found")
    }
    let version_name = investment_body_text(body, "versionName", "version_name")
    if version_name.is_empty() {
      raise reject(400, "versionName is required")
    }
    let version_id = investment_body_text(body, "versionGuid", "version_guid")
    let id = if version_id.is_empty() {
      "investment-version-" + idempotency_key
    } else {
      version_id
    }
    if !valid_identifier(id) {
      raise reject(422, "versionGuid contains unsupported characters")
    }
    let activate = json_bool(body, "activate", false)
    let copy_from = investment_body_text(body, "copyFrom", "copy_from")
    if !copy_from.is_empty() {
      if investment_version_payload(copy_from) is None {
        raise reject(404, "copyFrom version not found")
      }
      raise reject(422, "copyFrom version cloning remains gated")
    }
    (
      "investment_version",
      id,
      Json::object({
        "command_type": Json::string(command_type),
        "proj_guid": Json::string(project),
        "version_guid": Json::string(id),
        "version_name": Json::string(version_name),
        "remark": Json::string(investment_body_text(body, "remark", "")),
        "copy_from": Json::string(copy_from),
        "activate": Json::boolean(activate),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      project,
    )
  } else if command_type == "version_activate" ||
    command_type == "version_delete" {
    let project = match project_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "project id is required")
    }
    let version = match target_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "version id is required")
    }
    let payload = match
      investment_latest_projection("investment_version", version) {
      Some((value, _)) => value
      None => {
        if investment_imported_version(version) is Some(_) {
          raise reject(409, "imported investment versions are read-only")
        }
        raise reject(404, "investment version not found")
      }
    }
    if report_text(payload, "proj_guid", "") != project {
      raise reject(409, "investment version does not belong to project")
    }
    if json_text(payload, "state", "active") == "deleted" {
      raise reject(409, "investment version is already deleted")
    }
    if command_type == "version_delete" &&
      json_bool(payload, "is_current", false) {
      raise reject(400, "current investment version cannot be deleted")
    }
    (
      "investment_version",
      version,
      Json::object({
        "command_type": Json::string(command_type),
        "proj_guid": Json::string(project),
        "version_guid": Json::string(version),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      project,
    )
  } else if command_type == "index_create" {
    let version = match target_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "version id is required")
    }
    let version_payload = match investment_version_payload(version) {
      Some(value) => value
      None => raise reject(404, "investment version not found")
    }
    let dimension = investment_body_text(body, "dimension", "")
    let full_code = investment_body_text(body, "fullCode", "full_code")
    let index_name = investment_body_text(body, "indexName", "index_name")
    if !investment_dimension_valid(dimension) {
      raise reject(422, "dimension is invalid")
    }
    if full_code.is_empty() || index_name.is_empty() {
      raise reject(400, "fullCode and indexName are required")
    }
    let requested = investment_body_text(body, "indexGuid", "index_guid")
    let id = if requested.is_empty() {
      "investment-index-" + idempotency_key
    } else {
      requested
    }
    if !valid_identifier(id) {
      raise reject(422, "indexGuid contains unsupported characters")
    }
    let existing = investment_index_payloads(version)
    if existing.any(fn(value) {
        report_text(value, "full_code", "") == full_code &&
        report_text(value, "index_guid", "") != id
      }) {
      raise reject(409, "fullCode already exists in this version")
    }
    (
      "investment_index",
      id,
      Json::object({
        "command_type": Json::string(command_type),
        "index_guid": Json::string(id),
        "version_guid": Json::string(version),
        "proj_guid": json_field(version_payload, "proj_guid").unwrap_or(
          Json::string(""),
        ),
        "dimension": Json::string(dimension),
        "full_code": Json::string(full_code),
        "index_name": Json::string(index_name),
        "parent_code": Json::string(
          investment_body_text(body, "parentCode", "parent_code"),
        ),
        "unit": Json::string(investment_body_text(body, "unit", "")),
        "index_value": json_field(body, "indexValue").unwrap_or(
          json_field(body, "index_value").unwrap_or(Json::null()),
        ),
        "remark": json_field(body, "remark").unwrap_or(Json::null()),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      report_text(version_payload, "proj_guid", ""),
    )
  } else {
    let index = match target_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "index id is required")
    }
    let current = match
      investment_latest_projection("investment_index", index) {
      Some((value, _)) => value
      None => {
        if investment_imported_index(index) is Some(_) {
          raise reject(409, "imported investment indices are read-only")
        }
        raise reject(404, "investment index not found")
      }
    }
    if json_text(current, "state", "active") == "deleted" {
      raise reject(409, "investment index is already deleted")
    }
    let changes : Map[String, Json] = {}
    if command_type == "index_update" {
      match json_field(body, "indexValue") {
        Some(value) => changes.set("index_value", value)
        None =>
          match json_field(body, "index_value") {
            Some(value) => changes.set("index_value", value)
            None => ()
          }
      }
      if json_field(body, "remark") is Some(value) {
        changes.set("remark", value)
      }
      if changes.is_empty() {
        raise reject(422, "index update requires indexValue or remark")
      }
    }
    (
      "investment_index",
      index,
      Json::object({
        "command_type": Json::string(command_type),
        "index_guid": Json::string(index),
        "version_guid": json_field(current, "version_guid").unwrap_or(
          Json::string(""),
        ),
        "proj_guid": json_field(current, "proj_guid").unwrap_or(
          Json::string(""),
        ),
        "changes": Json::object(changes),
        "actor_id": Json::string(actor_id),
        "actor_user_id": Json::string(actor_user_id),
      }),
      report_text(current, "proj_guid", ""),
    )
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
        Json::object({
          "command": existing,
          "investment": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = investment_latest_projection(aggregate_type, aggregate_id)
  if command_type == "version_create" &&
    (current is Some(_) || investment_imported_version(aggregate_id) is Some(_)) {
    raise reject(409, "investment version already exists")
  }
  if command_type == "index_create" &&
    (current is Some(_) || investment_imported_index(aggregate_id) is Some(_)) {
    raise reject(409, "investment index already exists")
  }
  let current_payload = match current {
    Some((payload, _)) => payload
    None => Json::null()
  }
  let current_revision = match current {
    Some((_, revision)) => revision
    None => 0
  }
  let next_revision = if command_type == "version_create" ||
    command_type == "index_create" {
    1
  } else {
    current_revision + 1
  }
  let event_id = "investment:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "version_create" {
    let fields = investment_copy_fields(request)
    fields.set(
      "version_no",
      Json::number((investment_max_version_no(project_guid) + 1).to_double()),
    )
    let activate = json_bool(request, "activate", false)
    let has_current = investment_current_version_payload(project_guid)
      is Some(_)
    fields.set("is_current", Json::boolean(activate || !has_current))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "index_create" {
    let fields = investment_copy_fields(request)
    fields.set(
      "sort_order",
      Json::number(
        investment_index_payloads(json_text(request, "version_guid", ""))
        .length()
        .to_double() +
        1.0,
      ),
    )
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "version_activate" {
    let fields = investment_copy_fields(current_payload)
    fields.set("is_current", Json::boolean(true))
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else if command_type == "version_delete" || command_type == "index_delete" {
    let fields = investment_copy_fields(current_payload)
    fields.set("state", Json::string("deleted"))
    fields.set("deleted_at", Json::string(event_id))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  } else {
    let fields = investment_copy_fields(current_payload)
    match json_field(request, "changes") {
      Some(Object(changes)) =>
        changes.each((key, value) => fields.set(key, value))
      _ => ()
    }
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    Json::object(fields)
  }
  let result = Json::object({
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "projectGuid": Json::string(project_guid),
    "versionGuid": json_field(next_payload, "version_guid").unwrap_or(
      Json::string(""),
    ),
    "indexGuid": json_field(next_payload, "index_guid").unwrap_or(
      Json::string(""),
    ),
    "state": json_field(next_payload, "state").unwrap_or(Json::string("active")),
    "isCurrent": json_field(next_payload, "is_current").unwrap_or(
      Json::boolean(false),
    ),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "actor_id": Json::string(actor_id),
    "source_kind": Json::string("command"),
    "authorizing": Json::boolean(false),
    "investment_effect": Json::boolean(true),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("investment"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("investment." + command_type),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": json_text(next_payload, "state", "active"),
    "revision": Json::number(next_revision.to_double()),
    "investment_effect": Json::boolean(true),
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
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "version_create" || command_type == "index_create" {
      201
    } else {
      200
    },
    Json::object({
      "command": command_payload,
      "investment": result,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
