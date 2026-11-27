///|
fn charter_require_object(
  value : Json,
  label : String,
) -> Json raise CompanyServiceError {
  match value {
    Object(_) => value
    _ => raise reject(422, label + " must be a JSON object")
  }
}

///|
fn charter_require_string(
  obj : Json,
  field : String,
  label : String,
  max_len : Int32,
  allow_empty : Bool,
) -> String raise CompanyServiceError {
  let raw = match json_field(obj, field) {
    Some(String(value)) => value.trim().to_owned()
    _ => raise reject(422, label + " must be text")
  }
  if (!allow_empty && raw.is_empty()) || raw.length() > max_len {
    let min_len = if allow_empty { "0" } else { "1" }
    raise reject(
      422,
      label +
      " must contain between " +
      min_len +
      " and " +
      max_len.to_string() +
      " characters",
    )
  }
  raw
}

///|
fn charter_optional_string(
  obj : Json,
  field : String,
  label : String,
  max_len : Int32,
  default_value : String,
) -> String raise CompanyServiceError {
  match json_field(obj, field) {
    None | Some(Null) => default_value
    Some(String(value)) => {
      let trimmed = value.trim().to_owned()
      if trimmed.length() > max_len {
        raise reject(
          422,
          label + " must contain at most " + max_len.to_string() + " characters",
        )
      }
      if trimmed.is_empty() {
        default_value
      } else {
        trimmed
      }
    }
    _ => raise reject(422, label + " must be text")
  }
}

///|
fn charter_require_enum(
  obj : Json,
  field : String,
  label : String,
  allowed : Array[String],
  default_value : String?,
) -> String raise CompanyServiceError {
  let value = match json_field(obj, field) {
    None | Some(Null) =>
      match default_value {
        Some(fallback) => return fallback
        None => raise reject(422, label + " is required")
      }
    Some(String(text)) => text.trim().to_owned()
    _ => raise reject(422, label + " must be text")
  }
  if !allowed.contains(value) {
    raise reject(422, label + " must be one of: " + allowed.join(", "))
  }
  value
}

///|
fn charter_require_int(
  obj : Json,
  field : String,
  label : String,
  min_val : Int32?,
  max_val : Int32?,
) -> Int32 raise CompanyServiceError {
  let number = match json_field(obj, field) {
    Some(Number(n, ..)) => n
    _ => raise reject(422, label + " must be an integer")
  }
  let value = number.to_int()
  if value.to_double() != number {
    raise reject(422, label + " must be an integer")
  }
  match min_val {
    Some(lo) if value < lo =>
      raise reject(422, label + " must be at least " + lo.to_string())
    _ => ()
  }
  match max_val {
    Some(hi) if value > hi =>
      raise reject(422, label + " must be at most " + hi.to_string())
    _ => ()
  }
  value
}

///|
fn charter_optional_int(
  obj : Json,
  field : String,
  label : String,
  min_val : Int32?,
) -> Int32? raise CompanyServiceError {
  match json_field(obj, field) {
    None | Some(Null) => None
    Some(Number(n, ..)) => {
      let value = n.to_int()
      if value.to_double() != n {
        raise reject(422, label + " must be an integer")
      }
      match min_val {
        Some(lo) if value < lo =>
          raise reject(422, label + " must be at least " + lo.to_string())
        _ => ()
      }
      Some(value)
    }
    _ => raise reject(422, label + " must be an integer")
  }
}

///|
fn charter_require_id(
  obj : Json,
  field : String,
  label : String,
) -> String raise CompanyServiceError {
  let id = match json_field(obj, field) {
    Some(String(value)) => value.trim().to_owned()
    _ => raise reject(422, label + " must be a valid identifier")
  }
  if !valid_identifier(id) {
    raise reject(422, label + " must be a valid non-empty identifier")
  }
  id
}

