///|
fn advance_state_name(state : AdvanceState) -> String {
  match state {
    AdvanceState::Open => "open"
    AdvanceState::PartiallyRepaid => "partially_repaid"
    AdvanceState::Repaid => "repaid"
    AdvanceState::WrittenOff => "written_off"
  }
}

///|
fn advance_projection_payload(advance : EmployeeAdvance) -> String {
  Json::object({
    "advance_id": Json::string(advance.advance_id),
    "principal_id": Json::string(advance.principal_id),
    "employee_id": Json::string(advance.employee_id),
    "amount_minor": Json::number(
      advance.amount.minor.to_double(),
      repr=advance.amount.minor.to_string(),
    ),
    "repaid_minor": Json::number(
      advance.repaid_minor.to_double(),
      repr=advance.repaid_minor.to_string(),
    ),
    "currency": Json::string(advance.amount.currency),
    "state": Json::string(advance_state_name(advance.state)),
  }).stringify()
}

///|
pub fn EmployeeAdvance::append_projection(
  self : EmployeeAdvance,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise AdvanceError {
  if projection.aggregate_type != "employee_advance" ||
    projection.aggregate_id != self.advance_id {
    raise AdvanceError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=advance_projection_payload(self),
    source_event_id="company:employee-advance:" +
      self.advance_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise AdvanceError::Projection(error)
  }
}
