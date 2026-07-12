///|
fn asset_state_name(state : AssetState) -> String {
  match state {
    AssetState::Proposed => "proposed"
    AssetState::Capitalized => "capitalized"
    AssetState::Active => "active"
    AssetState::Impaired => "impaired"
    AssetState::Disposed => "disposed"
  }
}

///|
fn asset_projection_payload(asset : Asset) -> String {
  Json::object({
    "asset_id": Json::string(asset.asset_id),
    "principal_id": Json::string(asset.principal_id),
    "project_scope": Json::string(asset.project_scope),
    "description": Json::string(asset.description),
    "acquisition_minor": Json::number(
      asset.acquisition_cost.minor.to_double(),
      repr=asset.acquisition_cost.minor.to_string(),
    ),
    "residual_minor": Json::number(
      asset.residual_value.minor.to_double(),
      repr=asset.residual_value.minor.to_string(),
    ),
    "currency": Json::string(asset.acquisition_cost.currency),
    "useful_life_months": Json::number(
      asset.useful_life_months.to_double(),
      repr=asset.useful_life_months.to_string(),
    ),
    "accumulated_depreciation_minor": Json::number(
      asset.accumulated_depreciation.to_double(),
      repr=asset.accumulated_depreciation.to_string(),
    ),
    "state": Json::string(asset_state_name(asset.state)),
    "event_count": Json::number(
      asset.events.length().to_double(),
      repr=asset.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn Asset::append_projection(
  self : Asset,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise AssetError {
  if projection.aggregate_type != "asset" ||
    projection.aggregate_id != self.asset_id {
    raise AssetError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=asset_projection_payload(self),
    source_event_id="company:asset:" +
      self.asset_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise AssetError::Projection(error)
  }
}
