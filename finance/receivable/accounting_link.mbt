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

///|
/// Build a separate cash-collection source-to-journal link. Collection
/// evidence never mutates the receivable or releases treasury cash; callers
/// must persist the resulting event only after the collection transition is
/// independently authorized.
pub fn Receivable::to_collection_event(
  self : Receivable,
  collection_id~ : String,
  event_id~ : String,
  event_type~ : String,
  amount~ : @finance.Money,
  cash_account~ : String,
  receivable_account~ : String,
) -> @accounting.AccountingEvent raise ReceivableError {
  if collection_id.trim() == "" {
    raise ReceivableError::EmptyIdentifier
  }
  if amount.minor <= 0 || amount.minor > self.outstanding_minor() {
    raise ReceivableError::OverCollection
  }
  if amount.currency != self.amount.currency {
    raise ReceivableError::InvalidAmount
  }
  let journal : @finance.JournalEntry = {
    entry_id: "receivable/" + collection_id + "/collection",
    description: "Collect receivable " + self.receivable_id,
    postings: [
      { account: cash_account, side: @finance.PostingSide::Debit, amount },
      {
        account: receivable_account,
        side: @finance.PostingSide::Credit,
        amount,
      },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="receivable_collection",
    source_id=collection_id,
    event_type~,
    journal~,
  ) catch {
    error => raise ReceivableError::AccountingEvent(error)
  }
}
