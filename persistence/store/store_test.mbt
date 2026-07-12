///|
test "record store appends and reads typed envelopes" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = RecordStore::new(schema).migrate(migration)
  let record = StoredRecord::new(
    record_type="legal_entity",
    record_id="co-001",
    schema_version=1,
    payload="{\"entity_id\":\"co-001\"}",
    source_id="erp:mu_business_unit:co-001",
  )
  let store = store.append(record)
  assert_eq(store.count_type(record_type="legal_entity"), 1)
  assert_true(
    store.get(record_type="legal_entity", record_id="co-001") is Some(_),
  )
}

///|
test "record store rejects duplicate source identities" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = RecordStore::new(schema).migrate(migration)
  let record = StoredRecord::new(
    record_type="project",
    record_id="p-001",
    schema_version=1,
    payload="{\"project_id\":\"p-001\"}",
    source_id="erp:ep_project:p-001",
  )
  let store = store.append(record)
  try store.append(record) catch {
    StoreError::DuplicateRecord => ()
    _ => fail("wrong store error")
  } noraise {
    _ => fail("expected duplicate error")
  }
  let different_record = StoredRecord::new(
    record_type="project",
    record_id="p-002",
    schema_version=1,
    payload="{\"project_id\":\"p-002\"}",
    source_id="erp:ep_project:p-001",
  )
  try store.append(different_record) catch {
    StoreError::DuplicateSource => ()
    _ => fail("wrong source error")
  } noraise {
    _ => fail("expected source error")
  }
}

///|
test "record store snapshots round trip without changing envelopes" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let record = StoredRecord::new(
    record_type="project",
    record_id="p-001",
    schema_version=1,
    payload="{\"project_id\":\"p-001\"}",
    source_id="erp:ep_project:p-001",
  )
  let store = RecordStore::new(schema).migrate(migration).append(record)
  let restored = RecordStore::from_snapshot(store.to_snapshot())
  assert_eq(restored.schema.version, 1)
  assert_eq(restored.schema.checksum, "sha256:one")
  assert_true(restored.records == store.records)
}

///|
test "record store rejects malformed snapshots" {
  try RecordStore::from_snapshot("{\"schema\":{}}") catch {
    StoreError::InvalidSnapshot => ()
    _ => fail("wrong snapshot error")
  } noraise {
    _ => fail("expected snapshot error")
  }
}

///|
test "record store file adapter round trips a snapshot" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let record = StoredRecord::new(
    record_type="project",
    record_id="p-file",
    schema_version=1,
    payload="{\"project_id\":\"p-file\"}",
    source_id="erp:ep_project:p-file",
  )
  let store = RecordStore::new(schema).migrate(migration).append(record)
  let path = "/tmp/moonproj-record-store-snapshot.json"
  store.save_snapshot(path)
  let restored = load_snapshot(path)
  assert_true(restored.records == store.records)
  @fs.remove_file(path)
}

///|
test "record store batch append is all or nothing on duplicate" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = RecordStore::new(schema).migrate(migration)
  let first = StoredRecord::new(
    record_type="project",
    record_id="p-batch-001",
    schema_version=1,
    payload="{\"project_id\":\"p-batch-001\"}",
    source_id="erp:ep_project:p-batch-001",
  )
  let duplicate = StoredRecord::new(
    record_type="project",
    record_id="p-batch-001",
    schema_version=1,
    payload="{\"project_id\":\"p-batch-001\",\"changed\":true}",
    source_id="erp:ep_project:p-batch-001-replay",
  )
  try store.append_batch([first, duplicate]) catch {
    StoreError::DuplicateRecord => ()
    _ => fail("wrong batch error")
  } noraise {
    _ => fail("expected batch error")
  }
  assert_eq(store.count_type(record_type="project"), 0)
}

///|
test "record store rejects an empty migration batch" {
  let store = RecordStore::new(@schema.SchemaState::initial())
  try store.append_batch([]) catch {
    StoreError::EmptyBatch => ()
    _ => fail("wrong batch error")
  } noraise {
    _ => fail("expected batch error")
  }
}

