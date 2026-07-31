///|
async fn write_test_text(
  root : String,
  reference : String,
  content : String,
) -> Unit {
  let path = scoped_path(root, reference)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, content, create=0o644)
}

///|
fn fixture_request(
  evidence_digest : String,
) -> @project_plan.ProjectPlanRequest {
  {
    contract_id: "moonproj.project-plan-request.v1",
    operation_ref: @project_plan.operation_ref(),
    plan_request_id: "plan-flow-001",
    project: {
      project_id: "robotics-flow-001",
      principal_id: "opc-001",
      code: "ROBOT-FLOW-001",
      name: "Robot delivery plan",
    },
    prepared_by: "owner-plan",
    prepared_at: "2026-07-31T00:00:00Z",
    owners: [
      {
        owner_id: "owner-plan",
        display_name: "Plan Owner",
        role: "project-owner",
      },
      {
        owner_id: "owner-review",
        display_name: "Plan Reviewer",
        role: "independent-reviewer",
      },
    ],
    budget_envelope: {
      currency: "CNY",
      limit_minor: 500000L,
      contingency_minor: 50000L,
    },
    tasks: [
      {
        task_id: "task-model",
        name: "Prepare the digital model",
        owner_id: "owner-plan",
        milestone_id: "milestone-model",
        planned_cost_minor: 200000L,
        dependencies: [],
        acceptance_gate_ids: ["gate-model"],
        source_evidence_refs: ["inputs/requirements.txt"],
      },
    ],
    milestones: [
      {
        milestone_id: "milestone-model",
        name: "Digital model review",
        owner_id: "owner-plan",
        target_date: "2026-08-31",
        task_ids: ["task-model"],
        acceptance_gate_ids: ["gate-model"],
      },
    ],
    risks: [
      {
        risk_id: "risk-input",
        summary: "Requirements may change",
        severity: "medium",
        owner_id: "owner-review",
        mitigation: "Require a new immutable plan version",
        related_task_ids: ["task-model"],
        source_evidence_refs: ["inputs/requirements.txt"],
      },
    ],
    acceptance_gates: [
      {
        gate_id: "gate-model",
        name: "Model acceptance",
        owner_id: "owner-review",
        scope_type: "milestone",
        scope_id: "milestone-model",
        criteria: ["lineage is complete"],
        required_evidence: ["named reviewer receipt"],
      },
    ],
    source_evidence: [
      {
        artifact_ref: "inputs/requirements.txt",
        digest: evidence_digest,
        observed_at: "2026-07-31T00:00:00Z",
        kind: "accepted-requirements",
      },
    ],
  }
}

///|
async fn adapter_fixture(
  attempt_id? : String = "attempt-plan-1",
) -> (String, String, String, FlowRequest) {
  let root = @fs.tmpdir(prefix="moonproj-project-plan-adapter")
  let evidence_ref = "inputs/requirements.txt"
  let plan_ref = "inputs/project-plan-request.json"
  let request_ref = "runtime/request.json"
  let result_ref = "runtime/result.json"
  write_test_text(
    root, evidence_ref, "Build a reviewable digital robot model.\n",
  )
  let evidence_digest = digest_ref(root, evidence_ref)
  write_test_text(
    root,
    plan_ref,
    fixture_request(evidence_digest).to_json().stringify(indent=2) + "\n",
  )
  let input_artifacts = [plan_ref, evidence_ref]
  let flow : FlowRequest = {
    request_id: "request-\{attempt_id}",
    run_id: "robotics-plan-run",
    book_id: "robotics-delivery",
    work_item_id: "prepare-project-plan",
    declaration_id: "robotics-project-plan-v2",
    attempt_id,
    idempotency_key: "robotics-plan-run/\{attempt_id}",
    product_id: "moonproj",
    operation: @project_plan.operation_ref(),
    requested_authority: "workspace-mutation",
    acceptance_criteria: [
      "reviewable dependency-ordered plan exists", "all business effects remain separately authorized",
    ],
    input_contracts: [@project_plan.input_schema_ref()],
    output_contracts: [@project_plan.output_schema_ref()],
    required_claim: "digital-artifact",
    input_digest: declared_input_digest(root, input_artifacts),
    input_artifacts,
    timeout_ms: 60000,
    created_at: "2026-07-31T00:05:00Z",
  }
  let request_json : Json = {
    "request_id": flow.request_id,
    "run_id": flow.run_id,
    "book_id": flow.book_id,
    "work_item_id": flow.work_item_id,
    "declaration_id": flow.declaration_id,
    "attempt_id": flow.attempt_id,
    "idempotency_key": flow.idempotency_key,
    "product_id": flow.product_id,
    "operation": flow.operation,
    "requested_authority": flow.requested_authority,
    "acceptance_criteria": flow.acceptance_criteria,
    "input_contracts": flow.input_contracts,
    "output_contracts": flow.output_contracts,
    "required_claim": flow.required_claim,
    "input_digest": flow.input_digest,
    "input_artifacts": flow.input_artifacts,
    "timeout_ms": flow.timeout_ms,
    "created_at": flow.created_at,
  }
  write_test_text(root, request_ref, request_json.stringify(indent=2) + "\n")
  (root, request_ref, result_ref, flow)
}

///|
async test "MoonProj project planning executes once and reconciles exact evidence" {
  let (root, request_ref, result_ref, flow) = adapter_fixture()
  let first = execute(root, request_ref, result_ref)
  let replay = execute(root, request_ref, result_ref)
  let reconciled = reconcile(root, request_ref, result_ref)
  assert_eq(first, replay)
  assert_eq(first, reconciled)
  let fields = json_object(first, "result")
  assert_eq(json_string_field(fields, "status"), "succeeded")
  let artifact = @project_plan.decode_artifact(
    read_json_ref(root, artifact_ref(flow)),
  )
  assert_eq(artifact.workflow.status, "pending_review")
  assert_true(!artifact.workflow.accepted)
  assert_true(!artifact.authority_effects.spend_authorized)
  assert_eq(artifact.tasks[0].state, "planned")
}

