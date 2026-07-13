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

///|
fn recognition_postings_json(event : @accounting.AccountingEvent) -> Json {
  let postings : Array[Json] = []
  for posting in event.journal.postings {
    let side = match posting.side {
      @finance.PostingSide::Debit => "debit"
      @finance.PostingSide::Credit => "credit"
    }
    postings.push(
      Json::object({
        "account": Json::string(posting.account),
        "side": Json::string(side),
        "amount_minor": Json::number(
          posting.amount.minor.to_double(),
          repr=posting.amount.minor.to_string(),
        ),
        "currency": Json::string(posting.amount.currency),
      }),
    )
  }
  Json::array(postings)
}

///|
fn recognition_projection_payload(recognition : DeliveryRecognition) -> String {
  let event = recognition.accounting_event
  Json::object({
    "recognition_id": Json::string(recognition.recognition_id),
    "report_id": Json::string(recognition.report_id),
    "project_id": Json::string(recognition.project_id),
    "principal_id": Json::string(recognition.principal_id),
    "project_scope": Json::string(recognition.project_scope),
    "acceptance_id": Json::string(recognition.acceptance_id),
    "acceptance_evidence_ids": evidence_json(
      recognition.acceptance_evidence_ids,
    ),
    "accepted_by": Json::string(recognition.accepted_by),
    "created_by": Json::string(recognition.created_by),
    "event_id": Json::string(event.event_id),
    "source_type": Json::string(event.source_type),
    "source_id": Json::string(event.source_id),
    "event_type": Json::string(event.event_type),
    "journal_entry_id": Json::string(event.journal.entry_id),
    "postings": recognition_postings_json(event),
    "recognition_state": Json::string("pending_posting"),
    "posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify()
}

///|
pub fn DeliveryRecognition::append_projection(
  self : DeliveryRecognition,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise DeliveryError {
  if projection.aggregate_type != "delivery_recognition" ||
    projection.aggregate_id != self.recognition_id {
    raise DeliveryError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=recognition_projection_payload(self),
    source_event_id="company:delivery-recognition:" +
      self.recognition_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise DeliveryError::Projection(error)
  }
}
