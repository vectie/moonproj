///|
/// A commitment-to-budget reservation is explicit so budget consumption can be
/// reconciled independently from contract and payment state.
pub(all) struct BudgetReservation {
  reservation_id : String
  commitment_id : String
  budget_line_id : String
  amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
pub(all) suberror CommitmentBudgetError {
  InvalidState
  InvalidAmount
  CurrencyMismatch
  AmountExceedsCommitment
  Budget(@finance.BudgetError)
} derive(Debug, Eq)

///|
pub fn reserve_budget(
  commitment : Commitment,
  budget : @finance.BudgetLine,
  reservation_id~ : String,
  amount_minor~ : Int64,
) -> (BudgetReservation, @finance.BudgetLine) raise CommitmentBudgetError {
  if commitment.state != CommitmentState::Draft &&
    commitment.state != CommitmentState::Submitted {
    raise CommitmentBudgetError::InvalidState
  }
  if reservation_id.trim() == "" || amount_minor <= 0 {
    raise CommitmentBudgetError::InvalidAmount
  }
  if amount_minor > commitment.amount.minor {
    raise CommitmentBudgetError::AmountExceedsCommitment
  }
  if commitment.amount.currency != budget.currency {
    raise CommitmentBudgetError::CurrencyMismatch
  }
  let reserved = budget.reserve(amount_minor~) catch {
    error => raise CommitmentBudgetError::Budget(error)
  }
  (
    {
      reservation_id,
      commitment_id: commitment.commitment_id,
      budget_line_id: budget.line_id,
      amount_minor,
      currency: budget.currency,
    },
    reserved,
  )
}

///|
pub fn BudgetReservation::consume(
  self : BudgetReservation,
  budget : @finance.BudgetLine,
) -> @finance.BudgetLine raise CommitmentBudgetError {
  if budget.line_id != self.budget_line_id || budget.currency != self.currency {
    raise CommitmentBudgetError::CurrencyMismatch
  }
  budget.consume(amount_minor=self.amount_minor) catch {
    error => raise CommitmentBudgetError::Budget(error)
  }
}

///|
pub fn BudgetReservation::release(
  self : BudgetReservation,
  budget : @finance.BudgetLine,
) -> @finance.BudgetLine raise CommitmentBudgetError {
  if budget.line_id != self.budget_line_id || budget.currency != self.currency {
    raise CommitmentBudgetError::CurrencyMismatch
  }
  budget.release(amount_minor=self.amount_minor) catch {
    error => raise CommitmentBudgetError::Budget(error)
  }
}
