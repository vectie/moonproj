///|
pub(all) suberror SqliteDriverSmokeError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SqliteDriverSmokeError {
  SqliteDriverSmokeError::InvalidInput(message)
}

///|
fn schema_sql() -> String {
  "PRAGMA foreign_keys=ON;\n" +
  "PRAGMA busy_timeout=30000;\n" +
  "PRAGMA journal_mode=WAL;\n" +
  "CREATE TABLE IF NOT EXISTS company_schema(version INTEGER NOT NULL PRIMARY KEY, checksum VARCHAR(255) NOT NULL, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);\n" +
  "CREATE TABLE IF NOT EXISTS company_record(record_type VARCHAR(128) NOT NULL, record_id VARCHAR(255) NOT NULL, schema_version INTEGER NOT NULL, payload TEXT NOT NULL, source_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(record_type, record_id), UNIQUE(source_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_record_source_idx ON company_record(source_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_aggregate_projection(aggregate_type VARCHAR(128) NOT NULL, aggregate_id VARCHAR(255) NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, source_event_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(aggregate_type, aggregate_id, revision), UNIQUE(aggregate_type, aggregate_id, source_event_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_projection_event_idx ON company_aggregate_projection(source_event_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_accounting_event_link(event_id VARCHAR(255) NOT NULL PRIMARY KEY, source_type VARCHAR(128) NOT NULL, source_id VARCHAR(255) NOT NULL, journal_id VARCHAR(255) NOT NULL, principal_id VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(source_type, source_id), UNIQUE(journal_id));\n" +
  "CREATE INDEX IF NOT EXISTS company_accounting_source_idx ON company_accounting_event_link(source_type, source_id);\n" +
  "CREATE TABLE IF NOT EXISTS company_migration_receipt(run_id VARCHAR(255) NOT NULL PRIMARY KEY, source_snapshot_id VARCHAR(255) NOT NULL, target_schema_version INTEGER NOT NULL, mapping_version VARCHAR(255) NOT NULL, state VARCHAR(32) NOT NULL, baseline_hash VARCHAR(255) NOT NULL, applied_hash VARCHAR(255) NOT NULL, certified_at TIMESTAMP);\n" +
  "CREATE INDEX IF NOT EXISTS company_receipt_snapshot_idx ON company_migration_receipt(source_snapshot_id);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 1,'sha256:company-record-envelope-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=1);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 2,'sha256:aggregate-projection-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=2);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 3,'sha256:accounting-event-link-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=3);\n" +
  "INSERT INTO company_schema(version, checksum) SELECT 4,'sha256:migration-receipt-v1' WHERE NOT EXISTS(SELECT 1 FROM company_schema WHERE version=4);\n"
}

///|
fn insert_sql(record_id : String, source_id : String) -> String {
  "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id, created_at) VALUES('driver_smoke', '" +
  record_id +
  "', 4, '{}', '" +
  source_id +
  "', CURRENT_TIMESTAMP);\n"
}

///|
fn duplicate_insert_sql() -> String {
  "INSERT OR ROLLBACK INTO company_record(record_type, record_id, schema_version, payload, source_id, created_at) VALUES('driver_smoke', 'duplicate', 4, '{}', 'smoke:duplicate', CURRENT_TIMESTAMP);\n"
}

///|
fn write_file(
  path : String,
  content : String,
) -> Unit raise SqliteDriverSmokeError {
  @fs.write_string_to_file(path, content) catch {
    error => raise SqliteDriverSmokeError::Io(error)
  }
}

///|
fn prepare(work_dir : String) -> Unit raise SqliteDriverSmokeError {
  write_file(work_dir + "/schema.sql", schema_sql())
  write_file(
    work_dir + "/rollback.sql",
    "BEGIN IMMEDIATE;\n" +
    insert_sql("rollback", "smoke:rollback") +
    "ROLLBACK;\n",
  )
  write_file(
    work_dir + "/duplicate.sql",
    "BEGIN IMMEDIATE;\n" +
    insert_sql("duplicate", "smoke:duplicate") +
    duplicate_insert_sql() +
    "COMMIT;\n",
  )
  write_file(
    work_dir + "/commit.sql",
    "BEGIN IMMEDIATE;\n" +
    insert_sql("committed", "smoke:committed") +
    "COMMIT;\n",
  )
}

///|
fn parse_int(value : String) -> Int raise SqliteDriverSmokeError {
  let source = value.trim().to_owned()
  if source.is_empty() {
    raise fail("expected integer")
  }
  let mut result = 0
  for char in source.iter() {
    if char < '0' || char > '9' {
      raise fail("invalid integer: " + value)
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  result
}

///|
fn report(
  database : String,
  count : Int,
  integrity : String,
  duplicate_count : Int,
  output : String,
) -> Unit raise SqliteDriverSmokeError {
  if count != 1 || duplicate_count != 0 || integrity != "ok" {
    raise fail("driver smoke verification failed")
  }
  let report = Json::object({
    "database": Json::string(database),
    "state": Json::string("driver_transaction_verified"),
    "rolled_back_rows": Json::number(0, repr="0"),
    "committed_rows": Json::number(count.to_double(), repr=count.to_string()),
    "sql_command_verified": Json::boolean(true),
    "duplicate_rejected": Json::boolean(true),
    "integrity": Json::string(integrity),
  })
  write_file(output, report.stringify(indent=2) + "\n")
  println(report.stringify())
}

///|
fn run(args : Array[String]) -> Unit raise SqliteDriverSmokeError {
  if args.length() < 2 {
    raise fail("usage: sqlite_driver_smoke <prepare|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 3 => prepare(args[2])
    "report" if args.length() >= 7 =>
      report(args[2], parse_int(args[3]), args[4], parse_int(args[5]), args[6])
    _ => raise fail("invalid sqlite driver smoke arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteDriverSmokeError::InvalidInput(message) => {
      println("company SQLite driver smoke failed: " + message)
      @sys.exit(1)
    }
    SqliteDriverSmokeError::Io(_) => {
      println("company SQLite driver smoke failed: filesystem error")
      @sys.exit(1)
    }
  }
}
