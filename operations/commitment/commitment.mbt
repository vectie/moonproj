///|
pub(all) enum CommitmentState {
  Draft
  Submitted
  Approved
  Performed
  Settled
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct CommitmentEvent {
  from : CommitmentState
  to : CommitmentState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct Commitment {
  commitment_id : String
  principal_id : String
  project_scope : String
  counterparty_id : String
  amount : @finance.Money
  state : CommitmentState
  events : Array[CommitmentEvent]
} derive(Debug, Eq)

///|
pub(all) suberror CommitmentError {
  EmptyIdentifier
  EmptyReference
  InvalidStateTransition
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Commitment::new(
  commitment_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  counterparty_id~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Commitment raise CommitmentError {
  if commitment_id.trim() == "" {
    raise CommitmentError::EmptyIdentifier
  }
  if principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    counterparty_id.trim() == "" {
    raise CommitmentError::EmptyReference
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="commitment:create",
    scope=project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise CommitmentError::NotAuthorized(error)
  }
  {
    commitment_id,
    principal_id,
    project_scope,
    counterparty_id,
    amount,
    state: CommitmentState::Draft,
    events: [],
  }
}

///|
fn allowed_transition(from : CommitmentState, to : CommitmentState) -> Bool {
  (from == CommitmentState::Draft && to == CommitmentState::Submitted) ||
  (from == CommitmentState::Submitted && to == CommitmentState::Approved) ||
  (from == CommitmentState::Approved && to == CommitmentState::Performed) ||
  (from == CommitmentState::Performed && to == CommitmentState::Settled) ||
  (from == CommitmentState::Draft && to == CommitmentState::Cancelled) ||
  (from == CommitmentState::Submitted && to == CommitmentState::Cancelled) ||
  (from == CommitmentState::Approved && to == CommitmentState::Cancelled) ||
  (from == CommitmentState::Performed && to == CommitmentState::Cancelled)
}

///|
fn capability_for(state : CommitmentState) -> String {
  match state {
    CommitmentState::Submitted => "commitment:submit"
    CommitmentState::Approved => "commitment:approve"
    CommitmentState::Performed => "commitment:perform"
    CommitmentState::Settled => "commitment:settle"
    CommitmentState::Cancelled => "commitment:cancel"
    CommitmentState::Draft => "commitment:create"
  }
}

///|
pub fn Commitment::transition(
  self : Commitment,
  to : CommitmentState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Commitment raise CommitmentError {
  if !allowed_transition(self.state, to) {
    raise CommitmentError::InvalidStateTransition
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
    error => raise CommitmentError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn Commitment::is_terminal(self : Commitment) -> Bool {
  match self.state {
    CommitmentState::Settled | CommitmentState::Cancelled => true
    _ => false
  }
}
