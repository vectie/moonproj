///|
/// Encode the store as deterministic JSON. This is a persistence contract, not
/// a database driver: a file or SQL adapter can transport this envelope while
/// keeping domain payloads opaque and schema-versioned.
pub fn RecordStore::to_snapshot(self : RecordStore) -> String {
  let records : Array[Json] = []
  for record in self.records {
    records.push(
      Json::object({
        "record_type": Json::string(record.record_type),
        "record_id": Json::string(record.record_id),
        "schema_version": Json::number(
          record.schema_version.to_double(),
          repr=record.schema_version.to_string(),
        ),
        "payload": Json::string(record.payload),
        "source_id": Json::string(record.source_id),
      }),
    )
  }
  Json::object({
    "schema": Json::object({
      "version": Json::number(
        self.schema.version.to_double(),
        repr=self.schema.version.to_string(),
      ),
      "checksum": Json::string(self.schema.checksum),
    }),
    "records": Json::array(records),
  }).stringify(indent=2)
}

///|
/// Restore a snapshot through the same constructor and append checks used by
/// live writes. A malformed or replayed snapshot therefore cannot bypass the
/// store's identity and schema invariants.
pub fn RecordStore::from_snapshot(
  snapshot : String,
) -> RecordStore raise StoreError {
  let root = @json.parse(snapshot) catch {
    _ => raise StoreError::InvalidSnapshot
  }
  let root = match root {
    Object(value) => value
    _ => raise StoreError::InvalidSnapshot
  }
  let schema_obj = match root.get("schema") {
    Some(Object(value)) => value
    _ => raise StoreError::InvalidSnapshot
  }
  let version = match schema_obj.get("version") {
    Some(Number(value, ..)) if value == value.trunc() => value.to_int()
    _ => raise StoreError::InvalidSnapshot
  }
  let checksum = match schema_obj.get("checksum") {
    Some(String(value)) if value.trim() != "" => value
    _ => raise StoreError::InvalidSnapshot
  }
  if version < 0 {
    raise StoreError::InvalidSnapshot
  }
  let rows = match root.get("records") {
    Some(Array(value)) => value
    _ => raise StoreError::InvalidSnapshot
  }
  let mut store = RecordStore::new({ version, checksum })
  for row in rows {
    let row = match row {
      Object(value) => value
      _ => raise StoreError::InvalidSnapshot
    }
    let record_type = match row.get("record_type") {
      Some(String(value)) => value
      _ => raise StoreError::InvalidSnapshot
    }
    let record_id = match row.get("record_id") {
      Some(String(value)) => value
      _ => raise StoreError::InvalidSnapshot
    }
    let schema_version = match row.get("schema_version") {
      Some(Number(value, ..)) =>
        if value == value.trunc() && value >= 0.0 {
          value.to_int()
        } else {
          raise StoreError::InvalidSnapshot
        }
      _ => raise StoreError::InvalidSnapshot
    }
    let payload = match row.get("payload") {
      Some(String(value)) => value
      _ => raise StoreError::InvalidSnapshot
    }
    let source_id = match row.get("source_id") {
      Some(String(value)) => value
      _ => raise StoreError::InvalidSnapshot
    }
    let record = StoredRecord::new(
      record_type~,
      record_id~,
      schema_version~,
      payload~,
      source_id~,
    ) catch {
      _ => raise StoreError::InvalidSnapshot
    }
    store = store.append(record) catch {
      _ => raise StoreError::InvalidSnapshot
    }
  }
  store
}
