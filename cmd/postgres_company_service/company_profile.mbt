///|
/// Workspace identity only. This never asserts legal registration, capital,
/// tax status, cash, readiness, ERP membership, or execution authority.
fn company_profile_create_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(actor_id) {
    raise reject(422, "invalid actor identity")
  }
  company_command_validate_ids("company_profile:create:", idempotency_key)
  let name = match json_field(body, "companyName") {
    Some(String(value)) => value.trim().to_owned()
    _ => raise reject(422, "companyName must be text")
  }
  if name.is_empty() || name.length() > 256 {
    raise reject(422, "companyName must contain between 1 and 256 characters")
  }
  let existing = match json_field(body, "existingBuGuid") {
    None | Some(Null) => ""
    Some(String(value)) => {
      let id = value.trim().to_owned()
      if !valid_identifier(id) {
        raise reject(
          422, "existingBuGuid must identify a selected business unit",
        )
      }
      id
    }
    _ => raise reject(422, "existingBuGuid must be text")
  }
  let unit_id = if existing.is_empty() {
    "ORG-" + idempotency_key
  } else {
    existing
  }
  if !valid_identifier(unit_id) {
    raise reject(422, "generated business unit identity is too long")
  }
  Json::object({
    "command_type": "create_company_profile",
    "company_name": Json::string(name),
    "existing_bu_guid": Json::string(existing),
    "bu_guid": Json::string(unit_id),
    "actor_id": Json::string(actor_id),
  })
}

///|
fn company_command_validate_ids(
  prefix : String,
  key : String,
) -> Unit raise CompanyServiceError {
  for
    value in [
      key,
      prefix + key,
      prefix + key + ":audit",
      "moonproj:command:" + key,
      "moonproj:audit:" + prefix + key,
    ] {
    if !valid_identifier(value) {
      raise reject(
        422, "Idempotency-Key or generated command identity exceeds 128 characters or contains unsupported characters",
      )
    }
  }
}

///|
/// A single database call holds the established table locks until the response
/// has been selected. The temporary response is connection-local and dropped
/// at commit; all durable state uses the existing schema V4 tables.
fn company_command_transaction_sql(body : String) -> String {
  "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; " +
  "LOCK TABLE company_record IN SHARE ROW EXCLUSIVE MODE; " +
  "CREATE TEMP TABLE moonproj_command_response(response jsonb NOT NULL) ON COMMIT DROP; DO " +
  @postgres.sql_literal(body) +
  "; SELECT 'MOONPROJ_COMMAND_RESPONSE:' || encode(convert_to(response::text, 'UTF8'), 'hex') AS command_response FROM moonproj_command_response; COMMIT;"
}

///|
fn company_command_parse_response(
  output : String,
) -> (Int, Json) raise CompanyServiceError {
  let marker = "MOONPROJ_COMMAND_RESPONSE:"
  let frames : Array[String] = []
  for line in output.split("\n") {
    let value = line.trim().to_owned()
    if value.is_empty() {
      continue
    }
    if value.has_prefix(marker) {
      frames.push(value[marker.length():].to_owned())
    } else if !["BEGIN", "LOCK TABLE", "CREATE TABLE", "DO", "COMMIT"].contains(
        value,
      ) {
      raise company_command_uncertain_response()
    }
  }
  if frames.length() != 1 {
    raise company_command_uncertain_response()
  }
  let value = @json.parse(decode_hex(frames[0])) catch {
    _ => raise company_command_uncertain_response()
  }
  let body = json_field(value, "body").unwrap_or(Json::null())
  let status = json_int(value, "status", 0)
  if status < 200 || status > 599 || !(body is Object(_)) {
    raise company_command_uncertain_response()
  }
  (status, body)
}

///|
/// Output decoding can fail after commit. Treat it as uncertain transport and
/// recover the canonical receipt, never as a definitive rejected user request.
fn company_command_uncertain_response() -> CompanyServiceError {
  CompanyServiceError::Database(
    @postgres.PostgresError::Failed("company command response is uncertain"),
  )
}

///|
fn company_command_recovery_receipt(
  persisted : Json?,
  request : Json,
) -> Json raise CompanyServiceError {
  match persisted {
    Some(receipt) => plan_task_applied_command(Some(receipt), request)
    None => raise company_command_uncertain_response()
  }
}

