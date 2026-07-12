///|
fn run_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-migration-run",
    principal_id: "co-001",
    actor_id: "migration",
    capability,
    scope: "erp-snapshot-run",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn run_manifest() -> @manifest.MigrationManifest {
  try! @manifest.MigrationManifest::new(
    run_id="run-receipt-001",
    source_snapshot_id="erp-snapshot-run",
    principal_id="co-001",
    actor_id="migration",
    grant=run_grant("migration:run:create"),
  )
  .add_item(
    {
      source_type: "ep_project",
      source_id: "p-receipt-001",
      target_type: "legacy/project",
      target_id: Some("p-receipt-001"),
      disposition: @manifest.MigrationDisposition::Imported,
      reason: "stable identity",
    },
    actor_id="migration",
    grant=run_grant("migration:item:add"),
  )
  .validate(actor_id="migration", grant=run_grant("migration:run:validate"))
}

///|
fn run_baseline() -> @store.RecordStore {
  let schema = @schema.SchemaState::initial()
  let migration = try! @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  try! @store.RecordStore::new(schema).migrate(migration)
}

///|
fn run_record() -> @store.StoredRecord {
  try! @store.StoredRecord::new(
    record_type="legacy/project",
    record_id="p-receipt-001",
    schema_version=1,
    payload="{\"proj_guid\":\"p-receipt-001\"}",
    source_id="erp:ep_project:p-receipt-001",
  )
}

///|
test "migration receipt certifies parity and rolls back the unchanged apply" {
  let receipt = MigrationReceipt::apply(
    run_manifest(),
    run_baseline(),
    [run_record()],
    actor_id="migration",
    grant=run_grant("migration:run:apply"),
  )
  let report = @parity.ParityReport::new(
    run_id="run-receipt-001",
    source_snapshot_id="erp-snapshot-run",
  ).add_metric({
    metric_id: "project-count",
    domain: "project",
    dimension: "company:co-001",
    source_value: 1L,
    target_value: 1L,
    tolerance: 0L,
  })
  let receipt = receipt.record_parity(report).certify()
  assert_true(receipt.state is MigrationReceiptState::Certified)
  let (restored, rolled_back) = receipt.rollback(
    receipt.applied,
    actor_id="migration",
    grant=run_grant("migration:run:rollback"),
  )
  assert_eq(restored.records.length(), 0)
  assert_true(rolled_back.state is MigrationReceiptState::RolledBack)
}

///|
test "migration receipt fails closed on parity and rollback conflicts" {
  let receipt = MigrationReceipt::apply(
    run_manifest(),
    run_baseline(),
    [run_record()],
    actor_id="migration",
    grant=run_grant("migration:run:apply"),
  )
  try receipt.certify() catch {
    MigrationRunError::ParityRequired => ()
    _ => fail("wrong parity error")
  } noraise {
    _ => fail("expected parity requirement")
  }
  let changed = receipt.applied.append(
    @store.StoredRecord::new(
      record_type="legacy/project",
      record_id="p-later",
      schema_version=1,
      payload="{\"proj_guid\":\"p-later\"}",
      source_id="erp:ep_project:p-later",
    ),
  )
  try
    receipt.rollback(
      changed,
      actor_id="migration",
      grant=run_grant("migration:run:rollback"),
    )
  catch {
    MigrationRunError::RollbackConflict => ()
    _ => fail("wrong rollback error")
  } noraise {
    _ => fail("expected rollback conflict")
  }
}
