///|
test "company bootstrap empty response is reachable but never claims persistence" {
  let empty = company_profile_response(None)
  assert_eq(json_field(empty, "profile"), Some(Json::null()))
  assert_false(json_bool(empty, "persisted", true))
  assert_true(json_bool(empty, "success", false))
  let failure = service_error_response(
    CompanyServiceError::Database(@postgres.PostgresError::Failed("fixture")),
  )
  assert_eq(failure.0, 503)
  assert_false(failure.1 == empty)
}

///|
test "company bootstrap accepts an ordinary signed workspace actor without ERP users" {
  let request = company_profile_create_request(
    { "companyName": "  My OPC  " },
    "desktop-user",
    "first",
  )
  assert_eq(json_text(request, "company_name", ""), "My OPC")
  assert_eq(json_text(request, "bu_guid", ""), "ORG-first")
  assert_eq(json_text(request, "actor_id", ""), "desktop-user")
  let sql = company_profile_create_sql(request, "first")
  assert_false(sql.contains("sys_user"))
  assert_false(sql.contains("auth_current_user"))
  for
    false_fact in [
      "legal_name", "cash_balance", "capital", "tax_status", "''ready''",
    ] {
    assert_false(sql.contains(false_fact))
  }
}

///|
test "company bootstrap canonical request compares name explicit unit and actor" {
  let request = company_profile_create_request(
    { "companyName": "My OPC" },
    "desktop-user",
    "first",
  )
  assert_eq(
    request,
    company_profile_create_request(
      { "companyName": " My OPC " },
      "desktop-user",
      "first",
    ),
  )
  for
    altered in [
      company_profile_create_request(
        { "companyName": "Changed" },
        "desktop-user",
        "first",
      ),
      company_profile_create_request(
        { "companyName": "My OPC" },
        "other-user",
        "first",
      ),
      company_profile_create_request(
        { "companyName": "My OPC", "existingBuGuid": "ERP-unit" },
        "desktop-user",
        "first",
      ),
    ] {
    assert_false(json_equal(request, altered))
  }
}

///|
test "company bootstrap rejects malformed names IDs and overlong generated identities" {
  for
    body in (
      [
        {},
        { "companyName": 5 },
        { "companyName": " " },
        { "companyName": "My OPC", "existingBuGuid": "" },
        { "companyName": "My OPC", "existingBuGuid": "not/a/unit" },
      ] : Array[Json]) {
    assert_true(
      (try? company_profile_create_request(body, "desktop-user", "first"))
      is Err(_),
    )
  }
  for n in [0, 100, 128, 129] {
    assert_true(
      (try? company_profile_create_request(
        { "companyName": "My OPC" },
        "desktop-user",
        Array::make(n, "k").join(""),
      ))
      is Err(_),
    )
  }
  let maximum = 128 - "moonproj:audit:company_profile:create:".length()
  company_command_validate_ids(
    "company_profile:create:",
    Array::make(maximum, "k").join(""),
  )
  assert_true(
    (try? company_command_validate_ids(
      "company_profile:create:",
      Array::make(maximum + 1, "k").join(""),
    ))
    is Err(_),
  )
}

///|
test "company bootstrap transaction compares replay before singleton and unit checks" {
  let request = company_profile_create_request(
    { "companyName": "My OPC" },
    "desktop-user",
    "first",
  )
  let sql = company_profile_create_sql(request, "first")
  assert_true(
    sql.find("LOCK TABLE company_aggregate_projection").unwrap() <
    sql.find("DO '").unwrap(),
  )
  assert_true(
    sql.find("IF canonical IS NOT NULL").unwrap() <
    sql.find("ELSIF saved_profile IS NOT NULL").unwrap(),
  )
  assert_true(sql.contains("canonical->''request'' IS DISTINCT FROM request"))
  assert_false(sql.contains("ON CONFLICT"))
  assert_true(sql.contains("ON COMMIT DROP"))
  assert_true(sql.contains("canonical_reference"))
}

