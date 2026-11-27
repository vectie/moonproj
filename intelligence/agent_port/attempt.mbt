///|
#derive(Debug, Eq)
pub(all) enum ExecutionPhase {
  Queued
  Ready
  Claimed
  Running
  WaitingForPeer
  WaitingForChildren
  WaitingForReview
  WaitingForHuman
  ReadyForRework
  Succeeded
  Failed
  Rejected
  Cancelled
  Quarantined
}

///|
#derive(Debug, Eq)
pub(all) struct ExecutionClaim {
  claim_token : String
  executor_id : String
  lease_expires_at_epoch : Int64
}

///|
#derive(Debug, Eq)
pub(all) struct ExecutionAttemptEvent {
  revision : Int32
  from : ExecutionPhase
  to : ExecutionPhase
  actor_id : String
  reason : String
  at_epoch : Int64
}

///|
/// Runtime execution state is recoverable operational data, not a company
/// authorization record. `revision` is the compare-and-set boundary used by
/// MoonClaw/MoonFlow adapters and any future OpenOPC-compatible adapter.
#derive(Debug, Eq)
pub(all) struct ExecutionAttempt {
  protocol_version : String
  attempt_id : String
  request_id : String
  work_item_id : String
  flow_run_id : String
  phase : ExecutionPhase
  revision : Int32
  attempt_number : Int32
  claim : ExecutionClaim?
  crash_streak : Int32
  interrupted_streak : Int32
  rework_round : Int32
  artifact_refs : Array[String]
  cost_minor : Int64
  terminal_reason : String
  events : Array[ExecutionAttemptEvent]
}

///|
pub fn ExecutionPhase::is_terminal(self : ExecutionPhase) -> Bool {
  match self {
    Succeeded | Failed | Rejected | Cancelled | Quarantined => true
    _ => false
  }
}

///|
pub fn ExecutionPhase::is_dispatchable(self : ExecutionPhase) -> Bool {
  self is (Ready | ReadyForRework)
}

///|
fn ExecutionPhase::is_active(self : ExecutionPhase) -> Bool {
  self is (Claimed | Running | WaitingForPeer | WaitingForChildren)
}

///|
fn transition_allowed(from : ExecutionPhase, to : ExecutionPhase) -> Bool {
  if from == to {
    return true
  }
  match from {
    Queued => to is (Ready | Cancelled | Failed)
    Ready => to is (Claimed | Cancelled | Failed)
    ReadyForRework => to is (Claimed | Cancelled | Failed)
    Claimed =>
      to
      is (Running | Ready | ReadyForRework | Failed | Cancelled | Quarantined)
    Running =>
      to
      is (WaitingForPeer
      | WaitingForChildren
      | WaitingForReview
      | WaitingForHuman
      | Succeeded
      | Failed
      | Rejected
      | Cancelled
      | Ready
      | ReadyForRework
      | Quarantined)
    WaitingForPeer | WaitingForChildren =>
      to
      is (Running | Ready | ReadyForRework | Failed | Cancelled | Quarantined)
    WaitingForReview =>
      to is (Succeeded | ReadyForRework | WaitingForHuman | Failed | Cancelled)
    WaitingForHuman =>
      to is (Succeeded | ReadyForRework | Rejected | Failed | Cancelled)
    Succeeded | Failed | Rejected | Cancelled | Quarantined => false
  }
}

///|
fn append_event(
  attempt : ExecutionAttempt,
  to : ExecutionPhase,
  actor_id : String,
  reason : String,
  at_epoch : Int64,
) -> ExecutionAttempt {
  let revision = attempt.revision + 1
  let events = attempt.events.copy()
  events.push({ revision, from: attempt.phase, to, actor_id, reason, at_epoch, })
  { ..attempt, phase: to, revision, events, }
}

///|
fn require_revision(
  attempt : ExecutionAttempt,
  expected_revision : Int32,
) -> Unit raise AgentPortError {
  if attempt.revision != expected_revision {
    raise RevisionConflict(expected=expected_revision, actual=attempt.revision)
  }
}

///|
fn require_claim(
  attempt : ExecutionAttempt,
  claim_token : String,
) -> ExecutionClaim raise AgentPortError {
  match attempt.claim {
    None => raise ClaimRequired
    Some(claim) if claim.claim_token != claim_token => raise ClaimMismatch
    Some(claim) => claim
  }
}

///|
pub fn ExecutionAttempt::new(
  request : AgentRequest,
  attempt_id~ : String,
  at_epoch~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  request.validate()
  if attempt_id.trim().is_empty() || at_epoch < 0 {
    raise Invalid("attempt identity and creation time are required")
  }
  let event : ExecutionAttemptEvent = {
    revision: 1,
    from: Queued,
    to: Ready,
    actor_id: request.actor_id,
    reason: "execution admitted",
    at_epoch,
  }
  {
    protocol_version: protocol_version(),
    attempt_id,
    request_id: request.request_id,
    work_item_id: request.work_item_id,
    flow_run_id: request.flow_run_id,
    phase: Ready,
    revision: 1,
    attempt_number: 0,
    claim: None,
    crash_streak: 0,
    interrupted_streak: 0,
    rework_round: 0,
    artifact_refs: [],
    cost_minor: 0,
    terminal_reason: "",
    events: [event],
  }
}

