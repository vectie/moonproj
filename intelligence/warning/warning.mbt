///|
pub(all) enum WarningSeverity {
  Info
  Warning
  Critical
} derive(Debug, Eq)

///|
pub(all) enum WarningState {
  Open
  Acknowledged
  Resolved
  Suppressed
} derive(Debug, Eq)

///|
pub(all) struct WarningEvent {
  from : WarningState
  to : WarningState
  actor_id : String
  capability : String
} derive(Debug, Eq)

///|
pub(all) struct WarningFinding {
  warning_id : String
  principal_id : String
  scope : String
  rule_code : String
  target_type : String
  target_id : String
  message : String
  severity : WarningSeverity
  state : WarningState
  events : Array[WarningEvent]
} derive(Debug, Eq)

///|
/// Source-bound warning evidence. The finding remains an authority-checked
/// domain decision; this wrapper adds migration/source provenance so the
/// warning can be persisted and replayed without becoming a workflow command.
pub(all) struct WarningEvidence {
  finding : WarningFinding
  source_snapshot_id : String
  mapping_version : String
  evidence_id : String
} derive(Debug, Eq)

///|
pub(all) suberror WarningError {
  EmptyIdentifier
  InvalidState
  NotAuthorized(@foundation.AuthorityError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn WarningFinding::new(
  warning_id~ : String,
  principal_id~ : String,
  scope~ : String,
  rule_code~ : String,
  target_type~ : String,
  target_id~ : String,
  message~ : String,
  severity~ : WarningSeverity,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding raise WarningError {
  if warning_id.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" ||
    rule_code.trim() == "" ||
    target_type.trim() == "" ||
    target_id.trim() == "" ||
    message.trim() == "" {
    raise WarningError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="warning:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise WarningError::NotAuthorized(error)
  }
  {
    warning_id,
    principal_id,
    scope,
    rule_code,
    target_type,
    target_id,
    message,
    severity,
    state: WarningState::Open,
    events: [],
  }
}

///|
fn WarningFinding::transition(
  self : WarningFinding,
  to : WarningState,
  capability~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding raise WarningError {
  let allowed = (
      self.state == WarningState::Open &&
      (
        to == WarningState::Acknowledged ||
        to == WarningState::Suppressed ||
        to == WarningState::Resolved
      )
    ) ||
    (
      self.state == WarningState::Acknowledged &&
      (to == WarningState::Resolved || to == WarningState::Suppressed)
    )
  if !allowed {
    raise WarningError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise WarningError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability })
  { ..self, state: to, events }
}

///|
pub fn WarningFinding::acknowledge(
  self : WarningFinding,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding raise WarningError {
  self.transition(
    WarningState::Acknowledged,
    capability="warning:acknowledge",
    actor_id~,
    grant~,
  )
}

///|
pub fn WarningFinding::resolve(
  self : WarningFinding,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding raise WarningError {
  self.transition(
    WarningState::Resolved,
    capability="warning:resolve",
    actor_id~,
    grant~,
  )
}

///|
pub fn WarningFinding::suppress(
  self : WarningFinding,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding raise WarningError {
  self.transition(
    WarningState::Suppressed,
    capability="warning:suppress",
    actor_id~,
    grant~,
  )
}

///|
pub fn WarningFinding::bind_evidence(
  self : WarningFinding,
  source_snapshot_id~ : String,
  mapping_version~ : String,
  evidence_id~ : String,
) -> WarningEvidence raise WarningError {
  if source_snapshot_id.trim() == "" ||
    mapping_version.trim() == "" ||
    evidence_id.trim() == "" {
    raise WarningError::EmptyIdentifier
  }
  { finding: self, source_snapshot_id, mapping_version, evidence_id }
}

///|
/// Deterministic cost-overrun rule used by migration parity and project cockpit
/// scans. No warning is emitted when the forecast is at or below target.
pub fn warning_for_cost_forecast(
  warning_id~ : String,
  principal_id~ : String,
  forecast : @cost.CostForecast,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> WarningFinding? raise WarningError {
  if forecast.target.currency.length() != 3 {
    return None
  }
  if forecast.variance_minor >= 0L {
    return None
  }
  Some(
    WarningFinding::new(
      warning_id~,
      principal_id~,
      scope=forecast.project_scope,
      rule_code="COST_FORECAST_OVERRUN",
      target_type="project",
      target_id=forecast.project_scope,
      message="Forecast cost exceeds target baseline",
      severity=WarningSeverity::Critical,
      actor_id~,
      grant~,
    ),
  )
}
