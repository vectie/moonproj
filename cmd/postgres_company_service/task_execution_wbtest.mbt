///|
fn execution_test_record(state : String) -> Json {
  {
    "task_id": "PT-1",
    "run_id": "run-1",
    "session_id": "session-1",
    "command_id": "command-1",
    "state": state,
    "summary": "",
    "evidence_ids": [],
    "output_urls": [],
    "artifact_refs": [],
    "request_body": "immutable serialized request",
  }
}

///|
test "product context observations only change availability and public summary never leaks captured text" {
  let context : Json = {
    "schema": "moonproj.product-context.v1",
    "product_id": "moonproj",
    "product_name": "MoonProj",
    "coverage": "complete",
    "issues": [],
    "context_path": ".moonsuite/products/moonproj/execution-context/hash/context.md",
    "sha256": "captured-hash",
    "size_bytes": 32000,
    "text": "PRIVATE FULL TASK PHILOSOPHY AND PRD",
    "provenance": { "captured_private": "PRIVATE PROVENANCE" },
    "prd": {
      "document_id": "prd",
      "coverage": "complete",
      "source_sha256": "source-hash",
      "text": "PRIVATE NESTED SOURCE TEXT",
    },
  }
  let current = execution_test_record("running")
  if current is Object(fields) {
    fields.set("product_context", context)
    fields.set("product_context_artifact", { "state": "available", "error": "" })
  }
  let observation = execution_test_record("running")
  if observation is Object(fields) {
    fields.set("product_context", {
      "text": "REPLACEMENT",
      "product_id": "moonbook",
    })
    fields.set("request_body", Json::string("REPLACEMENT REQUEST"))
    fields.set("product_context_artifact", {
      "state": "missing",
      "error": "Input no longer present",
      "text": "UNTRUSTED OBSERVATION",
    })
  }
  let next = plan_task_execution_merge(current, observation)
  assert_eq(json_field(next, "product_context"), Some(context))
  assert_eq(json_text(next, "request_body", ""), "immutable serialized request")
  let public = plan_task_execution_public({
    "execution": next,
    "state": "in_progress",
  })
  let summary = json_field(public, "product_context").unwrap_or(Json::null())
  assert_eq(json_text(summary, "product_id", ""), "moonproj")
  assert_eq(json_text(summary, "coverage", ""), "complete")
  assert_eq(json_text(summary, "artifact_state", ""), "missing")
  assert_eq(json_field(summary, "text"), None)
  assert_eq(json_field(summary, "provenance"), None)
  assert_false(public.stringify().contains("PRIVATE"))
  assert_false(public.stringify().contains("UNTRUSTED"))
  assert_eq(
    json_field(
      plan_task_execution_public({
        "execution": execution_test_record("queued"),
      }),
      "product_context",
    ),
    Some(Json::null()),
  )
}

///|
test "task execution read model retains identity and keeps human acceptance separate" {
  let task : Json = {
    "state": "in_progress",
    "execution": execution_test_record("completed"),
  }
  let public = plan_task_execution_public(task)
  assert_eq(json_text(public, "state", ""), "completed")
  assert_eq(json_text(public, "acceptance", ""), "pending")
  assert_eq(json_field(public, "request_body"), None)
  assert_eq(
    json_text(
      plan_task_execution_public({
        "state": "done",
        "execution": execution_test_record("completed"),
      }),
      "acceptance",
      "",
    ),
    "accepted",
  )
}

///|
test "task execution rejects cross-command result and terminal state regression" {
  let current = execution_test_record("completed")
  let stale = execution_test_record("queued")
  assert_eq(plan_task_execution_merge(current, stale), current)
  let foreign : Json = {
    "task_id": "PT-1",
    "run_id": "run-1",
    "session_id": "session-1",
    "command_id": "wrong-command",
    "state": "completed",
  }
  assert_true(
    (try Ok(plan_task_execution_merge(current, foreign)) catch { e => Err(e) })
    is Err(_),
  )
}

///|
test "task execution terminal refresh enriches late artifacts without changing request bytes" {
  let current = execution_test_record("completed")
  let observation : Json = {
    "task_id": "PT-1",
    "run_id": "run-1",
    "session_id": "session-1",
    "command_id": "command-1",
    "state": "completed",
    "summary": "Done",
    "artifact_refs": [{ "path": "results/review.md" }],
    "evidence_ids": ["receipt-1", "artifact-2"],
  }
  let next = plan_task_execution_merge(current, observation)
  assert_eq(json_text(next, "request_body", ""), "immutable serialized request")
  assert_eq(json_text(next, "summary", ""), "Done")
  assert_eq(
    json_field(next, "artifact_refs"),
    Some(Json::array([{ "path": "results/review.md" }])),
  )
}

///|
test "task execution internal routes are exact" {
  assert_eq(
    plan_task_execution_route(
      "/api/company/internal/plan/tasks/PT-1/execution/reserve",
    ),
    Some(("PT-1", "reserve")),
  )
  assert_eq(
    plan_task_execution_route("/api/company/plan/tasks/PT-1/execution/reserve"),
    None,
  )
  assert_eq(
    plan_task_execution_route(
      "/api/company/internal/plan/tasks/PT-1/extra/execution/reserve",
    ),
    None,
  )
}

