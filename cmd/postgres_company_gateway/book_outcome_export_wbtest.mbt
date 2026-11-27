///|
fn outcome_export_test_gap() -> Json {
  {
    "present": false,
    "severity": 0,
    "summary": "The author observed no gap within this synthetic internal task review.",
    "evidence_refs": ["task-fixture", "report-fixture"],
  }
}

///|
fn outcome_export_test_draft() -> Json {
  {
    "outcome_summary": "The internal report met its stated local criterion. No customer response or cash is asserted.",
    "observed_at": 1791176400,
    "recorded_at": 1791176401,
    "owner_route": "https://proj.example.test/apps/proj/?page=dispatch&task=task-fixture",
    "information_gap": outcome_export_test_gap(),
    "recognition_gap": outcome_export_test_gap(),
    "decisiveness_gap": outcome_export_test_gap(),
    "capability": Json::null(),
  }
}

///|
fn outcome_export_test_changed(
  value : Json,
  key : String,
  replacement : Json,
) -> Json {
  match value {
    Object(fields) => {
      let changed = fields.copy()
      changed[key] = replacement
      Json::object(changed)
    }
    _ => value
  }
}

///|
fn outcome_export_test_complete_draft() -> Json {
  let gap : Json = {
    "present": true,
    "severity": 2,
    "summary": "The author found a missing comparison in the synthetic result.",
    "evidence_refs": ["report-fixture"],
  }
  let descriptor : Json = {
    "id": "fixture.actual-comparison-method",
    "version": "2",
    "summary": "Proposed comparison-method correction, not activated.",
    "change_text": "Retain the comparison against the named original criterion.\n",
  }
  outcome_export_test_changed(
    outcome_export_test_changed(
      outcome_export_test_draft(),
      "information_gap",
      gap,
    ),
    "capability",
    descriptor,
  )
}

///|
test "accepted task outcome exports complete no-change bytes without invented capability metadata" {
  let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
  let draft = outcome_export_test_draft()
  let result = book_outcome_export_projection(handoff, draft)
  assert_eq(native_field(result, "handoff"), handoff)
  assert_eq(native_field(result, "draft"), draft)
  let submission = native_field(result, "submission")
  assert_eq(
    native_text(submission, "contract_version"),
    "moonbook.bookkeeper.product_outcome_submission.v1",
  )
  assert_eq(native_text(submission, "source_product"), "moonproj")
  assert_eq(
    native_text(submission, "owner_route"),
    native_text(draft, "owner_route"),
  )
  assert_eq(
    native_text(submission, "outcome_summary"),
    native_text(draft, "outcome_summary"),
  )
  guard submission is Object(fields) else { raise fail("submission object") }
  for
    key in [
      "capability_id", "capability_version", "capability_change_digest", "capability_summary",
    ] {
    assert_eq(fields.get(key), None)
  }
  guard native_field(submission, "evidence_refs") is Array(evidence) else {
    raise fail("evidence")
  }
  assert_eq(evidence.length(), 2)
  for index, key in ["task", "report"] {
    let reference = native_field(handoff, key)
    assert_eq(
      native_text(evidence[index], "reference_id"),
      native_text(reference, "record_id"),
    )
    assert_eq(
      native_text(evidence[index], "reference_version"),
      native_text(reference, "record_version"),
    )
    assert_eq(
      native_text(evidence[index], "digest"),
      native_text(reference, "record_digest"),
    )
  }
  assert_eq(@json.parse(native_text(result, "submission_json")), submission)
  assert_eq(@json.parse(native_text(result, "handoff_json")), handoff)
  assert_eq(
    @json.parse(native_text(result, "evidence_json")),
    native_field(result, "evidence_bundle"),
  )
  let retained = native_field(result, "evidence_bundle")
  assert_eq(native_field(retained, "draft"), draft)
  assert_eq(native_field(retained, "handoff"), handoff)
  let reference = native_field(submission, "submission")
  assert_eq(
    native_text(reference, "record_digest"),
    "sha256:" +
    native_context_hash(
      @encoding/utf8.encode(native_text(retained, "digest_basis")),
    ),
  )
  assert_eq(
    native_text(submission, "decision_evidence_id"),
    native_text(native_field(handoff, "task"), "record_id"),
  )
  assert_eq(result, book_outcome_export_projection(handoff, draft))
}

