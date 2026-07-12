///|
fn milestone_trigger_name(trigger : MilestoneTrigger) -> String {
  match trigger {
    MilestoneTrigger::Time => "time"
    MilestoneTrigger::Progress => "progress"
    MilestoneTrigger::Event => "event"
  }
}

///|
fn milestone_state_name(state : MilestoneState) -> String {
  match state {
    MilestoneState::Planned => "planned"
    MilestoneState::Eligible => "eligible"
    MilestoneState::Reached => "reached"
    MilestoneState::Paid => "paid"
    MilestoneState::Overdue => "overdue"
    MilestoneState::Cancelled => "cancelled"
  }
}

///|
fn milestone_projection_payload(milestone : ContractMilestone) -> String {
  Json::object({
    "milestone_id": Json::string(milestone.milestone_id),
    "commitment_id": Json::string(milestone.commitment_id),
    "principal_id": Json::string(milestone.principal_id),
    "project_scope": Json::string(milestone.project_scope),
    "sequence": Json::number(
      milestone.sequence.to_double(),
      repr=milestone.sequence.to_string(),
    ),
    "node_name": Json::string(milestone.node_name),
    "trigger": Json::string(milestone_trigger_name(milestone.trigger)),
    "plan_amount_minor": Json::number(
      milestone.plan_amount.minor.to_double(),
      repr=milestone.plan_amount.minor.to_string(),
    ),
    "plan_pct_bps": Json::number(
      milestone.plan_pct_bps.to_double(),
      repr=milestone.plan_pct_bps.to_string(),
    ),
    "actual_amount_minor": Json::number(
      milestone.actual_amount.minor.to_double(),
      repr=milestone.actual_amount.minor.to_string(),
    ),
    "currency": Json::string(milestone.plan_amount.currency),
    "state": Json::string(milestone_state_name(milestone.state)),
    "event_count": Json::number(
      milestone.events.length().to_double(),
      repr=milestone.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn ContractMilestone::append_projection(
  self : ContractMilestone,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise MilestoneError {
  if projection.aggregate_type != "contract_milestone" ||
    projection.aggregate_id != self.milestone_id {
    raise MilestoneError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=milestone_projection_payload(self),
    source_event_id="company:contract-milestone:" +
      self.milestone_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise MilestoneError::Projection(error)
  }
}