///|
test "late repeated Start acknowledgement cannot regress a running command" {
  let current = execution_test_record("running")
  assert_eq(
    plan_task_execution_merge(current, execution_test_record("queued")),
    current,
  )
}

///|
test "native planning task projection retains workspace execution and acceptance" {
  let payload : Json = {
    "task_id": "PT-1",
    "project_id": "project-1",
    "task_name": "Review",
    "state": "in_progress",
    "execution_workspace": "/selected/book",
    "execution_model": "",
    "execution": execution_test_record("completed"),
  }
  let row : SourceRow = { record_id: "PT-1", source_id: "create-1", payload, }
  let item = project_plan_task_item(row, true, [])
  assert_eq(json_text(item, "execution_workspace", ""), "/selected/book")
  let run = json_field(item, "execution").unwrap_or(Json::null())
  assert_eq(json_text(run, "task_id", ""), "PT-1")
  assert_eq(json_text(run, "state", ""), "completed")
  assert_eq(json_text(run, "acceptance", ""), "pending")
}

///|
test "out-of-order terminal polls cannot erase later output evidence or summary" {
  let enriched : Json = {
    "task_id": "PT-1",
    "run_id": "run-1",
    "session_id": "session-1",
    "command_id": "command-1",
    "state": "completed",
    "summary": "Actual answer",
    "artifact_refs": [
      {
        "path": "finding.txt",
        "command_id": "command-1",
        "evidence_id": "event-late",
      },
    ],
    "evidence_ids": ["receipt-1", "event-late"],
  }
  let result = plan_task_execution_merge(
    enriched,
    execution_test_record("completed"),
  )
  assert_eq(
    json_field(result, "artifact_refs"),
    json_field(enriched, "artifact_refs"),
  )
  assert_eq(
    json_field(result, "evidence_ids"),
    json_field(enriched, "evidence_ids"),
  )
  assert_eq(json_text(result, "summary", ""), "Actual answer")
}

///|
test "task update and Accept SQL guard the originally validated revision under the lock" {
  for expected in [1, 2, 3] {
    let sql = plan_task_atomic_command_sql(
      "PT-1", expected, "moonproj:command:accept-1", "INSERT INTO observed VALUES ('accepted');",
    )
    assert_true(
      sql.contains(
        "LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE",
      ),
    )
    assert_true(
      sql.contains("LOCK TABLE company_record IN SHARE ROW EXCLUSIVE MODE"),
    )
    assert_true(sql.contains("SELECT max(revision)"))
    assert_true(sql.contains(") = " + expected.to_string() + " AND NOT EXISTS"))
    assert_true(sql.contains("THEN INSERT INTO observed"))
    assert_true(sql.contains("END IF; END;"))
  }
  // Revision 1 is the validated task; reserve=2 and observe=3 cannot match it.
  let stale = plan_task_atomic_command_sql(
    "PT-1", 1, "moonproj:command:update-1", "SELECT 1;",
  )
  assert_true(stale.contains(") = 1 AND NOT EXISTS"))
  assert_false(stale.contains(") = 2 AND NOT EXISTS"))
  assert_false(stale.contains(") = 3 AND NOT EXISTS"))
}

///|
test "exact native report query filters the task before global pagination" {
  let sql = delivery_projection_sql("task_report", false, Some("PT-601"), None)
  let task_filter = sql.find("coalesce(payload->>'task_id'").unwrap()
  let limit = sql.find("LIMIT 500").unwrap()
  assert_true(task_filter < limit)
  assert_true(sql.contains("= 'PT-601'"))
  let exact = delivery_projection_sql(
    "task_report",
    false,
    None,
    Some("REPORT-601"),
  )
  assert_true(
    exact.find("aggregate_id = 'REPORT-601'").unwrap() <
    exact.find("LIMIT 500").unwrap(),
  )
}

///|
test "native report 601 survives unrelated report history and retains evidence" {
  let rows : Array[SourceRow] = []
  for index in 0..<600 {
    rows.push({
      record_id: "report-" + index.to_string(),
      source_id: "source-" + index.to_string(),
      payload: {
        "task_id": "unrelated",
        "summary": "Other result",
        "state": "observed",
      },
    })
  }
  rows.push({
    record_id: "report-601",
    source_id: "native-source",
    payload: {
      "task_id": "PT-601",
      "summary": "Exact result",
      "state": "observed",
      "evidence_ids": ["native-receipt-601"],
    },
  })
  let selected = delivery_select_task_reports(rows, true, None, Some("PT-601"))
  assert_eq(selected.length(), 1)
  assert_eq(json_text(selected[0], "report_id", ""), "report-601")
  assert_eq(
    json_field(selected[0], "evidence_ids"),
    Some(Json::array(["native-receipt-601"])),
  )
}

///|
test "stale task update or Accept never acknowledges an unapplied command" {
  let update : Json = {
    "command_type": "update",
    "task_id": "PT-1",
    "changes": { "status": "done" },
  }
  assert_true(
    (try Ok(plan_task_applied_command(None, update)) catch { e => Err(e) })
    is Err(_),
  )
  assert_true(
    (try
      Ok(
        plan_task_applied_command(
          Some({ "request": { "command_type": "dispatch" } }),
          update,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let applied : Json = {
    "request": update,
    "result": { "task_id": "PT-1", "state": "done", "revision": 4 },
  }
  assert_eq(plan_task_applied_command(Some(applied), update), applied)
}
