///|
pub(all) suberror RowCoverageError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> RowCoverageError {
  RowCoverageError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise RowCoverageError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise RowCoverageError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON evidence: " + path)
  }
}

///|
fn try_read_json(path : String) -> Json? {
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let value = @json.parse(content) catch { _ => return None }
  Some(value)
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise RowCoverageError {
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
) -> Json raise RowCoverageError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing " + key + ": " + path)
  }
}

///|
fn text(value : Json, path : String) -> String raise RowCoverageError {
  match value {
    String(value) => value
    Number(number, repr~) =>
      match repr {
        Some(repr) => repr
        None => number.to_string()
      }
    True => "True"
    False => "False"
    Null => "None"
    _ => raise fail("source identity is not scalar: " + path)
  }
}

///|
fn array(value : Json, path : String) -> Array[Json] raise RowCoverageError {
  match value {
    Array(values) => values
    _ => raise fail("expected array: " + path)
  }
}

///|
fn optional_text(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    Some(Number(number, repr~)) =>
      Some(
        match repr {
          Some(repr) => repr
          None => number.to_string()
        },
      )
    _ => None
  }
}

///|
fn add_count(counts : Map[String, Int], key : String, amount : Int) -> Unit {
  counts.set(key, counts.get(key).unwrap_or(0) + amount)
}

///|
fn source_tables(
  export_dir : String,
) -> (Map[String, Int], Map[String, Map[String, Bool]]) raise RowCoverageError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let format = text(required(manifest, "format", "manifest"), "manifest.format")
  if format != "moonproj.erp.snapshot.v1" &&
    format != "moonproj.erp.full-export.v1" {
    raise fail("unexpected export manifest format")
  }
  let table_values = array(
    required(manifest, "tables", "manifest"),
    "manifest.tables",
  )
  let rows_by_table : Map[String, Int] = {}
  let ids_by_table : Map[String, Map[String, Bool]] = {}
  for index in 0..<table_values.length() {
    let path = "manifest.tables[" + index.to_string() + "]"
    let entry = object(table_values[index], path)
    let table = text(required(entry, "table", path), path + ".table")
    let relative = text(required(entry, "file", path), path + ".file")
    let rows = array(read_json(export_dir + "/" + relative), table)
    let ids : Map[String, Bool] = {}
    if !rows.is_empty() {
      let primary_key = text(
        required(entry, "primary_key", path),
        path + ".primary_key",
      )
      if primary_key.is_empty() {
        raise fail("non-empty table has no primary key: " + table)
      }
      for row_index in 0..<rows.length() {
        let row_path = table + "[" + row_index.to_string() + "]"
        let fields = object(rows[row_index], row_path)
        let identity = text(
          required(fields, primary_key, row_path),
          row_path + "." + primary_key,
        )
        if ids.contains(identity) {
          raise fail("duplicate source identity in " + table)
        }
        ids.set(identity, true)
      }
    }
    rows_by_table.set(table, rows.length())
    ids_by_table.set(table, ids)
  }
  (rows_by_table, ids_by_table)
}

///|
fn add_nested_counts(path : String, nested : Map[String, Int]) -> Unit {
  let value = match try_read_json(path) {
    Some(value) => value
    None => return
  }
  let root = match value {
    Object(fields) => fields
    _ => return
  }
  let format = optional_text(root, "format").unwrap_or("")
  if format == "moonproj.erp.workflow-promotion-plan.v1" {
    let items = match root.get("items") {
      Some(value) => array(value, path + ".items") catch { _ => return }
      None => return
    }
    for item in items {
      let item_fields = match item {
        Object(fields) => fields
        _ => continue
      }
      let candidate = match item_fields.get("target_candidate") {
        Some(Object(fields)) => fields
        _ => continue
      }
      let steps = match candidate.get("steps") {
        Some(Array(values)) => values
        _ => continue
      }
      add_count(nested, "wf_step_def", steps.length())
    }
  } else if format == "moonproj.erp.investment-promotion-plan.v1" {
    let items = match root.get("items") {
      Some(value) => array(value, path + ".items") catch { _ => return }
      None => return
    }
    for item in items {
      let item_fields = match item {
        Object(fields) => fields
        _ => continue
      }
      let candidate = match item_fields.get("target_candidate") {
        Some(Object(fields)) => fields
        _ => continue
      }
      let indexes = match candidate.get("indexes") {
        Some(Array(values)) => values
        _ => continue
      }
      add_count(nested, "tzsy_plan_index", indexes.length())
    }
  } else if format == "moonproj.erp.parameter-promotion-plan.v1" {
    let items = match root.get("items") {
      Some(value) => array(value, path + ".items") catch { _ => return }
      None => return
    }
    for item in items {
      let item_fields = match item {
        Object(fields) => fields
        _ => continue
      }
      if optional_text(item_fields, "source_table") !=
        Some("my_biz_param_option") {
        continue
      }
      let candidate = match item_fields.get("target_candidate") {
        Some(Object(fields)) => fields
        _ => continue
      }
      let options = match candidate.get("options") {
        Some(Array(values)) => values
        _ => continue
      }
      add_count(nested, "my_biz_param_option", options.length())
    }
  }
}

