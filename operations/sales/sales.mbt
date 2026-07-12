///|
pub(all) enum SalesState {
  Draft
  Reserved
  Signed
  Fulfilled
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct SalesEvent {
  from : SalesState
  to : SalesState
  actor_id : String
} derive(Debug, Eq)

///|
pub(all) struct SalesAgreement {
  agreement_id : String
  principal_id : String
  customer_id : String
  project_scope : String
  amount : @finance.Money
  state : SalesState
  events : Array[SalesEvent]
} derive(Debug, Eq)

///|
pub(all) suberror SalesError {
  EmptyIdentifier
  InvalidTransition
  Receivable(@receivable.ReceivableError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn SalesAgreement::new(
  agreement_id~ : String,
  principal_id~ : String,
  customer_id~ : String,
  project_scope~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> SalesAgreement raise SalesError {
  if agreement_id.trim() == "" ||
    principal_id.trim() == "" ||
    customer_id.trim() == "" ||
    project_scope.trim() == "" {
    raise SalesError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="sales:create",
    scope=project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise SalesError::NotAuthorized(error)
  }
  {
    agreement_id,
    principal_id,
    customer_id,
    project_scope,
    amount,
    state: SalesState::Draft,
    events: [],
  }
}

///|
fn allowed_transition(from : SalesState, to : SalesState) -> Bool {
  (from == SalesState::Draft && to == SalesState::Reserved) ||
  (from == SalesState::Reserved && to == SalesState::Signed) ||
  (from == SalesState::Signed && to == SalesState::Fulfilled) ||
  (from == SalesState::Draft && to == SalesState::Cancelled) ||
  (from == SalesState::Reserved && to == SalesState::Cancelled) ||
  (from == SalesState::Signed && to == SalesState::Cancelled)
}

///|
fn capability_for(state : SalesState) -> String {
  match state {
    SalesState::Reserved => "sales:reserve"
    SalesState::Signed => "sales:sign"
    SalesState::Fulfilled => "sales:fulfill"
    SalesState::Cancelled => "sales:cancel"
    SalesState::Draft => "sales:create"
  }
}

///|
pub fn SalesAgreement::transition(
  self : SalesAgreement,
  to : SalesState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> SalesAgreement raise SalesError {
  if !allowed_transition(self.state, to) {
    raise SalesError::InvalidTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SalesError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id })
  { ..self, state: to, events }
}

///|
/// Open a customer receivable only after the sales agreement is fulfilled.
/// Sales recognition and receivable authority are separate grants; collection
/// cash and revenue-accounting policy remain later events.
pub fn SalesAgreement::open_receivable(
  self : SalesAgreement,
  receivable_id~ : String,
  actor_id~ : String,
  sales_grant~ : @foundation.AuthorityGrant,
  receivable_grant~ : @foundation.AuthorityGrant,
) -> @receivable.Receivable raise SalesError {
  if self.state != SalesState::Fulfilled {
    raise SalesError::InvalidTransition
  }
  @foundation.require_authority(
    sales_grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:receivable-open",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SalesError::NotAuthorized(error)
  }
  @receivable.Receivable::open(
    receivable_id~,
    source_id=self.agreement_id,
    principal_id=self.principal_id,
    customer_id=self.customer_id,
    amount=self.amount,
    actor_id~,
    grant=receivable_grant,
  ) catch {
    error => raise SalesError::Receivable(error)
  }
}