///|
async test "MoonProj reconciliation resumes safely from durable intent" {
  let (root, request_ref, result_ref, flow) = adapter_fixture(
    attempt_id="attempt-plan-restart",
  )
  let (decoded, _) = load_bound_inputs(root, request_ref)
  begin_attempt(root, request_ref, result_ref, decoded)
  assert_true(!@fs.exists(scoped_path(root, artifact_ref(flow))))
  let result = reconcile(root, request_ref, result_ref)
  let fields = json_object(result, "result")
  assert_eq(json_string_field(fields, "status"), "succeeded")
  assert_true(@fs.exists(scoped_path(root, artifact_ref(flow))))
  assert_true(@fs.exists(scoped_path(root, internal_result_ref(flow))))
}

///|
async test "MoonProj health is content-addressed and expires within one hour" {
  let root = @fs.tmpdir(prefix="moonproj-project-plan-health")
  let attestation = publish_health(
    root, "2026-07-31T00:00:00Z", "2026-07-31T00:30:00Z", "health/moonproj-project-plan.attestation.json",
  )
  let fields = json_object(attestation, "health attestation")
  assert_eq(
    json_string_field(fields, "contract_id"),
    "moonflow.adapter-health.v1",
  )
  assert_eq(json_string_field(fields, "protocol"), "moonflow.adapter.v2")
  let evidence_ref = json_string_field(fields, "evidence_ref")
  assert_true(
    evidence_ref.has_prefix(".moonsuite/products/moonproj/health/evidence/"),
  )
  assert_eq(
    json_string_field(fields, "evidence_digest"),
    digest_ref(root, evidence_ref),
  )
  try
    publish_health(
      root, "2026-07-31T00:00:00Z", "2026-07-31T02:00:00Z", "health/too-long.json",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected long-lived health to be rejected")
  }
}

///|
async test "MoonProj pack, declaration and runtime publish one capability truth" {
  let pack = json_object(
    @json.parse(@fs.read_file("pack.json").text()),
    "pack manifest",
  )
  assert_eq(json_string_field(pack, "id"), "moonproj")
  assert_eq(json_string_field(pack, "version"), @project_plan.pack_version())
  guard pack.get("tools") is Some(Array([Object(tool)])) else {
    fail("expected one MoonProj pack tool")
  }
  assert_eq(json_string_field(tool, "id"), @project_plan.operation_id())
  assert_eq(json_string_field(tool, "owner_product"), "moonproj")
  assert_eq(json_string_field(tool, "input_schema_id"), "project-plan-request")
  assert_eq(
    json_string_field(tool, "output_schema_id"),
    "project-plan-artifact",
  )
  assert_eq(json_string_field(tool, "authority"), "WorkspaceMutation")
  guard tool.get("idempotent") is Some(True) &&
    tool.get("review_required") is Some(True) else {
    fail("project plan preparation must be idempotent and review-required")
  }
  let declaration = json_object(
    @json.parse(
      @fs.read_file("adapters/moonflow/adapter-declaration.v1.json").text(),
    ),
    "adapter declaration",
  )
  assert_eq(json_string_field(declaration, "adapter_id"), adapter_id())
  assert_eq(json_string_field(declaration, "protocol"), protocol())
  guard declaration.get("operations") is Some(Array([Object(operation)])) else {
    fail("expected one declared MoonProj operation")
  }
  assert_eq(
    json_string_field(operation, "operation_id"),
    @project_plan.operation_id(),
  )
  assert_eq(json_string_field(operation, "claim_ceiling"), "digital-artifact")
  guard operation.get("supports_reconcile") is Some(True) else {
    fail("MoonProj adapter declaration must support reconciliation")
  }
  let input_schema = json_object(
    @json.parse(
      @fs.read_file("schemas/project-plan-request.schema.json").text(),
    ),
    "input schema",
  )
  let output_schema = json_object(
    @json.parse(
      @fs.read_file("schemas/project-plan-artifact.schema.json").text(),
    ),
    "output schema",
  )
  assert_eq(
    json_string_field(input_schema, "$id"),
    @project_plan.input_schema_ref(),
  )
  assert_eq(
    json_string_field(output_schema, "$id"),
    @project_plan.output_schema_ref(),
  )
  let capability = json_object(capability_json(), "runtime capability")
  guard capability.get("operations") is Some(Array([String(operation_ref)])) else {
    fail("runtime capability must publish one operation")
  }
  assert_eq(operation_ref, @project_plan.operation_ref())
}

///|
async test "MoonProj adapter requires the full generic MoonFlow request identity" {
  let (root, request_ref, _, _) = adapter_fixture(
    attempt_id="attempt-plan-contract",
  )
  guard read_json_ref(root, request_ref) is Object(fields) else {
    fail("fixture request must be an object")
  }
  let without_book = fields.copy()
  ignore(without_book.remove("book_id"))
  try decode_flow_request(Json::object(without_book)) catch {
    _ => ()
  } noraise {
    _ => fail("expected missing book_id to be rejected")
  }
  let without_criteria = fields.copy()
  without_criteria["acceptance_criteria"] = Json::array([])
  try decode_flow_request(Json::object(without_criteria)) catch {
    _ => ()
  } noraise {
    _ => fail("expected empty acceptance criteria to be rejected")
  }
}
