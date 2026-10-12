///|
async fn revised_fixture(
  revision? : Int = 2,
) -> (String, String, String, FlowRequest) {
  let (root, request_ref, result_ref, original) = adapter_fixture()
  let snapshot : Json = @company_flow.snapshot(
    {
      "task_id": "PT-revised",
      "project_id": "robotics-flow-001",
      "created_by": "owner-plan",
      "task_name": "Prepare revised digital plan",
      "state": "pending",
      "source_kind": "command",
      "event_id": "plan_task:update:revision-" + revision.to_string(),
      "source_context": {
        "reference": "source:interview-7",
        "problem": "Revised comparison scope",
      },
    },
    revision,
  )
  let reference = "inputs/revised-task.json"
  write_test_text(root, reference, snapshot.stringify())
  let plan = fixture_request(digest_ref(root, "inputs/requirements.txt"))
  let sources = plan.source_evidence.copy()
  sources.push({
    artifact_ref: reference,
    digest: digest_ref(root, reference),
    observed_at: original.created_at,
    kind: "company-task-snapshot",
  })
  write_test_text(
    root,
    "inputs/project-plan-request.json",
    { ..plan, source_evidence: sources, }.to_json().stringify(),
  )
  let inputs = original.input_artifacts.copy()
  inputs.push(reference)
  let flow = {
    ..original,
    input_artifacts: inputs,
    input_digest: declared_input_digest(root, inputs),
  }
  write_test_text(root, request_ref, flow.to_json().stringify())
  (root, request_ref, result_ref, flow)
}

///|
fn revised_approval(binding : Json, key? : String = "approve-r2") -> Json {
  let event = "flow_task_binding:approve:" + key
  {
    "command": {
      "kind": "company_command",
      "command_family": "flow_task_binding",
      "command_type": "approve",
      "aggregate_type": "plan_task",
      "aggregate_id": "PT-revised",
      "actor_id": "owner-plan",
      "idempotency_key": key,
      "request": {
        "command_type": "approve",
        "actor_id": "owner-plan",
        "binding": binding,
        "authority": {
          "active": true,
          "actor_id": "owner-plan",
          "principal_id": "opc-001",
          "capability": "project:task:update",
          "scope": "project:robotics-flow-001",
        },
      },
      "result": {
        "task_id": "PT-revised",
        "actor_id": "owner-plan",
        "state": "approved",
        "source_revision": company_field(binding, "source_revision"),
        "event_id": event,
        "audit_id": event + ":audit",
        "execution_effect": false,
        "acceptance_effect": false,
      },
    },
  }
}

///|
fn revised_report_response(envelope : Json, replay : Bool) -> Json {
  let original = company_report_response(envelope, replay)
  let command = json_object(company_field(original, "command"), "command") catch {
    _ => abort("fixture")
  }
  let request = json_object(
    company_field(Json::object(command), "request"),
    "request",
  ) catch {
    _ => abort("fixture")
  }
  let result = json_object(
    company_field(Json::object(command), "result"),
    "result",
  ) catch {
    _ => abort("fixture")
  }
  command["actor_id"] = "owner-plan".to_json()
  request["actor_id"] = "owner-plan".to_json()
  request["flow_source_revision"] = company_field(
    company_field(company_field(envelope, "report_body"), "flow_binding"),
    "source_revision",
  )
  result["actor_id"] = "owner-plan".to_json()
  original
}

///|
async test "offline approval cannot authorize revised execution and persistence remains immutable" {
  let (root, request_ref, result_ref, flow) = revised_fixture()
  let binding = company_task_binding_proposal(root, request_ref)
  assert_eq(company_field(binding, "source_revision"), Json::number(2))
  try bind_company_task(root, request_ref) catch {
    _ => ()
  } noraise {
    _ => fail("approval required")
  }
  try execute(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("unapproved execution forbidden")
  }
  assert_false(@fs.exists(scoped_path(root, intent_ref(flow))))
  let approval = revised_approval(binding)
  assert_eq(record_company_task_approval(root, request_ref, approval), binding)
  assert_eq(record_company_task_approval(root, request_ref, approval), binding)
  try execute(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("local approval must not authorize ordinary execute")
  }
  try reconcile(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("local approval must not authorize ordinary reconcile")
  }
  assert_false(@fs.exists(scoped_path(root, intent_ref(flow))))
  assert_false(@fs.exists(scoped_path(root, artifact_ref(flow))))
  try
    execute_approved_company_task(
      root,
      request_ref,
      result_ref,
      service_uri="",
      service_token="",
      actor_id="owner-plan",
      actor_signature="",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("approved execution must contact the signed service")
  }
  assert_false(@fs.exists(scoped_path(root, intent_ref(flow))))
  let result = revised_fixture_persistence(root, request_ref, result_ref)
  assert_eq(revised_fixture_persistence(root, request_ref, result_ref), result)
  let envelope = prepare_company_task_report(
    root,
    request_ref,
    result_ref,
    "revision-two",
    "2026-10-08",
    "Revised plan prepared",
    [],
  )
  assert_eq(
    company_field(company_field(envelope, "report_body"), "flow_binding"),
    binding,
  )
  let partial = revised_report_response(envelope, false)
  let partial_request = json_object(
    company_field(company_field(partial, "command"), "request"),
    "request",
  )
  partial_request.remove("flow_source_revision")
  try
    record_company_task_report_response(
      root, request_ref, "revision-two", partial,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("partial revision receipt cannot settle report")
  }
  assert_eq(
    company_text(
      company_task_report_status(root, request_ref, "revision-two"),
      "state",
    ),
    "pending_report",
  )
  let status = record_company_task_report_response(
    root,
    request_ref,
    "revision-two",
    revised_report_response(envelope, false),
  )
  assert_eq(
    record_company_task_report_response(
      root,
      request_ref,
      "revision-two",
      revised_report_response(envelope, true),
    ),
    status,
  )
  assert_eq(company_text(status, "state"), "reported_local_cache")
  assert_eq(
    company_text(status, "acknowledgement"),
    "local_cached_command_not_independently_verified",
  )
  assert_eq(company_text(status, "task_acceptance"), "unchanged")
}