///|
test "record store backup and restore validates the recovery path" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let record = StoredRecord::new(
    record_type="project",
    record_id="p-recovery",
    schema_version=1,
    payload="{\"project_id\":\"p-recovery\"}",
    source_id="erp:ep_project:p-recovery",
  )
  let store = RecordStore::new(schema).migrate(migration).append(record)
  let source = "/tmp/moonproj-recovery-source.json"
  let backup = "/tmp/moonproj-recovery-backup.json"
  let restored_path = "/tmp/moonproj-recovery-restored.json"
  store.save_snapshot(source)
  backup_snapshot(source, backup)
  restore_snapshot(backup, restored_path)
  let restored = load_snapshot(restored_path)
  assert_true(restored.records == store.records)
  @fs.remove_file(source)
  @fs.remove_file(backup)
  @fs.remove_file(restored_path)
}

///|
test "record store backup rejects a malformed source" {
  let source = "/tmp/moonproj-recovery-bad.json"
  let backup = "/tmp/moonproj-recovery-bad-backup.json"
  @fs.write_string_to_file(source, "{\"schema\":{}}")
  try backup_snapshot(source, backup) catch {
    StoreError::InvalidSnapshot => ()
    _ => fail("wrong recovery error")
  } noraise {
    _ => fail("expected recovery error")
  }
  @fs.remove_file(source)
  if @fs.path_exists(backup) {
    @fs.remove_file(backup)
  }
}

///|
test "durable record store persists and reopens a committed batch" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let path = "/tmp/moonproj-durable-record-store.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  if @fs.path_exists(path + ".pending") {
    @fs.remove_file(path + ".pending")
  }
  RecordStore::new(schema).migrate(migration).save_snapshot(path)
  let durable = DurableRecordStore::open(path, schema).transact([
    StoredRecord::new(
      record_type="project",
      record_id="p-durable",
      schema_version=1,
      payload="{\"project_id\":\"p-durable\"}",
      source_id="erp:ep_project:p-durable",
    ),
  ])
  assert_eq(durable.snapshot().records.length(), 1)
  assert_true(!@fs.path_exists(path + ".pending"))
  @fs.remove_file(path)
}

///|
test "durable record store recovers a validated pending snapshot" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let base = RecordStore::new(schema).migrate(migration)
  let record = StoredRecord::new(
    record_type="project",
    record_id="p-pending",
    schema_version=1,
    payload="{\"project_id\":\"p-pending\"}",
    source_id="erp:ep_project:p-pending",
  )
  let path = "/tmp/moonproj-durable-pending.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  if @fs.path_exists(path + ".pending") {
    @fs.remove_file(path + ".pending")
  }
  base.append(record).save_snapshot(path + ".pending")
  let reopened = DurableRecordStore::open(path, schema)
  assert_eq(reopened.snapshot().records.length(), 1)
  @fs.remove_file(path + ".pending")
}

///|
test "aggregate projection enforces revisions and survives snapshot restore" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = RecordStore::new(schema).migrate(migration)
  let projection = AggregateProjection::new(
    store,
    aggregate_type="commitment",
    aggregate_id="c-001",
  )
  let projection = projection.append(
    expected_revision=1,
    payload="{\"state\":\"approved\"}",
    source_event_id="commitment:c-001:approved",
  )
  let projection = projection.append(
    expected_revision=2,
    payload="{\"state\":\"performed\"}",
    source_event_id="commitment:c-001:performed",
  )
  match projection.latest() {
    Some(latest) => {
      assert_eq(latest.revision, 2)
      assert_eq(latest.payload, "{\"state\":\"performed\"}")
    }
    None => fail("expected latest projection")
  }
  try
    projection.append(
      expected_revision=4,
      payload="{\"state\":\"settled\"}",
      source_event_id="commitment:c-001:settled",
    )
  catch {
    ProjectionError::RevisionConflict => ()
    _ => fail("wrong revision error")
  } noraise {
    _ => fail("expected revision error")
  }
  let restored = RecordStore::from_snapshot(
    projection.into_store().to_snapshot(),
  )
  let reopened = AggregateProjection::new(
    restored,
    aggregate_type="commitment",
    aggregate_id="c-001",
  )
  assert_eq(reopened.revision, 2)
}
