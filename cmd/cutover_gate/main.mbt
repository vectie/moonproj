///|
pub(all) suberror CutoverGateError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> CutoverGateError {
  CutoverGateError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise CutoverGateError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise CutoverGateError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON evidence: " + path)
  }
}

///|
fn try_json(path : String) -> Json? {
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let value = @json.parse(content) catch { _ => return None }
  Some(value)
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise CutoverGateError {
  match value {
    Object(fields) => fields
    _ => raise fail("evidence is not an object: " + path)
  }
}

///|
fn required_object(path : String) -> Map[String, Json] raise CutoverGateError {
  object(read_json(path), path)
}

///|
fn get(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn get_obj(value : Json, key : String) -> Map[String, Json] {
  match get(value, key) {
    Object(fields) => fields
    _ => {}
  }
}

///|
fn get_array(value : Json, key : String) -> Array[Json] {
  match get(value, key) {
    Array(values) => values
    _ => []
  }
}

///|
fn get_string(value : Json, key : String) -> String? {
  match get(value, key) {
    String(text) => Some(text)
    _ => None
  }
}

///|
fn get_int(value : Json, key : String, default : Int) -> Int {
  match get(value, key) {
    Number(number, ..) if number == number.trunc() => number.to_int()
    _ => default
  }
}

///|
fn get_bool(value : Json, key : String) -> Bool? {
  match get(value, key) {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn eq_string(value : Json, expected : String) -> Bool {
  value == Json::string(expected)
}

///|
fn eq_int(value : Json, expected : Int) -> Bool {
  match value {
    Number(number, ..) => number == expected.to_double()
    _ => false
  }
}

///|
fn check(name : String, passed : Bool, fields : Map[String, Json]) -> Json {
  fields.set("name", Json::string(name))
  fields.set("passed", Json::boolean(passed))
  Json::object(fields)
}

///|
fn check_file(
  work_dir : String,
  name : String,
) -> (String, Json) raise CutoverGateError {
  let path = work_dir + "/" + name
  let value = read_json(path)
  (path, value)
}

///|
fn path_list(directory : String, suffix : String) -> Array[String] {
  let directory_exists = @fs.is_dir(directory) catch { _ => false }
  if !directory_exists {
    return []
  }
  let names = @fs.read_dir(directory) catch { _ => return [] }
  let paths : Array[String] = []
  for name in names {
    if name.has_suffix(suffix) {
      paths.push(directory + "/" + name)
    }
  }
  paths.sort_by(fn(left, right) { left.lexical_compare(right) })
  paths
}

///|
fn unique_paths(paths : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for path in paths {
    if !result.contains(path) {
      result.push(path)
    }
  }
  result.sort_by(fn(left, right) { left.lexical_compare(right) })
  result
}

///|
fn mapping_check(
  checks : Array[Json],
  work_dir : String,
  file : String,
  name : String,
  wave : String,
  mapped_tables : Int,
) -> Unit {
  let path = work_dir + "/" + file
  match try_json(path) {
    None => ()
    Some(value) => {
      let tables = get_array(value, "tables")
      let table_items_valid = tables.all(fn(item) {
        get_bool(item, "promotion_authorized") == Some(false)
      })
      let passed = eq_string(
          get(value, "format"),
          "moonproj.erp.schema-cohort-mapping-result.v1",
        ) &&
        eq_string(get(value, "wave"), wave) &&
        eq_string(get(value, "state"), "mapped_scope_only") &&
        eq_int(get(value, "mapped_tables"), mapped_tables) &&
        eq_int(get(value, "source_rows_available"), 0) &&
        get_bool(value, "promotion_authorized") == Some(false) &&
        tables.length() == mapped_tables &&
        table_items_valid
      checks.push(
        check(name, passed, {
          "state": get(value, "state"),
          "mapped_tables": get(value, "mapped_tables"),
          "source_rows_available": get(value, "source_rows_available"),
          "promotion_authorized": get(value, "promotion_authorized"),
        }),
      )
    }
  }
}

///|
fn run(
  work_dir : String,
  output : String,
  expected_raw : Int,
  expected_projections : Int,
  expected_links : Int,
  integrity : String,
  schema_version : Int,
  raw_count : Int,
  projection_count : Int,
  link_count : Int,
  receipt_count : Int,
) -> Unit raise CutoverGateError {
  let checks : Array[Json] = []
  let staging = required_object(work_dir + "/raw-staging.ndjson.manifest.json")
  let staging_json = Json::object(staging)
  let mut staged_rows = 0
  for table in get_array(staging_json, "tables") {
    staged_rows += get_int(table, "rows", 0)
  }
  checks.push(
    check(
      "source_staging",
      eq_string(get(staging_json, "format"), "moonproj.erp.raw-staging.v1") &&
      staged_rows > 0,
      {
        "source_sha256": get(staging_json, "source_sha256"),
        "staged_rows": json_int(staged_rows),
      },
    ),
  )

  let schema_gap = required_object(work_dir + "/schema-gap.json")
  let schema_gap_json = Json::object(schema_gap)
  checks.push(
    check(
      "schema_scope",
      eq_string(get(schema_gap_json, "format"), "moonproj.erp.schema-gap.v1") &&
      eq_int(get(schema_gap_json, "schema_tables"), 75) &&
      eq_int(get(schema_gap_json, "present_tables"), 26) &&
      eq_int(get(schema_gap_json, "schema_only_tables"), 49),
      {
        "state": get(schema_gap_json, "state"),
        "schema_tables": get(schema_gap_json, "schema_tables"),
        "present_tables": get(schema_gap_json, "present_tables"),
        "schema_only_tables": get(schema_gap_json, "schema_only_tables"),
      },
    ),
  )

  match try_json(work_dir + "/source-export-contract.json") {
    Some(value) => {
      let missing = get_array(value, "missing_tables")
      checks.push(
        check(
          "source_export_contract",
          eq_string(get(value, "format"), "moonproj.erp.export-contract.v1") &&
          get_bool(value, "content_verified") == Some(true) &&
          eq_int(get(value, "schema_tables"), 75) &&
          eq_int(get(value, "export_tables"), 26) &&
          eq_int(get(value, "present_tables"), 26) &&
          missing.length() == 49 &&
          get_bool(value, "promotion_authorized") == Some(false),
          {
            "state": get(value, "state"),
            "schema_tables": get(value, "schema_tables"),
            "export_tables": get(value, "export_tables"),
            "missing_tables": json_int(missing.length()),
            "verified_rows": get(value, "verified_rows"),
          },
        ),
      )
    }
    None => ()
  }
  match try_json(work_dir + "/source-export-request.json") {
    Some(value) => {
      let tables = get_array(value, "tables")
      checks.push(
        check(
          "source_export_request",
          eq_string(
            get(value, "format"),
            "moonproj.erp.source-export-request.v1",
          ) &&
          eq_string(get(value, "state"), "awaiting_source_export") &&
          eq_int(get(value, "schema_tables"), 75) &&
          eq_int(get(value, "present_tables"), 26) &&
          eq_int(get(value, "requested_tables"), 49) &&
          get_bool(value, "cutover_authorized") == Some(false) &&
          get_bool(value, "promotion_authorized") == Some(false) &&
          tables.length() == 49,
          {
            "state": get(value, "state"),
            "requested_tables": get(value, "requested_tables"),
            "schema_tables": get(value, "schema_tables"),
            "present_tables": get(value, "present_tables"),
          },
        ),
      )
    }
    None => ()
  }
  match try_json(work_dir + "/schema-cohort-plan.json") {
    Some(value) => {
      let waves = get_array(value, "waves")
      checks.push(
        check(
          "schema_cohort_plan",
          eq_string(get(value, "format"), "moonproj.erp.schema-cohort-plan.v1") &&
          eq_int(get(value, "schema_only_tables"), 49) &&
          waves.length() == 7 &&
          get_bool(value, "cutover_authorized") == Some(false),
          {
            "state": get(value, "state"),
            "schema_only_tables": get(value, "schema_only_tables"),
            "wave_count": json_int(waves.length()),
          },
        ),
      )
    }
    None => ()
  }
  mapping_check(
    checks, work_dir, "schema-foundation-security.json", "foundation_security_schema_mapping",
    "foundation-security", 6,
  )
  mapping_check(
    checks, work_dir, "schema-workflow-control.json", "workflow_control_schema_mapping",
    "workflow-control", 7,
  )
  mapping_check(
    checks, work_dir, "schema-cost-investment.json", "cost_investment_schema_mapping",
    "cost-investment", 9,
  )
  mapping_check(
    checks, work_dir, "schema-procurement-contract.json", "procurement_contract_schema_mapping",
    "procurement-contract", 7,
  )
  mapping_check(
    checks, work_dir, "schema-sales-receivables.json", "sales_receivables_schema_mapping",
    "sales-receivables", 8,
  )
  mapping_check(
    checks, work_dir, "schema-delivery-treasury.json", "delivery_treasury_schema_mapping",
    "delivery-treasury", 8,
  )
  mapping_check(
    checks, work_dir, "schema-reporting-notification.json", "reporting_notification_schema_mapping",
    "reporting-notification", 4,
  )

  let relationship = required_object(work_dir + "/relationship-audit.json")
  let relationship_json = Json::object(relationship)
  checks.push(
    check(
      "relationship_integrity",
      eq_string(
        get(relationship_json, "format"),
        "moonproj.erp.relationship-audit.v1",
      ) &&
      eq_string(
        get(relationship_json, "state"),
        "relationship_integrity_verified",
      ) &&
      get_int(relationship_json, "relationship_count", 0) > 0 &&
      eq_int(get(relationship_json, "orphan_count"), 0),
      {
        "state": get(relationship_json, "state"),
        "relationship_count": get(relationship_json, "relationship_count"),
        "reference_count": get(relationship_json, "reference_count"),
        "orphan_count": get(relationship_json, "orphan_count"),
      },
    ),
  )
  let route = required_object(work_dir + "/route-inventory.json")
  let route_json = Json::object(route)
  checks.push(
    check(
      "route_surface_inventory",
      eq_string(get(route_json, "format"), "moonproj.erp.route-inventory.v1") &&
      eq_string(get(route_json, "state"), "route_surface_inventory_verified") &&
      eq_int(get(route_json, "route_file_count"), 30) &&
      eq_int(get(route_json, "handler_count"), 338) &&
      eq_int(get(route_json, "middleware_count"), 28),
      {
        "state": get(route_json, "state"),
        "route_file_count": get(route_json, "route_file_count"),
        "handler_count": get(route_json, "handler_count"),
        "middleware_count": get(route_json, "middleware_count"),
      },
    ),
  )

  match try_json(work_dir + "/period-close-control.json") {
    Some(value) => {
      let mappings = get_array(value, "mapping_versions")
      let snapshot = get_string(value, "source_snapshot_id")
      let evidence = get_string(value, "evidence_hash").unwrap_or("")
      checks.push(
        check(
          "period_close_control",
          eq_string(
            get(value, "format"),
            "moonproj.erp.period-close-control.v1",
          ) &&
          eq_string(get(value, "state"), "ready_for_reconciled_close") &&
          snapshot is Some(_) &&
          !mappings.is_empty() &&
          evidence.has_prefix("sha256:") &&
          get_bool(value, "close_authorized") == Some(false) &&
          get_bool(value, "cash_released") == Some(false) &&
          get_bool(value, "period_posted") == Some(false) &&
          get_int(value, "link_count", 0) > 0,
          {
            "state": get(value, "state"),
            "cohort_count": get(value, "cohort_count"),
            "link_count": get(value, "link_count"),
            "source_snapshot_id": get(value, "source_snapshot_id"),
            "evidence_hash": get(value, "evidence_hash"),
            "close_authorized": get(value, "close_authorized"),
          },
        ),
      )
    }
    None => ()
  }

  let counts = {
    "integrity": Json::string(integrity),
    "schema_version": json_int(schema_version),
    "counts": Json::object({
      "company_record": json_int(raw_count),
      "company_aggregate_projection": json_int(projection_count),
      "company_accounting_event_link": json_int(link_count),
      "company_migration_receipt": json_int(receipt_count),
    }),
  }
  let expected_ok = (expected_raw < 0 || raw_count == expected_raw) &&
    (expected_projections < 0 || projection_count == expected_projections) &&
    (expected_links < 0 || link_count == expected_links)
  checks.push(
    check(
      "target_database",
      integrity == "ok" && schema_version == 4 && expected_ok,
      counts,
    ),
  )
  let (_, backup_value) = check_file(work_dir, "backup-restore.json")
  checks.push(
    check(
      "backup_restore",
      eq_string(get(backup_value, "state"), "backup_restore_verified"),
      { "state": get(backup_value, "state") },
    ),
  )
  let (_, driver_value) = check_file(work_dir, "driver-smoke.json")
  checks.push(
    check(
      "sql_driver",
      eq_string(get(driver_value, "state"), "driver_transaction_verified") &&
      get_bool(driver_value, "sql_command_verified") == Some(true) &&
      get_bool(driver_value, "duplicate_rejected") == Some(true),
      { "state": get(driver_value, "state") },
    ),
  )

  let deployment : Json? = match
    try_json(work_dir + "/production-deployment-gate.json") {
    Some(value) => {
      checks.push(
        check(
          "production_deployment_contract",
          eq_string(
            get(value, "format"),
            "moonproj.company.production-deployment-gate.v1",
          ) &&
          (
            eq_string(get(value, "state"), "ready_for_owner_review") ||
            eq_string(get(value, "state"), "ready_for_managed_deployment")
          ),
          {
            "state": get(value, "state"),
            "deployment_authorized": get(value, "deployment_authorized"),
            "missing_approval_roles": get(value, "missing_approval_roles"),
          },
        ),
      )
      Some(value)
    }
    None => None
  }
  match try_json(work_dir + "/production-service-gate.json") {
    Some(value) =>
      checks.push(
        check(
          "production_service_contract",
          eq_string(
            get(value, "format"),
            "moonproj.company.production-service-gate.v1",
          ) &&
          (
            eq_string(get(value, "state"), "ready_for_service_review") ||
            eq_string(get(value, "state"), "ready_for_production_service")
          ) &&
          get_bool(value, "arbitrary_sql") == Some(false) &&
          get_array(value, "mutation_endpoints").is_empty(),
          {
            "state": get(value, "state"),
            "service_authorized": get(value, "service_authorized"),
            "deployment_authorized": get(value, "deployment_authorized"),
            "read_endpoints": get(value, "read_endpoints"),
          },
        ),
      )
    None => ()
  }
  match try_json(work_dir + "/row-coverage.json") {
    Some(value) => {
      let uncovered = get_array(value, "uncovered_tables")
      checks.push(
        check(
          "row_coverage",
          eq_string(get(value, "format"), "moonproj.erp.row-coverage.v1") &&
          eq_string(get(value, "state"), "row_coverage_verified") &&
          eq_int(get(value, "source_rows"), 120) &&
          eq_int(get(value, "covered_rows"), 120) &&
          eq_int(get(value, "uncovered_rows"), 0) &&
          uncovered.is_empty() &&
          get_bool(value, "promotion_authorized") == Some(false),
          {
            "state": get(value, "state"),
            "source_rows": get(value, "source_rows"),
            "covered_rows": get(value, "covered_rows"),
            "uncovered_rows": get(value, "uncovered_rows"),
            "uncovered_tables": get(value, "uncovered_tables"),
          },
        ),
      )
    }
    None => ()
  }
  let acceptance : Json? = match
    try_json(work_dir + "/business-acceptance.json") {
    Some(value) => {
      checks.push(
        check(
          "business_acceptance_packet",
          eq_string(
            get(value, "format"),
            "moonproj.erp.business-acceptance-result.v1",
          ) &&
          (
            eq_string(get(value, "state"), "acceptance_pending") ||
            eq_string(get(value, "state"), "ready_for_shadow")
          ) &&
          eq_int(get(value, "required_decisions"), 5) &&
          get_bool(value, "cutover_authorized") == Some(false),
          {
            "state": get(value, "state"),
            "required_decisions": get(value, "required_decisions"),
            "pending_decisions": get(value, "pending_decisions"),
            "deferred_decisions": get(value, "deferred_decisions"),
            "acceptance_authorized": get(value, "acceptance_authorized"),
            "shadow_authorized": get(value, "shadow_authorized"),
          },
        ),
      )
      Some(value)
    }
    None => None
  }
  let shadow : Json? = match try_json(work_dir + "/shadow-period.json") {
    Some(value) => {
      checks.push(
        check(
          "shadow_period_contract",
          eq_string(
            get(value, "format"),
            "moonproj.company.shadow-period-result.v1",
          ) &&
          (
            eq_string(get(value, "state"), "shadow_pending_owner") ||
            eq_string(get(value, "state"), "shadow_ready")
          ) &&
          get_bool(value, "legacy_authoritative") == Some(true) &&
          eq_string(get(value, "target_mode"), "read_only_shadow") &&
          get_bool(value, "target_mutations_allowed") == Some(false) &&
          get_bool(value, "cutover_authorized") == Some(false) &&
          get_int(value, "parity_report_count", 0) > 0 &&
          get_int(value, "source_rows", -1) ==
          get_int(value, "covered_rows", -2),
          {
            "state": get(value, "state"),
            "period_id": get(value, "period_id"),
            "legacy_authoritative": get(value, "legacy_authoritative"),
            "target_mutations_allowed": get(value, "target_mutations_allowed"),
            "shadow_authorized": get(value, "shadow_authorized"),
            "parity_report_count": get(value, "parity_report_count"),
          },
        ),
      )
      Some(value)
    }
    None => None
  }

  let parity_paths = unique_paths(
    path_list(work_dir, "-parity.json") +
    path_list(work_dir + "/typed-cohorts", "-parity.json"),
  )
  let parity_reports : Array[Json] = []
  let mut parity_passed = !parity_paths.is_empty()
  for path in parity_paths {
    let value = read_json(path)
    parity_reports.push(
      Json::object({
        "file": Json::string(path),
        "mapping_version": get(value, "mapping_version"),
        "state": get(value, "state"),
        "expected_items": get(value, "expected_items"),
        "actual_items": get(value, "actual_items"),
      }),
    )
    if !eq_string(get(value, "state"), "shadow_verified") {
      parity_passed = false
    }
  }
  checks.push(
    check("projection_parity", parity_passed, {
      "reports": Json::array(parity_reports),
    }),
  )

  let exception_review_path = work_dir +
    "/typed-cohorts/task-state-exception-review.json"
  match try_json(exception_review_path) {
    Some(exception_review) => {
      let exceptions = get_array(exception_review, "exceptions")
      checks.push(
        check(
          "task_state_exception_review",
          eq_string(
            get(exception_review, "format"),
            "moonproj.erp.task-state-exception-review.v1",
          ) &&
          eq_string(get(exception_review, "state"), "review_required") &&
          !exceptions.is_empty() &&
          exceptions.all(fn(item) { get(item, "decision") == Json::null() }),
          {
            "state": get(exception_review, "state"),
            "exception_count": json_int(exceptions.length()),
          },
        ),
      )
      let promotion_path = work_dir +
        "/typed-cohorts/task-state-exception-evidence-promotion.json"
      let parity_path = work_dir +
        "/typed-cohorts/task-state-exception-evidence-projection-parity.json"
      let replay_path = work_dir +
        "/typed-cohorts/task-state-exception-evidence-projection-replay.json"
      let promotion = try_json(promotion_path)
      let parity = try_json(parity_path)
      let replay = try_json(replay_path)
      let evidence_passed = match (promotion, parity, replay) {
        (Some(promotion), Some(parity), Some(replay)) => {
          let items = get_array(promotion, "accepted_items")
          let candidate = if items.length() == 1 {
            get_obj(items[0], "target_candidate")
          } else {
            {}
          }
          eq_string(
            get(promotion, "format"),
            "moonproj.erp.domain-promotion.v1",
          ) &&
          eq_string(
            get(promotion, "state"),
            "promoted_through_domain_importers",
          ) &&
          eq_string(
            get(promotion, "cohort"),
            "task-state-exception-evidence-v1",
          ) &&
          get_bool(promotion, "decision_required") == Some(true) &&
          get_bool(promotion, "target_state_mutated") == Some(false) &&
          get_bool(promotion, "cash_released") == Some(false) &&
          get_bool(promotion, "accounting_posted") == Some(false) &&
          get_bool(promotion, "period_closed") == Some(false) &&
          items.length() == 1 &&
          eq_string(
            get(items[0], "target_type"),
            "project_task_state_observation",
          ) &&
          eq_string(
            get(Json::object(candidate), "observation_policy"),
            "quarantined_source_evidence",
          ) &&
          get_bool(Json::object(candidate), "decision_required") == Some(true) &&
          get_bool(Json::object(candidate), "target_state_mutated") ==
          Some(false) &&
          get(Json::object(candidate), "decision") == Json::null() &&
          get(Json::object(candidate), "decision_owner") == Json::null() &&
          get_bool(Json::object(candidate), "cash_released") == Some(false) &&
          get_bool(Json::object(candidate), "accounting_posted") == Some(false) &&
          get_bool(Json::object(candidate), "period_closed") == Some(false) &&
          get(promotion, "source_snapshot_id") ==
          get(exception_review, "source_snapshot_id") &&
          get(promotion, "mapping_version") ==
          get(exception_review, "mapping_version") &&
          eq_string(get(parity, "format"), "moonproj.erp.projection-parity.v1") &&
          get(parity, "source_snapshot_id") ==
          get(promotion, "source_snapshot_id") &&
          get(parity, "mapping_version") == get(promotion, "mapping_version") &&
          eq_string(get(parity, "state"), "shadow_verified") &&
          eq_int(get(parity, "expected_items"), 1) &&
          eq_int(get(parity, "actual_items"), 1) &&
          get_array(parity, "missing").is_empty() &&
          get_array(parity, "extra").is_empty() &&
          eq_string(get(replay, "integrity"), "ok") &&
          get(replay, "source_snapshot_id") ==
          get(promotion, "source_snapshot_id") &&
          get(replay, "mapping_version") == get(promotion, "mapping_version") &&
          eq_int(get(replay, "inserted_projections"), 0) &&
          get_bool(replay, "receipt_inserted") == Some(false)
        }
        _ => false
      }
      let evidence = match (promotion, parity, replay) {
        (Some(promotion), Some(parity), Some(replay)) =>
          Json::object({
            "promotion_file": Json::string(promotion_path),
            "parity_file": Json::string(parity_path),
            "replay_file": Json::string(replay_path),
            "mapping_version": get(promotion, "mapping_version"),
            "source_snapshot_id": get(promotion, "source_snapshot_id"),
            "observation_count": get(promotion, "observation_count"),
            "parity_state": get(parity, "state"),
            "expected_items": get(parity, "expected_items"),
            "actual_items": get(parity, "actual_items"),
            "replay_inserted_projections": get(replay, "inserted_projections"),
            "replay_receipt_inserted": get(replay, "receipt_inserted"),
          })
        _ =>
          Json::object({
            "promotion_file": Json::string(promotion_path),
            "parity_file": Json::string(parity_path),
            "replay_file": Json::string(replay_path),
            "missing_artifacts": Json::boolean(true),
          })
      }
      checks.push(
        check("task_state_exception_observed_evidence", evidence_passed, {
          "evidence_only": Json::boolean(true),
          "target_state_mutated": Json::boolean(false),
          "decision_required": Json::boolean(true),
          "evidence": evidence,
        }),
      )
    }
    None => {
      let typed_exists = @fs.is_dir(work_dir + "/typed-cohorts") catch {
        _ => false
      }
      if typed_exists {
        checks.push(
          check("task_state_exception_review", false, {
            "state": Json::string("missing"),
            "exception_count": json_int(0),
          }),
        )
        checks.push(
          check("task_state_exception_observed_evidence", false, {
            "evidence_only": Json::boolean(true),
            "target_state_mutated": Json::boolean(false),
            "decision_required": Json::boolean(true),
            "evidence": Json::object({
              "missing_review_artifact": Json::string(exception_review_path),
            }),
          }),
        )
      }
    }
  }

  let fixed_replays = [
    "projection-replay.json", "advance-offset-projection-replay.json", "accounting-link-replay.json",
    "advance-offset-accounting-link-replay.json", "payment-accounting-link-replay.json",
    "cbs-cost-link-replay.json", "cbs-budget-replay.json", "cbs-budget-source-replay.json",
    "workflow-assignment-replay.json", "delivery-progress-replay.json", "delivery-recognition-replay.json",
    "delivery-recognition-accounting-link-replay.json", "consolidated-report-replay.json",
    "investment-benchmark-replay.json", "warning-replay.json", "warning-source-replay.json",
    "notification-replay.json", "access-replay.json", "accounting-posting-replay.json",
    "opening-control-replay.json", "tax-filing-replay.json", "bank-statement-replay.json",
    "financing-facility-replay.json", "asset-lifecycle-replay.json", "treasury-plan-dispatch-replay.json",
    "invoice-subledger-replay.json", "procurement-cohort-replay.json", "investment-performance-replay.json",
  ]
  let mut replay_paths : Array[String] = []
  for name in fixed_replays {
    replay_paths.push(work_dir + "/" + name)
  }
  replay_paths = replay_paths +
    path_list(work_dir + "/typed-cohorts", "-projection-replay.json")
  let replay_values : Array[Json] = []
  for path in replay_paths {
    match try_json(path) {
      Some(value) =>
        replay_values.push(
          Json::object({
            "file": Json::string(path),
            "inserted_projections": json_int(
              get_int(value, "inserted_projections", 0),
            ),
            "inserted_accounting_links": json_int(
              get_int(value, "inserted_accounting_links", 0),
            ),
            "receipt_inserted": get(value, "receipt_inserted"),
          }),
        )
      None => ()
    }
  }
  let replay_passed = !replay_values.is_empty() &&
    replay_values.all(fn(value) {
      eq_int(get(value, "inserted_projections"), 0) &&
      eq_int(get(value, "inserted_accounting_links"), 0) &&
      get_bool(value, "receipt_inserted") == Some(false)
    })
  checks.push(
    check("replay_idempotency", replay_passed, {
      "evidence": Json::array(replay_values),
    }),
  )
  let reconciliation_names = [
    "accounting-reconciliation.json", "advance-offset-accounting-reconciliation.json",
    "payment-accounting-reconciliation.json",
  ]
  let reconciliation_values : Array[Json] = []
  for name in reconciliation_names {
    let path = work_dir + "/" + name
    match try_json(path) {
      Some(value) =>
        reconciliation_values.push(
          Json::object({
            "file": Json::string(path),
            "state": get(value, "state"),
            "link_count": get(value, "link_count"),
            "cash_released": get(value, "cash_released"),
            "period_posted": get(value, "period_posted"),
          }),
        )
      None => ()
    }
  }
  let reconciliation_passed = !reconciliation_values.is_empty() &&
    reconciliation_values.all(fn(value) {
      eq_string(get(value, "state"), "reconciled") &&
      get_bool(value, "cash_released") == Some(false) &&
      get_bool(value, "period_posted") == Some(false)
    })
  checks.push(
    check("accounting_reconciliation", reconciliation_passed, {
      "evidence": Json::array(reconciliation_values),
    }),
  )

  let deployment_present = match deployment {
    Some(_) => true
    None => false
  }
  let deployment_reason = if deployment_present {
    "managed deployment contract is not owner-approved"
  } else {
    "managed pooling, encryption, retention, and restore runbook are not approved"
  }
  let exceptions : Array[Json] = [
    Json::object({
      "id": Json::string("task-state-proj-0001"),
      "severity": Json::string("business_review"),
      "state": Json::string("quarantined"),
      "reason": Json::string(
        "two child task states conflict with the parent dependency invariant",
      ),
    }),
    Json::object({
      "id": Json::string("production-database-deployment"),
      "severity": Json::string("operational"),
      "state": Json::string("open"),
      "reason": Json::string(deployment_reason),
    }),
    Json::object({
      "id": Json::string("erp-schema-coverage"),
      "severity": Json::string("scope"),
      "state": Json::string("open"),
      "reason": Json::string(
        "the fixture contains 26 of 75 ERP schema tables; 49 schema-only tables require later cohorts",
      ),
    }),
  ]
  if acceptance is None ||
    !eq_string(get(acceptance.unwrap(), "state"), "ready_for_shadow") {
    exceptions.push(
      Json::object({
        "id": Json::string("business-acceptance"),
        "severity": Json::string("owner_review"),
        "state": Json::string("open"),
        "reason": Json::string(
          "required business, finance, migration-owner, and operations decisions are not complete",
        ),
      }),
    )
  }
  if shadow is None || !eq_string(get(shadow.unwrap(), "state"), "shadow_ready") {
    exceptions.push(
      Json::object({
        "id": Json::string("shadow-period"),
        "severity": Json::string("owner_review"),
        "state": Json::string("open"),
        "reason": Json::string(
          "read-only shadow contract is defined but operations has not authorized the shadow period",
        ),
      }),
    )
  }
  let technical_passed = checks.all(fn(value) {
    get_bool(value, "passed") == Some(true)
  })
  let report = Json::object({
    "format": Json::string("moonproj.erp.cutover-gate.v1"),
    "work_dir": Json::string(work_dir),
    "state": Json::string(
      if technical_passed {
        "ready_for_business_acceptance"
      } else {
        "blocked_by_technical_checks"
      },
    ),
    "technical_checks_passed": Json::boolean(technical_passed),
    "cutover_authorized": Json::boolean(false),
    "checks": Json::array(checks),
    "exceptions": Json::array(exceptions),
    "next_actions": Json::array([
      Json::string(
        "obtain named business, accounting, and operations acceptance",
      ),
      Json::string(
        "resolve or explicitly waive the proj-0001 task-state exception",
      ),
      Json::string("approve managed database deployment and rollback runbook"),
    ]),
  })
  @fs.write_string_to_file(output, report.stringify(indent=2) + "\n") catch {
    error => raise CutoverGateError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output),
      "state": get(report, "state"),
      "technical_checks_passed": get(report, "technical_checks_passed"),
    }).stringify(),
  )
  if !technical_passed {
    @sys.exit(1)
  }
}

///|
fn parse_int(value : String) -> Int raise CutoverGateError {
  let text = value.trim().to_owned()
  if text.is_empty() {
    raise fail("expected integer")
  }
  let mut sign = 1
  let mut index = 0
  if text.get_char(0) == Some('-') {
    sign = -1
    index = 1
  }
  let mut result = 0
  while index < text.length() {
    let char = text.get_char(index).unwrap()
    if char < '0' || char > '9' {
      raise fail("invalid integer: " + value)
    }
    result = result * 10 + char.to_int() - '0'.to_int()
    index += 1
  }
  result * sign
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 12 {
    println(
      "usage: cutover_gate WORK_DIR OUTPUT EXPECTED_RAW EXPECTED_PROJECTIONS EXPECTED_LINKS INTEGRITY SCHEMA RAW PROJECTIONS LINKS RECEIPTS",
    )
    @sys.exit(2)
  } else {
    run(
      args[1],
      args[2],
      parse_int(args[3]),
      parse_int(args[4]),
      parse_int(args[5]),
      args[6],
      parse_int(args[7]),
      parse_int(args[8]),
      parse_int(args[9]),
      parse_int(args[10]),
      parse_int(args[11]),
    ) catch {
      CutoverGateError::InvalidInput(message) => {
        println("company cutover gate failed: " + message)
        @sys.exit(1)
      }
      CutoverGateError::Io(_) => {
        println("company cutover gate failed: filesystem error")
        @sys.exit(1)
      }
    }
  }
}
