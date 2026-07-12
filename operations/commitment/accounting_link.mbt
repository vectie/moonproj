///|
/// Build the source-to-journal link for commitment recognition. Posting and
/// event-log authorization remain separate operations.
pub fn recognition_event(
  commitment : Commitment,
  event_id~ : String,
  event_type~ : String,
  expense_account~ : String,
  payable_account~ : String,
) -> @accounting.AccountingEvent raise CommitmentAccountingError {
  let journal = recognition_journal(
    commitment,
    expense_account~,
    payable_account~,
  )
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=commitment.principal_id,
    source_type="commitment",
    source_id=commitment.commitment_id,
    event_type~,
    journal~,
  ) catch {
    error => raise CommitmentAccountingError::AccountingEvent(error)
  }
}