///|
fn business_unit_candidates_sql(unit_id : String?) -> String {
  let raw_filter = match unit_id {
    Some(id) =>
      " AND " +
      plan_task_json_text_sql("bu_guid", "record_id") +
      " = " +
      @postgres.sql_literal(id)
    None => ""
  }
  let exact = match unit_id {
    Some(id) => " AND aggregate_id = " + @postgres.sql_literal(id)
    None => ""
  }
  "SELECT record_id, source_id, payload || jsonb_build_object('__unit_source_kind', 'imported') AS payload FROM company_record " +
  "WHERE record_type = 'legacy/raw/mu_business_unit'" +
  raw_filter +
  " UNION ALL SELECT aggregate_id AS record_id, source_event_id AS source_id, payload || jsonb_build_object('__unit_source_kind', 'command', '__unit_aggregate_id', aggregate_id, '__revision', revision) AS payload " +
  "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, source_event_id, payload, revision FROM company_aggregate_projection " +
  "WHERE aggregate_type = 'organization_unit'" +
  exact +
  " ORDER BY aggregate_id, revision DESC) latest " +
  "WHERE payload->>'source_kind' = 'command'"
}

///|
fn business_unit_active_sql() -> String {
  "coalesce(payload->>'state', '') <> 'deleted' AND coalesce(payload->>'deleted_at', '') = '' AND coalesce(payload->>'deletedAt', '') = '' AND (payload->>'__unit_source_kind' <> 'command' OR " +
  plan_task_json_text_sql("bu_guid", "record_id") +
  " = payload->>'__unit_aggregate_id')"
}

///|
fn business_unit_rows_sql(unit_id : String?) -> String {
  "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (" +
  business_unit_candidates_sql(unit_id) +
  ") units WHERE " +
  business_unit_active_sql() +
  " ORDER BY record_id"
}

///|
/// Keep competing tombstones visible until tree ambiguity has been diagnosed.
fn business_unit_tree_sql() -> String {
  "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), encode(convert_to(source_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (" +
  business_unit_candidates_sql(None) +
  ") units ORDER BY record_id"
}

///|
async fn business_unit_rows(
  unit_id : String?,
) -> Array[SourceRow] raise CompanyServiceError {
  product_work_source_rows(business_unit_rows_sql(unit_id))
}

///|
fn company_profile_read_sql() -> String {
  "SELECT encode(convert_to((payload || jsonb_build_object('revision', revision))::text, 'UTF8'), 'hex') " +
  "FROM company_aggregate_projection WHERE aggregate_type = 'company_profile' AND aggregate_id = 'current' ORDER BY revision DESC LIMIT 1"
}

///|
fn company_profile_response(profile : Json?) -> Json {
  Json::object({
    "success": true,
    "code": 0,
    "profile": profile.unwrap_or(Json::null()),
    "persisted": Json::boolean(profile is Some(_)),
    "authorizing": false,
  })
}

///|
async fn company_profile_read_response() -> Json raise CompanyServiceError {
  let output = run_sql(company_profile_read_sql()).trim().to_owned()
  let profile = if output.is_empty() {
    None
  } else {
    Some(
      @json.parse(decode_hex(output)) catch {
        _ => raise fail("invalid company profile projection")
      },
    )
  }
  company_profile_response(profile)
}

