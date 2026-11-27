///|
test "product association survives the public native task projection" {
  let item = project_plan_task_item(
    {
      record_id: "PT-book",
      source_id: "create-book",
      payload: {
        "project_id": "shared-project",
        "product_id": "moonbook",
        "__created_at": "2026-11-24T10:00:00.000000",
      },
    },
    true,
    [],
  )
  assert_eq(json_field(item, "product_id"), Some(Json::string("moonbook")))
  assert_eq(json_text(item, "createdAt", ""), "2026-11-24T10:00:00.000000")
}

///|
test "product association survives the stored report projection" {
  let item = delivery_report_item(
    {
      record_id: "report-book",
      source_id: "report-book",
      payload: {
        "task_id": "PT-book",
        "project_id": "shared-project",
        "product_id": "moonbook",
      },
    },
    true,
  )
  assert_eq(json_field(item, "product_id"), Some(Json::string("moonbook")))
}

///|
fn product_work_test_row(
  id : String,
  project : String,
  product : Json,
  command : Bool,
) -> SourceRow {
  {
    record_id: id,
    source_id: "fixture:" + id,
    payload: {
      "task_id": Json::string(id),
      "project_id": Json::string(project),
      "product_id": product,
      "task_name": "MoonBook display name does not imply association",
      "state": "pending",
      "source_kind": Json::string(if command { "command" } else { "imported" }),
    },
  }
}

///|
fn product_work_report_body() -> Json {
  {
    "report_id": "report-book",
    "task_id": "PT-book",
    "project_id": "shared-project",
    "progress_pct": 100,
    "report_date": "2026-10-02",
    "summary": "Observed output",
    "evidence_ids": ["receipt-book"],
    "product_id": "client-cannot-retag-report",
  }
}

///|
test "product normalization accepts explicit unknown IDs but rejects malformed nontext IDs" {
  assert_eq(
    plan_task_product_id({ "product_id": " moonbook " }),
    Some("moonbook"),
  )
  assert_eq(
    plan_task_product_id({ "product_id": "removed.from.catalog:v2" }),
    Some("removed.from.catalog:v2"),
  )
  for
    body in (
      [
        {},
        { "product_id": Json::null() },
        { "product_id": "" },
        { "product_id": "   " },
      ] : Array[Json]) {
    assert_eq(plan_task_product_id(body), None)
  }
  for
    body in (
      [
        { "product_id": 12 },
        { "product_id": true },
        { "product_id": [] },
        { "product_id": "a/b" },
        { "product_id": "a b" },
      ] : Array[Json]) {
    assert_true(
      (Ok(plan_task_product_id(body)) catch { e => Err(e) }) is Err(_),
    )
  }
}

///|
test "unassigned create requests retain their canonical bytes and explicit tags participate in equality" {
  let original : Json = {
    "task_id": "PT-book",
    "project_id": "shared-project",
    "command_type": "create",
  }
  for
    body in (
      [{}, { "product_id": Json::null() }, { "product_id": "" }] : Array[Json]) {
    assert_eq(plan_task_with_product_metadata(original, body, true), original)
  }
  let tagged = plan_task_with_product_metadata(
    original,
    { "product_id": "moonbook" },
    true,
  )
  assert_false(json_equal(tagged, original))
  assert_eq(
    plan_task_with_product_metadata(
      original,
      { "product_id": "moonbook" },
      true,
    ),
    tagged,
  )
  assert_false(
    json_equal(
      plan_task_with_product_metadata(
        original,
        { "product_id": "moondesk" },
        true,
      ),
      tagged,
    ),
  )
}

///|
test "ordinary product update omission preserves tag and explicit clear changes only metadata" {
  let payload : Json = {
    "product_id": "moonbook",
    "execution_workspace": "/explicit/book",
    "execution_model": "chosen",
    "execution": execution_test_record("running"),
    "state": "in_progress",
  }
  assert_eq(plan_task_product_metadata({}, false), Json::object({}))
  assert_eq(plan_task_with_product_metadata(payload, {}, false), payload)
  for
    body in (
      [
        { "product_id": Json::null() },
        { "product_id": "" },
        { "product_id": "moondesk" },
      ] : Array[Json]) {
    let changed = plan_task_with_product_metadata(payload, body, false)
    assert_eq(
      json_field(changed, "execution"),
      json_field(payload, "execution"),
    )
    assert_eq(json_text(changed, "execution_workspace", ""), "/explicit/book")
    assert_eq(json_text(changed, "execution_model", ""), "chosen")
    assert_eq(json_text(changed, "state", ""), "in_progress")
  }
  assert_eq(
    plan_task_product_metadata({ "product_id": "" }, false),
    Json::object({ "product_id": Json::null() }),
  )
}

