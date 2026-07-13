///|
/// How a preserved ERP value was interpreted by the explicit model evaluator.
/// A source representation that is not a JSON number remains evidence and is
/// never coerced into a financial value.
pub(all) enum ModelValueKind {
  Numeric
  DateSerial
  Unparsed
  Missing
} derive(Debug, Eq)

///|
pub(all) struct ModelEvaluatedValue {
  index_id : String
  full_code : String
  unit : String?
  raw_value : String?
  numeric_value : Double?
  kind : ModelValueKind
} derive(Debug)

///|
/// A derived ratio is a reporting metric only. It does not create an
/// investment, journal, cash movement, or approval.
pub(all) struct ModelDerivedMetric {
  metric_code : String
  numerator_code : String
  denominator_code : String
  value_bps : Int64
} derive(Debug, Eq)

///|
/// Deterministic evaluation of explicit numeric model indexes and parent
/// totals. Formula-like derivations are emitted only for known code pairs;
/// unknown source remarks and units remain untouched.
pub(all) struct ModelEvaluation {
  version_id : String
  project_id : String
  source_snapshot_id : String
  mapping_version : String
  values : Array[ModelEvaluatedValue]
  derived_metrics : Array[ModelDerivedMetric]
  parent_check_count : Int
  mismatch_count : Int
  issues : Array[String]
  validated : Bool
} derive(Debug)

///|
fn parse_numeric(value : String) -> Double? {
  let parsed = @json.parse(value) catch { _ => return None }
  match parsed {
    Number(number, ..) => Some(number)
    _ => None
  }
}

///|
fn value_for_code(
  indexes : Array[ModelIndex],
  code : String,
) -> (Double, String)? {
  for index in indexes {
    if index.full_code == code {
      match index.value_repr {
        Some(raw) =>
          match parse_numeric(raw) {
            Some(value) =>
              match index.unit {
                Some(unit) => return Some((value, unit))
                None => return None
              }
            None => return None
          }
        None => return None
      }
    }
  }
  None
}

///|
fn derive_metric(
  indexes : Array[ModelIndex],
  metric_code : String,
  numerator_code : String,
  denominator_code : String,
) -> ModelDerivedMetric? {
  let numerator = match value_for_code(indexes, numerator_code) {
    Some(value) => value
    None => return None
  }
  let denominator = match value_for_code(indexes, denominator_code) {
    Some(value) => value
    None => return None
  }
  if numerator.1 != denominator.1 || denominator.0 == 0.0 {
    return None
  }
  let ratio_bps = numerator.0 * 10000.0 / denominator.0
  Some({
    metric_code,
    numerator_code,
    denominator_code,
    value_bps: ratio_bps.to_int().to_int64(),
  })
}

///|
fn evaluated_value(index : ModelIndex) -> ModelEvaluatedValue {
  match index.value_repr {
    None =>
      {
        index_id: index.index_id,
        full_code: index.full_code,
        unit: index.unit,
        raw_value: None,
        numeric_value: None,
        kind: ModelValueKind::Missing,
      }
    Some(raw) =>
      match parse_numeric(raw) {
        None =>
          {
            index_id: index.index_id,
            full_code: index.full_code,
            unit: index.unit,
            raw_value: Some(raw),
            numeric_value: None,
            kind: ModelValueKind::Unparsed,
          }
        Some(number) => {
          let kind = match index.unit {
            Some(unit) if unit == "日期序号" => ModelValueKind::DateSerial
            _ => ModelValueKind::Numeric
          }
          {
            index_id: index.index_id,
            full_code: index.full_code,
            unit: index.unit,
            raw_value: Some(raw),
            numeric_value: Some(number),
            kind,
          }
        }
      }
  }
}

