///|
fn procurement_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-procurement",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn active_supplier() -> Supplier raise SupplierError {
  let supplier = Supplier::new(
    supplier_id="supplier-001",
    principal_id="co-001",
    scope="project:p-001",
    supplier_code="SUP-001",
    name="Qualified Supplier",
    category_code="construction",
    actor_id="alice",
    grant=procurement_grant("supplier:create"),
  ).submit_review(actor_id="alice", grant=procurement_grant("supplier:submit"))
  supplier.review(
    evaluation=SupplierEvaluation::Qualified,
    actor_id="alice",
    grant=procurement_grant("supplier:review"),
  )
}

///|
test "supplier qualification gates tender award" {
  let supplier = active_supplier()
  let tender = TenderPlan::new(
      tender_id="tender-001",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Foundation works",
      category="construction",
      estimated_amount=@finance.Money::new(minor=500000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:create"),
    )
    .publish(actor_id="alice", grant=procurement_grant("tender:publish"))
    .open_bidding(actor_id="alice", grant=procurement_grant("tender:open"))
    .add_bid(
      supplier,
      amount=@finance.Money::new(minor=480000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:bid"),
    )
    .award(supplier, actor_id="alice", grant=procurement_grant("tender:award"))
  assert_true(tender.state == TenderState::Awarded)
  assert_true(tender.awarded_supplier_id == Some("supplier-001"))
  assert_eq(tender.awarded_amount.unwrap().minor, 480000L)
}

///|
test "tender rejects an unqualified supplier" {
  let supplier = Supplier::new(
    supplier_id="supplier-002",
    principal_id="co-001",
    scope="project:p-001",
    supplier_code="SUP-002",
    name="Unreviewed Supplier",
    category_code="construction",
    actor_id="alice",
    grant=procurement_grant("supplier:create"),
  )
  let tender = TenderPlan::new(
      tender_id="tender-002",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Electrical works",
      category="construction",
      estimated_amount=@finance.Money::new(minor=100000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:create"),
    )
    .publish(actor_id="alice", grant=procurement_grant("tender:publish"))
    .open_bidding(actor_id="alice", grant=procurement_grant("tender:open"))
  try
    tender.add_bid(
      supplier,
      amount=@finance.Money::new(minor=90000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:bid"),
    )
  catch {
    TenderError::SupplierNotEligible => ()
    _ => fail("wrong tender error")
  } noraise {
    _ => fail("expected tender error")
  }
}

///|
test "supplier and tender state persist as revisioned projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let supplier = active_supplier()
  let supplier_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="supplier",
    aggregate_id="supplier-001",
  )
  let supplier_projection = supplier.append_projection(supplier_projection)
  let tender = TenderPlan::new(
      tender_id="tender-projection",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Foundation works",
      category="construction",
      estimated_amount=@finance.Money::new(minor=500000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:create"),
    )
    .publish(actor_id="alice", grant=procurement_grant("tender:publish"))
    .open_bidding(actor_id="alice", grant=procurement_grant("tender:open"))
    .add_bid(
      supplier,
      amount=@finance.Money::new(minor=480000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:bid"),
    )
    .award(supplier, actor_id="alice", grant=procurement_grant("tender:award"))
  let tender_projection = @store.AggregateProjection::new(
    supplier_projection.into_store(),
    aggregate_type="tender",
    aggregate_id="tender-projection",
  )
  let tender_projection = tender.append_projection(tender_projection)
  assert_eq(tender_projection.revision, 1)
  match tender_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("awarded"))
      assert_true(latest.payload.contains("supplier-001"))
    }
    None => fail("expected tender projection")
  }
}

///|
test "supplier void preserves an explicit lifecycle event" {
  let supplier = active_supplier()
  let voided = supplier.void_supplier(
    actor_id="alice",
    grant=procurement_grant("supplier:void"),
  )
  assert_true(voided.state == SupplierState::Voided)
  assert_eq(voided.events.length(), supplier.events.length() + 1)
  let event = voided.events[voided.events.length() - 1]
  assert_eq(event.capability, "supplier:void")
  assert_true(event.to == SupplierState::Voided)
}

///|
test "awarded tender creates a commitment through two authority gates" {
  let supplier = active_supplier()
  let tender = TenderPlan::new(
      tender_id="tender-commitment",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Foundation works",
      category="construction",
      estimated_amount=@finance.Money::new(minor=500000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:create"),
    )
    .publish(actor_id="alice", grant=procurement_grant("tender:publish"))
    .open_bidding(actor_id="alice", grant=procurement_grant("tender:open"))
    .add_bid(
      supplier,
      amount=@finance.Money::new(minor=480000, currency="CNY"),
      actor_id="alice",
      grant=procurement_grant("tender:bid"),
    )
    .award(supplier, actor_id="alice", grant=procurement_grant("tender:award"))
  let commitment = tender.create_commitment(
    commitment_id="commitment-from-tender",
    actor_id="alice",
    award_grant=procurement_grant("tender:award-to-commitment"),
    commitment_grant=procurement_grant("commitment:create"),
  )
  assert_true(commitment.state == @commitment.CommitmentState::Draft)
  assert_eq(commitment.counterparty_id, "supplier-001")
  assert_eq(commitment.amount.minor, 480000L)
}

///|
test "unawarded tender cannot create a commitment" {
  let supplier = active_supplier()
  let tender = TenderPlan::new(
    tender_id="tender-no-award",
    principal_id="co-001",
    project_scope="project:p-001",
    name="No award",
    category="construction",
    estimated_amount=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=procurement_grant("tender:create"),
  ).publish(actor_id="alice", grant=procurement_grant("tender:publish"))
  try
    tender.create_commitment(
      commitment_id="commitment-invalid",
      actor_id="alice",
      award_grant=procurement_grant("tender:award-to-commitment"),
      commitment_grant=procurement_grant("commitment:create"),
    )
  catch {
    TenderError::InvalidState => ()
    _ => fail("wrong tender error")
  } noraise {
    _ => fail("expected award gate")
  }
  // Keep the supplier binding in the fixture so the test also exercises the
  // qualified-supplier path before the state rejection.
  assert_eq(supplier.supplier_id, "supplier-001")
}
