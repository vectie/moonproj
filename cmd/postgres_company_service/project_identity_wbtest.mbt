///|
fn project_identity_fixture_row(
  record_id : String,
  project_id : String,
  source_id : String,
  deleted? : Bool = false,
) -> SourceRow {
  {
    record_id,
    source_id,
    payload: {
      "proj_guid": Json::string(project_id),
      "state": Json::string(if deleted { "deleted" } else { "active" }),
    },
  }
}

///|
test "project identity exact detail and membership survive 600 unrelated projects per source" {
  for
    source in [
      "erp:ep_project:", "moonproj:project-import:", "moonproj:command:",
    ] {
    let rows : Array[SourceRow] = []
    for index in 0..<600 {
      let id = "A-unrelated-" + index.to_string()
      rows.push(project_identity_fixture_row(id, id, source + id))
    }
    rows.push(
      project_identity_fixture_row("Z-storage", "Z-target", source + "Z-source"),
    )
    let resolved = project_identity_live_rows(rows, "Z-target")
    assert_eq(resolved.length(), 1)
    assert_eq(resolved[0].record_id, "Z-storage")
    assert_eq(resolved[0].source_id, source + "Z-source")
    assert_true(project_plan_project_contains_id(rows, "Z-target"))
    assert_false(project_plan_project_contains_id(rows, "Z-storage"))
    assert_false(project_plan_project_contains_id(rows, "missing"))
  }
}

///|
test "project identity rejects every cross-source collision rather than merging" {
  let sources = [
    "erp:ep_project:", "moonproj:project-import:", "moonproj:command:",
  ]
  for left in 0..<sources.length() {
    for right in (left + 1)..<sources.length() {
      for deleted in [false, true] {
        let rows = [
          project_identity_fixture_row("left", "shared", sources[left] + "left"),
          project_identity_fixture_row(
            "right",
            "shared",
            sources[right] + "right",
            deleted~,
          ),
        ]
        try project_plan_project_contains_id(rows, "shared") catch {
          CompanyServiceError::CommandRejected(status, message) => {
            assert_eq(status, 409)
            assert_true(message.contains("ambiguous"))
          }
          _ => assert_true(false, msg="expected project identity collision")
        } noraise {
          _ =>
            assert_true(
              false,
              msg="colliding project identity must not authorize plan-task membership",
            )
        }
      }
    }
  }
}

///|
test "project identity catalog omits only ambiguous IDs and preserves unrelated selection" {
  let rows = [
    project_identity_fixture_row(
      "same-storage", "raw-guid", "erp:ep_project:raw",
    ),
    project_identity_fixture_row(
      "same-storage", "native-guid", "moonproj:command:native",
    ),
  ]
  let (initial, initial_diagnostics) = project_identity_catalog(rows)
  assert_eq(initial.length(), 2)
  assert_true(initial_diagnostics.is_empty())
  rows.push(
    project_identity_fixture_row(
      "import-storage", "raw-guid", "moonproj:project-import:import",
    ),
  )
  let (selectable, diagnostics) = project_identity_catalog(rows)
  assert_eq(selectable.length(), 1)
  assert_eq(json_text(selectable[0].payload, "proj_guid", ""), "native-guid")
  assert_eq(selectable[0].record_id, "same-storage")
  assert_eq(selectable[0].source_id, "moonproj:command:native")
  assert_eq(diagnostics.length(), 1)
  assert_eq(json_text(diagnostics[0], "code", ""), "ambiguous_project_identity")
  assert_eq(json_text(diagnostics[0], "projectId", ""), "raw-guid")
  assert_true(project_plan_project_contains_id(rows, "native-guid"))
  assert_true(project_plan_project_contains_id(selectable, "native-guid"))
  assert_false(project_plan_project_contains_id(selectable, "raw-guid"))
  try project_plan_project_contains_id(rows, "raw-guid") catch {
    CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 409)
    _ =>
      assert_true(false, msg="expected selected ambiguous identity rejection")
  } noraise {
    _ =>
      assert_true(
        false,
        msg="an exact ambiguous project must still be rejected",
      )
  }
}