///|
test "business unit tree preserves imported IDs hierarchy and independent native root" {
  let units : Array[SourceRow] = [
    {
      record_id: "raw-child",
      source_id: "erp-child",
      payload: {
        "bu_guid": "child",
        "bu_name": "Branch",
        "parent_guid": "erp-root",
        "__unit_source_kind": "imported",
      },
    },
    {
      record_id: "raw-root",
      source_id: "erp-root-source",
      payload: {
        "bu_guid": "erp-root",
        "bu_name": "ERP",
        "bu_code": "existing-code",
        "legal_name": "Existing legal name",
        "__unit_source_kind": "imported",
      },
    },
    {
      record_id: "ORG-first",
      source_id: "native",
      payload: {
        "bu_guid": "ORG-first",
        "bu_name": "My OPC",
        "level": 1,
        "__unit_source_kind": "command",
      },
    },
  ]
  let response = business_units_tree_from_rows(units)
  let roots = match json_field(response, "data") {
    Some(Array(rows)) => rows
    _ => []
  }
  assert_eq(roots.length(), 2)
  let imported = roots.filter(root => {
      json_text(root, "buGuid", "") == "erp-root"
    })[0]
  assert_eq(json_text(imported, "legalName", ""), "Existing legal name")
  assert_eq(json_text(imported, "buCode", ""), "existing-code")
  let children = match json_field(imported, "children") {
    Some(Array(rows)) => rows
    _ => []
  }
  assert_eq(children.length(), 1)
  assert_eq(json_text(children[0], "buGuid", ""), "child")
  let partial = business_units_tree_from_rows([units[1], units[1], units[2]])
  assert_eq(json_bool(partial, "success", false), true)
  let partial_roots = match json_field(partial, "data") {
    Some(Array(rows)) => rows
    _ => []
  }
  assert_eq(partial_roots.length(), 1)
  assert_eq(json_text(partial_roots[0], "buGuid", ""), "ORG-first")
  let diagnostics = match json_field(partial, "diagnostics") {
    Some(Array(rows)) => rows
    _ => []
  }
  assert_eq(json_text(diagnostics[0], "code", ""), "ambiguous_identity")
}

///|
test "unrelated duplicate cycle and blank unit names preserve usable identities and canonical names" {
  let rows : Array[SourceRow] = [
    {
      record_id: "first",
      source_id: "first",
      payload: { "bu_guid": "bad-duplicate" },
    },
    {
      record_id: "second",
      source_id: "second",
      payload: { "bu_guid": "bad-duplicate" },
    },
    {
      record_id: "cycle-a",
      source_id: "a",
      payload: { "bu_guid": "cycle-a", "parent_guid": "cycle-b" },
    },
    {
      record_id: "cycle-b",
      source_id: "b",
      payload: { "bu_guid": "cycle-b", "parent_guid": "cycle-a" },
    },
    {
      record_id: "blank",
      source_id: "blank",
      payload: { "bu_guid": "blank", "bu_name": "" },
    },
    {
      record_id: "valid",
      source_id: "valid",
      payload: { "bu_guid": "valid", "bu_name": "Existing" },
    },
    {
      record_id: "ORG-first",
      source_id: "native",
      payload: {
        "bu_guid": "ORG-first",
        "bu_name": "My OPC",
        "__unit_source_kind": "command",
      },
    },
    {
      record_id: "child",
      source_id: "child",
      payload: { "bu_guid": "child", "parent_guid": "bad-duplicate" },
    },
  ]
  let response = business_units_tree_from_rows(rows)
  let roots = match json_field(response, "data") {
    Some(Array(values)) => values
    _ => []
  }
  for id in ["valid", "ORG-first", "blank", "cycle-a", "cycle-b", "child"] {
    assert_true(roots.any(row => json_text(row, "buGuid", "") == id))
  }
  assert_false(
    roots.any(row => json_text(row, "buGuid", "") == "bad-duplicate"),
  )
  let blank = roots.filter(row => json_text(row, "buGuid", "") == "blank")[0]
  assert_eq(json_text(blank, "buName", "incorrect"), "")
  assert_eq(json_text(blank, "displayName", ""), "blank")
  let cycle = roots.filter(row => json_text(row, "buGuid", "") == "cycle-a")[0]
  assert_eq(json_text(cycle, "parentGuid", ""), "cycle-b")
  assert_eq(json_text(cycle, "hierarchyIssue", ""), "cycle")
  assert_true(response.stringify().length() > 0)
  let profile = company_profile_response(
    Some({
      "company_id": "current",
      "company_name": "Saved",
      "bu_guid": "blank",
      "bu_name": "",
    }),
  )
  assert_eq(
    json_text(json_field(profile, "profile").unwrap(), "bu_name", "wrong"),
    "",
  )
}

