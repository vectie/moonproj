///|
/// Build a validated source-to-journal link for a controlled investment
/// acquisition. Market analysis and proposal approval remain separate events.
pub fn InvestmentPosition::to_accounting_event(
  self : InvestmentPosition,
  event_id~ : String,
  event_type~ : String,
  principal_id~ : String,
  investment_account~ : String,
  cash_account~ : String,
) -> @accounting.AccountingEvent raise InvestmentError {
  let journal = self.to_acquisition_journal(investment_account~, cash_account~)
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id~,
    source_type="investment_position",
    source_id=self.position_id,
    event_type~,
    journal~,
  ) catch {
    error => raise InvestmentError::AccountingEvent(error)
  }
}