///|
fn values_json(values : Array[ModelEvaluatedValue]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    let kind = match value.kind {
      ModelValueKind::Numeric => "numeric"
      ModelValueKind::DateSerial => "date_serial"
      ModelValueKind::Unparsed => "unparsed"
      ModelValueKind::Missing => "missing"
    }
    let numeric = match value.numeric_value {
      Some(number) => Json::number(number, repr=number.to_string())
      None => Json::null()
    }
    encoded.push(
      Json::object({
        "index_id": Json::string(value.index_id),
        "full_code": Json::string(value.full_code),
        "unit": match value.unit {
          Some(unit) => Json::string(unit)
          None => Json::null()
        },
        "raw_value": match value.raw_value {
          Some(raw) => Json::string(raw)
          None => Json::null()
        },
        "numeric_value": numeric,
        "kind": Json::string(kind),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn metrics_json(metrics : Array[ModelDerivedMetric]) -> Json {
  let encoded : Array[Json] = []
  for metric in metrics {
    encoded.push(
      Json::object({
        "metric_code": Json::string(metric.metric_code),
        "numerator_code": Json::string(metric.numerator_code),
        "denominator_code": Json::string(metric.denominator_code),
        "value_bps": Json::number(
          metric.value_bps.to_double(),
          repr=metric.value_bps.to_string(),
        ),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn strings_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
pub fn InvestmentModel::evaluate(
  self : InvestmentModel,
  source_snapshot_id~ : String,
  mapping_version~ : String,
) -> ModelEvaluation raise ModelError {
  if source_snapshot_id.trim() == "" || mapping_version.trim() == "" {
    raise ModelError::EmptyIdentifier
  }
  if self.indexes.length() == 0 {
    raise ModelError::InvalidIndex
  }
  let values : Array[ModelEvaluatedValue] = []
  for index in self.indexes {
    values.push(evaluated_value(index))
  }
  let derived_metrics : Array[ModelDerivedMetric] = []
  let derivations : Array[(String, String, String)] = [
    ("CO.GrossMarginBps", "CO.GrossProfit", "CO.Revenue"),
    ("CO.NetMarginBps", "CO.NetProfit", "CO.Revenue"),
    ("CO.TaxToRevenueBps", "Tax.Total", "CO.Revenue"),
    ("CO.CostToRevenueBps", "CO.Cost", "CO.Revenue"),
  ]
  for derivation in derivations {
    match
      derive_metric(self.indexes, derivation.0, derivation.1, derivation.2) {
      Some(metric) => derived_metrics.push(metric)
      None => ()
    }
  }
  let issues : Array[String] = []
  let mut parent_check_count = 0
  for parent in self.indexes {
    let children : Array[ModelIndex] = []
    for candidate in self.indexes {
      match candidate.parent_code {
        Some(parent_code) if parent_code == parent.full_code =>
          children.push(candidate)
        _ => ()
      }
    }
    if children.length() == 0 {
      continue
    }
    parent_check_count += 1
    let parent_value = match value_for_code(self.indexes, parent.full_code) {
      Some(value) => value
      None => {
        issues.push("parent is not numeric: " + parent.full_code)
        continue
      }
    }
    let mut sum = 0.0
    let mut comparable = true
    for child in children {
      if child.unit != parent.unit {
        issues.push(
          "unit mismatch: " + parent.full_code + ":" + child.full_code,
        )
        comparable = false
      }
      match value_for_code(self.indexes, child.full_code) {
        Some(value) => sum += value.0
        None => {
          issues.push("child is not numeric: " + child.full_code)
          comparable = false
        }
      }
    }
    if comparable {
      let difference = parent_value.0 - sum
      let absolute_difference = if difference < 0.0 {
        0.0 - difference
      } else {
        difference
      }
      if absolute_difference > 0.000001 {
        issues.push(
          "parent total mismatch: " +
          parent.full_code +
          ":" +
          parent_value.0.to_string() +
          " != " +
          sum.to_string(),
        )
      }
    }
  }
  {
    version_id: self.version.version_id,
    project_id: self.version.project_id,
    source_snapshot_id,
    mapping_version,
    values,
    derived_metrics,
    parent_check_count,
    mismatch_count: issues.length(),
    issues: issues.copy(),
    validated: issues.length() == 0,
  }
}

///|
pub fn ModelEvaluation::append_projection(
  self : ModelEvaluation,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ModelError {
  if projection.aggregate_type != "investment_model_evaluation" ||
    projection.aggregate_id != self.version_id {
    raise ModelError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "version_id": Json::string(self.version_id),
    "project_id": Json::string(self.project_id),
    "source_snapshot_id": Json::string(self.source_snapshot_id),
    "mapping_version": Json::string(self.mapping_version),
    "values": values_json(self.values),
    "derived_metrics": metrics_json(self.derived_metrics),
    "parent_check_count": Json::number(
      self.parent_check_count.to_double(),
      repr=self.parent_check_count.to_string(),
    ),
    "mismatch_count": Json::number(
      self.mismatch_count.to_double(),
      repr=self.mismatch_count.to_string(),
    ),
    "issues": strings_json(self.issues),
    "validated": Json::boolean(self.validated),
    "analytics_only": Json::boolean(true),
    "investment_execution_authorized": Json::boolean(false),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-model-evaluation:" +
      self.version_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ModelError::Projection(error)
  }
}
