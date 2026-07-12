///|
/// Append a migration batch atomically from the caller's perspective. Because
/// `RecordStore` is immutable, a failed append returns an error without
/// exposing any of the intermediate records; SQL adapters must preserve this
/// all-or-nothing behavior in their transaction implementation.
pub fn RecordStore::append_batch(
  self : RecordStore,
  records : Array[StoredRecord],
) -> RecordStore raise StoreError {
  if records.length() == 0 {
    raise StoreError::EmptyBatch
  }
  let mut next = self
  for record in records {
    next = next.append(record)
  }
  next
}
