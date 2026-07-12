///|
pub(all) enum SupplierState {
  Draft
  PendingReview
  Active
  Suspended
  Blacklisted
  Voided
} derive(Debug, Eq)

///|
pub(all) enum SupplierEvaluation {
  Unrated
  Reviewed
  Qualified
  Unqualified
  Strategic
} derive(Debug, Eq)

///|
pub(all) struct SupplierEvent {
  from : SupplierState
  to : SupplierState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct Supplier {
  supplier_id : String
  principal_id : String
  scope : String
  supplier_code : String
  name : String
  category_code : String
  state : SupplierState
  evaluation : SupplierEvaluation
  events : Array[SupplierEvent]
} derive(Debug, Eq)

///|
pub(all) suberror SupplierError {
  EmptyIdentifier
  InvalidState
  InvalidEvaluation
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Supplier::new(
  supplier_id~ : String,
  principal_id~ : String,
  scope~ : String,
  supplier_code~ : String,
  name~ : String,
  category_code~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Supplier raise SupplierError {
  if supplier_id.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" ||
    supplier_code.trim() == "" ||
    name.trim() == "" ||
    category_code.trim() == "" {
    raise SupplierError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="supplier:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise SupplierError::NotAuthorized(error)
  }
  {
    supplier_id,
    principal_id,
    scope,
    supplier_code,
    name,
    category_code,
    state: SupplierState::Draft,
    evaluation: SupplierEvaluation::Unrated,
    events: [],
  }
}

///|
pub fn Supplier::submit_review(
  self : Supplier,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Supplier raise SupplierError {
  if self.state != SupplierState::Draft {
    raise SupplierError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="supplier:submit",
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise SupplierError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: SupplierState::PendingReview,
    actor_id,
    capability: "supplier:submit",
  })
  { ..self, state: SupplierState::PendingReview, events }
}

///|
pub fn Supplier::review(
  self : Supplier,
  evaluation~ : SupplierEvaluation,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Supplier raise SupplierError {
  if self.state != SupplierState::PendingReview {
    raise SupplierError::InvalidState
  }
  if evaluation == SupplierEvaluation::Unrated {
    raise SupplierError::InvalidEvaluation
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="supplier:review",
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise SupplierError::NotAuthorized(error)
  }
  let state = match evaluation {
    SupplierEvaluation::Qualified | SupplierEvaluation::Strategic =>
      SupplierState::Active
    SupplierEvaluation::Reviewed
    | SupplierEvaluation::Unqualified
    | SupplierEvaluation::Unrated => SupplierState::Suspended
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: state,
    actor_id,
    capability: "supplier:review",
  })
  { ..self, state, evaluation, events }
}

///|
pub fn Supplier::blacklist(
  self : Supplier,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Supplier raise SupplierError {
  if self.state == SupplierState::Voided {
    raise SupplierError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="supplier:blacklist",
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise SupplierError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: SupplierState::Blacklisted,
    actor_id,
    capability: "supplier:blacklist",
  })
  { ..self, state: SupplierState::Blacklisted, events }
}

///|
pub(all) enum TenderState {
  Planning
  Publishing
  Bidding
  Awarded
  Completed
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct TenderBid {
  supplier_id : String
  amount : @finance.Money
  actor_id : String
} derive(Debug, Eq)

///|
pub(all) struct TenderEvent {
  from : TenderState
  to : TenderState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct TenderPlan {
  tender_id : String
  principal_id : String
  project_scope : String
  name : String
  category : String
  estimated_amount : @finance.Money
  state : TenderState
  bids : Array[TenderBid]
  awarded_supplier_id : String?
  awarded_amount : @finance.Money?
  events : Array[TenderEvent]
} derive(Debug, Eq)

///|
pub(all) suberror TenderError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  InvalidState
  SupplierNotEligible
  NoMatchingBid
  DuplicateBid
  ProjectionIdentity
  Projection(@store.ProjectionError)
  Commitment(@commitment.CommitmentError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn TenderPlan::new(
  tender_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  name~ : String,
  category~ : String,
  estimated_amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  if tender_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    name.trim() == "" ||
    category.trim() == "" {
    raise TenderError::EmptyIdentifier
  }
  if estimated_amount.minor <= 0 {
    raise TenderError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="tender:create",
    scope=project_scope,
    amount_minor=estimated_amount.minor,
  ) catch {
    error => raise TenderError::NotAuthorized(error)
  }
  {
    tender_id,
    principal_id,
    project_scope,
    name,
    category,
    estimated_amount,
    state: TenderState::Planning,
    bids: [],
    awarded_supplier_id: None,
    awarded_amount: None,
    events: [],
  }
}

///|
fn TenderPlan::transition_internal(
  self : TenderPlan,
  to : TenderState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  let allowed = (
      self.state == TenderState::Planning && to == TenderState::Publishing
    ) ||
    (self.state == TenderState::Publishing && to == TenderState::Bidding) ||
    (self.state == TenderState::Awarded && to == TenderState::Completed) ||
    (
      (
        self.state == TenderState::Planning ||
        self.state == TenderState::Publishing ||
        self.state == TenderState::Bidding
      ) &&
      to == TenderState::Cancelled
    )
  if !allowed {
    raise TenderError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.estimated_amount.minor,
  ) catch {
    error => raise TenderError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn TenderPlan::publish(
  self : TenderPlan,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  self.transition_internal(
    TenderState::Publishing,
    capability="tender:publish",
    actor_id~,
    grant~,
  )
}

///|
pub fn TenderPlan::open_bidding(
  self : TenderPlan,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  self.transition_internal(
    TenderState::Bidding,
    capability="tender:open",
    actor_id~,
    grant~,
  )
}

///|
pub fn TenderPlan::add_bid(
  self : TenderPlan,
  supplier : Supplier,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  if self.state != TenderState::Bidding {
    raise TenderError::InvalidState
  }
  if supplier.state != SupplierState::Active {
    raise TenderError::SupplierNotEligible
  }
  if amount.minor <= 0 {
    raise TenderError::InvalidAmount
  }
  if amount.currency != self.estimated_amount.currency {
    raise TenderError::CurrencyMismatch
  }
  for bid in self.bids {
    if bid.supplier_id == supplier.supplier_id {
      raise TenderError::DuplicateBid
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="tender:bid",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise TenderError::NotAuthorized(error)
  }
  let bids = self.bids.copy()
  bids.push({ supplier_id: supplier.supplier_id, amount, actor_id })
  { ..self, bids, }
}

///|
pub fn TenderPlan::award(
  self : TenderPlan,
  supplier : Supplier,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  if self.state != TenderState::Bidding {
    raise TenderError::InvalidState
  }
  if supplier.state != SupplierState::Active {
    raise TenderError::SupplierNotEligible
  }
  let mut awarded_amount : @finance.Money? = None
  for bid in self.bids {
    if bid.supplier_id == supplier.supplier_id {
      awarded_amount = Some(bid.amount)
    }
  }
  let awarded_amount = match awarded_amount {
    Some(amount) => amount
    None => raise TenderError::NoMatchingBid
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="tender:award",
    scope=self.project_scope,
    amount_minor=awarded_amount.minor,
  ) catch {
    error => raise TenderError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: TenderState::Awarded,
    actor_id,
    capability: "tender:award",
  })
  {
    ..self,
    state: TenderState::Awarded,
    awarded_supplier_id: Some(supplier.supplier_id),
    awarded_amount: Some(awarded_amount),
    events,
  }
}

///|
pub fn TenderPlan::complete(
  self : TenderPlan,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> TenderPlan raise TenderError {
  self.transition_internal(
    TenderState::Completed,
    capability="tender:complete",
    actor_id~,
    grant~,
  )
}

///|
/// Convert an awarded tender into a draft commitment only through an explicit
/// cross-domain boundary. Award authority and commitment-creation authority
/// are separate grants so procurement cannot silently create an obligation or
/// bypass segregation of duties.
pub fn TenderPlan::create_commitment(
  self : TenderPlan,
  commitment_id~ : String,
  actor_id~ : String,
  award_grant~ : @foundation.AuthorityGrant,
  commitment_grant~ : @foundation.AuthorityGrant,
) -> @commitment.Commitment raise TenderError {
  if commitment_id.trim() == "" {
    raise TenderError::InvalidState
  }
  if self.state != TenderState::Awarded {
    raise TenderError::InvalidState
  }
  let supplier_id = match self.awarded_supplier_id {
    Some(value) => value
    None => raise TenderError::NoMatchingBid
  }
  let amount = match self.awarded_amount {
    Some(value) => value
    None => raise TenderError::NoMatchingBid
  }
  @foundation.require_authority(
    award_grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="tender:award-to-commitment",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise TenderError::NotAuthorized(error)
  }
  @commitment.Commitment::new(
    commitment_id~,
    principal_id=self.principal_id,
    project_scope=self.project_scope,
    counterparty_id=supplier_id,
    amount~,
    actor_id~,
    grant=commitment_grant,
  ) catch {
    error => raise TenderError::Commitment(error)
  }
}
