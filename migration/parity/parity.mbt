///|
/// A source-to-target comparison metric used during shadow migration. Values
/// are integer-safe so counts and minor-unit financial totals can share the
/// same deterministic gate.
pub(all) struct ParityMetric {
  metric_id : String
  domain : String
  dimension : String
  source_value : Int64
  target_value : Int64
  tolerance : Int64
} derive(Debug, Eq)

///|
pub(all) enum ParityStatus {
  Exact
  WithinTolerance
  Mismatch
} derive(Debug, Eq)

///|
pub(all) struct ParityFinding {
  metric_id : String
  status : ParityStatus
  delta : Int64
} derive(Debug, Eq)

///|
pub(all) struct ParitySummary {
  findings : Array[ParityFinding]
  exact_count : Int
  within_tolerance_count : Int
  mismatch_count : Int
  accepted : Bool
} derive(Debug, Eq)

///|
pub(all) struct ParityReport {
  run_id : String
  source_snapshot_id : String
  metrics : Array[ParityMetric]
} derive(Debug, Eq)

///|
pub(all) suberror ParityError {
  EmptyIdentifier
  NegativeTolerance
  DuplicateMetric
} derive(Debug, Eq)

///|
pub fn ParityReport::new(
  run_id~ : String,
  source_snapshot_id~ : String,
) -> ParityReport raise ParityError {
  if run_id.trim() == "" || source_snapshot_id.trim() == "" {
    raise ParityError::EmptyIdentifier
  }
  { run_id, source_snapshot_id, metrics: [] }
}

///|
pub fn ParityReport::add_metric(
  self : ParityReport,
  metric : ParityMetric,
) -> ParityReport raise ParityError {
  if metric.metric_id.trim() == "" ||
    metric.domain.trim() == "" ||
    metric.dimension.trim() == "" {
    raise ParityError::EmptyIdentifier
  }
  if metric.tolerance < 0 {
    raise ParityError::NegativeTolerance
  }
  for existing in self.metrics {
    if existing.metric_id == metric.metric_id {
      raise ParityError::DuplicateMetric
    }
  }
  let metrics = self.metrics.copy()
  metrics.push(metric)
  { ..self, metrics, }
}

///|
fn classify(delta : Int64, tolerance : Int64) -> ParityStatus {
  if delta == 0 {
    ParityStatus::Exact
  } else {
    let absolute = if delta < 0 { -delta } else { delta }
    if absolute <= tolerance {
      ParityStatus::WithinTolerance
    } else {
      ParityStatus::Mismatch
    }
  }
}

///|
pub fn ParityReport::evaluate(self : ParityReport) -> ParitySummary {
  let findings : Array[ParityFinding] = []
  let mut exact_count = 0
  let mut within_tolerance_count = 0
  let mut mismatch_count = 0
  for metric in self.metrics {
    let delta = metric.target_value - metric.source_value
    let status = classify(delta, metric.tolerance)
    match status {
      ParityStatus::Exact => exact_count += 1
      ParityStatus::WithinTolerance => within_tolerance_count += 1
      ParityStatus::Mismatch => mismatch_count += 1
    }
    findings.push({ metric_id: metric.metric_id, status, delta })
  }
  {
    findings,
    exact_count,
    within_tolerance_count,
    mismatch_count,
    accepted: mismatch_count == 0,
  }
}
