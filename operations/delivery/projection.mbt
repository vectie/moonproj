///|
fn progress_state_name(state : ProgressState) -> String {
  match state {
    ProgressState::Draft => "draft"
    ProgressState::Submitted => "submitted"
    ProgressState::Accepted => "accepted"
    ProgressState::Rejected => "rejected"
  }
}

///|
fn deliverable_state_name(state : DeliverableState) -> String {
  match state {
    DeliverableState::Planned => "planned"
    DeliverableState::Submitted => "submitted"
    DeliverableState::Accepted => "accepted"
    DeliverableState::Rejected => "rejected"
    DeliverableState::Remediation => "remediation"
  }
}

///|
fn evidence_json(evidence_ids : Array[String]) -> Json {
  let values : Array[Json] = []
  for evidence_id in evidence_ids {
    values.push(Json::string(evidence_id))
  }
  Json::array(values)
}

///|
fn progress_projection_payload(report : ProgressReport) -> String {
  Json::object({
    "report_id": Json::string(report.report_id),
    "project_id": Json::string(report.project_id),
    "principal_id": Json::string(report.principal_id),
    "project_scope": Json::string(report.project_scope),
    "progress_bps": Json::number(
      report.progress_bps.to_double(),
      repr=report.progress_bps.to_string(),
    ),
    "completed_value_minor": Json::number(
      report.completed_value.minor.to_double(),
      repr=report.completed_value.minor.to_string(),
    ),
    "currency": Json::string(report.completed_value.currency),
    "evidence_ids": evidence_json(report.evidence_ids),
    "state": Json::string(progress_state_name(report.state)),
  }).stringify()
}

///|
pub fn ProgressReport::append_projection(
  self : ProgressReport,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise DeliveryError {
  if projection.aggregate_type != "progress_report" ||
    projection.aggregate_id != self.report_id {
    raise DeliveryError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=progress_projection_payload(self),
    source_event_id="company:progress-report:" +
      self.report_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise DeliveryError::Projection(error)
  }
}

///|
fn deliverable_projection_payload(deliverable : Deliverable) -> String {
  Json::object({
    "deliverable_id": Json::string(deliverable.deliverable_id),
    "project_id": Json::string(deliverable.project_id),
    "principal_id": Json::string(deliverable.principal_id),
    "project_scope": Json::string(deliverable.project_scope),
    "name": Json::string(deliverable.name),
    "evidence_ids": evidence_json(deliverable.evidence_ids),
    "state": Json::string(deliverable_state_name(deliverable.state)),
  }).stringify()
}

///|
pub fn Deliverable::append_projection(
  self : Deliverable,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise DeliveryError {
  if projection.aggregate_type != "deliverable" ||
    projection.aggregate_id != self.deliverable_id {
    raise DeliveryError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=deliverable_projection_payload(self),
    source_event_id="company:deliverable:" +
      self.deliverable_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise DeliveryError::Projection(error)
  }
}
