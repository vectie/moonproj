///|
/// Project and contract batch-import command boundaries.
///
/// Rows are normalized and committed as command-owned immutable projections.
/// Both batches use one idempotent PostgreSQL transaction; financial posting,
/// provider execution, and tax effects remain outside this import boundary.

///|
fn import_project_text(body : Json, camel : String, snake : String) -> String {
  json_text(body, camel, json_text(body, snake, "")).trim().to_owned()
}

///|
async fn import_project_batch_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let profile = match auth_current_user(actor_id) {
    Some(value) => value
    None => raise reject(403, "user not found or disabled")
  }
  if !json_bool(
      json_field(profile, "data").unwrap_or(Json::null()),
      "enabled",
      false,
    ) {
    raise reject(403, "user not found or disabled")
  }
  let rows = match json_field(body, "rows") {
    Some(Array(values)) => values
    _ => raise reject(400, "rows must be a non-empty array")
  }
  if rows.is_empty() || rows.length() > 500 {
    raise reject(400, "rows must contain between 1 and 500 items")
  }
  let dry_run = json_bool(body, "dryRun", json_bool(body, "dry_run", false))
  let request = Json::object({
    "command_type": Json::string("project_batch_import"),
    "actor_id": Json::string(actor_id),
    "dry_run": Json::boolean(dry_run),
    "rows": Json::array(rows),
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
          "command": existing,
          "data": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let units = raw_source_rows("mu_business_unit", 500)
  let imported = raw_source_rows("ep_project", 500)
  let normalized : Array[Json] = []
  let result_rows : Array[Json] = []
  for index in 0..<rows.length() {
    let row = rows[index]
    let code = import_project_text(row, "projCode", "proj_code")
    let name = import_project_text(row, "projName", "proj_name")
    let bu_code = import_project_text(row, "buCode", "bu_code")
    if code.is_empty() || name.is_empty() || bu_code.is_empty() {
      raise reject(400, "projCode/projName/buCode are required")
    }
    if !valid_identifier(code) || !valid_identifier(bu_code) {
      raise reject(422, "projCode and buCode contain unsupported characters")
    }
    let mut bu_guid = ""
    for unit in units {
      if json_text(unit.payload, "bu_code", unit.record_id) == bu_code {
        bu_guid = json_text(unit.payload, "bu_guid", unit.record_id)
      }
    }
    if bu_guid.is_empty() {
      raise reject(404, "business unit not found: " + bu_code)
    }
    if imported.any(fn(existing) {
        json_text(existing.payload, "proj_code", existing.record_id) == code
      }) ||
      normalized.any(fn(existing) {
        json_text(existing, "proj_code", "") == code
      }) {
      raise reject(409, "projCode already exists: " + code)
    }
    let requested_guid = import_project_text(row, "projGuid", "proj_guid")
    let project_guid = if requested_guid.is_empty() {
      "project-import-" + idempotency_key + "-" + (index + 1).to_string()
    } else {
      requested_guid
    }
    if !valid_identifier(project_guid) {
      raise reject(422, "projGuid contains unsupported characters")
    }
    let payload = Json::object({
      "proj_guid": Json::string(project_guid),
      "proj_code": Json::string(code),
      "proj_name": Json::string(name),
      "proj_short_name": Json::string(
        if import_project_text(row, "projShortName", "proj_short_name").is_empty() {
          name
        } else {
          import_project_text(row, "projShortName", "proj_short_name")
        },
      ),
      "bu_guid": Json::string(bu_guid),
      "level": Json::number(1),
      "level_code": Json::string("001"),
      "if_end": Json::boolean(true),
      "begin_date": Json::string(
        import_project_text(row, "beginDate", "begin_date"),
      ),
      "end_date": Json::string(import_project_text(row, "endDate", "end_date")),
      "proj_status": Json::string(
        if import_project_text(row, "projStatus", "proj_status").is_empty() {
          "initiation"
        } else {
          import_project_text(row, "projStatus", "proj_status")
        },
      ),
      "source_kind": Json::string("command"),
      "state": Json::string("active"),
      "actor_id": Json::string(actor_id),
      "import_batch": Json::string(idempotency_key),
      "import_row": Json::number((index + 1).to_double()),
    })
    normalized.push(payload)
    result_rows.push(
      Json::object({
        "row": Json::number((index + 1).to_double()),
        "projGuid": Json::string(project_guid),
        "projCode": Json::string(code),
        "projName": Json::string(name),
        "buGuid": Json::string(bu_guid),
      }),
    )
  }
  let mode = if dry_run { "dryRun" } else { "commit" }
  let batch_event = "project-import:" + idempotency_key
  let audit_id = batch_event + ":audit"
  let result = Json::object({
    "mode": Json::string(mode),
    "ok": Json::array(result_rows),
    "failed": Json::array([]),
    "rowsAccepted": Json::number(result_rows.length().to_double()),
    "persisted": Json::boolean(!dry_run),
    "sourceKind": Json::string("command"),
    "authorizing": Json::boolean(false),
  })
  if dry_run {
    return (
      200,
      Json::object({
        "success": Json::boolean(true),
        "code": Json::number(0),
        "data": result,
        "source_kind": Json::string("import_batch_command_candidate"),
        "dry_run": Json::boolean(true),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
      }),
    )
  }
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("import"),
    "command_type": Json::string("project_batch_import"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("project_import"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("import.project_batch"),
    "aggregate_type": Json::string("project_import"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(batch_event),
    "rows": Json::number(result_rows.length().to_double()),
  })
  let mut sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(batch_event) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING;"
  for index in 0..<normalized.length() {
    let project_guid = json_text(normalized[index], "proj_guid", "")
    let event_id = batch_event + ":" + (index + 1).to_string()
    sql = sql +
      " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('project_import', " +
      @postgres.sql_literal(project_guid) +
      ", 1, " +
      @postgres.sql_literal(normalized[index].stringify()) +
      "::jsonb, " +
      @postgres.sql_literal(event_id) +
      ") ON CONFLICT DO NOTHING;"
  }
  sql = sql +
    " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + batch_event) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("import_batch_command_candidate"),
    }),
  )
}

