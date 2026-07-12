///|
fn receivable_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "receivable-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "customer:customer-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "receivable tracks partial and complete collection" {
  let receivable = Receivable::open(
    receivable_id="ar-001",
    source_id="sale-001",
    principal_id="co-001",
    customer_id="customer-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=receivable_grant("receivable:open"),
  )
  let partial = receivable.collect(
    amount_minor=40000,
    actor_id="alice",
    grant=receivable_grant("receivable:collect"),
  )
  let collected = partial.collect(
    amount_minor=50000,
    actor_id="alice",
    grant=receivable_grant("receivable:collect"),
  )
  assert_eq(partial.outstanding_minor(), 50000)
  assert_true(collected.state == ReceivableState::Collected)
  assert_eq(collected.outstanding_minor(), 0)
}

///|
test "receivable rejects over-collection" {
  let receivable = Receivable::open(
    receivable_id="ar-002",
    source_id="sale-002",
    principal_id="co-001",
    customer_id="customer-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=receivable_grant("receivable:open"),
  )
  try
    receivable.collect(
      amount_minor=90001,
      actor_id="alice",
      grant=receivable_grant("receivable:collect"),
    )
  catch {
    ReceivableError::OverCollection => ()
    _ => fail("wrong receivable error")
  } noraise {
    _ => fail("expected receivable error")
  }
}

///|
test "receivable opening creates a source accounting event" {
  let receivable = Receivable::open(
    receivable_id="ar-accounting",
    source_id="sale-001",
    principal_id="co-001",
    customer_id="customer-001",
    amount=@finance.Money::new(minor=10000, currency="CNY"),
    actor_id="alice",
    grant=receivable_grant("receivable:open"),
  )
  let event = receivable.to_opening_event(
    event_id="event-ar-opening",
    event_type="receivable.opened",
    receivable_account="1122",
    revenue_account="6001",
  )
  assert_eq(event.source_type, "receivable")
  assert_eq(event.journal.postings.length(), 2)
}

///|
test "receivable collection persists an immutable projection" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let receivable = Receivable::open(
    receivable_id="ar-projection",
    source_id="sale-projection",
    principal_id="co-001",
    customer_id="customer-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=receivable_grant("receivable:open"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="receivable",
    aggregate_id="ar-projection",
  )
  let projection = receivable.append_projection(projection)
  let collected = receivable.collect(
    amount_minor=90000,
    actor_id="alice",
    grant=receivable_grant("receivable:collect"),
  )
  let projection = collected.append_projection(projection)
  assert_eq(projection.revision, 2)
  match projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("collected"))
    None => fail("expected receivable projection")
  }
}
