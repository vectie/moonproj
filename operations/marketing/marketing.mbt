///|
pub(all) enum CampaignState {
  Planning
  Active
  Completed
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct MarketingCampaign {
  campaign_id : String
  principal_id : String
  project_scope : String
  name : String
  budget : @finance.Money
  actual_cost : @finance.Money
  state : CampaignState
} derive(Debug, Eq)

///|
pub(all) enum PlacementState {
  Planned
  Placed
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct MarketingPlacement {
  placement_id : String
  campaign_id : String
  principal_id : String
  project_scope : String
  channel : String
  amount : @finance.Money
  leads : Int
  state : PlacementState
} derive(Debug, Eq)

///|
pub(all) suberror MarketingError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  BudgetExceeded
  InvalidState
  InvalidLeads
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn MarketingCampaign::new(
  campaign_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  name~ : String,
  budget~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingCampaign raise MarketingError {
  if campaign_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    name.trim() == "" {
    raise MarketingError::EmptyIdentifier
  }
  if budget.minor <= 0 {
    raise MarketingError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="marketing:campaign:create",
    scope=project_scope,
    amount_minor=budget.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  let zero = @finance.Money::zero(currency=budget.currency) catch {
    error => raise MarketingError::Money(error)
  }
  {
    campaign_id,
    principal_id,
    project_scope,
    name,
    budget,
    actual_cost: zero,
    state: CampaignState::Planning,
  }
}

///|
pub fn MarketingCampaign::activate(
  self : MarketingCampaign,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingCampaign raise MarketingError {
  if self.state != CampaignState::Planning {
    raise MarketingError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="marketing:campaign:activate",
    scope=self.project_scope,
    amount_minor=self.budget.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  { ..self, state: CampaignState::Active }
}

///|
pub fn MarketingCampaign::record_spend(
  self : MarketingCampaign,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingCampaign raise MarketingError {
  if self.state != CampaignState::Active {
    raise MarketingError::InvalidState
  }
  if amount.minor <= 0 {
    raise MarketingError::InvalidAmount
  }
  if amount.currency != self.budget.currency {
    raise MarketingError::CurrencyMismatch
  }
  if self.actual_cost.minor + amount.minor > self.budget.minor {
    raise MarketingError::BudgetExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="marketing:spend",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  let actual_cost = @finance.Money::new(
    minor=self.actual_cost.minor + amount.minor,
    currency=self.budget.currency,
  ) catch {
    error => raise MarketingError::Money(error)
  }
  { ..self, actual_cost, }
}

///|
pub fn MarketingCampaign::complete(
  self : MarketingCampaign,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingCampaign raise MarketingError {
  if self.state != CampaignState::Active {
    raise MarketingError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="marketing:campaign:complete",
    scope=self.project_scope,
    amount_minor=self.actual_cost.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  { ..self, state: CampaignState::Completed }
}

///|
pub fn MarketingPlacement::new(
  placement_id~ : String,
  campaign : MarketingCampaign,
  channel~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingPlacement raise MarketingError {
  if placement_id.trim() == "" || channel.trim() == "" {
    raise MarketingError::EmptyIdentifier
  }
  if campaign.state != CampaignState::Active {
    raise MarketingError::InvalidState
  }
  if amount.minor <= 0 {
    raise MarketingError::InvalidAmount
  }
  if amount.currency != campaign.budget.currency {
    raise MarketingError::CurrencyMismatch
  }
  if campaign.actual_cost.minor + amount.minor > campaign.budget.minor {
    raise MarketingError::BudgetExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=campaign.principal_id,
    actor_id~,
    capability="marketing:placement:create",
    scope=campaign.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  {
    placement_id,
    campaign_id: campaign.campaign_id,
    principal_id: campaign.principal_id,
    project_scope: campaign.project_scope,
    channel,
    amount,
    leads: 0,
    state: PlacementState::Planned,
  }
}

///|
pub fn MarketingPlacement::place(
  self : MarketingPlacement,
  leads~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MarketingPlacement raise MarketingError {
  if self.state != PlacementState::Planned {
    raise MarketingError::InvalidState
  }
  if leads < 0 {
    raise MarketingError::InvalidLeads
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="marketing:placement:place",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise MarketingError::NotAuthorized(error)
  }
  { ..self, leads, state: PlacementState::Placed }
}
