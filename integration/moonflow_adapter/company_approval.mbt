///|
fn company_approval_ref(flow : FlowRequest) -> String {
  attempt_base(flow) + "/company-task-approval.json"
}

///|
async fn require_company_approval(
  root : String,
  flow : FlowRequest,
  binding : Json,
) -> Unit {
  if company_text(binding, "contract_id") == "moonproj.flow-task-binding.v2" {
    @company_flow.validate_approval(
      binding,
      read_json_ref(root, company_approval_ref(flow)),
    )
  }
}

///|
/// Read-only proposal. It is not authority and writes no attempt or binding.
pub async fn company_task_binding_proposal(
  workspace : String,
  request_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  guard company_binding(root, flow, plan) is Some(binding) else {
    fail("Flow request has no company task snapshot")
  }
  if company_text(binding, "contract_id") != "moonproj.flow-task-binding.v2" {
    fail("Gateway approval requires a current revision snapshot")
  }
  binding
}

///|
/// The authenticated gateway owns service authentication. A JSON file alone
/// cannot prove who authenticated; this API checks exact durable correlation.
pub async fn record_company_task_approval(
  workspace : String,
  request_ref : String,
  response : Json,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, _) = load_bound_inputs(root, request_ref)
  let binding = company_task_binding_proposal(workspace, request_ref)
  let command = company_field(response, "command")
  @company_flow.validate_approval(binding, command)
  match read_optional_json_ref(root, company_approval_ref(flow)) {
    Some(existing) =>
      if existing != command {
        fail("Flow approval receipt conflicts")
      }
    None =>
      ignore(immutable_json_ref(root, company_approval_ref(flow), command))
  }
  // A crash after approval persistence is repaired by the same immutable call.
  bind_company_task(workspace, request_ref)
}

///|
async fn require_revised_company_binding(
  root : String,
  flow : FlowRequest,
  plan : @project_plan.ProjectPlanRequest,
) -> Unit {
  if company_binding(root, flow, plan) is Some(binding) &&
    company_text(binding, "contract_id") == "moonproj.flow-task-binding.v2" {
    fail(
      "Revised company tasks require authenticated gateway-execute; offline execute/reconcile cannot authorize them",
    )
  }
}

///|
#derive(Debug)
pub(all) suberror CompanyApprovalError {
  ServiceRejected(Int32)
  ServiceUnavailable
}

///|
async fn approved_service_json(
  service_uri : String,
  path : String,
  service_token : String,
  actor_id : String,
  actor_signature : String,
) -> Json {
  if service_uri.is_empty() ||
    service_token.is_empty() ||
    actor_id.is_empty() ||
    actor_signature.is_empty() {
    raise CompanyApprovalError::ServiceUnavailable
  }
  let (response, data) = @async.with_timeout(10000, () => {
    @http.get(service_uri + path, headers={
      "Authorization": "Bearer " + service_token,
      "X-Moonproj-Actor": actor_id,
      "X-Moonproj-Actor-Signature": actor_signature,
    })
  }) catch {
    _ => raise CompanyApprovalError::ServiceUnavailable
  }
  if response.code != 200 {
    raise CompanyApprovalError::ServiceRejected(response.code)
  }
  @json.parse(data.text()) catch {
    _ => raise CompanyApprovalError::ServiceUnavailable
  }
}

///|
/// The sole revised-task execution entry always obtains approval and current
/// task state from the configured authenticated service. It accepts no offline
/// verified-JSON shortcut. Credentials/signature are process inputs, never files.
pub async fn execute_approved_company_task(
  workspace : String,
  request_ref : String,
  result_ref : String,
  service_uri~ : String,
  service_token~ : String,
  actor_id~ : String,
  actor_signature~ : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  let binding = bound_company_input(root, flow, plan)
  if company_text(binding, "contract_id") != "moonproj.flow-task-binding.v2" ||
    actor_id !=
    company_text(
      company_field(company_field(binding, "snapshot"), "task"),
      "created_by",
    ) {
    fail("Approved company execution requires its exact v2 task owner")
  }
  let cached = saved_company_task_approval(workspace, request_ref)
  let task = company_text(binding, "task_id")
  let observed = approved_service_json(
    service_uri,
    "/api/company/internal/plan/tasks/" +
    task +
    "/flow-approvals/" +
    company_text(cached, "idempotency_key"),
    service_token,
    actor_id,
    actor_signature,
  )
  let persisted = company_field(observed, "command")
  @company_flow.validate_approval(binding, persisted)
  if persisted != cached {
    fail("Local approval differs from the persisted company command")
  }
  let current = approved_service_json(
    service_uri,
    "/api/company/plan/tasks/" + task + "/flow-snapshot",
    service_token,
    actor_id,
    actor_signature,
  )
  @company_flow.require_current(binding, current)
  // No durable attempt/output is created until both authenticated reads match.
  begin_attempt(root, request_ref, result_ref, flow, plan)
  complete_attempt(root, result_ref, flow, plan)
}

///|
pub async fn saved_company_task_report(
  workspace : String,
  request_ref : String,
  report_key : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  load_company_task_report(root, flow, plan, request_ref, report_key)
}

///|
/// Correlated local approval evidence. The gateway independently rereads the
/// persisted service command before execution; this file is not authentication.
pub async fn saved_company_task_approval(
  workspace : String,
  request_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  let binding = bound_company_input(root, flow, plan)
  if company_text(binding, "contract_id") != "moonproj.flow-task-binding.v2" {
    fail("Current approval requires a v2 company binding")
  }
  read_json_ref(root, company_approval_ref(flow))
}
