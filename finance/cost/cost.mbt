///|
/// The four controllable components behind the ERP dynamic-cost total.
pub(all) struct CostBreakdown {
  direct_minor : Int64
  indirect_minor : Int64
  contingency_minor : Int64
  other_minor : Int64
} derive(Debug, Eq)

///|
pub(all) struct DynamicCost {
  currency : String
  breakdown : CostBreakdown
  total_minor : Int64
} derive(Debug, Eq)

///|
pub(all) suberror CostError {
  InvalidCurrency
  NegativeComponent
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn CostBreakdown::new(
  direct_minor~ : Int64,
  indirect_minor~ : Int64,
  contingency_minor~ : Int64,
  other_minor~ : Int64,
) -> CostBreakdown raise CostError {
  if direct_minor < 0 ||
    indirect_minor < 0 ||
    contingency_minor < 0 ||
    other_minor < 0 {
    raise CostError::NegativeComponent
  }
  { direct_minor, indirect_minor, contingency_minor, other_minor }
}

///|
pub fn CostBreakdown::total_minor(self : CostBreakdown) -> Int64 {
  self.direct_minor +
  self.indirect_minor +
  self.contingency_minor +
  self.other_minor
}

///|
pub fn calculate_dynamic_cost(
  currency~ : String,
  breakdown : CostBreakdown,
) -> DynamicCost raise CostError {
  if currency.length() != 3 {
    raise CostError::InvalidCurrency
  }
  { currency, breakdown, total_minor: breakdown.total_minor() }
}
