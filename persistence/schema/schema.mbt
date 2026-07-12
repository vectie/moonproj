///|
/// A versioned, immutable description of the database schema.
pub(all) struct SchemaState {
  version : Int
  checksum : String
} derive(Debug, Eq)

///|
/// A single forward-only migration step.
pub(all) struct MigrationStep {
  version : Int
  migration_id : String
  checksum : String
  description : String
} derive(Debug, Eq)

///|
pub(all) suberror MigrationError {
  InvalidVersion
  EmptyMigrationId
  EmptyChecksum
  EmptyDescription
  NonSequential
  AlreadyApplied
} derive(Debug, Eq)

///|
pub fn SchemaState::initial() -> SchemaState {
  { version: 0, checksum: "genesis" }
}

///|
pub fn MigrationStep::new(
  version~ : Int,
  migration_id~ : String,
  checksum~ : String,
  description~ : String,
) -> MigrationStep raise MigrationError {
  if version <= 0 {
    raise MigrationError::InvalidVersion
  }
  if migration_id.trim() == "" {
    raise MigrationError::EmptyMigrationId
  }
  if checksum.trim() == "" {
    raise MigrationError::EmptyChecksum
  }
  if description.trim() == "" {
    raise MigrationError::EmptyDescription
  }
  { version, migration_id, checksum, description }
}

///|
pub fn apply_migration(
  current : SchemaState,
  migration : MigrationStep,
) -> SchemaState raise MigrationError {
  if migration.version <= current.version {
    raise MigrationError::AlreadyApplied
  }
  if migration.version != current.version + 1 {
    raise MigrationError::NonSequential
  }
  { version: migration.version, checksum: migration.checksum }
}

///|
pub fn validate_chain(
  current : SchemaState,
  migrations : Array[MigrationStep],
) -> SchemaState raise MigrationError {
  let mut state = current
  for migration in migrations {
    state = apply_migration(state, migration)
  }
  state
}
