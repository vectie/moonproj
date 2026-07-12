///|
fn invoice_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "invoice-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "customer:customer-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "invoice distinguishes acceptance from payment" {
  let invoice = Invoice::new(
    invoice_id="invoice-001",
    principal_id="co-001",
    customer_id="customer-001",
    source_id="sale-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=invoice_grant("invoice:create"),
  )
  let issued = invoice.transition(
    InvoiceState::Issued,
    actor_id="alice",
    grant=invoice_grant("invoice:issue"),
  )
  let accepted = issued.transition(
    InvoiceState::Accepted,
    actor_id="alice",
    grant=invoice_grant("invoice:accept"),
  )
  let partial = accepted.record_payment(
    amount_minor=40000,
    actor_id="alice",
    grant=invoice_grant("invoice:collect"),
  )
  let paid = partial.record_payment(
    amount_minor=50000,
    actor_id="alice",
    grant=invoice_grant("invoice:collect"),
  )
  assert_true(partial.state == InvoiceState::PartiallyPaid)
  assert_true(paid.state == InvoiceState::Paid)
  assert_eq(paid.outstanding_minor(), 0)
}

///|
test "invoice rejects payment before acceptance and overpayment" {
  let invoice = Invoice::new(
    invoice_id="invoice-002",
    principal_id="co-001",
    customer_id="customer-001",
    source_id="sale-002",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=invoice_grant("invoice:create"),
  )
  try
    invoice.record_payment(
      amount_minor=1,
      actor_id="alice",
      grant=invoice_grant("invoice:collect"),
    )
  catch {
    InvoiceError::InvalidState => ()
    _ => fail("wrong invoice error")
  } noraise {
    _ => fail("expected invoice error")
  }
  let accepted = try! invoice.transition(
    InvoiceState::Issued,
    actor_id="alice",
    grant=invoice_grant("invoice:issue"),
  )
  let accepted = try! accepted.transition(
    InvoiceState::Accepted,
    actor_id="alice",
    grant=invoice_grant("invoice:accept"),
  )
  try
    accepted.record_payment(
      amount_minor=90001,
      actor_id="alice",
      grant=invoice_grant("invoice:collect"),
    )
  catch {
    InvoiceError::Overpayment => ()
    _ => fail("wrong overpayment error")
  } noraise {
    _ => fail("expected overpayment error")
  }
}

///|
test "accepted invoice opens a receivable through a separate gate" {
  let invoice = Invoice::new(
    invoice_id="invoice-receivable-001",
    principal_id="co-001",
    customer_id="customer-001",
    source_id="sale-receivable-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=invoice_grant("invoice:create"),
  )
  let accepted = invoice
    .transition(
      InvoiceState::Issued,
      actor_id="alice",
      grant=invoice_grant("invoice:issue"),
    )
    .transition(
      InvoiceState::Accepted,
      actor_id="alice",
      grant=invoice_grant("invoice:accept"),
    )
  let receivable = accepted.open_receivable(
    receivable_id="receivable-invoice-001",
    actor_id="alice",
    invoice_grant=invoice_grant("invoice:receivable-open"),
    receivable_grant={
      grant_id: "receivable-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "receivable:open",
      scope: "customer:customer-001",
      max_amount_minor: 100000,
      active: true,
    },
  )
  assert_true(receivable.state == @receivable.ReceivableState::Open)
  assert_eq(receivable.source_id, "invoice-receivable-001")
  assert_eq(receivable.outstanding_minor(), 90000L)
}

///|
test "invoice and receivable retain separate durable source projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let invoice = Invoice::new(
    invoice_id="invoice-receivable-projection",
    principal_id="co-001",
    customer_id="customer-001",
    source_id="sale-receivable-projection",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=invoice_grant("invoice:create"),
  )
  let accepted = invoice
    .transition(
      InvoiceState::Issued,
      actor_id="alice",
      grant=invoice_grant("invoice:issue"),
    )
    .transition(
      InvoiceState::Accepted,
      actor_id="alice",
      grant=invoice_grant("invoice:accept"),
    )
  let receivable = accepted.open_receivable(
    receivable_id="receivable-invoice-projection",
    actor_id="alice",
    invoice_grant=invoice_grant("invoice:receivable-open"),
    receivable_grant={
      grant_id: "receivable-projection-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "receivable:open",
      scope: "customer:customer-001",
      max_amount_minor: 100000,
      active: true,
    },
  )
  let invoice_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="invoice",
    aggregate_id="invoice-receivable-projection",
  )
  let invoice_projection = accepted.append_projection(invoice_projection)
  let receivable_projection = @store.AggregateProjection::new(
    invoice_projection.into_store(),
    aggregate_type="receivable",
    aggregate_id="receivable-invoice-projection",
  )
  let receivable_projection = receivable.append_projection(
    receivable_projection,
  )
  match receivable_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("invoice-receivable-projection"))
      assert_true(latest.payload.contains("source_id"))
    }
    None => fail("expected receivable projection")
  }
}

///|
test "invoice acceptance and payment persist projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let invoice = Invoice::new(
    invoice_id="invoice-projection",
    principal_id="co-001",
    customer_id="customer-001",
    source_id="sale-projection",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=invoice_grant("invoice:create"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="invoice",
    aggregate_id="invoice-projection",
  )
  let projection = invoice.append_projection(projection)
  let accepted = invoice
    .transition(
      InvoiceState::Issued,
      actor_id="alice",
      grant=invoice_grant("invoice:issue"),
    )
    .transition(
      InvoiceState::Accepted,
      actor_id="alice",
      grant=invoice_grant("invoice:accept"),
    )
  let paid = accepted.record_payment(
    amount_minor=90000,
    actor_id="alice",
    grant=invoice_grant("invoice:collect"),
  )
  let projection = paid.append_projection(projection)
  assert_eq(projection.revision, 2)
  match projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("paid"))
    None => fail("expected invoice projection")
  }
}
