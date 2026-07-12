///|
pub(all) enum MilestoneTrigger {
  Time
  Progress
  Event
} derive(Debug, Eq)

///|
pub(all) enum MilestoneState {
  Planned
  Eligible
  Reached
  Paid
  Overdue
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct MilestoneEvent {
  from : MilestoneState
  to : MilestoneState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct ContractMilestone {
  milestone_id : String
  commitment_id : String
  principal_id : String
  project_scope : String
  sequence : Int
  node_name : String
  trigger : MilestoneTrigger
  plan_amount : @finance.Money
  plan_pct_bps : Int64
  actual_amount : @finance.Money
  state : MilestoneState
  events : Array[MilestoneEvent]
} derive(Debug, Eq)

///|
pub(all) suberror MilestoneError {
  EmptyIdentifier
  InvalidCommitment
  InvalidSequence
  InvalidPercentage
  InvalidAmount
  CurrencyMismatch
  AmountExceedsCommitment
  InvalidState
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
  Settlement(@settlement.SettlementError)
} derive(Debug, Eq)

///|
pub fn ContractMilestone::new(
  commitment : @commitment.Commitment,
  milestone_id~ : String,
  sequence~ : Int,
  node_name~ : String,
  trigger~ : MilestoneTrigger,
  plan_amount~ : @finance.Money,
  plan_pct_bps~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  if milestone_id.trim() == "" || node_name.trim() == "" {
    raise MilestoneError::EmptyIdentifier
  }
  if sequence <= 0 {
    raise MilestoneError::InvalidSequence
  }
  if plan_pct_bps < 0L || plan_pct_bps > 10000L {
    raise MilestoneError::InvalidPercentage
  }
  if plan_amount.minor < 0 {
    raise MilestoneError::InvalidAmount
  }
  if plan_amount.currency != commitment.amount.currency {
    raise MilestoneError::CurrencyMismatch
  }
  if plan_amount.minor > commitment.amount.minor {
    raise MilestoneError::AmountExceedsCommitment
  }
  @foundation.require_authority(
    grant,
    principal_id=commitment.principal_id,
    actor_id~,
    capability="milestone:create",
    scope=commitment.project_scope,
    amount_minor=plan_amount.minor,
  ) catch {
    error => raise MilestoneError::NotAuthorized(error)
  }
  let zero = @finance.Money::zero(currency=plan_amount.currency) catch {
    error => raise MilestoneError::Money(error)
  }
  {
    milestone_id,
    commitment_id: commitment.commitment_id,
    principal_id: commitment.principal_id,
    project_scope: commitment.project_scope,
    sequence,
    node_name,
    trigger,
    plan_amount,
    plan_pct_bps,
    actual_amount: zero,
    state: MilestoneState::Planned,
    events: [],
  }
}

///|
fn ContractMilestone::transition(
  self : ContractMilestone,
  to : MilestoneState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  let allowed = (
      self.state == MilestoneState::Planned && to == MilestoneState::Eligible
    ) ||
    (self.state == MilestoneState::Eligible && to == MilestoneState::Reached) ||
    (self.state == MilestoneState::Reached && to == MilestoneState::Paid) ||
    (
      (
        self.state == MilestoneState::Planned ||
        self.state == MilestoneState::Eligible
      ) &&
      (to == MilestoneState::Overdue || to == MilestoneState::Cancelled)
    )
  if !allowed {
    raise MilestoneError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.plan_amount.minor,
  ) catch {
    error => raise MilestoneError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn ContractMilestone::mark_eligible(
  self : ContractMilestone,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  self.transition(
    MilestoneState::Eligible,
    capability="milestone:eligible",
    actor_id~,
    grant~,
  )
}

///|
pub fn ContractMilestone::reach(
  self : ContractMilestone,
  actual_amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  if self.state != MilestoneState::Eligible {
    raise MilestoneError::InvalidState
  }
  if actual_amount.minor < 0 {
    raise MilestoneError::InvalidAmount
  }
  if actual_amount.currency != self.plan_amount.currency {
    raise MilestoneError::CurrencyMismatch
  }
  if self.plan_amount.minor > 0 && actual_amount.minor > self.plan_amount.minor {
    raise MilestoneError::AmountExceedsCommitment
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="milestone:reach",
    scope=self.project_scope,
    amount_minor=actual_amount.minor,
  ) catch {
    error => raise MilestoneError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: MilestoneState::Reached,
    actor_id,
    capability: "milestone:reach",
  })
  { ..self, actual_amount, state: MilestoneState::Reached, events }
}

///|
pub fn ContractMilestone::mark_paid(
  self : ContractMilestone,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  self.transition(
    MilestoneState::Paid,
    capability="milestone:pay",
    actor_id~,
    grant~,
  )
}

///|
pub fn ContractMilestone::mark_overdue(
  self : ContractMilestone,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  self.transition(
    MilestoneState::Overdue,
    capability="milestone:overdue",
    actor_id~,
    grant~,
  )
}

///|
pub fn ContractMilestone::cancel(
  self : ContractMilestone,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ContractMilestone raise MilestoneError {
  self.transition(
    MilestoneState::Cancelled,
    capability="milestone:cancel",
    actor_id~,
    grant~,
  )
}

///|
/// Link a reached milestone to a requested settlement through separate
/// milestone and settlement authority grants. A milestone cannot approve or
/// release its own cash effect.
pub fn ContractMilestone::request_settlement(
  self : ContractMilestone,
  commitment : @commitment.Commitment,
  settlement_id~ : String,
  actor_id~ : String,
  milestone_grant~ : @foundation.AuthorityGrant,
  settlement_grant~ : @foundation.AuthorityGrant,
) -> @settlement.Settlement raise MilestoneError {
  if self.state != MilestoneState::Reached {
    raise MilestoneError::InvalidState
  }
  if self.commitment_id != commitment.commitment_id {
    raise MilestoneError::InvalidCommitment
  }
  @foundation.require_authority(
    milestone_grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="milestone:settlement-request",
    scope=self.project_scope,
    amount_minor=self.actual_amount.minor,
  ) catch {
    error => raise MilestoneError::NotAuthorized(error)
  }
  @settlement.Settlement::request_with_milestone(
    commitment,
    milestone_id=self.milestone_id,
    settlement_id~,
    amount=self.actual_amount,
    actor_id~,
    grant=settlement_grant,
  ) catch {
    error => raise MilestoneError::Settlement(error)
  }
}
