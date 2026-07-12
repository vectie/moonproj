///|
pub(all) enum PayableState {
  Open
  PartiallyPaid
  Paid
  Voided
} derive(Debug, Eq)

///|
pub(all) struct PayableEvent {
  from : PayableState
  to : PayableState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct Payable {
  payable_id : String
  principal_id : String
  project_scope : String
  supplier_id : String
  source_reference : String
  amount : @finance.Money
  outstanding : @finance.Money
  state : PayableState
  events : Array[PayableEvent]
} derive(Debug, Eq)

///|
pub(all) suberror PayableError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  OverPayment
  InvalidState
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
} derive(Debug, Eq)

///|
pub fn Payable::open(
  payable_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  supplier_id~ : String,
  source_reference~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Payable raise PayableError {
  if payable_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    supplier_id.trim() == "" ||
    source_reference.trim() == "" {
    raise PayableError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise PayableError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="payable:create",
    scope=project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise PayableError::NotAuthorized(error)
  }
  {
    payable_id,
    principal_id,
    project_scope,
    supplier_id,
    source_reference,
    amount,
    outstanding: amount,
    state: PayableState::Open,
    events: [],
  }
}

///|
pub fn Payable::record_payment(
  self : Payable,
  payment~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Payable raise PayableError {
  if self.state == PayableState::Paid || self.state == PayableState::Voided {
    raise PayableError::InvalidState
  }
  if payment.minor <= 0 {
    raise PayableError::InvalidAmount
  }
  if payment.currency != self.amount.currency {
    raise PayableError::CurrencyMismatch
  }
  if payment.minor > self.outstanding.minor {
    raise PayableError::OverPayment
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="payable:pay",
    scope=self.project_scope,
    amount_minor=payment.minor,
  ) catch {
    error => raise PayableError::NotAuthorized(error)
  }
  let outstanding = self.outstanding.subtract(payment) catch {
    error => raise PayableError::Money(error)
  }
  let next_state = if outstanding.is_zero() {
    PayableState::Paid
  } else {
    PayableState::PartiallyPaid
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: next_state,
    actor_id,
    capability: "payable:pay",
  })
  { ..self, outstanding, state: next_state, events }
}

///|
pub fn Payable::void_record(
  self : Payable,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Payable raise PayableError {
  if self.state == PayableState::Paid || self.state == PayableState::Voided {
    raise PayableError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="payable:void",
    scope=self.project_scope,
    amount_minor=self.outstanding.minor,
  ) catch {
    error => raise PayableError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: PayableState::Voided,
    actor_id,
    capability: "payable:void",
  })
  { ..self, state: PayableState::Voided, events }
}
