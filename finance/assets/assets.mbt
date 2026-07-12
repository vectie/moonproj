///|
pub(all) enum AssetState {
  Proposed
  Capitalized
  Active
  Impaired
  Disposed
} derive(Debug, Eq)

///|
pub(all) struct AssetEvent {
  from : AssetState
  to : AssetState
  actor_id : String
  capability : String
  detail : String
} derive(Debug, Eq)

///|
pub(all) struct Asset {
  asset_id : String
  principal_id : String
  project_scope : String
  description : String
  acquisition_cost : @finance.Money
  residual_value : @finance.Money
  useful_life_months : Int
  accumulated_depreciation : Int64
  state : AssetState
  events : Array[AssetEvent]
} derive(Debug, Eq)

///|
pub(all) struct DepreciationEntry {
  asset_id : String
  period_id : String
  amount : @finance.Money
  remaining_book_value_minor : Int64
} derive(Debug, Eq)

///|
/// A reviewed disposal basis. Positive gain/loss is a gain; negative is a loss.
pub(all) struct DisposalEntry {
  asset_id : String
  proceeds : @finance.Money
  acquisition_cost_minor : Int64
  accumulated_depreciation_minor : Int64
  carrying_value_minor : Int64
  gain_loss_minor : Int64
} derive(Debug, Eq)

