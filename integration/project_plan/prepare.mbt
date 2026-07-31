///|
fn planning_grant(
  request : ProjectPlanRequest,
  capability : String,
  max_amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "suite-plan-proposal:\{request.plan_request_id}:\{capability}",
    principal_id: request.project.principal_id,
    actor_id: request.prepared_by,
    capability,
    scope: "project:\{request.project.project_id}",
    max_amount_minor,
    active: true,
  }
}

///|
pub fn prepare(
  request : ProjectPlanRequest,
  attempt_id : String,
  request_digest : String,
  recorded_at : String,
) -> ProjectPlanArtifact raise ProjectPlanCapabilityError {
  let planned_total = validate_request(request)
  if !non_blank(attempt_id) || !sha256_digest(request_digest) {
    raise invalid("attempt_id and request_digest must be bound")
  }
  if !canonical_utc_timestamp(recorded_at) {
    raise invalid("recorded_at must be canonical UTC")
  }
  let project = @project.Project::new(
    project_id=request.project.project_id,
    principal_id=request.project.principal_id,
    code=request.project.code,
    name=request.project.name,
    actor_id=request.prepared_by,
    grant=planning_grant(request, "project:create", 0L),
  ) catch {
    error => raise ProjectPlanCapabilityError::Project(error)
  }
  let project = project.advance(
    @project.ProjectStage::Planning,
    actor_id=request.prepared_by,
    grant=planning_grant(request, "project:advance", 0L),
  ) catch {
    error => raise ProjectPlanCapabilityError::Project(error)
  }
  let mut plan = @project.ProjectPlan::new(project)
  for task in request.tasks {
    let cost = @finance.Money::new(
      minor=task.planned_cost_minor,
      currency=request.budget_envelope.currency,
    ) catch {
      error => raise ProjectPlanCapabilityError::Money(error)
    }
    plan = plan.add_task(
      task_id=task.task_id,
      name=task.name,
      planned_cost=Some(cost),
      dependencies=task.dependencies,
      actor_id=request.prepared_by,
      grant=planning_grant(
        request,
        "project:task:add",
        request.budget_envelope.limit_minor,
      ),
    ) catch {
      error => raise ProjectPlanCapabilityError::Plan(error)
    }
  }
  let prepared_tasks : Array[PreparedTask] = []
  for index in 0..<plan.tasks.length() {
    let task = plan.tasks[index]
    let source = request.tasks[index]
    prepared_tasks.push({
      task_id: task.task_id,
      name: task.name,
      owner_id: source.owner_id,
      milestone_id: source.milestone_id,
      planned_cost_minor: match task.planned_cost {
        Some(value) => value.minor
        None => 0L
      },
      currency: request.budget_envelope.currency,
      dependencies: task.dependencies.copy(),
      acceptance_gate_ids: source.acceptance_gate_ids.copy(),
      source_evidence_refs: source.source_evidence_refs.copy(),
      progress_bps: task.progress_bps,
      state: "planned",
    })
  }
  {
    contract_id: "moonproj.project-plan-artifact.v1",
    operation_ref: operation_ref(),
    input_schema_ref: input_schema_ref(),
    output_schema_ref: output_schema_ref(),
    plan_request_id: request.plan_request_id,
    attempt_id,
    request_digest,
    project: {
      project_id: request.project.project_id,
      principal_id: request.project.principal_id,
      code: request.project.code,
      name: request.project.name,
      stage: "planning",
      state: "draft",
    },
    owners: request.owners.copy(),
    budget: {
      currency: request.budget_envelope.currency,
      limit_minor: request.budget_envelope.limit_minor,
      contingency_minor: request.budget_envelope.contingency_minor,
      planned_total_minor: planned_total,
      unallocated_minor: request.budget_envelope.limit_minor -
      planned_total -
      request.budget_envelope.contingency_minor,
    },
    tasks: prepared_tasks,
    milestones: request.milestones.copy(),
    risks: request.risks.copy(),
    acceptance_gates: request.acceptance_gates.copy(),
    source_evidence: request.source_evidence.copy(),
    workflow: {
      status: "pending_review",
      current_gate: "named-human-plan-review",
      review_required: true,
      accepted: false,
      next_actions: [
        "review scope, dependencies, owners, budget and risks", "accept or reject each milestone gate with named-human evidence",
        "authorize execution separately after plan acceptance",
      ],
    },
    authority_effects: {
      spend_authorized: false,
      accounting_posted: false,
      payment_released: false,
      contract_signed: false,
      work_executed: false,
    },
    claim_ceiling: "digital-artifact",
    recorded_at,
  }
}

///|
pub fn validate_artifact(
  artifact : ProjectPlanArtifact,
) -> Unit raise ProjectPlanCapabilityError {
  if artifact.contract_id != "moonproj.project-plan-artifact.v1" ||
    artifact.operation_ref != operation_ref() ||
    artifact.input_schema_ref != input_schema_ref() ||
    artifact.output_schema_ref != output_schema_ref() ||
    artifact.workflow.status != "pending_review" ||
    !artifact.workflow.review_required ||
    artifact.workflow.accepted ||
    artifact.claim_ceiling != "digital-artifact" ||
    artifact.authority_effects.spend_authorized ||
    artifact.authority_effects.accounting_posted ||
    artifact.authority_effects.payment_released ||
    artifact.authority_effects.contract_signed ||
    artifact.authority_effects.work_executed {
    raise invalid("project plan artifact exceeds its planning-only contract")
  }
}

///|
pub fn decode_artifact(
  value : Json,
) -> ProjectPlanArtifact raise ProjectPlanCapabilityError {
  let artifact : ProjectPlanArtifact = @json.from_json(value) catch {
    _ =>
      raise invalid("project plan artifact does not match the typed contract")
  }
  validate_artifact(artifact)
  artifact
}
