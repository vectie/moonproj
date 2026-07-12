///|
test "reconciliation report aggregates migration lines" {
  let report = ReconciliationReport::new(scope="erp-import/2026-07", lines=[
    {
      reference_id: "project/p-001",
      expected: @finance.Money::new(minor=100, currency="CNY"),
      actual: @finance.Money::new(minor=100, currency="CNY"),
    },
    {
      reference_id: "project/p-002",
      expected: @finance.Money::new(minor=200, currency="CNY"),
      actual: @finance.Money::new(minor=190, currency="CNY"),
    },
  ])
  assert_eq(report.expected_total.minor, 300)
  assert_eq(report.actual_total.minor, 290)
  assert_eq(report.difference_minor, -10)
  assert_true(!report.balanced)
  try report.require_balanced() catch {
    ReconciliationError::Unbalanced(-10) => ()
    _ => fail("wrong reconciliation error")
  } noraise {
    _ => fail("expected reconciliation error")
  }
}

///|
test "journal reconciliation compares a posting side" {
  let amount = @finance.Money::new(minor=50000, currency="CNY")
  let journal : @finance.JournalEntry = {
    entry_id: "settlement/settlement-001",
    description: "settlement",
    postings: [
      { account: "2202", side: @finance.PostingSide::Debit, amount },
      { account: "1002", side: @finance.PostingSide::Credit, amount },
    ],
  }
  let report = reconcile_journal(
    scope="settlement",
    reference_id="settlement-001",
    expected=amount,
    journal~,
    side=@finance.PostingSide::Debit,
  )
  assert_true(report.balanced)
  report.require_balanced()
}

///|
test "reconciliation rejects mixed currencies" {
  try
    ReconciliationReport::new(scope="erp-import", lines=[
      {
        reference_id: "row-1",
        expected: @finance.Money::new(minor=1, currency="CNY"),
        actual: @finance.Money::new(minor=1, currency="USD"),
      },
    ])
  catch {
    ReconciliationError::CurrencyMismatch => ()
    _ => fail("wrong reconciliation error")
  } noraise {
    _ => fail("expected reconciliation error")
  }
}

///|
test "reconciliation rejects duplicate source references" {
  try
    ReconciliationReport::new(scope="erp-import", lines=[
      {
        reference_id: "row-1",
        expected: @finance.Money::new(minor=1, currency="CNY"),
        actual: @finance.Money::new(minor=1, currency="CNY"),
      },
      {
        reference_id: "row-1",
        expected: @finance.Money::new(minor=2, currency="CNY"),
        actual: @finance.Money::new(minor=2, currency="CNY"),
      },
    ])
  catch {
    ReconciliationError::DuplicateReference => ()
    _ => fail("wrong duplicate reference error")
  } noraise {
    _ => fail("expected duplicate reference error")
  }
}
