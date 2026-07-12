///|
fn statement_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-statement",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "company:co-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn released_statement_movement() -> CashMovement {
  let account = try! CashAccount::open(
    account_id="bank-statement-001-release",
    principal_id="co-001",
    project_scope="company:co-001",
    currency="CNY",
    bank_reference="bank:statement-001-release",
    opening_balance=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=statement_grant("treasury:account:create"),
  )
  let movement = try! CashMovement::request(
    account,
    movement_id="cash-statement-in-001",
    reference_id="settlement-statement-001",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    direction=CashDirection::Inflow,
    actor_id="alice",
    grant=statement_grant("treasury:request"),
  ).approve(actor_id="alice", grant=statement_grant("treasury:approve"))
  let (_, released) = try! account.release(
    movement,
    actor_id="alice",
    grant=statement_grant("treasury:release"),
  )
  released
}

///|
test "bank statement imports, matches released movement, and projects" {
  let movement = released_statement_movement()
  let statement = BankStatement::from_statement(
    statement_id="statement-001",
    account_id="bank-statement-001-release",
    principal_id="co-001",
    project_scope="company:co-001",
    period="2026-01",
    opening_balance=@finance.Money::new(minor=100000, currency="CNY"),
    closing_balance=@finance.Money::new(minor=120000, currency="CNY"),
    lines=[
      {
        line_id: "line-001",
        account_id: "bank-statement-001-release",
        principal_id: "co-001",
        project_scope: "company:co-001",
        external_reference: "bank-ref-001",
        booked_at: "2026-01-10",
        amount: @finance.Money::new(minor=20000, currency="CNY"),
        direction: CashDirection::Inflow,
      },
    ],
    actor_id="alice",
    grant=statement_grant("treasury:statement:import"),
  )
  let reconciled = statement.reconcile(
    [movement],
    matches=[{ line_id: "line-001", movement_id: "cash-statement-in-001" }],
    actor_id="alice",
    grant=statement_grant("treasury:statement:reconcile"),
  )
  assert_true(reconciled.state == BankStatementState::Reconciled)
  assert_eq(reconciled.matches.length(), 1)
  let event = try! @accounting.AccountingEvent::new(
    event_id="event-statement-001",
    principal_id="co-001",
    source_type="settlement",
    source_id="settlement-statement-001",
    event_type="settlement.received",
    journal={
      entry_id: "journal-statement-001",
      description: "Statement settlement",
      postings: [
        {
          account: "1001",
          side: @finance.PostingSide::Debit,
          amount: @finance.Money::new(minor=20000, currency="CNY"),
        },
        {
          account: "1122",
          side: @finance.PostingSide::Credit,
          amount: @finance.Money::new(minor=20000, currency="CNY"),
        },
      ],
    },
  )
  assert_eq(event.principal_id, "co-001")
  assert_eq(event.source_id, "settlement-statement-001")
  let ledger_reconciled = reconciled.reconcile_to_ledger(
    [movement],
    [event],
    matches=[{ line_id: "line-001", event_id: "event-statement-001" }],
    actor_id="alice",
    grant=statement_grant("treasury:statement:ledger-reconcile"),
  )
  assert_true(ledger_reconciled.state == BankStatementState::LedgerReconciled)
  assert_eq(ledger_reconciled.ledger_matches.length(), 1)
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="bank_statement",
    aggregate_id="statement-001",
  )
  let projection = ledger_reconciled.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("ledger_reconciled"))
      assert_true(latest.payload.contains("cash-statement-in-001"))
      assert_true(latest.payload.contains("event-statement-001"))
    }
    None => fail("expected bank statement projection")
  }
}

///|
test "bank statement rejects balance and movement mismatches" {
  try
    BankStatement::from_statement(
      statement_id="statement-bad-balance",
      account_id="bank-001",
      principal_id="co-001",
      project_scope="company:co-001",
      period="2026-01",
      opening_balance=@finance.Money::new(minor=100, currency="CNY"),
      closing_balance=@finance.Money::new(minor=102, currency="CNY"),
      lines=[
        {
          line_id: "line-bad",
          account_id: "bank-001",
          principal_id: "co-001",
          project_scope: "company:co-001",
          external_reference: "bank-ref-bad",
          booked_at: "2026-01-10",
          amount: @finance.Money::new(minor=1, currency="CNY"),
          direction: CashDirection::Inflow,
        },
      ],
      actor_id="alice",
      grant=statement_grant("treasury:statement:import"),
    )
  catch {
    StatementError::InvalidBalance => ()
    _ => fail("wrong statement error")
  } noraise {
    _ => fail("expected statement balance error")
  }
  let movement = released_statement_movement()
  let statement = BankStatement::from_statement(
    statement_id="statement-mismatch",
    account_id="bank-statement-001-release",
    principal_id="co-001",
    project_scope="company:co-001",
    period="2026-01",
    opening_balance=@finance.Money::new(minor=100000, currency="CNY"),
    closing_balance=@finance.Money::new(minor=119000, currency="CNY"),
    lines=[
      {
        line_id: "line-mismatch",
        account_id: "bank-statement-001-release",
        principal_id: "co-001",
        project_scope: "company:co-001",
        external_reference: "bank-ref-mismatch",
        booked_at: "2026-01-10",
        amount: @finance.Money::new(minor=19000, currency="CNY"),
        direction: CashDirection::Inflow,
      },
    ],
    actor_id="alice",
    grant=statement_grant("treasury:statement:import"),
  )
  try
    statement.reconcile(
      [movement],
      matches=[
        { line_id: "line-mismatch", movement_id: "cash-statement-in-001" },
      ],
      actor_id="alice",
      grant=statement_grant("treasury:statement:reconcile"),
    )
  catch {
    StatementError::MovementMismatch => ()
    _ => fail("wrong statement movement error")
  } noraise {
    _ => fail("expected statement movement mismatch")
  }
}