///|
test "project catalog unresolved BU name preserves project identity and unrelated units" {
  let project : SourceRow = {
    record_id: "valid-project",
    source_id: "moonproj:command:valid-project",
    payload: { "proj_guid": "valid-project", "bu_guid": "shared-unit" },
  }
  let units : Array[SourceRow] = [
    {
      record_id: "raw-unit",
      source_id: "erp:mu_business_unit:raw-unit",
      payload: { "bu_guid": "shared-unit", "bu_name": "Imported name" },
    },
    {
      record_id: "shared-unit",
      source_id: "moonproj:command:unit",
      payload: { "bu_guid": "shared-unit", "bu_name": "Native name" },
    },
  ]
  let (selectable, diagnostics) = project_identity_catalog([project])
  let unresolved = project_catalog_unit_rows(
    "valid-project", "shared-unit", units, false, diagnostics,
  )
  assert_eq(selectable.length(), 1)
  assert_eq(json_text(selectable[0].payload, "bu_guid", ""), "shared-unit")
  assert_eq(unit_name(unresolved, "shared-unit"), "")
  assert_eq(diagnostics.length(), 1)
  assert_eq(
    json_text(diagnostics[0], "code", ""),
    "ambiguous_project_business_unit",
  )
  assert_eq(json_text(diagnostics[0], "projectId", ""), "valid-project")
  assert_eq(json_text(diagnostics[0], "buGuid", ""), "shared-unit")
  let valid_unit : SourceRow = {
    record_id: "good-unit",
    source_id: "moonproj:command:good-unit",
    payload: { "bu_guid": "good-unit", "bu_name": "Unaffected name" },
  }
  let unaffected = project_catalog_unit_rows(
    "other-project",
    "good-unit",
    [valid_unit],
    false,
    diagnostics,
  )
  assert_eq(unit_name(unaffected, "good-unit"), "Unaffected name")
  assert_eq(diagnostics.length(), 1)
  assert_true(project_plan_project_contains_id(selectable, "valid-project"))
  try
    project_catalog_unit_rows("valid-project", "shared-unit", units, true, [])
  catch {
    CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 409)
    _ =>
      assert_true(false, msg="expected exact business-unit identity rejection")
  } noraise {
    _ =>
      assert_true(
        false,
        msg="exact detail must retain its local BU collision guard",
      )
  }
}

///|
test "project identity tombstones remain absent and unrelated tombstones do not block" {
  let rows = [
    project_identity_fixture_row(
      "deleted",
      "deleted",
      "moonproj:command:delete",
      deleted=true,
    ),
    project_identity_fixture_row(
      "active", "active", "moonproj:project-import:active",
    ),
  ]
  assert_true(project_identity_live_rows(rows, "deleted").is_empty())
  assert_false(project_plan_project_contains_id(rows, "deleted"))
  assert_true(project_plan_project_contains_id(rows, "active"))
}

///|
test "project catalog groups competing tombstones before removing inactive choices" {
  let (rows, diagnostics) = project_identity_catalog([
    project_identity_fixture_row("raw-shared", "shared", "erp:shared"),
    project_identity_fixture_row(
      "native-shared",
      "shared",
      "native:shared",
      deleted=true,
    ),
    project_identity_fixture_row("valid", "valid", "native:valid"),
  ])
  assert_eq(rows.length(), 1)
  assert_eq(json_text(rows[0].payload, "proj_guid", ""), "valid")
  assert_eq(diagnostics.length(), 1)
  assert_eq(json_text(diagnostics[0], "projectId", ""), "shared")
}

///|
test "project identity recognizes both raw ERP deletion timestamp aliases" {
  for field in ["deleted_at", "deletedAt"] {
    let values : Map[String, Json] = { "proj_guid": "raw-deleted" }
    values.set(field, Json::string("2026-10-02T10:00:00Z"))
    let rows : Array[SourceRow] = [
      {
        record_id: "raw-storage",
        source_id: "erp:ep_project:raw-storage",
        payload: Json::object(values),
      },
    ]
    assert_false(project_plan_project_contains_id(rows, "raw-deleted"))
    assert_true(project_identity_live_rows(rows, "raw-deleted").is_empty())
    rows.push(
      project_identity_fixture_row(
        "native", "raw-deleted", "moonproj:command:native",
      ),
    )
    try project_plan_project_contains_id(rows, "raw-deleted") catch {
      CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 409)
      _ => assert_true(false, msg="expected raw tombstone identity collision")
    } noraise {
      _ =>
        assert_true(
          false,
          msg="raw tombstone must not expose a competing project",
        )
    }
  }
}

