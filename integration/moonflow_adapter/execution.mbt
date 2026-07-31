///|
async fn find_plan_request(
  root : String,
  flow : FlowRequest,
) -> (String, @project_plan.ProjectPlanRequest) {
  let mut found : (String, @project_plan.ProjectPlanRequest)? = None
  for reference in flow.input_artifacts {
    let text = read_text_ref(root, reference)
    let value = @json.parse(text) catch { _ => continue }
    guard value is Object(fields) else { continue }
    guard fields.get("contract_id") is Some(String(contract_id)) &&
      contract_id == "moonproj.project-plan-request.v1" else {
      continue
    }
    if found is Some(_) {
      fail("MoonProj Flow request contains more than one project plan request")
    }
    found = Some((reference, @project_plan.decode_request(value)))
  }
  match found {
    Some(value) => value
    None =>
      fail(
        "MoonProj Flow request has no moonproj.project-plan-request.v1 artifact",
      )
  }
}

///|
async fn verify_source_evidence(
  root : String,
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
) -> Unit {
  for evidence in request.source_evidence {
    if !flow.input_artifacts.contains(evidence.artifact_ref) {
      fail(
        "MoonProj source evidence is not bound by the Flow input digest: \{evidence.artifact_ref}",
      )
    }
    if digest_ref(root, evidence.artifact_ref) != evidence.digest {
      fail("MoonProj source evidence digest changed: \{evidence.artifact_ref}")
    }
  }
}

///|
fn intent_json(
  request_ref : String,
  result_ref : String,
  flow : FlowRequest,
) -> Json {
  {
    "contract_id": "moonproj.project-plan-attempt-intent.v1",
    "adapter_id": adapter_id(),
    "protocol": protocol(),
    "product_id": "moonproj",
    "pack_version": @project_plan.pack_version(),
    "operation_ref": @project_plan.operation_ref(),
    "request_id": flow.request_id,
    "run_id": flow.run_id,
    "book_id": flow.book_id,
    "work_item_id": flow.work_item_id,
    "declaration_id": flow.declaration_id,
    "attempt_id": flow.attempt_id,
    "idempotency_key": flow.idempotency_key,
    "acceptance_criteria": flow.acceptance_criteria,
    "input_digest": flow.input_digest,
    "request_ref": request_ref,
    "result_ref": result_ref,
    "authority": "workspace-mutation",
    "claim_ceiling": "digital-artifact",
    "recorded_at": flow.created_at,
  }
}

///|
async fn begin_attempt(
  root : String,
  request_ref : String,
  result_ref : String,
  flow : FlowRequest,
) -> Unit {
  ignore(
    immutable_json_ref(root, idempotency_ref(flow), {
      "contract_id": "moonproj.project-plan-idempotency.v1",
      "idempotency_key": flow.idempotency_key,
      "request_id": flow.request_id,
      "run_id": flow.run_id,
      "book_id": flow.book_id,
      "work_item_id": flow.work_item_id,
      "declaration_id": flow.declaration_id,
      "attempt_id": flow.attempt_id,
      "operation_ref": @project_plan.operation_ref(),
      "acceptance_criteria": flow.acceptance_criteria,
      "input_digest": flow.input_digest,
      "intent_ref": intent_ref(flow),
    }),
  )
  let intent = intent_json(request_ref, result_ref, flow)
  ignore(immutable_json_ref(root, intent_ref(flow), intent))
}

///|
async fn validate_artifact_evidence(
  root : String,
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
  value : Json,
) -> @project_plan.ProjectPlanArtifact {
  let artifact = @project_plan.decode_artifact(value)
  let expected = @project_plan.prepare(
    request,
    flow.attempt_id,
    flow.input_digest,
    flow.created_at,
  )
  if artifact != expected {
    fail(
      "MoonProj project plan artifact is not the deterministic result of its bound request",
    )
  }
  for evidence in artifact.source_evidence {
    if !flow.input_artifacts.contains(evidence.artifact_ref) ||
      digest_ref(root, evidence.artifact_ref) != evidence.digest {
      fail("MoonProj project plan artifact has stale source evidence")
    }
  }
  artifact
}