///|
fn import_project_for_contract(
  projects : Array[SourceRow],
  project_code : String,
  project_id : String,
) -> (String, String) raise CompanyServiceError {
  if !project_id.is_empty() {
    if !valid_identifier(project_id) {
      raise reject(422, "projGuid contains unsupported characters")
    }
    for project in projects {
      let known_id = json_text(project.payload, "proj_guid", project.record_id)
      if known_id == project_id {
        return (project_id, json_text(project.payload, "proj_name", project_id))
      }
    }
    raise reject(404, "project not found: " + project_id)
  }
  if project_code.is_empty() || !valid_identifier(project_code) {
    raise reject(422, "projCode or projGuid is required")
  }
  for project in projects {
    if json_text(project.payload, "proj_code", "") == project_code {
      return (
        json_text(project.payload, "proj_guid", project.record_id),
        json_text(project.payload, "proj_name", project_code),
      )
    }
  }
  raise reject(404, "project not found: " + project_code)
}

///|
fn import_unit_for_contract(
  units : Array[SourceRow],
  unit_id : String,
  unit_code : String,
) -> (String, String) raise CompanyServiceError {
  if !unit_id.is_empty() && !valid_identifier(unit_id) {
    raise reject(422, "buGuid contains unsupported characters")
  }
  if !unit_code.is_empty() && !valid_identifier(unit_code) {
    raise reject(422, "buCode contains unsupported characters")
  }
  for unit in units {
    let known_id = json_text(unit.payload, "bu_guid", unit.record_id)
    let known_code = json_text(unit.payload, "bu_code", "")
    if (!unit_id.is_empty() && known_id == unit_id) ||
      (!unit_code.is_empty() && known_code == unit_code) {
      return (
        known_id,
        json_text(
          unit.payload,
          "bu_name",
          if known_code.is_empty() {
            known_id
          } else {
            known_code
          },
        ),
      )
    }
  }
  let missing_ref = if !unit_id.is_empty() { unit_id } else { unit_code }
  raise reject(404, "business unit not found: " + missing_ref)
}