///|
pub(all) suberror AssetError {
  EmptyIdentifier
  InvalidAmount
  InvalidResidualValue
  InvalidUsefulLife
  CurrencyMismatch
  InvalidStateTransition
  InvalidDepreciationState
  FullyDepreciated
  InvalidDisposalState
  InvalidDisposalProceeds
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn Asset::new(
  asset_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  description~ : String,
  acquisition_cost~ : @finance.Money,
  residual_value~ : @finance.Money,
  useful_life_months~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Asset raise AssetError {
  if asset_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    description.trim() == "" {
    raise AssetError::EmptyIdentifier
  }
  if acquisition_cost.minor <= 0 || residual_value.minor < 0 {
    raise AssetError::InvalidAmount
  }
  if acquisition_cost.currency != residual_value.currency {
    raise AssetError::CurrencyMismatch
  }
  if residual_value.minor > acquisition_cost.minor {
    raise AssetError::InvalidResidualValue
  }
  if useful_life_months <= 0 {
    raise AssetError::InvalidUsefulLife
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="asset:propose",
    scope=project_scope,
    amount_minor=acquisition_cost.minor,
  ) catch {
    error => raise AssetError::NotAuthorized(error)
  }
  {
    asset_id,
    principal_id,
    project_scope,
    description,
    acquisition_cost,
    residual_value,
    useful_life_months,
    accumulated_depreciation: 0,
    state: AssetState::Proposed,
    events: [],
  }
}

///|
fn allowed_transition(from : AssetState, to : AssetState) -> Bool {
  (from == AssetState::Proposed && to == AssetState::Capitalized) ||
  (from == AssetState::Capitalized && to == AssetState::Active) ||
  (from == AssetState::Active && to == AssetState::Impaired) ||
  (from == AssetState::Active && to == AssetState::Disposed) ||
  (from == AssetState::Impaired && to == AssetState::Disposed)
}

///|
fn capability_for(state : AssetState) -> String {
  match state {
    AssetState::Capitalized => "asset:capitalize"
    AssetState::Active => "asset:activate"
    AssetState::Impaired => "asset:impair"
    AssetState::Disposed => "asset:dispose"
    AssetState::Proposed => "asset:propose"
  }
}

///|
pub fn Asset::transition(
  self : Asset,
  to : AssetState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Asset raise AssetError {
  if !allowed_transition(self.state, to) {
    raise AssetError::InvalidStateTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.acquisition_cost.minor,
  ) catch {
    error => raise AssetError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability, detail: "state" })
  { ..self, state: to, events }
}

///|
fn monthly_depreciation(asset : Asset) -> Int64 {
  let depreciable = asset.acquisition_cost.minor - asset.residual_value.minor
  Int64::div(depreciable, asset.useful_life_months.to_int64())
}

///|
pub fn Asset::depreciate(
  self : Asset,
  period_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (Asset, DepreciationEntry) raise AssetError {
  if period_id.trim() == "" {
    raise AssetError::EmptyIdentifier
  }
  if self.state != AssetState::Active && self.state != AssetState::Impaired {
    raise AssetError::InvalidDepreciationState
  }
  let book_value = self.acquisition_cost.minor - self.accumulated_depreciation
  let remaining = book_value - self.residual_value.minor
  if remaining <= 0 {
    raise AssetError::FullyDepreciated
  }
  let base = monthly_depreciation(self)
  let amount_minor = if base <= 0 || base > remaining {
    remaining
  } else {
    base
  }
  let amount = @finance.Money::new(
    minor=amount_minor,
    currency=self.acquisition_cost.currency,
  ) catch {
    error => raise AssetError::Money(error)
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="asset:depreciate",
    scope=self.project_scope,
    amount_minor~,
  ) catch {
    error => raise AssetError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: self.state,
    actor_id,
    capability: "asset:depreciate",
    detail: "period:" + period_id,
  })
  let next = {
    ..self,
    accumulated_depreciation: self.accumulated_depreciation + amount_minor,
    events,
  }
  (
    next,
    {
      asset_id: self.asset_id,
      period_id,
      amount,
      remaining_book_value_minor: book_value - amount_minor,
    },
  )
}

///| Build a disposal basis only after the asset lifecycle reaches Disposed.

///|
/// No cash or ledger effect is created by this method.
pub fn Asset::to_disposal_entry(
  self : Asset,
  proceeds~ : @finance.Money,
) -> DisposalEntry raise AssetError {
  if self.state != AssetState::Disposed {
    raise AssetError::InvalidDisposalState
  }
  if proceeds.minor < 0 {
    raise AssetError::InvalidDisposalProceeds
  }
  if proceeds.currency != self.acquisition_cost.currency {
    raise AssetError::CurrencyMismatch
  }
  let carrying = self.acquisition_cost.minor - self.accumulated_depreciation
  if carrying < 0 {
    raise AssetError::InvalidDisposalProceeds
  }
  {
    asset_id: self.asset_id,
    proceeds,
    acquisition_cost_minor: self.acquisition_cost.minor,
    accumulated_depreciation_minor: self.accumulated_depreciation,
    carrying_value_minor: carrying,
    gain_loss_minor: proceeds.minor - carrying,
  }
}

///| Construct the balanced derecognition journal. Posting remains a separate

///|
/// accounting-book authority decision.
pub fn DisposalEntry::to_journal(
  self : DisposalEntry,
  cash_or_receivable_account~ : String,
  asset_account~ : String,
  accumulated_depreciation_account~ : String,
  gain_account~ : String,
  loss_account~ : String,
) -> @finance.JournalEntry raise AssetError {
  if cash_or_receivable_account.trim() == "" ||
    asset_account.trim() == "" ||
    accumulated_depreciation_account.trim() == "" ||
    gain_account.trim() == "" ||
    loss_account.trim() == "" {
    raise AssetError::EmptyIdentifier
  }
  let postings : Array[@finance.Posting] = []
  if self.proceeds.minor > 0 {
    postings.push({
      account: cash_or_receivable_account,
      side: @finance.PostingSide::Debit,
      amount: self.proceeds,
    })
  }
  let accumulated = self.accumulated_depreciation_minor
  if accumulated > 0 {
    let accumulated_money = @finance.Money::new(
      minor=accumulated,
      currency=self.proceeds.currency,
    ) catch {
      error => raise AssetError::Money(error)
    }
    postings.push({
      account: accumulated_depreciation_account,
      side: @finance.PostingSide::Debit,
      amount: accumulated_money,
    })
  }
  if self.gain_loss_minor < 0 {
    let loss = @finance.Money::new(
      minor=-self.gain_loss_minor,
      currency=self.proceeds.currency,
    ) catch {
      error => raise AssetError::Money(error)
    }
    postings.push({
      account: loss_account,
      side: @finance.PostingSide::Debit,
      amount: loss,
    })
  }
  let asset_money = @finance.Money::new(
    minor=self.acquisition_cost_minor,
    currency=self.proceeds.currency,
  ) catch {
    error => raise AssetError::Money(error)
  }
  postings.push({
    account: asset_account,
    side: @finance.PostingSide::Credit,
    amount: asset_money,
  })
  if self.gain_loss_minor > 0 {
    let gain = @finance.Money::new(
      minor=self.gain_loss_minor,
      currency=self.proceeds.currency,
    ) catch {
      error => raise AssetError::Money(error)
    }
    postings.push({
      account: gain_account,
      side: @finance.PostingSide::Credit,
      amount: gain,
    })
  }
  let entry : @finance.JournalEntry = {
    entry_id: "asset-disposal/" + self.asset_id,
    description: "Disposal for asset " + self.asset_id,
    postings,
  }
  @finance.validate_journal(entry) catch {
    error => raise AssetError::Journal(error)
  }
  entry
}

///|
pub fn DepreciationEntry::to_journal(
  self : DepreciationEntry,
  expense_account~ : String,
  accumulated_depreciation_account~ : String,
) -> @finance.JournalEntry raise AssetError {
  if expense_account.trim() == "" ||
    accumulated_depreciation_account.trim() == "" {
    raise AssetError::EmptyIdentifier
  }
  let entry : @finance.JournalEntry = {
    entry_id: "asset-depreciation/" + self.asset_id + "/" + self.period_id,
    description: "Depreciation for asset " + self.asset_id,
    postings: [
      {
        account: expense_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: accumulated_depreciation_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @finance.validate_journal(entry) catch {
    error => raise AssetError::Journal(error)
  }
  entry
}
