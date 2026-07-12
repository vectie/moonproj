///|
pub(all) enum AccountKind {
  Asset
  Liability
  Equity
  Revenue
  Expense
} derive(Debug, Eq)

///|
pub(all) struct Account {
  account_id : String
  account_code : String
  name : String
  kind : AccountKind
  currency : String
  active : Bool
} derive(Debug, Eq)

///|
pub(all) struct ChartOfAccounts {
  accounts : Array[Account]
} derive(Debug, Eq)

///|
pub(all) enum PeriodState {
  Open
  SoftClosed
  Closed
} derive(Debug, Eq)

///|
pub(all) struct AccountingPeriod {
  period_id : String
  label : String
  state : PeriodState
} derive(Debug, Eq)

///|
pub(all) struct AccountingBook {
  book_id : String
  principal_id : String
  scope : String
  chart : ChartOfAccounts
  periods : Array[AccountingPeriod]
  ledger : @finance.Ledger
} derive(Debug, Eq)

///|
pub(all) suberror AccountingError {
  EmptyIdentifier
  InvalidCurrency
  DuplicateAccount
  MissingAccount
  DuplicatePeriod
  InvalidPeriod
  PeriodNotOpen
  InactiveAccount
  CurrencyMismatch
  ReconciliationRequired
  Reconciliation(@reconciliation.ReconciliationError)
  NotAuthorized(@foundation.AuthorityError)
  Ledger(@finance.LedgerError)
} derive(Debug, Eq)

///|
pub fn Account::new(
  account_id~ : String,
  account_code~ : String,
  name~ : String,
  kind~ : AccountKind,
  currency~ : String,
) -> Account raise AccountingError {
  if account_id.trim() == "" || account_code.trim() == "" || name.trim() == "" {
    raise AccountingError::EmptyIdentifier
  }
  if currency.length() != 3 {
    raise AccountingError::InvalidCurrency
  }
  { account_id, account_code, name, kind, currency, active: true }
}

///|
pub fn ChartOfAccounts::empty() -> ChartOfAccounts {
  { accounts: [] }
}

///|
pub fn ChartOfAccounts::add(
  self : ChartOfAccounts,
  account : Account,
) -> ChartOfAccounts raise AccountingError {
  for existing in self.accounts {
    if existing.account_id == account.account_id ||
      existing.account_code == account.account_code {
      raise AccountingError::DuplicateAccount
    }
  }
  let accounts = self.accounts.copy()
  accounts.push(account)
  { accounts, }
}

///|
pub fn AccountingPeriod::new(
  period_id~ : String,
  label~ : String,
  actor_id~ : String,
  principal_id~ : String,
  scope~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingPeriod raise AccountingError {
  if period_id.trim() == "" || label.trim() == "" {
    raise AccountingError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="accounting:period:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise AccountingError::NotAuthorized(error)
  }
  { period_id, label, state: PeriodState::Open }
}

///|
pub fn AccountingBook::new(
  book_id~ : String,
  principal_id~ : String,
  scope~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  if book_id.trim() == "" || principal_id.trim() == "" || scope.trim() == "" {
    raise AccountingError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="accounting:book:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise AccountingError::NotAuthorized(error)
  }
  {
    book_id,
    principal_id,
    scope,
    chart: ChartOfAccounts::empty(),
    periods: [],
    ledger: @finance.Ledger::empty(),
  }
}

///|
pub fn AccountingBook::add_account(
  self : AccountingBook,
  account : Account,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="accounting:account:add",
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise AccountingError::NotAuthorized(error)
  }
  let chart = self.chart.add(account)
  { ..self, chart, }
}

///|
pub fn AccountingBook::open_period(
  self : AccountingBook,
  period_id~ : String,
  label~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  for period in self.periods {
    if period.period_id == period_id {
      raise AccountingError::DuplicatePeriod
    }
  }
  let period = AccountingPeriod::new(
    period_id~,
    label~,
    actor_id~,
    principal_id=self.principal_id,
    scope=self.scope,
    grant~,
  )
  let periods = self.periods.copy()
  periods.push(period)
  { ..self, periods, }
}

///|
fn period_state(
  book : AccountingBook,
  period_id : String,
) -> PeriodState raise AccountingError {
  for period in book.periods {
    if period.period_id == period_id {
      return period.state
    }
  }
  raise AccountingError::InvalidPeriod
}

///|
fn account_for(
  book : AccountingBook,
  account_code : String,
) -> Account raise AccountingError {
  for account in book.chart.accounts {
    if account.account_code == account_code {
      return account
    }
  }
  raise AccountingError::MissingAccount
}

///|
pub fn AccountingBook::post(
  self : AccountingBook,
  period_id~ : String,
  entry : @finance.JournalEntry,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  if period_state(self, period_id) != PeriodState::Open {
    raise AccountingError::PeriodNotOpen
  }
  @finance.validate_journal(entry) catch {
    error => raise AccountingError::Ledger(error)
  }
  let first_currency = entry.postings[0].amount.currency
  for posting in entry.postings {
    let account = account_for(self, posting.account)
    if !account.active {
      raise AccountingError::InactiveAccount
    }
    if account.currency != first_currency {
      raise AccountingError::CurrencyMismatch
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="accounting:post",
    scope=self.scope,
    amount_minor=entry.postings[0].amount.minor,
  ) catch {
    error => raise AccountingError::NotAuthorized(error)
  }
  let ledger = self.ledger.post(entry) catch {
    error => raise AccountingError::Ledger(error)
  }
  { ..self, ledger, }
}

///|
fn AccountingBook::change_period(
  self : AccountingBook,
  period_id : String,
  to : PeriodState,
  capability : String,
  actor_id : String,
  grant : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  let current = period_state(self, period_id)
  let allowed = (current == PeriodState::Open && to == PeriodState::SoftClosed) ||
    (current == PeriodState::SoftClosed && to == PeriodState::Closed)
  if !allowed {
    raise AccountingError::InvalidPeriod
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise AccountingError::NotAuthorized(error)
  }
  let periods = self.periods.copy()
  for i in 0..<periods.length() {
    if periods[i].period_id == period_id {
      periods[i] = { ..periods[i], state: to }
    }
  }
  { ..self, periods, }
}

///|
pub fn AccountingBook::soft_close(
  self : AccountingBook,
  period_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  self.change_period(
    period_id,
    PeriodState::SoftClosed,
    "accounting:period:soft-close",
    actor_id,
    grant,
  )
}

///|
pub fn AccountingBook::close(
  self : AccountingBook,
  period_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  self.change_period(
    period_id,
    PeriodState::Closed,
    "accounting:period:close",
    actor_id,
    grant,
  )
}

///|
/// Close a period only after every supplied subledger/control report is
/// balanced. The ordinary `close` method remains available for low-level book
/// construction; production workflows should use this gate so close cannot
/// silently bypass reconciliation.
pub fn AccountingBook::close_reconciled(
  self : AccountingBook,
  period_id~ : String,
  reports~ : Array[@reconciliation.ReconciliationReport],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingBook raise AccountingError {
  if reports.length() == 0 {
    raise AccountingError::ReconciliationRequired
  }
  for report in reports {
    report.require_balanced() catch {
      error => raise AccountingError::Reconciliation(error)
    }
  }
  self.close(period_id~, actor_id~, grant~)
}
