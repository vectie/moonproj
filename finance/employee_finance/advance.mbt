///|
pub(all) enum AdvanceState {
  Open
  PartiallyRepaid
  Repaid
  WrittenOff
} derive(Debug, Eq)

///|
pub(all) struct EmployeeAdvance {
  advance_id : String
  principal_id : String
  employee_id : String
  amount : @finance.Money
  repaid_minor : Int64
  state : AdvanceState
} derive(Debug, Eq)

///|
pub(all) suberror AdvanceError {
  EmptyIdentifier
  InvalidAmount
  InvalidState
  OverRepayment
  ProjectionIdentity
  Projection(@store.ProjectionError)
  AccountingEvent(@accounting.AccountingEventError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn EmployeeAdvance::new(
  advance_id~ : String,
  principal_id~ : String,
  employee_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> EmployeeAdvance raise AdvanceError {
  if advance_id.trim() == "" ||
    principal_id.trim() == "" ||
    employee_id.trim() == "" {
    raise AdvanceError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise AdvanceError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="advance:create",
    scope="employee:\{employee_id}",
    amount_minor=amount.minor,
  ) catch {
    error => raise AdvanceError::NotAuthorized(error)
  }
  {
    advance_id,
    principal_id,
    employee_id,
    amount,
    repaid_minor: 0,
    state: AdvanceState::Open,
  }
}

///|
pub fn EmployeeAdvance::outstanding_minor(self : EmployeeAdvance) -> Int64 {
  self.amount.minor - self.repaid_minor
}

///|
pub fn EmployeeAdvance::offset(
  self : EmployeeAdvance,
  amount_minor~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> EmployeeAdvance raise AdvanceError {
  if self.state == AdvanceState::Repaid ||
    self.state == AdvanceState::WrittenOff {
    raise AdvanceError::InvalidState
  }
  if amount_minor <= 0 || amount_minor > self.outstanding_minor() {
    raise AdvanceError::OverRepayment
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="advance:offset",
    scope="employee:\{self.employee_id}",
    amount_minor~,
  ) catch {
    error => raise AdvanceError::NotAuthorized(error)
  }
  let repaid_minor = self.repaid_minor + amount_minor
  let state = if repaid_minor == self.amount.minor {
    AdvanceState::Repaid
  } else {
    AdvanceState::PartiallyRepaid
  }
  { ..self, repaid_minor, state }
}
