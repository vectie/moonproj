///|
fn dynamic_cost_projection_payload(cost : DynamicCost) -> String {
  Json::object({
    "currency": Json::string(cost.currency),
    "direct_minor": Json::number(
      cost.breakdown.direct_minor.to_double(),
      repr=cost.breakdown.direct_minor.to_string(),
    ),
    "indirect_minor": Json::number(
      cost.breakdown.indirect_minor.to_double(),
      repr=cost.breakdown.indirect_minor.to_string(),
    ),
    "contingency_minor": Json::number(
      cost.breakdown.contingency_minor.to_double(),
      repr=cost.breakdown.contingency_minor.to_string(),
    ),
    "other_minor": Json::number(
      cost.breakdown.other_minor.to_double(),
      repr=cost.breakdown.other_minor.to_string(),
    ),
    "total_minor": Json::number(
      cost.total_minor.to_double(),
      repr=cost.total_minor.to_string(),
    ),
  }).stringify()
}

///|
pub fn DynamicCost::append_projection(
  self : DynamicCost,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise CostError {
  if projection.aggregate_type != "dynamic_cost" {
    raise CostError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=dynamic_cost_projection_payload(self),
    source_event_id="company:dynamic-cost:" +
      projection.aggregate_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise CostError::Projection(error)
  }
}

///|
fn forecast_projection_payload(forecast : CostForecast) -> String {
  Json::object({
    "project_scope": Json::string(forecast.project_scope),
    "target_minor": Json::number(
      forecast.target.minor.to_double(),
      repr=forecast.target.minor.to_string(),
    ),
    "committed_minor": Json::number(
      forecast.committed.minor.to_double(),
      repr=forecast.committed.minor.to_string(),
    ),
    "actual_minor": Json::number(
      forecast.actual.minor.to_double(),
      repr=forecast.actual.minor.to_string(),
    ),
    "progress_bps": Json::number(
      forecast.progress_bps.to_double(),
      repr=forecast.progress_bps.to_string(),
    ),
    "forecast_at_completion_minor": Json::number(
      forecast.forecast_at_completion.minor.to_double(),
      repr=forecast.forecast_at_completion.minor.to_string(),
    ),
    "variance_minor": Json::number(
      forecast.variance_minor.to_double(),
      repr=forecast.variance_minor.to_string(),
    ),
    "currency": Json::string(forecast.target.currency),
  }).stringify()
}

///|
pub fn CostForecast::append_projection(
  self : CostForecast,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ForecastError {
  if projection.aggregate_type != "cost_forecast" ||
    projection.aggregate_id != self.project_scope {
    raise ForecastError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=forecast_projection_payload(self),
    source_event_id="company:cost-forecast:" +
      self.project_scope +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ForecastError::Projection(error)
  }
}
