///|
/// A parameterized statement emitted by the persistence boundary. Values are
/// kept out of `sql`; a concrete driver is responsible for binding `params`.
pub(all) struct SqlCommand {
  sql : String
  params : Array[String]
} derive(Debug, Eq)

///|
pub(all) enum SqlTransactionState {
  Prepared
  Committed
  RolledBack
} derive(Debug, Eq)

///|
/// A driver-neutral transaction plan. The plan can be committed or rolled
/// back exactly once; executing the commands is deliberately left to an
/// application-owned database adapter.
pub(all) struct SqlTransaction {
  commands : Array[SqlCommand]
  state : SqlTransactionState
} derive(Debug, Eq)

///|
/// SQL adapter metadata and the schema version it has validated.
pub(all) struct SqlAdapter {
  schema : @schema.SchemaState
  catalog : Array[SqlMigration]
} derive(Debug, Eq)

///|
pub(all) suberror SqlAdapterError {
  EmptyBatch
  DuplicateRecord
  DuplicateSource
  RecordAheadOfSchema
  InvalidTransactionState
  InvalidCommand
  Store(@store.StoreError)
  Durable(@store.DurableStoreError)
  Catalog(SqlCatalogError)
} derive(Debug, Eq)

///|
pub fn SqlAdapter::new(
  catalog : Array[SqlMigration],
) -> SqlAdapter raise SqlAdapterError {
  let schema = validate_catalog(@schema.SchemaState::initial(), catalog) catch {
    error => raise SqlAdapterError::Catalog(error)
  }
  { schema, catalog: catalog.copy() }
}

///|
fn insert_sql() -> String {
  "INSERT INTO company_record (record_type, record_id, schema_version, payload, source_id, created_at) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"
}

///|
fn insert_command(record : @store.StoredRecord) -> SqlCommand {
  {
    sql: insert_sql(),
    params: [
      record.record_type,
      record.record_id,
      record.schema_version.to_string(),
      record.payload,
      record.source_id,
    ],
  }
}

///|
pub fn SqlAdapter::prepare_insert(
  self : SqlAdapter,
  record : @store.StoredRecord,
) -> SqlCommand raise SqlAdapterError {
  if record.schema_version > self.schema.version {
    raise SqlAdapterError::RecordAheadOfSchema
  }
  insert_command(record)
}

///|
pub fn SqlAdapter::prepare_batch(
  self : SqlAdapter,
  records : Array[@store.StoredRecord],
) -> SqlTransaction raise SqlAdapterError {
  if records.length() == 0 {
    raise SqlAdapterError::EmptyBatch
  }
  let commands : Array[SqlCommand] = []
  let keys : Array[String] = []
  let sources : Array[String] = []
  for record in records {
    let _ = self.prepare_insert(record)
    let key = record.record_type + "\u{1f}" + record.record_id
    for existing in keys {
      if existing == key {
        raise SqlAdapterError::DuplicateRecord
      }
    }
    for existing in sources {
      if existing == record.source_id {
        raise SqlAdapterError::DuplicateSource
      }
    }
    keys.push(key)
    sources.push(record.source_id)
    commands.push(insert_command(record))
  }
  { commands, state: SqlTransactionState::Prepared }
}

///|
pub fn SqlTransaction::commit(
  self : SqlTransaction,
) -> SqlTransaction raise SqlAdapterError {
  if self.state != SqlTransactionState::Prepared {
    raise SqlAdapterError::InvalidTransactionState
  }
  { ..self, state: SqlTransactionState::Committed }
}

///|
pub fn SqlTransaction::rollback(
  self : SqlTransaction,
) -> SqlTransaction raise SqlAdapterError {
  if self.state != SqlTransactionState::Prepared {
    raise SqlAdapterError::InvalidTransactionState
  }
  { ..self, state: SqlTransactionState::RolledBack }
}

///|
fn command_record(
  command : SqlCommand,
) -> @store.StoredRecord raise SqlAdapterError {
  if command.sql != insert_sql() || command.params.length() != 5 {
    raise SqlAdapterError::InvalidCommand
  }
  let schema_version : Int = @string.from_str(command.params[2]) catch {
    _ => raise SqlAdapterError::InvalidCommand
  }
  @store.StoredRecord::new(
    record_type=command.params[0],
    record_id=command.params[1],
    schema_version~,
    payload=command.params[3],
    source_id=command.params[4],
  ) catch {
    error => raise SqlAdapterError::Store(error)
  }
}

///|
fn transaction_records(
  commands : Array[SqlCommand],
) -> Array[@store.StoredRecord] raise SqlAdapterError {
  let records : Array[@store.StoredRecord] = []
  for command in commands {
    records.push(command_record(command))
  }
  records
}

///|
/// Reference executor for tests and local migration rehearsals. A production
/// adapter can use the same command/transaction contract with a real database;
/// this implementation deliberately executes against the immutable store.
pub fn SqlTransaction::apply_to_store(
  self : SqlTransaction,
  store : @store.RecordStore,
) -> (SqlTransaction, @store.RecordStore) raise SqlAdapterError {
  if self.state != SqlTransactionState::Prepared {
    raise SqlAdapterError::InvalidTransactionState
  }
  let records = transaction_records(self.commands)
  let next_store = store.append_batch(records) catch {
    error => raise SqlAdapterError::Store(error)
  }
  ({ ..self, state: SqlTransactionState::Committed }, next_store)
}

///|
/// Apply the same prepared transaction to the durable file adapter. This is a
/// concrete crash-recoverable rehearsal path; a production SQL driver should
/// preserve the same command ordering and commit/rollback semantics.
pub fn SqlTransaction::apply_to_durable_store(
  self : SqlTransaction,
  durable : @store.DurableRecordStore,
) -> (SqlTransaction, @store.DurableRecordStore) raise SqlAdapterError {
  if self.state != SqlTransactionState::Prepared {
    raise SqlAdapterError::InvalidTransactionState
  }
  let records = transaction_records(self.commands)
  let next_durable = durable.transact(records) catch {
    error => raise SqlAdapterError::Durable(error)
  }
  ({ ..self, state: SqlTransactionState::Committed }, next_durable)
}