///|
fn charter_optional_string_array(
  obj : Json,
  field : String,
  label : String,
  max_items : Int32,
  max_item_len : Int32,
) -> Array[Json] raise CompanyServiceError {
  let items = match json_field(obj, field) {
    None | Some(Null) => return []
    Some(Array(values)) => values
    _ => raise reject(422, label + " must be an array")
  }
  if items.length() > max_items {
    raise reject(
      422,
      label + " must contain at most " + max_items.to_string() + " items",
    )
  }
  let normalized : Array[Json] = []
  for item in items {
    match item {
      String(raw) => {
        let trimmed = raw.trim().to_owned()
        if trimmed.is_empty() || trimmed.length() > max_item_len {
          raise reject(
            422,
            label +
            " entries must contain between 1 and " +
            max_item_len.to_string() +
            " characters",
          )
        }
        normalized.push(Json::string(trimmed))
      }
      _ => raise reject(422, label + " entries must be text")
    }
  }
  normalized
}

///|
fn charter_validate_mission(body : Json) -> Json raise CompanyServiceError {
  let mission = match json_field(body, "mission") {
    Some(value) => charter_require_object(value, "mission")
    None => raise reject(422, "mission is required")
  }
  let title = charter_require_string(
    mission, "title", "mission.title", 256, false,
  )
  let north_star = charter_optional_string(
    mission, "north_star", "mission.north_star", 2000, "",
  )
  let active_stage_id = charter_optional_string(
    mission, "active_stage_id", "mission.active_stage_id", 128, "",
  )
  let focus_ratio = charter_optional_string(
    mission, "focus_ratio", "mission.focus_ratio", 64, "80/20",
  )
  Json::object({
    "title": Json::string(title),
    "north_star": Json::string(north_star),
    "active_stage_id": Json::string(active_stage_id),
    "focus_ratio": Json::string(focus_ratio),
  })
}

///|
fn charter_validate_stages(
  body : Json,
) -> Array[Json] raise CompanyServiceError {
  let items = match json_field(body, "stages") {
    None | Some(Null) => return []
    Some(Array(values)) => values
    _ => raise reject(422, "stages must be an array")
  }
  if items.length() > 24 {
    raise reject(422, "stages must contain at most 24 items")
  }
  let seen : Map[String, Bool] = Map([])
  let normalized : Array[Json] = []
  for item in items {
    let stage = charter_require_object(item, "stages[]")
    let id = charter_require_id(stage, "id", "stages[].id")
    if seen.get(id) is Some(true) {
      raise reject(422, "duplicate stage id: " + id)
    }
    seen.set(id, true)
    let order = charter_require_int(
      stage,
      "order",
      "stages[].order",
      None,
      None,
    )
    let title = charter_require_string(
      stage, "title", "stages[].title", 256, false,
    )
    let status = charter_require_enum(
      stage,
      "status",
      "stages[].status",
      ["achieved", "active", "upcoming"],
      None,
    )
    let weight_pct = charter_require_int(
      stage,
      "weight_pct",
      "stages[].weight_pct",
      Some(0),
      Some(100),
    )
    let outcome = charter_optional_string(
      stage, "outcome", "stages[].outcome", 1000, "",
    )
    let milestone_task_id = charter_optional_string(
      stage, "milestone_task_id", "stages[].milestone_task_id", 128, "",
    )
    normalized.push(
      Json::object({
        "id": Json::string(id),
        "order": Json::number(order.to_double()),
        "title": Json::string(title),
        "status": Json::string(status),
        "weight_pct": Json::number(weight_pct.to_double()),
        "outcome": Json::string(outcome),
        "milestone_task_id": Json::string(milestone_task_id),
      }),
    )
  }
  normalized
}

