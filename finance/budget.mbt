///|
/// A budget line tracks allocated, reserved, and consumed minor units.
pub(all) struct BudgetLine {
  line_id : String
  principal_id : String
  scope : String
  currency : String
  allocated_minor : Int64
  reserved_minor : Int64
  consumed_minor : Int64
} derive(Debug, Eq)

///|
pub(all) suberror BudgetError {
  EmptyIdentifier
  EmptyScope
  InvalidCurrency
  NegativeAmount
  InsufficientAvailable
  InsufficientReserved
} derive(Debug, Eq)

///|
pub fn BudgetLine::new(
  line_id~ : String,
  principal_id~ : String,
  scope~ : String,
  currency~ : String,
  allocated_minor~ : Int64,
) -> BudgetLine raise BudgetError {
  if line_id.trim() == "" || principal_id.trim() == "" {
    raise BudgetError::EmptyIdentifier
  }
  if scope.trim() == "" {
    raise BudgetError::EmptyScope
  }
  if currency.length() != 3 {
    raise BudgetError::InvalidCurrency
  }
  if allocated_minor < 0 {
    raise BudgetError::NegativeAmount
  }
  {
    line_id,
    principal_id,
    scope,
    currency,
    allocated_minor,
    reserved_minor: 0,
    consumed_minor: 0,
  }
}

///|
pub fn BudgetLine::available_minor(self : BudgetLine) -> Int64 {
  self.allocated_minor - self.reserved_minor - self.consumed_minor
}

///|
pub fn BudgetLine::reserve(
  self : BudgetLine,
  amount_minor~ : Int64,
) -> BudgetLine raise BudgetError {
  if amount_minor < 0 {
    raise BudgetError::NegativeAmount
  }
  if amount_minor > self.available_minor() {
    raise BudgetError::InsufficientAvailable
  }
  { ..self, reserved_minor: self.reserved_minor + amount_minor }
}

///|
pub fn BudgetLine::release(
  self : BudgetLine,
  amount_minor~ : Int64,
) -> BudgetLine raise BudgetError {
  if amount_minor < 0 {
    raise BudgetError::NegativeAmount
  }
  if amount_minor > self.reserved_minor {
    raise BudgetError::InsufficientReserved
  }
  { ..self, reserved_minor: self.reserved_minor - amount_minor }
}

///|
pub fn BudgetLine::consume(
  self : BudgetLine,
  amount_minor~ : Int64,
) -> BudgetLine raise BudgetError {
  if amount_minor < 0 {
    raise BudgetError::NegativeAmount
  }
  if amount_minor > self.reserved_minor {
    raise BudgetError::InsufficientReserved
  }
  {
    ..self,
    reserved_minor: self.reserved_minor - amount_minor,
    consumed_minor: self.consumed_minor + amount_minor,
  }
}
