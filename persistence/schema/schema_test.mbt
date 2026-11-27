///|
test "schema migrations are forward-only and sequential" {
  let first = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let second = @schema.MigrationStep::new(
    version=2,
    migration_id="V2__finance",
    checksum="sha256:two",
    description="Create finance tables",
  )
  let state = @schema.validate_chain(@schema.SchemaState::initial(), [
    first, second,
  ])
  assert_eq(state.version, 2)
  assert_eq(state.checksum, "sha256:two")
}

///|
test "schema migrations reject a skipped version" {
  let skipped = @schema.MigrationStep::new(
    version=2,
    migration_id="V2__skipped",
    checksum="sha256:skip",
    description="Invalid gap",
  )
  try @schema.apply_migration(@schema.SchemaState::initial(), skipped) catch {
    @schema.MigrationError::NonSequential => ()
    _ => fail("wrong migration error")
  } noraise {
    _ => fail("expected migration error")
  }
}

///|
test "schema migrations reject replay" {
  let first = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let state = @schema.apply_migration(@schema.SchemaState::initial(), first)
  try @schema.apply_migration(state, first) catch {
    @schema.MigrationError::AlreadyApplied => ()
    _ => fail("wrong migration error")
  } noraise {
    _ => fail("expected migration error")
  }
}
