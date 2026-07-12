///|
fn commitment_state_name(state : CommitmentState) -> String {
  match state {
    CommitmentState::Draft => "draft"
    CommitmentState::Submitted => "submitted"
    CommitmentState::Approved => "approved"
    CommitmentState::Performed => "performed"
    CommitmentState::Settled => "settled"
    CommitmentState::Cancelled => "cancelled"
  }
}

///|
fn commitment_projection_payload(commitment : Commitment) -> String {
  Json::object({
    "commitment_id": Json::string(commitment.commitment_id),
    "principal_id": Json::string(commitment.principal_id),
    "project_scope": Json::string(commitment.project_scope),
    "counterparty_id": Json::string(commitment.counterparty_id),
    "amount_minor": Json::number(
      commitment.amount.minor.to_double(),
      repr=commitment.amount.minor.to_string(),
    ),
    "currency": Json::string(commitment.amount.currency),
    "state": Json::string(commitment_state_name(commitment.state)),
    "event_count": Json::number(
      commitment.events.length().to_double(),
      repr=commitment.events.length().to_string(),
    ),
  }).stringify()
}

///|
/// Append the current commitment snapshot to its immutable aggregate history.
/// The projection revision is authoritative: callers may persist every
/// transition or periodically persist a later aggregate snapshot.
pub fn Commitment::append_projection(
  self : Commitment,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise CommitmentError {
  if projection.aggregate_type != "commitment" ||
    projection.aggregate_id != self.commitment_id {
    raise CommitmentError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=commitment_projection_payload(self),
    source_event_id="company:commitment:" +
      self.commitment_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise CommitmentError::Projection(error)
  }
}
