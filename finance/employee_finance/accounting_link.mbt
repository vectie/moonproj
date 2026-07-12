///|
/// Build the opening source-to-journal link for an employee advance. Repayment
/// and expense-offset events are separate links; creating this event does not
/// move cash or post to an accounting book.
pub fn EmployeeAdvance::to_accounting_event(
  self : EmployeeAdvance,
  event_id~ : String,
  event_type~ : String,
  advance_account~ : String,
  cash_account~ : String,
) -> @accounting.AccountingEvent raise AdvanceError {
  let journal : @finance.JournalEntry = {
    entry_id: "advance/" + self.advance_id + "/opening",
    description: "Open employee advance " + self.advance_id,
    postings: [
      {
        account: advance_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: cash_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="employee_advance",
    source_id=self.advance_id,
    event_type~,
    journal~,
  ) catch {
    error => raise AdvanceError::AccountingEvent(error)
  }
}

///|
/// Build the separate expense-to-advance link for an explicit repayment or
/// expense offset. The caller still owns the state transition and must pass
/// the source offset identity; this helper does not net, release cash, or post
/// the ledger.
pub fn EmployeeAdvance::to_offset_accounting_event(
  self : EmployeeAdvance,
  offset_id~ : String,
  amount_minor~ : Int64,
  event_id~ : String,
  event_type~ : String,
  expense_account~ : String,
  advance_account~ : String,
) -> @accounting.AccountingEvent raise AdvanceError {
  if offset_id.trim() == "" ||
    amount_minor <= 0 ||
    amount_minor > self.outstanding_minor() {
    raise AdvanceError::OverRepayment
  }
  let amount = @finance.Money::new(
    minor=amount_minor,
    currency=self.amount.currency,
  ) catch {
    _ => raise AdvanceError::InvalidAmount
  }
  let journal : @finance.JournalEntry = {
    entry_id: "advance/" + self.advance_id + "/offset/" + offset_id,
    description: "Offset employee advance " + self.advance_id,
    postings: [
      { account: expense_account, side: @finance.PostingSide::Debit, amount },
      { account: advance_account, side: @finance.PostingSide::Credit, amount },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="employee_advance_offset",
    source_id=offset_id,
    event_type~,
    journal~,
  ) catch {
    error => raise AdvanceError::AccountingEvent(error)
  }
}
