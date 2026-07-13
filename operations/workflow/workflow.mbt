///|
pub(all) enum Decision {
  Approve
  Reject
} derive(Debug, Eq)

///|
pub(all) enum ProcessStatus {
  Pending
  Approved
  Rejected
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct ApprovalStep {
  step_id : String
  capability : String
  required_weight : Int
} derive(Debug, Eq)

///|
pub(all) struct WorkflowAssignment {
  assignment_id : String
  process_id : String
  step_id : String
  assignee_id : String
  principal_id : String
  scope : String
  weight : Int
} derive(Debug, Eq)

///|
/// Evidence that an assignment is attached to a process definition. The
/// attachment changes which actors are eligible for a configured step; it
/// never creates authority and it never records an approval decision.
pub(all) struct WorkflowAssignmentAttachment {
  attachment_id : String
  assignment_id : String
  process_id : String
  step_id : String
  grants_authority : Bool
  approves_instance : Bool
} derive(Debug, Eq)

///|
pub(all) struct WorkflowSlaPolicy {
  policy_id : String
  process_id : String
  step_id : String
  due_after_seconds : Int64
  escalation_actor_id : String
  scope : String
} derive(Debug, Eq)

///|
pub(all) enum WorkflowSlaState {
  Due
  Overdue
} derive(Debug, Eq)

///|
/// Observation-only escalation evidence. It never grants the escalation
/// target authority and never changes workflow approval state.
pub(all) struct WorkflowEscalationEvidence {
  escalation_id : String
  instance_id : String
  policy_id : String
  step_id : String
  escalation_actor_id : String
  due_at_epoch : Int64
  observed_at_epoch : Int64
  state : WorkflowSlaState
  notification_requested : Bool
  authority_granted : Bool
  approves_instance : Bool
} derive(Debug, Eq)

///|
pub(all) struct ProcessDefinition {
  process_id : String
  process_key : String
  steps : Array[ApprovalStep]
  assignments : Array[WorkflowAssignment]
  sla_policies : Array[WorkflowSlaPolicy]
} derive(Debug, Eq)

///|
pub(all) struct ApprovalAction {
  step_id : String
  actor_id : String
  decision : Decision
  weight : Int
  delegation_id : String?
} derive(Debug, Eq)

///|
pub(all) struct ProcessInstance {
  instance_id : String
  process_key : String
  principal_id : String
  subject_id : String
  steps : Array[ApprovalStep]
  assignments : Array[WorkflowAssignment]
  sla_policies : Array[WorkflowSlaPolicy]
  sla_evidence : Array[WorkflowEscalationEvidence]
  current_step : Int
  status : ProcessStatus
  actions : Array[ApprovalAction]
} derive(Debug, Eq)

///|
pub(all) suberror WorkflowError {
  EmptyIdentifier
  EmptyStep
  UnknownStep
  EmptyAssignment
  AssignmentProcessMismatch
  DuplicateAssignment
  UnknownAssignment
  SlaProcessMismatch
  UnknownSlaPolicy
  DuplicateSlaPolicy
  InvalidSla
  SlaNotCurrent
  SlaEvidenceIdentity
  DuplicateSlaEvidence
  NotAssigned
  InvalidWeight
  DuplicateStep
  InvalidState
  WrongStep
  DuplicateAction
  ProjectionIdentity
  Projection(@store.ProjectionError)
  Delegation(@access.AccessError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn ProcessDefinition::new(
  process_id~ : String,
  process_key~ : String,
  steps~ : Array[ApprovalStep],
) -> ProcessDefinition raise WorkflowError {
  if process_id.trim() == "" || process_key.trim() == "" {
    raise WorkflowError::EmptyIdentifier
  }
  if steps.length() == 0 {
    raise WorkflowError::EmptyStep
  }
  for step in steps {
    if step.step_id.trim() == "" || step.capability.trim() == "" {
      raise WorkflowError::EmptyStep
    }
    if step.required_weight <= 0 {
      raise WorkflowError::InvalidWeight
    }
  }
  for i in 0..<steps.length() {
    for j in (i + 1)..<steps.length() {
      if steps[i].step_id == steps[j].step_id {
        raise WorkflowError::DuplicateStep
      }
    }
  }
  { process_id, process_key, steps, assignments: [], sla_policies: [] }
}

///|
/// Attach an explicit assignee to a configured workflow step. Assignment is
/// workflow configuration, not a role grant; approval execution still
/// validates its own capability and authority at decision time.
pub fn ProcessDefinition::assign_step(
  self : ProcessDefinition,
  assignment_id~ : String,
  step_id~ : String,
  assignee_id~ : String,
  principal_id~ : String,
  scope~ : String,
  weight~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WorkflowAssignment raise WorkflowError {
  if assignment_id.trim() == "" ||
    step_id.trim() == "" ||
    assignee_id.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" {
    raise WorkflowError::EmptyAssignment
  }
  if weight <= 0 {
    raise WorkflowError::InvalidWeight
  }
  let mut found = false
  for step in self.steps {
    if step.step_id == step_id {
      found = true
    }
  }
  if !found {
    raise WorkflowError::UnknownStep
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="workflow:assignment:add",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise WorkflowError::NotAuthorized(error)
  }
  {
    assignment_id,
    process_id: self.process_id,
    step_id,
    assignee_id,
    principal_id,
    scope,
    weight,
  }
}

///|
/// Attach a previously authorized assignment to its process definition. This
/// is the opt-in switch that makes assignment enforcement visible to new
/// process instances; it does not issue a role or capability grant.
pub fn ProcessDefinition::attach_assignment(
  self : ProcessDefinition,
  assignment : WorkflowAssignment,
) -> ProcessDefinition raise WorkflowError {
  if assignment.process_id != self.process_id {
    raise WorkflowError::AssignmentProcessMismatch
  }
  let mut found_step = false
  for step in self.steps {
    if step.step_id == assignment.step_id {
      found_step = true
    }
  }
  if !found_step {
    raise WorkflowError::UnknownStep
  }
  for existing in self.assignments {
    if existing.assignment_id == assignment.assignment_id {
      raise WorkflowError::DuplicateAssignment
    }
  }
  let assignments = self.assignments.copy()
  assignments.push(assignment)
  { ..self, assignments, }
}

///|
/// Add an explicit due-time and escalation target to a workflow step. The
/// policy is configuration only; observing an overdue step never issues a
/// grant or approves an instance.
pub fn ProcessDefinition::add_sla_policy(
  self : ProcessDefinition,
  policy : WorkflowSlaPolicy,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProcessDefinition raise WorkflowError {
  if policy.policy_id.trim() == "" ||
    policy.step_id.trim() == "" ||
    policy.escalation_actor_id.trim() == "" ||
    policy.scope.trim() == "" {
    raise WorkflowError::InvalidSla
  }
  if policy.process_id != self.process_id {
    raise WorkflowError::SlaProcessMismatch
  }
  if policy.due_after_seconds <= 0L {
    raise WorkflowError::InvalidSla
  }
  let mut step_found = false
  for step in self.steps {
    if step.step_id == policy.step_id {
      step_found = true
    }
  }
  if !step_found {
    raise WorkflowError::UnknownStep
  }
  for existing in self.sla_policies {
    if existing.policy_id == policy.policy_id {
      raise WorkflowError::DuplicateSlaPolicy
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="workflow:sla:add",
    scope=policy.scope,
    amount_minor=0,
  ) catch {
    error => raise WorkflowError::NotAuthorized(error)
  }
  let sla_policies = self.sla_policies.copy()
  sla_policies.push(policy)
  { ..self, sla_policies, }
}

///|
/// Return durable identity evidence for an assignment that is already
/// attached to this definition. This is deliberately separate from
/// `AuthorityGrant`: attachment eligibility and decision capability are two
/// different controls.
pub fn ProcessDefinition::assignment_attachment(
  self : ProcessDefinition,
  assignment_id~ : String,
) -> WorkflowAssignmentAttachment raise WorkflowError {
  if assignment_id.trim() == "" {
    raise WorkflowError::EmptyAssignment
  }
  for assignment in self.assignments {
    if assignment.assignment_id == assignment_id {
      return {
        attachment_id: "workflow-attachment:" + assignment.assignment_id,
        assignment_id: assignment.assignment_id,
        process_id: assignment.process_id,
        step_id: assignment.step_id,
        grants_authority: false,
        approves_instance: false,
      }
    }
  }
  raise WorkflowError::UnknownAssignment
}

///|
pub fn start_process(
  definition : ProcessDefinition,
  instance_id~ : String,
  principal_id~ : String,
  subject_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProcessInstance raise WorkflowError {
  if instance_id.trim() == "" ||
    principal_id.trim() == "" ||
    subject_id.trim() == "" {
    raise WorkflowError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="workflow:start",
    scope=subject_id,
    amount_minor=0,
  ) catch {
    error => raise WorkflowError::NotAuthorized(error)
  }
  {
    instance_id,
    process_key: definition.process_key,
    principal_id,
    subject_id,
    steps: definition.steps.copy(),
    assignments: definition.assignments.copy(),
    sla_policies: definition.sla_policies.copy(),
    sla_evidence: [],
    current_step: 0,
    status: ProcessStatus::Pending,
    actions: [],
  }
}

///|
fn sla_state_name(state : WorkflowSlaState) -> String {
  match state {
    WorkflowSlaState::Due => "due"
    WorkflowSlaState::Overdue => "overdue"
  }
}

///|
/// Evaluate a policy at an explicit observation time. This pure operation
/// produces deterministic evidence and has no notification or approval side
/// effects.
pub fn ProcessInstance::evaluate_sla(
  self : ProcessInstance,
  policy_id~ : String,
  started_at_epoch~ : Int64,
  observed_at_epoch~ : Int64,
) -> WorkflowEscalationEvidence raise WorkflowError {
  if policy_id.trim() == "" ||
    started_at_epoch < 0L ||
    observed_at_epoch < started_at_epoch {
    raise WorkflowError::InvalidSla
  }
  if self.status != ProcessStatus::Pending ||
    self.current_step >= self.steps.length() {
    raise WorkflowError::SlaNotCurrent
  }
  let mut selected : WorkflowSlaPolicy? = None
  for policy in self.sla_policies {
    if policy.policy_id == policy_id {
      selected = Some(policy)
    }
  }
  let policy = match selected {
    Some(value) => value
    None => raise WorkflowError::UnknownSlaPolicy
  }
  if self.steps[self.current_step].step_id != policy.step_id {
    raise WorkflowError::SlaNotCurrent
  }
  let due_at_epoch = started_at_epoch + policy.due_after_seconds
  if due_at_epoch < started_at_epoch {
    raise WorkflowError::InvalidSla
  }
  let state = if observed_at_epoch >= due_at_epoch {
    WorkflowSlaState::Overdue
  } else {
    WorkflowSlaState::Due
  }
  {
    escalation_id: "workflow-escalation:" +
    self.instance_id +
    ":" +
    policy.policy_id +
    ":" +
    observed_at_epoch.to_string(),
    instance_id: self.instance_id,
    policy_id: policy.policy_id,
    step_id: policy.step_id,
    escalation_actor_id: policy.escalation_actor_id,
    due_at_epoch,
    observed_at_epoch,
    state,
    notification_requested: state == WorkflowSlaState::Overdue,
    authority_granted: false,
    approves_instance: false,
  }
}

///|
/// Persist an SLA observation under a separate observation capability. This
/// does not change status, current step, actions, or authority grants.
pub fn ProcessInstance::record_sla_evidence(
  self : ProcessInstance,
  evidence : WorkflowEscalationEvidence,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProcessInstance raise WorkflowError {
  if evidence.instance_id != self.instance_id ||
    evidence.escalation_id.trim() == "" ||
    evidence.policy_id.trim() == "" ||
    evidence.step_id.trim() == "" ||
    evidence.escalation_actor_id.trim() == "" ||
    evidence.due_at_epoch < 0L ||
    evidence.observed_at_epoch < 0L ||
    (
      evidence.state == WorkflowSlaState::Due &&
      evidence.observed_at_epoch >= evidence.due_at_epoch
    ) ||
    (
      evidence.state == WorkflowSlaState::Overdue &&
      evidence.observed_at_epoch < evidence.due_at_epoch
    ) ||
    evidence.notification_requested !=
    (evidence.state == WorkflowSlaState::Overdue) ||
    evidence.authority_granted ||
    evidence.approves_instance {
    raise WorkflowError::SlaEvidenceIdentity
  }
  let mut policy_found = false
  for policy in self.sla_policies {
    if policy.policy_id == evidence.policy_id &&
      policy.step_id == evidence.step_id &&
      policy.escalation_actor_id == evidence.escalation_actor_id {
      policy_found = true
    }
  }
  if !policy_found {
    raise WorkflowError::SlaEvidenceIdentity
  }
  for existing in self.sla_evidence {
    if existing.escalation_id == evidence.escalation_id {
      raise WorkflowError::DuplicateSlaEvidence
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="workflow:sla:observe",
    scope=self.subject_id,
    amount_minor=0,
  ) catch {
    error => raise WorkflowError::NotAuthorized(error)
  }
  let sla_evidence = self.sla_evidence.copy()
  sla_evidence.push(evidence)
  { ..self, sla_evidence, }
}

///|
fn weight_for_step(instance : ProcessInstance, step_id : String) -> Int {
  let mut total = 0
  for action in instance.actions {
    if action.step_id == step_id && action.decision == Decision::Approve {
      total += action.weight
    }
  }
  total
}

///|
fn has_action(
  instance : ProcessInstance,
  step_id : String,
  actor_id : String,
) -> Bool {
  for action in instance.actions {
    if action.step_id == step_id && action.actor_id == actor_id {
      return true
    }
  }
  false
}

///|
fn assignment_weights(
  instance : ProcessInstance,
  step_id : String,
  actor_id : String,
) -> (Bool, Int) {
  let mut has_assignments = false
  let mut actor_weight = 0
  for assignment in instance.assignments {
    if assignment.step_id == step_id {
      has_assignments = true
      if assignment.assignee_id == actor_id {
        actor_weight += assignment.weight
      }
    }
  }
  (has_assignments, actor_weight)
}

///|
pub fn ProcessInstance::decide(
  self : ProcessInstance,
  step_id~ : String,
  decision~ : Decision,
  weight~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProcessInstance raise WorkflowError {
  self.decide_with_source(
    step_id~,
    decision~,
    weight~,
    actor_id~,
    grant~,
    delegation_id=None,
  )
}

///|
/// Decide through a separately recorded, effective-dated delegation. The
/// access directory issues a bounded grant; the workflow still enforces the
/// attached-assignee check and the step capability. Delegation is evidence of
/// how authority was obtained, not a workflow assignment or approval itself.
pub fn ProcessInstance::decide_delegated(
  self : ProcessInstance,
  step_id~ : String,
  decision~ : Decision,
  weight~ : Int,
  actor_id~ : String,
  delegation_id~ : String,
  at_epoch~ : Int64,
  directory~ : @access.AccessDirectory,
) -> ProcessInstance raise WorkflowError {
  if delegation_id.trim() == "" {
    raise WorkflowError::EmptyIdentifier
  }
  let grant = directory.issue_delegated_grant(
    delegation_id~,
    requester_id=actor_id,
    at_epoch~,
    amount_minor=0L,
  ) catch {
    error => raise WorkflowError::Delegation(error)
  }
  self.decide_with_source(
    step_id~,
    decision~,
    weight~,
    actor_id~,
    grant~,
    delegation_id=Some(delegation_id),
  )
}

///|
fn ProcessInstance::decide_with_source(
  self : ProcessInstance,
  step_id~ : String,
  decision~ : Decision,
  weight~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
  delegation_id~ : String?,
) -> ProcessInstance raise WorkflowError {
  if self.status != ProcessStatus::Pending ||
    self.current_step >= self.steps.length() {
    raise WorkflowError::InvalidState
  }
  if weight <= 0 {
    raise WorkflowError::InvalidWeight
  }
  let step = self.steps[self.current_step]
  if step.step_id != step_id {
    raise WorkflowError::WrongStep
  }
  let (has_assignments, actor_weight) = assignment_weights(
    self, step_id, actor_id,
  )
  if has_assignments && actor_weight == 0 {
    raise WorkflowError::NotAssigned
  }
  if actor_weight > 0 && weight > actor_weight {
    raise WorkflowError::InvalidWeight
  }
  if has_action(self, step_id, actor_id) {
    raise WorkflowError::DuplicateAction
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability=step.capability,
    scope=self.subject_id,
    amount_minor=0,
  ) catch {
    error => raise WorkflowError::NotAuthorized(error)
  }
  let actions = self.actions.copy()
  actions.push({ step_id, actor_id, decision, weight, delegation_id })
  match decision {
    Decision::Reject => { ..self, status: ProcessStatus::Rejected, actions }
    Decision::Approve => {
      let total = weight_for_step({ ..self, actions, }, step_id)
      if total < step.required_weight {
        { ..self, actions, }
      } else if self.current_step + 1 >= self.steps.length() {
        { ..self, status: ProcessStatus::Approved, actions }
      } else {
        { ..self, current_step: self.current_step + 1, actions }
      }
    }
  }
}
