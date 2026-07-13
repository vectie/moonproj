///|
pub(all) enum TaxObligationState {
  Draft
  Calculated
  Reviewed
  Filed
  Paid
  Voided
} derive(Debug, Eq)

///|
pub(all) struct TaxEvent {
  from : TaxObligationState
  to : TaxObligationState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct TaxObligation {
  tax_id : String
  principal_id : String
  project_scope : String
  source_reference : String
  jurisdiction : String
  category : String
  base_amount : @finance.Money
  tax_rate_bps : Int64
  withholding_rate_bps : Int64
  tax_amount : @finance.Money
  withholding_amount : @finance.Money
  state : TaxObligationState
  events : Array[TaxEvent]
} derive(Debug, Eq)

///|
pub(all) enum TaxFilingState {
  Prepared
  Submitted
  Accepted
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct TaxFilingEvent {
  from : TaxFilingState
  to : TaxFilingState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct TaxFiling {
  filing_id : String
  tax_id : String
  principal_id : String
  project_scope : String
  jurisdiction : String
  category : String
  filing_period : String
  authority_reference : String
  reported_tax_amount : @finance.Money
  state : TaxFilingState
  events : Array[TaxFilingEvent]
} derive(Debug, Eq)

///|
pub(all) suberror TaxError {
  EmptyIdentifier
  EmptyCategory
  EmptyJurisdiction
  EmptyFilingPeriod
  EmptyAuthorityReference
  InvalidAmount
  InvalidRate
  CurrencyMismatch
  InvalidTransition
  InvalidFilingState
  AccountingEvent(@accounting.AccountingEventError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn TaxObligation::new(
  tax_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  source_reference~ : String,
  jurisdiction~ : String,
  category~ : String,
  base_amount~ : @finance.Money,
  tax_rate_bps~ : Int64,
  withholding_rate_bps~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TaxObligation raise TaxError {
  if tax_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    source_reference.trim() == "" {
    raise TaxError::EmptyIdentifier
  }
  if jurisdiction.trim() == "" {
    raise TaxError::EmptyJurisdiction
  }
  if category.trim() == "" {
    raise TaxError::EmptyCategory
  }
  if base_amount.minor <= 0 {
    raise TaxError::InvalidAmount
  }
  validate_rate(tax_rate_bps)
  validate_rate(withholding_rate_bps)
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="tax:create",
    scope=project_scope,
    amount_minor=base_amount.minor,
  ) catch {
    error => raise TaxError::NotAuthorized(error)
  }
  let zero = @finance.Money::zero(currency=base_amount.currency) catch {
    error => raise TaxError::Money(error)
  }
  {
    tax_id,
    principal_id,
    project_scope,
    source_reference,
    jurisdiction,
    category,
    base_amount,
    tax_rate_bps,
    withholding_rate_bps,
    tax_amount: zero,
    withholding_amount: zero,
    state: TaxObligationState::Draft,
    events: [],
  }
}

///|
fn validate_rate(rate_bps : Int64) -> Unit raise TaxError {
  if rate_bps < 0L || rate_bps > 10000L {
    raise TaxError::InvalidRate
  }
}

///|
fn calculate_minor(base_minor : Int64, rate_bps : Int64) -> Int64 {
  (base_minor * rate_bps + 5000L) / 10000L
}

///|
pub fn TaxObligation::calculate(
  self : TaxObligation,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TaxObligation raise TaxError {
  if self.state != TaxObligationState::Draft {
    raise TaxError::InvalidTransition
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="tax:calculate",
    scope=self.project_scope,
    amount_minor=self.base_amount.minor,
  ) catch {
    error => raise TaxError::NotAuthorized(error)
  }
  let tax = @finance.Money::new(
    minor=calculate_minor(self.base_amount.minor, self.tax_rate_bps),
    currency=self.base_amount.currency,
  ) catch {
    error => raise TaxError::Money(error)
  }
  let withholding = @finance.Money::new(
    minor=calculate_minor(self.base_amount.minor, self.withholding_rate_bps),
    currency=self.base_amount.currency,
  ) catch {
    error => raise TaxError::Money(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: TaxObligationState::Calculated,
    actor_id,
    capability: "tax:calculate",
  })
  {
    ..self,
    tax_amount: tax,
    withholding_amount: withholding,
    state: TaxObligationState::Calculated,
    events,
  }
}

///| Prepare a filing from a reviewed obligation. Preparation is separate from

///|
/// submitting the filing and from marking the obligation Filed/Paid.
pub fn TaxObligation::prepare_filing(
  self : TaxObligation,
  filing_id~ : String,
  filing_period~ : String,
  authority_reference~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TaxFiling raise TaxError {
  if self.state != TaxObligationState::Reviewed {
    raise TaxError::InvalidFilingState
  }
  if filing_id.trim() == "" {
    raise TaxError::EmptyIdentifier
  }
  if filing_period.trim() == "" {
    raise TaxError::EmptyFilingPeriod
  }
  if authority_reference.trim() == "" {
    raise TaxError::EmptyAuthorityReference
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="tax:filing:prepare",
    scope=self.project_scope,
    amount_minor=self.tax_amount.minor,
  ) catch {
    error => raise TaxError::NotAuthorized(error)
  }
  {
    filing_id,
    tax_id: self.tax_id,
    principal_id: self.principal_id,
    project_scope: self.project_scope,
    jurisdiction: self.jurisdiction,
    category: self.category,
    filing_period,
    authority_reference,
    reported_tax_amount: self.tax_amount,
    state: TaxFilingState::Prepared,
    events: [],
  }
}

///|
fn filing_capability(state : TaxFilingState) -> String {
  match state {
    TaxFilingState::Submitted => "tax:filing:submit"
    TaxFilingState::Accepted => "tax:filing:accept"
    TaxFilingState::Rejected => "tax:filing:reject"
    TaxFilingState::Prepared => "tax:filing:prepare"
  }
}

///|
pub fn TaxFiling::transition(
  self : TaxFiling,
  to : TaxFilingState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TaxFiling raise TaxError {
  let allowed = (
      self.state == TaxFilingState::Prepared && to == TaxFilingState::Submitted
    ) ||
    (
      self.state == TaxFilingState::Submitted &&
      (to == TaxFilingState::Accepted || to == TaxFilingState::Rejected)
    )
  if !allowed {
    raise TaxError::InvalidTransition
  }
  let capability = filing_capability(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.reported_tax_amount.minor,
  ) catch {
    error => raise TaxError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
fn capability_for(state : TaxObligationState) -> String {
  match state {
    TaxObligationState::Reviewed => "tax:review"
    TaxObligationState::Filed => "tax:file"
    TaxObligationState::Paid => "tax:pay"
    TaxObligationState::Voided => "tax:void"
    TaxObligationState::Draft | TaxObligationState::Calculated =>
      "tax:transition"
  }
}

///|
fn allowed_transition(
  from : TaxObligationState,
  to : TaxObligationState,
) -> Bool {
  (from == TaxObligationState::Calculated && to == TaxObligationState::Reviewed) ||
  (from == TaxObligationState::Reviewed && to == TaxObligationState::Filed) ||
  (from == TaxObligationState::Filed && to == TaxObligationState::Paid) ||
  (
    (
      from == TaxObligationState::Draft ||
      from == TaxObligationState::Calculated ||
      from == TaxObligationState::Reviewed ||
      from == TaxObligationState::Filed
    ) &&
    to == TaxObligationState::Voided
  )
}

///|
pub fn TaxObligation::transition(
  self : TaxObligation,
  to : TaxObligationState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TaxObligation raise TaxError {
  if !allowed_transition(self.state, to) {
    raise TaxError::InvalidTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.base_amount.minor,
  ) catch {
    error => raise TaxError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}
