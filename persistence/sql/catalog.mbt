///|
/// A SQL migration statement is kept separate from the domain record types.
/// The Moonproj production adapter executes this SQL on PostgreSQL while
/// preserving the version/checksum chain. ERP MySQL is source-only and is not
/// a target backend for this product.
pub(all) struct SqlMigration {
  step : @schema.MigrationStep
  up_sql : String
  down_sql : String
} derive(Debug, Eq)

///|
pub(all) suberror SqlCatalogError {
  EmptySql
  InvalidDownMigration
  Schema(@schema.MigrationError)
} derive(Debug, Eq)

///|
pub fn SqlMigration::new(
  step : @schema.MigrationStep,
  up_sql~ : String,
  down_sql~ : String,
) -> SqlMigration raise SqlCatalogError {
  if up_sql.trim() == "" {
    raise SqlCatalogError::EmptySql
  }
  if down_sql.trim() == "" {
    raise SqlCatalogError::InvalidDownMigration
  }
  { step, up_sql, down_sql }
}

///|
pub fn initial_catalog() -> Array[SqlMigration] {
  [
    try! SqlMigration::new(
      @schema.MigrationStep::new(
        version=1,
        migration_id="V1__company_record_envelope",
        checksum="sha256:company-record-envelope-v1",
        description="Create schema ledger and append-only company record envelope",
      ),
      up_sql="CREATE TABLE company_schema (\n" +
        "  version INTEGER NOT NULL,\n" +
        "  checksum VARCHAR(255) NOT NULL,\n" +
        "  applied_at TIMESTAMP NOT NULL,\n" +
        "  PRIMARY KEY (version)\n" +
        ");\n" +
        "CREATE TABLE company_record (\n" +
        "  record_type VARCHAR(128) NOT NULL,\n" +
        "  record_id VARCHAR(255) NOT NULL,\n" +
        "  schema_version INTEGER NOT NULL,\n" +
        "  payload TEXT NOT NULL,\n" +
        "  source_id VARCHAR(255) NOT NULL,\n" +
        "  created_at TIMESTAMP NOT NULL,\n" +
        "  PRIMARY KEY (record_type, record_id),\n" +
        "  UNIQUE (source_id)\n" +
        ");\n" +
        "CREATE INDEX company_record_source_idx ON company_record(source_id);\n",
      down_sql="DROP INDEX company_record_source_idx;\n" +
        "DROP TABLE company_record;\n" +
        "DROP TABLE company_schema;\n",
    ),
  ]
}

///|
/// The production-oriented catalog extends the generic envelope with the
/// durable aggregate, accounting-link, and migration-receipt tables required
/// by the cutover protocol. A concrete database driver may translate this DDL,
/// but must preserve the version/checksum chain.
pub fn company_catalog() -> Array[SqlMigration] {
  let migrations = initial_catalog()
  migrations.push(
    try! SqlMigration::new(
      @schema.MigrationStep::new(
        version=2,
        migration_id="V2__aggregate_projection",
        checksum="sha256:aggregate-projection-v1",
        description="Create immutable aggregate projection revisions",
      ),
      up_sql="CREATE TABLE company_aggregate_projection (\n" +
        "  aggregate_type VARCHAR(128) NOT NULL,\n" +
        "  aggregate_id VARCHAR(255) NOT NULL,\n" +
        "  revision INTEGER NOT NULL,\n" +
        "  payload TEXT NOT NULL,\n" +
        "  source_event_id VARCHAR(255) NOT NULL,\n" +
        "  created_at TIMESTAMP NOT NULL,\n" +
        "  PRIMARY KEY (aggregate_type, aggregate_id, revision),\n" +
        "  UNIQUE (aggregate_type, aggregate_id, source_event_id)\n" +
        ");\n" +
        "CREATE INDEX company_projection_event_idx ON company_aggregate_projection(source_event_id);\n",
      down_sql="DROP INDEX company_projection_event_idx;\n" +
        "DROP TABLE company_aggregate_projection;\n",
    ),
  )
  migrations.push(
    try! SqlMigration::new(
      @schema.MigrationStep::new(
        version=3,
        migration_id="V3__accounting_event_link",
        checksum="sha256:accounting-event-link-v1",
        description="Create source-to-journal accounting event links",
      ),
      up_sql="CREATE TABLE company_accounting_event_link (\n" +
        "  event_id VARCHAR(255) NOT NULL,\n" +
        "  source_type VARCHAR(128) NOT NULL,\n" +
        "  source_id VARCHAR(255) NOT NULL,\n" +
        "  journal_id VARCHAR(255) NOT NULL,\n" +
        "  principal_id VARCHAR(255) NOT NULL,\n" +
        "  created_at TIMESTAMP NOT NULL,\n" +
        "  PRIMARY KEY (event_id),\n" +
        "  UNIQUE (source_type, source_id),\n" +
        "  UNIQUE (journal_id)\n" +
        ");\n" +
        "CREATE INDEX company_accounting_source_idx ON company_accounting_event_link(source_type, source_id);\n",
      down_sql="DROP INDEX company_accounting_source_idx;\n" +
        "DROP TABLE company_accounting_event_link;\n",
    ),
  )
  migrations.push(
    try! SqlMigration::new(
      @schema.MigrationStep::new(
        version=4,
        migration_id="V4__migration_receipt",
        checksum="sha256:migration-receipt-v1",
        description="Create immutable migration receipt controls",
      ),
      up_sql="CREATE TABLE company_migration_receipt (\n" +
        "  run_id VARCHAR(255) NOT NULL,\n" +
        "  source_snapshot_id VARCHAR(255) NOT NULL,\n" +
        "  target_schema_version INTEGER NOT NULL,\n" +
        "  mapping_version VARCHAR(255) NOT NULL,\n" +
        "  state VARCHAR(32) NOT NULL,\n" +
        "  baseline_hash VARCHAR(255) NOT NULL,\n" +
        "  applied_hash VARCHAR(255) NOT NULL,\n" +
        "  certified_at TIMESTAMP,\n" +
        "  PRIMARY KEY (run_id)\n" +
        ");\n" +
        "CREATE INDEX company_receipt_snapshot_idx ON company_migration_receipt(source_snapshot_id);\n",
      down_sql="DROP INDEX company_receipt_snapshot_idx;\n" +
        "DROP TABLE company_migration_receipt;\n",
    ),
  )
  migrations
}

///|
pub fn validate_catalog(
  current : @schema.SchemaState,
  migrations : Array[SqlMigration],
) -> @schema.SchemaState raise SqlCatalogError {
  let steps : Array[@schema.MigrationStep] = []
  for migration in migrations {
    steps.push(migration.step)
  }
  @schema.validate_chain(current, steps) catch {
    error => raise SqlCatalogError::Schema(error)
  }
}
