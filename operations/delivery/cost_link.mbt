///|
/// Build a project cost forecast from accepted delivery progress. The report's
/// evidence and acceptance state are the source of the progress input; this
/// method does not post cost, alter budgets, or infer accounting treatment.
pub fn ProgressReport::to_cost_forecast(
  self : ProgressReport,
  target~ : @finance.Money,
  committed~ : @finance.Money,
  actual~ : @finance.Money,
) -> @cost.CostForecast raise DeliveryError {
  if self.state != ProgressState::Accepted {
    raise DeliveryError::InvalidState
  }
  @cost.CostForecast::new(
    project_scope=self.project_scope,
    target~,
    committed~,
    actual~,
    progress_bps=self.progress_bps,
  ) catch {
    error => raise DeliveryError::CostForecast(error)
  }
}
