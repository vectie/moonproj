///|
pub(all) enum EvidenceState {
  Pending
  Verified
  Redacted
  Archived
} derive(Debug, Eq)

///|
pub(all) struct EvidenceEvent {
  from : EvidenceState
  to : EvidenceState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct Evidence {
  evidence_id : String
  principal_id : String
  scope : String
  source_reference : String
  media_type : String
  content_hash : String
  state : EvidenceState
  events : Array[EvidenceEvent]
} derive(Debug, Eq)

///|
pub(all) struct AuditRecord {
  audit_id : String
  principal_id : String
  actor_id : String
  scope : String
  action : String
  target_type : String
  target_id : String
  outcome : String
  evidence_id : String?
} derive(Debug, Eq)

///|
pub(all) struct AuditTrail {
  records : Array[AuditRecord]
} derive(Debug, Eq)

///|
pub(all) suberror EvidenceError {
  EmptyIdentifier
  InvalidHash
  InvalidState
  DuplicateAudit
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Evidence::new(
  evidence_id~ : String,
  principal_id~ : String,
  scope~ : String,
  source_reference~ : String,
  media_type~ : String,
  content_hash~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Evidence raise EvidenceError {
  if evidence_id.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" ||
    source_reference.trim() == "" ||
    media_type.trim() == "" {
    raise EvidenceError::EmptyIdentifier
  }
  if content_hash.trim() == "" {
    raise EvidenceError::InvalidHash
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="evidence:attach",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise EvidenceError::NotAuthorized(error)
  }
  {
    evidence_id,
    principal_id,
    scope,
    source_reference,
    media_type,
    content_hash,
    state: EvidenceState::Pending,
    events: [],
  }
}

///|
fn Evidence::transition(
  self : Evidence,
  to : EvidenceState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Evidence raise EvidenceError {
  let allowed = (
      self.state == EvidenceState::Pending && to == EvidenceState::Verified
    ) ||
    (
      (
        self.state == EvidenceState::Pending ||
        self.state == EvidenceState::Verified
      ) &&
      to == EvidenceState::Redacted
    ) ||
    (
      (
        self.state == EvidenceState::Verified ||
        self.state == EvidenceState::Redacted
      ) &&
      to == EvidenceState::Archived
    )
  if !allowed {
    raise EvidenceError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise EvidenceError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn Evidence::verify(
  self : Evidence,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Evidence raise EvidenceError {
  self.transition(
    EvidenceState::Verified,
    capability="evidence:verify",
    actor_id~,
    grant~,
  )
}

///|
pub fn Evidence::redact(
  self : Evidence,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Evidence raise EvidenceError {
  self.transition(
    EvidenceState::Redacted,
    capability="evidence:redact",
    actor_id~,
    grant~,
  )
}

///|
pub fn Evidence::archive(
  self : Evidence,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Evidence raise EvidenceError {
  self.transition(
    EvidenceState::Archived,
    capability="evidence:archive",
    actor_id~,
    grant~,
  )
}

///|
pub fn AuditTrail::empty() -> AuditTrail {
  { records: [] }
}

///|
pub fn AuditTrail::append(
  self : AuditTrail,
  record : AuditRecord,
  grant~ : @foundation.AuthorityGrant,
) -> AuditTrail raise EvidenceError {
  if record.audit_id.trim() == "" ||
    record.principal_id.trim() == "" ||
    record.actor_id.trim() == "" ||
    record.scope.trim() == "" ||
    record.action.trim() == "" ||
    record.target_type.trim() == "" ||
    record.target_id.trim() == "" ||
    record.outcome.trim() == "" {
    raise EvidenceError::EmptyIdentifier
  }
  for existing in self.records {
    if existing.audit_id == record.audit_id {
      raise EvidenceError::DuplicateAudit
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=record.principal_id,
    actor_id=record.actor_id,
    capability="audit:append",
    scope=record.scope,
    amount_minor=0,
  ) catch {
    error => raise EvidenceError::NotAuthorized(error)
  }
  let records = self.records.copy()
  records.push(record)
  { records, }
}
