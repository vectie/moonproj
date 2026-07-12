///|
/// Build the source-to-journal link for an approved or paid expense claim.
/// Advance offsetting remains a separate source event and is not silently
/// netted into recognition.
pub fn ExpenseClaim::to_accounting_event(
  self : ExpenseClaim,
  event_id~ : String,
  event_type~ : String,
  expense_account~ : String,
  payable_account~ : String,
) -> @accounting.AccountingEvent raise ExpenseError {
  let journal = self.to_recognition_journal(expense_account~, payable_account~)
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="expense_claim",
    source_id=self.expense_id,
    event_type~,
    journal~,
  ) catch {
    error => raise ExpenseError::AccountingEvent(error)
  }
}
