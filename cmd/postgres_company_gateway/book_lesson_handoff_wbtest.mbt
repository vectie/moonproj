///|
fn lesson_handoff_test_data() -> Json {
  let delivery : Json = {
    "kind": "native_execution",
    "run_id": "run-fixture",
    "command_id": "command-fixture",
  }
  let accepted : Json = {
    "action": "internal_acceptance",
    "actor_id": "fixture-reviewer",
    "event_id": "task-accept-event",
    "audit_id": "task-accept-event:audit",
    "audit_state": "available",
    "revision": 3,
    "report_id": "report-fixture",
    "delivery_source": delivery,
  }
  let reported : Json = {
    "action": "report",
    "actor_id": "fixture-author",
    "event_id": "report-event",
    "audit_id": "report-event:audit",
    "audit_state": "available",
    "revision": 1,
    "report_id": "report-fixture",
    "delivery_source": delivery,
  }
  {
    "task": {
      "taskGuid": "task-fixture",
      "projGuid": "project-fixture",
      "taskName": "Synthetic accepted task <&>",
      "status": "done",
      "revision": 3,
      "accepted_report_id": "report-fixture",
      "accepted_delivery_source": delivery,
      "source_context": {
        "reference": "fixture://source",
        "problem": "Synthetic local continuity test",
      },
    },
    "reports": [
      {
        "reportGuid": "report-fixture",
        "task_id": "task-fixture",
        "summary": "Synthetic local result, no customer or cash fact",
        "delivery_source": delivery,
        "evidence_ids": ["sha256:fixture"],
      },
    ],
    "commitment": {
      "task_id": "task-fixture",
      "receipts": [reported, accepted],
    },
  }
}

///|
test "lesson handoff is a byte-exact read-only accepted task and report projection" {
  let data = lesson_handoff_test_data()
  let handoff = book_lesson_handoff_projection(data)
  assert_eq(handoff, book_lesson_handoff_projection(data))
  assert_eq(
    native_text(handoff, "contract_version"),
    "moonproj.book-lesson-handoff.v1",
  )
  let task = native_field(handoff, "task")
  let report = native_field(handoff, "report")
  assert_eq(native_text(task, "record_id"), "task-fixture")
  assert_eq(native_text(task, "record_version"), "3")
  assert_eq(native_text(report, "record_id"), "report-fixture")
  assert_eq(native_text(report, "record_version"), "1")
  assert_eq(
    native_text(task, "record_digest"),
    "sha256:" +
    native_context_hash(
      @encoding/utf8.encode(native_text(handoff, "task_snapshot")),
    ),
  )
  assert_eq(native_field(handoff, "authorizing"), Json::boolean(false))
  assert_eq(native_text(handoff, "customer_acceptance"), "not_asserted")
}

///|
test "lesson handoff refuses unaccepted missing ambiguous and changed report bindings" {
  for field in ["status", "accepted_report_id", "accepted_delivery_source"] {
    let data = lesson_handoff_test_data()
    guard native_field(data, "task") is Object(task) else {
      raise fail("fixture")
    }
    task[field] = Json::null()
    assert_true(
      (try Ok(book_lesson_handoff_projection(data)) catch { e => Err(e) })
      is Err(_),
    )
  }
  for field in ["actor_id", "audit_id", "event_id", "audit_state", "revision"] {
    let data = lesson_handoff_test_data()
    guard native_field(native_field(data, "commitment"), "receipts")
      is Array(receipts) &&
      receipts[1] is Object(acceptance) else {
      raise fail("fixture")
    }
    acceptance[field] = Json::null()
    assert_true(
      (try Ok(book_lesson_handoff_projection(data)) catch { e => Err(e) })
      is Err(_),
    )
  }
  let data = lesson_handoff_test_data()
  guard native_field(data, "reports") is Array(reports) else {
    raise fail("fixture")
  }
  reports.push(reports[0])
  assert_true(
    (try Ok(book_lesson_handoff_projection(data)) catch { e => Err(e) })
    is Err(_),
  )
}

///|
test "lesson handoff route is exact and bounded" {
  assert_eq(
    book_lesson_handoff_task_id(
      "/api/company/tasks/task-fixture/lesson-handoff",
    ),
    Some("task-fixture"),
  )
  assert_eq(
    book_lesson_handoff_task_id(
      "/api/company/tasks/task-fixture/extra/lesson-handoff",
    ),
    None,
  )
  assert_eq(
    book_lesson_handoff_task_id("/api/company/tasks/task-fixture/desk-handoff"),
    None,
  )
}

///|
async test "serialized production lesson handoff fixture can be passed to Book" {
  if @env.get_env_var("MOONPROJ_LESSON_FIXTURE_OUTPUT") is Some(path) {
    @fs.write_file(
      path,
      book_lesson_handoff_projection(lesson_handoff_test_data()).stringify(
        indent=2,
      ),
      create_mode=CreateOrTruncate,
    )
  }
}
