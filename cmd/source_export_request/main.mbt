///|
/// MoonBit source-export request generator.
pub(all) suberror SourceExportRequestError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SourceExportRequestError {
  SourceExportRequestError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SourceExportRequestError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SourceExportRequestError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SourceExportRequestError {
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
) -> Json raise SourceExportRequestError {
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
) -> String raise SourceExportRequestError {
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
) -> Array[Json] raise SourceExportRequestError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn optional_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise SourceExportRequestError {
  match fields.get(key) {
    None => 0
    Some(Number(value, ..)) if value == value.trunc() => value.to_int()
    Some(_) => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn secret_keys() -> Json {
  Json::array([
    Json::string("password"),
    Json::string("secret"),
    Json::string("token"),
    Json::string("private"),
    Json::string("credential"),
    Json::string("ip"),
  ])
}

///|
fn run(
  gap_path : String,
  plan_path : String,
) -> Json raise SourceExportRequestError {
  let gap = object(read_json(gap_path), "schema-gap")
  let plan = object(read_json(plan_path), "schema-cohort-plan")
  if required_string(gap, "format", "schema-gap") !=
    "moonproj.erp.schema-gap.v1" {
    raise fail("unexpected schema-gap format")
  }
  if required_string(plan, "format", "schema-cohort-plan") !=
    "moonproj.erp.schema-cohort-plan.v1" {
    raise fail("unexpected schema-cohort-plan format")
  }
  let entries = required_array(plan, "entries", "schema-cohort-plan")
  if entries.length() != 49 {
    raise fail(
      "expected 49 schema-only entries, found " + entries.length().to_string(),
    )
  }
  let tables : Array[Json] = []
  for index in 0..<entries.length() {
    let path = "schema-cohort-plan.entries[" + index.to_string() + "]"
    let entry = object(entries[index], path)
    if required_string(entry, "state", path) != "schema_only" {
      raise fail("schema cohort entry is not schema_only: " + path)
    }
    let table = required_string(entry, "table", path)
    tables.push(
      Json::object({
        "table": Json::string(table),
        "wave": Json::string(required_string(entry, "wave", path)),
        "capability_id": Json::string(
          required_string(entry, "capability_id", path),
        ),
        "snapshot_rows": Json::number(
          optional_int(entry, "snapshot_rows", path).to_double(),
        ),
        "required_export": Json::object({
          "format": Json::string("redacted_json_array"),
          "primary_key": Json::string("required_for_non_empty_table"),
          "per_table_sha256": Json::boolean(true),
          "source_snapshot_hash": Json::boolean(true),
          "secret_keys_removed": secret_keys(),
        }),
        "migration_action": Json::string(
          required_string(entry, "migration_action", path),
        ),
        "requested": Json::boolean(true),
      }),
    )
  }
  Json::object({
    "format": Json::string("moonproj.erp.source-export-request.v1"),
    "state": Json::string("awaiting_source_export"),
    "source_engine": Json::string("mysql"),
    "schema_tables": required(gap, "schema_tables", "schema-gap"),
    "present_tables": required(gap, "present_tables", "schema-gap"),
    "requested_tables": Json::number(tables.length().to_double()),
    "source_snapshot_id": required(gap, "source_snapshot_id", "schema-gap"),
    "cutover_authorized": Json::boolean(false),
    "promotion_authorized": Json::boolean(false),
    "request": Json::object({
      "read_only": Json::boolean(true),
      "credential_free_output": Json::boolean(true),
      "include_empty_tables": Json::boolean(true),
      "include_primary_keys": Json::boolean(true),
      "include_table_hashes": Json::boolean(true),
      "include_source_snapshot_hash": Json::boolean(true),
      "exclude_credentials_and_network_secrets": Json::boolean(true),
    }),
    "tables": Json::array(tables),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: source_export_request <schema_gap> <cohort_plan> <output>")
    @sys.exit(2)
  }
  let report = run(args[1], args[2]) catch {
    error => {
      println("ERP source export request failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[3], output) catch {
    _ => {
      println("ERP source export request failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
