///|
pub(all) enum MigrationReceiptState {
  Applied
  Certified
  RolledBack
} derive(Debug, Eq)

///|
/// A migration receipt retains both sides of an immutable apply. Keeping the
/// baseline makes rollback a verifiable operation instead of a metadata-only
/// state change.
pub(all) struct MigrationReceipt {
  manifest : @manifest.MigrationManifest
  baseline : @store.RecordStore
  applied : @store.RecordStore
  parity : @parity.ParitySummary?
  state : MigrationReceiptState
} derive(Debug, Eq)

///|
pub(all) suberror MigrationRunError {
  InvalidState
  IdentityMismatch
  ParityRequired
  ParityRejected
  RollbackConflict
  Manifest(@manifest.ManifestError)
} derive(Debug, Eq)

///|
pub fn MigrationReceipt::apply(
  manifest : @manifest.MigrationManifest,
  baseline : @store.RecordStore,
  records : Array[@store.StoredRecord],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationReceipt raise MigrationRunError {
  let (applied_manifest, applied) = manifest.apply_records(
    baseline,
    records,
    actor_id~,
    grant~,
  ) catch {
    error => raise MigrationRunError::Manifest(error)
  }
  {
    manifest: applied_manifest,
    baseline,
    applied,
    parity: None,
    state: MigrationReceiptState::Applied,
  }
}

///|
pub fn MigrationReceipt::record_parity(
  self : MigrationReceipt,
  report : @parity.ParityReport,
) -> MigrationReceipt raise MigrationRunError {
  if self.state == MigrationReceiptState::RolledBack {
    raise MigrationRunError::InvalidState
  }
  if report.run_id != self.manifest.run_id ||
    report.source_snapshot_id != self.manifest.source_snapshot_id {
    raise MigrationRunError::IdentityMismatch
  }
  { ..self, parity: Some(report.evaluate()) }
}

///|
pub fn MigrationReceipt::certify(
  self : MigrationReceipt,
) -> MigrationReceipt raise MigrationRunError {
  if self.state != MigrationReceiptState::Applied {
    raise MigrationRunError::InvalidState
  }
  let summary = match self.parity {
    Some(value) => value
    None => raise MigrationRunError::ParityRequired
  }
  if !summary.accepted {
    raise MigrationRunError::ParityRejected
  }
  { ..self, state: MigrationReceiptState::Certified }
}

///|
/// Roll back only if the current store is byte-for-byte equal to the applied
/// receipt. Any later write makes ownership ambiguous and fails closed.
pub fn MigrationReceipt::rollback(
  self : MigrationReceipt,
  current : @store.RecordStore,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (@store.RecordStore, MigrationReceipt) raise MigrationRunError {
  if self.state != MigrationReceiptState::Applied &&
    self.state != MigrationReceiptState::Certified {
    raise MigrationRunError::InvalidState
  }
  if current != self.applied {
    raise MigrationRunError::RollbackConflict
  }
  let manifest = self.manifest.rollback(actor_id~, grant~) catch {
    error => raise MigrationRunError::Manifest(error)
  }
  (
    self.baseline,
    { ..self, manifest, state: MigrationReceiptState::RolledBack },
  )
}
