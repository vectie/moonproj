///|
/// Build the opening source-to-journal link for a receivable. Collection cash
/// events are separate and must carry their own settlement evidence.
pub fn Receivable::to_opening_event(
  self : Receivable,
  event_id~ : String,
  event_type~ : String,
  receivable_account~ : String,
  revenue_account~ : String,
) -> @accounting.AccountingEvent raise ReceivableError {
  let journal : @finance.JournalEntry = {
    entry_id: "receivable/" + self.receivable_id + "/opening",
    description: "Open receivable " + self.receivable_id,
    postings: [
      {
        account: receivable_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: revenue_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="receivable",
    source_id=self.receivable_id,
    event_type~,
    journal~,
  ) catch {
    error => raise ReceivableError::AccountingEvent(error)
  }
}
