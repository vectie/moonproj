///|
/// Translate MoonFlow's single-workflow envelope into MoonProj's stable
/// execution protocol. MoonFlow still owns dispatch and its runtime claim;
/// MoonProj owns the company scope, authority ceiling, and prohibited effects.
fn agent_request(
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
) -> @agent_port.AgentRequest raise {
  let execution_request : @agent_port.AgentRequest = {
    protocol_version: @agent_port.protocol_version(),
    request_id: flow.request_id,
    work_item_id: flow.work_item_id,
    flow_run_id: flow.run_id,
    principal_id: request.project.principal_id,
    actor_id: request.prepared_by,
    capability: @project_plan.operation_ref(),
    scope: "project:\{request.project.project_id}",
    coordination_mode: MoonFlowSingleAgent,
    authority_ceiling_minor: 0,
    input_evidence: flow.input_artifacts,
    input_digest: flow.input_digest,
    acceptance_criteria: flow.acceptance_criteria,
    expected_result_schema: @project_plan.output_schema_ref(),
    prohibited_effects: @agent_port.reserved_company_effects(),
    idempotency_key: flow.idempotency_key,
  }
  execution_request.validate()
  if !execution_request.protects_reserved_effects() {
    fail(
      "MoonFlow execution request must prohibit every reserved company effect",
    )
  }
  execution_request
}

///|
/// Mirror MoonFlow's admitted runtime claim through the shared CAS state
/// machine. The adapter-local lease is only an execution-plane receipt; a
/// restart still reconciles from durable intent and cannot gain company
/// authority from this claim.
fn admitted_attempt(
  flow : FlowRequest,
  request : @project_plan.ProjectPlanRequest,
) -> @agent_port.ExecutionAttempt raise {
  let execution_request = agent_request(flow, request)
  let ready = @agent_port.ExecutionAttempt::new(
    execution_request,
    attempt_id=flow.attempt_id,
    at_epoch=0L,
  )
  let claim_token = "moonflow-adapter-claim:\{flow.run_id}:\{flow.attempt_id}"
  let claimed = ready.claim(
    expected_revision=ready.revision,
    claim_token~,
    executor_id="moonflow:\{flow.run_id}",
    now_epoch=0L,
    lease_seconds=300L,
  )
  claimed.transition(
    expected_revision=claimed.revision,
    to=Running,
    actor_id="moonflow:\{flow.run_id}",
    claim_token~,
    reason="MoonFlow adapter execution admitted",
    at_epoch=0L,
  )
}