///|
test "two products share one company project without cross-product task leakage" {
  let native = [
    product_work_test_row("PT-book", "shared-project", "moonbook", true),
    product_work_test_row("PT-desk", "shared-project", "moondesk", true),
    product_work_test_row("PT-unassigned", "shared-project", Json::null(), true),
    product_work_test_row("PT-book-second", "second-project", "moonbook", true),
  ]
  let book = project_plan_select_task_items(
    [],
    native,
    [],
    None,
    None,
    Some("moonbook"),
  )
  assert_eq(book.length(), 2)
  assert_eq(json_text(book[0], "taskGuid", ""), "PT-book")
  assert_eq(json_text(book[1], "projGuid", ""), "second-project")
  let shared_book = project_plan_select_task_items(
    [],
    native,
    [],
    Some("shared-project"),
    None,
    Some("moonbook"),
  )
  assert_eq(shared_book.length(), 1)
  assert_eq(json_text(shared_book[0], "taskGuid", ""), "PT-book")
  let shared = project_plan_select_task_items(
    [],
    native,
    [],
    Some("shared-project"),
    None,
    None,
  )
  assert_eq(shared.length(), 3)
  assert_eq(plan_task_product_public(shared[2]), Json::null())
  assert_eq(
    project_plan_select_task_items(
      [],
      native,
      [],
      None,
      None,
      Some("unknown-valid-product"),
    ).length(),
    0,
  )
}

///|
test "imported tasks use explicit metadata and legacy ID project fallbacks with no name inference" {
  let raw : Array[SourceRow] = [
    {
      record_id: "row-book",
      source_id: "fixture:raw-book",
      payload: {
        "task_guid": "legacy-book",
        "task_id": "ignored-task",
        "proj_guid": "shared-project",
        "project_id": "ignored-project",
        "product_id": "moonbook",
        "task_type": "key_node",
      },
    },
    {
      record_id: "row-fallback",
      source_id: "fixture:raw-fallback",
      payload: {
        "task_id": "legacy-fallback",
        "project_id": "shared-project",
        "task_name": "MoonBook work",
      },
    },
    {
      record_id: "row-bare",
      source_id: "fixture:raw-bare",
      payload: { "project_id": "shared-project", "product_id": Json::null() },
    },
  ]
  let tagged = project_plan_select_task_items(
    raw,
    [],
    [],
    Some("shared-project"),
    Some("key_node"),
    Some("moonbook"),
  )
  assert_eq(tagged.length(), 1)
  assert_eq(json_text(tagged[0], "taskGuid", ""), "legacy-book")
  let project = project_plan_select_task_items(
    raw,
    [],
    [],
    Some("shared-project"),
    None,
    None,
  )
  assert_eq(project.length(), 3)
  assert_eq(json_text(project[1], "taskGuid", ""), "legacy-fallback")
  assert_eq(plan_task_product_public(project[1]), Json::null())
  assert_eq(json_text(project[2], "taskGuid", ""), "row-bare")
}

