///|
pub(all) enum ProgressState {
  Draft
  Submitted
  Accepted
  Rejected
} derive(Debug, Eq)

///|
pub(all) enum DeliverableState {
  Planned
  Submitted
  Accepted
  Rejected
  Remediation
} derive(Debug, Eq)

///|
pub(all) struct DeliveryEvent {
  from : String
  to : String
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct ProgressReport {
  report_id : String
  project_id : String
  principal_id : String
  project_scope : String
  progress_bps : Int64
  completed_value : @finance.Money
  evidence_ids : Array[String]
  state : ProgressState
  events : Array[DeliveryEvent]
} derive(Debug, Eq)

///|
pub(all) struct Deliverable {
  deliverable_id : String
  project_id : String
  principal_id : String
  project_scope : String
  name : String
  evidence_ids : Array[String]
  state : DeliverableState
  events : Array[DeliveryEvent]
} derive(Debug, Eq)

///|
/// Reviewed recognition evidence derived from an accepted progress report.
/// This is a source-to-journal link only: posting, cash release, tax, and
/// period close remain separate accounting controls.
pub(all) struct DeliveryRecognition {
  recognition_id : String
  report_id : String
  project_id : String
  principal_id : String
  project_scope : String
  acceptance_id : String
  acceptance_evidence_ids : Array[String]
  accepted_by : String
  created_by : String
  accounting_event : @accounting.AccountingEvent
} derive(Debug, Eq)

///|
pub(all) suberror DeliveryError {
  EmptyIdentifier
  InvalidProgress
  InvalidAmount
  MissingEvidence
  AcceptanceMismatch
  InvalidState
  AccountingEvent(@accounting.AccountingEventError)
  CostForecast(@cost.ForecastError)
  CurrencyMismatch
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn ProgressReport::new(
  report_id~ : String,
  project_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  progress_bps~ : Int64,
  completed_value~ : @finance.Money,
  evidence_ids~ : Array[String],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProgressReport raise DeliveryError {
  if report_id.trim() == "" ||
    project_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" {
    raise DeliveryError::EmptyIdentifier
  }
  if progress_bps < 0L || progress_bps > 10000L {
    raise DeliveryError::InvalidProgress
  }
  if completed_value.minor < 0 {
    raise DeliveryError::InvalidAmount
  }
  if evidence_ids.length() == 0 {
    raise DeliveryError::MissingEvidence
  }
  for evidence_id in evidence_ids {
    if evidence_id.trim() == "" {
      raise DeliveryError::MissingEvidence
    }
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="delivery:progress:create",
    scope=project_scope,
    amount_minor=completed_value.minor,
  ) catch {
    error => raise DeliveryError::NotAuthorized(error)
  }
  {
    report_id,
    project_id,
    principal_id,
    project_scope,
    progress_bps,
    completed_value,
    evidence_ids: evidence_ids.copy(),
    state: ProgressState::Draft,
    events: [],
  }
}

///|
fn ProgressReport::transition(
  self : ProgressReport,
  to : ProgressState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProgressReport raise DeliveryError {
  let allowed = (
      self.state == ProgressState::Draft && to == ProgressState::Submitted
    ) ||
    (
      self.state == ProgressState::Submitted &&
      (to == ProgressState::Accepted || to == ProgressState::Rejected)
    )
  if !allowed {
    raise DeliveryError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=self.completed_value.minor,
  ) catch {
    error => raise DeliveryError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: "progress:{self.state}",
    to: "progress:{to}",
    actor_id,
    capability,
  })
  { ..self, state: to, events }
}

///|
pub fn ProgressReport::submit(
  self : ProgressReport,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProgressReport raise DeliveryError {
  self.transition(
    ProgressState::Submitted,
    capability="delivery:progress:submit",
    actor_id~,
    grant~,
  )
}

///|
pub fn ProgressReport::accept(
  self : ProgressReport,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProgressReport raise DeliveryError {
  self.transition(
    ProgressState::Accepted,
    capability="delivery:progress:accept",
    actor_id~,
    grant~,
  )
}

///|
pub fn ProgressReport::reject(
  self : ProgressReport,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProgressReport raise DeliveryError {
  self.transition(
    ProgressState::Rejected,
    capability="delivery:progress:reject",
    actor_id~,
    grant~,
  )
}

///|
pub fn Deliverable::new(
  deliverable_id~ : String,
  project_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  name~ : String,
  evidence_ids~ : Array[String],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Deliverable raise DeliveryError {
  if deliverable_id.trim() == "" ||
    project_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    name.trim() == "" {
    raise DeliveryError::EmptyIdentifier
  }
  if evidence_ids.length() == 0 {
    raise DeliveryError::MissingEvidence
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="delivery:deliverable:create",
    scope=project_scope,
    amount_minor=0,
  ) catch {
    error => raise DeliveryError::NotAuthorized(error)
  }
  {
    deliverable_id,
    project_id,
    principal_id,
    project_scope,
    name,
    evidence_ids: evidence_ids.copy(),
    state: DeliverableState::Planned,
    events: [],
  }
}

///|
fn Deliverable::transition(
  self : Deliverable,
  to : DeliverableState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Deliverable raise DeliveryError {
  let allowed = (
      self.state == DeliverableState::Planned &&
      to == DeliverableState::Submitted
    ) ||
    (
      self.state == DeliverableState::Submitted &&
      (
        to == DeliverableState::Accepted ||
        to == DeliverableState::Rejected ||
        to == DeliverableState::Remediation
      )
    ) ||
    (
      self.state == DeliverableState::Remediation &&
      to == DeliverableState::Submitted
    )
  if !allowed {
    raise DeliveryError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise DeliveryError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({
    from: "deliverable:{self.state}",
    to: "deliverable:{to}",
    actor_id,
    capability,
  })
  { ..self, state: to, events }
}

///|
pub fn Deliverable::submit(
  self : Deliverable,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Deliverable raise DeliveryError {
  self.transition(
    DeliverableState::Submitted,
    capability="delivery:deliverable:submit",
    actor_id~,
    grant~,
  )
}

///|
pub fn Deliverable::accept(
  self : Deliverable,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Deliverable raise DeliveryError {
  self.transition(
    DeliverableState::Accepted,
    capability="delivery:deliverable:accept",
    actor_id~,
    grant~,
  )
}

///|
pub fn Deliverable::reject(
  self : Deliverable,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Deliverable raise DeliveryError {
  self.transition(
    DeliverableState::Rejected,
    capability="delivery:deliverable:reject",
    actor_id~,
    grant~,
  )
}