///|
fn charter_validate_roles(body : Json) -> Array[Json] raise CompanyServiceError {
  let items = match json_field(body, "roles") {
    None | Some(Null) => return []
    Some(Array(values)) => values
    _ => raise reject(422, "roles must be an array")
  }
  if items.length() > 32 {
    raise reject(422, "roles must contain at most 32 items")
  }
  let seen : Map[String, Bool] = Map([])
  let normalized : Array[Json] = []
  for item in items {
    let role = charter_require_object(item, "roles[]")
    let id = charter_require_id(role, "id", "roles[].id")
    if seen.get(id) is Some(true) {
      raise reject(422, "duplicate role id: " + id)
    }
    seen.set(id, true)
    let name = charter_require_string(role, "name", "roles[].name", 128, false)
    let tier = charter_require_int(
      role,
      "tier",
      "roles[].tier",
      Some(0),
      Some(2),
    )
    let kind = charter_require_enum(
      role,
      "kind",
      "roles[].kind",
      ["human", "agent"],
      None,
    )
    let reports_to = charter_optional_string(
      role, "reports_to", "roles[].reports_to", 128, "",
    )
    let mission = charter_optional_string(
      role, "mission", "roles[].mission", 1000, "",
    )
    let powers = charter_optional_string_array(
      role, "powers", "roles[].powers", 24, 512,
    )
    let limits = charter_optional_string_array(
      role, "limits", "roles[].limits", 24, 512,
    )
    let skill_ref = charter_optional_string(
      role, "skill_ref", "roles[].skill_ref", 256, "",
    )
    let model = charter_optional_string(role, "model", "roles[].model", 128, "")
    let version = charter_optional_string(
      role, "version", "roles[].version", 64, "v1",
    )
    let status = charter_require_enum(
      role,
      "status",
      "roles[].status",
      ["active", "evolving", "paused"],
      Some("active"),
    )
    normalized.push(
      Json::object({
        "id": Json::string(id),
        "name": Json::string(name),
        "tier": Json::number(tier.to_double()),
        "kind": Json::string(kind),
        "reports_to": Json::string(reports_to),
        "mission": Json::string(mission),
        "powers": Json::array(powers),
        "limits": Json::array(limits),
        "skill_ref": Json::string(skill_ref),
        "model": Json::string(model),
        "version": Json::string(version),
        "status": Json::string(status),
      }),
    )
  }
  normalized
}

///|
fn charter_validate_resources(
  body : Json,
) -> Array[Json] raise CompanyServiceError {
  let items = match json_field(body, "resources") {
    None | Some(Null) => return []
    Some(Array(values)) => values
    _ => raise reject(422, "resources must be an array")
  }
  if items.length() > 64 {
    raise reject(422, "resources must contain at most 64 items")
  }
  let seen : Map[String, Bool] = Map([])
  let normalized : Array[Json] = []
  for item in items {
    let resource = charter_require_object(item, "resources[]")
    let id = charter_require_id(resource, "id", "resources[].id")
    if seen.get(id) is Some(true) {
      raise reject(422, "duplicate resource id: " + id)
    }
    seen.set(id, true)
    let name = charter_require_string(
      resource, "name", "resources[].name", 256, false,
    )
    let kind = charter_require_enum(
      resource,
      "kind",
      "resources[].kind",
      ["moonbook", "corpus", "tool", "runtime"],
      None,
    )
    let uri = charter_optional_string(
      resource, "uri", "resources[].uri", 512, "",
    )
    let desk_url = charter_optional_string(
      resource, "desk_url", "resources[].desk_url", 512, "",
    )
    let access = charter_require_enum(
      resource,
      "access",
      "resources[].access",
      ["read_only", "read_write", "execute"],
      Some("read_only"),
    )
    let owner_role = charter_optional_string(
      resource, "owner_role", "resources[].owner_role", 128, "",
    )
    let notes = charter_optional_string(
      resource, "notes", "resources[].notes", 1000, "",
    )
    normalized.push(
      Json::object({
        "id": Json::string(id),
        "name": Json::string(name),
        "kind": Json::string(kind),
        "uri": Json::string(uri),
        "desk_url": Json::string(desk_url),
        "access": Json::string(access),
        "owner_role": Json::string(owner_role),
        "notes": Json::string(notes),
      }),
    )
  }
  normalized
}

