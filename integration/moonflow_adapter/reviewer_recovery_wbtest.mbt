///|
async test "reviewer rejects null saved report checkpoint" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  ignore(bind_company_task(root, request_ref))
  ignore(execute(root, request_ref, result_ref))
  ignore(
    prepare_company_task_report(
      root,
      request_ref,
      result_ref,
      "first",
      "2026-10-04",
      "Summary",
      [],
    ),
  )
  write_test_text(
    root,
    company_report_base(flow, "first") + "/report.json",
    "null",
  )
  try company_task_report_status(root, request_ref, "first") catch {
    _ => ()
  } noraise {
    status =>
      fail("null report checkpoint returned success: " + status.stringify())
  }
}

///|
async test "reviewer rejects report checkpoint belonging to another task" {
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
  let fields = json_object(envelope, "envelope").copy()
  let body = json_object(company_field(envelope, "report_body"), "body").copy()
  body["task_id"] = "PT-other-company-task".to_json()
  fields["report_body"] = Json::object(body)
  let changed = Json::object(fields)
  write_test_text(
    root,
    company_report_base(flow, "first") + "/report.json",
    changed.stringify(),
  )
  write_test_text(
    root,
    "other-task-response.json",
    company_report_response(changed, false).stringify(),
  )
  try
    record_company_task_report_receipt(
      root, request_ref, "first", "other-task-response.json",
    )
  catch {
    _ => ()
  } noraise {
    status =>
      fail(
        "mismatched checkpoint settled different task: " + status.stringify(),
      )
  }
}

///|
async test "reviewer rejects incomplete report command revision" {
  let (root, request_ref, result_ref, _) = company_delivery_fixture()
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
  let command = json_object(company_field(response, "command"), "command").copy()
  let result = json_object(
    company_field(Json::object(command), "result"),
    "result",
  ).copy()
  result.remove("revision")
  command["result"] = Json::object(result)
  write_test_text(
    root,
    "incomplete-response.json",
    ({ "command": Json::object(command) } : Json).stringify(),
  )
  try
    record_company_task_report_receipt(
      root, request_ref, "first", "incomplete-response.json",
    )
  catch {
    _ => ()
  } noraise {
    status => fail("missing revision settled report: " + status.stringify())
  }
}
