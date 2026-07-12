///|
pub(all) enum ReceivableState {
  Open
  PartiallyCollected
  Collected
  WrittenOff
} derive(Debug, Eq)

///|
pub(all) struct Receivable {
  receivable_id : String
  source_id : String
  principal_id : String
  customer_id : String
  amount : @finance.Money
  collected_minor : Int64
  state : ReceivableState
} derive(Debug, Eq)

///|
pub(all) suberror ReceivableError {
  EmptyIdentifier
  InvalidAmount
  InvalidState
  OverCollection
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Receivable::open(
  receivable_id~ : String,
  source_id~ : String,
  principal_id~ : String,
  customer_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Receivable raise ReceivableError {
  if receivable_id.trim() == "" ||
    source_id.trim() == "" ||
    principal_id.trim() == "" ||
    customer_id.trim() == "" {
    raise ReceivableError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise ReceivableError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="receivable:open",
    scope="customer:\{customer_id}",
    amount_minor=amount.minor,
  ) catch {
    error => raise ReceivableError::NotAuthorized(error)
  }
  {
    receivable_id,
    source_id,
    principal_id,
    customer_id,
    amount,
    collected_minor: 0,
    state: ReceivableState::Open,
  }
}

///|
pub fn Receivable::outstanding_minor(self : Receivable) -> Int64 {
  self.amount.minor - self.collected_minor
}

///|
pub fn Receivable::collect(
  self : Receivable,
  amount_minor~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Receivable raise ReceivableError {
  if self.state == ReceivableState::Collected ||
    self.state == ReceivableState::WrittenOff {
    raise ReceivableError::InvalidState
  }
  if amount_minor <= 0 || amount_minor > self.outstanding_minor() {
    raise ReceivableError::OverCollection
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="receivable:collect",
    scope="customer:\{self.customer_id}",
    amount_minor~,
  ) catch {
    error => raise ReceivableError::NotAuthorized(error)
  }
  let collected_minor = self.collected_minor + amount_minor
  let state = if collected_minor == self.amount.minor {
    ReceivableState::Collected
  } else {
    ReceivableState::PartiallyCollected
  }
  { ..self, collected_minor, state }
}
