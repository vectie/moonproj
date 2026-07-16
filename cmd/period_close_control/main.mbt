///|
pub(all) suberror PeriodCloseControlError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct Cohort {
  file : String
  files : Array[String]
  backends : Array[String]
  source_snapshot_id : String
  mapping_version : String
  link_count : Int
  state : String
}

///|
fn fail(message : String) -> PeriodCloseControlError {
  PeriodCloseControlError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PeriodCloseControlError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise PeriodCloseControlError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot read reconciliation evidence: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PeriodCloseControlError {
  match value {
    Object(fields) => fields
    _ => raise fail("reconciliation evidence is not an object: " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise PeriodCloseControlError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("reconciliation has no " + key + ": " + path)
  }
}

///|
fn string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise PeriodCloseControlError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("reconciliation has invalid " + key + ": " + path)
  }
}

///|
fn integer(value : Json, path : String) -> Int raise PeriodCloseControlError {
  match value {
    Number(number, ..) if number == number.trunc() => number.to_int()
    _ => raise fail("reconciliation has invalid link_count: " + path)
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
fn strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn cohort_json(value : Cohort) -> Json {
  Json::object({
    "file": Json::string(value.file),
    "files": strings(value.files),
    "backends": strings(value.backends),
    "source_snapshot_id": Json::string(value.source_snapshot_id),
    "mapping_version": Json::string(value.mapping_version),
    "link_count": Json::number(
      value.link_count.to_double(),
      repr=value.link_count.to_string(),
    ),
    "state": Json::string(value.state),
  })
}

///|
fn find_cohort(
  values : Array[Cohort],
  source : String,
  mapping : String,
) -> Int? {
  for index in 0..<values.length() {
    if values[index].source_snapshot_id == source &&
      values[index].mapping_version == mapping {
      return Some(index)
    }
  }
  None
}

///|
fn load_cohort(path : String) -> Cohort raise PeriodCloseControlError {
  let root = object(read_json(path), path)
  if string(root, "format", path) != "moonproj.erp.accounting-reconciliation.v1" {
    raise fail("unexpected reconciliation format: " + path)
  }
  if string(root, "state", path) != "reconciled" {
    raise fail("unreconciled cohort: " + path)
  }
  if string(root, "integrity", path) != "ok" {
    raise fail("unhealthy cohort: " + path)
  }
  if root.get("cash_released") != Some(Json::boolean(false)) ||
    root.get("period_posted") != Some(Json::boolean(false)) {
    raise fail("economic side effect already asserted: " + path)
  }
  let link_count = integer(required(root, "link_count", path), path)
  if link_count <= 0 {
    raise fail("empty reconciliation cohort: " + path)
  }
  let backend = match root.get("backend") {
    Some(String(value)) if !value.trim().is_empty() => value
    None => "sqlite"
    _ => raise fail("reconciliation has no backend: " + path)
  }
  {
    file: path,
    files: [path],
    backends: [backend],
    source_snapshot_id: string(root, "source_snapshot_id", path),
    mapping_version: string(root, "mapping_version", path),
    link_count,
    state: string(root, "state", path),
  }
}

///|
fn run(
  output : String,
  period_id : String,
  paths : Array[String],
) -> Unit raise PeriodCloseControlError {
  if period_id.trim().is_empty() {
    raise fail("period_id must be non-empty")
  }
  if paths.is_empty() {
    raise fail("no accounting reconciliation cohorts found")
  }
  let cohorts : Array[Cohort] = []
  for path in paths {
    let value = load_cohort(path)
    match
      find_cohort(cohorts, value.source_snapshot_id, value.mapping_version) {
      None => cohorts.push(value)
      Some(index) => {
        let existing = cohorts[index]
        if existing.link_count != value.link_count ||
          existing.state != value.state {
          raise fail(
            "duplicate backend reconciliation disagrees at " +
            value.source_snapshot_id +
            ":" +
            value.mapping_version,
          )
        }
        existing.files.push(path)
        if !existing.backends.contains(value.backends[0]) {
          existing.backends.push(value.backends[0])
        }
      }
    }
  }
  cohorts.sort_by(fn(left, right) {
    (left.source_snapshot_id + "\u{1f}" + left.mapping_version).lexical_compare(
      right.source_snapshot_id + "\u{1f}" + right.mapping_version,
    )
  })
  let snapshots : Array[String] = []
  let mappings : Array[String] = []
  let mut total_links = 0
  for cohort in cohorts {
    if !snapshots.contains(cohort.source_snapshot_id) {
      snapshots.push(cohort.source_snapshot_id)
    }
    if !mappings.contains(cohort.mapping_version) {
      mappings.push(cohort.mapping_version)
    }
    total_links += cohort.link_count
  }
  if snapshots.length() != 1 {
    raise fail("reconciliation cohorts come from different source snapshots")
  }
  mappings.sort_by(fn(left, right) { left.lexical_compare(right) })
  let evidence_values = cohorts.map(fn(cohort) {
    Json::object({
      "source_snapshot_id": Json::string(cohort.source_snapshot_id),
      "mapping_version": Json::string(cohort.mapping_version),
      "link_count": Json::number(
        cohort.link_count.to_double(),
        repr=cohort.link_count.to_string(),
      ),
      "state": Json::string(cohort.state),
      "backends": strings(cohort.backends.copy()),
    })
  })
  let evidence = "[" + evidence_values.map(canonical).join(",") + "]"
  let evidence_hash = "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@encoding/utf8.encode(evidence)))
  let report = Json::object({
    "format": Json::string("moonproj.erp.period-close-control.v1"),
    "period_id": Json::string(period_id),
    "source_snapshot_id": Json::string(snapshots[0]),
    "mapping_versions": strings(mappings),
    "cohort_count": Json::number(
      cohorts.length().to_double(),
      repr=cohorts.length().to_string(),
    ),
    "link_count": Json::number(
      total_links.to_double(),
      repr=total_links.to_string(),
    ),
    "evidence_hash": Json::string(evidence_hash),
    "cohorts": Json::array(cohorts.map(cohort_json)),
    "state": Json::string("ready_for_reconciled_close"),
    "close_authorized": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
    "close_requires": Json::array([
      Json::string("named period owner approval"),
      Json::string("native AccountingBook.close_reconciled"),
      Json::string("rollback evidence retained"),
    ]),
  })
  @fs.write_string_to_file(output, report.stringify(indent=2) + "\n") catch {
    error => raise PeriodCloseControlError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output),
      "state": Json::string("ready_for_reconciled_close"),
      "cohort_count": Json::number(cohorts.length().to_double()),
      "link_count": Json::number(total_links.to_double()),
      "evidence_hash": Json::string(evidence_hash),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println(
      "usage: period_close_control <output> <period_id> <reconciliation...>",
    )
    @sys.exit(2)
  } else {
    let paths : Array[String] = []
    for index in 3..<args.length() {
      paths.push(args[index])
    }
    run(args[1], args[2], paths) catch {
      PeriodCloseControlError::InvalidInput(message) => {
        println("period close control failed: " + message)
        @sys.exit(1)
      }
      PeriodCloseControlError::Io(_) => {
        println("period close control failed: filesystem error")
        @sys.exit(1)
      }
    }
  }
}
