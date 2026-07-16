///|
pub(all) suberror SqliteBackupRestoreError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SqliteBackupRestoreError {
  SqliteBackupRestoreError::InvalidInput(message)
}

///|
fn write_file(
  path : String,
  content : String,
) -> Unit raise SqliteBackupRestoreError {
  @fs.write_string_to_file(path, content) catch {
    error => raise SqliteBackupRestoreError::Io(error)
  }
}

///|
fn prepare(work_dir : String) -> Unit raise SqliteBackupRestoreError {
  let sql = "SELECT 'company_schema';\n" +
    "SELECT json_array(version, checksum, applied_at) FROM company_schema ORDER BY rowid;\n" +
    "SELECT 'company_record';\n" +
    "SELECT json_array(record_type, record_id, schema_version, payload, source_id, created_at) FROM company_record ORDER BY rowid;\n" +
    "SELECT 'company_aggregate_projection';\n" +
    "SELECT json_array(aggregate_type, aggregate_id, revision, payload, source_event_id, created_at) FROM company_aggregate_projection ORDER BY rowid;\n" +
    "SELECT 'company_accounting_event_link';\n" +
    "SELECT json_array(event_id, source_type, source_id, journal_id, principal_id, created_at) FROM company_accounting_event_link ORDER BY rowid;\n" +
    "SELECT 'company_migration_receipt';\n" +
    "SELECT json_array(run_id, source_snapshot_id, target_schema_version, mapping_version, state, baseline_hash, applied_hash, certified_at) FROM company_migration_receipt ORDER BY rowid;\n"
  write_file(work_dir + "/logical-dump.sql", sql)
}

///|
fn read_json(path : String) -> Json raise SqliteBackupRestoreError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SqliteBackupRestoreError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot parse summary: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SqliteBackupRestoreError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object: " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise SqliteBackupRestoreError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("summary has no " + key + ": " + path)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise SqliteBackupRestoreError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise fail("summary has invalid " + key + ": " + path)
  }
}

///|
fn canonical(value : Json) -> String {
  match value {
    Null => "null"
    True => "true"
    False => "false"
    String(text) => Json::string(text).stringify()
    Number(number, repr~) =>
      match repr {
        Some(repr) => Json::number(number, repr~).stringify()
        None => Json::number(number).stringify()
      }
    Array(values) => "[" + values.map(canonical).join(",") + "]"
    Object(fields) => {
      let keys = fields.keys().to_array()
      keys.sort_by(fn(left, right) { left.lexical_compare(right) })
      "{" +
      keys
      .map(fn(key) {
        Json::string(key).stringify() +
        ":" +
        canonical(fields.get(key).unwrap())
      })
      .join(",") +
      "}"
    }
  }
}

///|
fn digest(path : String) -> String raise SqliteBackupRestoreError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    error => raise SqliteBackupRestoreError::Io(error)
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn report(
  source : String,
  backup : String,
  source_rows_path : String,
  backup_rows_path : String,
  source_summary_path : String,
  backup_summary_path : String,
  output : String,
) -> Unit raise SqliteBackupRestoreError {
  let source_summary = read_json(source_summary_path)
  let backup_summary = read_json(backup_summary_path)
  let source_fields = object(source_summary, source_summary_path)
  let backup_fields = object(backup_summary, backup_summary_path)
  let source_integrity = required_string(
    source_fields, "integrity", source_summary_path,
  )
  let backup_integrity = required_string(
    backup_fields, "integrity", backup_summary_path,
  )
  if source_integrity != "ok" || backup_integrity != "ok" {
    raise fail("source or restored database failed integrity check")
  }
  if canonical(source_summary) != canonical(backup_summary) {
    raise fail("backup/restore parity mismatch")
  }
  let source_digest = digest(source_rows_path)
  let backup_digest = digest(backup_rows_path)
  if source_digest != backup_digest {
    raise fail("backup/restore logical digest mismatch")
  }
  source_fields.set("logical_digest", Json::string(source_digest))
  backup_fields.set("logical_digest", Json::string(backup_digest))
  let source_summary_with_digest = Json::object(source_fields)
  let backup_summary_with_digest = Json::object(backup_fields)
  let result = Json::object({
    "source": Json::string(source),
    "backup": Json::string(backup),
    "state": Json::string("backup_restore_verified"),
    "source_summary": source_summary_with_digest,
    "restored_summary": backup_summary_with_digest,
  })
  write_file(output, result.stringify(indent=2) + "\n")
  println(result.stringify())
}

///|
fn run(args : Array[String]) -> Unit raise SqliteBackupRestoreError {
  if args.length() < 2 {
    raise fail("usage: sqlite_backup_restore <prepare|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 3 => prepare(args[2])
    "report" if args.length() >= 9 =>
      report(args[2], args[3], args[4], args[5], args[6], args[7], args[8])
    _ => raise fail("invalid sqlite backup/restore arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    SqliteBackupRestoreError::InvalidInput(message) => {
      println("company SQLite backup/restore failed: " + message)
      @sys.exit(1)
    }
    SqliteBackupRestoreError::Io(_) => {
      println("company SQLite backup/restore failed: filesystem error")
      @sys.exit(1)
    }
  }
}
