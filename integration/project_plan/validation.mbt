///|
fn invalid(message : String) -> ProjectPlanCapabilityError {
  ProjectPlanCapabilityError::Invalid(message)
}

///|
fn non_blank(value : String) -> Bool {
  !value.trim().is_empty()
}

///|
fn unique_non_blank(values : Array[String]) -> Bool {
  let seen : Map[String, Bool] = Map([])
  for value in values {
    if !non_blank(value) || seen.contains(value) {
      return false
    }
    seen[value] = true
  }
  true
}

///|
fn safe_artifact_ref(reference : String) -> Bool {
  let normalized = reference.trim().replace(old="\\", new="/")
  !normalized.is_empty() &&
  !normalized.has_prefix("/") &&
  !normalized
  .split("/")
  .any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn sha256_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].iter().all(ch => ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f'))
}

///|
fn canonical_date(value : String) -> Bool {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    return false
  }
  try @time.PlainDate::from_str(value) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn canonical_utc_timestamp(value : String) -> Bool {
  if value.length() != 20 ||
    value[4] != '-' ||
    value[7] != '-' ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != 'Z' {
    return false
  }
  try @time.PlainDateTime::from_str(value[0:19]) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn owner_ids(request : ProjectPlanRequest) -> Array[String] {
  request.owners.map(owner => owner.owner_id)
}

///|
fn task_ids(request : ProjectPlanRequest) -> Array[String] {
  request.tasks.map(task => task.task_id)
}

///|
fn milestone_ids(request : ProjectPlanRequest) -> Array[String] {
  request.milestones.map(milestone => milestone.milestone_id)
}

///|
fn gate_ids(request : ProjectPlanRequest) -> Array[String] {
  request.acceptance_gates.map(gate => gate.gate_id)
}

///|
fn evidence_refs(request : ProjectPlanRequest) -> Array[String] {
  request.source_evidence.map(evidence => evidence.artifact_ref)
}

///|
fn task_by_id(request : ProjectPlanRequest, task_id : String) -> PlanTaskInput? {
  for task in request.tasks {
    if task.task_id == task_id {
      return Some(task)
    }
  }
  None
}

///|
fn milestone_by_id(
  request : ProjectPlanRequest,
  milestone_id : String,
) -> PlanMilestone? {
  for milestone in request.milestones {
    if milestone.milestone_id == milestone_id {
      return Some(milestone)
    }
  }
  None
}

///|
fn validate_identity(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  if request.contract_id != "moonproj.project-plan-request.v1" {
    raise invalid("contract_id must be moonproj.project-plan-request.v1")
  }
  if request.operation_ref != operation_ref() {
    raise invalid("operation_ref must exactly match \{operation_ref()}")
  }
  if !non_blank(request.plan_request_id) ||
    !non_blank(request.project.project_id) ||
    !non_blank(request.project.principal_id) ||
    !non_blank(request.project.code) ||
    !non_blank(request.project.name) ||
    !non_blank(request.prepared_by) {
    raise invalid("plan and project identity fields must be non-empty")
  }
  if !canonical_utc_timestamp(request.prepared_at) {
    raise invalid("prepared_at must be canonical UTC")
  }
}

///|
fn validate_owners(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let ids = owner_ids(request)
  if ids.is_empty() || !unique_non_blank(ids) {
    raise invalid("owners must have unique non-empty ids")
  }
  for owner in request.owners {
    if !non_blank(owner.display_name) || !non_blank(owner.role) {
      raise invalid("owner display_name and role must be non-empty")
    }
  }
  if !ids.contains(request.prepared_by) {
    raise invalid("prepared_by must name a declared owner")
  }
}

///|
fn validate_evidence(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let refs = evidence_refs(request)
  if refs.is_empty() || !unique_non_blank(refs) {
    raise invalid("source evidence must contain unique artifact refs")
  }
  for evidence in request.source_evidence {
    if !safe_artifact_ref(evidence.artifact_ref) ||
      !sha256_digest(evidence.digest) ||
      !canonical_utc_timestamp(evidence.observed_at) ||
      !non_blank(evidence.kind) {
      raise invalid(
        "source evidence requires a safe ref, sha256 digest, UTC timestamp and kind",
      )
    }
  }
}

///|
fn validate_budget(
  request : ProjectPlanRequest,
) -> Int64 raise ProjectPlanCapabilityError {
  let budget = request.budget_envelope
  if budget.currency.length() != 3 ||
    budget.currency != budget.currency.to_upper() ||
    budget.limit_minor < 0L ||
    budget.contingency_minor < 0L ||
    budget.contingency_minor > budget.limit_minor {
    raise invalid(
      "budget envelope must use a three-letter currency and non-negative bounds",
    )
  }
  let mut total = 0L
  for task in request.tasks {
    if task.planned_cost_minor < 0L ||
      task.planned_cost_minor > budget.limit_minor - total {
      raise invalid("planned task costs exceed the budget envelope")
    }
    total += task.planned_cost_minor
  }
  if budget.contingency_minor > budget.limit_minor - total {
    raise invalid(
      "planned task costs plus contingency exceed the budget envelope",
    )
  }
  total
}

///|
fn validate_tasks(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let owners = owner_ids(request)
  let tasks = task_ids(request)
  let milestones = milestone_ids(request)
  let gates = gate_ids(request)
  let evidence = evidence_refs(request)
  if tasks.is_empty() || !unique_non_blank(tasks) {
    raise invalid("tasks must have unique non-empty ids")
  }
  for task in request.tasks {
    if !non_blank(task.name) ||
      !owners.contains(task.owner_id) ||
      !milestones.contains(task.milestone_id) ||
      !unique_non_blank(task.dependencies) ||
      task.acceptance_gate_ids.is_empty() ||
      !unique_non_blank(task.acceptance_gate_ids) ||
      task.source_evidence_refs.is_empty() ||
      !unique_non_blank(task.source_evidence_refs) {
      raise invalid(
        "task ownership, milestone, dependency, gate or evidence binding is invalid",
      )
    }
    for dependency in task.dependencies {
      if !tasks.contains(dependency) {
        raise invalid("task dependency does not name a declared task")
      }
    }
    for gate in task.acceptance_gate_ids {
      if !gates.contains(gate) {
        raise invalid("task acceptance gate does not exist")
      }
    }
    for reference in task.source_evidence_refs {
      if !evidence.contains(reference) {
        raise invalid("task source evidence is not declared")
      }
    }
  }
}

///|
fn validate_milestones(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let owners = owner_ids(request)
  let tasks = task_ids(request)
  let milestones = milestone_ids(request)
  let gates = gate_ids(request)
  if milestones.is_empty() || !unique_non_blank(milestones) {
    raise invalid("milestones must have unique non-empty ids")
  }
  for milestone in request.milestones {
    if !non_blank(milestone.name) ||
      !owners.contains(milestone.owner_id) ||
      !canonical_date(milestone.target_date) ||
      milestone.task_ids.is_empty() ||
      !unique_non_blank(milestone.task_ids) ||
      milestone.acceptance_gate_ids.is_empty() ||
      !unique_non_blank(milestone.acceptance_gate_ids) {
      raise invalid(
        "milestone identity, owner, date, task or gate binding is invalid",
      )
    }
    for task_id in milestone.task_ids {
      if !tasks.contains(task_id) {
        raise invalid("milestone task does not exist")
      }
      let task = task_by_id(request, task_id)
      guard task is Some(task) && task.milestone_id == milestone.milestone_id else {
        raise invalid("task and milestone mappings must agree")
      }
    }
    for gate in milestone.acceptance_gate_ids {
      if !gates.contains(gate) {
        raise invalid("milestone acceptance gate does not exist")
      }
    }
  }
  for task in request.tasks {
    let milestone = milestone_by_id(request, task.milestone_id)
    guard milestone is Some(milestone) &&
      milestone.task_ids.contains(task.task_id) else {
      raise invalid("every task must appear in its declared milestone")
    }
  }
}

///|
fn validate_gates(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let owners = owner_ids(request)
  let tasks = task_ids(request)
  let milestones = milestone_ids(request)
  let gates = gate_ids(request)
  if gates.is_empty() || !unique_non_blank(gates) {
    raise invalid("acceptance gates must have unique non-empty ids")
  }
  for gate in request.acceptance_gates {
    if !non_blank(gate.name) ||
      !owners.contains(gate.owner_id) ||
      gate.criteria.is_empty() ||
      !unique_non_blank(gate.criteria) ||
      gate.required_evidence.is_empty() ||
      !unique_non_blank(gate.required_evidence) {
      raise invalid(
        "acceptance gate ownership, criteria or evidence requirement is invalid",
      )
    }
    match gate.scope_type {
      "project" =>
        if gate.scope_id != request.project.project_id {
          raise invalid("project gate must scope to the request project")
        }
      "task" =>
        if !tasks.contains(gate.scope_id) {
          raise invalid("task gate scope does not exist")
        }
      "milestone" =>
        if !milestones.contains(gate.scope_id) {
          raise invalid("milestone gate scope does not exist")
        }
      _ => raise invalid("gate scope_type must be project, task or milestone")
    }
  }
}

///|
fn validate_risks(
  request : ProjectPlanRequest,
) -> Unit raise ProjectPlanCapabilityError {
  let owners = owner_ids(request)
  let tasks = task_ids(request)
  let evidence = evidence_refs(request)
  let risk_ids = request.risks.map(risk => risk.risk_id)
  if !unique_non_blank(risk_ids) {
    raise invalid("risks must have unique non-empty ids")
  }
  for risk in request.risks {
    if !non_blank(risk.summary) ||
      !non_blank(risk.mitigation) ||
      !owners.contains(risk.owner_id) ||
      !["low", "medium", "high", "critical"].contains(risk.severity) ||
      !unique_non_blank(risk.related_task_ids) ||
      risk.source_evidence_refs.is_empty() ||
      !unique_non_blank(risk.source_evidence_refs) {
      raise invalid(
        "risk identity, owner, severity, mitigation or bindings are invalid",
      )
    }
    for task in risk.related_task_ids {
      if !tasks.contains(task) {
        raise invalid("risk task binding does not exist")
      }
    }
    for reference in risk.source_evidence_refs {
      if !evidence.contains(reference) {
        raise invalid("risk source evidence is not declared")
      }
    }
  }
}

///|
pub fn validate_request(
  request : ProjectPlanRequest,
) -> Int64 raise ProjectPlanCapabilityError {
  validate_identity(request)
  validate_owners(request)
  validate_evidence(request)
  validate_tasks(request)
  validate_milestones(request)
  validate_gates(request)
  validate_risks(request)
  validate_budget(request)
}

///|
pub fn decode_request(
  value : Json,
) -> ProjectPlanRequest raise ProjectPlanCapabilityError {
  let request : ProjectPlanRequest = @json.from_json(value) catch {
    _ => raise invalid("project plan request does not match the typed contract")
  }
  ignore(validate_request(request))
  request
}
