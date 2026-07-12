///|
/// Build a validated accounting-event link for a depreciation entry. The
/// accounting book still controls period-open checks and posting authority.
pub fn DepreciationEntry::to_accounting_event(
  self : DepreciationEntry,
  event_id~ : String,
  event_type~ : String,
  principal_id~ : String,
  expense_account~ : String,
  accumulated_depreciation_account~ : String,
) -> @accounting.AccountingEvent raise AssetError {
  let journal = self.to_journal(
    expense_account~,
    accumulated_depreciation_account~,
  )
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id~,
    source_type="asset_depreciation",
    source_id=self.asset_id + ":" + self.period_id,
    event_type~,
    journal~,
  ) catch {
    error => raise AssetError::AccountingEvent(error)
  }
}

///| Build a validated accounting-event link for a disposal basis. The

///|
/// accounting book still controls posting, period, and cash authority.
pub fn DisposalEntry::to_accounting_event(
  self : DisposalEntry,
  event_id~ : String,
  event_type~ : String,
  principal_id~ : String,
  cash_or_receivable_account~ : String,
  asset_account~ : String,
  accumulated_depreciation_account~ : String,
  gain_account~ : String,
  loss_account~ : String,
) -> @accounting.AccountingEvent raise AssetError {
  let journal = self.to_journal(
    cash_or_receivable_account~,
    asset_account~,
    accumulated_depreciation_account~,
    gain_account~,
    loss_account~,
  )
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id~,
    source_type="asset_disposal",
    source_id=self.asset_id,
    event_type~,
    journal~,
  ) catch {
    error => raise AssetError::AccountingEvent(error)
  }
}
