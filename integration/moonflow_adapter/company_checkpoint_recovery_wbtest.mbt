///|
fn checkpoint_change(
  value : Json,
  key : String,
  replacement : Json,
) -> Json raise {
  let fields = json_object(value, "checkpoint object").copy()
  fields[key] = replacement
  Json::object(fields)
}

///|
async test "saved report schema and binding corruption reject both recovery paths without receipt writes" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  ignore(bind_company_task(root, request_ref))
  ignore(execute(root, request_ref, result_ref))
  let envelope = prepare_company_task_report(
    root,
    request_ref,
    result_ref,
    "first",
    "2026-10-04",
    "Summary",
    [],
  )
  let body = company_field(envelope, "report_body")
  let base = company_report_base(flow, "first")
  write_test_text(
    root,
    "good-response.json",
    company_report_response(envelope, false).stringify(),
  )
  let mutations : Array[Json] = [
    Json::null(),
    Json::array([]),
    Json::object({}),
  ]
  for
    (key, value) in [
      ("contract_id", "unsupported".to_json()),
      (
        "binding",
        checkpoint_change(
          company_field(envelope, "binding"),
          "task_id",
          "other".to_json(),
        ),
      ),
      ("request_ref", "other-request.json".to_json()),
      ("result_ref", "other-result.json".to_json()),
      ("result_digest", "sha256:changed".to_json()),
      ("output_digest", "sha256:changed".to_json()),
      ("method", "PUT".to_json()),
      ("path", "/api/company/plan/tasks/other/report".to_json()),
      ("idempotency_key", "other-report".to_json()),
      ("evidence", Json::array([])),
      ("task_acceptance", "accepted".to_json()),
    ] {
    mutations.push(checkpoint_change(envelope, key, value))
  }
  for
    (key, value) in [
      ("task_id", "other".to_json()),
      ("project_id", "other".to_json()),
      ("report_id", "other".to_json()),
      ("report_date", "not-a-date".to_json()),
      ("summary", "".to_json()),
      ("progress_pct", Json::number(0.5)),
      ("progress_pct", Json::number(4294967296.0)),
      ("evidence_ids", Json::array([])),
    ] {
    mutations.push(
      checkpoint_change(
        envelope,
        "report_body",
        checkpoint_change(body, key, value),
      ),
    )
  }
  for corrupted in mutations {
    write_test_text(root, base + "/report.json", corrupted.stringify())
    try company_task_report_status(root, request_ref, "first") catch {
      _ => ()
    } noraise {
      _ => fail("corrupt checkpoint returned actionable status")
    }
    try
      record_company_task_report_receipt(
        root, request_ref, "first", "good-response.json",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("corrupt checkpoint recorded receipt")
    }
    assert_false(@fs.exists(scoped_path(root, base + "/receipt.json")))
  }
  write_test_text(root, base + "/report.json", envelope.stringify())
  let second_base = company_report_base(flow, "second")
  write_test_text(root, second_base + "/report.json", envelope.stringify())
  try company_task_report_status(root, request_ref, "second") catch {
    _ => ()
  } noraise {
    _ => fail("copied checkpoint must not change report key")
  }
  assert_eq(
    company_text(
      company_task_report_status(root, request_ref, "first"),
      "state",
    ),
    "pending_report",
  )
}

///|
async test "changed valid evidence or result bytes block recovery without recording or executing" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  ignore(bind_company_task(root, request_ref))
  ignore(execute(root, request_ref, result_ref))
  write_test_text(
    root,
    "review.json",
    ({ "review": "original" } : Json).stringify(),
  )
  let envelope = prepare_company_task_report(
    root,
    request_ref,
    result_ref,
    "first",
    "2026-10-04",
    "Summary",
    ["review.json"],
  )
  write_test_text(
    root,
    "good-response.json",
    company_report_response(envelope, false).stringify(),
  )
  for reference in ["review.json", result_ref, artifact_ref(flow)] {
    let original = read_text_ref(root, reference)
    let changed = checkpoint_change(
      @json.parse(original),
      "changed",
      Json::boolean(true),
    )
    write_test_text(root, reference, changed.stringify())
    try company_task_report_status(root, request_ref, "first") catch {
      _ => ()
    } noraise {
      _ => fail("changed bytes returned actionable status")
    }
    try
      record_company_task_report_receipt(
        root, request_ref, "first", "good-response.json",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("changed bytes recorded receipt")
    }
    assert_false(
      @fs.exists(
        scoped_path(root, company_report_base(flow, "first") + "/receipt.json"),
      ),
    )
    write_test_text(root, reference, original)
  }
  assert_eq(
    company_text(
      company_task_report_status(root, request_ref, "first"),
      "state",
    ),
    "pending_report",
  )
  let status = record_company_task_report_receipt(
    root, request_ref, "first", "good-response.json",
  )
  assert_eq(company_text(status, "state"), "reported")
}

///|
async test "incomplete command shape and wrong revision never persist report receipts" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  ignore(bind_company_task(root, request_ref))
  ignore(execute(root, request_ref, result_ref))
  let envelope = prepare_company_task_report(
    root,
    request_ref,
    result_ref,
    "first",
    "2026-10-04",
    "Summary",
    [],
  )
  let response = company_report_response(envelope, false)
  let command = company_field(response, "command")
  let mutations : Array[Json] = []
  for
    key in [
      "kind", "command_family", "family", "command_type", "aggregate_type", "aggregate_id",
      "idempotency_key", "actor_id", "request", "result",
    ] {
    let fields = json_object(command, "command").copy()
    fields.remove(key)
    mutations.push(Json::object(fields))
  }
  for
    key in [
      "aggregate_id", "revision", "state", "event_id", "audit_id", "actor_id", "delivery_effect",
      "cash_effect", "accounting_effect", "tax_effect",
    ] {
    let result = json_object(company_field(command, "result"), "result").copy()
    result.remove(key)
    mutations.push(checkpoint_change(command, "result", Json::object(result)))
  }
  for
    revision in [
      Json::null(),
      Json::number(0),
      Json::number(2),
      Json::number(1.5),
      "1".to_json(),
    ] {
    mutations.push(
      checkpoint_change(
        command,
        "result",
        checkpoint_change(
          company_field(command, "result"),
          "revision",
          revision,
        ),
      ),
    )
  }
  for invalid in mutations {
    write_test_text(
      root,
      "bad-response.json",
      ({ "command": invalid } : Json).stringify(),
    )
    try
      record_company_task_report_receipt(
        root, request_ref, "first", "bad-response.json",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("incomplete command recorded receipt")
    }
    assert_false(
      @fs.exists(
        scoped_path(root, company_report_base(flow, "first") + "/receipt.json"),
      ),
    )
  }
  write_test_text(root, "good-response.json", response.stringify())
  ignore(
    record_company_task_report_receipt(
      root, request_ref, "first", "good-response.json",
    ),
  )
  let result = json_object(company_field(command, "result"), "result").copy()
  result.remove("revision")
  write_test_text(
    root,
    company_report_base(flow, "first") + "/receipt.json",
    checkpoint_change(command, "result", Json::object(result)).stringify(),
  )
  try company_task_report_status(root, request_ref, "first") catch {
    _ => ()
  } noraise {
    _ => fail("incomplete persisted receipt returned reported status")
  }
}
