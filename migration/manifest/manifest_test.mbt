///|
fn manifest_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-manifest",
    principal_id: "co-001",
    actor_id: "migration",
    capability,
    scope: "erp-snapshot-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "migration manifest validates, applies, and rolls back" {
  let manifest = MigrationManifest::new(
      run_id="run-001",
      source_snapshot_id="erp-snapshot-001",
      principal_id="co-001",
      actor_id="migration",
      grant=manifest_grant("migration:run:create"),
    )
    .add_item(
      {
        source_type: "ep_project",
        source_id: "p-001",
        target_type: "project",
        target_id: Some("p-001"),
        disposition: MigrationDisposition::Imported,
        reason: "mapped by stable identifier",
      },
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
    .add_item(
      {
        source_type: "cb_cost",
        source_id: "cost-001",
        target_type: "cost",
        target_id: None,
        disposition: MigrationDisposition::Quarantined,
        reason: "currency missing",
      },
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
    .validate(
      actor_id="migration",
      grant=manifest_grant("migration:run:validate"),
    )
    .apply(actor_id="migration", grant=manifest_grant("migration:run:apply"))
    .rollback(
      actor_id="migration",
      grant=manifest_grant("migration:run:rollback"),
    )
  assert_true(manifest.state == MigrationRunState::RolledBack)
  assert_eq(manifest.count(MigrationDisposition::Imported), 1)
  assert_eq(manifest.count(MigrationDisposition::Quarantined), 1)
}

///|
test "migration manifest rejects duplicate source identity" {
  let manifest = MigrationManifest::new(
    run_id="run-002",
    source_snapshot_id="erp-snapshot-001",
    principal_id="co-001",
    actor_id="migration",
    grant=manifest_grant("migration:run:create"),
  )
  let item : MigrationItem = {
    source_type: "ep_project",
    source_id: "p-001",
    target_type: "project",
    target_id: Some("p-001"),
    disposition: MigrationDisposition::Imported,
    reason: "mapped",
  }
  let manifest = manifest.add_item(
    item,
    actor_id="migration",
    grant=manifest_grant("migration:item:add"),
  )
  try
    manifest.add_item(
      item,
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
  catch {
    ManifestError::DuplicateSource => ()
    _ => fail("wrong manifest error")
  } noraise {
    _ => fail("expected manifest error")
  }
}

///|
test "migration manifest requires quarantine reasons" {
  try
    MigrationManifest::new(
      run_id="run-003",
      source_snapshot_id="erp-snapshot-001",
      principal_id="co-001",
      actor_id="migration",
      grant=manifest_grant("migration:run:create"),
    ).add_item(
      {
        source_type: "invoice_out",
        source_id: "invoice-003",
        target_type: "invoice",
        target_id: None,
        disposition: MigrationDisposition::Quarantined,
        reason: "",
      },
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
  catch {
    ManifestError::QuarantineReasonRequired => ()
    _ => fail("wrong manifest error")
  } noraise {
    _ => fail("expected manifest error")
  }
}

///|
test "validated manifest applies matching envelopes atomically" {
  let manifest = MigrationManifest::new(
      run_id="run-004",
      source_snapshot_id="erp-snapshot-001",
      principal_id="co-001",
      actor_id="migration",
      grant=manifest_grant("migration:run:create"),
    )
    .add_item(
      {
        source_type: "ep_project",
        source_id: "p-004",
        target_type: "legacy/project",
        target_id: Some("p-004"),
        disposition: MigrationDisposition::Imported,
        reason: "stable identity",
      },
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
    .validate(
      actor_id="migration",
      grant=manifest_grant("migration:run:validate"),
    )
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let record = @store.StoredRecord::new(
    record_type="legacy/project",
    record_id="p-004",
    schema_version=1,
    payload="{\"proj_guid\":\"p-004\"}",
    source_id="erp:ep_project:p-004",
  )
  let (applied, store) = manifest.apply_records(
    store,
    [record],
    actor_id="migration",
    grant=manifest_grant("migration:run:apply"),
  )
  assert_true(applied.state == MigrationRunState::Applied)
  assert_eq(store.count_type(record_type="legacy/project"), 1)
}

///|
test "manifest rejects a target mismatch without changing the store" {
  let manifest = MigrationManifest::new(
      run_id="run-005",
      source_snapshot_id="erp-snapshot-001",
      principal_id="co-001",
      actor_id="migration",
      grant=manifest_grant("migration:run:create"),
    )
    .add_item(
      {
        source_type: "ep_project",
        source_id: "p-005",
        target_type: "legacy/project",
        target_id: Some("p-005"),
        disposition: MigrationDisposition::Imported,
        reason: "stable identity",
      },
      actor_id="migration",
      grant=manifest_grant("migration:item:add"),
    )
    .validate(
      actor_id="migration",
      grant=manifest_grant("migration:run:validate"),
    )
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let wrong = @store.StoredRecord::new(
    record_type="legacy/project",
    record_id="p-other",
    schema_version=1,
    payload="{\"proj_guid\":\"p-other\"}",
    source_id="erp:ep_project:p-other",
  )
  try
    manifest.apply_records(
      store,
      [wrong],
      actor_id="migration",
      grant=manifest_grant("migration:run:apply"),
    )
  catch {
    ManifestError::RecordTargetMismatch => ()
    _ => fail("wrong manifest error")
  } noraise {
    _ => fail("expected target mismatch")
  }
  assert_eq(store.count_type(record_type="legacy/project"), 0)
}