///|
fn charter_validate_evolution_log(
  body : Json,
) -> Array[Json] raise CompanyServiceError {
  let items = match json_field(body, "evolution_log") {
    None | Some(Null) => return []
    Some(Array(values)) => values
    _ => raise reject(422, "evolution_log must be an array")
  }
  if items.length() > 100 {
    raise reject(422, "evolution_log must contain at most 100 items")
  }
  let normalized : Array[Json] = []
  for item in items {
    let entry = charter_require_object(item, "evolution_log[]")
    let id = charter_require_id(entry, "id", "evolution_log[].id")
    let date = charter_optional_string(
      entry, "date", "evolution_log[].date", 32, "",
    )
    let target = charter_require_enum(
      entry,
      "target",
      "evolution_log[].target",
      ["company", "agent"],
      None,
    )
    let target_id = charter_optional_string(
      entry, "target_id", "evolution_log[].target_id", 128, "",
    )
    let change = charter_require_string(
      entry, "change", "evolution_log[].change", 1000, false,
    )
    let evidence = charter_optional_string(
      entry, "evidence", "evolution_log[].evidence", 1000, "",
    )
    normalized.push(
      Json::object({
        "id": Json::string(id),
        "date": Json::string(date),
        "target": Json::string(target),
        "target_id": Json::string(target_id),
        "change": Json::string(change),
        "evidence": Json::string(evidence),
      }),
    )
  }
  normalized
}

///|
/// Persisted Company Operating Charter request validator and normalizer.
/// Produces canonical JSON used for both storage and idempotency comparison.
fn company_charter_upsert_request(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(actor_id) {
    raise reject(422, "invalid actor identity")
  }
  company_command_validate_ids("company_charter:upsert:", idempotency_key)
  let root = charter_require_object(body, "charter body")
  let mission = charter_validate_mission(root)
  let stages = charter_validate_stages(root)
  let roles = charter_validate_roles(root)
  let resources = charter_validate_resources(root)
  let evolution_log = charter_validate_evolution_log(root)
  let critical_task_ids = charter_optional_string_array(
    root, "critical_task_ids", "critical_task_ids", 64, 128,
  )
  let expected_revision = charter_optional_int(
    root,
    "expected_revision",
    "expected_revision",
    Some(0),
  )
  Json::object({
    "command_type": Json::string("upsert_company_charter"),
    "actor_id": Json::string(actor_id),
    "mission": mission,
    "stages": Json::array(stages),
    "roles": Json::array(roles),
    "resources": Json::array(resources),
    "evolution_log": Json::array(evolution_log),
    "critical_task_ids": Json::array(critical_task_ids),
    "expected_revision": match expected_revision {
      Some(rev) => Json::number(rev.to_double())
      None => Json::null()
    },
  })
}

///|
fn company_charter_read_sql() -> String {
  "SELECT encode(convert_to((payload || jsonb_build_object('revision', revision))::text, 'UTF8'), 'hex') " +
  "FROM company_aggregate_projection " +
  "WHERE aggregate_type = 'company_charter' AND aggregate_id = 'current' " +
  "ORDER BY company_aggregate_projection.revision DESC LIMIT 1"
}

///|
fn company_charter_response(charter : Json?) -> Json {
  Json::object({
    "success": true,
    "code": 0,
    "charter": charter.unwrap_or(Json::null()),
    "persisted": Json::boolean(charter is Some(_)),
    "authorizing": false,
  })
}

///|
async fn company_charter_read_response() -> Json raise CompanyServiceError {
  let output = run_sql(company_charter_read_sql()).trim().to_owned()
  let charter = if output.is_empty() {
    None
  } else {
    Some(
      @json.parse(decode_hex(output)) catch {
        _ => raise fail("invalid company charter projection")
      },
    )
  }
  company_charter_response(charter)
}

