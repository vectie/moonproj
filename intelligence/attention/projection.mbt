///|
pub(all) struct ExecutionActivityRow {
  attempt_id : String
  request_id : String
  work_item_id : String
  phase : @agent_port.ExecutionPhase
  revision : Int
  attempt_number : Int
  crash_streak : Int
  interrupted_streak : Int
  artifact_count : Int
  cost_minor : Int64
  needs_attention : Bool
  last_reason : String
} derive(Debug, Eq)

///|
pub(all) struct ExecutionActivityProjection {
  total : Int
  active : Int
  waiting : Int
  review : Int
  succeeded : Int
  quarantined : Int
  total_cost_minor : Int64
  rows : Array[ExecutionActivityRow]
  inbox : AttentionInbox
} derive(Debug, Eq)

///|
fn attempt_needs_attention(attempt : @agent_port.ExecutionAttempt) -> Bool {
  attempt.phase is (WaitingForHuman | WaitingForReview | Quarantined | Failed)
}

///|
fn attempt_reason(attempt : @agent_port.ExecutionAttempt) -> String {
  if !attempt.terminal_reason.trim().is_empty() {
    return attempt.terminal_reason
  }
  if attempt.events.is_empty() {
    return "execution admitted"
  }
  attempt.events[attempt.events.length() - 1].reason
}

///|
fn phase_key(phase : @agent_port.ExecutionPhase) -> String {
  match phase {
    Queued => "queued"
    Ready => "ready"
    Claimed => "claimed"
    Running => "running"
    WaitingForPeer => "waiting-for-peer"
    WaitingForChildren => "waiting-for-children"
    WaitingForReview => "waiting-for-review"
    WaitingForHuman => "waiting-for-human"
    ReadyForRework => "ready-for-rework"
    Succeeded => "succeeded"
    Failed => "failed"
    Rejected => "rejected"
    Cancelled => "cancelled"
    Quarantined => "quarantined"
  }
}

///|
fn attention_for_attempt(
  attempt : @agent_port.ExecutionAttempt,
  principal_id : String,
  at_epoch : Int64,
) -> AttentionItem? {
  let (severity, title, action) = match attempt.phase {
    WaitingForReview =>
      (
        Normal,
        "Execution output awaits review",
        "Review evidence and accept or request rework",
      )
    WaitingForHuman =>
      (
        Urgent,
        "Execution is waiting for a person",
        "Supply the requested decision or evidence",
      )
    Failed =>
      (
        Urgent,
        "Execution failed",
        "Classify the failure and choose retry, rework, or cancel",
      )
    Quarantined =>
      (
        Critical,
        "Execution attempt quarantined",
        "Investigate repeated crashes or interruptions before release",
      )
    _ => return None
  }
  Some({
    attention_id: "attention-attempt-\{attempt.attempt_id}",
    dedupe_key: "execution-attempt:\{attempt.attempt_id}:\{phase_key(attempt.phase)}",
    principal_id,
    source_kind: "execution-attempt",
    source_id: attempt.attempt_id,
    work_item_id: attempt.work_item_id,
    title,
    reason: attempt_reason(attempt),
    requested_action: action,
    severity,
    amount_at_risk_minor: attempt.cost_minor,
    reversible: !(attempt.phase is Quarantined),
    evidence: attempt.artifact_refs,
    status: Open,
    created_at_epoch: at_epoch,
    updated_at_epoch: at_epoch,
  })
}

///|
pub fn project_execution_activity(
  attempts : Array[@agent_port.ExecutionAttempt],
  principal_id~ : String,
  at_epoch~ : Int64,
) -> ExecutionActivityProjection raise AttentionError {
  if principal_id.trim().is_empty() || at_epoch < 0 {
    raise Invalid("projection principal and time are required")
  }
  let rows : Array[ExecutionActivityRow] = []
  let mut inbox = AttentionInbox::new()
  let mut active = 0
  let mut waiting = 0
  let mut review = 0
  let mut succeeded = 0
  let mut quarantined = 0
  let mut total_cost_minor = 0L
  for attempt in attempts {
    if attempt.phase
      is (Claimed | Running | WaitingForPeer | WaitingForChildren) {
      active += 1
    }
    if attempt.phase is (WaitingForHuman | WaitingForPeer | WaitingForChildren) {
      waiting += 1
    }
    if attempt.phase is WaitingForReview {
      review += 1
    }
    if attempt.phase is Succeeded {
      succeeded += 1
    }
    if attempt.phase is Quarantined {
      quarantined += 1
    }
    total_cost_minor += attempt.cost_minor
    let needs_attention = attempt_needs_attention(attempt)
    rows.push({
      attempt_id: attempt.attempt_id,
      request_id: attempt.request_id,
      work_item_id: attempt.work_item_id,
      phase: attempt.phase,
      revision: attempt.revision,
      attempt_number: attempt.attempt_number,
      crash_streak: attempt.crash_streak,
      interrupted_streak: attempt.interrupted_streak,
      artifact_count: attempt.artifact_refs.length(),
      cost_minor: attempt.cost_minor,
      needs_attention,
      last_reason: attempt_reason(attempt),
    })
    match attention_for_attempt(attempt, principal_id, at_epoch) {
      Some(item) => inbox = inbox.upsert(item)
      None => ()
    }
  }
  {
    total: attempts.length(),
    active,
    waiting,
    review,
    succeeded,
    quarantined,
    total_cost_minor,
    rows,
    inbox,
  }
}
