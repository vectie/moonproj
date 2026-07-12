///|
fn settlement_state_name(state : SettlementState) -> String {
  match state {
    SettlementState::Requested => "requested"
    SettlementState::Approved => "approved"
    SettlementState::Released => "released"
    SettlementState::Reconciled => "reconciled"
    SettlementState::Rejected => "rejected"
  }
}

///|
fn settlement_projection_payload(settlement : Settlement) -> String {
  Json::object({
    "settlement_id": Json::string(settlement.settlement_id),
    "commitment_id": Json::string(settlement.commitment_id),
    "milestone_id": match settlement.milestone_id {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "principal_id": Json::string(settlement.principal_id),
    "project_scope": Json::string(settlement.project_scope),
    "amount_minor": Json::number(
      settlement.amount.minor.to_double(),
      repr=settlement.amount.minor.to_string(),
    ),
    "currency": Json::string(settlement.amount.currency),
    "state": Json::string(settlement_state_name(settlement.state)),
    "event_count": Json::number(
      settlement.events.length().to_double(),
      repr=settlement.events.length().to_string(),
    ),
  }).stringify()
}

///|
/// Persist a settlement snapshot without making the record store part of the
/// settlement state machine. The projection revision is independent from the
/// number of in-memory events so callers may checkpoint at any cadence.
pub fn Settlement::append_projection(
  self : Settlement,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise SettlementError {
  if projection.aggregate_type != "settlement" ||
    projection.aggregate_id != self.settlement_id {
    raise SettlementError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=settlement_projection_payload(self),
    source_event_id="company:settlement:" +
      self.settlement_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise SettlementError::Projection(error)
  }
}