///|
fn company_charter_upsert_sql(request : Json, key : String) -> String {
  let event_id = "company_charter:upsert:" + key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + key
  let audit_source = "moonproj:audit:" + event_id
  let body = "DECLARE canonical jsonb; current_revision integer; next_revision integer; expected_rev integer; charter jsonb; receipt jsonb; response jsonb; request jsonb := " +
    @postgres.sql_literal(request.stringify()) +
    "::jsonb; BEGIN " +
    "SELECT payload INTO canonical FROM company_record WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; " +
    "SELECT company_aggregate_projection.revision INTO current_revision FROM company_aggregate_projection " +
    "WHERE aggregate_type = 'company_charter' AND aggregate_id = 'current' " +
    "ORDER BY company_aggregate_projection.revision DESC LIMIT 1; " +
    "expected_rev := CASE WHEN jsonb_typeof(request->'expected_revision') = 'number' THEN (request->>'expected_revision')::integer ELSE NULL END; " +
    "IF canonical IS NOT NULL THEN IF canonical->'request' IS DISTINCT FROM request THEN " +
    "response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'Idempotency-Key was already used for another request')); ELSE " +
    "response := jsonb_build_object('status', 200, 'body', jsonb_build_object('success', true, 'code', 0, 'charter', canonical->'result', 'command', canonical, 'idempotent_replay', true, 'persisted', true, 'authorizing', false)); END IF; " +
    "ELSIF expected_rev IS NOT NULL AND coalesce(current_revision, 0) <> expected_rev THEN " +
    "response := jsonb_build_object('status', 409, 'body', jsonb_build_object('error', 'company charter revision conflict; reload and retry', 'expected_revision', expected_rev, 'current_revision', coalesce(current_revision, 0), 'canonical_reference', '/api/company/charter', 'persisted', current_revision IS NOT NULL)); " +
    "ELSE next_revision := coalesce(current_revision, 0) + 1; " +
    "charter := jsonb_build_object('schema', 'moonproj.company-charter.v1', 'charter_id', 'current', 'mission', request->'mission', 'stages', request->'stages', 'roles', request->'roles', 'resources', request->'resources', 'evolution_log', request->'evolution_log', 'critical_task_ids', request->'critical_task_ids', 'source_kind', 'command', 'updated_by', request->>'actor_id', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'revision', next_revision); " +
    "receipt := jsonb_build_object('kind', 'company_command', 'command_family', 'company_charter', 'command_type', 'upsert', 'idempotency_key', " +
    @postgres.sql_literal(key) +
    ", 'aggregate_type', 'company_charter', 'aggregate_id', 'current', 'actor_id', request->>'actor_id', 'request', request, 'result', charter); " +
    "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('company_charter', 'current', next_revision, charter, " +
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
    ", 'action', 'company_charter.upsert', 'aggregate_type', 'company_charter', 'aggregate_id', 'current', 'actor_id', request->>'actor_id', 'event_id', " +
    @postgres.sql_literal(event_id) +
    ", 'revision', next_revision), " +
    @postgres.sql_literal(audit_source) +
    "); " +
    "response := jsonb_build_object('status', CASE WHEN next_revision = 1 THEN 201 ELSE 200 END, 'body', jsonb_build_object('success', true, 'code', 0, 'charter', charter, 'command', receipt, 'idempotent_replay', false, 'persisted', true, 'authorizing', false)); END IF; " +
    "INSERT INTO moonproj_command_response VALUES(response); END;"
  company_command_transaction_sql(body)
}

///|
async fn company_charter_upsert_command(
  body : Json,
  actor_id : String,
  key : String,
) -> (Int32, Json) raise CompanyServiceError {
  let request = company_charter_upsert_request(body, actor_id, key)
  let response = try {
    let output = run_sql(company_charter_upsert_sql(request, key))
    company_command_parse_response(output)
  } catch {
    _ => {
      // A transport failure after commit is indeterminate until the canonical
      // receipt is read. Never invent success or retry with a new identity.
      let persisted = existing_company_command(key) catch { _ => None }
      let canonical = company_command_recovery_receipt(persisted, request)
      let fields = match
        company_charter_response(json_field(canonical, "result")) {
        Object(fields) => fields
        _ => Map([])
      }
      fields.set("command", canonical)
      fields.set("idempotent_replay", true)
      return (200, Json::object(fields))
    }
  }
  response
}
