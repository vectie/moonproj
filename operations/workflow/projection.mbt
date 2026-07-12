///|
fn decision_name(decision : Decision) -> String {
  match decision {
    Decision::Approve => "approve"
    Decision::Reject => "reject"
  }
}

///|
fn process_status_name(status : ProcessStatus) -> String {
  match status {
    ProcessStatus::Pending => "pending"
    ProcessStatus::Approved => "approved"
    ProcessStatus::Rejected => "rejected"
    ProcessStatus::Cancelled => "cancelled"
  }
}

///|
fn steps_json(steps : Array[ApprovalStep]) -> Json {
  let values : Array[Json] = []
  for step in steps {
    values.push(
      Json::object({
        "step_id": Json::string(step.step_id),
        "capability": Json::string(step.capability),
        "required_weight": Json::number(
          step.required_weight.to_double(),
          repr=step.required_weight.to_string(),
        ),
      }),
    )
  }
  Json::array(values)
}

///|
fn assignments_json(assignments : Array[WorkflowAssignment]) -> Json {
  let values : Array[Json] = []
  for assignment in assignments {
    values.push(
      Json::object({
        "assignment_id": Json::string(assignment.assignment_id),
        "process_id": Json::string(assignment.process_id),
        "step_id": Json::string(assignment.step_id),
        "assignee_id": Json::string(assignment.assignee_id),
        "principal_id": Json::string(assignment.principal_id),
        "scope": Json::string(assignment.scope),
        "weight": Json::number(
          assignment.weight.to_double(),
          repr=assignment.weight.to_string(),
        ),
      }),
    )
  }
  Json::array(values)
}

///|
fn process_definition_payload(definition : ProcessDefinition) -> String {
  Json::object({
    "process_id": Json::string(definition.process_id),
    "process_key": Json::string(definition.process_key),
    "steps": steps_json(definition.steps),
    "assignments": assignments_json(definition.assignments),
  }).stringify()
}

///|
pub fn ProcessDefinition::append_projection(
  self : ProcessDefinition,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise WorkflowError {
  if projection.aggregate_type != "process_definition" ||
    projection.aggregate_id != self.process_id {
    raise WorkflowError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=process_definition_payload(self),
    source_event_id="company:workflow-definition:" +
      self.process_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise WorkflowError::Projection(error)
  }
}

///|
fn workflow_assignment_projection_payload(
  assignment : WorkflowAssignment,
) -> String {
  Json::object({
    "assignment_id": Json::string(assignment.assignment_id),
    "process_id": Json::string(assignment.process_id),
    "step_id": Json::string(assignment.step_id),
    "assignee_id": Json::string(assignment.assignee_id),
    "principal_id": Json::string(assignment.principal_id),
    "scope": Json::string(assignment.scope),
    "weight": Json::number(
      assignment.weight.to_double(),
      repr=assignment.weight.to_string(),
    ),
  }).stringify()
}

///|
pub fn WorkflowAssignment::append_projection(
  self : WorkflowAssignment,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise WorkflowError {
  if projection.aggregate_type != "workflow_assignment" ||
    projection.aggregate_id != self.assignment_id {
    raise WorkflowError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=workflow_assignment_projection_payload(self),
    source_event_id="company:workflow-assignment:" +
      self.assignment_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise WorkflowError::Projection(error)
  }
}

///|
fn actions_json(actions : Array[ApprovalAction]) -> Json {
  let values : Array[Json] = []
  for action in actions {
    values.push(
      Json::object({
        "step_id": Json::string(action.step_id),
        "actor_id": Json::string(action.actor_id),
        "decision": Json::string(decision_name(action.decision)),
        "weight": Json::number(
          action.weight.to_double(),
          repr=action.weight.to_string(),
        ),
      }),
    )
  }
  Json::array(values)
}

///|
fn process_instance_payload(instance : ProcessInstance) -> String {
  Json::object({
    "instance_id": Json::string(instance.instance_id),
    "process_key": Json::string(instance.process_key),
    "principal_id": Json::string(instance.principal_id),
    "subject_id": Json::string(instance.subject_id),
    "current_step": Json::number(
      instance.current_step.to_double(),
      repr=instance.current_step.to_string(),
    ),
    "status": Json::string(process_status_name(instance.status)),
    "steps": steps_json(instance.steps),
    "assignments": assignments_json(instance.assignments),
    "actions": actions_json(instance.actions),
  }).stringify()
}

///|
pub fn ProcessInstance::append_projection(
  self : ProcessInstance,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise WorkflowError {
  if projection.aggregate_type != "workflow_instance" ||
    projection.aggregate_id != self.instance_id {
    raise WorkflowError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=process_instance_payload(self),
    source_event_id="company:workflow-instance:" +
      self.instance_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise WorkflowError::Projection(error)
  }
}
