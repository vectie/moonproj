///|
async test "actual Desk gateway candidate crosses service attachment report and Accept unchanged when configured" {
  let directory = @env.get_env_var("MOONPROJ_CONTINUATION_FIXTURE_OUTPUT").unwrap_or(
    "",
  )
  if directory.is_empty() {
    return
  }
  let exported = @json.parse(
    @fs.read_file(directory + "/gateway-candidate.json").text(),
  )
  let public_task = json_field(exported, "task").unwrap()
  let candidate = json_field(exported, "candidate").unwrap()
  let original = json_field(public_task, "execution").unwrap()
  let task : Json = {
    "task_id": json_text(public_task, "taskGuid", ""),
    "project_id": json_text(public_task, "projGuid", ""),
    "created_by": "actor",
    "state": "in_progress",
    "product_id": "moonbook",
    "execution": original,
    "__delivery_task_revision": 7,
  }
  let body = continuation_test_body(observation=candidate)
  let request = plan_task_continuation_request(task, body, "actor")
  let attached = plan_task_continuation_apply(task, body)
  assert_eq(plan_task_continuation_apply(attached, body), attached)
  assert_eq(json_field(attached, "execution"), Some(original))
  assert_eq(plan_task_continuations(attached), [
    plan_task_continuation_public(candidate),
  ])
  let source = plan_task_delivery_source(attached)
  let report_body = continuation_test_changed(
    continuation_test_changed(
      continuation_test_report_body(source~),
      "summary",
      json_field(candidate, "summary").unwrap(),
    ),
    "evidence_ids",
    json_field(candidate, "evidence_ids").unwrap(),
  )
  let report = delivery_task_report_request(report_body, "actor", attached)
  let snapshot = json_field(report, "delivery_source_snapshot").unwrap()
  assert_eq(snapshot, plan_task_continuation_public(candidate))
  assert_eq(json_field(snapshot, "input"), json_field(candidate, "input"))
  assert_eq(json_field(snapshot, "receipt"), json_field(candidate, "receipt"))
  let accepted = plan_task_acceptance_binding(
    attached,
    { "report_id": "report-1", "delivery_source": source },
    report,
  )
  assert_eq(json_field(accepted, "accepted_delivery_source"), Some(source))
  let receipt : Json = { "request": request }
  ignore(
    plan_task_applied_command(
      Some(receipt),
      plan_task_continuation_request(attached, body, "actor"),
    ),
  )
  let result : Json = {
    "task_id": json_text(task, "task_id", ""),
    "attached_source": source,
    "report": report,
    "acceptance_binding": accepted,
    "canonical_observe_bytes": @encoding/utf8.encode(body.stringify()).length(),
    "original_preserved": true,
    "native_io": "injected",
    "provider_called": false,
    "persistence": "pure DTO boundary; separate PostgreSQL fixture validates SQL",
  }
  @fs.write_file(
    directory + "/service-attached-report.json",
    result.stringify(),
    create_mode=CreateOrTruncate,
  )
}
