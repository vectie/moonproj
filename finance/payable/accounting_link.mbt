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

///|
/// Build a separate supplier-payment source-to-journal link. The payable
/// transition, cash release, and accounting-book posting remain independent
/// controls; this event only preserves reviewed settlement evidence.
pub fn Payable::to_payment_event(
  self : Payable,
  payment_id~ : String,
  event_id~ : String,
  event_type~ : String,
  amount~ : @finance.Money,
  payable_account~ : String,
  cash_account~ : String,
) -> @accounting.AccountingEvent raise PayableError {
  if payment_id.trim() == "" {
    raise PayableError::EmptyIdentifier
  }
  if amount.minor <= 0 || amount.minor > self.outstanding.minor {
    raise PayableError::OverPayment
  }
  if amount.currency != self.amount.currency {
    raise PayableError::CurrencyMismatch
  }
  let journal : @finance.JournalEntry = {
    entry_id: "payable/" + payment_id + "/payment",
    description: "Pay payable " + self.payable_id,
    postings: [
      { account: payable_account, side: @finance.PostingSide::Debit, amount },
      { account: cash_account, side: @finance.PostingSide::Credit, amount },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="payable_payment",
    source_id=payment_id,
    event_type~,
    journal~,
  ) catch {
    error => raise PayableError::AccountingEvent(error)
  }
}