///|
test "complete native and imported product history survives more than 500 unrelated and relevant tasks" {
  let native : Array[SourceRow] = []
  let imported : Array[SourceRow] = []
  for index in 0..<600 {
    native.push(
      product_work_test_row(
        "A-native-" + index.to_string(),
        "unrelated",
        "other",
        true,
      ),
    )
    imported.push(
      product_work_test_row(
        "A-imported-" + index.to_string(),
        "unrelated",
        Json::null(),
        false,
      ),
    )
  }
  for index in 0..<601 {
    native.push(
      product_work_test_row(
        "Z-native-" + index.to_string(),
        "shared-project",
        "moonbook",
        true,
      ),
    )
    imported.push(
      product_work_test_row(
        "Z-imported-" + index.to_string(),
        "shared-project",
        Json::null(),
        false,
      ),
    )
  }
  assert_eq(
    project_plan_select_task_items(
      imported,
      native,
      [],
      Some("shared-project"),
      None,
      None,
    ).length(),
    1202,
  )
  assert_eq(
    project_plan_select_task_items(
      imported,
      native,
      [],
      None,
      None,
      Some("moonbook"),
    ).length(),
    601,
  )
  assert_eq(
    project_plan_select_task_items(
      imported,
      [],
      [],
      Some("shared-project"),
      None,
      None,
    ).length(),
    601,
  )
}

///|
test "native SQL selects latest revision before deleted project type and product filtering without pagination" {
  let sql = plan_task_projection_sql(
    false,
    Some("shared-project"),
    Some("key_node"),
    Some("moonbook"),
    None,
  )
  let latest = sql.find(") latest").unwrap()
  assert_true(sql.find("'state'").unwrap() > latest)
  assert_true(sql.find("'project_id'").unwrap() > latest)
  assert_true(sql.find("'task_type'").unwrap() > latest)
  assert_true(sql.find("'product_id'").unwrap() > latest)
  assert_true(sql.contains("ORDER BY aggregate_id, revision DESC"))
  assert_false(sql.contains("LIMIT"))
  assert_true(
    sql.contains(
      "min(created_at) OVER (PARTITION BY aggregate_id) AS first_created_at",
    ),
  )
  assert_true(sql.contains("to_char(first_created_at"))
  assert_false(
    plan_task_projection_sql(true, None, None, None, None).contains("'deleted'"),
  )
  let exact = plan_task_projection_sql(false, None, None, None, Some("PT-601"))
  assert_true(
    exact.find("aggregate_id = 'PT-601'").unwrap() <
    exact.find(") latest").unwrap(),
  )
}

///|
test "imported SQL filters projected task and project identities before any bound" {
  let sql = project_plan_source_task_sql(
    Some("shared-project"),
    Some("key_node"),
    Some("moonbook"),
    Some("late-task"),
  )
  for
    key in [
      "'proj_guid'", "'project_id'", "'task_type'", "'product_id'", "'task_guid'",
      "'task_id'",
    ] {
    assert_true(sql.contains(key))
  }
  assert_true(sql.contains("ELSE record_id END"))
  assert_true(sql.contains("record_type = 'legacy/raw/jd_task'"))
  assert_true(sql.contains("= 'shared-project'"))
  assert_true(sql.contains("= 'late-task'"))
  assert_false(sql.contains("LIMIT"))
  assert_true(
    project_plan_source_task_sql(Some("quote'escaped"), None, None, None).contains(
      "'quote''escaped'",
    ),
  )
}

