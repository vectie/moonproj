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
pub(all) enum CbsBudgetReservationState {
  Reserved
  Consumed
  Released
} derive(Debug, Eq)

///|
/// A governed budget reservation tied to one explicit CBS cost link. It is a
/// budget-control record only; cash and accounting remain separate effects.
pub(all) struct CbsBudgetReservation {
  reservation_id : String
  source_id : String
  version_id : String
  project_scope : String
  subject_code : String
  principal_id : String
  amount : @finance.Money
  state : CbsBudgetReservationState
} derive(Debug, Eq)

///|
/// Subject-scoped CBS budget ledger. The ledger is intentionally separate from
/// the immutable subject configuration and from source-to-subject links.
pub(all) struct CbsBudgetLedger {
  version_id : String
  project_scope : String
  principal_id : String
  currency : String
  reservations : Array[CbsBudgetReservation]
} derive(Debug, Eq)

///|
pub(all) suberror CbsError {
  EmptyIdentifier
  EmptySubject
  NegativeTarget
  InvalidAmount
  InvalidCurrency
  UnknownSubject
  UnknownParent
  HierarchyCycle
  DuplicateCode
  Frozen
  InvalidTransition
  InvalidBudgetState
  DuplicateReservation
  UnknownReservation
  BudgetExceeded
  CurrencyMismatch
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
  for subject in self.subjects {
    if subject.parent_code != "" {
      let mut parent_found = false
      for parent in self.subjects {
        if parent.code == subject.parent_code {
          parent_found = true
        }
      }
      if !parent_found {
        raise CbsError::UnknownParent
      }
      if hierarchy_cycle(self.subjects, subject) {
        raise CbsError::HierarchyCycle
      }
    }
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
fn hierarchy_cycle(
  subjects : Array[CostSubject],
  subject : CostSubject,
) -> Bool {
  let mut current = subject.parent_code
  let visited : Array[String] = []
  for _ in 0..<subjects.length() {
    if current == "" {
      return false
    }
    for seen in visited {
      if seen == current {
        return true
      }
    }
    visited.push(current)
    let mut next = ""
    for candidate in subjects {
      if candidate.code == current {
        next = candidate.parent_code
      }
    }
    current = next
  }
  true
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
pub fn CbsBudgetLedger::new(
  version : CbsVersion,
  principal_id~ : String,
  currency~ : String,
) -> CbsBudgetLedger raise CbsError {
  if version.state != CbsVersionState::Active &&
    version.state != CbsVersionState::Frozen {
    raise CbsError::InvalidTransition
  }
  if principal_id.trim() == "" || version.project_scope.trim() == "" {
    raise CbsError::EmptyIdentifier
  }
  if currency.length() != 3 {
    raise CbsError::InvalidCurrency
  }
  {
    version_id: version.version_id,
    project_scope: version.project_scope,
    principal_id,
    currency,
    reservations: [],
  }
}

///|
fn reservation_amount_for_subject(
  reservations : Array[CbsBudgetReservation],
  subject_code : String,
) -> Int64 {
  let mut total : Int64 = 0
  for reservation in reservations {
    if reservation.subject_code == subject_code &&
      reservation.state != CbsBudgetReservationState::Released {
      total += reservation.amount.minor
    }
  }
  total
}

///|
fn subject_target(version : CbsVersion, subject_code : String) -> Int64? {
  for subject in version.subjects {
    if subject.code == subject_code {
      return Some(subject.target_minor)
    }
  }
  None
}

///|
/// Reserve the explicit cost-link amount against the matching CBS subject
/// target. A reservation cannot exceed the subject target after active
/// reservations and consumed amounts are included.
pub fn CbsBudgetLedger::reserve(
  self : CbsBudgetLedger,
  version : CbsVersion,
  link : CostSubjectLink,
  reservation_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (CbsBudgetLedger, CbsBudgetReservation) raise CbsError {
  if version.version_id != self.version_id ||
    version.project_scope != self.project_scope ||
    link.version_id != self.version_id ||
    link.project_scope != self.project_scope ||
    link.principal_id != self.principal_id {
    raise CbsError::ProjectionIdentity
  }
  if reservation_id.trim() == "" || link.source_id.trim() == "" {
    raise CbsError::EmptyIdentifier
  }
  if link.amount.currency != self.currency || link.amount.minor <= 0 {
    raise CbsError::CurrencyMismatch
  }
  for existing in self.reservations {
    if existing.reservation_id == reservation_id {
      raise CbsError::DuplicateReservation
    }
  }
  let target = match subject_target(version, link.subject_code) {
    Some(value) => value
    None => raise CbsError::UnknownSubject
  }
  let used = reservation_amount_for_subject(
    self.reservations,
    link.subject_code,
  )
  if used + link.amount.minor > target {
    raise CbsError::BudgetExceeded
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="cbs:budget:reserve",
    scope=self.project_scope,
    amount_minor=link.amount.minor,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  let reservation : CbsBudgetReservation = {
    reservation_id,
    source_id: link.source_id,
    version_id: self.version_id,
    project_scope: self.project_scope,
    subject_code: link.subject_code,
    principal_id: self.principal_id,
    amount: link.amount,
    state: CbsBudgetReservationState::Reserved,
  }
  let reservations = self.reservations.copy()
  reservations.push(reservation)
  ({ ..self, reservations, }, reservation)
}

///|
fn CbsBudgetLedger::transition_reservation(
  self : CbsBudgetLedger,
  reservation_id : String,
  next : CbsBudgetReservationState,
  capability : String,
  actor_id : String,
  grant : @foundation.AuthorityGrant,
) -> CbsBudgetLedger raise CbsError {
  let mut found : Int? = None
  for index in 0..<self.reservations.length() {
    if self.reservations[index].reservation_id == reservation_id {
      found = Some(index)
    }
  }
  let index = match found {
    Some(index) => index
    None => raise CbsError::UnknownReservation
  }
  let current = self.reservations[index]
  let allowed = current.state == CbsBudgetReservationState::Reserved
  if !allowed {
    raise CbsError::InvalidBudgetState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=current.amount.minor,
  ) catch {
    error => raise CbsError::NotAuthorized(error)
  }
  let reservations = self.reservations.copy()
  reservations[index] = { ..current, state: next }
  { ..self, reservations, }
}

///|
pub fn CbsBudgetLedger::consume(
  self : CbsBudgetLedger,
  reservation_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsBudgetLedger raise CbsError {
  self.transition_reservation(
    reservation_id,
    CbsBudgetReservationState::Consumed,
    "cbs:budget:consume",
    actor_id,
    grant,
  )
}

///|
pub fn CbsBudgetLedger::release(
  self : CbsBudgetLedger,
  reservation_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> CbsBudgetLedger raise CbsError {
  self.transition_reservation(
    reservation_id,
    CbsBudgetReservationState::Released,
    "cbs:budget:release",
    actor_id,
    grant,
  )
}

///|
pub fn CbsBudgetLedger::reserved_minor(self : CbsBudgetLedger) -> Int64 {
  let mut total : Int64 = 0
  for reservation in self.reservations {
    if reservation.state == CbsBudgetReservationState::Reserved {
      total += reservation.amount.minor
    }
  }
  total
}

///|
pub fn CbsBudgetLedger::consumed_minor(self : CbsBudgetLedger) -> Int64 {
  let mut total : Int64 = 0
  for reservation in self.reservations {
    if reservation.state == CbsBudgetReservationState::Consumed {
      total += reservation.amount.minor
    }
  }
  total
}

///|
pub fn CbsVersion::target_total_minor(self : CbsVersion) -> Int64 {
  let mut total : Int64 = 0
  for subject in self.subjects {
    total += subject.target_minor
  }
  total
}
