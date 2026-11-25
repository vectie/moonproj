///|
fn continuation_test_report_body(source? : Json) -> Json {
  let body : Json = {
    "report_id": "report-1",
    "task_id": "T",
    "project_id": "P",
    "progress_pct": 100,
    "report_date": "2026-10-02",
    "summary": "Exact selected result",
    "evidence_ids": ["receipt-C1"],
  }
  match source {
    Some(value) => continuation_test_changed(body, "delivery_source", value)
    None => body
  }
}

///|
test "manual progress report stays independent of running C0 while explicit delivery requires completion" {
  let original_task = continuation_test_task()
  let execution = continuation_test_changed(
    json_field(original_task, "execution").unwrap(),
    "state",
    "running",
  )
  let task = continuation_test_changed(original_task, "execution", execution)
  let manual_body = continuation_test_changed(
    continuation_test_report_body(),
    "progress_pct",
    Json::number(25),
  )
  let manual = delivery_task_report_request(manual_body, "actor", task)
  assert_eq(json_int(manual, "progress_bps", 0), 2500)
  assert_eq(json_field(manual, "delivery_source"), None)
  assert_eq(json_field(manual, "delivery_source_snapshot"), None)
  assert_eq(delivery_task_report_request(manual_body, "actor", manual), manual)
  let explicit = continuation_test_changed(
    manual_body,
    "delivery_source",
    plan_task_original_source(execution),
  )
  try delivery_task_report_request(explicit, "actor", task) catch {
    _ => ()
  } noraise {
    _ =>
      assert_true(
        false,
        msg="explicit native delivery requires completed exact source",
      )
  }
  let selected = plan_task_continuation_apply(
    original_task,
    continuation_test_body(),
  )
  try delivery_task_report_request(manual_body, "actor", selected) catch {
    _ => ()
  } noraise {
    _ =>
      assert_true(
        false,
        msg="explicitly selected flow cannot bypass source binding",
      )
  }
}

