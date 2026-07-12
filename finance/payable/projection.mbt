///|
fn payable_state_name(state : PayableState) -> String {
  match state {
    PayableState::Open => "open"
    PayableState::PartiallyPaid => "partially_paid"
    PayableState::Paid => "paid"
    PayableState::Voided => "voided"
  }
}

///|
fn payable_projection_payload(payable : Payable) -> String {
  Json::object({
    "payable_id": Json::string(payable.payable_id),
    "principal_id": Json::string(payable.principal_id),
    "project_scope": Json::string(payable.project_scope),
    "supplier_id": Json::string(payable.supplier_id),
    "source_reference": Json::string(payable.source_reference),
    "amount_minor": Json::number(
      payable.amount.minor.to_double(),
      repr=payable.amount.minor.to_string(),
    ),
    "outstanding_minor": Json::number(
      payable.outstanding.minor.to_double(),
      repr=payable.outstanding.minor.to_string(),
    ),
    "currency": Json::string(payable.amount.currency),
    "state": Json::string(payable_state_name(payable.state)),
    "event_count": Json::number(
      payable.events.length().to_double(),
      repr=payable.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn Payable::append_projection(
  self : Payable,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PayableError {
  if projection.aggregate_type != "payable" ||
    projection.aggregate_id != self.payable_id {
    raise PayableError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=payable_projection_payload(self),
    source_event_id="company:payable:" +
      self.payable_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PayableError::Projection(error)
  }
}
