///|
fn treasury_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-treasury",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "company:co-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "cash account controls a released inflow and outflow" {
  let account = CashAccount::open(
    account_id="bank-001",
    principal_id="co-001",
    project_scope="company:co-001",
    currency="CNY",
    bank_reference="bank:001",
    opening_balance=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=treasury_grant("treasury:account:create"),
  )
  let incoming = CashMovement::request(
    account,
    movement_id="cash-in-001",
    reference_id="settlement-in-001",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    direction=CashDirection::Inflow,
    actor_id="alice",
    grant=treasury_grant("treasury:request"),
  ).approve(actor_id="alice", grant=treasury_grant("treasury:approve"))
  let (account, incoming) = account.release(
    incoming,
    actor_id="alice",
    grant=treasury_grant("treasury:release"),
  )
  assert_eq(account.balance.minor, 120000L)
  let outgoing = CashMovement::request(
    account,
    movement_id="cash-out-001",
    reference_id="settlement-out-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    direction=CashDirection::Outflow,
    actor_id="alice",
    grant=treasury_grant("treasury:request"),
  ).approve(actor_id="alice", grant=treasury_grant("treasury:approve"))
  let (account, outgoing) = account.release(
    outgoing,
    actor_id="alice",
    grant=treasury_grant("treasury:release"),
  )
  let reconciled = outgoing.reconcile(
    actor_id="alice",
    grant=treasury_grant("treasury:reconcile"),
  )
  assert_eq(account.balance.minor, 70000L)
  assert_true(reconciled.state == CashMovementState::Reconciled)
  assert_eq(incoming.events.length(), 2)
}

///|
test "cash account blocks an overdrawn release" {
  let account = CashAccount::open(
    account_id="bank-002",
    principal_id="co-001",
    project_scope="company:co-001",
    currency="CNY",
    bank_reference="bank:002",
    opening_balance=@finance.Money::new(minor=100, currency="CNY"),
    actor_id="alice",
    grant=treasury_grant("treasury:account:create"),
  )
  let movement = CashMovement::request(
    account,
    movement_id="cash-out-002",
    reference_id="settlement-out-002",
    amount=@finance.Money::new(minor=101, currency="CNY"),
    direction=CashDirection::Outflow,
    actor_id="alice",
    grant=treasury_grant("treasury:request"),
  ).approve(actor_id="alice", grant=treasury_grant("treasury:approve"))
  try
    account.release(
      movement,
      actor_id="alice",
      grant=treasury_grant("treasury:release"),
    )
  catch {
    TreasuryError::InsufficientBalance => ()
    _ => fail("wrong treasury error")
  } noraise {
    _ => fail("expected treasury error")
  }
}

///|
test "cash account and released movement persist treasury evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let account = CashAccount::open(
    account_id="bank-projection",
    principal_id="co-001",
    project_scope="company:co-001",
    currency="CNY",
    bank_reference="bank:projection",
    opening_balance=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=treasury_grant("treasury:account:create"),
  )
  let movement = CashMovement::request(
    account,
    movement_id="cash-projection",
    reference_id="settlement-projection",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    direction=CashDirection::Inflow,
    actor_id="alice",
    grant=treasury_grant("treasury:request"),
  ).approve(actor_id="alice", grant=treasury_grant("treasury:approve"))
  let (account, movement) = account.release(
    movement,
    actor_id="alice",
    grant=treasury_grant("treasury:release"),
  )
  let account_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="cash_account",
    aggregate_id="bank-projection",
  )
  let account_projection = account.append_projection(account_projection)
  let movement_projection = @store.AggregateProjection::new(
    account_projection.into_store(),
    aggregate_type="cash_movement",
    aggregate_id="cash-projection",
  )
  let movement_projection = movement.append_projection(movement_projection)
  match movement_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("released"))
      assert_true(latest.payload.contains("20000"))
    }
    None => fail("expected cash movement projection")
  }
}
