///|
pub(all) enum PostingSide {
  Debit
  Credit
} derive(Debug, Eq)

///|
pub(all) struct Posting {
  account : String
  side : PostingSide
  amount : Money
} derive(Debug, Eq)

///|
pub(all) struct JournalEntry {
  entry_id : String
  description : String
  postings : Array[Posting]
} derive(Debug, Eq)

///|
/// An append-only ledger boundary. Persistence adapters may store the entries
/// elsewhere, but they must preserve this validation contract.
pub(all) struct Ledger {
  entries : Array[JournalEntry]
} derive(Debug, Eq)

///|
pub(all) suberror LedgerError {
  EmptyEntryId
  NoPostings
  EmptyAccount
  NonPositiveAmount
  Unbalanced
  MixedCurrencies
  DuplicateEntry
} derive(Debug, Eq)

///|
pub fn validate_journal(entry : JournalEntry) -> Unit raise LedgerError {
  if entry.entry_id.trim() == "" {
    raise LedgerError::EmptyEntryId
  }
  if entry.postings.length() == 0 {
    raise LedgerError::NoPostings
  }
  let currency = entry.postings[0].amount.currency
  let mut debit : Int64 = 0
  let mut credit : Int64 = 0
  for posting in entry.postings {
    if posting.account.trim() == "" {
      raise LedgerError::EmptyAccount
    }
    if posting.amount.minor <= 0 {
      raise LedgerError::NonPositiveAmount
    }
    if posting.amount.currency != currency {
      raise LedgerError::MixedCurrencies
    }
    match posting.side {
      PostingSide::Debit => debit += posting.amount.minor
      PostingSide::Credit => credit += posting.amount.minor
    }
  }
  if debit != credit {
    raise LedgerError::Unbalanced
  }
}

///|
pub fn Ledger::empty() -> Ledger {
  { entries: [] }
}

///|
pub fn Ledger::post(
  self : Ledger,
  entry : JournalEntry,
) -> Ledger raise LedgerError {
  validate_journal(entry)
  for existing in self.entries {
    if existing.entry_id == entry.entry_id {
      raise LedgerError::DuplicateEntry
    }
  }
  let entries = self.entries.copy()
  entries.push(entry)
  { entries, }
}

///|
pub fn Ledger::length(self : Ledger) -> Int {
  self.entries.length()
}

///|
pub fn journal_total(entry : JournalEntry) -> Money raise LedgerError {
  validate_journal(entry)
  let first = entry.postings[0].amount
  let mut total = try! Money::zero(currency=first.currency)
  for posting in entry.postings {
    total = try! total.add(posting.amount)
  }
  total
}
