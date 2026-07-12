///|
fn facility_state_name(state : FacilityState) -> String {
  match state {
    FacilityState::Draft => "draft"
    FacilityState::Approved => "approved"
    FacilityState::Active => "active"
    FacilityState::PartiallyRepaid => "partially_repaid"
    FacilityState::Closed => "closed"
    FacilityState::Defaulted => "defaulted"
    FacilityState::Cancelled => "cancelled"
  }
}

///|
fn facility_projection_payload(facility : FinancingFacility) -> String {
  Json::object({
    "facility_id": Json::string(facility.facility_id),
    "principal_id": Json::string(facility.principal_id),
    "project_scope": Json::string(facility.project_scope),
    "lender_id": Json::string(facility.lender_id),
    "limit_amount_minor": Json::number(
      facility.limit_amount.minor.to_double(),
      repr=facility.limit_amount.minor.to_string(),
    ),
    "drawn_amount_minor": Json::number(
      facility.drawn_amount.minor.to_double(),
      repr=facility.drawn_amount.minor.to_string(),
    ),
    "outstanding_principal_minor": Json::number(
      facility.outstanding_principal.minor.to_double(),
      repr=facility.outstanding_principal.minor.to_string(),
    ),
    "annual_rate_bps": Json::number(
      facility.annual_rate_bps.to_double(),
      repr=facility.annual_rate_bps.to_string(),
    ),
    "currency": Json::string(facility.limit_amount.currency),
    "state": Json::string(facility_state_name(facility.state)),
    "event_count": Json::number(
      facility.events.length().to_double(),
      repr=facility.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn FinancingFacility::append_projection(
  self : FinancingFacility,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise FinancingError {
  if projection.aggregate_type != "financing_facility" ||
    projection.aggregate_id != self.facility_id {
    raise FinancingError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=facility_projection_payload(self),
    source_event_id="company:financing-facility:" +
      self.facility_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise FinancingError::Projection(error)
  }
}
