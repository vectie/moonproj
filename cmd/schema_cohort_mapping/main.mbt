///|
/// MoonBit validator for one explicit schema-only target mapping wave.
pub(all) suberror SchemaCohortMappingError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct PlanEntry {
  table : String
  snapshot_rows : Int
}

///|
struct AcceptedEntry {
  table : String
  snapshot_rows : Int
  target : Json
  security_controls : Json
  disposition : String
}

///|
fn fail(message : String) -> SchemaCohortMappingError {
  SchemaCohortMappingError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SchemaCohortMappingError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SchemaCohortMappingError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SchemaCohortMappingError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise SchemaCohortMappingError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => raise fail("expected string at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise SchemaCohortMappingError {
  match fields.get(key) {
    Some(Array(values)) => values
    Some(_) => raise fail("expected array at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_object(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Map[String, Json] raise SchemaCohortMappingError {
  match fields.get(key) {
    Some(Object(value)) => value
    Some(_) => raise fail("expected object at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn optional_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise SchemaCohortMappingError {
  match fields.get(key) {
    None => 0
    Some(Number(value, ..)) if value == value.trunc() => value.to_int()
    Some(_) => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn find_plan_entry(entries : Array[PlanEntry], table : String) -> PlanEntry? {
  for entry in entries {
    if entry.table == table {
      return Some(entry)
    }
  }
  None
}

///|
fn contains(values : Array[String], value : String) -> Bool {
  values.contains(value)
}

///|
fn run(
  plan_path : String,
  mapping_path : String,
) -> Json raise SchemaCohortMappingError {
  let plan = object(read_json(plan_path), "cohort-plan")
  let mapping = object(read_json(mapping_path), "mapping")
  if required_string(plan, "format", "cohort-plan") !=
    "moonproj.erp.schema-cohort-plan.v1" {
    raise fail("unexpected schema cohort plan format")
  }
  if required_string(mapping, "format", "mapping") !=
    "moonproj.erp.schema-cohort-mapping.v1" {
    raise fail("unexpected schema cohort mapping format")
  }
  let wave = required_string(mapping, "wave", "mapping")
  let all_entries = required_array(plan, "entries", "cohort-plan")
  let plan_entries : Array[PlanEntry] = []
  for index in 0..<all_entries.length() {
    let path = "cohort-plan.entries[" + index.to_string() + "]"
    let entry = object(all_entries[index], path)
    if required_string(entry, "wave", path) == wave {
      plan_entries.push(PlanEntry::{
        table: required_string(entry, "table", path),
        snapshot_rows: optional_int(entry, "snapshot_rows", path),
      })
    }
  }
  if plan_entries.length() == 0 {
    raise fail("wave has no schema-only entries: " + wave)
  }
  let rows = required_array(mapping, "tables", "mapping")
  if rows.length() == 0 {
    raise fail("mapping tables must be a non-empty array")
  }
  let seen : Array[String] = []
  let accepted : Array[AcceptedEntry] = []
  for index in 0..<rows.length() {
    let path = "mapping.tables[" + index.to_string() + "]"
    let item = object(rows[index], path)
    let table = required_string(item, "table", path)
    if contains(seen, table) {
      raise fail("duplicate mapping table: " + table)
    }
    seen.push(table)
    let plan_entry = match find_plan_entry(plan_entries, table) {
      Some(entry) => entry
      None => raise fail("mapping table is outside wave " + wave + ": " + table)
    }
    let target = required_object(item, "target", path)
    let owner = required_string(target, "owner", path + ".target")
    let record_type = required_string(target, "record_type", path + ".target")
    if owner.is_empty() || record_type.is_empty() {
      raise fail(table + " requires target owner and record type")
    }
    let controls = required_array(item, "security_controls", path)
    if controls.length() == 0 {
      raise fail(table + " requires security controls")
    }
    let disposition = required_string(item, "disposition", path)
    if disposition != "typed_import" &&
      disposition != "evidence_only" &&
      disposition != "exclude_sensitive" {
      raise fail(table + " has unsupported disposition: " + disposition)
    }
    accepted.push(AcceptedEntry::{
      table,
      snapshot_rows: plan_entry.snapshot_rows,
      target: Json::object(target),
      security_controls: Json::array(controls),
      disposition,
    })
  }
  let missing : Array[String] = []
  for entry in plan_entries {
    if !contains(seen, entry.table) {
      missing.push(entry.table)
    }
  }
  if missing.length() > 0 {
    missing.sort_by(fn(left, right) { left.lexical_compare(right) })
    raise fail("wave tables missing mappings: " + missing.join(","))
  }
  accepted.sort_by(fn(left, right) { left.table.lexical_compare(right.table) })
  let table_json : Array[Json] = []
  let mut source_rows = 0
  for entry in accepted {
    source_rows += entry.snapshot_rows
    table_json.push(
      Json::object({
        "table": Json::string(entry.table),
        "wave": Json::string(wave),
        "snapshot_rows": Json::number(entry.snapshot_rows.to_double()),
        "target": entry.target,
        "security_controls": entry.security_controls,
        "disposition": Json::string(entry.disposition),
        "promotion_authorized": Json::boolean(false),
      }),
    )
  }
  Json::object({
    "format": Json::string("moonproj.erp.schema-cohort-mapping-result.v1"),
    "cohort_plan_format": Json::string(
      required_string(plan, "format", "cohort-plan"),
    ),
    "mapping_version": match mapping.get("mapping_version") {
      Some(value) => value
      None => Json::null()
    },
    "wave": Json::string(wave),
    "state": Json::string("mapped_scope_only"),
    "source_rows_available": Json::number(source_rows.to_double()),
    "mapped_tables": Json::number(accepted.length().to_double()),
    "tables": Json::array(table_json),
    "promotion_authorized": Json::boolean(false),
    "cutover_authorized": Json::boolean(false),
    "note": Json::string(
      "Semantic ownership is explicit; no absent source rows were fabricated or promoted.",
    ),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: schema_cohort_mapping <cohort_plan> <mapping> <output>")
    @sys.exit(2)
  }
  let report = run(args[1], args[2]) catch {
    error => {
      println("ERP schema cohort mapping failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[3], output) catch {
    _ => {
      println("ERP schema cohort mapping failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
