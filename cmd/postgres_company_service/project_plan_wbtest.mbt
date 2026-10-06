///|
test "project plan lookup recognizes a native command project" {
  let rows : Array[SourceRow] = [
    {
      record_id: "native-project",
      source_id: "moonproj:command:create-native-project",
      payload: {
        "project_id": "native-project",
        "proj_guid": "native-project",
        "source_kind": "command",
        "state": "active",
      },
    },
  ]
  assert_true(project_plan_project_contains_id(rows, "native-project"))
  assert_false(project_plan_project_contains_id(rows, "other-project"))
}

///|
test "project plan lookup recognizes an imported project projection" {
  let rows : Array[SourceRow] = [
    {
      record_id: "imported-project",
      source_id: "moonproj:project-import:batch-1",
      payload: { "proj_guid": "imported-project", "state": "active" },
    },
  ]
  assert_true(project_plan_project_contains_id(rows, "imported-project"))
}

///|
test "project plan lookup preserves ERP identity and record fallback" {
  let rows : Array[SourceRow] = [
    {
      record_id: "raw-row-1",
      source_id: "erp:ep_project:raw-row-1",
      payload: { "proj_guid": "erp-project" },
    },
    {
      record_id: "legacy-fallback",
      source_id: "erp:ep_project:legacy-fallback",
      payload: {},
    },
  ]
  assert_true(project_plan_project_contains_id(rows, "erp-project"))
  assert_true(project_plan_project_contains_id(rows, "legacy-fallback"))
  assert_false(project_plan_project_contains_id(rows, "raw-row-1"))
}

///|
test "project plan lookup rejects absent project identities" {
  assert_false(project_plan_project_contains_id([], "missing-project"))
}
