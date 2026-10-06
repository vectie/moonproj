///|
async fn company_delivery_fixture() -> (String, String, String, FlowRequest) {
  let (root, request_ref, result_ref, old_flow) = adapter_fixture()
  let company_ref = "inputs/company-task-command.json"
  let command : Json = {
    "kind": "company_command",
    "command_family": "plan_task",
    "command_type": "create",
    "aggregate_id": "PT-company",
    "actor_id": "owner-plan",
    "request": {
      "command_type": "create",
      "task_id": "PT-company",
      "project_id": "robotics-flow-001",
      "created_by": "owner-plan",
      "task_name": "Prepare a scoped digital plan",
      "source_context": {
        "reference": "source:interview-7",
        "problem": "Cannot compare alternatives",
      },
    },
    "result": {
      "task_id": "PT-company",
      "actor_id": "owner-plan",
      "revision": 1,
      "event_id": "plan_task:create:company-key",
      "audit_id": "plan_task:create:company-key:audit",
    },
  }
  write_test_text(root, company_ref, command.stringify())
  let original = fixture_request(digest_ref(root, "inputs/requirements.txt"))
  let sources = original.source_evidence.copy()
  sources.push({
    artifact_ref: company_ref,
    digest: digest_ref(root, company_ref),
    observed_at: old_flow.created_at,
    kind: "company-task-snapshot",
  })
  let plan = { ..original, source_evidence: sources, }
  write_test_text(
    root,
    "inputs/project-plan-request.json",
    plan.to_json().stringify(),
  )
  let inputs = old_flow.input_artifacts.copy()
  inputs.push(company_ref)
  let flow = {
    ..old_flow,
    input_artifacts: inputs,
    input_digest: declared_input_digest(root, inputs),
  }
  let request_fields = json_object(read_json_ref(root, request_ref), "request").copy()
  request_fields["input_artifacts"] = inputs.to_json()
  request_fields["input_digest"] = flow.input_digest.to_json()
  write_test_text(root, request_ref, Json::object(request_fields).stringify())
  (root, request_ref, result_ref, flow)
}

///|
fn company_report_response(envelope : Json, replay : Bool) -> Json {
  let body = company_field(envelope, "report_body")
  let fields = json_object(body, "body") catch { _ => abort("fixture body") }
  let request = fields.copy()
  request.remove("progress_pct")
  request["progress_bps"] = Json::number(0)
  request["command_type"] = "report".to_json()
  request["state"] = "observed".to_json()
  request["actor_id"] = "reporter".to_json()
  let key = company_text(envelope, "idempotency_key")
  let event_id = "delivery:task_report:report:" + key
  {
    "idempotent_replay": replay,
    "command": {
      "kind": "company_command",
      "command_family": "delivery",
      "family": "task_report",
      "aggregate_type": "task_report",
      "command_type": "report",
      "idempotency_key": key,
      "aggregate_id": company_field(body, "report_id"),
      "actor_id": "reporter",
      "request": Json::object(request),
      "result": {
        "aggregate_id": company_field(body, "report_id"),
        "state": "observed",
        "revision": 1,
        "event_id": event_id,
        "audit_id": event_id + ":audit",
        "actor_id": "reporter",
        "delivery_effect": false,
        "cash_effect": false,
        "accounting_effect": false,
        "tax_effect": false,
      },
    },
  }
}

///|
async test "company report retries retain exact named output and report receipt after restart" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  let binding = bind_company_task(root, request_ref)
  assert_eq(bind_company_task(root, request_ref), binding)
  let result = execute(root, request_ref, result_ref)
  let envelope = prepare_company_task_report(
    root,
    request_ref,
    result_ref,
    "first",
    "2026-10-04",
    "  Plan prepared; review remains separate.  ",
    [],
  )
  assert_eq(
    company_text(envelope, "path"),
    "/api/company/plan/tasks/PT-company/report",
  )
  assert_eq(
    company_text(company_field(envelope, "report_body"), "summary"),
    "Plan prepared; review remains separate.",
  )
  assert_eq(
    company_text(
      company_task_report_status(root, request_ref, "first"),
      "state",
    ),
    "pending_report",
  )
  let recovered = @json.parse(
    read_text_ref(root, company_report_base(flow, "first") + "/report.json"),
  )
  assert_eq(recovered, envelope)
  assert_eq(
    prepare_company_task_report(
      root,
      request_ref,
      result_ref,
      "first",
      "2026-10-04",
      "Plan prepared; review remains separate.",
      [],
    ),
    envelope,
  )
  write_test_text(
    root,
    "report-response.json",
    company_report_response(envelope, false).stringify(),
  )
  let first = record_company_task_report_receipt(
    root, request_ref, "first", "report-response.json",
  )
  write_test_text(
    root,
    "report-response.json",
    company_report_response(envelope, true).stringify(),
  )
  let replayed = record_company_task_report_receipt(
    root, request_ref, "first", "report-response.json",
  )
  assert_eq(first, replayed)
  let original_command = json_object(
    company_field(company_report_response(envelope, true), "command"),
    "command",
  )
  let reordered : Map[String, Json] = {}
  let keys = original_command.keys().to_array()
  for index in 0..<keys.length() {
    let key = keys[keys.length() - index - 1]
    reordered[key] = original_command[key]
  }
  write_test_text(
    root,
    "report-response.json",
    ({ "command": Json::object(reordered) } : Json).stringify(),
  )
  assert_eq(
    record_company_task_report_receipt(
      root, request_ref, "first", "report-response.json",
    ),
    first,
  )
  assert_eq(company_text(first, "state"), "reported")
  assert_eq(company_text(first, "task_acceptance"), "unchanged")
  assert_eq(reconcile(root, request_ref, result_ref), result)
  assert_true(
    read_text_ref(root, company_binding_ref(flow)).contains(
      "company-task-command.json",
    ),
  )
  assert_true(
    read_text_ref(root, artifact_ref(flow)).contains(
      "company-task-command.json",
    ),
  )
}

