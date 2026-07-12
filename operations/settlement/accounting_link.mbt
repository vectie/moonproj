///|
/// Build the validated source-to-journal link for a released settlement. The
/// caller still appends it to an authorized `AccountingEventLog`; constructing
/// the link does not post or authorize accounting by itself.
pub fn Settlement::to_accounting_event(
  self : Settlement,
  event_id~ : String,
  event_type~ : String,
  payable_account~ : String,
  cash_account~ : String,
) -> @accounting.AccountingEvent raise SettlementError {
  let journal = self.to_journal(payable_account~, cash_account~)
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="settlement",
    source_id=self.settlement_id,
    event_type~,
    journal~,
  ) catch {
    error => raise SettlementError::AccountingEvent(error)
  }
}
