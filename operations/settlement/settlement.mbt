///|
pub(all) enum SettlementState {
  Requested
  Approved
  Released
  Reconciled
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct SettlementEvent {
  from : SettlementState
  to : SettlementState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct Settlement {
  settlement_id : String
  commitment_id : String
  milestone_id : String?
  principal_id : String
  project_scope : String
  amount : @finance.Money
  state : SettlementState
  events : Array[SettlementEvent]
} derive(Debug, Eq)

///|
pub(all) suberror SettlementError {
  EmptyIdentifier
  InvalidCommitmentState
  InvalidAmount
  CurrencyMismatch
  AmountExceedsCommitment
  InvalidStateTransition
  ProjectionIdentity
  Projection(@store.ProjectionError)
  AccountingEvent(@accounting.AccountingEventError)
  NotAuthorized(@foundation.AuthorityError)
  Journal(@finance.LedgerError)
} derive(Debug, Eq)

///|
pub fn Settlement::request(
  commitment : @commitment.Commitment,
  settlement_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Settlement raise SettlementError {
  if settlement_id.trim() == "" {
    raise SettlementError::EmptyIdentifier
  }
  if commitment.state != @commitment.CommitmentState::Performed {
    raise SettlementError::InvalidCommitmentState
  }
  if amount.minor <= 0 {
    raise SettlementError::InvalidAmount
  }
  if amount.currency != commitment.amount.currency {
    raise SettlementError::CurrencyMismatch
  }
  if amount.minor > commitment.amount.minor {
    raise SettlementError::AmountExceedsCommitment
  }
  @foundation.require_authority(
    grant,
    principal_id=commitment.principal_id,
    actor_id~,
    capability="settlement:request",
    scope=commitment.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise SettlementError::NotAuthorized(error)
  }
  {
    settlement_id,
    commitment_id: commitment.commitment_id,
    milestone_id: None,
    principal_id: commitment.principal_id,
    project_scope: commitment.project_scope,
    amount,
    state: SettlementState::Requested,
    events: [],
  }
}

///|
/// Request settlement for a reached contract milestone while retaining the
/// milestone identity. This is a relationship link only; approval, release,
/// cash movement, and accounting remain separate transitions.
pub fn Settlement::request_with_milestone(
  commitment : @commitment.Commitment,
  milestone_id~ : String,
  settlement_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Settlement raise SettlementError {
  if milestone_id.trim() == "" {
    raise SettlementError::EmptyIdentifier
  }
  let settlement = Settlement::request(
    commitment,
    settlement_id~,
    amount~,
    actor_id~,
    grant~,
  )
  { ..settlement, milestone_id: Some(milestone_id) }
}

///|
fn allowed_transition(from : SettlementState, to : SettlementState) -> Bool {
  (from == SettlementState::Requested && to == SettlementState::Approved) ||
  (from == SettlementState::Approved && to == SettlementState::Released) ||
  (from == SettlementState::Released && to == SettlementState::Reconciled) ||
  (from == SettlementState::Requested && to == SettlementState::Rejected) ||
  (from == SettlementState::Approved && to == SettlementState::Rejected)
}

///|
fn capability_for(state : SettlementState) -> String {
  match state {
    SettlementState::Approved => "settlement:approve"
    SettlementState::Released => "settlement:release"
    SettlementState::Reconciled => "settlement:reconcile"
    SettlementState::Rejected => "settlement:reject"
    SettlementState::Requested => "settlement:request"
  }
}

///|
pub fn Settlement::transition(
  self : Settlement,
  to : SettlementState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Settlement raise SettlementError {
  if !allowed_transition(self.state, to) {
    raise SettlementError::InvalidStateTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SettlementError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
/// Project a released payment into a balanced payable-to-cash journal.
pub fn Settlement::to_journal(
  self : Settlement,
  payable_account~ : String,
  cash_account~ : String,
) -> @finance.JournalEntry raise SettlementError {
  if self.state != SettlementState::Released &&
    self.state != SettlementState::Reconciled {
    raise SettlementError::InvalidStateTransition
  }
  let entry : @finance.JournalEntry = {
    entry_id: "settlement/\{self.settlement_id}",
    description: "Release settlement for commitment \{self.commitment_id}",
    postings: [
      {
        account: payable_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: cash_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @finance.validate_journal(entry) catch {
    error => raise SettlementError::Journal(error)
  }
  entry
}
