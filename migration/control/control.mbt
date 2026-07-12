///|
/// A source-side opening control total. Values are minor units or exact row
/// counts, depending on the named domain/dimension; the extractor decides the
/// unit and records it in the metric identifier.
pub(all) struct ControlTotal {
  metric_id : String
  domain : String
  dimension : String
  value : Int64
  tolerance : Int64
} derive(Debug, Eq)

///|
pub(all) struct OpeningControlSet {
  source_snapshot_id : String
  controls : Array[ControlTotal]
} derive(Debug, Eq)

///|
pub(all) suberror ControlError {
  EmptyIdentifier
  NegativeValue
  NegativeTolerance
  DuplicateMetric
  Shadow(@shadow.ShadowError)
} derive(Debug, Eq)

///|
pub fn OpeningControlSet::new(
  source_snapshot_id~ : String,
) -> OpeningControlSet raise ControlError {
  if source_snapshot_id.trim() == "" {
    raise ControlError::EmptyIdentifier
  }
  { source_snapshot_id, controls: [] }
}

///|
pub fn OpeningControlSet::add(
  self : OpeningControlSet,
  control : ControlTotal,
) -> OpeningControlSet raise ControlError {
  if control.metric_id.trim() == "" ||
    control.domain.trim() == "" ||
    control.dimension.trim() == "" {
    raise ControlError::EmptyIdentifier
  }
  if control.value < 0L {
    raise ControlError::NegativeValue
  }
  if control.tolerance < 0L {
    raise ControlError::NegativeTolerance
  }
  for existing in self.controls {
    if existing.metric_id == control.metric_id {
      raise ControlError::DuplicateMetric
    }
  }
  let controls = self.controls.copy()
  controls.push(control)
  { ..self, controls, }
}

///|
pub fn OpeningControlSet::to_shadow_plan(
  self : OpeningControlSet,
  run_id~ : String,
) -> @shadow.ShadowPlan raise ControlError {
  let mut plan = @shadow.ShadowPlan::new(
    run_id~,
    source_snapshot_id=self.source_snapshot_id,
  ) catch {
    error => raise ControlError::Shadow(error)
  }
  for control in self.controls {
    plan = plan.add_expectation({
      metric_id: control.metric_id,
      domain: control.domain,
      dimension: control.dimension,
      measure: @shadow.ShadowMeasure::ProvidedValue(control.value),
      source_value: control.value,
      tolerance: control.tolerance,
    }) catch {
      error => raise ControlError::Shadow(error)
    }
  }
  plan
}
