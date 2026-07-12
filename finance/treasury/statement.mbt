///|
/// A single immutable line imported from a bank statement.
pub(all) struct BankStatementLine {
  line_id : String
  account_id : String
  principal_id : String
  project_scope : String
  external_reference : String
  booked_at : String
  amount : @finance.Money
  direction : CashDirection
} derive(Debug, Eq)

///|
pub(all) struct StatementMatch {
  line_id : String
  movement_id : String
} derive(Debug, Eq)

///|
/// A reviewed line-to-journal identity link; it does not post the journal.
pub(all) struct StatementLedgerMatch {
  line_id : String
  event_id : String
} derive(Debug, Eq)

///|
pub(all) enum BankStatementState {
  Imported
  Reconciled
  LedgerReconciled
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct BankStatement {
  statement_id : String
  account_id : String
  principal_id : String
  project_scope : String
  period : String
  opening_balance : @finance.Money
  closing_balance : @finance.Money
  lines : Array[BankStatementLine]
  matches : Array[StatementMatch]
  ledger_matches : Array[StatementLedgerMatch]
  state : BankStatementState
} derive(Debug, Eq)

///|
pub(all) suberror StatementError {
  EmptyIdentifier
  InvalidAmount
  CurrencyMismatch
  AccountMismatch
  DuplicateLine
  DuplicateMovement
  InvalidBalance
  InvalidState
  MissingMatch
  UnknownLine
  UnknownMovement
  MovementMismatch
  InvalidMovementState
  LedgerMismatch
  MissingLedgerMatch
  UnknownAccountingEvent
  DuplicateLedgerMatch
  InvalidLedgerState
  NotAuthorized(@foundation.AuthorityError)
  Money(@finance.MoneyError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn BankStatement::from_statement(
  statement_id~ : String,
  account_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  period~ : String,
  opening_balance~ : @finance.Money,
  closing_balance~ : @finance.Money,
  lines~ : Array[BankStatementLine],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> BankStatement raise StatementError {
  if statement_id.trim() == "" ||
    account_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    period.trim() == "" {
    raise StatementError::EmptyIdentifier
  }
  if opening_balance.currency != closing_balance.currency {
    raise StatementError::CurrencyMismatch
  }
  let mut expected_balance = opening_balance.minor
  let seen : Array[String] = []
  for line in lines {
    if line.line_id.trim() == "" ||
      line.external_reference.trim() == "" ||
      line.booked_at.trim() == "" {
      raise StatementError::EmptyIdentifier
    }
    for existing in seen {
      if existing == line.line_id {
        raise StatementError::DuplicateLine
      }
    }
    seen.push(line.line_id)
    if line.account_id != account_id ||
      line.principal_id != principal_id ||
      line.project_scope != project_scope {
      raise StatementError::AccountMismatch
    }
    if line.amount.minor <= 0 {
      raise StatementError::InvalidAmount
    }
    if line.amount.currency != opening_balance.currency {
      raise StatementError::CurrencyMismatch
    }
    expected_balance = match line.direction {
      CashDirection::Inflow => expected_balance + line.amount.minor
      CashDirection::Outflow => expected_balance - line.amount.minor
    }
  }
  if expected_balance != closing_balance.minor {
    raise StatementError::InvalidBalance
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="treasury:statement:import",
    scope=project_scope,
    amount_minor=0,
  ) catch {
    error => raise StatementError::NotAuthorized(error)
  }
  {
    statement_id,
    account_id,
    principal_id,
    project_scope,
    period,
    opening_balance,
    closing_balance,
    lines: lines.copy(),
    matches: [],
    ledger_matches: [],
    state: BankStatementState::Imported,
  }
}

///|
fn statement_line_for(
  lines : Array[BankStatementLine],
  line_id : String,
) -> BankStatementLine? {
  for line in lines {
    if line.line_id == line_id {
      return Some(line)
    }
  }
  None
}

///|
fn movement_for(
  movements : Array[CashMovement],
  movement_id : String,
) -> CashMovement? {
  for movement in movements {
    if movement.movement_id == movement_id {
      return Some(movement)
    }
  }
  None
}

///|
fn statement_match_for(
  matches : Array[StatementMatch],
  line_id : String,
) -> StatementMatch? {
  for item in matches {
    if item.line_id == line_id {
      return Some(item)
    }
  }
  None
}

///|
fn accounting_event_for(
  events : Array[@accounting.AccountingEvent],
  event_id : String,
) -> @accounting.AccountingEvent? {
  for event in events {
    if event.event_id == event_id {
      return Some(event)
    }
  }
  None
}

///| Match every reconciled statement line to a reviewed source-to-journal

///| event. This validates traceability only; the accounting book still owns

///|
/// posting and period controls.
pub fn BankStatement::reconcile_to_ledger(
  self : BankStatement,
  movements : Array[CashMovement],
  events : Array[@accounting.AccountingEvent],
  matches~ : Array[StatementLedgerMatch],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> BankStatement raise StatementError {
  if self.state != BankStatementState::Reconciled {
    raise StatementError::InvalidLedgerState
  }
  if self.matches.length() != self.lines.length() ||
    matches.length() != self.lines.length() {
    raise StatementError::MissingLedgerMatch
  }
  let matched_lines : Array[String] = []
  let matched_events : Array[String] = []
  for item in matches {
    if item.line_id.trim() == "" || item.event_id.trim() == "" {
      raise StatementError::MissingLedgerMatch
    }
    for existing in matched_lines {
      if existing == item.line_id {
        raise StatementError::DuplicateLedgerMatch
      }
    }
    for existing in matched_events {
      if existing == item.event_id {
        raise StatementError::DuplicateLedgerMatch
      }
    }
    matched_lines.push(item.line_id)
    matched_events.push(item.event_id)
    let line = match statement_line_for(self.lines, item.line_id) {
      Some(value) => value
      None => raise StatementError::UnknownLine
    }
    let event = match accounting_event_for(events, item.event_id) {
      Some(value) => value
      None => raise StatementError::UnknownAccountingEvent
    }
    if event.principal_id != self.principal_id || event.source_id.trim() == "" {
      raise StatementError::LedgerMismatch
    }
    let mut debit_total : Int64 = 0
    let mut debit_currency : String? = None
    for posting in event.journal.postings {
      match posting.side {
        @finance.PostingSide::Debit => {
          debit_total += posting.amount.minor
          debit_currency = Some(posting.amount.currency)
        }
        @finance.PostingSide::Credit => ()
      }
    }
    if debit_total != line.amount.minor ||
      debit_currency != Some(line.amount.currency) {
      raise StatementError::LedgerMismatch
    }
    let movement_id = match statement_match_for(self.matches, line.line_id) {
      Some(value) => value.movement_id
      None => raise StatementError::MissingMatch
    }
    let movement = match movement_for(movements, movement_id) {
      Some(value) => value
      None => raise StatementError::UnknownMovement
    }
    if event.source_id != movement.reference_id {
      raise StatementError::LedgerMismatch
    }
  }
  for line in self.lines {
    let mut found = false
    for matched in matched_lines {
      if matched == line.line_id {
        found = true
      }
    }
    if !found {
      raise StatementError::MissingLedgerMatch
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:statement:ledger-reconcile",
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise StatementError::NotAuthorized(error)
  }
  {
    ..self,
    ledger_matches: matches.copy(),
    state: BankStatementState::LedgerReconciled,
  }
}

///|
pub fn BankStatement::reconcile(
  self : BankStatement,
  movements : Array[CashMovement],
  matches~ : Array[StatementMatch],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> BankStatement raise StatementError {
  if self.state != BankStatementState::Imported {
    raise StatementError::InvalidState
  }
  if matches.length() != self.lines.length() {
    raise StatementError::MissingMatch
  }
  let matched_lines : Array[String] = []
  let matched_movements : Array[String] = []
  for item in matches {
    if item.line_id.trim() == "" || item.movement_id.trim() == "" {
      raise StatementError::MissingMatch
    }
    for existing in matched_lines {
      if existing == item.line_id {
        raise StatementError::DuplicateLine
      }
    }
    for existing in matched_movements {
      if existing == item.movement_id {
        raise StatementError::DuplicateMovement
      }
    }
    matched_lines.push(item.line_id)
    matched_movements.push(item.movement_id)
    let line = match statement_line_for(self.lines, item.line_id) {
      Some(value) => value
      None => raise StatementError::UnknownLine
    }
    let movement = match movement_for(movements, item.movement_id) {
      Some(value) => value
      None => raise StatementError::UnknownMovement
    }
    if movement.state != CashMovementState::Released &&
      movement.state != CashMovementState::Reconciled {
      raise StatementError::InvalidMovementState
    }
    if movement.account_id != self.account_id ||
      movement.principal_id != self.principal_id ||
      movement.project_scope != self.project_scope ||
      movement.amount != line.amount ||
      movement.direction != line.direction {
      raise StatementError::MovementMismatch
    }
  }
  for line in self.lines {
    let mut found = false
    for matched in matched_lines {
      if matched == line.line_id {
        found = true
      }
    }
    if !found {
      raise StatementError::MissingMatch
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="treasury:statement:reconcile",
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise StatementError::NotAuthorized(error)
  }
  { ..self, matches: matches.copy(), state: BankStatementState::Reconciled }
}
