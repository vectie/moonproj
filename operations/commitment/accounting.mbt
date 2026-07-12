///|
pub(all) suberror CommitmentAccountingError {
  InvalidState
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
} derive(Debug, Eq)

///|
/// Recognize a performed commitment as expense/inventory and payable. Payment
/// release is a separate settlement journal.
pub fn recognition_journal(
  commitment : Commitment,
  expense_account~ : String,
  payable_account~ : String,
) -> @finance.JournalEntry raise CommitmentAccountingError {
  if commitment.state != CommitmentState::Performed {
    raise CommitmentAccountingError::InvalidState
  }
  let entry : @finance.JournalEntry = {
    entry_id: "commitment/\{commitment.commitment_id}/recognition",
    description: "Recognize commitment \{commitment.commitment_id}",
    postings: [
      {
        account: expense_account,
        side: @finance.PostingSide::Debit,
        amount: commitment.amount,
      },
      {
        account: payable_account,
        side: @finance.PostingSide::Credit,
        amount: commitment.amount,
      },
    ],
  }
  @finance.validate_journal(entry) catch {
    error => raise CommitmentAccountingError::Journal(error)
  }
  entry
}
