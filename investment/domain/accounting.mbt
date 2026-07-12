///|
/// Project an executed position into the balanced acquisition journal. The
/// caller still decides when to create and append an AccountingEvent; this
/// method only supplies the validated source journal.
pub fn InvestmentPosition::to_acquisition_journal(
  self : InvestmentPosition,
  investment_account~ : String,
  cash_account~ : String,
) -> @finance.JournalEntry raise InvestmentError {
  if self.position_id.trim() == "" ||
    investment_account.trim() == "" ||
    cash_account.trim() == "" {
    raise InvestmentError::EmptyIdentifier
  }
  let entry : @finance.JournalEntry = {
    entry_id: "investment-acquisition/" + self.position_id,
    description: "Acquire investment position " + self.position_id,
    postings: [
      {
        account: investment_account,
        side: @finance.PostingSide::Debit,
        amount: self.cost_basis,
      },
      {
        account: cash_account,
        side: @finance.PostingSide::Credit,
        amount: self.cost_basis,
      },
    ],
  }
  @finance.validate_journal(entry) catch {
    error => raise InvestmentError::Journal(error)
  }
  entry
}
