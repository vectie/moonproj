///|
/// Build a validated source-to-journal link for accepted delivery progress.
/// Acceptance is an operational gate; constructing this event does not post
/// the journal, recognize cash, or decide tax treatment.
pub fn ProgressReport::to_recognition_event(
  self : ProgressReport,
  event_id~ : String,
  event_type~ : String,
  contract_asset_account~ : String,
  revenue_account~ : String,
) -> @accounting.AccountingEvent raise DeliveryError {
  if self.state != ProgressState::Accepted {
    raise DeliveryError::InvalidState
  }
  if self.completed_value.minor <= 0 {
    raise DeliveryError::InvalidAmount
  }
  let journal : @finance.JournalEntry = {
    entry_id: "delivery/" + self.report_id + "/recognition",
    description: "Recognize accepted delivery progress " + self.report_id,
    postings: [
      {
        account: contract_asset_account,
        side: @finance.PostingSide::Debit,
        amount: self.completed_value,
      },
      {
        account: revenue_account,
        side: @finance.PostingSide::Credit,
        amount: self.completed_value,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="delivery_progress",
    source_id=self.report_id,
    event_type~,
    journal~,
  ) catch {
    error => raise DeliveryError::AccountingEvent(error)
  }
}
