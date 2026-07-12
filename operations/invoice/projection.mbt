///|
fn invoice_state_name(state : InvoiceState) -> String {
  match state {
    InvoiceState::Draft => "draft"
    InvoiceState::Issued => "issued"
    InvoiceState::Accepted => "accepted"
    InvoiceState::PartiallyPaid => "partially_paid"
    InvoiceState::Paid => "paid"
    InvoiceState::Voided => "voided"
  }
}

///|
fn invoice_projection_payload(invoice : Invoice) -> String {
  Json::object({
    "invoice_id": Json::string(invoice.invoice_id),
    "principal_id": Json::string(invoice.principal_id),
    "customer_id": Json::string(invoice.customer_id),
    "source_id": Json::string(invoice.source_id),
    "amount_minor": Json::number(
      invoice.amount.minor.to_double(),
      repr=invoice.amount.minor.to_string(),
    ),
    "paid_minor": Json::number(
      invoice.paid_minor.to_double(),
      repr=invoice.paid_minor.to_string(),
    ),
    "currency": Json::string(invoice.amount.currency),
    "state": Json::string(invoice_state_name(invoice.state)),
    "event_count": Json::number(
      invoice.events.length().to_double(),
      repr=invoice.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn Invoice::append_projection(
  self : Invoice,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise InvoiceError {
  if projection.aggregate_type != "invoice" ||
    projection.aggregate_id != self.invoice_id {
    raise InvoiceError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=invoice_projection_payload(self),
    source_event_id="company:invoice:" +
      self.invoice_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise InvoiceError::Projection(error)
  }
}