///|
fn company_profile_create_sql(request : Json, key : String) -> String {
  let event_id = "company_profile:create:" + key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + key
  let unit_id = json_text(request, "bu_guid", "")
  let name = json_text(request, "company_name", "")
  let existing = json_text(request, "existing_bu_guid", "")
  let native_unit : Json = {
    "bu_guid": Json::string(unit_id),
    "bu_name": Json::string(name),
    "parent_guid": "",
    "level": 1,
    "state": "active",
    "source_kind": "command",
  }
  let unit_query = "SELECT count(*) INTO unit_count FROM (" +
    business_unit_candidates_sql(Some(unit_id)) +
    ") units; " +
    "SELECT payload INTO selected_unit FROM (" +
    business_unit_candidates_sql(Some(unit_id)) +
    ") units WHERE " +
    business_unit_active_sql() +
    " LIMIT 1; "
  let body = "DECLARE canonical jsonb; saved_profile jsonb; selected_unit jsonb; unit_count integer; profile jsonb; receipt jsonb; response jsonb; request jsonb := " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb; BEGIN " +
    "SELECT payload INTO canonical FROM company_record WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; " +
    "SELECT payload || jsonb_build_object('revision', revision) INTO saved_profile FROM company_aggregate_projection WHERE aggregate_type = 'company_profile' AND aggregate_id = 'current' ORDER BY revision DESC LIMIT 1; " +
    unit_query +
    "IF canonical IS NOT NULL THEN IF canonical->'request' IS DISTINCT FROM request THEN " +
    "response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'Idempotency-Key was already used for another request')); ELSE " +
    "response := jsonb_build_object('status', 200, 'body', jsonb_build_object('success', true, 'code', 0, 'profile', canonical->'result', 'command', canonical, 'idempotent_replay', true, 'persisted', true, 'authorizing', false)); END IF; " +
    "ELSIF saved_profile IS NOT NULL THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'company profile already exists', 'profile', saved_profile, 'canonical_reference', '/api/company/profile', 'persisted', true)); " +
    (if existing.is_empty() {
      "ELSIF unit_count <> 0 OR EXISTS (SELECT 1 FROM company_aggregate_projection WHERE aggregate_type = 'organization_unit' AND aggregate_id = " +
      @postgres.sql_literal(unit_id) +
      ") THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'business unit identity already exists')); "
    } else {
      "ELSIF unit_count <> 1 OR selected_unit IS NULL THEN response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'selected business unit is missing, deleted, or ambiguous')); "
    }) +
    "ELSE " +
    (if existing.is_empty() {
      "selected_unit := " +
      @postgres.sql_literal(native_unit.stringify()) +
      "::jsonb; " +
      "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('organization_unit', " +
      @postgres.sql_literal(unit_id) +
      ", 1, selected_unit, " +
      @postgres.sql_literal(event_id) +
      "); "
    } else {
      ""
    }) +
    "profile := jsonb_build_object('company_id', 'current', 'company_name', request->>'company_name', 'bu_guid', request->>'bu_guid', 'bu_name', coalesce(selected_unit->>'bu_name', ''), 'unit_source_kind', " +
    (if existing.is_empty() {
      "'command'"
    } else {
      "selected_unit->>'__unit_source_kind'"
    }) +
    ", 'source_kind', 'command', 'revision', 1); " +
    "receipt := jsonb_build_object('kind', 'company_command', 'command_family', 'company_profile', 'command_type', 'create', 'idempotency_key', " +
    @postgres.sql_literal(key) +
    ", 'aggregate_type', 'company_profile', 'aggregate_id', 'current', 'actor_id', request->>'actor_id', 'request', request, 'result', profile); " +
    "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('company_profile', 'current', 1, profile, " +
    @postgres.sql_literal(event_id) +
    "); " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, receipt, " +
    @postgres.sql_literal(command_source) +
    "); " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, jsonb_build_object('audit_id', " +
    @postgres.sql_literal(audit_id) +
    ", 'action', 'company_profile.create', 'aggregate_type', 'company_profile', 'aggregate_id', 'current', 'actor_id', request->>'actor_id', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'bu_guid', request->>'bu_guid', 'created_unit', " +
    (if existing.is_empty() { "true" } else { "false" }) +
    "), " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    "); " +
    "response := jsonb_build_object('status', 201, 'body', jsonb_build_object('success', true, 'code', 0, 'profile', profile, 'command', receipt, 'idempotent_replay', false, 'persisted', true, 'authorizing', false)); END IF; " +
    "INSERT INTO moonproj_command_response VALUES(response); END;"
  company_command_transaction_sql(body)
}

///|
async fn company_profile_create_command(
  body : Json,
  actor_id : String,
  key : String,
) -> (Int, Json) raise CompanyServiceError {
  let request = company_profile_create_request(body, actor_id, key)
  let response = try {
    let output = run_sql(company_profile_create_sql(request, key))
    company_command_parse_response(output)
  } catch {
    _ => {
      // A transport failure after commit is indeterminate until the canonical
      // receipt is read. Never invent success or retry with a new identity.
      let persisted = existing_company_command(key) catch { _ => None }
      let canonical = company_command_recovery_receipt(persisted, request)
      let fields = match
        company_profile_response(json_field(canonical, "result")) {
        Object(fields) => fields
        _ => Map::new()
      }
      fields.set("command", canonical)
      fields.set("idempotent_replay", true)
      return (200, Json::object(fields))
    }
  }
  response
}
