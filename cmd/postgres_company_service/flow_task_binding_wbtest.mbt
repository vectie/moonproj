///|
fn flow_service_fixture() -> (Json, Json, Json) raise {
  let task : Json = {
    "task_id": "PT-revised",
    "project_id": "robotics-flow-001",
    "created_by": "owner-plan",
    "state": "pending",
    "source_kind": "command",
    "event_id": "plan_task:update:rev2",
    "task_name": "Revised plan",
  }
  let snapshot = @company_flow.snapshot(task, 2)
  let flow : Json = {
    "product_id": "moonproj",
    "operation": "moonproj/project.plan.prepare@0.1.0",
    "requested_authority": "workspace-mutation",
    "required_claim": "digital-artifact",
    "run_id": "r2",
    "request_id": "q2",
    "work_item_id": "w2",
    "declaration_id": "d2",
    "attempt_id": "a2",
    "book_id": "b2",
    "idempotency_key": "r2/w2/1",
    "input_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  }
  let binding = @company_flow.binding(
    snapshot, flow, "inputs/snapshot.json", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  let body : Json = {
    "binding": binding,
    "authority": {
      "active": true,
      "actor_id": "owner-plan",
      "principal_id": "p1",
      "capability": "project:task:update",
      "scope": "project:robotics-flow-001",
    },
  }
  (task, binding, body)
}

///|
test "fresh exact approved revision refuses stale snapshot wrong actor and inactive authority" {
  assert_eq(
    flow_approval_read_route(
      "/api/company/internal/plan/tasks/PT-revised/flow-approvals/approve-r2",
    ),
    Some(("PT-revised", "approve-r2")),
  )
  assert_true(
    flow_approval_read_route(
      "/api/company/internal/plan/tasks/../flow-approvals/key",
    )
    is None,
  )
  let (task, binding, body) = flow_service_fixture()
  let request = flow_binding_request(task, 2, body, "owner-plan")
  let command = flow_binding_command(request, "approve-r2")
  @company_flow.validate_approval(binding, command)
  for actor in ["other-owner", ""] {
    try flow_binding_request(task, 2, body, actor) catch {
      _ => ()
    } noraise {
      _ => raise fail("wrong signed actor")
    }
  }
  try flow_binding_request(task, 3, body, "owner-plan") catch {
    _ => ()
  } noraise {
    _ => raise fail("stale revision")
  }
  let inactive = @json.parse(
    body.stringify().replace_all(old="true", new="false"),
  )
  try flow_binding_request(task, 2, inactive, "owner-plan") catch {
    _ => ()
  } noraise {
    _ => raise fail("inactive grant")
  }
  let wrong_scope = @json.parse(
    body
    .stringify()
    .replace_all(old="project:robotics-flow-001", new="project:other"),
  )
  try flow_binding_request(task, 2, wrong_scope, "owner-plan") catch {
    _ => ()
  } noraise {
    _ => raise fail("wrong grant scope")
  }
  assert_eq(
    json_text(json_field(command, "result").unwrap(), "state", ""),
    "approved",
  )
  assert_eq(
    json_field(json_field(command, "result").unwrap(), "execution_effect"),
    Some(Json::boolean(false)),
  )
  let sql = flow_binding_atomic_sql(
    "PT-revised", 2, "moonproj:command:approve-r2", binding, "INSERT INTO receipt VALUES ('test');",
  )
  assert_true(sql.contains("LOCK TABLE company_record"))
  assert_true(
    sql.contains("payload->''request''->''binding''->>''attempt_id''=''a2''"),
  )
  assert_true(sql.contains("= 2 AND NOT EXISTS"))
}

///|
test "Flow report canonical request preserves approval on replay and refuses changed or stale returns" {
  let (task, binding, body) = flow_service_fixture()
  let approval = flow_binding_command(
    flow_binding_request(task, 2, body, "owner-plan"),
    "approve-r2",
  )
  let report : Json = {
    "report_id": "TR-flow",
    "task_id": "PT-revised",
    "project_id": "robotics-flow-001",
    "report_date": "2026-10-08",
    "summary": "Prepared plan",
    "progress_pct": 0,
    "evidence_ids": ["sha256:evidence"],
    "flow_binding": binding,
    "flow_approval_key": "approve-r2",
  }
  let normal = delivery_task_report_request(report, "owner-plan", task)
  let current = @company_flow.snapshot(task, 2)
  let canonical = flow_report_request(
    report,
    normal,
    approval,
    Some(current),
    None,
    "owner-plan",
  )
  assert_eq(
    flow_report_request(
      report,
      normal,
      approval,
      None,
      Some(canonical),
      "owner-plan",
    ),
    canonical,
  )
  try
    flow_report_request(
      report,
      normal,
      approval,
      Some(@company_flow.snapshot(task, 3)),
      None,
      "owner-plan",
    )
  catch {
    _ => ()
  } noraise {
    _ => raise fail("stale new report")
  }
  try
    flow_report_request(
      report,
      normal,
      approval,
      Some(current),
      None,
      "other-owner",
    )
  catch {
    _ => ()
  } noraise {
    _ => raise fail("report owner must authenticate")
  }
  let changed = @json.parse(
    report.stringify().replace_all(old="approve-r2", new="approve-r3"),
  )
  try
    flow_report_request(
      changed,
      normal,
      approval,
      None,
      Some(canonical),
      "owner-plan",
    )
  catch {
    _ => ()
  } noraise {
    _ => raise fail("changed approval on retry")
  }
  let changed_binding = @json.parse(
    report
    .stringify()
    .replace_all(old="\"request_id\":\"q2\"", new="\"request_id\":\"q3\""),
  )
  try
    flow_report_request(
      changed_binding,
      normal,
      approval,
      None,
      Some(canonical),
      "owner-plan",
    )
  catch {
    _ => ()
  } noraise {
    _ => raise fail("changed Flow identity")
  }
  let sql = flow_report_atomic_sql(
    canonical, "moonproj:command:report-key", "INSERT INTO receipt VALUES ('test');",
  )
  assert_true(sql.contains("LOCK TABLE company_aggregate_projection"))
  assert_true(sql.contains("LOCK TABLE company_record"))
  assert_true(sql.contains("aggregate_type = ''plan_task''"))
  assert_true(sql.contains("aggregate_type=''task_report''"))
  assert_true(sql.contains("= 2 AND NOT EXISTS"))
}

///|
async test "serialized gateway request crosses actual company approval and report normalizers" {
  let pointer = @env.get_env_var("MOONPROJ_FLOW_V2_FIXTURE_POINTER").unwrap_or(
    "",
  )
  if pointer.is_empty() {
    return
  }
  let fixture = @json.parse(@fs.read_file(pointer).text())
  let workspace = json_text(fixture, "workspace", "")
  let parent = workspace[:workspace.rev_find("/").unwrap()].to_owned()
  let approval_body = @json.parse(
    @fs.read_file(parent + "/wire-approval-body.json").text(),
  )
  let binding = json_field(approval_body, "binding").unwrap()
  let snapshot = json_field(binding, "snapshot").unwrap()
  let task = json_field(snapshot, "task").unwrap()
  let request = flow_binding_request(
    task,
    json_int(snapshot, "source_revision", 0),
    approval_body,
    "owner-plan",
  )
  let approval = flow_binding_command(request, "approve-r2")
  assert_eq(
    approval,
    json_field(json_field(fixture, "approval").unwrap(), "command").unwrap(),
  )
  let report_body = @json.parse(
    @fs.read_file(parent + "/wire-report-body.json").text(),
  )
  let normal = delivery_task_report_request(report_body, "owner-plan", task)
  let canonical = flow_report_request(
    report_body,
    normal,
    approval,
    Some(snapshot),
    None,
    "owner-plan",
  )
  let observed = @json.parse(
    @fs.read_file(parent + "/wire-report-command.json").text(),
  )
  assert_eq(canonical, json_field(observed, "request").unwrap())
  assert_eq(
    flow_report_request(
      report_body,
      normal,
      approval,
      None,
      Some(canonical),
      "owner-plan",
    ),
    canonical,
  )
  @fs.write_file(
    parent + "/service-normalizer-receipt.json",
    (
      {
        "approval_request": "actual signed-service normalizer",
        "report_request": "actual delivery normalizer plus Flow approval and revision guard",
        "exact_wire_requests": true,
        "database": "not exercised",
        "configured_identity": "not exercised",
        "historical_replay_request_equal": true,
      } : Json).stringify(indent=2),
    create_mode=@fs.CreateOrTruncate,
  )
}
