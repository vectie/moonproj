///|
/// A file-backed store with a pending snapshot journal. The pending file is
/// written before the live path and is preferred during reopen, so a process
/// interrupted between those writes can recover the fully validated candidate.
/// A production database adapter must still provide its own atomic commit and
/// durability guarantees.
pub(all) struct DurableRecordStore {
  path : String
  pending_path : String
  store : RecordStore
} derive(Debug, Eq)

///|
pub(all) suberror DurableStoreError {
  FileIo
  InvalidPendingSnapshot
  Store(StoreError)
} derive(Debug, Eq)

///|
fn durable_pending_path(path : String) -> String {
  path + ".pending"
}

///|
pub fn DurableRecordStore::open(
  path : String,
  schema : @schema.SchemaState,
) -> DurableRecordStore raise DurableStoreError {
  let pending = durable_pending_path(path)
  if @fs.path_exists(pending) {
    let store = load_snapshot(pending) catch {
      _ => raise DurableStoreError::InvalidPendingSnapshot
    }
    return { path, pending_path: pending, store }
  }
  if @fs.path_exists(path) {
    let store = load_snapshot(path) catch {
      error => raise DurableStoreError::Store(error)
    }
    return { path, pending_path: pending, store }
  }
  { path, pending_path: pending, store: RecordStore::new(schema) }
}

///|
pub fn DurableRecordStore::snapshot(self : DurableRecordStore) -> RecordStore {
  self.store
}

///|
/// Append a batch and persist the complete candidate. The in-memory value is
/// returned only after the pending snapshot and live snapshot have both been
/// written successfully; a failed write leaves the previous value in memory
/// and the pending candidate available for recovery on reopen.
pub fn DurableRecordStore::transact(
  self : DurableRecordStore,
  records : Array[StoredRecord],
) -> DurableRecordStore raise DurableStoreError {
  let candidate = self.store.append_batch(records) catch {
    error => raise DurableStoreError::Store(error)
  }
  candidate.save_snapshot(self.pending_path) catch {
    error => raise DurableStoreError::Store(error)
  }
  candidate.save_snapshot(self.path) catch {
    error => raise DurableStoreError::Store(error)
  }
  if @fs.path_exists(self.pending_path) {
    @fs.remove_file(self.pending_path) catch {
      _ => raise DurableStoreError::FileIo
    }
  }
  { ..self, store: candidate }
}
