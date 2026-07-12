///|
fn accounting_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-accounting",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "company:co-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "accounting book validates accounts and closes periods" {
  let book = AccountingBook::new(
      book_id="book-001",
      principal_id="co-001",
      scope="company:co-001",
      actor_id="alice",
      grant=accounting_grant("accounting:book:create"),
    )
    .add_account(
      Account::new(
        account_id="cash",
        account_code="1002",
        name="Cash",
        kind=AccountKind::Asset,
        currency="CNY",
      ),
      actor_id="alice",
      grant=accounting_grant("accounting:account:add"),
    )
    .add_account(
      Account::new(
        account_id="payable",
        account_code="2202",
        name="Payable",
        kind=AccountKind::Liability,
        currency="CNY",
      ),
      actor_id="alice",
      grant=accounting_grant("accounting:account:add"),
    )
    .open_period(
      period_id="2026-07",
      label="July 2026",
      actor_id="alice",
      grant=accounting_grant("accounting:period:create"),
    )
  let amount = @finance.Money::new(minor=50000, currency="CNY")
  let entry : @finance.JournalEntry = {
    entry_id: "entry-001",
    description: "settlement",
    postings: [
      { account: "2202", side: @finance.PostingSide::Debit, amount },
      { account: "1002", side: @finance.PostingSide::Credit, amount },
    ],
  }
  let book = book
    .post(
      period_id="2026-07",
      entry,
      actor_id="alice",
      grant=accounting_grant("accounting:post"),
    )
    .soft_close(
      period_id="2026-07",
      actor_id="alice",
      grant=accounting_grant("accounting:period:soft-close"),
    )
    .close(
      period_id="2026-07",
      actor_id="alice",
      grant=accounting_grant("accounting:period:close"),
    )
  assert_eq(book.ledger.length(), 1)
  assert_true(book.periods[0].state == PeriodState::Closed)
}

///|
test "accounting book rejects an unknown account" {
  let book = AccountingBook::new(
    book_id="book-002",
    principal_id="co-001",
    scope="company:co-001",
    actor_id="alice",
    grant=accounting_grant("accounting:book:create"),
  ).open_period(
    period_id="2026-07",
    label="July 2026",
    actor_id="alice",
    grant=accounting_grant("accounting:period:create"),
  )
  let amount = @finance.Money::new(minor=1, currency="CNY")
  let entry : @finance.JournalEntry = {
    entry_id: "entry-unknown",
    description: "unknown account",
    postings: [
      { account: "9999", side: @finance.PostingSide::Debit, amount },
      { account: "1002", side: @finance.PostingSide::Credit, amount },
    ],
  }
  try
    book.post(
      period_id="2026-07",
      entry,
      actor_id="alice",
      grant=accounting_grant("accounting:post"),
    )
  catch {
    AccountingError::MissingAccount => ()
    _ => fail("wrong accounting error")
  } noraise {
    _ => fail("expected accounting error")
  }
}

///|
test "closed accounting period rejects posting" {
  let book = AccountingBook::new(
      book_id="book-003",
      principal_id="co-001",
      scope="company:co-001",
      actor_id="alice",
      grant=accounting_grant("accounting:book:create"),
    )
    .open_period(
      period_id="2026-07",
      label="July 2026",
      actor_id="alice",
      grant=accounting_grant("accounting:period:create"),
    )
    .soft_close(
      period_id="2026-07",
      actor_id="alice",
      grant=accounting_grant("accounting:period:soft-close"),
    )
  let amount = @finance.Money::new(minor=1, currency="CNY")
  let entry : @finance.JournalEntry = {
    entry_id: "entry-closed",
    description: "closed period",
    postings: [{ account: "1002", side: @finance.PostingSide::Debit, amount }],
  }
  try
    book.post(
      period_id="2026-07",
      entry,
      actor_id="alice",
      grant=accounting_grant("accounting:post"),
    )
  catch {
    AccountingError::PeriodNotOpen => ()
    _ => fail("wrong accounting error")
  } noraise {
    _ => fail("expected accounting error")
  }
}

///|
test "reconciled close requires balanced control reports" {
  let book = AccountingBook::new(
      book_id="book-004",
      principal_id="co-001",
      scope="company:co-001",
      actor_id="alice",
      grant=accounting_grant("accounting:book:create"),
    )
    .open_period(
      period_id="2026-07",
      label="July 2026",
      actor_id="alice",
      grant=accounting_grant("accounting:period:create"),
    )
    .soft_close(
      period_id="2026-07",
      actor_id="alice",
      grant=accounting_grant("accounting:period:soft-close"),
    )
  let amount = @finance.Money::new(minor=100, currency="CNY")
  let balanced = @reconciliation.ReconciliationReport::new(scope="payable", lines=[
    { reference_id: "payable-001", expected: amount, actual: amount },
  ])
  let closed = book.close_reconciled(
    period_id="2026-07",
    reports=[balanced],
    actor_id="alice",
    grant=accounting_grant("accounting:period:close"),
  )
  assert_true(closed.periods[0].state == PeriodState::Closed)
  let unbalanced = @reconciliation.ReconciliationReport::new(
    scope="receivable",
    lines=[
      {
        reference_id: "receivable-001",
        expected: amount,
        actual: @finance.Money::new(minor=90, currency="CNY"),
      },
    ],
  )
  try
    book.close_reconciled(
      period_id="2026-07",
      reports=[unbalanced],
      actor_id="alice",
      grant=accounting_grant("accounting:period:close"),
    )
  catch {
    AccountingError::Reconciliation(
      @reconciliation.ReconciliationError::Unbalanced(-10)
    ) => ()
    _ => fail("wrong accounting error")
  } noraise {
    _ => fail("expected reconciliation gate")
  }
}
