///|
test "money uses fixed point arithmetic" {
  let a = Money::new(minor=1250, currency="CNY")
  let b = Money::new(minor=750, currency="CNY")
  let total = a.add(b)
  assert_eq(total.minor, 2000)
  assert_true(total.is_non_negative())
}

///|
test "journal validation requires balanced postings" {
  let entry : JournalEntry = {
    entry_id: "entry-001",
    description: "Recognize service payable",
    postings: [
      {
        account: "6101",
        side: PostingSide::Debit,
        amount: Money::new(minor=10000, currency="CNY"),
      },
      {
        account: "2202",
        side: PostingSide::Credit,
        amount: Money::new(minor=10000, currency="CNY"),
      },
    ],
  }
  validate_journal(entry)
  let total = journal_total(entry)
  assert_eq(total.minor, 20000)
}

///|
test "unbalanced journal is rejected" {
  let entry : JournalEntry = {
    entry_id: "entry-002",
    description: "Invalid entry",
    postings: [
      {
        account: "6101",
        side: PostingSide::Debit,
        amount: Money::new(minor=10000, currency="CNY"),
      },
      {
        account: "2202",
        side: PostingSide::Credit,
        amount: Money::new(minor=9000, currency="CNY"),
      },
    ],
  }
  try validate_journal(entry) catch {
    LedgerError::Unbalanced => ()
    _ => fail("wrong ledger error")
  } noraise {
    _ => fail("expected ledger error")
  }
}

///|
test "budget reserves, consumes, and releases without overrun" {
  let line = BudgetLine::new(
    line_id="budget-001",
    principal_id="co-001",
    scope="project:p-001",
    currency="CNY",
    allocated_minor=100000,
  )
  let reserved = line.reserve(amount_minor=60000)
  assert_eq(reserved.available_minor(), 40000)
  let consumed = reserved.consume(amount_minor=25000)
  assert_eq(consumed.reserved_minor, 35000)
  assert_eq(consumed.consumed_minor, 25000)
  let released = consumed.release(amount_minor=10000)
  assert_eq(released.reserved_minor, 25000)
}

///|
test "budget rejects an overrun" {
  let line = BudgetLine::new(
    line_id="budget-002",
    principal_id="co-001",
    scope="project:p-001",
    currency="CNY",
    allocated_minor=100000,
  )
  try line.reserve(amount_minor=100001) catch {
    BudgetError::InsufficientAvailable => ()
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected budget error")
  }
}

///|
test "ledger is append-only and rejects duplicate entry ids" {
  let entry : JournalEntry = {
    entry_id: "entry-ledger-001",
    description: "Ledger test",
    postings: [
      {
        account: "6101",
        side: PostingSide::Debit,
        amount: Money::new(minor=1000, currency="CNY"),
      },
      {
        account: "2202",
        side: PostingSide::Credit,
        amount: Money::new(minor=1000, currency="CNY"),
      },
    ],
  }
  let ledger = Ledger::empty().post(entry)
  assert_eq(ledger.length(), 1)
  try ledger.post(entry) catch {
    LedgerError::DuplicateEntry => ()
    _ => fail("wrong ledger error")
  } noraise {
    _ => fail("expected duplicate entry error")
  }
}
