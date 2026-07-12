///|
pub(all) enum ShadowMeasure {
  RecordCount(String)
  ProvidedValue(Int64)
} derive(Debug, Eq)

///|
pub(all) struct ShadowExpectation {
  metric_id : String
  domain : String
  dimension : String
  measure : ShadowMeasure
  source_value : Int64
  tolerance : Int64
} derive(Debug, Eq)

///|
pub(all) struct ShadowPlan {
  run_id : String
  source_snapshot_id : String
  expectations : Array[ShadowExpectation]
} derive(Debug, Eq)

///|
pub(all) struct ShadowComparison {
  report : @parity.ParityReport
  summary : @parity.ParitySummary
} derive(Debug, Eq)

///|
pub(all) suberror ShadowError {
  EmptyIdentifier
  NegativeValue
  NegativeTolerance
  DuplicateMetric
} derive(Debug, Eq)

///|
pub fn ShadowPlan::new(
  run_id~ : String,
  source_snapshot_id~ : String,
) -> ShadowPlan raise ShadowError {
  if run_id.trim() == "" || source_snapshot_id.trim() == "" {
    raise ShadowError::EmptyIdentifier
  }
  { run_id, source_snapshot_id, expectations: [] }
}

///|
pub fn ShadowPlan::add_expectation(
  self : ShadowPlan,
  expectation : ShadowExpectation,
) -> ShadowPlan raise ShadowError {
  if expectation.metric_id.trim() == "" ||
    expectation.domain.trim() == "" ||
    expectation.dimension.trim() == "" {
    raise ShadowError::EmptyIdentifier
  }
  if expectation.source_value < 0L {
    raise ShadowError::NegativeValue
  }
  if expectation.tolerance < 0L {
    raise ShadowError::NegativeTolerance
  }
  for existing in self.expectations {
    if existing.metric_id == expectation.metric_id {
      raise ShadowError::DuplicateMetric
    }
  }
  let expectations = self.expectations.copy()
  expectations.push(expectation)
  { ..self, expectations, }
}

///|
pub fn ShadowPlan::compare(
  self : ShadowPlan,
  target : @store.RecordStore,
) -> ShadowComparison {
  let mut report = try! @parity.ParityReport::new(
    run_id=self.run_id,
    source_snapshot_id=self.source_snapshot_id,
  )
  for expectation in self.expectations {
    let target_value = match expectation.measure {
      ShadowMeasure::RecordCount(record_type) =>
        target.count_type(record_type~).to_int64()
      ShadowMeasure::ProvidedValue(value) => value
    }
    report = try! report.add_metric({
      metric_id: expectation.metric_id,
      domain: expectation.domain,
      dimension: expectation.dimension,
      source_value: expectation.source_value,
      target_value,
      tolerance: expectation.tolerance,
    })
  }
  let summary = report.evaluate()
  { report, summary }
}
