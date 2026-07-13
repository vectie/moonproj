///|
fn warning_severity_name(severity : WarningSeverity) -> String {
  match severity {
    WarningSeverity::Info => "info"
    WarningSeverity::Warning => "warning"
    WarningSeverity::Critical => "critical"
  }
}

///|
fn warning_state_name(state : WarningState) -> String {
  match state {
    WarningState::Open => "open"
    WarningState::Acknowledged => "acknowledged"
    WarningState::Resolved => "resolved"
    WarningState::Suppressed => "suppressed"
  }
}

///|
fn warning_events_json(events : Array[WarningEvent]) -> Json {
  let values : Array[Json] = []
  for event in events {
    values.push(
      Json::object({
        "from": Json::string(warning_state_name(event.from)),
        "to": Json::string(warning_state_name(event.to)),
        "actor_id": Json::string(event.actor_id),
        "capability": Json::string(event.capability),
      }),
    )
  }
  Json::array(values)
}

///|
pub fn WarningEvidence::append_projection(
  self : WarningEvidence,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise WarningError {
  let finding = self.finding
  if projection.aggregate_type != "warning_finding" ||
    projection.aggregate_id != finding.warning_id {
    raise WarningError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "warning_id": Json::string(finding.warning_id),
    "principal_id": Json::string(finding.principal_id),
    "scope": Json::string(finding.scope),
    "rule_code": Json::string(finding.rule_code),
    "target_type": Json::string(finding.target_type),
    "target_id": Json::string(finding.target_id),
    "message": Json::string(finding.message),
    "severity": Json::string(warning_severity_name(finding.severity)),
    "state": Json::string(warning_state_name(finding.state)),
    "events": warning_events_json(finding.events),
    "source_snapshot_id": Json::string(self.source_snapshot_id),
    "mapping_version": Json::string(self.mapping_version),
    "evidence_id": Json::string(self.evidence_id),
    "notification_delivered": Json::boolean(false),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:warning-finding:" +
      finding.warning_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise WarningError::Projection(error)
  }
}
