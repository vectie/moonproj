///|
pub(all) enum CbsVersionState {
  Draft
  Active
  Frozen
} derive(Debug, Eq)

///|
pub(all) struct CostSubject {
  subject_id : String
  code : String
  name : String
  parent_code : String
  target_minor : Int64
} derive(Debug, Eq)

///|
pub(all) struct CbsVersion {
  version_id : String
  project_scope : String
  state : CbsVersionState
  subjects : Array[CostSubject]
} derive(Debug, Eq)

///|
pub(all) struct CostSubjectLink {
  link_id : String
  source_id : String
  version_id : String
  project_scope : String
  subject_code : String
  principal_id : String
  amount : @finance.Money
} derive(Debug, Eq)

///|
pub(all) suberror CbsError {
  EmptyIdentifier
  EmptySubject
  NegativeTarget
  InvalidAmount
  InvalidCurrency
  UnknownSubject
  DuplicateCode
  Frozen
  InvalidTransition
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn CbsVersion::new(
  version_id~ : String,
  project_scope~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsVersion raise CbsError {
  if version_id.trim() == "" || project_scope.trim() == "" {
    raise CbsError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="cbs:create",
    scope=project_scope,
    amount_minor=0,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  { version_id, project_scope, state: CbsVersionState::Draft, subjects: [] }
}

///|
pub fn CbsVersion::add_subject(
  self : CbsVersion,
  subject~ : CostSubject,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsVersion raise CbsError {
  if self.state != CbsVersionState::Draft {
    raise CbsError::Frozen
  }
  if subject.subject_id.trim() == "" ||
    subject.code.trim() == "" ||
    subject.name.trim() == "" {
    raise CbsError::EmptySubject
  }
  if subject.target_minor < 0 {
    raise CbsError::NegativeTarget
  }
  for existing in self.subjects {
    if existing.code == subject.code {
      raise CbsError::DuplicateCode
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="cbs:edit",
    scope=self.project_scope,
    amount_minor=subject.target_minor,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  let subjects = self.subjects.copy()
  subjects.push(subject)
  { ..self, subjects, }
}

///|
pub fn CbsVersion::activate(
  self : CbsVersion,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsVersion raise CbsError {
  if self.state != CbsVersionState::Draft {
    raise CbsError::InvalidTransition
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="cbs:activate",
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  { ..self, state: CbsVersionState::Active }
}

///|
pub fn CbsVersion::freeze(
  self : CbsVersion,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsVersion raise CbsError {
  if self.state != CbsVersionState::Active {
    raise CbsError::InvalidTransition
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="cbs:freeze",
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  { ..self, state: CbsVersionState::Frozen }
}

///|
/// Link a source amount to a governed CBS subject. The link is an allocation
/// record only: it does not consume budget, post accounting, or approve an
/// overrun. That requires a separate budget or accounting event.
pub fn CbsVersion::link_cost(
  self : CbsVersion,
  link_id~ : String,
  source_id~ : String,
  subject_code~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CostSubjectLink raise CbsError {
  if self.state != CbsVersionState::Active &&
    self.state != CbsVersionState::Frozen {
    raise CbsError::InvalidTransition
  }
  if link_id.trim() == "" || source_id.trim() == "" || subject_code.trim() == "" {
    raise CbsError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise CbsError::InvalidAmount
  }
  if amount.currency.length() != 3 {
    raise CbsError::InvalidCurrency
  }
  let mut found = false
  for subject in self.subjects {
    if subject.code == subject_code {
      found = true
    }
  }
  if !found {
    raise CbsError::UnknownSubject
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="cbs:cost:link",
    scope=self.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  {
    link_id,
    source_id,
    version_id: self.version_id,
    project_scope: self.project_scope,
    subject_code,
    principal_id: grant.principal_id,
    amount,
  }
}

///|
pub fn CbsVersion::target_total_minor(self : CbsVersion) -> Int64 {
  let mut total : Int64 = 0
  for subject in self.subjects {
    total += subject.target_minor
  }
  total
}
