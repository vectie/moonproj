///|
/// Build the opening source-to-journal link for a payable. Payment events are
/// separate and must carry their own cash-settlement evidence.
pub fn Payable::to_opening_event(
  self : Payable,
  event_id~ : String,
  event_type~ : String,
  expense_account~ : String,
  payable_account~ : String,
) -> @accounting.AccountingEvent raise PayableError {
  let journal : @finance.JournalEntry = {
    entry_id: "payable/" + self.payable_id + "/opening",
    description: "Open payable " + self.payable_id,
    postings: [
      {
        account: expense_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: payable_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="payable",
    source_id=self.payable_id,
    event_type~,
    journal~,
  ) catch {
    error => raise PayableError::AccountingEvent(error)
  }
}