///|
async test "partial approval checkpoint repairs without inheriting approval across revisions" {
  let (root, request_ref, result_ref, flow) = revised_fixture()
  let binding = company_task_binding_proposal(root, request_ref)
  let approval = revised_approval(binding)
  write_test_text(
    root,
    company_approval_ref(flow),
    company_field(approval, "command").stringify(),
  )
  assert_false(@fs.exists(scoped_path(root, company_binding_ref(flow))))
  assert_eq(record_company_task_approval(root, request_ref, approval), binding)
  ignore(revised_fixture_persistence(root, request_ref, result_ref))
  let before = read_text_ref(root, artifact_ref(flow))
  let (child, _, _, original_child_flow) = revised_fixture(revision=3)
  for reference in original_child_flow.input_artifacts {
    write_test_text(
      root,
      "child/" + reference,
      read_text_ref(child, reference).replace_all(
        old="inputs/",
        new="child/inputs/",
      ),
    )
  }
  let child_inputs = original_child_flow.input_artifacts.map(reference => {
    "child/" + reference
  })
  let child_flow = {
    ..original_child_flow,
    run_id: "company-child-r3",
    request_id: "company-request-r3",
    attempt_id: "company-attempt-r3",
    idempotency_key: "company-child-r3/plan/1",
    input_artifacts: child_inputs,
    input_digest: declared_input_digest(root, child_inputs),
  }
  let child_request = "child/runtime/request.json"
  let child_result = "child/runtime/result.json"
  write_test_text(root, child_request, child_flow.to_json().stringify())
  try record_company_task_approval(root, child_request, approval) catch {
    _ => ()
  } noraise {
    _ => fail("old approval must not authorize a revision")
  }
  try execute(root, child_request, child_result) catch {
    _ => ()
  } noraise {
    _ => fail("child requires fresh approval")
  }
  assert_false(@fs.exists(scoped_path(root, intent_ref(child_flow))))
  let child_binding = company_task_binding_proposal(root, child_request)
  ignore(
    record_company_task_approval(
      root,
      child_request,
      revised_approval(child_binding, key="approve-r3"),
    ),
  )
  ignore(revised_fixture_persistence(root, child_request, child_result))
  assert_eq(read_text_ref(root, artifact_ref(flow)), before)
  assert_eq(read_json_ref(root, company_binding_ref(flow)), binding)
  assert_true(company_binding_ref(flow) != company_binding_ref(child_flow))
}

///|
async test "approved checkpoint refuses wrong actor changed input and incomplete approval" {
  let (root, request_ref, result_ref, flow) = revised_fixture()
  let binding = company_task_binding_proposal(root, request_ref)
  let approval = revised_approval(binding)
  let changed = @json.parse(
    approval.stringify().replace_all(old="owner-plan", new="other-owner"),
  )
  try record_company_task_approval(root, request_ref, changed) catch {
    _ => ()
  } noraise {
    _ => fail("actor mismatch")
  }
  write_test_text(root, company_approval_ref(flow), "{}")
  try bind_company_task(root, request_ref) catch {
    _ => ()
  } noraise {
    _ => fail("partial approval must block")
  }
  try execute(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("partial approval cannot execute")
  }
}

///|
async test "export revised task inputs for authenticated gateway wire qualification" {
  if @env.get_env_var("MOONPROJ_FLOW_V2_FIXTURE_POINTER") is Some(pointer) {
    let (root, request_ref, result_ref, _) = revised_fixture()
    let binding = company_task_binding_proposal(root, request_ref)
    write_test_text(
      root,
      "fixture-approval.json",
      revised_approval(binding).stringify(),
    )
    @fs.write_file(
      pointer,
      (
        {
          "workspace": root,
          "request_ref": request_ref,
          "result_ref": result_ref,
          "binding": binding,
          "approval": revised_approval(binding),
        } : Json).stringify(),
      create_mode=@fs.CreateOrTruncate,
    )
  }
}

///|
/// Whitebox-only storage fixture, not an execution authority API. Authenticated
/// execution is qualified by the production gateway/HTTP fixture separately.
async fn revised_fixture_persistence(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  ignore(bound_company_input(root, flow, plan))
  begin_attempt(root, request_ref, result_ref, flow, plan)
  complete_attempt(root, result_ref, flow, plan)
}
