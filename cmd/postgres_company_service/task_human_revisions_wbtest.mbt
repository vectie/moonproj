///|
fn human_revision_service_fixture(id? : String = "H1") -> Json {
  {
    "schema": "moonproj.human-revision.v1",
    "capture_scope": "immutable_human_revision",
    "revision_id": id,
    "task_id": "T",
    "original_run_id": "R",
    "session_id": "S",
    "original_command_id": "C0",
    "workspace": "/book",
    "workspace_id": "desk-workspace",
    "author_type": "human",
    "state": "saved",
    "output": { "command_id": "C0", "path": "answer.md", "evidence_id": "E0" },
    "base": {
      "scope": "current_workspace_bytes_at_edit",
      "sha256": "a".repeat(64),
    },
    "content": {
      "path": ".moonsuite/products/moonproj/human-revisions/" +
      id +
      "/content.txt",
      "sha256": "b".repeat(64),
      "size_bytes": 18,
    },
    "created_at": "2026-10-05T00:00:00Z",
  }
}

///|
fn human_revision_service_body(revision? : Json, select? : Bool = true) -> Json {
  {
    "human_revision": revision.unwrap_or(human_revision_service_fixture()),
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
test "human revision explicit selection remains a sibling and preserves native execution and continuations" {
  let task = plan_task_continuation_apply(
    continuation_test_task(),
    continuation_test_body(),
  )
  let revision = human_revision_service_fixture()
  let body = human_revision_service_body()
  let request = plan_task_continuation_request(task, body, "actor")
  assert_eq(json_field(request, "human_revision"), Some(revision))
  let next = plan_task_continuation_apply(task, body)
  assert_eq(json_field(next, "execution"), json_field(task, "execution"))
  assert_eq(plan_task_continuations(next), plan_task_continuations(task))
  assert_eq(json_text(next, "state", ""), "in_progress")
  assert_eq(plan_task_human_revisions(next), [revision])
  let source = plan_task_human_revision_source(revision)
  assert_eq(plan_task_delivery_source(next), source)
  assert_eq(plan_task_completed_source(next, source), revision)
  for key in ["command_id", "receipt", "model", "run_id"] {
    assert_eq(json_field(revision, key), None)
  }
  let public = project_plan_task_item(
    { record_id: "T", source_id: "", payload: next, },
    true,
    [],
  )
  assert_eq(json_field(public, "human_revisions"), Some([revision].to_json()))
  assert_false(public.stringify().contains("PRIVATE"))
  let response = plan_task_continuation_operation_response(
    next, false, "human-select-1", request, true, 5,
  )
  assert_eq(json_field(response, "operation_source"), Some(source))
  assert_eq(json_field(response, "human_revisions"), Some([revision].to_json()))
}

///|
test "human revision return does not select without explicit action and idempotent replay cannot mutate capture" {
  let task = continuation_test_task()
  let observed = plan_task_continuation_apply(
    task,
    human_revision_service_body(select=false),
  )
  assert_true(plan_task_delivery_source(observed) is Null)
  let first = plan_task_continuation_apply(
    observed,
    human_revision_service_body(),
  )
  assert_eq(
    plan_task_continuation_apply(first, human_revision_service_body()),
    first,
  )
  let changed = continuation_test_changed(
    human_revision_service_fixture(),
    "created_at",
    "changed".to_json(),
  )
  try
    plan_task_continuation_apply(
      first,
      human_revision_service_body(revision=changed),
    )
  catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => raise fail("immutable revision changed")
  }
  let original_body : Json = {
    "selected_delivery_source": plan_task_original_source(
      json_field(task, "execution").unwrap(),
    ),
    "select_for_delivery": true,
    "authority": json_field(human_revision_service_body(), "authority").unwrap(),
  }
  let restored = plan_task_continuation_apply(first, original_body)
  assert_eq(
    plan_task_human_revisions(restored),
    plan_task_human_revisions(first),
  )
  assert_eq(
    json_text(plan_task_delivery_source(restored), "type", ""),
    "original",
  )
}

///|
test "human revision report pins immutable manifest while later selection and acceptance preserve report snapshot" {
  let h1 = human_revision_service_fixture()
  let selected = plan_task_continuation_apply(
    continuation_test_task(),
    human_revision_service_body(),
  )
  let source = plan_task_human_revision_source(h1)
  let report_body : Json = { "delivery_source": source }
  let metadata = delivery_task_source_metadata(report_body, selected)
  assert_eq(json_field(metadata, "delivery_source_snapshot"), Some(h1))
  let saved = continuation_test_changed(
    metadata,
    "command_type",
    "report".to_json(),
  )
  let changed_selection = plan_task_continuation_apply(
    selected,
    human_revision_service_body(
      revision=human_revision_service_fixture(id="H2"),
    ),
  )
  assert_eq(
    json_text(plan_task_delivery_source(changed_selection), "revision_id", ""),
    "H2",
  )
  assert_eq(delivery_task_source_metadata(report_body, saved), metadata)
  try
    delivery_task_source_metadata(
      { "delivery_source": plan_task_delivery_source(changed_selection) },
      saved,
    )
  catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => raise fail("report replay changed its immutable source")
  }
  let report : Json = {
    "report_id": "REPORT1",
    "task_id": "T",
    "project_id": "P",
    "delivery_source": source,
  }
  assert_eq(
    json_text(
      plan_task_acceptance_binding(
        selected,
        { "report_id": "REPORT1", "delivery_source": source },
        report,
      ),
      "accepted_report_id",
      "",
    ),
    "REPORT1",
  )
  try
    plan_task_acceptance_binding(
      changed_selection,
      { "report_id": "REPORT1", "delivery_source": source },
      report,
    )
  catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => raise fail("accept bound old report to new selection")
  }
  let done = continuation_test_changed(selected, "state", "done".to_json())
  assert_eq(
    plan_task_continuation_apply(
      done,
      human_revision_service_body(
        revision=human_revision_service_fixture(id="H2"),
      ),
    ),
    done,
  )
  try delivery_task_source_metadata(report_body, done) catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => raise fail("accepted work allowed a new report")
  }
}

