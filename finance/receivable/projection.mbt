///|
fn receivable_state_name(state : ReceivableState) -> String {
  match state {
    ReceivableState::Open => "open"
    ReceivableState::PartiallyCollected => "partially_collected"
    ReceivableState::Collected => "collected"
    ReceivableState::WrittenOff => "written_off"
  }
}

///|
fn receivable_projection_payload(receivable : Receivable) -> String {
  Json::object({
    "receivable_id": Json::string(receivable.receivable_id),
    "source_id": Json::string(receivable.source_id),
    "principal_id": Json::string(receivable.principal_id),
    "customer_id": Json::string(receivable.customer_id),
    "amount_minor": Json::number(
      receivable.amount.minor.to_double(),
      repr=receivable.amount.minor.to_string(),
    ),
    "collected_minor": Json::number(
      receivable.collected_minor.to_double(),
      repr=receivable.collected_minor.to_string(),
    ),
    "currency": Json::string(receivable.amount.currency),
    "state": Json::string(receivable_state_name(receivable.state)),
  }).stringify()
}

///|
pub fn Receivable::append_projection(
  self : Receivable,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ReceivableError {
  if projection.aggregate_type != "receivable" ||
    projection.aggregate_id != self.receivable_id {
    raise ReceivableError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=receivable_projection_payload(self),
    source_event_id="company:receivable:" +
      self.receivable_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ReceivableError::Projection(error)
  }
}