///|
test "unit tree omits competing tombstone and mismatched native identities without hiding valid units" {
  let response = business_units_tree_from_rows([
    {
      record_id: "raw",
      source_id: "raw",
      payload: { "bu_guid": "shared", "bu_name": "Live" },
    },
    {
      record_id: "shared",
      source_id: "native",
      payload: {
        "bu_guid": "shared",
        "state": "deleted",
        "__unit_source_kind": "command",
      },
    },
    {
      record_id: "physical",
      source_id: "mismatch",
      payload: {
        "bu_guid": "different-public",
        "__unit_source_kind": "command",
        "__unit_aggregate_id": "physical",
      },
    },
    { record_id: "valid", source_id: "valid", payload: { "bu_guid": "valid" }, },
  ])
  let roots = match json_field(response, "data") {
    Some(Array(values)) => values
    _ => []
  }
  assert_eq(roots.length(), 1)
  assert_eq(json_text(roots[0], "buGuid", ""), "valid")
}

///|
fn company_psql_frame(value : Json) -> String {
  "MOONPROJ_COMMAND_RESPONSE:" +
  @crypto.bytes_to_hex_string(@encoding/utf8.encode(value.stringify()))
}

///|
test "transaction response parser handles actual psql command tags whitespace and framed conflicts" {
  for status in [200, 201, 409] {
    let body : Json = {
      "success": Json::boolean(status < 400),
      "profile": null,
    }
    let frame = company_psql_frame({
      "status": Json::number(status.to_double()),
      "body": body,
    })
    let output = "\nBEGIN\nLOCK TABLE\nLOCK TABLE\nCREATE TABLE\nDO\n  " +
      frame +
      "  \r\nCOMMIT\n\n"
    assert_eq(company_command_parse_response(output), (status, body))
    assert_eq(company_command_parse_response(frame + "\n"), (status, body))
  }
}

///|
test "invalid missing duplicate or rolled-back response frames remain uncertain 503" {
  let frame = company_psql_frame({
    "status": 201,
    "body": { "persisted": true },
  })
  for
    output in [
      "",
      "BEGIN\nCOMMIT",
      "MOONPROJ_COMMAND_RESPONSE:zz",
      "MOONPROJ_COMMAND_RESPONSE:7b",
      frame + "\n" + frame,
      "BEGIN\n" + frame + "\nROLLBACK",
      company_psql_frame({ "status": 0, "body": {} }),
      company_psql_frame({ "status": 201, "body": null }),
    ] {
    try company_command_parse_response(output) catch {
      error => assert_eq(service_error_response(error).0, 503)
    } noraise {
      _ => assert_true(false, msg="Uncertain output must not be accepted")
    }
  }
}

///|
test "possible commit recovers only matching canonical receipt and never invents rejection or success" {
  let request : Json = { "company_name": "My OPC", "actor_id": "desktop-user" }
  let receipt : Json = {
    "request": request,
    "result": { "company_id": "current" },
  }
  assert_eq(company_command_recovery_receipt(Some(receipt), request), receipt)
  try company_command_recovery_receipt(None, request) catch {
    error => assert_eq(service_error_response(error).0, 503)
  } noraise {
    _ => assert_true(false)
  }
  try
    company_command_recovery_receipt(Some(receipt), {
      "company_name": "My OPC",
      "actor_id": "other-user",
    })
  catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => assert_true(false)
  }
}

