///|
test "customer cash is matched to a bank line and accounting event" {
  let treasury_scope = "treasury:operating-cny"
  let customer_id = "customer-echo"
  let amount = cny(250000L)
  let receivable = @receivable.Receivable::open(
    receivable_id="receivable-echo",
    source_id="sale-echo",
    principal_id="opc-market-studio",
    customer_id~,
    amount~,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-receivable-echo-open",
      "finance-operator",
      "receivable:open",
      "customer:" + customer_id,
      250000L,
    ),
  )
  let collection_event = receivable.to_collection_event(
    collection_id="collection-echo",
    event_id="event-collection-echo",
    event_type="customer_cash_collected",
    amount~,
    cash_account="1000-bank",
    receivable_account="1100-accounts-receivable",
  )
  let collected = receivable.collect(
    amount_minor=250000L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-receivable-echo-collect",
      "finance-operator",
      "receivable:collect",
      "customer:" + customer_id,
      250000L,
    ),
  )
  let account = @treasury.CashAccount::open(
    account_id="cash-operating-cny",
    principal_id="opc-market-studio",
    project_scope=treasury_scope,
    currency="CNY",
    bank_reference="bank/account/operating-cny",
    opening_balance=cny(100000L),
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-cash-account-open", "finance-operator", "treasury:account:create", treasury_scope,
      100000L,
    ),
  )
  let requested = @treasury.CashMovement::request(
    account,
    movement_id="movement-collection-echo",
    reference_id="collection-echo",
    amount~,
    direction=Inflow,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-cash-request", "finance-operator", "treasury:request", treasury_scope,
      250000L,
    ),
  )
  let approved = requested.approve(
    actor_id="treasury-reviewer",
    grant=portfolio_authority(
      "grant-cash-approve", "treasury-reviewer", "treasury:approve", treasury_scope,
      250000L,
    ),
  )
  let (updated_account, released) = account.release(
    approved,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-cash-release", "finance-operator", "treasury:release", treasury_scope,
      250000L,
    ),
  )
  let reconciled_movement = released.reconcile(
    actor_id="treasury-reviewer",
    grant=portfolio_authority(
      "grant-cash-reconcile", "treasury-reviewer", "treasury:reconcile", treasury_scope,
      250000L,
    ),
  )
  let line : @treasury.BankStatementLine = {
    line_id: "bank-line-echo",
    account_id: account.account_id,
    principal_id: "opc-market-studio",
    project_scope: treasury_scope,
    external_reference: "bank-credit-echo",
    booked_at: "2026-08-12",
    amount,
    direction: Inflow,
  }
  let imported = @treasury.BankStatement::from_statement(
    statement_id="statement-operating-2026-08",
    account_id=account.account_id,
    principal_id="opc-market-studio",
    project_scope=treasury_scope,
    period="2026-08",
    opening_balance=cny(100000L),
    closing_balance=cny(350000L),
    lines=[line],
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-statement-import", "finance-operator", "treasury:statement:import",
      treasury_scope, 0L,
    ),
  )
  let statement_match : @treasury.StatementMatch = {
    line_id: line.line_id,
    movement_id: reconciled_movement.movement_id,
  }
  let reconciled_statement = imported.reconcile(
    [reconciled_movement],
    matches=[statement_match],
    actor_id="treasury-reviewer",
    grant=portfolio_authority(
      "grant-statement-reconcile", "treasury-reviewer", "treasury:statement:reconcile",
      treasury_scope, 0L,
    ),
  )
  let ledger_match : @treasury.StatementLedgerMatch = {
    line_id: line.line_id,
    event_id: collection_event.event_id,
  }
  let ledger_reconciled = reconciled_statement.reconcile_to_ledger(
    [reconciled_movement],
    [collection_event],
    matches=[ledger_match],
    actor_id="accounting-reviewer",
    grant=portfolio_authority(
      "grant-statement-ledger-reconcile", "accounting-reviewer", "treasury:statement:ledger-reconcile",
      treasury_scope, 0L,
    ),
  )
  assert_eq(collected.state, Collected)
  assert_eq(updated_account.balance.minor, 350000L)
  assert_eq(reconciled_movement.state, Reconciled)
  assert_eq(ledger_reconciled.state, LedgerReconciled)
}
