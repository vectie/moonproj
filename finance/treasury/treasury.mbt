///|
pub(all) enum CashAccountState {
  Open
  Suspended
  Closed
} derive(Debug, Eq)

///|
pub(all) enum CashDirection {
  Inflow
  Outflow
} derive(Debug, Eq)

///|
pub(all) enum CashMovementState {
  Requested
  Approved
  Released
  Reconciled
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct CashEvent {
  from : CashMovementState
  to : CashMovementState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct CashAccount {
  account_id : String
  principal_id : String
  project_scope : String
  currency : String
  bank_reference : String
  balance : @finance.Money
  state : CashAccountState
  applied_movement_ids : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct CashMovement {
  movement_id : String
  account_id : String
  principal_id : String
  project_scope : String
  reference_id : String
  amount : @finance.Money
  direction : CashDirection
  state : CashMovementState
  events : Array[CashEvent]
} derive(Debug, Eq)

///|
pub(all) suberror TreasuryError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  AccountNotOpen
  InvalidState
  InsufficientBalance
  DuplicateMovement
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn CashAccount::open(
  account_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  currency~ : String,
  bank_reference~ : String,
  opening_balance~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashAccount raise TreasuryError {
  if account_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    bank_reference.trim() == "" {
    raise TreasuryError::EmptyIdentifier
  }
  if opening_balance.minor < 0 {
    raise TreasuryError::InvalidAmount
  }
  if opening_balance.currency != currency {
    raise TreasuryError::CurrencyMismatch
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="treasury:account:create",
    scope=project_scope,
    amount_minor=opening_balance.minor,
  ) catch {
    error => raise TreasuryError::NotAuthorized(error)
  }
  {
    account_id,
    principal_id,
    project_scope,
    currency,
    bank_reference,
    balance: opening_balance,
    state: CashAccountState::Open,
    applied_movement_ids: [],
  }
}

///|
pub fn CashMovement::request(
  account : CashAccount,
  movement_id~ : String,
  reference_id~ : String,
  amount~ : @finance.Money,
  direction~ : CashDirection,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashMovement raise TreasuryError {
  if movement_id.trim() == "" || reference_id.trim() == "" {
    raise TreasuryError::EmptyIdentifier
  }
  if account.state != CashAccountState::Open {
    raise TreasuryError::AccountNotOpen
  }
  if amount.minor <= 0 {
    raise TreasuryError::InvalidAmount
  }
  if amount.currency != account.currency {
    raise TreasuryError::CurrencyMismatch
  }
  @foundation.require_authority(
    grant,
    principal_id=account.principal_id,
    actor_id~,
    capability="treasury:request",
    scope=account.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise TreasuryError::NotAuthorized(error)
  }
  {
    movement_id,
    account_id: account.account_id,
    principal_id: account.principal_id,
    project_scope: account.project_scope,
    reference_id,
    amount,
    direction,
    state: CashMovementState::Requested,
    events: [],
  }
}

///|
pub fn CashMovement::approve(
  self : CashMovement,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashMovement raise TreasuryError {
  if self.state != CashMovementState::Requested {
    raise TreasuryError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:approve",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise TreasuryError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: CashMovementState::Approved,
    actor_id,
    capability: "treasury:approve",
  })
  { ..self, state: CashMovementState::Approved, events }
}

///|
pub fn CashAccount::release(
  self : CashAccount,
  movement : CashMovement,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (CashAccount, CashMovement) raise TreasuryError {
  if self.state != CashAccountState::Open {
    raise TreasuryError::AccountNotOpen
  }
  if movement.account_id != self.account_id {
    raise TreasuryError::EmptyIdentifier
  }
  if movement.state != CashMovementState::Approved {
    raise TreasuryError::InvalidState
  }
  if movement.amount.currency != self.currency {
    raise TreasuryError::CurrencyMismatch
  }
  for applied_id in self.applied_movement_ids {
    if applied_id == movement.movement_id {
      raise TreasuryError::DuplicateMovement
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:release",
    scope=self.project_scope,
    amount_minor=movement.amount.minor,
  ) catch {
    error => raise TreasuryError::NotAuthorized(error)
  }
  let delta = match movement.direction {
    CashDirection::Inflow => movement.amount.minor
    CashDirection::Outflow => -movement.amount.minor
  }
  if delta < 0 && self.balance.minor < movement.amount.minor {
    raise TreasuryError::InsufficientBalance
  }
  let balance = @finance.Money::new(
    minor=self.balance.minor + delta,
    currency=self.currency,
  ) catch {
    error => raise TreasuryError::Money(error)
  }
  let movement_events = movement.events.copy()
  movement_events.push({
    from: movement.state,
    to: CashMovementState::Released,
    actor_id,
    capability: "treasury:release",
  })
  let applied = self.applied_movement_ids.copy()
  applied.push(movement.movement_id)
  (
    { ..self, balance, applied_movement_ids: applied },
    { ..movement, state: CashMovementState::Released, events: movement_events },
  )
}

///|
pub fn CashMovement::reconcile(
  self : CashMovement,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashMovement raise TreasuryError {
  if self.state != CashMovementState::Released {
    raise TreasuryError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:reconcile",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise TreasuryError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: CashMovementState::Reconciled,
    actor_id,
    capability: "treasury:reconcile",
  })
  { ..self, state: CashMovementState::Reconciled, events }
}
