///|
fn mandate_state_name(state : MandateState) -> String {
  match state {
    MandateState::Draft => "draft"
    MandateState::Active => "active"
    MandateState::Suspended => "suspended"
    MandateState::Closed => "closed"
  }
}

///|
fn proposal_state_name(state : ProposalState) -> String {
  match state {
    ProposalState::Draft => "draft"
    ProposalState::Analyzed => "analyzed"
    ProposalState::Submitted => "submitted"
    ProposalState::Approved => "approved"
    ProposalState::Rejected => "rejected"
    ProposalState::Executed => "executed"
    ProposalState::Cancelled => "cancelled"
  }
}

///|
fn trend_name(trend : @analytics.Trend) -> String {
  match trend {
    @analytics.Trend::Rising => "rising"
    @analytics.Trend::Falling => "falling"
    @analytics.Trend::Flat => "flat"
  }
}

///|
fn analysis_json(report : @analytics.AnalysisReport) -> Json {
  Json::object({
    "instrument": Json::string(report.instrument),
    "sample_size": Json::number(
      report.sample_size.to_double(),
      repr=report.sample_size.to_string(),
    ),
    "first_close_minor": Json::number(
      report.first_close_minor.to_double(),
      repr=report.first_close_minor.to_string(),
    ),
    "last_close_minor": Json::number(
      report.last_close_minor.to_double(),
      repr=report.last_close_minor.to_string(),
    ),
    "trend": Json::string(trend_name(report.trend)),
    "moving_average_minor": Json::number(
      report.moving_average_minor.to_double(),
      repr=report.moving_average_minor.to_string(),
    ),
  })
}

///|
fn mandate_projection_payload(mandate : InvestmentMandate) -> String {
  Json::object({
    "mandate_id": Json::string(mandate.mandate_id),
    "principal_id": Json::string(mandate.principal_id),
    "project_scope": Json::string(mandate.project_scope),
    "base_currency": Json::string(mandate.base_currency),
    "max_exposure_minor": Json::number(
      mandate.max_exposure.minor.to_double(),
      repr=mandate.max_exposure.minor.to_string(),
    ),
    "max_single_position_minor": Json::number(
      mandate.max_single_position.minor.to_double(),
      repr=mandate.max_single_position.minor.to_string(),
    ),
    "state": Json::string(mandate_state_name(mandate.state)),
    "event_count": Json::number(
      mandate.events.length().to_double(),
      repr=mandate.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn InvestmentMandate::append_projection(
  self : InvestmentMandate,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise InvestmentError {
  if projection.aggregate_type != "investment_mandate" ||
    projection.aggregate_id != self.mandate_id {
    raise InvestmentError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=mandate_projection_payload(self),
    source_event_id="company:investment-mandate:" +
      self.mandate_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise InvestmentError::Projection(error)
  }
}

///|
fn proposal_projection_payload(proposal : InvestmentProposal) -> String {
  let analysis : Json = match proposal.analysis {
    Some(report) => analysis_json(report)
    None => Json::null()
  }
  Json::object({
    "proposal_id": Json::string(proposal.proposal_id),
    "mandate_id": Json::string(proposal.mandate_id),
    "principal_id": Json::string(proposal.principal_id),
    "project_scope": Json::string(proposal.project_scope),
    "instrument": Json::string(proposal.instrument),
    "quantity": Json::number(
      proposal.quantity.to_double(),
      repr=proposal.quantity.to_string(),
    ),
    "price_minor": Json::number(
      proposal.price.minor.to_double(),
      repr=proposal.price.minor.to_string(),
    ),
    "notional_minor": Json::number(
      proposal.notional.minor.to_double(),
      repr=proposal.notional.minor.to_string(),
    ),
    "currency": Json::string(proposal.price.currency),
    "analysis": analysis,
    "state": Json::string(proposal_state_name(proposal.state)),
    "event_count": Json::number(
      proposal.events.length().to_double(),
      repr=proposal.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn InvestmentProposal::append_projection(
  self : InvestmentProposal,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise InvestmentError {
  if projection.aggregate_type != "investment_proposal" ||
    projection.aggregate_id != self.proposal_id {
    raise InvestmentError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=proposal_projection_payload(self),
    source_event_id="company:investment-proposal:" +
      self.proposal_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise InvestmentError::Projection(error)
  }
}

///|
pub fn InvestmentPosition::append_projection(
  self : InvestmentPosition,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise InvestmentError {
  if projection.aggregate_type != "investment_position" ||
    projection.aggregate_id != self.position_id {
    raise InvestmentError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "position_id": Json::string(self.position_id),
    "mandate_id": Json::string(self.mandate_id),
    "instrument": Json::string(self.instrument),
    "quantity": Json::number(
      self.quantity.to_double(),
      repr=self.quantity.to_string(),
    ),
    "cost_basis_minor": Json::number(
      self.cost_basis.minor.to_double(),
      repr=self.cost_basis.minor.to_string(),
    ),
    "currency": Json::string(self.cost_basis.currency),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-position:" +
      self.position_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise InvestmentError::Projection(error)
  }
}
