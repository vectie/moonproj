///|
/// Project cost forecast joining target, commitment, actual, and accepted
/// progress. `variance_minor` is signed: positive is under target, negative is
/// an expected overrun.
pub(all) struct CostForecast {
  project_scope : String
  target : @finance.Money
  committed : @finance.Money
  actual : @finance.Money
  progress_bps : Int64
  forecast_at_completion : @finance.Money
  variance_minor : Int64
} derive(Debug, Eq)

///|
pub(all) suberror ForecastError {
  EmptyScope
  InvalidAmount
  InvalidProgress
  CurrencyMismatch
  ProjectionIdentity
  Projection(@store.ProjectionError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn CostForecast::new(
  project_scope~ : String,
  target~ : @finance.Money,
  committed~ : @finance.Money,
  actual~ : @finance.Money,
  progress_bps~ : Int64,
) -> CostForecast raise ForecastError {
  if project_scope.trim() == "" {
    raise ForecastError::EmptyScope
  }
  if target.minor < 0 || committed.minor < 0 || actual.minor < 0 {
    raise ForecastError::InvalidAmount
  }
  if progress_bps < 0L || progress_bps > 10000L {
    raise ForecastError::InvalidProgress
  }
  if target.currency != committed.currency || target.currency != actual.currency {
    raise ForecastError::CurrencyMismatch
  }
  let baseline_forecast = if progress_bps == 0L {
    target.minor
  } else {
    (actual.minor * 10000L + progress_bps / 2L) / progress_bps
  }
  let committed_floor = actual.minor + committed.minor
  let forecast_minor = if baseline_forecast < committed_floor {
    committed_floor
  } else {
    baseline_forecast
  }
  let forecast = @finance.Money::new(
    minor=forecast_minor,
    currency=target.currency,
  ) catch {
    error => raise ForecastError::Money(error)
  }
  {
    project_scope,
    target,
    committed,
    actual,
    progress_bps,
    forecast_at_completion: forecast,
    variance_minor: target.minor - forecast_minor,
  }
}