///|
async test "rehashing changed task input cannot reuse original company binding or adapter effect" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  ignore(bind_company_task(root, request_ref))
  ignore(execute(root, request_ref, result_ref))
  let output_before = read_text_ref(root, artifact_ref(flow))
  let command_ref = "inputs/company-task-command.json"
  let original = read_text_ref(root, command_ref)
  write_test_text(
    root,
    command_ref,
    original.replace(
      old="Cannot compare alternatives",
      new="Changed founder brief",
    ),
  )
  let plan_ref = "inputs/project-plan-request.json"
  let plan = @project_plan.decode_request(read_json_ref(root, plan_ref))
  let digest = digest_ref(root, command_ref)
  let changed = {
    ..plan,
    source_evidence: plan.source_evidence.map(evidence => {
      if evidence.artifact_ref == command_ref {
        { ..evidence, digest, }
      } else {
        evidence
      }
    }),
  }
  write_test_text(root, plan_ref, changed.to_json().stringify())
  let request = json_object(read_json_ref(root, request_ref), "request").copy()
  request["input_digest"] = declared_input_digest(root, flow.input_artifacts).to_json()
  write_test_text(root, request_ref, Json::object(request).stringify())
  try bind_company_task(root, request_ref) catch {
    _ => ()
  } noraise {
    _ => fail("rehashed task must not change old binding")
  }
  try execute(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("rehashed task must not change old effect")
  }
  assert_eq(read_text_ref(root, artifact_ref(flow)), output_before)
}

///|
async test "incomplete receipt checkpoint cannot display reported status" {
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
    company_report_base(flow, "first") + "/receipt.json",
    "null",
  )
  try company_task_report_status(root, request_ref, "first") catch {
    _ => ()
  } noraise {
    _ => fail("incomplete checkpoint cannot be reported")
  }
}

///|
async test "company report preparation cannot execute or accept missing work" {
  let (root, request_ref, result_ref, flow) = company_delivery_fixture()
  try
    prepare_company_task_report(
      root,
      request_ref,
      result_ref,
      "first",
      "2026-10-04",
      "Summary",
      [],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("unexecuted work must not create a report")
  }
  assert_false(@fs.exists(scoped_path(root, intent_ref(flow))))
  assert_false(@fs.exists(scoped_path(root, artifact_ref(flow))))
}

///|
async test "company bridge rejects changed task bytes result evidence and report response" {
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
  try
    prepare_company_task_report(
      root,
      request_ref,
      result_ref,
      "first",
      "2026-10-04",
      "Changed",
      [],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("report body must remain immutable")
  }
  let response = company_report_response(envelope, false)
  let command = json_object(company_field(response, "command"), "command").copy()
  command["idempotency_key"] = "other".to_json()
  write_test_text(
    root,
    "wrong-response.json",
    ({ "command": Json::object(command) } : Json).stringify(),
  )
  try
    record_company_task_report_receipt(
      root, request_ref, "first", "wrong-response.json",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("wrong receipt must not settle report")
  }
  assert_eq(
    company_text(
      company_task_report_status(root, request_ref, "first"),
      "state",
    ),
    "pending_report",
  )
  write_test_text(root, "inputs/company-task-command.json", "{}")
  try reconcile(root, request_ref, result_ref) catch {
    _ => ()
  } noraise {
    _ => fail("changed task snapshot must not reuse binding")
  }
}

///|
async test "legacy plan adapter remains optional and has no company binding" {
  let (root, request_ref, result_ref, flow) = adapter_fixture()
  ignore(execute(root, request_ref, result_ref))
  assert_false(@fs.exists(scoped_path(root, company_binding_ref(flow))))
  try
    prepare_company_task_report(
      root,
      request_ref,
      result_ref,
      "first",
      "2026-10-04",
      "Summary",
      [],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("legacy attempt has no company task report")
  }
}

///|
/// Opt-in serialized interoperability fixture; ordinary package tests do not
/// export files. Other product processes consume only these workspace bytes.
async test "company fixture exports one declared task without executing it" {
  match @env.get_env_var("MOONSUITE_COMPANY_FLOW_FIXTURE_POINTER") {
    None => ()
    Some(pointer) => {
      let (root, request_ref, result_ref, flow) = company_delivery_fixture()
      assert_false(@fs.exists(scoped_path(root, intent_ref(flow))))
      @fs.write_file(
        pointer,
        (
          {
            "workspace": root,
            "request_ref": request_ref,
            "result_ref": result_ref,
          } : Json).stringify(),
        create_mode=@fs.CreateOrTruncate,
      )
    }
  }
}