///|
test "outcome export rejects missing unknown false-default and invented evidence inputs" {
  let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
  let draft = outcome_export_test_draft()
  for
    key in [
      "outcome_summary", "observed_at", "recorded_at", "information_gap", "recognition_gap",
      "decisiveness_gap",
    ] {
    assert_true(
      (Ok(
        book_outcome_export_projection(
          handoff,
          outcome_export_test_changed(draft, key, Json::null()),
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for
    (key, value) in [
      ("present", Json::null()),
      ("present", Json::string("unknown")),
      ("severity", Json::number(1)),
      ("summary", Json::string("  ")),
      ("evidence_refs", Json::array([])),
      ("evidence_refs", ToJson::to_json(["foreign"])),
      ("evidence_refs", ToJson::to_json(["task-fixture", "task-fixture"])),
    ] {
    let gap = outcome_export_test_changed(outcome_export_test_gap(), key, value)
    assert_true(
      (Ok(
        book_outcome_export_projection(
          handoff,
          outcome_export_test_changed(draft, "information_gap", gap),
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  assert_true(
    (Ok(
      book_outcome_export_projection(
        handoff,
        outcome_export_test_changed(draft, "recorded_at", Json::number(1)),
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(
      book_outcome_export_projection(
        handoff,
        outcome_export_test_changed(draft, "observed_at", Json::number(1.5)),
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "a present gap requires an explicit complete change descriptor and hashes its retained text" {
  let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
  let gap : Json = {
    "present": true,
    "severity": 2,
    "summary": "The author found a missing comparison in the synthetic result.",
    "evidence_refs": ["report-fixture"],
  }
  let draft = outcome_export_test_changed(
    outcome_export_test_draft(),
    "information_gap",
    gap,
  )
  assert_true(
    (Ok(book_outcome_export_projection(handoff, draft)) catch { e => Err(e) })
    is Err(_),
  )
  let descriptor : Json = {
    "id": "fixture.actual-comparison-method",
    "version": "2",
    "summary": "Proposed comparison-method correction, not activated.",
    "change_text": "Retain the comparison against the named original criterion.\n",
  }
  let complete = outcome_export_test_changed(draft, "capability", descriptor)
  let result = book_outcome_export_projection(handoff, complete)
  let submission = native_field(result, "submission")
  assert_eq(
    native_text(submission, "capability_id"),
    "fixture.actual-comparison-method",
  )
  assert_eq(
    native_text(submission, "capability_change_digest"),
    "sha256:" +
    native_context_hash(
      @encoding/utf8.encode(native_text(descriptor, "change_text")),
    ),
  )
  for key in ["id", "version", "summary", "change_text"] {
    let broken = outcome_export_test_changed(descriptor, key, Json::null())
    assert_true(
      (Ok(
        book_outcome_export_projection(
          handoff,
          outcome_export_test_changed(draft, "capability", broken),
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let changed = book_outcome_export_projection(
    handoff,
    outcome_export_test_changed(
      complete,
      "outcome_summary",
      Json::string("A new observation with different content."),
    ),
  )
  assert_true(
    native_field(native_field(changed, "submission"), "submission") !=
    native_field(submission, "submission"),
  )
}

///|
async test "production outcome exporter serializes authored inputs for actual Book import" {
  if @env.get_env_var("MOONPROJ_OUTCOME_EXPORT_FIXTURE") is Some(path) {
    let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
    let result = book_outcome_export_projection(
      handoff,
      outcome_export_test_draft(),
    )
    @fs.write_file(
      path,
      result.stringify(indent=2),
      create_mode=CreateOrTruncate,
    )
    let complete = book_outcome_export_projection(
      handoff,
      outcome_export_test_complete_draft(),
    )
    @fs.write_file(
      path + ".complete.json",
      complete.stringify(indent=2),
      create_mode=CreateOrTruncate,
    )
  }
}

///|
test "outcome export is bounded and exact route matching cannot select another endpoint" {
  assert_eq(
    book_outcome_export_task_id(
      "/api/company/tasks/task-fixture/outcome-export",
    ),
    Some("task-fixture"),
  )
  for
    path in [
      "/api/company/tasks/task-fixture/outcome-export/", "/api/company/tasks/task-fixture/extra/outcome-export",
      "/api/company/tasks/../outcome-export", "/api/company/tasks/task-fixture/lesson-handoff",
    ] {
    assert_eq(book_outcome_export_task_id(path), None)
  }
  let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
  assert_true(
    (Ok(
      book_outcome_export_projection(
        handoff,
        outcome_export_test_changed(
          outcome_export_test_draft(),
          "root",
          Json::string("/foreign"),
        ),
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(
      book_outcome_export_projection(
        handoff,
        outcome_export_test_changed(
          outcome_export_test_draft(),
          "outcome_summary",
          Json::string("界".repeat(3000)),
        ),
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(
      book_outcome_export_projection(
        outcome_export_test_changed(
          handoff,
          "task_snapshot",
          Json::string(native_text(handoff, "task_snapshot") + " "),
        ),
        outcome_export_test_draft(),
      ),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "exported display route preserves a mount and strips credential query fragment hazards" {
  let handoff = book_lesson_handoff_projection(lesson_handoff_test_data())
  let draft = outcome_export_test_draft()
  let route = native_text(draft, "owner_route")
  assert_eq(outcome_export_owner_route(draft, "task-fixture"), route)
  for
    bad in [
      "javascript:alert(1)",
      "https://user:password@proj.example.test/apps/proj/?page=dispatch&task=task-fixture",
      "https://proj.example.test/apps/proj/?page=dispatch&task=other-task",
      "https://proj.example.test/apps/proj/?token=secret&page=dispatch&task=task-fixture",
      route + "#fragment",
      route + "&extra=1",
      "https://proj.example.test\\foreign/apps/proj/?page=dispatch&task=task-fixture",
    ] {
    assert_true(
      (Ok(
        book_outcome_export_projection(
          handoff,
          outcome_export_test_changed(draft, "owner_route", Json::string(bad)),
        ),
      ) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  let other = outcome_export_test_changed(
    draft,
    "owner_route",
    Json::string(
      "https://proj.example.test/another-mount/?page=dispatch&task=task-fixture",
    ),
  )
  assert_true(
    native_field(
      native_field(book_outcome_export_projection(handoff, draft), "submission"),
      "submission",
    ) !=
    native_field(
      native_field(book_outcome_export_projection(handoff, other), "submission"),
      "submission",
    ),
  )
}