///|
async fn import_contract_batch_command(
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let profile = match auth_current_user(actor_id) {
    Some(value) => value
    None => raise reject(403, "user not found or disabled")
  }
  if !json_bool(
      json_field(profile, "data").unwrap_or(Json::null()),
      "enabled",
      false,
    ) {
    raise reject(403, "user not found or disabled")
  }
  let rows = match json_field(body, "rows") {
    Some(Array(values)) => values
    _ => raise reject(400, "rows must be a non-empty array")
  }
  if rows.is_empty() || rows.length() > 500 {
    raise reject(400, "rows must contain between 1 and 500 items")
  }
  let dry_run = json_bool(body, "dryRun", json_bool(body, "dry_run", false))
  let request = Json::object({
    "command_type": Json::string("contract_batch_import"),
    "actor_id": Json::string(actor_id),
    "dry_run": Json::boolean(dry_run),
    "rows": Json::array(rows),
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
          "command": existing,
          "data": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let projects = raw_source_rows("ep_project", 500)
  let command_projects = project_import_projection_rows()
  for project in command_projects {
    projects.push(project)
  }
  let units = raw_source_rows("mu_business_unit", 500)
  let visible_contracts = contract_items(None)
  let normalized : Array[Json] = []
  let result_rows : Array[Json] = []
  for index in 0..<rows.length() {
    let row = rows[index]
    let contract_code = import_project_text(
      row, "contractCode", "contract_code",
    )
    let contract_name = import_project_text(
      row, "contractName", "contract_name",
    )
    if contract_code.is_empty() || contract_name.is_empty() {
      raise reject(422, "contractCode and contractName are required")
    }
    if !valid_identifier(contract_code) {
      raise reject(422, "contractCode contains unsupported characters")
    }
    if visible_contracts.any(fn(existing) {
        json_text(existing, "contract_code", "") == contract_code
      }) ||
      normalized.any(fn(existing) {
        json_text(existing, "contract_code", "") == contract_code
      }) {
      raise reject(409, "contractCode already exists: " + contract_code)
    }
    let project = import_project_for_contract(
      projects,
      import_project_text(row, "projCode", "proj_code"),
      import_project_text(row, "projGuid", "proj_guid"),
    )
    let unit = import_unit_for_contract(
      units,
      import_project_text(row, "buGuid", "bu_guid"),
      import_project_text(row, "buCode", "bu_code"),
    )
    let contract_id = import_project_text(row, "contractGuid", "contract_guid")
    let resolved_id = if contract_id.is_empty() {
      "contract-import-" + idempotency_key + "-" + (index + 1).to_string()
    } else {
      contract_id
    }
    if !valid_identifier(resolved_id) {
      raise reject(422, "contractGuid contains unsupported characters")
    }
    if visible_contracts.any(fn(existing) {
        json_text(existing, "contract_id", "") == resolved_id
      }) ||
      normalized.any(fn(existing) {
        json_text(existing, "contract_id", "") == resolved_id
      }) {
      raise reject(409, "contractGuid already exists: " + resolved_id)
    }
    let amount_minor = if json_field(row, "htAmount") is Some(_) {
      source_decimal_minor(row, "htAmount", 1)
    } else {
      contract_positive_amount(row, "amount_minor")
    }
    let sign_date = import_project_text(row, "signDate", "sign_date")
    if sign_date.is_empty() {
      raise reject(422, "signDate is required")
    }
    let supplier_id = import_project_text(row, "providerGuid", "provider_guid")
    let resolved_supplier = if supplier_id.is_empty() {
      "source-supplier-" + idempotency_key + "-" + (index + 1).to_string()
    } else {
      supplier_id
    }
    if !valid_identifier(resolved_supplier) {
      raise reject(422, "providerGuid contains unsupported characters")
    }
    let supplier_name = import_project_text(
      row, "yfProviderName", "supplier_name",
    )
    let canonical : Map[String, Json] = {}
    canonical.set("contract_id", Json::string(resolved_id))
    canonical.set("contract_code", Json::string(contract_code))
    canonical.set("contract_name", Json::string(contract_name))
    canonical.set("project_id", Json::string(project.0))
    canonical.set(
      "project_name",
      Json::string(
        if import_project_text(row, "projName", "proj_name").is_empty() {
          project.1
        } else {
          import_project_text(row, "projName", "proj_name")
        },
      ),
    )
    canonical.set("supplier_id", Json::string(resolved_supplier))
    canonical.set(
      "supplier_name",
      Json::string(
        if supplier_name.is_empty() {
          resolved_supplier
        } else {
          supplier_name
        },
      ),
    )
    canonical.set("bu_guid", Json::string(unit.0))
    canonical.set("bu_name", Json::string(unit.1))
    canonical.set("sign_date", Json::string(sign_date))
    canonical.set("amount_minor", Json::number(amount_minor.to_double()))
    canonical.set(
      "currency",
      Json::string(
        if json_field(row, "currency") is Some(_) {
          contract_currency(row, "currency")
        } else {
          "CNY"
        },
      ),
    )
    let source_keys = [
      "htTypeCode", "yfCorporation", "htCfState", "jsState", "costCode", "rCode",
      "l3Code",
    ]
    let target_keys = [
      "ht_type_code", "supplier_corporation", "ht_cf_state", "js_state", "cost_code",
      "r_code", "l3_code",
    ]
    for field_index in 0..<source_keys.length() {
      source_contract_optional_text(
        row,
        source_keys[field_index],
        target_keys[field_index],
        canonical,
      )
    }
    let request_row = contract_create_request(Json::object(canonical), actor_id)
    normalized.push(request_row)
    result_rows.push(
      Json::object({
        "row": Json::number((index + 1).to_double()),
        "contractGuid": Json::string(resolved_id),
        "contractCode": Json::string(contract_code),
        "contractName": Json::string(contract_name),
        "projGuid": Json::string(project.0),
        "buGuid": Json::string(unit.0),
        "amountMinor": Json::number(amount_minor.to_double()),
      }),
    )
  }
  let mode = if dry_run { "dryRun" } else { "commit" }
  let batch_event = "contract-import:" + idempotency_key
  let result = Json::object({
    "mode": Json::string(mode),
    "ok": Json::array(result_rows),
    "failed": Json::array([]),
    "rowsAccepted": Json::number(result_rows.length().to_double()),
    "persisted": Json::boolean(!dry_run),
    "sourceKind": Json::string("command"),
    "authorizing": Json::boolean(false),
  })
  if dry_run {
    return (
      200,
      Json::object({
        "success": Json::boolean(true),
        "code": Json::number(0),
        "data": result,
        "source_kind": Json::string("import_batch_command_candidate"),
        "dry_run": Json::boolean(true),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
      }),
    )
  }
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("import"),
    "command_type": Json::string("contract_batch_import"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("contract"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_id = batch_event + ":audit"
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("import.contract_batch"),
    "aggregate_type": Json::string("contract"),
    "aggregate_id": Json::string(idempotency_key),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(batch_event),
    "rows": Json::number(result_rows.length().to_double()),
  })
  let mut sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(batch_event) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING;"
  for index in 0..<normalized.length() {
    let contract = normalized[index]
    let contract_id = json_text(contract, "contract_id", "")
    let event_id = batch_event + ":" + (index + 1).to_string()
    let payload = @postgres.sql_literal(contract.stringify()) +
      "::jsonb || jsonb_build_object('state', 'draft', 'event_id', " +
      @postgres.sql_literal(event_id) +
      ", 'updated_by', " +
      @postgres.sql_literal(actor_id) +
      ", 'source_kind', 'command', 'import_batch', " +
      @postgres.sql_literal(idempotency_key) +
      ")"
    sql = sql +
      " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('contract', " +
      @postgres.sql_literal(contract_id) +
      ", 1, " +
      payload +
      ", " +
      @postgres.sql_literal(event_id) +
      ") ON CONFLICT DO NOTHING;"
  }
  sql = sql +
    " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + batch_event) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": result,
      "command": command_payload,
      "idempotent_replay": Json::boolean(false),
      "source_kind": Json::string("import_batch_command_candidate"),
    }),
  )
}
