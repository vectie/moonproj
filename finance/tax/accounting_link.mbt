///|
/// Build the reviewed tax-obligation recognition link. Filing, payment, and
/// accounting-book posting remain separate authority-bearing events.
pub fn TaxObligation::to_accounting_event(
  self : TaxObligation,
  event_id~ : String,
  event_type~ : String,
  tax_expense_account~ : String,
  tax_payable_account~ : String,
) -> @accounting.AccountingEvent raise TaxError {
  if self.state != TaxObligationState::Reviewed &&
    self.state != TaxObligationState::Filed &&
    self.state != TaxObligationState::Paid {
    raise TaxError::InvalidTransition
  }
  if self.tax_amount.minor <= 0 {
    raise TaxError::InvalidAmount
  }
  let journal : @finance.JournalEntry = {
    entry_id: "tax/" + self.tax_id + "/recognition",
    description: "Recognize tax obligation " + self.tax_id,
    postings: [
      {
        account: tax_expense_account,
        side: @finance.PostingSide::Debit,
        amount: self.tax_amount,
      },
      {
        account: tax_payable_account,
        side: @finance.PostingSide::Credit,
        amount: self.tax_amount,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="tax_obligation",
    source_id=self.tax_id,
    event_type~,
    journal~,
  ) catch {
    error => raise TaxError::AccountingEvent(error)
  }
}
