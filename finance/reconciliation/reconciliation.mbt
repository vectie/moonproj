///|
/// One expected-versus-observed amount used by migration and operational
/// parity reports. The reference is deliberately domain-neutral so the same
/// report can compare an ERP row, a subledger balance, or a journal projection.
pub(all) struct ReconciliationLine {
  reference_id : String
  expected : @finance.Money
  actual : @finance.Money
} derive(Debug, Eq)

///|
pub(all) struct ReconciliationReport {
  scope : String
  lines : Array[ReconciliationLine]
  expected_total : @finance.Money
  actual_total : @finance.Money
  difference_minor : Int64
  balanced : Bool
} derive(Debug, Eq)

///|
pub(all) suberror ReconciliationError {
  EmptyScope
  EmptyReference
  DuplicateReference
  NoLines
  NegativeExpected
  NegativeActual
  CurrencyMismatch
  Unbalanced(Int64)
  Journal(@finance.LedgerError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)

///|
pub fn ReconciliationReport::new(
  scope~ : String,
  lines~ : Array[ReconciliationLine],
) -> ReconciliationReport raise ReconciliationError {
  if scope.trim() == "" {
    raise ReconciliationError::EmptyScope
  }
  if lines.length() == 0 {
    raise ReconciliationError::NoLines
  }
  let first = lines[0]
  if first.reference_id.trim() == "" {
    raise ReconciliationError::EmptyReference
  }
  if first.expected.minor < 0 {
    raise ReconciliationError::NegativeExpected
  }
  if first.actual.minor < 0 {
    raise ReconciliationError::NegativeActual
  }
  let currency = first.expected.currency
  if first.actual.currency != currency {
    raise ReconciliationError::CurrencyMismatch
  }
  let mut expected_total : Int64 = first.expected.minor
  let mut actual_total : Int64 = first.actual.minor
  let seen_references : Array[String] = [first.reference_id]
  for line in lines[1:] {
    if line.reference_id.trim() == "" {
      raise ReconciliationError::EmptyReference
    }
    if line.expected.minor < 0 {
      raise ReconciliationError::NegativeExpected
    }
    if line.actual.minor < 0 {
      raise ReconciliationError::NegativeActual
    }
    if line.expected.currency != currency || line.actual.currency != currency {
      raise ReconciliationError::CurrencyMismatch
    }
    for existing in seen_references {
      if existing == line.reference_id {
        raise ReconciliationError::DuplicateReference
      }
    }
    seen_references.push(line.reference_id)
    expected_total += line.expected.minor
    actual_total += line.actual.minor
  }
  let expected = try! @finance.Money::new(minor=expected_total, currency~)
  let actual = try! @finance.Money::new(minor=actual_total, currency~)
  let difference_minor = actual_total - expected_total
  {
    scope,
    lines: lines.copy(),
    expected_total: expected,
    actual_total: actual,
    difference_minor,
    balanced: difference_minor == 0,
  }
}

///|
pub fn ReconciliationReport::require_balanced(
  self : ReconciliationReport,
) -> Unit raise ReconciliationError {
  if !self.balanced {
    raise ReconciliationError::Unbalanced(self.difference_minor)
  }
}

///|
/// Compare an expected operational amount with one side of a validated journal.
/// This is the seam used by settlement, payable, receivable, and migration
/// parity checks without making the report package own any ledger state.
pub fn reconcile_journal(
  scope~ : String,
  reference_id~ : String,
  expected~ : @finance.Money,
  journal~ : @finance.JournalEntry,
  side~ : @finance.PostingSide,
) -> ReconciliationReport raise ReconciliationError {
  @finance.validate_journal(journal) catch {
    error => raise ReconciliationError::Journal(error)
  }
  let mut actual_minor : Int64 = 0
  for posting in journal.postings {
    if posting.side == side {
      if posting.amount.currency != expected.currency {
        raise ReconciliationError::CurrencyMismatch
      }
      actual_minor += posting.amount.minor
    }
  }
  ReconciliationReport::new(scope~, lines=[
    {
      reference_id,
      expected,
      actual: try! @finance.Money::new(
        minor=actual_minor,
        currency=expected.currency,
      ),
    },
  ])
}
