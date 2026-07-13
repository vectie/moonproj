///|
fn payable_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-payable",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "payable tracks partial and complete supplier settlement" {
  let payable = Payable::open(
    payable_id="pay-001",
    principal_id="co-001",
    project_scope="project:p-001",
    supplier_id="supplier-001",
    source_reference="commitment/commit-001",
    amount=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:create"),
  )
  let partial = payable.record_payment(
    payment=@finance.Money::new(minor=40000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:pay"),
  )
  let paid = partial.record_payment(
    payment=@finance.Money::new(minor=60000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:pay"),
  )
  assert_true(partial.state == PayableState::PartiallyPaid)
  assert_true(paid.state == PayableState::Paid)
  assert_eq(paid.outstanding.minor, 0L)
}

///|
test "payable rejects overpayment" {
  let payable = Payable::open(
    payable_id="pay-002",
    principal_id="co-001",
    project_scope="project:p-001",
    supplier_id="supplier-001",
    source_reference="commitment/commit-002",
    amount=@finance.Money::new(minor=100, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:create"),
  )
  try
    payable.record_payment(
      payment=@finance.Money::new(minor=101, currency="CNY"),
      actor_id="alice",
      grant=payable_grant("payable:pay"),
    )
  catch {
    PayableError::OverPayment => ()
    _ => fail("wrong payable error")
  } noraise {
    _ => fail("expected payable error")
  }
}

///|
test "payable opening creates a source accounting event" {
  let payable = Payable::open(
    payable_id="pay-accounting",
    principal_id="co-001",
    project_scope="project:p-001",
    supplier_id="supplier-001",
    source_reference="commitment/commit-accounting",
    amount=@finance.Money::new(minor=10000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:create"),
  )
  let event = payable.to_opening_event(
    event_id="event-ap-opening",
    event_type="payable.opened",
    expense_account="6601",
    payable_account="2202",
  )
  assert_eq(event.source_type, "payable")
  assert_eq(event.journal.postings.length(), 2)
}

///|
test "payable payment creates a separate cash settlement event" {
  let payable = Payable::open(
    payable_id="pay-payment-accounting",
    principal_id="co-001",
    project_scope="project:p-001",
    supplier_id="supplier-001",
    source_reference="commitment/commit-payment",
    amount=@finance.Money::new(minor=10000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:create"),
  )
  let event = payable.to_payment_event(
    payment_id="payment-001",
    event_id="event-ap-payment",
    event_type="payable.paid",
    amount=@finance.Money::new(minor=4000, currency="CNY"),
    payable_account="2202",
    cash_account="1001",
  )
  assert_eq(event.source_type, "payable_payment")
  assert_eq(event.source_id, "payment-001")
  assert_eq(event.journal.postings[0].amount.minor, 4000L)
  assert_eq(event.journal.postings[1].amount.minor, 4000L)
  try
    payable.to_payment_event(
      payment_id="payment-too-large",
      event_id="event-ap-payment-too-large",
      event_type="payable.paid",
      amount=@finance.Money::new(minor=10001, currency="CNY"),
      payable_account="2202",
      cash_account="1001",
    )
  catch {
    PayableError::OverPayment => ()
    _ => fail("wrong payment event error")
  } noraise {
    _ => fail("expected payment event error")
  }
}

///|
test "payable payment persists an immutable projection" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let payable = Payable::open(
    payable_id="pay-projection",
    principal_id="co-001",
    project_scope="project:p-001",
    supplier_id="supplier-001",
    source_reference="commitment/commit-projection",
    amount=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:create"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="payable",
    aggregate_id="pay-projection",
  )
  let projection = payable.append_projection(projection)
  let paid = payable.record_payment(
    payment=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=payable_grant("payable:pay"),
  )
  let projection = paid.append_projection(projection)
  assert_eq(projection.revision, 2)
  match projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("paid"))
    None => fail("expected payable projection")
  }
}
