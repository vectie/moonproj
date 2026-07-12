///|
pub(all) enum MandateState {
  Draft
  Active
  Suspended
  Closed
} derive(Debug, Eq)

///|
pub(all) struct MandateEvent {
  from : MandateState
  to : MandateState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct InvestmentMandate {
  mandate_id : String
  principal_id : String
  project_scope : String
  base_currency : String
  max_exposure : @finance.Money
  max_single_position : @finance.Money
  state : MandateState
  events : Array[MandateEvent]
} derive(Debug, Eq)

///|
pub(all) enum ProposalState {
  Draft
  Analyzed
  Submitted
  Approved
  Rejected
  Executed
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct ProposalEvent {
  from : ProposalState
  to : ProposalState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct InvestmentProposal {
  proposal_id : String
  mandate_id : String
  principal_id : String
  project_scope : String
  instrument : String
  quantity : Int64
  price : @finance.Money
  notional : @finance.Money
  analysis : @analytics.AnalysisReport?
  state : ProposalState
  events : Array[ProposalEvent]
} derive(Debug, Eq)

///|
pub(all) struct InvestmentPosition {
  position_id : String
  mandate_id : String
  instrument : String
  quantity : Int64
  cost_basis : @finance.Money
} derive(Debug, Eq)

///|
pub(all) suberror InvestmentError {
  EmptyIdentifier
  InvalidAmount
  InvalidQuantity
  CurrencyMismatch
  MandateLimitExceeded
  InvalidState
  AnalysisMismatch
  ProjectionIdentity
  Projection(@store.ProjectionError)
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn InvestmentMandate::new(
  mandate_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  base_currency~ : String,
  max_exposure~ : @finance.Money,
  max_single_position~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentMandate raise InvestmentError {
  if mandate_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" {
    raise InvestmentError::EmptyIdentifier
  }
  if max_exposure.minor <= 0 || max_single_position.minor <= 0 {
    raise InvestmentError::InvalidAmount
  }
  if max_exposure.currency != base_currency ||
    max_single_position.currency != base_currency {
    raise InvestmentError::CurrencyMismatch
  }
  if max_single_position.minor > max_exposure.minor {
    raise InvestmentError::MandateLimitExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="investment:mandate:create",
    scope=project_scope,
    amount_minor=max_exposure.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  {
    mandate_id,
    principal_id,
    project_scope,
    base_currency,
    max_exposure,
    max_single_position,
    state: MandateState::Draft,
    events: [],
  }
}

///|
fn InvestmentMandate::transition(
  self : InvestmentMandate,
  to : MandateState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentMandate raise InvestmentError {
  let allowed = (
      self.state == MandateState::Draft && to == MandateState::Active
    ) ||
    (self.state == MandateState::Active && to == MandateState::Suspended) ||
    (self.state == MandateState::Suspended && to == MandateState::Active) ||
    (
      (
        self.state == MandateState::Draft ||
        self.state == MandateState::Active ||
        self.state == MandateState::Suspended
      ) &&
      to == MandateState::Closed
    )
  if !allowed {
    raise InvestmentError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.max_exposure.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn InvestmentMandate::activate(
  self : InvestmentMandate,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentMandate raise InvestmentError {
  self.transition(
    MandateState::Active,
    capability="investment:mandate:activate",
    actor_id~,
    grant~,
  )
}

///|
pub fn InvestmentMandate::suspend(
  self : InvestmentMandate,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentMandate raise InvestmentError {
  self.transition(
    MandateState::Suspended,
    capability="investment:mandate:suspend",
    actor_id~,
    grant~,
  )
}

///|
fn notional(
  quantity : Int64,
  price : @finance.Money,
) -> @finance.Money raise InvestmentError {
  if quantity <= 0 || price.minor <= 0 {
    raise InvestmentError::InvalidQuantity
  }
  @finance.Money::new(minor=quantity * price.minor, currency=price.currency) catch {
    error => raise InvestmentError::Money(error)
  }
}

///|
pub fn InvestmentMandate::propose(
  self : InvestmentMandate,
  proposal_id~ : String,
  instrument~ : String,
  quantity~ : Int64,
  price~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentProposal raise InvestmentError {
  if self.state != MandateState::Active {
    raise InvestmentError::InvalidState
  }
  if proposal_id.trim() == "" || instrument.trim() == "" {
    raise InvestmentError::EmptyIdentifier
  }
  if price.currency != self.base_currency {
    raise InvestmentError::CurrencyMismatch
  }
  let amount = notional(quantity, price)
  if amount.minor > self.max_single_position.minor ||
    amount.minor > self.max_exposure.minor {
    raise InvestmentError::MandateLimitExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:proposal:create",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  {
    proposal_id,
    mandate_id: self.mandate_id,
    principal_id: self.principal_id,
    project_scope: self.project_scope,
    instrument,
    quantity,
    price,
    notional: amount,
    analysis: None,
    state: ProposalState::Draft,
    events: [],
  }
}

///|
pub fn InvestmentProposal::attach_analysis(
  self : InvestmentProposal,
  report~ : @analytics.AnalysisReport,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentProposal raise InvestmentError {
  if self.state != ProposalState::Draft {
    raise InvestmentError::InvalidState
  }
  if report.instrument != self.instrument {
    raise InvestmentError::AnalysisMismatch
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:proposal:analyze",
    scope=self.project_scope,
    amount_minor=self.notional.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: ProposalState::Analyzed,
    actor_id,
    capability: "investment:proposal:analyze",
  })
  { ..self, analysis: Some(report), state: ProposalState::Analyzed, events }
}

///|
pub fn InvestmentProposal::submit(
  self : InvestmentProposal,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentProposal raise InvestmentError {
  if self.state != ProposalState::Analyzed {
    raise InvestmentError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:proposal:submit",
    scope=self.project_scope,
    amount_minor=self.notional.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: ProposalState::Submitted,
    actor_id,
    capability: "investment:proposal:submit",
  })
  { ..self, state: ProposalState::Submitted, events }
}

///|
pub fn InvestmentProposal::approve(
  self : InvestmentProposal,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentProposal raise InvestmentError {
  if self.state != ProposalState::Submitted {
    raise InvestmentError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:proposal:approve",
    scope=self.project_scope,
    amount_minor=self.notional.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: ProposalState::Approved,
    actor_id,
    capability: "investment:proposal:approve",
  })
  { ..self, state: ProposalState::Approved, events }
}

///|
pub fn InvestmentProposal::execute(
  self : InvestmentProposal,
  position_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (InvestmentProposal, InvestmentPosition) raise InvestmentError {
  if self.state != ProposalState::Approved {
    raise InvestmentError::InvalidState
  }
  if position_id.trim() == "" {
    raise InvestmentError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:execute",
    scope=self.project_scope,
    amount_minor=self.notional.minor,
  ) catch {
    error => raise InvestmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: self.state,
    to: ProposalState::Executed,
    actor_id,
    capability: "investment:execute",
  })
  (
    { ..self, state: ProposalState::Executed, events },
    {
      position_id,
      mandate_id: self.mandate_id,
      instrument: self.instrument,
      quantity: self.quantity,
      cost_basis: self.notional,
    },
  )
}
