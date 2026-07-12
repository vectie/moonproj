///|
pub(all) enum InvoiceState {
  Draft
  Issued
  Accepted
  PartiallyPaid
  Paid
  Voided
} derive(Debug, Eq)

///|
pub(all) struct InvoiceEvent {
  from : InvoiceState
  to : InvoiceState
  actor_id : String
} derive(Debug, Eq)

///|
pub(all) struct Invoice {
  invoice_id : String
  principal_id : String
  customer_id : String
  source_id : String
  amount : @finance.Money
  paid_minor : Int64
  state : InvoiceState
  events : Array[InvoiceEvent]
} derive(Debug, Eq)

///|
pub(all) suberror InvoiceError {
  EmptyIdentifier
  InvalidAmount
  InvalidTransition
  InvalidState
  Overpayment
  Receivable(@receivable.ReceivableError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Invoice::new(
  invoice_id~ : String,
  principal_id~ : String,
  customer_id~ : String,
  source_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Invoice raise InvoiceError {
  if invoice_id.trim() == "" ||
    principal_id.trim() == "" ||
    customer_id.trim() == "" ||
    source_id.trim() == "" {
    raise InvoiceError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise InvoiceError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="invoice:create",
    scope="customer:\{customer_id}",
    amount_minor=amount.minor,
  ) catch {
    error => raise InvoiceError::NotAuthorized(error)
  }
  {
    invoice_id,
    principal_id,
    customer_id,
    source_id,
    amount,
    paid_minor: 0,
    state: InvoiceState::Draft,
    events: [],
  }
}

///|
fn allowed_transition(from : InvoiceState, to : InvoiceState) -> Bool {
  (from == InvoiceState::Draft && to == InvoiceState::Issued) ||
  (from == InvoiceState::Issued && to == InvoiceState::Accepted) ||
  (from == InvoiceState::Draft && to == InvoiceState::Voided) ||
  (from == InvoiceState::Issued && to == InvoiceState::Voided) ||
  (from == InvoiceState::Accepted && to == InvoiceState::Voided)
}

///|
fn capability_for(state : InvoiceState) -> String {
  match state {
    InvoiceState::Issued => "invoice:issue"
    InvoiceState::Accepted => "invoice:accept"
    InvoiceState::Voided => "invoice:void"
    _ => "invoice:create"
  }
}

///|
pub fn Invoice::transition(
  self : Invoice,
  to : InvoiceState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Invoice raise InvoiceError {
  if !allowed_transition(self.state, to) {
    raise InvoiceError::InvalidTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope="customer:\{self.customer_id}",
    amount_minor=self.amount.minor,
  ) catch {
    error => raise InvoiceError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id })
  { ..self, state: to, events }
}

///|
/// Open a customer receivable only after the invoice is accepted. Invoice
/// acceptance and receivable recognition use separate authority grants;
/// collection and cash accounting remain later, independent events.
pub fn Invoice::open_receivable(
  self : Invoice,
  receivable_id~ : String,
  actor_id~ : String,
  invoice_grant~ : @foundation.AuthorityGrant,
  receivable_grant~ : @foundation.AuthorityGrant,
) -> @receivable.Receivable raise InvoiceError {
  if self.state != InvoiceState::Accepted {
    raise InvoiceError::InvalidState
  }
  @foundation.require_authority(
    invoice_grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="invoice:receivable-open",
    scope="customer:\{self.customer_id}",
    amount_minor=self.amount.minor,
  ) catch {
    error => raise InvoiceError::NotAuthorized(error)
  }
  @receivable.Receivable::open(
    receivable_id~,
    source_id=self.invoice_id,
    principal_id=self.principal_id,
    customer_id=self.customer_id,
    amount=self.amount,
    actor_id~,
    grant=receivable_grant,
  ) catch {
    error => raise InvoiceError::Receivable(error)
  }
}

///|
pub fn Invoice::outstanding_minor(self : Invoice) -> Int64 {
  self.amount.minor - self.paid_minor
}

///|
pub fn Invoice::record_payment(
  self : Invoice,
  amount_minor~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Invoice raise InvoiceError {
  if self.state != InvoiceState::Accepted &&
    self.state != InvoiceState::PartiallyPaid {
    raise InvoiceError::InvalidState
  }
  if amount_minor <= 0 || amount_minor > self.outstanding_minor() {
    raise InvoiceError::Overpayment
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="invoice:collect",
    scope="customer:\{self.customer_id}",
    amount_minor~,
  ) catch {
    error => raise InvoiceError::NotAuthorized(error)
  }
  let paid_minor = self.paid_minor + amount_minor
  let state = if paid_minor == self.amount.minor {
    InvoiceState::Paid
  } else {
    InvoiceState::PartiallyPaid
  }
  { ..self, paid_minor, state }
}
