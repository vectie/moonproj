///|
/// Write a complete store snapshot. The file adapter is intentionally thin:
/// atomic replacement, encryption, and database transactions belong to the
/// deployment adapter, while snapshot contents remain governed here.
pub fn RecordStore::save_snapshot(
  self : RecordStore,
  path : String,
) -> Unit raise StoreError {
  @fs.write_string_to_file(path, self.to_snapshot()) catch {
    _ => raise StoreError::FileIo
  }
}

///|
pub fn load_snapshot(path : String) -> RecordStore raise StoreError {
  let snapshot = @fs.read_file_to_string(path) catch {
    _ => raise StoreError::FileIo
  }
  RecordStore::from_snapshot(snapshot)
}

///|
/// Validate and copy a snapshot into a backup location. The source is parsed
/// before writing so malformed state cannot become the recovery artifact.
pub fn backup_snapshot(
  source_path : String,
  backup_path : String,
) -> Unit raise StoreError {
  let store = load_snapshot(source_path)
  @fs.write_string_to_file(backup_path, store.to_snapshot()) catch {
    _ => raise StoreError::FileIo
  }
}

///|
/// Validate a backup and restore it to a target path. This remains a file
/// adapter; production SQL adapters must provide the same validation boundary
/// inside a transaction and prove their own physical backup semantics.
pub fn restore_snapshot(
  backup_path : String,
  target_path : String,
) -> Unit raise StoreError {
  let store = load_snapshot(backup_path)
  @fs.write_string_to_file(target_path, store.to_snapshot()) catch {
    _ => raise StoreError::FileIo
  }
}