///|
test "project identity preserves raw GUID precedence with malformed or absent fallback" {
  let rows : Array[SourceRow] = [
    {
      record_id: "raw-storage",
      source_id: "erp:ep_project:raw-storage",
      payload: { "proj_guid": "public-guid" },
    },
    { record_id: "no-guid", source_id: "erp:ep_project:no-guid", payload: {}, },
    {
      record_id: "null-guid",
      source_id: "erp:ep_project:null-guid",
      payload: { "proj_guid": Json::null() },
    },
    {
      record_id: "object-guid",
      source_id: "erp:ep_project:object-guid",
      payload: { "proj_guid": {} },
    },
    {
      record_id: "empty-guid",
      source_id: "erp:ep_project:empty-guid",
      payload: { "proj_guid": "" },
    },
  ]
  assert_true(project_plan_project_contains_id(rows, "public-guid"))
  assert_false(project_plan_project_contains_id(rows, "raw-storage"))
  for id in ["no-guid", "null-guid", "object-guid"] {
    assert_true(project_plan_project_contains_id(rows, id))
  }
  assert_false(project_plan_project_contains_id(rows, "empty-guid"))
}

///|
test "project identity row decoding keeps storage and source identity and current revision" {
  let rows = project_identity_decode_rows(
    "726177|6572703a726177|7b2270726f6a5f67756964223a2267756964227d|0\n" +
    "696d706f7274|696d706f72743a6576656e74|7b2270726f6a5f67756964223a22696d706f72742d67756964227d|7\n",
  )
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].record_id, "raw")
  assert_eq(rows[0].source_id, "erp:raw")
  assert_eq(json_text(rows[0].payload, "proj_guid", ""), "guid")
  assert_true(json_field(rows[0].payload, "__revision") is None)
  assert_eq(rows[1].record_id, "import")
  assert_eq(rows[1].source_id, "import:event")
  assert_eq(json_int(rows[1].payload, "__revision", 0), 7)
}

///|
test "project identity SQL selects latest before mutable filters and never caps exact lookup" {
  let sql = project_identity_sql("quote'escaped", false)
  assert_false(sql.contains("LIMIT"))
  assert_false(sql.contains("company_profile"))
  assert_true(sql.contains("'quote''escaped'"))
  assert_true(
    sql.contains(
      "WHERE aggregate_type = 'project' ORDER BY aggregate_id, revision DESC)",
    ),
  )
  assert_true(
    sql.contains(
      "WHERE aggregate_type = 'project_import' ORDER BY aggregate_id, revision DESC)",
    ),
  )
  assert_true(
    sql.contains(
      "FROM latest_native_project WHERE payload->>'source_kind' = 'command'",
    ),
  )
  assert_true(
    sql.contains(
      ") authoritative WHERE coalesce(payload->>'state', '') <> 'deleted'",
    ),
  )
  assert_false(project_identity_sql("target", true).contains("<> 'deleted'"))
}

///|
test "project identity SQL fixture exports the actual service query builder" {
  let queries : Map[String, Json] = {}
  for
    id in [
      "Z-raw-target", "Z-raw-fallback", "Z-import-target", "Z-native-target", "raw-storage-target",
      "public-raw-target", "null-guid", "object-guid", "empty-guid", "deleted-raw",
      "deleted-import", "deleted-native", "old-import-identity", "new-import-identity",
      "old-native-identity", "new-native-identity", "migration-only", "native-source-replaced",
      "shared-raw-import", "shared-raw-native", "shared-import-native", "shared-all-three",
      "deleted-shared", "raw-deleted-at", "raw-deleted-camel",
    ] {
    queries.set(id, Json::string(project_identity_sql(id, true)))
  }
  for
    id in [
      "deleted-raw", "deleted-import", "deleted-native", "deleted-shared", "raw-deleted-at",
      "raw-deleted-camel",
    ] {
    queries.set(
      id + "-live-only",
      Json::string(project_identity_sql(id, false)),
    )
  }
  assert_eq(queries.length(), 31)
  if @env.get_env_var("MOONPROJ_EXPORT_PROJECT_IDENTITY_SQL") == Some("1") {
    println("PROJECT_IDENTITY_SQL=" + Json::object(queries).stringify())
  }
}
