///|
fn continuation_test_task(state? : String = "in_progress") -> Json {
  {
    "task_id": "T",
    "project_id": "P",
    "created_by": "actor",
    "state": state,
    "product_id": "moonbook",
    "__delivery_task_revision": 4,
    "execution": {
      "run_id": "R",
      "task_id": "T",
      "session_id": "S",
      "command_id": "C0",
      "workspace": "/book",
      "model": "native/model",
      "state": "completed",
      "request_body": "C0 EXACT PRIVATE BYTES\n",
      "summary": "Original answer",
      "receipt": {
        "session_id": "S",
        "command_id": "C0",
        "status": "runtime-completed",
      },
      "evidence_ids": ["receipt-C0"],
    },
  }
}

///|
fn continuation_test_observation(state? : String = "completed") -> Json {
  {
    "continuation_id": "K",
    "original_run_id": "R",
    "task_id": "T",
    "session_id": "S",
    "original_command_id": "C0",
    "prior_result_command_id": "C0",
    "command_id": "C1",
    "client_turn_id": "U",
    "workspace": "/book",
    "model": "native/model",
    "input": {
      "path": ".moonsuite/products/moonproj/human-continuations/K/input.md",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
    "state": state,
    "summary": if state == "completed" {
      "Exact C1 answer"
    } else {
      ""
    },
    "error": "",
    "receipt": {
      "session_id": "S",
      "command_id": "C1",
      "status": if state == "completed" {
        "runtime-completed"
      } else {
        "runtime-claimed"
      },
    },
    "evidence_ids": ["receipt-C1"],
    "output_urls": [],
    "artifact_refs": [
      { "path": "answer.md", "command_id": "C1", "evidence_id": "event-C1" },
    ],
  }
}

///|
fn continuation_test_body(observation? : Json, select? : Bool = true) -> Json {
  {
    "continuation": observation.unwrap_or(continuation_test_observation()),
    "select_for_delivery": select,
    "authority": {
      "active": true,
      "principal_id": "principal",
      "actor_id": "actor",
      "capability": "project:task:update",
      "scope": "project:P",
    },
  }
}

///|
fn continuation_test_changed(value : Json, key : String, item : Json) -> Json {
  let fields = match value {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields.set(key, item)
  Json::object(fields)
}

///|
test "continuation attachment preserves every original execution byte and reads sibling identity" {
  let task = continuation_test_task()
  let next = plan_task_continuation_apply(task, continuation_test_body())
  assert_eq(json_field(next, "execution"), json_field(task, "execution"))
  assert_eq(json_text(next, "state", ""), "in_progress")
  assert_eq(plan_task_continuations(next).length(), 1)
  assert_eq(
    plan_task_delivery_source(next),
    plan_task_continuation_source(continuation_test_observation()),
  )
  let public = project_plan_task_item(
    { record_id: "T", source_id: "fixture", payload: next, },
    true,
    [],
  )
  assert_eq(
    json_field(public, "continuations"),
    Some(plan_task_continuations_public(next)),
  )
  assert_false(public.stringify().contains("PRIVATE"))
  assert_eq(
    json_text(json_field(public, "execution").unwrap(), "command_id", ""),
    "C0",
  )
}

///|
test "completed failed or cancelled original permits separate completed follow-up" {
  for state in ["completed", "failed", "cancelled"] {
    let task = continuation_test_task()
    let original = continuation_test_changed(
      json_field(task, "execution").unwrap(),
      "state",
      Json::string(state),
    )
    let task = continuation_test_changed(task, "execution", original)
    let next = plan_task_continuation_apply(task, continuation_test_body())
    assert_eq(json_field(next, "execution"), Some(original))
    assert_eq(
      json_text(
        plan_task_completed_source(next, plan_task_delivery_source(next)),
        "command_id",
        "",
      ),
      "C1",
    )
  }
}

///|
test "continuations reject every cross-original lineage coordinate and forged evidence" {
  let task = continuation_test_task()
  for
    key in [
      "original_run_id", "task_id", "session_id", "original_command_id", "workspace",
    ] {
    assert_true(
      (try
        Ok(
          plan_task_continuation_apply(
            task,
            continuation_test_body(
              observation=continuation_test_changed(
                continuation_test_observation(),
                key,
                "other",
              ),
            ),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for
    (key, value) in (
      [
        (
          "receipt",
          {
            "session_id": "S",
            "command_id": "C2",
            "status": "runtime-completed",
          },
        ),
        (
          "receipt",
          {
            "session_id": "other",
            "command_id": "C1",
            "status": "runtime-completed",
          },
        ),
        ("artifact_refs", [{ "path": "other.md", "command_id": "C2" }]),
        (
          "input",
          {
            "path": "../input.md",
            "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          },
        ),
        ("input", { "path": "input.md", "sha256": "wrong" }),
      ] : Array[(String, Json)]) {
    assert_true(
      (try
        Ok(
          plan_task_continuation_apply(
            task,
            continuation_test_body(
              observation=continuation_test_changed(
                continuation_test_observation(),
                key,
                value,
              ),
            ),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}

///|
test "continuation identity and input cannot be retargeted on later observation" {
  let first = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  for
    key in ["command_id", "client_turn_id", "prior_result_command_id", "model"] {
    assert_true(
      (try
        Ok(
          plan_task_continuation_apply(
            first,
            continuation_test_body(
              observation=continuation_test_changed(
                continuation_test_observation(),
                key,
                "different",
              ),
            ),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let input : Json = {
    "path": "different/input.md",
    "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  }
  assert_true(
    (try
      Ok(
        plan_task_continuation_apply(
          first,
          continuation_test_body(
            observation=continuation_test_changed(
              continuation_test_observation(),
              "input",
              input,
            ),
          ),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  for key in ["continuation_id", "client_turn_id"] {
    let duplicate = continuation_test_changed(
      continuation_test_observation(),
      key,
      "K2",
    )
    assert_true(
      (try
        Ok(
          plan_task_continuation_apply(
            first,
            continuation_test_body(observation=duplicate),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}

///|
test "attach and select are structurally idempotent and native evidence enriches only C1" {
  let task = continuation_test_task()
  let first = plan_task_continuation_apply(task, continuation_test_body())
  assert_eq(
    plan_task_continuation_apply(first, continuation_test_body()),
    first,
  )
  let enriched = continuation_test_changed(
    continuation_test_observation(),
    "evidence_ids",
    ["receipt-C1", "late-C1"],
  )
  let second = plan_task_continuation_apply(
    first,
    continuation_test_body(observation=enriched, select=false),
  )
  assert_eq(plan_task_delivery_source(second), plan_task_delivery_source(first))
  assert_eq(
    json_field(plan_task_continuations(second)[0], "evidence_ids"),
    Some(Json::array(["receipt-C1", "late-C1"])),
  )
  assert_eq(
    plan_task_continuation_apply(
      second,
      continuation_test_body(
        observation=continuation_test_observation(state="queued"),
        select=false,
      ),
    ),
    second,
  )
  assert_eq(json_field(second, "execution"), json_field(task, "execution"))
}

///|
test "pending failed cancelled and control settled receipts never select or submit" {
  for
    state in [
      "queued", "running", "waiting_approval", "interrupted", "failed", "cancelled",
    ] {
    let body = continuation_test_body(
      observation=continuation_test_observation(state~),
      select=false,
    )
    let attached = plan_task_continuation_apply(continuation_test_task(), body)
    assert_eq(plan_task_continuations(attached).length(), 1)
    assert_eq(plan_task_delivery_source(attached), Json::null())
    assert_true(
      (try
        Ok(
          plan_task_continuation_apply(
            attached,
            continuation_test_changed(body, "select_for_delivery", true),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
    assert_true(
      (try
        Ok(
          plan_task_completed_source(
            attached,
            plan_task_continuation_source(continuation_test_observation()),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let control = continuation_test_changed(
    continuation_test_observation(),
    "receipt",
    { "session_id": "S", "command_id": "C1", "status": "control-settled" },
  )
  assert_true(
    (try
      Ok(
        plan_task_continuation_apply(
          continuation_test_task(),
          continuation_test_body(observation=control),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "accepted tasks are inspection-only with every original and sibling field unchanged" {
  let selected = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  let accepted = continuation_test_changed(selected, "state", "done")
  assert_eq(
    plan_task_continuation_apply(accepted, continuation_test_body()),
    accepted,
  )
  let response = plan_task_continuation_response(accepted, false)
  assert_true(json_bool(response, "inspection_only", false))
  assert_eq(json_text(response, "acceptance", ""), "accepted")
  assert_eq(
    json_field(response, "selected_delivery_source"),
    json_field(accepted, "selected_delivery_source"),
  )
}

///|
test "continuation authority retains creator signed actor capability and project scope" {
  let task = continuation_test_task()
  let body = continuation_test_body()
  ignore(plan_task_continuation_request(task, body, "actor"))
  assert_true(
    (try Ok(plan_task_continuation_request(task, body, "intruder")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  for
    (key, value) in (
      [
        ("active", false),
        ("principal_id", ""),
        ("actor_id", "intruder"),
        ("capability", "project:task:create"),
        ("scope", "project:other"),
      ] : Array[(String, Json)]) {
    let authority = continuation_test_changed(
      json_field(body, "authority").unwrap(),
      key,
      value,
    )
    assert_true(
      (try
        Ok(
          plan_task_continuation_request(
            task,
            continuation_test_changed(body, "authority", authority),
            "actor",
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}

///|
test "idempotent request excludes mutable native observations but includes exact lineage selection and authority" {
  let task = continuation_test_task()
  let first = plan_task_continuation_request(
    task,
    continuation_test_body(select=false),
    "actor",
  )
  let refreshed = plan_task_continuation_request(
    task,
    continuation_test_body(
      observation=continuation_test_observation(state="queued"),
      select=false,
    ),
    "actor",
  )
  assert_eq(first, refreshed)
  assert_false(
    json_equal(
      first,
      plan_task_continuation_request(task, continuation_test_body(), "actor"),
    ),
  )
  let receipt : Json = { "request": first }
  ignore(plan_task_applied_command(Some(receipt), refreshed))
  assert_true(
    (try Ok(plan_task_applied_command(None, refreshed)) catch { e => Err(e) })
    is Err(_),
  )
}

///|
test "durable attach acknowledgement remains C1 while current selection may already be C2" {
  let original = continuation_test_task()
  let request = plan_task_continuation_request(
    original,
    continuation_test_body(),
    "actor",
  )
  let current = continuation_test_changed(
    original,
    "selected_delivery_source",
    {
      "type": "continuation",
      "continuation_id": "K2",
      "original_run_id": "R",
      "command_id": "C2",
    },
  )
  ignore(plan_task_applied_command(Some({ "request": request }), request))
  let response = plan_task_continuation_operation_response(
    current, true, "attach-K", request, true, 8,
  )
  assert_eq(
    json_text(
      json_field(response, "operation_source").unwrap(),
      "command_id",
      "",
    ),
    "C1",
  )
  assert_eq(
    json_text(
      json_field(response, "selected_delivery_source").unwrap(),
      "command_id",
      "",
    ),
    "C2",
  )
  assert_true(json_bool(response, "operation_applied", false))
  assert_eq(json_text(response, "operation_idempotency_key", ""), "attach-K")
  assert_eq(json_int(json_field(response, "task").unwrap(), "revision", 0), 8)
  let rejected = plan_task_continuation_operation_response(
    continuation_test_task(state="done"),
    false,
    "attach-K",
    request,
    false,
    9,
  )
  assert_false(json_bool(rejected, "operation_applied", true))
  assert_true(json_bool(rejected, "inspection_only", false))
}

///|
test "explicit original selection restores C0 without altering C1 or its immutable capture" {
  let first = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  let source = plan_task_original_source(
    json_field(first, "execution").unwrap(),
  )
  let body = continuation_test_changed(
    continuation_test_changed(
      continuation_test_body(),
      "continuation",
      Json::null(),
    ),
    "selected_delivery_source",
    source,
  )
  ignore(plan_task_continuation_request(first, body, "actor"))
  let second = plan_task_continuation_apply(first, body)
  assert_eq(plan_task_delivery_source(second), source)
  assert_eq(plan_task_continuations(second), plan_task_continuations(first))
  assert_eq(json_field(second, "execution"), json_field(first, "execution"))
}

///|
test "continuation internal route is exact and persistence SQL checks acceptance under revision lock" {
  assert_eq(
    plan_task_continuation_route(
      "/api/company/internal/plan/tasks/T/continuations/observe",
    ),
    Some("T"),
  )
  for
    path in [
      "/api/company/plan/tasks/T/continuations/observe", "/api/company/internal/plan/tasks/T/continuations",
      "/api/company/internal/plan/tasks/T/continuations/observe/extra",
    ] {
    assert_eq(plan_task_continuation_route(path), None)
  }
  let task = continuation_test_task()
  let body = continuation_test_body()
  let sql = plan_task_continuation_sql(
    "T",
    4,
    plan_task_continuation_apply(task, body),
    plan_task_continuation_request(task, body, "actor"),
    "actor",
    "attach-K",
  )
  assert_true(
    sql.contains(
      "LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE",
    ),
  )
  assert_true(
    sql.contains("LOCK TABLE company_record IN SHARE ROW EXCLUSIVE MODE"),
  )
  assert_true(sql.contains(") = 4 AND NOT EXISTS"))
  assert_true(sql.contains("NOT IN (''done'', ''deleted'')"))
  assert_true(sql.contains("INSERT INTO company_audit_event") == false)
  assert_true(sql.contains("company_audit_event"))
}

///|
test "export exact continuation persistence SQL for socket-free PostgreSQL fixture" {
  let task = continuation_test_changed(
    continuation_test_task(),
    "__delivery_task_revision",
    1,
  )
  let body = continuation_test_body()
  let next = plan_task_continuation_apply(task, body)
  let request = plan_task_continuation_request(task, body, "actor")
  let attach = plan_task_continuation_sql(
    "T", 1, next, request, "actor", "attach-K",
  )
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
  let body2 = continuation_test_body(observation=c2)
  let next2 = plan_task_continuation_apply(next, body2)
  let select2 = plan_task_continuation_sql(
    "T",
    2,
    next2,
    plan_task_continuation_request(next, body2, "actor"),
    "actor",
    "attach-K2",
  )
  let report = delivery_task_report_request(
    continuation_test_report_body(source=plan_task_delivery_source(next)),
    "actor",
    continuation_test_changed(next, "__delivery_task_revision", 2),
  )
  let report_sql = "INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('task_report','report-1',1," +
    @postgres.sql_literal(report.stringify()) +
    "::jsonb,'report-1');"
  let report2 = delivery_task_report_request(
    continuation_test_changed(
      continuation_test_report_body(source=plan_task_delivery_source(next2)),
      "report_id",
      "report-2",
    ),
    "actor",
    continuation_test_changed(next2, "__delivery_task_revision", 3),
  )
  let accept_body : Json = {
    "status": "done",
    "report_id": "report-2",
    "delivery_source": plan_task_delivery_source(next2),
  }
  let binding = plan_task_acceptance_binding(next2, accept_body, report2)
  let acceptance : Json = { "changes": binding }
  let accepted_payload = continuation_test_changed(
    continuation_test_changed(
      continuation_test_changed(next2, "state", "done"),
      "accepted_report_id",
      "report-2",
    ),
    "accepted_delivery_source",
    plan_task_delivery_source(next2),
  )
  let accept_command : Json = {
    "request": acceptance,
    "result": { "state": "done" },
  }
  let accept_sql = "INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('plan_task','T',4," +
    @postgres.sql_literal(accepted_payload.stringify()) +
    "::jsonb,'accepted'); INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command','accept-2',4," +
    @postgres.sql_literal(accept_command.stringify()) +
    "::jsonb,'moonproj:command:accept-2');"
  let queries : Json = {
    "task": task,
    "next": next,
    "attach": attach,
    "select2": select2,
    "stale": plan_task_continuation_sql(
      "T", 2, next, request, "actor", "stale-K",
    ),
    "accepted": plan_task_continuation_sql(
      "T", 4, next, request, "actor", "accepted-K",
    ),
    "report": delivery_task_source_atomic_sql(
      report, "moonproj:command:report-1", report_sql,
    ),
    "stale_report": delivery_task_source_atomic_sql(
      continuation_test_changed(report, "report_id", "report-stale"),
      "moonproj:command:report-stale",
      "INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('task_report','report-stale',1,'{}'::jsonb,'report-stale');",
    ),
    "duplicate_report": delivery_task_source_atomic_sql(
      continuation_test_changed(report, "delivery_source_revision", 3),
      "moonproj:command:duplicate-report",
      "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command','duplicate-report',4,'{}'::jsonb,'moonproj:command:duplicate-report');",
    ),
    "report2": delivery_task_source_atomic_sql(
      report2,
      "moonproj:command:report-2",
      "INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('task_report','report-2',1," +
      @postgres.sql_literal(report2.stringify()) +
      "::jsonb,'report-2');",
    ),
    "accept_exact": plan_task_acceptance_atomic_sql(
      "T", 3, "moonproj:command:accept-2", acceptance, accept_sql,
    ),
    "accept_stale": plan_task_acceptance_atomic_sql(
      "T", 2, "moonproj:command:accept-stale", acceptance, "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command','accept-stale',4,'{}'::jsonb,'moonproj:command:accept-stale');",
    ),
    "accept_wrong_report": plan_task_acceptance_atomic_sql(
      "T",
      3,
      "moonproj:command:accept-wrong",
      {
        "changes": {
          "accepted_report_id": "report-1",
          "accepted_delivery_source": plan_task_delivery_source(next2),
        },
      },
      "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command','accept-wrong',4,'{}'::jsonb,'moonproj:command:accept-wrong');",
    ),
  }
  if @env.get_env_var("MOONPROJ_EXPORT_CONTINUATION_SQL") == Some("1") {
    println("CONTINUATION_SQL=" + queries.stringify())
  }
}

///|
async test "canonical continuation body uses existing 128 KiB JSON reader boundary" {
  let normal = continuation_test_body().stringify()
  let normal_bytes = @encoding/utf8.encode(normal)
  let normal_reader = @io.MemoryReader(async fn(writer) {
    writer.write(normal_bytes)
  })
  assert_eq(read_json_body(normal_reader), continuation_test_body())
  let empty_summary = continuation_test_body(
    observation=continuation_test_changed(
      continuation_test_observation(),
      "summary",
      "",
    ),
  ).stringify()
  let room = 128 * 1024 - @encoding/utf8.encode(empty_summary).length()
  let at_limit = continuation_test_body(
    observation=continuation_test_changed(
      continuation_test_observation(),
      "summary",
      Json::string("x".repeat(room)),
    ),
  ).stringify()
  let exact_bytes = @encoding/utf8.encode(at_limit)
  assert_eq(exact_bytes.length(), 128 * 1024)
  let exact_reader = @io.MemoryReader(async fn(writer) {
    writer.write(exact_bytes)
  })
  ignore(read_json_body(exact_reader))
  let oversized = @encoding/utf8.encode(at_limit + " ")
  let oversized_reader = @io.MemoryReader(async fn(writer) {
    writer.write(oversized)
  })
  try read_json_body(oversized_reader) catch {
    error => assert_eq(service_error_response(error).0, 413)
  } noraise {
    _ => assert_true(false, msg="oversized canonical body must remain rejected")
  }
  if @env.get_env_var("MOONPROJ_EXPORT_CONTINUATION_SQL") == Some("1") {
    println(
      "CONTINUATION_BODY_BYTES=" +
      normal_bytes.length().to_string() +
      ";MAX=131072;ONE_BYTE_OVER=413",
    )
  }
}