///|
async fn build_artifact(
  root : String,
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
) -> String {
  let reference = artifact_ref(flow)
  match read_optional_json_ref(root, reference) {
    Some(value) => {
      ignore(validate_artifact_evidence(root, flow, request, value))
      @fs.read_file(checked_input_path(root, reference)).text()
    }
    None => {
      let artifact = @project_plan.prepare(
        request,
        flow.attempt_id,
        flow.input_digest,
        flow.created_at,
      )
      @project_plan.validate_artifact(artifact)
      let text = immutable_json_ref(root, reference, artifact.to_json())
      ignore(validate_artifact_evidence(root, flow, request, @json.parse(text)))
      text
    }
  }
}

///|
fn result_json(flow : FlowRequest, output_text : String) -> Json {
  {
    "result_id": "result-\{flow.attempt_id}-succeeded",
    "request_id": flow.request_id,
    "attempt_id": flow.attempt_id,
    "idempotency_key": flow.idempotency_key,
    "product_id": "moonproj",
    "external_job_id": "moonproj-project-plan-\{flow.attempt_id}",
    "status": "succeeded",
    "output_digest": sha256_text(output_text),
    "output_artifacts": [artifact_ref(flow)],
    "error_kind": "",
    "compensable": false,
    "recorded_at": flow.created_at,
  }
}

///|
async fn validate_result(
  root : String,
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
  result : Json,
) -> Unit {
  let fields = json_object(result, "adapter result")
  if json_string_field(fields, "request_id") != flow.request_id ||
    json_string_field(fields, "attempt_id") != flow.attempt_id ||
    json_string_field(fields, "idempotency_key") != flow.idempotency_key ||
    json_string_field(fields, "product_id") != "moonproj" ||
    json_string_field(fields, "status") != "succeeded" {
    fail("MoonProj adapter result belongs to a different request")
  }
  guard fields.get("output_artifacts") is Some(Array([String(reference)])) &&
    reference == artifact_ref(flow) else {
    fail("MoonProj adapter result must name its exact plan artifact")
  }
  let output_text = read_text_ref(root, reference)
  if json_string_field(fields, "output_digest") != sha256_text(output_text) {
    fail("MoonProj adapter result digest does not match its plan artifact")
  }
  ignore(
    validate_artifact_evidence(root, flow, request, @json.parse(output_text)),
  )
}

///|
async fn complete_attempt(
  root : String,
  result_ref : String,
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
) -> Json {
  let internal_ref = internal_result_ref(flow)
  let result = match read_optional_json_ref(root, internal_ref) {
    Some(result) => result
    None => {
      let output_text = build_artifact(root, flow, request)
      let result = result_json(flow, output_text)
      ignore(immutable_json_ref(root, internal_ref, result))
      result
    }
  }
  validate_result(root, flow, request, result)
  ignore(immutable_json_ref(root, result_ref, result))
  result
}

///|
async fn load_bound_inputs(
  root : String,
  request_ref : String,
) -> (FlowRequest, @project_plan.ProjectPlanRequest) {
  let flow = decode_flow_request(read_json_ref(root, request_ref))
  if declared_input_digest(root, flow.input_artifacts) != flow.input_digest {
    fail("MoonProj Flow input digest does not match its artifacts")
  }
  let (_, request) = find_plan_request(root, flow)
  verify_source_evidence(root, flow, request)
  (flow, request)
}

///|
pub async fn execute(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, request) = load_bound_inputs(root, request_ref)
  begin_attempt(root, request_ref, result_ref, flow)
  complete_attempt(root, result_ref, flow, request)
}

///|
pub async fn reconcile(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, request) = load_bound_inputs(root, request_ref)
  let expected_intent = intent_json(request_ref, result_ref, flow)
  guard read_optional_json_ref(root, intent_ref(flow)) is Some(actual_intent) else {
    fail("MoonProj cannot reconcile an attempt without durable intent")
  }
  if actual_intent != expected_intent {
    fail("MoonProj durable intent does not match the reconciliation request")
  }
  begin_attempt(root, request_ref, result_ref, flow)
  complete_attempt(root, result_ref, flow, request)
}
