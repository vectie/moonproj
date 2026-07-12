///|
/// A persistence-neutral record envelope. `payload` is owned by a domain
/// serializer; this package deliberately does not choose JSON, SQL, or files.
pub(all) struct StoredRecord {
  record_type : String
  record_id : String
  schema_version : Int
  payload : String
  source_id : String
} derive(Debug, Eq)

///|
pub(all) struct RecordStore {
  schema : @schema.SchemaState
  records : Array[StoredRecord]
} derive(Debug, Eq)

///|
pub(all) suberror StoreError {
  EmptyRecordType
  EmptyRecordId
  EmptySourceId
  InvalidSchemaVersion
  EmptyPayload
  DuplicateRecord
  DuplicateSource
  InvalidSnapshot
  FileIo
  EmptyBatch
  Schema(@schema.MigrationError)
} derive(Debug, Eq)

///|
pub fn StoredRecord::new(
  record_type~ : String,
  record_id~ : String,
  schema_version~ : Int,
  payload~ : String,
  source_id~ : String,
) -> StoredRecord raise StoreError {
  if record_type.trim() == "" {
    raise StoreError::EmptyRecordType
  }
  if record_id.trim() == "" {
    raise StoreError::EmptyRecordId
  }
  if source_id.trim() == "" {
    raise StoreError::EmptySourceId
  }
  if schema_version <= 0 {
    raise StoreError::InvalidSchemaVersion
  }
  if payload.trim() == "" {
    raise StoreError::EmptyPayload
  }
  { record_type, record_id, schema_version, payload, source_id }
}

///|
pub fn RecordStore::new(schema : @schema.SchemaState) -> RecordStore {
  { schema, records: [] }
}

///|
pub fn RecordStore::append(
  self : RecordStore,
  record : StoredRecord,
) -> RecordStore raise StoreError {
  if record.schema_version > self.schema.version {
    raise StoreError::InvalidSchemaVersion
  }
  for existing in self.records {
    if existing.record_type == record.record_type &&
      existing.record_id == record.record_id {
      raise StoreError::DuplicateRecord
    }
    if existing.source_id == record.source_id {
      raise StoreError::DuplicateSource
    }
  }
  let records = self.records.copy()
  records.push(record)
  { ..self, records, }
}

///|
pub fn RecordStore::get(
  self : RecordStore,
  record_type~ : String,
  record_id~ : String,
) -> StoredRecord? {
  for record in self.records {
    if record.record_type == record_type && record.record_id == record_id {
      return Some(record)
    }
  }
  None
}

///|
pub fn RecordStore::count_type(
  self : RecordStore,
  record_type~ : String,
) -> Int {
  let mut count = 0
  for record in self.records {
    if record.record_type == record_type {
      count += 1
    }
  }
  count
}

///|
pub fn RecordStore::migrate(
  self : RecordStore,
  migration : @schema.MigrationStep,
) -> RecordStore raise StoreError {
  let schema = @schema.apply_migration(self.schema, migration) catch {
    error => raise StoreError::Schema(error)
  }
  { ..self, schema, }
}
