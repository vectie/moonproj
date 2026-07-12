///|
fn sql_test_record(
  record_id : String,
  source_id : String,
) -> @store.StoredRecord raise @store.StoreError {
  @store.StoredRecord::new(
    record_type="project",
    record_id~,
    schema_version=1,
    payload="{\"project_id\":\"" +
      record_id +
      "\",\"note\":\"a 'quoted' value\"}",
    source_id~,
  )
}

///|
test "SQL adapter emits parameterized inserts and commits once" {
  let adapter = SqlAdapter::new(initial_catalog())
  let command = adapter.prepare_insert(
    sql_test_record("p-sql-001", "erp:ep_project:p-sql-001"),
  )
  assert_true(command.sql.contains("VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"))
  assert_eq(command.params[1], "p-sql-001")
  assert_true(command.params[3].contains("'quoted'"))
  let transaction = adapter.prepare_batch([
    sql_test_record("p-sql-002", "erp:ep_project:p-sql-002"),
  ])
  let committed = transaction.commit()
  assert_true(committed.state is SqlTransactionState::Committed)
  try committed.commit() catch {
    SqlAdapterError::InvalidTransactionState => ()
    _ => fail("wrong transaction error")
  } noraise {
    _ => fail("expected transaction error")
  }
}

///|
test "SQL adapter rejects duplicate keys and sources before execution" {
  let adapter = SqlAdapter::new(initial_catalog())
  let first = sql_test_record("p-sql-003", "erp:ep_project:p-sql-003")
  let duplicate_key = sql_test_record(
    "p-sql-003", "erp:ep_project:p-sql-003-replay",
  )
  try adapter.prepare_batch([first, duplicate_key]) catch {
    SqlAdapterError::DuplicateRecord => ()
    _ => fail("wrong duplicate key error")
  } noraise {
    _ => fail("expected duplicate key error")
  }
  let duplicate_source = sql_test_record(
    "p-sql-004", "erp:ep_project:p-sql-004",
  )
  let duplicate_source_again = sql_test_record(
    "p-sql-005", "erp:ep_project:p-sql-004",
  )
  try adapter.prepare_batch([duplicate_source, duplicate_source_again]) catch {
    SqlAdapterError::DuplicateSource => ()
    _ => fail("wrong duplicate source error")
  } noraise {
    _ => fail("expected duplicate source error")
  }
}

///|
test "SQL adapter rollback is explicit and schema-bound" {
  let adapter = SqlAdapter::new(initial_catalog())
  let transaction = adapter.prepare_batch([
    sql_test_record("p-sql-006", "erp:ep_project:p-sql-006"),
  ])
  let rolled_back = transaction.rollback()
  assert_true(rolled_back.state is SqlTransactionState::RolledBack)
  try
    adapter.prepare_insert(
      @store.StoredRecord::new(
        record_type="project",
        record_id="p-sql-future",
        schema_version=2,
        payload="{\"project_id\":\"p-sql-future\"}",
        source_id="erp:ep_project:p-sql-future",
      ),
    )
  catch {
    SqlAdapterError::RecordAheadOfSchema => ()
    _ => fail("wrong schema error")
  } noraise {
    _ => fail("expected schema error")
  }
}

///|
test "reference SQL executor applies a prepared plan atomically" {
  let adapter = SqlAdapter::new(initial_catalog())
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let transaction = adapter.prepare_batch([
    sql_test_record("p-sql-exec", "erp:ep_project:p-sql-exec"),
  ])
  let (committed, next_store) = transaction.apply_to_store(store)
  assert_true(committed.state is SqlTransactionState::Committed)
  assert_eq(next_store.count_type(record_type="project"), 1)
  try committed.apply_to_store(next_store) catch {
    SqlAdapterError::InvalidTransactionState => ()
    _ => fail("wrong execution state error")
  } noraise {
    _ => fail("expected execution state error")
  }
}

///|
test "SQL transaction applies through the durable file boundary" {
  let adapter = SqlAdapter::new(initial_catalog())
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let path = "/tmp/moonproj-sql-durable.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  let durable = @store.DurableRecordStore::open(path, schema)
  let base = durable.snapshot().migrate(migration)
  base.save_snapshot(path)
  let durable = @store.DurableRecordStore::open(path, schema)
  let transaction = adapter.prepare_batch([
    sql_test_record("p-sql-durable", "erp:ep_project:p-sql-durable"),
  ])
  let (committed, next) = transaction.apply_to_durable_store(durable)
  assert_true(committed.state is SqlTransactionState::Committed)
  assert_eq(next.snapshot().count_type(record_type="project"), 1)
  let reopened = @store.DurableRecordStore::open(path, schema)
  assert_eq(reopened.snapshot().count_type(record_type="project"), 1)
  @fs.remove_file(path)
}

///|
test "company SQL adapter accepts the latest projection schema" {
  let adapter = SqlAdapter::new(company_catalog())
  let record = @store.StoredRecord::new(
    record_type="company/aggregate_projection",
    record_id="asset-001:r1",
    schema_version=4,
    payload="{\"aggregate_type\":\"asset\"}",
    source_id="company:asset:asset-001:r1",
  )
  let command = adapter.prepare_insert(record)
  assert_eq(command.params[2], "4")
}
