///|
fn accepted_actor(report : ProgressReport) -> String? {
  for event in report.events {
    if event.capability == "delivery:progress:accept" {
      return Some(event.actor_id)
    }
  }
  None
}

///|
/// Create a reviewed recognition link from an accepted report. The acceptance
/// actor is checked against the supplied evidence, and a separate recognition
/// capability is required from the actor creating the link.
pub fn ProgressReport::recognize(
  self : ProgressReport,
  recognition_id~ : String,
  acceptance_id~ : String,
  acceptance_evidence_ids~ : Array[String],
  accepted_by~ : String,
  actor_id~ : String,
  contract_asset_account~ : String,
  revenue_account~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> DeliveryRecognition raise DeliveryError {
  if recognition_id.trim() == "" ||
    acceptance_id.trim() == "" ||
    accepted_by.trim() == "" {
    raise DeliveryError::EmptyIdentifier
  }
  if acceptance_evidence_ids.length() == 0 {
    raise DeliveryError::MissingEvidence
  }
  for evidence_id in acceptance_evidence_ids {
    if evidence_id.trim() == "" {
      raise DeliveryError::MissingEvidence
    }
  }
  if self.state != ProgressState::Accepted || self.completed_value.minor <= 0 {
    raise DeliveryError::InvalidState
  }
  match accepted_actor(self) {
    Some(actor) if actor == accepted_by => ()
    Some(_) => raise DeliveryError::AcceptanceMismatch
    None => raise DeliveryError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="delivery:recognition:create",
    scope=self.project_scope,
    amount_minor=self.completed_value.minor,
  ) catch {
    error => raise DeliveryError::NotAuthorized(error)
  }
  let accounting_event = self.to_recognition_event(
    event_id="delivery-recognition:" + recognition_id,
    event_type="delivery.accepted",
    contract_asset_account~,
    revenue_account~,
  )
  {
    recognition_id,
    report_id: self.report_id,
    project_id: self.project_id,
    principal_id: self.principal_id,
    project_scope: self.project_scope,
    acceptance_id,
    acceptance_evidence_ids: acceptance_evidence_ids.copy(),
    accepted_by,
    created_by: actor_id,
    accounting_event,
  }
}
