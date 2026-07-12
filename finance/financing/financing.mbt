///|
pub(all) enum FacilityState {
  Draft
  Approved
  Active
  PartiallyRepaid
  Closed
  Defaulted
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct FacilityEvent {
  from : FacilityState
  to : FacilityState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct FinancingFacility {
  facility_id : String
  principal_id : String
  project_scope : String
  lender_id : String
  limit_amount : @finance.Money
  drawn_amount : @finance.Money
  outstanding_principal : @finance.Money
  annual_rate_bps : Int64
  state : FacilityState
  events : Array[FacilityEvent]
} derive(Debug, Eq)

///|
pub(all) suberror FinancingError {
  EmptyIdentifier
  InvalidAmount
  InvalidRate
  CurrencyMismatch
  InvalidState
  LimitExceeded
  OverRepayment
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn FinancingFacility::new(
  facility_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  lender_id~ : String,
  limit_amount~ : @finance.Money,
  annual_rate_bps~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  if facility_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    lender_id.trim() == "" {
    raise FinancingError::EmptyIdentifier
  }
  if limit_amount.minor <= 0 {
    raise FinancingError::InvalidAmount
  }
  if annual_rate_bps < 0L || annual_rate_bps > 10000L {
    raise FinancingError::InvalidRate
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="financing:create",
    scope=project_scope,
    amount_minor=limit_amount.minor,
  ) catch {
    error => raise FinancingError::NotAuthorized(error)
  }
  let zero = @finance.Money::zero(currency=limit_amount.currency) catch {
    error => raise FinancingError::Money(error)
  }
  {
    facility_id,
    principal_id,
    project_scope,
    lender_id,
    limit_amount,
    drawn_amount: zero,
    outstanding_principal: zero,
    annual_rate_bps,
    state: FacilityState::Draft,
    events: [],
  }
}

///|
fn FinancingFacility::transition(
  self : FinancingFacility,
  to : FacilityState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  let allowed = (
      self.state == FacilityState::Draft && to == FacilityState::Approved
    ) ||
    (self.state == FacilityState::Approved && to == FacilityState::Active) ||
    (
      (
        self.state == FacilityState::Draft ||
        self.state == FacilityState::Approved
      ) &&
      to == FacilityState::Cancelled
    ) ||
    (
      (
        self.state == FacilityState::Active ||
        self.state == FacilityState::PartiallyRepaid
      ) &&
      to == FacilityState::Defaulted
    )
  if !allowed {
    raise FinancingError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.limit_amount.minor,
  ) catch {
    error => raise FinancingError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn FinancingFacility::approve(
  self : FinancingFacility,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  self.transition(
    FacilityState::Approved,
    capability="financing:approve",
    actor_id~,
    grant~,
  )
}

///|
pub fn FinancingFacility::activate(
  self : FinancingFacility,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  self.transition(
    FacilityState::Active,
    capability="financing:activate",
    actor_id~,
    grant~,
  )
}

///|
pub fn FinancingFacility::available_minor(self : FinancingFacility) -> Int64 {
  self.limit_amount.minor - self.drawn_amount.minor
}

///|
pub fn FinancingFacility::draw(
  self : FinancingFacility,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  if self.state != FacilityState::Active &&
    self.state != FacilityState::PartiallyRepaid {
    raise FinancingError::InvalidState
  }
  if amount.minor <= 0 {
    raise FinancingError::InvalidAmount
  }
  if amount.currency != self.limit_amount.currency {
    raise FinancingError::CurrencyMismatch
  }
  if amount.minor > self.available_minor() {
    raise FinancingError::LimitExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="financing:draw",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise FinancingError::NotAuthorized(error)
  }
  let drawn = @finance.Money::new(
    minor=self.drawn_amount.minor + amount.minor,
    currency=self.limit_amount.currency,
  ) catch {
    error => raise FinancingError::Money(error)
  }
  let outstanding = @finance.Money::new(
    minor=self.outstanding_principal.minor + amount.minor,
    currency=self.limit_amount.currency,
  ) catch {
    error => raise FinancingError::Money(error)
  }
  {
    ..self,
    drawn_amount: drawn,
    outstanding_principal: outstanding,
    state: FacilityState::Active,
  }
}

///|
pub fn FinancingFacility::repay(
  self : FinancingFacility,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  if self.state != FacilityState::Active &&
    self.state != FacilityState::PartiallyRepaid {
    raise FinancingError::InvalidState
  }
  if amount.minor <= 0 {
    raise FinancingError::InvalidAmount
  }
  if amount.currency != self.limit_amount.currency {
    raise FinancingError::CurrencyMismatch
  }
  if amount.minor > self.outstanding_principal.minor {
    raise FinancingError::OverRepayment
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="financing:repay",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise FinancingError::NotAuthorized(error)
  }
  let outstanding = @finance.Money::new(
    minor=self.outstanding_principal.minor - amount.minor,
    currency=self.limit_amount.currency,
  ) catch {
    error => raise FinancingError::Money(error)
  }
  let state = if outstanding.is_zero() {
    FacilityState::Closed
  } else {
    FacilityState::PartiallyRepaid
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: state,
    actor_id,
    capability: "financing:repay",
  })
  { ..self, outstanding_principal: outstanding, state, events }
}

///|
pub fn FinancingFacility::accrue_interest(
  self : FinancingFacility,
  days : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (@finance.Money, FinancingFacility) raise FinancingError {
  if days <= 0 {
    raise FinancingError::InvalidAmount
  }
  if self.state != FacilityState::Active &&
    self.state != FacilityState::PartiallyRepaid {
    raise FinancingError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="financing:accrue",
    scope=self.project_scope,
    amount_minor=self.outstanding_principal.minor,
  ) catch {
    error => raise FinancingError::NotAuthorized(error)
  }
  let denominator : Int64 = 10000L * 365L
  let interest_minor = (
      self.outstanding_principal.minor * self.annual_rate_bps * days +
      denominator / 2L
    ) /
    denominator
  let interest = @finance.Money::new(
    minor=interest_minor,
    currency=self.limit_amount.currency,
  ) catch {
    error => raise FinancingError::Money(error)
  }
  (interest, self)
}

///|
pub fn FinancingFacility::default(
  self : FinancingFacility,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FinancingFacility raise FinancingError {
  self.transition(
    FacilityState::Defaulted,
    capability="financing:default",
    actor_id~,
    grant~,
  )
}