///|
test "human revision service rejects cross task native forgery invalid bounds and ambiguous selection" {
  let task = continuation_test_task()
  let revision = human_revision_service_fixture()
  for
    (key, value) in [
      ("task_id", "wrong".to_json()),
      ("original_run_id", "wrong".to_json()),
      ("session_id", "wrong".to_json()),
      ("original_command_id", "wrong".to_json()),
      ("workspace", "/elsewhere".to_json()),
      ("revision_id", "../escape".to_json()),
      ("author_type", "model".to_json()),
      ("capture_scope", "workspace_replacement".to_json()),
      ("state", "completed".to_json()),
      ("receipt", { "status": "runtime-completed" }),
      ("model", "fake".to_json()),
      ("command_id", "C1".to_json()),
      (
        "content",
        {
          "path": ".moonsuite/products/moonproj/human-revisions/H1/content.txt",
          "sha256": "b".repeat(64),
          "size_bytes": 262145,
        },
      ),
      (
        "content",
        {
          "path": ".moonsuite/products/moonproj/human-revisions/H1/content.txt",
          "sha256": "b".repeat(64),
          "size_bytes": "18",
        },
      ),
    ] {
    try
      plan_task_human_revision_validate(
        task,
        continuation_test_changed(revision, key, value),
      )
    catch {
      _ => ()
    } noraise {
      _ => raise fail("invalid human revision accepted: " + key)
    }
  }
  try
    plan_task_continuation_request(task, human_revision_service_body(), "other")
  catch {
    error => assert_eq(service_error_response(error).0, 403)
  } noraise {
    _ => raise fail("noncreator changed source")
  }
  let ambiguous = continuation_test_changed(
    human_revision_service_body(),
    "continuation",
    continuation_test_observation(),
  )
  try plan_task_continuation_request(task, ambiguous, "actor") catch {
    error => assert_eq(service_error_response(error).0, 422)
  } noraise {
    _ => raise fail("ambiguous source accepted")
  }
}

///|
test "human revision report while native work is running never completes cancels or replaces that execution" {
  let task = continuation_test_task()
  let running = continuation_test_changed(
    json_field(task, "execution").unwrap(),
    "state",
    "running".to_json(),
  )
  let task = continuation_test_changed(task, "execution", running)
  let selected = plan_task_continuation_apply(
    task,
    human_revision_service_body(),
  )
  let source = plan_task_delivery_source(selected)
  let report_body : Json = { "delivery_source": source }
  let metadata = delivery_task_source_metadata(report_body, selected)
  assert_eq(json_field(selected, "execution"), Some(running))
  assert_eq(
    json_text(json_field(selected, "execution").unwrap(), "state", ""),
    "running",
  )
  let observation = continuation_test_changed(
    running,
    "state",
    "completed".to_json(),
  )
  let completed = plan_task_execution_merge(running, observation)
  let later = continuation_test_changed(selected, "execution", completed)
  assert_eq(plan_task_delivery_source(later), source)
  assert_eq(
    plan_task_human_revisions(later),
    plan_task_human_revisions(selected),
  )
  assert_eq(delivery_task_source_metadata(report_body, later), metadata)
  let report : Json = {
    "report_id": "REPORT-RUNNING",
    "task_id": "T",
    "project_id": "P",
    "delivery_source": source,
  }
  let acceptance = plan_task_acceptance_binding(
    selected,
    { "report_id": "REPORT-RUNNING", "delivery_source": source },
    report,
  )
  assert_eq(json_text(acceptance, "accepted_report_id", ""), "REPORT-RUNNING")
  assert_eq(json_field(selected, "execution"), Some(running))
  assert_eq(json_field(acceptance, "execution"), None)
}
