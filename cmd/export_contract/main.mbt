///|
/// MoonBit implementation of the credential-free ERP export contract.
///
/// This command is intentionally source/database agnostic: it validates the
/// redacted JSON envelope on disk, never opens the ERP database, and never
/// authorizes promotion or cutover.
pub(all) suberror ExportContractError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ExportContractError {
  ExportContractError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ExportContractError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ExportContractError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ExportContractError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ExportContractError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ExportContractError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise fail("expected string at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ExportContractError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise ExportContractError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn is_identifier(value : String) -> Bool {
  if value.is_empty() {
    false
  } else {
    value
    .iter()
    .all(fn(c) { c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' })
  }
}

///|
fn is_sha256(value : String) -> Bool {
  value.length() == 64 && value.iter().all(fn(c) { c.is_ascii_hexdigit() })
}

///|
fn contains_secret_marker(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.has_suffix("ip")
}

///|
fn contains_dsn(value : String) -> Bool {
  let lowered = value.to_lower()
  lowered.contains("postgres://") ||
  lowered.contains("postgresql://") ||
  lowered.contains("mysql://")
}

///|
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise ExportContractError {
  match value {
    Object(fields) =>
      fields.each((key, child) => {
        if contains_secret_marker(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      })
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    String(text) if contains_dsn(text) =>
      raise fail("raw database DSN at " + path)
    _ => ()
  }
}

///|
fn sha256_file(path : String) -> String raise ExportContractError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    error => raise ExportContractError::Io(error)
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn schema_tables(path : String) -> Array[String] raise ExportContractError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise ExportContractError::Io(error)
  }
  let marker = "CREATE TABLE IF NOT EXISTS "
  let tables : Array[String] = []
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    match line.find(marker) {
      Some(start) => {
        let tail = line.sub(start=start + marker.length())
        match tail.before(" ") {
          Some(name_view) => {
            let name = name_view.to_owned()
            if !is_identifier(name) {
              raise fail("unsafe schema table name: " + name)
            }
            if !tables.contains(name) {
              tables.push(name)
            }
          }
          None => raise fail("schema table has no name")
        }
      }
      None => ()
    }
  }
  if tables.is_empty() {
    raise fail("schema initializer has no table definitions")
  }
  tables
}

///|
fn json_rows(
  value : Json,
  table : String,
) -> Array[Json] raise ExportContractError {
  match value {
    Array(rows) => rows
    _ => raise fail("export table is not an array: " + table)
  }
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  values.any(fn(item) { item == value })
}

///|
fn json_strings(values : Array[String]) -> Array[Json] {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  encoded
}

///|
fn validate(
  schema_path : String,
  export_dir : String,
) -> Json raise ExportContractError {
  let manifest_path = export_dir + "/manifest.json"
  let manifest = object(read_json(manifest_path), "manifest")
  let manifest_format = required_string(manifest, "format", "manifest")
  if manifest_format != "moonproj.erp.snapshot.v1" &&
    manifest_format != "moonproj.erp.full-export.v1" {
    raise fail("unsupported export manifest format")
  }
  let source_hash = required_string(manifest, "source_sha256", "manifest")
  if !is_sha256(source_hash) {
    raise fail("export manifest has no valid source_sha256")
  }
  if required_string(manifest, "redaction", "manifest").trim().is_empty() {
    raise fail("export manifest has no redaction declaration")
  }
  let entries = required_array(manifest, "tables", "manifest")
  if entries.is_empty() {
    raise fail("export manifest tables must be a non-empty array")
  }
  let expected = schema_tables(schema_path)
  let seen : Array[String] = []
  let mut verified_rows = 0
  let mut verified_files = 0
  let table_reports : Array[Json] = []
  for index in 0..<entries.length() {
    let entry_path = "manifest.tables[" + index.to_string() + "]"
    let entry = object(entries[index], entry_path)
    let table = required_string(entry, "table", entry_path)
    if !is_identifier(table) {
      raise fail("unsafe or missing table name: " + table)
    }
    if contains_string(seen, table) {
      raise fail("duplicate table entry: " + table)
    }
    seen.push(table)
    let relative = required_string(entry, "file", entry_path)
    let expected_relative = "tables/" + table + ".json"
    if relative != expected_relative {
      raise fail("table path does not match table name: " + table)
    }
    let table_path = export_dir + "/" + relative
    let table_exists = @fs.is_file(table_path) catch {
      error => raise ExportContractError::Io(error)
    }
    if !table_exists {
      raise fail("export table missing: " + table_path)
    }
    let table_value = read_json(table_path)
    let rows = json_rows(table_value, table)
    reject_secrets(table_value, table)
    let declared_rows = required_int(entry, "rows", entry_path)
    if declared_rows < 0 || declared_rows != rows.length() {
      raise fail("row count mismatch for " + table)
    }
    let primary_key = match entry.get("primary_key") {
      Some(String(value)) => value
      Some(_) => raise fail("invalid primary key for " + table)
      None => ""
    }
    if declared_rows > 0 && primary_key.trim().is_empty() {
      raise fail("non-empty table has no primary key: " + table)
    }
    let key_values : Array[String] = []
    for row_index in 0..<rows.length() {
      let row_path = table + "[" + row_index.to_string() + "]"
      let row = object(rows[row_index], row_path)
      if declared_rows > 0 {
        let key_value = match row.get(primary_key) {
          Some(Null) | None =>
            raise fail("primary-key value is missing for " + row_path)
          Some(value) => value.stringify()
        }
        if key_value == "\"\"" || contains_string(key_values, key_value) {
          raise fail("duplicate or empty primary-key value for " + table)
        }
        key_values.push(key_value)
      }
    }
    let declared_hash = required_string(entry, "sha256", entry_path)
    if !is_sha256(declared_hash) {
      raise fail("invalid table hash for " + table)
    }
    let actual_hash = sha256_file(table_path)
    if actual_hash != declared_hash {
      raise fail("table hash mismatch for " + table)
    }
    verified_rows += declared_rows
    verified_files += 1
    table_reports.push(
      Json::object({
        "table": Json::string(table),
        "rows": Json::number(declared_rows.to_double()),
        "sha256": Json::string(actual_hash),
        "verified": Json::boolean(true),
      }),
    )
  }
  let missing_names : Array[String] = []
  for table in expected {
    if !contains_string(seen, table) {
      missing_names.push(table)
    }
  }
  let extra_names : Array[String] = []
  for table in seen {
    if !contains_string(expected, table) {
      extra_names.push(table)
    }
  }
  missing_names.sort_by(fn(left, right) { left.lexical_compare(right) })
  extra_names.sort_by(fn(left, right) { left.lexical_compare(right) })
  let state = if missing_names.is_empty() && extra_names.is_empty() {
    "ready_for_source_import"
  } else {
    "source_export_incomplete"
  }
  Json::object({
    "format": Json::string("moonproj.erp.export-contract.v1"),
    "manifest_format": Json::string(manifest_format),
    "schema_tables": Json::number(expected.length().to_double()),
    "export_tables": Json::number(seen.length().to_double()),
    "present_tables": Json::number(
      (expected.length() - missing_names.length()).to_double(),
    ),
    "missing_tables": Json::array(json_strings(missing_names)),
    "extra_tables": Json::array(json_strings(extra_names)),
    "verified_files": Json::number(verified_files.to_double()),
    "verified_rows": Json::number(verified_rows.to_double()),
    "source_sha256": Json::string(source_hash),
    "state": Json::string(state),
    "content_verified": Json::boolean(true),
    "promotion_authorized": Json::boolean(false),
    "cutover_authorized": Json::boolean(false),
    "tables": Json::array(table_reports),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: export_contract <schema> <export_dir> <output>")
    @sys.exit(2)
  }
  let report = validate(args[1], args[2]) catch {
    error => {
      println("ERP export contract failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[3], output) catch {
    _ => {
      println("ERP export contract failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
