///|
/// Fixed-point monetary value. `minor` is the smallest currency unit.
pub(all) struct Money {
  minor : Int64
  currency : String
} derive(Debug, Eq)

///|
pub(all) suberror MoneyError {
  InvalidCurrency(String)
  CurrencyMismatch
  NegativeResult
} derive(Debug, Eq)

///|
pub fn Money::new(minor~ : Int64, currency~ : String) -> Money raise MoneyError {
  if currency.length() != 3 {
    raise MoneyError::InvalidCurrency(currency)
  }
  { minor, currency }
}

///|
pub fn Money::zero(currency~ : String) -> Money raise MoneyError {
  Money::new(minor=0, currency~)
}

///|
pub fn Money::add(self : Money, other : Money) -> Money raise MoneyError {
  if self.currency != other.currency {
    raise MoneyError::CurrencyMismatch
  }
  { minor: self.minor + other.minor, currency: self.currency }
}

///|
pub fn Money::subtract(self : Money, other : Money) -> Money raise MoneyError {
  if self.currency != other.currency {
    raise MoneyError::CurrencyMismatch
  }
  let result = self.minor - other.minor
  if result < 0 {
    raise MoneyError::NegativeResult
  }
  { minor: result, currency: self.currency }
}

///|
pub fn Money::is_zero(self : Money) -> Bool {
  self.minor == 0
}

///|
pub fn Money::is_non_negative(self : Money) -> Bool {
  self.minor >= 0
}