///|
fn add_direct_receipts(
  paths : Array[String],
  source_ids : Map[String, Map[String, Bool]],
  accepted : Map[String, Map[String, Bool]],
) -> Unit {
  for path in paths {
    let value = match try_read_json(path) {
      Some(value) => value
      None => continue
    }
    let root = match value {
      Object(fields) => fields
      _ => continue
    }
    let items = match root.get("accepted_items") {
      Some(Array(values)) => values
      _ => continue
    }
    for item in items {
      let fields = match item {
        Object(fields) => fields
        _ => continue
      }
      let table = optional_text(fields, "source_table")
      let source_id = optional_text(fields, "source_id")
      match (table, source_id) {
        (Some(table), Some(source_id)) =>
          match source_ids.get(table) {
            Some(ids) if ids.contains(source_id) => {
              let seen = match accepted.get(table) {
                Some(seen) => seen
                None => {
                  let created : Map[String, Bool] = {}
                  accepted.set(table, created)
                  created
                }
              }
              seen.set(source_id, true)
            }
            _ => ()
          }
        _ => ()
      }
    }
  }
}

///|
fn number(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  export_dir : String,
  output : String,
  paths : Array[String],
) -> Unit raise RowCoverageError {
  let (rows_by_table, source_ids) = source_tables(export_dir)
  let accepted : Map[String, Map[String, Bool]] = {}
  let nested : Map[String, Int] = {}
  add_direct_receipts(paths, source_ids, accepted)
  for path in paths {
    add_nested_counts(path, nested)
  }
  let tables = rows_by_table.keys().to_array()
  tables.sort_by(fn(left, right) { left.lexical_compare(right) })
  let reports : Array[Json] = []
  let uncovered_tables : Array[Json] = []
  let mut total_rows = 0
  let mut covered_rows = 0
  for table in tables {
    let source_rows = rows_by_table.get(table).unwrap()
    let direct_rows = match accepted.get(table) {
      Some(values) => values.keys().length()
      None => 0
    }
    let structural_rows = nested.get(table).unwrap_or(0)
    let candidate_covered = direct_rows + structural_rows
    let covered = if source_rows < candidate_covered {
      source_rows
    } else {
      candidate_covered
    }
    let uncovered = source_rows - covered
    if uncovered > 0 {
      uncovered_tables.push(Json::string(table))
    }
    total_rows += source_rows
    covered_rows += covered
    reports.push(
      Json::object({
        "table": Json::string(table),
        "source_rows": number(source_rows),
        "direct_rows": number(direct_rows),
        "structural_rows": number(structural_rows),
        "covered_rows": number(covered),
        "uncovered_rows": number(uncovered),
        "state": Json::string(
          if source_rows == 0 {
            "empty"
          } else if uncovered == 0 {
            "covered"
          } else {
            "uncovered"
          },
        ),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.row-coverage.v1"),
    "state": Json::string(
      if uncovered_tables.is_empty() {
        "row_coverage_verified"
      } else {
        "row_coverage_incomplete"
      },
    ),
    "source_tables": number(tables.length()),
    "source_rows": number(total_rows),
    "covered_rows": number(covered_rows),
    "uncovered_rows": number(total_rows - covered_rows),
    "uncovered_tables": Json::array(uncovered_tables),
    "promotion_authorized": Json::boolean(false),
    "cutover_authorized": Json::boolean(false),
    "tables": Json::array(reports),
  })
  @fs.write_string_to_file(output, report.stringify(indent=2) + "\n") catch {
    error => raise RowCoverageError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output),
      "source_tables": number(tables.length()),
      "source_rows": number(total_rows),
      "covered_rows": number(covered_rows),
      "uncovered_rows": number(total_rows - covered_rows),
      "state": Json::string(
        if uncovered_tables.is_empty() {
          "row_coverage_verified"
        } else {
          "row_coverage_incomplete"
        },
      ),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: row_coverage <export_dir> <output> <evidence.json...>")
    @sys.exit(2)
  } else {
    let paths : Array[String] = []
    for index in 3..<args.length() {
      paths.push(args[index])
    }
    run(args[1], args[2], paths) catch {
      RowCoverageError::InvalidInput(message) => {
        println("ERP row coverage failed: " + message)
        @sys.exit(1)
      }
      RowCoverageError::Io(_) => {
        println("ERP row coverage failed: filesystem error")
        @sys.exit(1)
      }
    }
  }
}
