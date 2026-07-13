///|
/// Build a reviewed draw source-to-journal link. The facility state change and
/// accounting-book posting remain separate events.
pub fn FinancingFacility::to_draw_event(
  self : FinancingFacility,
  draw_id~ : String,
  event_id~ : String,
  event_type~ : String,
  amount~ : @finance.Money,
  cash_account~ : String,
  liability_account~ : String,
) -> @accounting.AccountingEvent raise FinancingError {
  if self.state != FacilityState::Active &&
    self.state != FacilityState::PartiallyRepaid {
    raise FinancingError::InvalidState
  }
  if draw_id.trim() == "" {
    raise FinancingError::EmptyIdentifier
  }
  if amount.minor <= 0 || amount.minor > self.drawn_amount.minor {
    raise FinancingError::InvalidAmount
  }
  if amount.currency != self.limit_amount.currency {
    raise FinancingError::CurrencyMismatch
  }
  let journal : @finance.JournalEntry = {
    entry_id: "financing/" + draw_id + "/draw",
    description: "Draw financing facility " + self.facility_id,
    postings: [
      { account: cash_account, side: @finance.PostingSide::Debit, amount },
      { account: liability_account, side: @finance.PostingSide::Credit, amount },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="financing_facility",
    source_id=draw_id,
    event_type~,
    journal~,
  ) catch {
    error => raise FinancingError::AccountingEvent(error)
  }
}

///|
/// Build a reviewed repayment source-to-journal link before the repayment is
/// posted to the accounting book. The caller supplies a stable repayment ID
/// so multiple repayments cannot collapse into one source event.
pub fn FinancingFacility::to_repayment_event(
  self : FinancingFacility,
  repayment_id~ : String,
  event_id~ : String,
  event_type~ : String,
  amount~ : @finance.Money,
  liability_account~ : String,
  cash_account~ : String,
) -> @accounting.AccountingEvent raise FinancingError {
  if self.state != FacilityState::Active &&
    self.state != FacilityState::PartiallyRepaid {
    raise FinancingError::InvalidState
  }
  if repayment_id.trim() == "" {
    raise FinancingError::EmptyIdentifier
  }
  if amount.minor <= 0 || amount.minor > self.outstanding_principal.minor {
    raise FinancingError::OverRepayment
  }
  if amount.currency != self.limit_amount.currency {
    raise FinancingError::CurrencyMismatch
  }
  let journal : @finance.JournalEntry = {
    entry_id: "financing/" + repayment_id + "/repayment",
    description: "Repay financing facility " + self.facility_id,
    postings: [
      { account: liability_account, side: @finance.PostingSide::Debit, amount },
      { account: cash_account, side: @finance.PostingSide::Credit, amount },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="financing_facility",
    source_id=repayment_id,
    event_type~,
    journal~,
  ) catch {
    error => raise FinancingError::AccountingEvent(error)
  }
}