///|
test "company SQL fixture exports actual compiled transaction and unit selectors" {
  let queries : Map[String, Json] = Map([])
  for
    (label, name, actor, key, unit) in [
      ("profile_create", "My OPC", "desktop-user", "first", ""),
      ("profile_name_conflict", "Changed", "desktop-user", "first", ""),
      ("profile_actor_conflict", "My OPC", "other-user", "first", ""),
      ("profile_other", "Other OPC", "desktop-user", "second", ""),
      ("profile_bind", "Bound OPC", "desktop-user", "bind", "ERP-unit"),
      ("profile_missing", "Missing", "desktop-user", "missing", "unknown-unit"),
      (
        "profile_ambiguous", "Ambiguous", "desktop-user", "ambiguous", "ambiguous-unit",
      ),
      (
        "profile_mismatch", "Mismatch", "desktop-user", "mismatch", "physical-unit",
      ),
      (
        "profile_blank", "Blank existing name", "desktop-user", "blank", "blank-name",
      ),
      ("profile_deleted", "Deleted", "desktop-user", "deleted", "deleted-unit"),
      ("profile_collision", "Collision", "desktop-user", "collision", ""),
      (
        "profile_projection_collision", "Collision", "desktop-user", "projection-collision",
        "",
      ),
    ] {
    let body : Map[String, Json] = { "companyName": Json::string(name) }
    if !unit.is_empty() {
      body.set("existingBuGuid", Json::string(unit))
    }
    queries.set(
      label,
      Json::string(
        company_profile_create_sql(
          company_profile_create_request(Json::object(body), actor, key),
          key,
        ),
      ),
    )
  }
  queries.set("profile_read", Json::string(company_profile_read_sql()))
  queries.set("units_all", Json::string(business_unit_rows_sql(None)))
  queries.set("units_tree_candidates", Json::string(business_unit_tree_sql()))
  queries.set(
    "units_exact",
    Json::string(business_unit_rows_sql(Some("ORG-first"))),
  )
  queries.set(
    "project_first_read",
    Json::string(project_identity_sql("PRJ-SRC-project-first", false)),
  )
  let project_body : Json = {
    "projCode": "first-project",
    "projName": "First project",
    "buGuid": "ORG-first",
  }
  let create = project_source_create_request(
    project_body, "project-first", "desktop-user",
  )
  for
    (label, kind, request, key) in [
      ("project_create", "create", create, "project-first"),
      (
        "project_changed_actor",
        "create",
        project_source_create_request(
          project_body, "project-first", "other-user",
        ),
        "project-first",
      ),
      (
        "project_changed_name",
        "create",
        project_source_create_request(
          {
            "projCode": "first-project",
            "projName": "Changed",
            "buGuid": "ORG-first",
          },
          "project-first",
          "desktop-user",
        ),
        "project-first",
      ),
      (
        "project_update",
        "update",
        project_source_update_request(
          "PRJ-SRC-project-first",
          { "projName": "Renamed" },
          "desktop-user",
        ),
        "project-update",
      ),
      (
        "project_delete",
        "delete",
        project_source_delete_request(
          "PRJ-SRC-project-first",
          Json::empty_object(),
          "desktop-user",
        ),
        "project-delete",
      ),
    ] {
    queries.set(
      label,
      Json::string(project_source_atomic_sql(kind, request, key)),
    )
  }
  for
    (label, id) in [
      ("project_raw_collision", "Z-raw-target"),
      ("project_import_collision", "Z-import-target"),
      ("project_native_collision", "Z-native-target"),
      ("project_deleted_collision", "deleted-native"),
    ] {
    let request = project_source_create_request(
      {
        "projGuid": Json::string(id),
        "projCode": "duplicate-code-is-allowed",
        "projName": "Collision",
        "buGuid": "ORG-first",
      },
      label,
      "desktop-user",
    )
    queries.set(
      label,
      Json::string(project_source_atomic_sql("create", request, label)),
    )
  }
  for
    (label, unit) in [
      ("project_without_profile", "ORG-first"),
      ("project_missing_unit", "does-not-exist"),
    ] {
    let request = project_source_create_request(
      {
        "projCode": "first-project",
        "projName": "Independent project",
        "buGuid": Json::string(unit),
      },
      label,
      "desktop-user",
    )
    queries.set(
      label,
      Json::string(project_source_atomic_sql("create", request, label)),
    )
  }
  if @env.get_env_var("MOONPROJ_EXPORT_COMPANY_BOOTSTRAP_SQL") == Some("1") {
    println("COMPANY_BOOTSTRAP_SQL=" + Json::object(queries).stringify())
  }
}

///|
test "project command transaction protects identity and canonical receipt without conflict swallowing" {
  let request = project_source_create_request(
    { "projCode": "one", "projName": "One", "buGuid": "ORG-first" },
    "project-first",
    "desktop-user",
  )
  let sql = project_source_atomic_sql("create", request, "project-first")
  assert_true(sql.contains("canonical->''request'' IS DISTINCT FROM request"))
  assert_true(
    sql.contains("identity_count <> 0 OR current_payload IS NOT NULL"),
  )
  assert_true(sql.contains("business unit is missing, deleted, or ambiguous"))
  assert_false(sql.contains("ON CONFLICT"))
  assert_false(sql.contains("company_profile"))
  assert_false(sql.contains("sys_user"))
  assert_true(
    (try? project_source_create_request(
      { "projCode": "one", "projName": "One", "buGuid": "ORG-first" },
      Array::make(121, "k").join(""),
      "desktop-user",
    ))
    is Err(_),
  )
}
