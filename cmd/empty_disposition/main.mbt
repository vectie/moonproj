///|
pub(all) suberror EmptyDispositionError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> EmptyDispositionError {
  EmptyDispositionError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise EmptyDispositionError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise EmptyDispositionError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot read JSON evidence: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise EmptyDispositionError {
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
) -> Json raise EmptyDispositionError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn string_value(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise EmptyDispositionError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise fail("expected string at " + path + "." + key)
  }
}

///|
fn optional_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn integer_value(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise EmptyDispositionError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn number_or_null(fields : Map[String, Json], key : String) -> Json {
  fields.get(key).unwrap_or(Json::null())
}

///|
fn is_hex_hash(value : String) -> Bool {
  value.length() == 64 &&
  value
  .iter()
  .all(fn(char) { (char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') })
}

///|
fn non_empty(value : Json, path : String) -> String raise EmptyDispositionError {
  match value {
    String(text) if !text.trim().is_empty() => text
    _ => raise fail(path + " must be a non-empty string")
  }
}

///|
fn sensitive_key(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.contains("credential") ||
  lowered.contains("dsn") ||
  lowered.contains("connection_string") ||
  lowered.contains("connection-string") ||
  lowered.contains("bearer")
}

///|
fn safe_metadata_key(key : String) -> Bool {
  [
    "format", "state", "baseline_source_snapshot_id", "source_snapshot_hash", "source_snapshot_kind",
    "table", "capability_id", "wave", "snapshot_rows", "disposition", "row_count",
    "table_sha256", "promotion_authorized", "cutover_authorized", "schema_only_tables",
  ].contains(key)
}

///|
fn reject_sensitive(
  value : Json,
  path : String,
  key : String?,
) -> Unit raise EmptyDispositionError {
  match value {
    Object(fields) =>
      for field, child in fields {
        if sensitive_key(field) {
          raise fail("sensitive key is not allowed: " + path + "." + field)
        }
        reject_sensitive(child, path + "." + field, Some(field))
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_sensitive(
          values[index],
          path + "[" + index.to_string() + "]",
          key,
        )
      }
    String(text) =>
      match key {
        Some(field) if !safe_metadata_key(field) && sensitive_key(text) =>
          raise fail("sensitive value is not allowed: " + path)
        _ => ()
      }
    _ => ()
  }
}

///|
fn schema_only_entries(
  schema_gap : Json,
  cohort_plan : Json,
) -> Array[Json] raise EmptyDispositionError {
  let gap = object(schema_gap, "schema-gap")
  let plan = object(cohort_plan, "schema-cohort-plan")
  if string_value(gap, "format", "schema-gap") != "moonproj.erp.schema-gap.v1" {
    raise fail("unexpected schema-gap format")
  }
  if string_value(plan, "format", "schema-cohort-plan") !=
    "moonproj.erp.schema-cohort-plan.v1" {
    raise fail("unexpected schema-cohort-plan format")
  }
  let gap_values = match required(gap, "entries", "schema-gap") {
    Array(values) => values
    _ => raise fail("schema-gap entries must be an array")
  }
  let plan_values = match required(plan, "entries", "schema-cohort-plan") {
    Array(values) => values
    _ => raise fail("schema-cohort-plan entries must be an array")
  }
  let gap_tables : Map[String, Map[String, Json]] = {}
  for index in 0..<gap_values.length() {
    let entry = object(
      gap_values[index],
      "schema-gap.entries[" + index.to_string() + "]",
    )
    if optional_string(entry, "state") == Some("schema_only") {
      let table = string_value(
        entry,
        "table",
        "schema-gap.entries[" + index.to_string() + "]",
      )
      gap_tables.set(table, entry)
    }
  }
  let candidates : Array[Map[String, Json]] = []
  for index in 0..<plan_values.length() {
    let entry = object(
      plan_values[index],
      "schema-cohort-plan.entries[" + index.to_string() + "]",
    )
    if optional_string(entry, "state") == Some("schema_only") {
      candidates.push(entry)
    }
  }
  if gap_tables.length() != 49 || candidates.length() != 49 {
    raise fail(
      "expected 49 schema-only tables, found gap=" +
      gap_tables.length().to_string() +
      " plan=" +
      candidates.length().to_string(),
    )
  }
  candidates.sort_by(fn(left, right) {
    let left_table = match left.get("table") {
      Some(String(value)) => value
      _ => ""
    }
    let right_table = match right.get("table") {
      Some(String(value)) => value
      _ => ""
    }
    left_table.lexical_compare(right_table)
  })
  let result : Array[Json] = []
  for entry in candidates {
    let table = string_value(entry, "table", "cohort entry")
    if !gap_tables.contains(table) {
      raise fail("cohort table is absent from schema gap: " + table)
    }
    let gap_entry = gap_tables.get(table).unwrap()
    result.push(
      Json::object({
        "table": Json::string(table),
        "capability_id": required(entry, "capability_id", "cohort entry"),
        "wave": required(entry, "wave", "cohort entry"),
        "snapshot_rows": number_or_null(gap_entry, "snapshot_rows"),
        "disposition": Json::string("pending"),
        "source_evidence": Json::object({
          "row_count": Json::null(),
          "table_sha256": Json::null(),
        }),
        "owner": Json::null(),
        "approved_at": Json::null(),
        "rationale": Json::null(),
        "evidence_ref": Json::null(),
      }),
    )
  }
  result
}

///|
fn template(
  schema_gap : Json,
  cohort_plan : Json,
) -> Json raise EmptyDispositionError {
  let gap = object(schema_gap, "schema-gap")
  Json::object({
    "format": Json::string("moonproj.erp.empty-disposition.v1"),
    "state": Json::string("awaiting_owner_disposition"),
    "baseline_source_snapshot_id": required(
      gap, "source_snapshot_id", "schema-gap",
    ),
    "source_snapshot_hash": Json::null(),
    "source_snapshot_kind": Json::string("redacted_empty_table_evidence"),
    "entries": Json::array(schema_only_entries(schema_gap, cohort_plan)),
    "promotion_authorized": Json::boolean(false),
    "cutover_authorized": Json::boolean(false),
  })
}

///|
fn utc_timestamp(
  value : Json,
  path : String,
) -> Unit raise EmptyDispositionError {
  let text = non_empty(value, path)
  let utc = text.has_suffix("Z") || text.has_suffix("+00:00")
  if !utc || text.length() < 20 || !text.contains("T") {
    raise fail(path + " must be an ISO-8601 UTC timestamp")
  }
}

///|
fn validate(
  schema_gap : Json,
  cohort_plan : Json,
  report : Json,
) -> Json raise EmptyDispositionError {
  let gap = object(schema_gap, "schema-gap")
  let expected_json = schema_only_entries(schema_gap, cohort_plan)
  let expected : Map[String, Map[String, Json]] = {}
  for item in expected_json {
    let entry = object(item, "expected entry")
    expected.set(string_value(entry, "table", "expected entry"), entry)
  }
  reject_sensitive(report, "root", None)
  let fields = object(report, "report")
  if string_value(fields, "format", "report") !=
    "moonproj.erp.empty-disposition.v1" {
    raise fail("unexpected empty-disposition format")
  }
  let source_hash = string_value(fields, "source_snapshot_hash", "report")
  if !is_hex_hash(source_hash) {
    raise fail("source_snapshot_hash must be a 64-character lowercase SHA-256")
  }
  let values = match required(fields, "entries", "report") {
    Array(items) => items
    _ => raise fail("entries must be an array")
  }
  let seen : Map[String, Bool] = {}
  let mut pending = 0
  let mut approved = 0
  let mut source_required = 0
  for index in 0..<values.length() {
    let path = "entries[" + index.to_string() + "]"
    let entry = object(values[index], path)
    let table = string_value(entry, "table", path)
    if !expected.contains(table) {
      raise fail(path + " has an unexpected table")
    }
    if seen.contains(table) {
      raise fail("duplicate disposition for table: " + table)
    }
    seen.set(table, true)
    let expected_entry = expected.get(table).unwrap()
    if required(entry, "capability_id", path) !=
      required(expected_entry, "capability_id", "expected") {
      raise fail("capability_id does not match cohort plan for " + table)
    }
    if required(entry, "wave", path) !=
      required(expected_entry, "wave", "expected") {
      raise fail("wave does not match cohort plan for " + table)
    }
    let disposition = string_value(entry, "disposition", path)
    if disposition != "pending" &&
      disposition != "owner_approved_empty" &&
      disposition != "source_export_required" {
      raise fail("unsupported disposition for " + table + ": " + disposition)
    }
    let evidence = object(
      required(entry, "source_evidence", path),
      path + ".source_evidence",
    )
    if disposition == "owner_approved_empty" {
      if integer_value(evidence, "row_count", path + ".source_evidence") != 0 ||
        string_value(evidence, "table_sha256", path + ".source_evidence") !=
        "37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570" {
        raise fail("empty table evidence does not match []\\n: " + table)
      }
      let owner = non_empty(required(entry, "owner", path), path + ".owner")
      if owner.length() > 128 {
        raise fail("owner is required for " + table)
      }
      utc_timestamp(required(entry, "approved_at", path), path + ".approved_at")
      for key in ["rationale", "evidence_ref"] {
        let text = non_empty(required(entry, key, path), path + "." + key)
        if text.length() > 1000 {
          raise fail(key + " is required for " + table)
        }
      }
      approved += 1
    } else if disposition == "pending" {
      match entry.get("owner") {
        None | Some(Null) | Some(String("")) => ()
        _ => raise fail("pending entry cannot have an owner: " + table)
      }
      match entry.get("approved_at") {
        None | Some(Null) | Some(String("")) => ()
        _ => raise fail("pending entry cannot have approval time: " + table)
      }
      pending += 1
    } else {
      match entry.get("approved_at") {
        None | Some(Null) | Some(String("")) => ()
        _ =>
          raise fail(
            "source-export-required entry cannot be approved: " + table,
          )
      }
      source_required += 1
    }
  }
  if seen.length() != expected.length() {
    let missing : Array[String] = []
    for table, _ in expected {
      if !seen.contains(table) {
        missing.push(table)
      }
    }
    missing.sort_by(fn(left, right) { left.lexical_compare(right) })
    raise fail("missing schema-only dispositions: " + missing.join(","))
  }
  if values.length() != expected.length() {
    raise fail(
      "expected " +
      expected.length().to_string() +
      " dispositions, found " +
      values.length().to_string(),
    )
  }
  let state = if pending == 0 && source_required == 0 {
    "owner_dispositions_complete"
  } else if pending == 0 {
    "source_export_required"
  } else {
    "awaiting_owner_disposition"
  }
  fields.set("state", Json::string(state))
  fields.set("schema_only_tables", Json::number(expected.length().to_double()))
  fields.set(
    "disposition_counts",
    Json::object({
      "pending": Json::number(pending.to_double()),
      "owner_approved_empty": Json::number(approved.to_double()),
      "source_export_required": Json::number(source_required.to_double()),
    }),
  )
  fields.set("promotion_authorized", Json::boolean(false))
  fields.set("cutover_authorized", Json::boolean(false))
  fields.set(
    "baseline_source_snapshot_id",
    required(gap, "source_snapshot_id", "schema-gap"),
  )
  Json::object(fields)
}

///|
fn run(args : Array[String]) -> Json raise EmptyDispositionError {
  if args.length() < 5 {
    raise fail(
      "usage: empty_disposition <schema-gap> <cohort-plan> <output> (--template | --input <path>)",
    )
  }
  let schema_gap = read_json(args[1])
  let cohort_plan = read_json(args[2])
  if args[4] == "--template" && args.length() == 5 {
    template(schema_gap, cohort_plan)
  } else if args[4] == "--input" && args.length() == 6 {
    validate(schema_gap, cohort_plan, read_json(args[5]))
  } else {
    raise fail("one of --template or --input is required")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  let report = run(args) catch {
    error => {
      println("ERP empty disposition failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  @fs.write_string_to_file(args[3], report.stringify(indent=2) + "\n") catch {
    _ => {
      println("ERP empty disposition failed: filesystem error")
      @sys.exit(1)
    }
  }
  let summary = match report {
    Object(fields) =>
      Json::object({
        "output": Json::string(args[3]),
        "schema_only_tables": match fields.get("entries") {
          Some(Array(values)) => Json::number(values.length().to_double())
          _ => Json::number(0)
        },
        "state": fields.get("state").unwrap_or(Json::null()),
        "promotion_authorized": Json::boolean(false),
        "cutover_authorized": Json::boolean(false),
      })
    _ => Json::null()
  }
  println(summary.stringify())
}