///|
test "task scope rejects malformed filters but does not need catalog admission" {
  project_plan_validate_task_scope(None, None, Some("missing-catalog-entry"))
  for invalid in ["", "contains spaces", "a/b"] {
    assert_true(
      (Ok(project_plan_validate_task_scope(None, None, Some(invalid))) catch {
        e => Err(e)
      })
      is Err(_),
    )
    assert_true(
      (Ok(project_plan_validate_task_scope(Some(invalid), None, None)) catch {
        e => Err(e)
      })
      is Err(_),
    )
    assert_true(
      (Ok(project_plan_validate_task_scope(None, Some(invalid), None)) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}

///|
test "report attribution comes from exact task snapshot and rejects client retagging" {
  let body = product_work_report_body()
  let request = delivery_task_report_request(body, "signed-actor", {
    "product_id": "moonbook",
  })
  assert_eq(json_text(request, "product_id", ""), "moonbook")
  assert_eq(json_text(request, "actor_id", ""), "signed-actor")
  assert_eq(json_text(request, "state", ""), "observed")
  assert_eq(
    json_field(
      delivery_task_report_request(body, "signed-actor", {}),
      "product_id",
    ),
    None,
  )
}

///|
test "report retry preserves original product snapshot after retag and still compares submitted fields" {
  let body = product_work_report_body()
  let stored = delivery_task_report_request(body, "signed-actor", {
    "product_id": "moonbook",
  })
  let replay = delivery_task_report_request(body, "signed-actor", stored)
  let after_retag = delivery_task_report_request(body, "signed-actor", {
    "product_id": "moondesk",
  })
  assert_eq(replay, stored)
  assert_false(json_equal(after_retag, stored))
  let changed_body = match body {
    Object(fields) => {
      let copy = fields.copy()
      copy.set("summary", "Changed consequential content")
      Json::object(copy)
    }
    _ => body
  }
  assert_false(
    json_equal(
      delivery_task_report_request(changed_body, "signed-actor", stored),
      stored,
    ),
  )
  assert_false(
    json_equal(
      delivery_task_report_request(body, "different-actor", stored),
      stored,
    ),
  )
  let legacy = delivery_task_report_request(body, "signed-actor", {})
  assert_eq(delivery_task_report_request(body, "signed-actor", legacy), legacy)
  assert_eq(json_field(legacy, "product_id"), None)
}

///|
test "create read report and JSON reload preserve product project and unaccepted run identity" {
  let execution = execution_test_record("completed")
  if execution is Object(fields) {
    fields.set("task_id", "PT-book")
    fields.set("receipt", {
      "session_id": "session-1",
      "command_id": "command-1",
      "status": "runtime-completed",
    })
  }
  let canonical = plan_task_with_product_metadata(
    {
      "task_id": "PT-book",
      "project_id": "shared-project",
      "task_name": "Actual work",
      "state": "in_progress",
      "execution_workspace": "/explicit/workspace",
      "execution": execution,
    },
    { "product_id": "moonbook" },
    true,
  )
  let reloaded = @json.parse(canonical.stringify())
  let task = project_plan_task_item(
    { record_id: "PT-book", source_id: "create-book", payload: reloaded, },
    true,
    [],
  )
  let report = delivery_task_report_request(
    product_work_report_body(),
    "signed-actor",
    reloaded,
  )
  let reloaded_report = @json.parse(report.stringify())
  let report_item = delivery_report_item(
    {
      record_id: "report-book",
      source_id: "report-book",
      payload: reloaded_report,
    },
    true,
  )
  let detail_report = project_plan_task_report_item(report_item, "PT-book", [])
  assert_eq(plan_task_product_public(task), Json::string("moonbook"))
  assert_eq(json_text(task, "projGuid", ""), "shared-project")
  assert_eq(json_text(task, "execution_workspace", ""), "/explicit/workspace")
  assert_eq(plan_task_product_public(detail_report), Json::string("moonbook"))
  assert_eq(
    json_field(detail_report, "evidence_ids"),
    Some(Json::array(["receipt-book"])),
  )
  let public_run = json_field(task, "execution").unwrap()
  assert_eq(json_text(public_run, "acceptance", ""), "pending")
  let retagged = plan_task_with_product_metadata(
    reloaded,
    { "product_id": "moondesk" },
    false,
  )
  assert_eq(
    json_field(retagged, "execution"),
    json_field(reloaded, "execution"),
  )
  assert_eq(plan_task_product_public(report_item), Json::string("moonbook"))
}

///|
test "old reports and tasks remain explicitly unassigned after projection and reload" {
  let task = project_plan_task_item(
    {
      record_id: "legacy",
      source_id: "legacy",
      payload: { "project_id": "shared-project", "task_name": "MoonBook" },
    },
    false,
    [],
  )
  let report = delivery_report_item(
    {
      record_id: "legacy-report",
      source_id: "legacy-report",
      payload: { "task_id": "legacy" },
    },
    false,
  )
  assert_eq(json_field(task, "product_id"), Some(Json::null()))
  assert_eq(json_field(report, "product_id"), Some(Json::null()))
  assert_eq(
    json_field(
      project_plan_task_report_item(report, "legacy", []),
      "product_id",
    ),
    Some(Json::null()),
  )
}

///|
test "scoped imported report SQL has no unrelated or relevant history cap" {
  let task = delivery_source_report_sql(None, Some("late-task"))
  let report = delivery_source_report_sql(Some("late-report"), None)
  assert_true(task.contains("'task_id'"))
  assert_true(task.contains("'task_guid'"))
  assert_true(report.contains("'report_guid'"))
  assert_true(report.contains("'report_id'"))
  assert_false(task.contains("LIMIT"))
  assert_false(report.contains("LIMIT"))
  assert_true(delivery_source_report_sql(None, None).contains("LIMIT 500"))
}

///|
async test "unfiltered task route preserves 200 envelope and explicitly explains missing scope" {
  let response = route("/api/company/tasks", "", 4, "fixture-actor")
  assert_eq(response.0, 200)
  assert_eq(json_field(response.1, "items"), Some(Json::array([])))
  assert_true(json_bool(response.1, "scope_required", false))
  assert_false(json_bool(response.1, "authorizing", true))
}

///|
test "scoped task envelope remains compatible and non-authorizing" {
  let response = project_plan_tasks_response([
    project_plan_task_item(
      product_work_test_row("PT-book", "shared-project", "moonbook", true),
      true,
      [],
    ),
  ])
  assert_eq(json_field(response, "data"), json_field(response, "items"))
  assert_true(json_bool(response, "success", false))
  assert_false(json_bool(response, "authorizing", true))
}

///|
test "retagged and deleted latest tasks cannot reappear in the old product read model" {
  let retagged = product_work_test_row(
    "retagged", "shared-project", "moondesk", true,
  )
  let deleted : SourceRow = {
    record_id: "deleted",
    source_id: "fixture:delete",
    payload: {
      "project_id": "shared-project",
      "product_id": "moonbook",
      "state": "deleted",
    },
  }
  assert_eq(
    project_plan_select_task_items(
      [],
      [retagged, deleted],
      [],
      None,
      None,
      Some("moonbook"),
    ).length(),
    0,
  )
  assert_eq(
    project_plan_select_task_items(
      [],
      [retagged, deleted],
      [],
      None,
      None,
      Some("moondesk"),
    ).length(),
    1,
  )
}

///|
test "product retag and stale run observations cannot replace the dispatched command or request bytes" {
  let task : Json = {
    "task_id": "PT-1",
    "product_id": "moonbook",
    "state": "in_progress",
    "execution": execution_test_record("completed"),
  }
  let retagged = plan_task_with_product_metadata(
    task,
    { "product_id": "moondesk" },
    false,
  )
  let current = json_field(retagged, "execution").unwrap()
  let run = plan_task_execution_merge(current, execution_test_record("queued"))
  assert_eq(run, current)
  assert_eq(json_text(run, "request_body", ""), "immutable serialized request")
  assert_eq(json_text(run, "run_id", ""), "run-1")
  assert_eq(json_text(run, "command_id", ""), "command-1")
  assert_eq(json_text(run, "session_id", ""), "session-1")
  assert_eq(plan_task_product_public(retagged), Json::string("moondesk"))
}

///|
test "SQL fixture selectors remain the actual scoped service query builders" {
  let queries : Json = {
    "book_native": Json::string(
      plan_task_projection_sql(false, None, None, Some("moonbook"), None),
    ),
    "shared_native": Json::string(
      plan_task_projection_sql(false, Some("shared-project"), None, None, None),
    ),
    "shared_book_native": Json::string(
      plan_task_projection_sql(
        false,
        Some("shared-project"),
        None,
        Some("moonbook"),
        None,
      ),
    ),
    "unknown_native": Json::string(
      plan_task_projection_sql(false, None, None, Some("unknown-product"), None),
    ),
    "shared_imported": Json::string(
      project_plan_source_task_sql(Some("shared-project"), None, None, None),
    ),
    "book_imported": Json::string(
      project_plan_source_task_sql(None, None, Some("moonbook"), None),
    ),
    "exact_imported": Json::string(
      project_plan_source_task_sql(None, None, None, Some("Z-imported-601")),
    ),
    "exact_report": Json::string(
      delivery_source_report_sql(Some("Z-report-601"), None),
    ),
  }
  assert_false(json_text(queries, "shared_native", "").contains("LIMIT"))
  if @env.get_env_var("MOONPROJ_EXPORT_PRODUCT_WORK_SQL") == Some("1") {
    println("PRODUCT_WORK_SQL=" + queries.stringify())
  }
}