///|
test "report pins explicit completed C1 snapshot and never the later same-session C2" {
  let task = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  let source = plan_task_delivery_source(task)
  let request = delivery_task_report_request(
    continuation_test_report_body(source~),
    "actor",
    task,
  )
  assert_eq(json_field(request, "delivery_source"), Some(source))
  let snapshot = json_field(request, "delivery_source_snapshot").unwrap()
  assert_eq(json_text(snapshot, "command_id", ""), "C1")
  assert_eq(json_text(snapshot, "summary", ""), "Exact C1 answer")
  assert_eq(json_field(snapshot, "request_body"), None)
  let c2 = continuation_test_changed(
    continuation_test_changed(
      continuation_test_changed(
        continuation_test_changed(
          continuation_test_observation(),
          "continuation_id",
          "K2",
        ),
        "client_turn_id",
        "U2",
      ),
      "command_id",
      "C2",
    ),
    "receipt",
    { "session_id": "S", "command_id": "C2", "status": "runtime-completed" },
  )
  let c2 = continuation_test_changed(c2, "artifact_refs", [])
  let later = plan_task_continuation_apply(
    task,
    continuation_test_body(observation=c2),
  )
  assert_eq(json_text(plan_task_delivery_source(later), "command_id", ""), "C2")
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(source~),
          "actor",
          later,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_eq(
    delivery_task_report_request(
      continuation_test_report_body(source~),
      "actor",
      request,
    ),
    request,
  )
  assert_eq(
    json_text(
      json_field(request, "delivery_source_snapshot").unwrap(),
      "command_id",
      "",
    ),
    "C1",
  )
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(source=plan_task_delivery_source(later)),
          "actor",
          request,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "report rejects omitted forged nonselected source and accepted task" {
  let task = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(),
          "actor",
          task,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let forged = continuation_test_changed(
    plan_task_delivery_source(task),
    "command_id",
    "C2",
  )
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(source=forged),
          "actor",
          task,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let source = plan_task_delivery_source(task)
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(source~),
          "actor",
          continuation_test_changed(task, "state", "done"),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let not_selected = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(select=false),
  )
  assert_true(
    (try
      Ok(
        delivery_task_report_request(
          continuation_test_report_body(source~),
          "actor",
          not_selected,
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "new original report snapshots C0 and historical legacy report replays remain compatible" {
  let task = continuation_test_task()
  let source = plan_task_original_source(json_field(task, "execution").unwrap())
  let request = delivery_task_report_request(
    continuation_test_report_body(source~),
    "actor",
    task,
  )
  assert_eq(
    json_field(request, "delivery_source"),
    Some(plan_task_original_source(json_field(task, "execution").unwrap())),
  )
  assert_eq(
    delivery_task_report_request(
      continuation_test_report_body(source~),
      "actor",
      request,
    ),
    request,
  )
  let legacy = delivery_task_report_request(
    continuation_test_report_body(),
    "actor",
    { "product_id": "moonbook" },
  )
  assert_eq(json_field(legacy, "delivery_source"), None)
  assert_eq(
    delivery_task_report_request(
      continuation_test_report_body(),
      "actor",
      legacy,
    ),
    legacy,
  )
  let report = delivery_report_item(
    { record_id: "report-1", source_id: "fixture", payload: request, },
    true,
  )
  assert_eq(
    json_field(report, "delivery_source"),
    json_field(request, "delivery_source"),
  )
  assert_eq(
    json_field(report, "delivery_source_snapshot"),
    json_field(request, "delivery_source_snapshot"),
  )
  let projected = project_plan_task_report_item(report, "T", [])
  assert_eq(
    json_field(projected, "delivery_source"),
    json_field(request, "delivery_source"),
  )
}

///|
test "unaccepted original report can be followed by separate selected C1 report" {
  let task = continuation_test_task()
  let original_report = delivery_task_report_request(
    continuation_test_report_body(
      source=plan_task_original_source(json_field(task, "execution").unwrap()),
    ),
    "actor",
    task,
  )
  let selected = plan_task_continuation_apply(task, continuation_test_body())
  let next_body = continuation_test_changed(
    continuation_test_report_body(source=plan_task_delivery_source(selected)),
    "report_id",
    "report-2",
  )
  let followup_report = delivery_task_report_request(
    next_body, "actor", selected,
  )
  assert_eq(json_text(original_report, "report_id", ""), "report-1")
  assert_eq(json_text(followup_report, "report_id", ""), "report-2")
  assert_eq(
    json_text(
      json_field(original_report, "delivery_source_snapshot").unwrap(),
      "command_id",
      "",
    ),
    "C0",
  )
  assert_eq(
    json_text(
      json_field(followup_report, "delivery_source_snapshot").unwrap(),
      "command_id",
      "",
    ),
    "C1",
  )
  assert_eq(
    delivery_task_report_request(
      continuation_test_report_body(
        source=plan_task_original_source(json_field(task, "execution").unwrap()),
      ),
      "actor",
      original_report,
    ),
    original_report,
  )
}

///|
test "Accept binds only the displayed persisted report and selected source with legacy compatibility" {
  let original = continuation_test_task()
  assert_eq(
    plan_task_acceptance_binding(original, { "status": "done" }, Json::null()),
    Json::object({}),
  )
  let explicitly_original = continuation_test_changed(
    original,
    "selected_delivery_source",
    plan_task_original_source(json_field(original, "execution").unwrap()),
  )
  assert_true(
    (try
      Ok(
        plan_task_acceptance_binding(
          explicitly_original,
          { "status": "done" },
          Json::null(),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let original_source = plan_task_delivery_source(explicitly_original)
  let original_report = delivery_task_report_request(
    continuation_test_report_body(source=original_source),
    "actor",
    explicitly_original,
  )
  let original_binding = plan_task_acceptance_binding(
    explicitly_original,
    {
      "status": "done",
      "report_id": "report-1",
      "delivery_source": original_source,
    },
    original_report,
  )
  assert_eq(
    json_field(original_binding, "accepted_delivery_source"),
    Some(original_source),
  )
  let task = plan_task_continuation_apply(original, continuation_test_body())
  let source = plan_task_delivery_source(task)
  let report = delivery_task_report_request(
    continuation_test_report_body(source~),
    "actor",
    task,
  )
  let body : Json = {
    "status": "done",
    "report_id": "report-1",
    "delivery_source": source,
  }
  let binding = plan_task_acceptance_binding(task, body, report)
  assert_eq(json_text(binding, "accepted_report_id", ""), "report-1")
  assert_eq(json_field(binding, "accepted_delivery_source"), Some(source))
  assert_true(
    (try Ok(plan_task_acceptance_binding(task, { "status": "done" }, report)) catch {
      e => Err(e)
    })
    is Err(_),
  )
  for
    (key, value) in (
      [
        ("report_id", "other-report"),
        ("task_id", "other-task"),
        ("project_id", "other-project"),
        (
          "delivery_source",
          { "type": "original", "original_run_id": "R", "command_id": "C0" },
        ),
      ] : Array[(String, Json)]) {
    assert_true(
      (try
        Ok(
          plan_task_acceptance_binding(
            task,
            body,
            continuation_test_changed(report, key, value),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let accepted = continuation_test_changed(
    continuation_test_changed(
      continuation_test_changed(task, "state", "done"),
      "accepted_report_id",
      "report-1",
    ),
    "accepted_delivery_source",
    source,
  )
  assert_eq(plan_task_acceptance_binding(accepted, body, report), binding)
  let changed = continuation_test_changed(task, "selected_delivery_source", {
    "type": "continuation",
    "continuation_id": "K2",
    "original_run_id": "R",
    "command_id": "C2",
  })
  assert_true(
    (try Ok(plan_task_acceptance_binding(changed, body, report)) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let request : Json = {
    "changes": {
      "status": "done",
      "accepted_report_id": "report-1",
      "accepted_delivery_source": source,
    },
  }
  let sql = plan_task_acceptance_atomic_sql(
    "T", 4, "moonproj:command:accept-1", request, "SELECT 1;",
  )
  assert_true(sql.contains(") = 4 AND NOT EXISTS"))
  assert_true(sql.contains("aggregate_type=''task_report''"))
  assert_true(sql.contains("payload->''delivery_source''="))
  assert_true(sql.contains("NOT IN (''done'', ''deleted'')"))
  assert_eq(
    plan_task_acceptance_atomic_sql(
      "T",
      4,
      "moonproj:command:legacy",
      { "changes": { "status": "done" } },
      "SELECT 1;",
    ),
    plan_task_atomic_command_sql("T", 4, "moonproj:command:legacy", "SELECT 1;"),
  )
  ignore(plan_task_applied_command(Some({ "request": request }), request))
  assert_true(
    (try Ok(plan_task_applied_command(None, request)) catch { e => Err(e) })
    is Err(_),
  )
}