///|
pub fn ExecutionAttempt::claim(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  claim_token~ : String,
  executor_id~ : String,
  now_epoch~ : Int64,
  lease_seconds~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  if self.phase is Quarantined {
    raise AttemptQuarantined
  }
  if !self.phase.is_dispatchable() {
    raise InvalidTransition(from=self.phase, to=Claimed)
  }
  if self.claim is Some(_) {
    raise ClaimAlreadyHeld
  }
  if claim_token.trim().is_empty() ||
    executor_id.trim().is_empty() ||
    now_epoch < 0 ||
    lease_seconds <= 0 {
    raise Invalid("claim identity, time and positive lease are required")
  }
  let claimed = append_event(
    self,
    Claimed,
    executor_id,
    "execution claimed",
    now_epoch,
  )
  {
    ..claimed,
    attempt_number: self.attempt_number + 1,
    claim: Some({
      claim_token,
      executor_id,
      lease_expires_at_epoch: now_epoch + lease_seconds,
    }),
  }
}

///|
pub fn ExecutionAttempt::heartbeat(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  claim_token~ : String,
  now_epoch~ : Int64,
  lease_seconds~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  let claim = require_claim(self, claim_token)
  if self.phase.is_terminal() || now_epoch < 0 || lease_seconds <= 0 {
    raise Invalid(
      "terminal attempts cannot heartbeat and leases must be positive",
    )
  }
  let revision = self.revision + 1
  {
    ..self,
    revision,
    claim: Some({ ..claim, lease_expires_at_epoch: now_epoch + lease_seconds, }),
  }
}

///|
pub fn ExecutionAttempt::transition(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  to~ : ExecutionPhase,
  actor_id~ : String,
  claim_token? : String,
  reason~ : String,
  at_epoch~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  if !transition_allowed(self.phase, to) {
    raise InvalidTransition(from=self.phase, to~)
  }
  if actor_id.trim().is_empty() || reason.trim().is_empty() || at_epoch < 0 {
    raise Invalid("transition actor, reason and time are required")
  }
  if self.phase.is_active() {
    let token = claim_token.unwrap_or("")
    ignore(require_claim(self, token))
  }
  let transitioned = append_event(self, to, actor_id, reason, at_epoch)
  if to.is_terminal() || to is (WaitingForReview | WaitingForHuman) {
    {
      ..transitioned,
      claim: None,
      terminal_reason: if to.is_terminal() {
        reason
      } else {
        ""
      },
    }
  } else {
    transitioned
  }
}

///|
pub fn ExecutionAttempt::record_crash(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  claim_token~ : String,
  at_epoch~ : Int64,
  reason~ : String,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  let claim = require_claim(self, claim_token)
  let crash_streak = self.crash_streak + 1
  let to = if crash_streak >= 3 {
    Quarantined
  } else if self.rework_round > 0 {
    ReadyForRework
  } else {
    Ready
  }
  let recovered = append_event(self, to, claim.executor_id, reason, at_epoch)
  {
    ..recovered,
    claim: None,
    crash_streak,
    terminal_reason: if to is Quarantined {
      reason
    } else {
      ""
    },
  }
}

///|
pub fn ExecutionAttempt::recover_expired_claim(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  now_epoch~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  let claim = match self.claim {
    None => raise ClaimRequired
    Some(value) => value
  }
  if now_epoch <= claim.lease_expires_at_epoch {
    raise LeaseNotExpired
  }
  if self.phase is (WaitingForReview | WaitingForHuman) {
    let revision = self.revision + 1
    return { ..self, revision, claim: None, }
  }
  if !self.phase.is_active() {
    raise Invalid("only active or passive claimed attempts can be recovered")
  }
  let interrupted_streak = self.interrupted_streak + 1
  let to = if interrupted_streak >= 5 {
    Quarantined
  } else if self.rework_round > 0 {
    ReadyForRework
  } else {
    Ready
  }
  let recovered = append_event(
    self,
    to,
    claim.executor_id,
    "expired execution claim recovered",
    now_epoch,
  )
  {
    ..recovered,
    claim: None,
    interrupted_streak,
    terminal_reason: if to is Quarantined {
      "interrupted-attempt limit reached"
    } else {
      ""
    },
  }
}

///|
pub fn ExecutionAttempt::request_rework(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  reviewer_id~ : String,
  reason~ : String,
  at_epoch~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  if !(self.phase is (WaitingForReview | WaitingForHuman)) {
    raise InvalidTransition(from=self.phase, to=ReadyForRework)
  }
  if reviewer_id.trim().is_empty() || reason.trim().is_empty() || at_epoch < 0 {
    raise Invalid("rework reviewer, reason, and time are required")
  }
  let transitioned = append_event(
    self,
    ReadyForRework,
    reviewer_id,
    reason,
    at_epoch,
  )
  { ..transitioned, claim: None, rework_round: self.rework_round + 1, }
}

///|
pub fn ExecutionAttempt::record_artifact(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  artifact_ref~ : String,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  if self.phase.is_terminal() ||
    artifact_ref.trim().is_empty() ||
    self.artifact_refs.contains(artifact_ref) {
    raise Invalid("artifact reference must be non-empty and unique")
  }
  let artifact_refs = self.artifact_refs.copy()
  artifact_refs.push(artifact_ref)
  { ..self, revision: self.revision + 1, artifact_refs, }
}

///|
pub fn ExecutionAttempt::record_cost(
  self : ExecutionAttempt,
  expected_revision~ : Int32,
  additional_minor~ : Int64,
) -> ExecutionAttempt raise AgentPortError {
  require_revision(self, expected_revision)
  if additional_minor < 0 {
    raise Invalid("execution cost cannot be negative")
  }
  {
    ..self,
    revision: self.revision + 1,
    cost_minor: self.cost_minor + additional_minor,
  }
}
