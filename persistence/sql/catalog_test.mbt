///|
test "SQL catalog validates the generic record envelope migration" {
  let migrations = initial_catalog()
  let state = validate_catalog(@schema.SchemaState::initial(), migrations)
  assert_eq(state.version, 1)
  assert_eq(state.checksum, "sha256:company-record-envelope-v1")
  assert_true(migrations[0].up_sql.contains("CREATE TABLE company_record"))
  assert_true(migrations[0].up_sql.contains("UNIQUE (source_id)"))
}

///|
test "SQL catalog rejects a migration without rollback SQL" {
  try
    SqlMigration::new(
      @schema.MigrationStep::new(
        version=1,
        migration_id="V1__bad",
        checksum="sha256:bad",
        description="bad",
      ),
      up_sql="CREATE TABLE bad_table (id INTEGER);",
      down_sql="",
    )
  catch {
    SqlCatalogError::InvalidDownMigration => ()
    _ => fail("wrong SQL catalog error")
  } noraise {
    _ => fail("expected SQL catalog error")
  }
}

///|
test "company SQL catalog includes projection, accounting, and receipt gates" {
  let migrations = company_catalog()
  let state = validate_catalog(@schema.SchemaState::initial(), migrations)
  assert_eq(state.version, 4)
  assert_eq(state.checksum, "sha256:migration-receipt-v1")
  assert_true(migrations[1].up_sql.contains("company_aggregate_projection"))
  assert_true(migrations[2].up_sql.contains("company_accounting_event_link"))
  assert_true(migrations[3].up_sql.contains("company_migration_receipt"))
  assert_true(migrations[3].down_sql.contains("DROP TABLE"))
}
