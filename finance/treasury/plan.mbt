///|
pub(all) enum CashPlanDirection {
  Inflow
  Outflow
} derive(Debug, Eq)

///|
pub(all) enum CashPlanState {
  Planned
  Confirmed
  Actualized
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct CashPlan {
  plan_id : String
  principal_id : String
  project_scope : String
  period : String
  category : String
  direction : CashPlanDirection
  planned_amount : @finance.Money
  actual_amount : @finance.Money
  state : CashPlanState
} derive(Debug, Eq)

///|
pub(all) enum DispatchState {
  Pending
  Approved
  Executed
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct FundDispatch {
  dispatch_id : String
  principal_id : String
  from_project : String
  to_project : String
  amount : @finance.Money
  reason : String
  state : DispatchState
} derive(Debug, Eq)

///|
pub(all) suberror TreasuryPlanError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  InvalidState
  SameProject
  OverActualization
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn CashPlan::new(
  plan_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  period~ : String,
  category~ : String,
  direction~ : CashPlanDirection,
  planned_amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashPlan raise TreasuryPlanError {
  if plan_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    period.trim() == "" ||
    category.trim() == "" {
    raise TreasuryPlanError::EmptyIdentifier
  }
  if planned_amount.minor <= 0 {
    raise TreasuryPlanError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="treasury:plan:create",
    scope=project_scope,
    amount_minor=planned_amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  let zero = @finance.Money::zero(currency=planned_amount.currency) catch {
    _ => raise TreasuryPlanError::CurrencyMismatch
  }
  {
    plan_id,
    principal_id,
    project_scope,
    period,
    category,
    direction,
    planned_amount,
    actual_amount: zero,
    state: CashPlanState::Planned,
  }
}

///|
pub fn CashPlan::confirm(
  self : CashPlan,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashPlan raise TreasuryPlanError {
  if self.state != CashPlanState::Planned {
    raise TreasuryPlanError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:plan:confirm",
    scope=self.project_scope,
    amount_minor=self.planned_amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  { ..self, state: CashPlanState::Confirmed }
}

///|
pub fn CashPlan::actualize(
  self : CashPlan,
  actual_amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CashPlan raise TreasuryPlanError {
  if self.state != CashPlanState::Confirmed {
    raise TreasuryPlanError::InvalidState
  }
  if actual_amount.minor <= 0 {
    raise TreasuryPlanError::InvalidAmount
  }
  if actual_amount.currency != self.planned_amount.currency {
    raise TreasuryPlanError::CurrencyMismatch
  }
  if actual_amount.minor > self.planned_amount.minor {
    raise TreasuryPlanError::OverActualization
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:plan:actualize",
    scope=self.project_scope,
    amount_minor=actual_amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  { ..self, actual_amount, state: CashPlanState::Actualized }
}

///|
pub fn FundDispatch::new(
  dispatch_id~ : String,
  principal_id~ : String,
  from_project~ : String,
  to_project~ : String,
  amount~ : @finance.Money,
  reason~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FundDispatch raise TreasuryPlanError {
  if dispatch_id.trim() == "" ||
    principal_id.trim() == "" ||
    from_project.trim() == "" ||
    to_project.trim() == "" ||
    reason.trim() == "" {
    raise TreasuryPlanError::EmptyIdentifier
  }
  if from_project == to_project {
    raise TreasuryPlanError::SameProject
  }
  if amount.minor <= 0 {
    raise TreasuryPlanError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="treasury:dispatch:create",
    scope=from_project,
    amount_minor=amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  {
    dispatch_id,
    principal_id,
    from_project,
    to_project,
    amount,
    reason,
    state: DispatchState::Pending,
  }
}

///|
pub fn FundDispatch::approve(
  self : FundDispatch,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FundDispatch raise TreasuryPlanError {
  if self.state != DispatchState::Pending {
    raise TreasuryPlanError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:dispatch:approve",
    scope=self.from_project,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  { ..self, state: DispatchState::Approved }
}

///|
pub fn FundDispatch::execute(
  self : FundDispatch,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> FundDispatch raise TreasuryPlanError {
  if self.state != DispatchState::Approved {
    raise TreasuryPlanError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:dispatch:execute",
    scope=self.from_project,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise TreasuryPlanError::NotAuthorized(error)
  }
  { ..self, state: DispatchState::Executed }
}
