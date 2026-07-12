///|
fn tax_state_name(state : TaxObligationState) -> String {
  match state {
    TaxObligationState::Draft => "draft"
    TaxObligationState::Calculated => "calculated"
    TaxObligationState::Reviewed => "reviewed"
    TaxObligationState::Filed => "filed"
    TaxObligationState::Paid => "paid"
    TaxObligationState::Voided => "voided"
  }
}

///|
fn tax_projection_payload(obligation : TaxObligation) -> String {
  Json::object({
    "tax_id": Json::string(obligation.tax_id),
    "principal_id": Json::string(obligation.principal_id),
    "project_scope": Json::string(obligation.project_scope),
    "source_reference": Json::string(obligation.source_reference),
    "jurisdiction": Json::string(obligation.jurisdiction),
    "category": Json::string(obligation.category),
    "base_amount_minor": Json::number(
      obligation.base_amount.minor.to_double(),
      repr=obligation.base_amount.minor.to_string(),
    ),
    "tax_rate_bps": Json::number(
      obligation.tax_rate_bps.to_double(),
      repr=obligation.tax_rate_bps.to_string(),
    ),
    "withholding_rate_bps": Json::number(
      obligation.withholding_rate_bps.to_double(),
      repr=obligation.withholding_rate_bps.to_string(),
    ),
    "tax_amount_minor": Json::number(
      obligation.tax_amount.minor.to_double(),
      repr=obligation.tax_amount.minor.to_string(),
    ),
    "withholding_amount_minor": Json::number(
      obligation.withholding_amount.minor.to_double(),
      repr=obligation.withholding_amount.minor.to_string(),
    ),
    "currency": Json::string(obligation.base_amount.currency),
    "state": Json::string(tax_state_name(obligation.state)),
    "event_count": Json::number(
      obligation.events.length().to_double(),
      repr=obligation.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn TaxObligation::append_projection(
  self : TaxObligation,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise TaxError {
  if projection.aggregate_type != "tax_obligation" ||
    projection.aggregate_id != self.tax_id {
    raise TaxError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=tax_projection_payload(self),
    source_event_id="company:tax-obligation:" +
      self.tax_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise TaxError::Projection(error)
  }
}

///|
fn filing_state_name(state : TaxFilingState) -> String {
  match state {
    TaxFilingState::Prepared => "prepared"
    TaxFilingState::Submitted => "submitted"
    TaxFilingState::Accepted => "accepted"
    TaxFilingState::Rejected => "rejected"
  }
}

///|
fn filing_projection_payload(filing : TaxFiling) -> String {
  Json::object({
    "filing_id": Json::string(filing.filing_id),
    "tax_id": Json::string(filing.tax_id),
    "principal_id": Json::string(filing.principal_id),
    "project_scope": Json::string(filing.project_scope),
    "jurisdiction": Json::string(filing.jurisdiction),
    "category": Json::string(filing.category),
    "filing_period": Json::string(filing.filing_period),
    "authority_reference": Json::string(filing.authority_reference),
    "reported_tax_amount_minor": Json::number(
      filing.reported_tax_amount.minor.to_double(),
      repr=filing.reported_tax_amount.minor.to_string(),
    ),
    "currency": Json::string(filing.reported_tax_amount.currency),
    "state": Json::string(filing_state_name(filing.state)),
    "event_count": Json::number(
      filing.events.length().to_double(),
      repr=filing.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn TaxFiling::append_projection(
  self : TaxFiling,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise TaxError {
  if projection.aggregate_type != "tax_filing" ||
    projection.aggregate_id != self.filing_id {
    raise TaxError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=filing_projection_payload(self),
    source_event_id="company:tax-filing:" +
      self.filing_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise TaxError::Projection(error)
  }
}
