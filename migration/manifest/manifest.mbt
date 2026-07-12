///|
pub(all) enum MigrationDisposition {
  Imported
  Quarantined
  Skipped
} derive(Debug, Eq)

///|
pub(all) enum MigrationRunState {
  Planned
  Validated
  Applied
  RolledBack
} derive(Debug, Eq)

///|
pub(all) struct MigrationItem {
  source_type : String
  source_id : String
  target_type : String
  target_id : String?
  disposition : MigrationDisposition
  reason : String
} derive(Debug, Eq)

///|
pub(all) struct MigrationManifest {
  run_id : String
  source_snapshot_id : String
  principal_id : String
  items : Array[MigrationItem]
  state : MigrationRunState
} derive(Debug, Eq)

///|
pub(all) suberror ManifestError {
  EmptyIdentifier
  DuplicateSource
  InvalidDisposition
  InvalidState
  QuarantineReasonRequired
  MissingTarget
  RecordCountMismatch
  RecordTargetMismatch
  NotAuthorized(@foundation.AuthorityError)
  Store(@store.StoreError)
} derive(Debug, Eq)

///|
pub fn MigrationManifest::new(
  run_id~ : String,
  source_snapshot_id~ : String,
  principal_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationManifest raise ManifestError {
  if run_id.trim() == "" ||
    source_snapshot_id.trim() == "" ||
    principal_id.trim() == "" {
    raise ManifestError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="migration:run:create",
    scope=source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  {
    run_id,
    source_snapshot_id,
    principal_id,
    items: [],
    state: MigrationRunState::Planned,
  }
}

///|
pub fn MigrationManifest::add_item(
  self : MigrationManifest,
  item : MigrationItem,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationManifest raise ManifestError {
  if self.state != MigrationRunState::Planned {
    raise ManifestError::InvalidState
  }
  if item.source_type.trim() == "" ||
    item.source_id.trim() == "" ||
    item.target_type.trim() == "" {
    raise ManifestError::EmptyIdentifier
  }
  match item.disposition {
    MigrationDisposition::Imported => {
      match item.target_id {
        Some(target_id) if target_id.trim() != "" => ()
        _ => raise ManifestError::MissingTarget
      }
      if item.reason.trim() == "" {
        raise ManifestError::InvalidDisposition
      }
    }
    MigrationDisposition::Quarantined =>
      if item.reason.trim() == "" {
        raise ManifestError::QuarantineReasonRequired
      }
    MigrationDisposition::Skipped =>
      if item.reason.trim() == "" {
        raise ManifestError::InvalidDisposition
      }
  }
  for existing in self.items {
    if existing.source_type == item.source_type &&
      existing.source_id == item.source_id {
      raise ManifestError::DuplicateSource
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="migration:item:add",
    scope=self.source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  let items = self.items.copy()
  items.push(item)
  { ..self, items, }
}

///|
pub fn MigrationManifest::validate(
  self : MigrationManifest,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationManifest raise ManifestError {
  if self.state != MigrationRunState::Planned || self.items.length() == 0 {
    raise ManifestError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="migration:run:validate",
    scope=self.source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  { ..self, state: MigrationRunState::Validated }
}

///|
pub fn MigrationManifest::apply(
  self : MigrationManifest,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationManifest raise ManifestError {
  if self.state != MigrationRunState::Validated {
    raise ManifestError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="migration:run:apply",
    scope=self.source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  { ..self, state: MigrationRunState::Applied }
}

///|
/// Apply imported envelopes and the manifest state in one immutable operation.
/// Target identity checks happen before the store batch is appended, so a
/// mismatch or duplicate leaves both the manifest and store unchanged.
pub fn MigrationManifest::apply_records(
  self : MigrationManifest,
  store : @store.RecordStore,
  records : Array[@store.StoredRecord],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> (MigrationManifest, @store.RecordStore) raise ManifestError {
  if self.state != MigrationRunState::Validated {
    raise ManifestError::InvalidState
  }
  if self.count(MigrationDisposition::Imported) != records.length() {
    raise ManifestError::RecordCountMismatch
  }
  for record in records {
    let mut matched = false
    for item in self.items {
      match item.target_id {
        Some(target_id) if item.disposition == MigrationDisposition::Imported &&
          item.target_type == record.record_type &&
          target_id == record.record_id &&
          (
            record.source_id == item.source_id ||
            record.source_id == "erp:" + item.source_type + ":" + item.source_id
          ) => matched = true
        _ => ()
      }
    }
    if !matched {
      raise ManifestError::RecordTargetMismatch
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="migration:run:apply",
    scope=self.source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  let next_store = if records.length() == 0 {
    store
  } else {
    store.append_batch(records) catch {
      error => raise ManifestError::Store(error)
    }
  }
  ({ ..self, state: MigrationRunState::Applied }, next_store)
}

///|
pub fn MigrationManifest::rollback(
  self : MigrationManifest,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MigrationManifest raise ManifestError {
  if self.state != MigrationRunState::Applied {
    raise ManifestError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="migration:run:rollback",
    scope=self.source_snapshot_id,
    amount_minor=0,
  ) catch {
    error => raise ManifestError::NotAuthorized(error)
  }
  { ..self, state: MigrationRunState::RolledBack }
}

///|
pub fn MigrationManifest::count(
  self : MigrationManifest,
  disposition : MigrationDisposition,
) -> Int {
  let mut count = 0
  for item in self.items {
    if item.disposition == disposition {
      count += 1
    }
  }
  count
}
