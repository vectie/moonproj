///|
pub(all) suberror TaskPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct TaskRow {
  json : Json
  task_id : String
  parent_id : String
  sort_order : Int64
}

///|
fn fail(message : String) -> TaskPromotionPlanError {
  TaskPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TaskPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaskPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TaskPromotionPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn field_or(value : Json, key : String, fallback : Json) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(fallback)
    _ => fallback
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(value, ..) => value.to_int().to_int64()
    String(value) => parse_integer(value, default)
    _ => default
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim().to_owned()
  if source.is_empty() {
    return default
  }
  let mut index = 0
  let mut sign : Int64 = 1
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut result : Int64 = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return default
    }
    result = result * 10 + (char.to_int() - '0'.to_int()).to_int64()
    index += 1
  }
  result * sign
}

///|
fn progress_bps(value : Json) -> Int64 raise TaskPromotionPlanError {
  let source = match value {
    Null => "0"
    Number(_, ..) => value.stringify()
    String(value) => value
    _ => raise fail("invalid task progress: " + value.stringify())
  }
  let source = source.trim().to_owned()
  if source.is_empty() {
    raise fail("invalid task progress: " + source)
  }
  let mut index = 0
  let mut sign : Int64 = 1
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut numerator : Int64 = 0
  let mut denominator : Int64 = 1
  let mut after_decimal = false
  let mut digit_count = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char == '.' {
      if after_decimal {
        raise fail("invalid task progress: " + source)
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      numerator = numerator * 10 + (char.to_int() - '0'.to_int()).to_int64()
      digit_count += 1
      if after_decimal {
        denominator *= 10
      }
    } else {
      raise fail("invalid task progress: " + source)
    }
    index += 1
  }
  if digit_count == 0 {
    raise fail("invalid task progress: " + source)
  }
  let scaled = numerator * 100
  let quotient = scaled / denominator
  let remainder = scaled % denominator
  let rounded = if remainder * 2 > denominator ||
    (remainder * 2 == denominator && quotient % 2 == 1) {
    quotient + 1
  } else {
    quotient
  }
  let result = rounded * sign
  if result < 0 || result > 10000 {
    raise fail("task progress outside 0..10000 bps: " + result.to_string())
  }
  result
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn sorted_reasons(values : Array[String]) -> Json {
  let unique : Array[String] = []
  for value in values {
    let mut found = false
    for existing in unique {
      if existing == value {
        found = true
      }
    }
    if !found {
      unique.push(value)
    }
  }
  unique.sort_by(fn(left, right) { left.compare(right) })
  Json::array(unique.map(fn(value) { Json::string(value) }))
}

///|
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    String(value) => !value.is_empty()
    Number(value, ..) => value != 0.0
    _ => true
  }
}

///|
fn task_row(
  value : Json,
  project_id : String,
) -> TaskRow raise TaskPromotionPlanError {
  let task_id = text(field(value, "task_guid"))
  let parent_raw = field(value, "parent_task_guid")
  let parent_id = if truthy(parent_raw) { text(parent_raw) } else { "" }
  let progress = progress_bps(
    field_or(value, "progress_pct", Json::number(0.0, repr="0.0")),
  )
  let sort_order = integer(field_or(value, "sort_order", number(0L)), 0L)
  let candidate = Json::object({
    "task_guid": Json::string(task_id),
    "proj_guid": Json::string(project_id),
    "bu_guid": Json::string(text(field(value, "bu_guid"))),
    "parent_task_guid": if parent_id.is_empty() {
      Json::null()
    } else {
      Json::string(parent_id)
    },
    "task_code": field(value, "task_code"),
    "task_name": field(value, "task_name"),
    "task_type": field(value, "task_type"),
    "plan_begin_date": field(value, "plan_begin_date"),
    "plan_end_date": field(value, "plan_end_date"),
    "actual_begin_date": field(value, "actual_begin_date"),
    "actual_end_date": field(value, "actual_end_date"),
    "progress_bps": number(progress),
    "owner_guid": field(value, "owner_guid"),
    "status": field(value, "status"),
    "sort_order": number(sort_order),
  })
  TaskRow::{ json: candidate, task_id, parent_id, sort_order }
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise TaskPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let projects = match read_json(export_dir + "/tables/ep_project.json") {
    Array(values) => values
    _ => raise fail("project export must be an array")
  }
  let tasks = match read_json(export_dir + "/tables/jd_task.json") {
    Array(values) => values
    _ => raise fail("task export must be an array")
  }
  let project_items : Array[Json] = []
  let task_items : Array[Json] = []
  for project in projects {
    let project_id = text(field(project, "proj_guid"))
    let bu_id = text(field(project, "bu_guid"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let project_reasons : Array[String] = []
    if !truthy(principal) {
      project_reasons.push("missing_principal_by_bu")
    }
    project_items.push(
      Json::object({
        "source_table": Json::string("ep_project"),
        "source_id": Json::string(project_id),
        "target_type": Json::string("project"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if project_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": Json::array(
          project_reasons.map(fn(value) { Json::string(value) }),
        ),
        "warnings": Json::array([]),
        "target_candidate": if project_reasons.is_empty() {
          Json::object({
            "project_id": Json::string(project_id),
            "principal_id": principal,
            "authority_scope": Json::string("project:" + project_id),
            "code": field(project, "proj_code"),
            "name": field(project, "proj_name"),
            "business_unit_id": Json::string(bu_id),
          })
        } else {
          Json::null()
        },
      }),
    )
    let rows : Array[TaskRow] = []
    for task in tasks {
      if text(field(task, "proj_guid")) == project_id {
        rows.push(task_row(task, project_id))
      }
    }
    rows.sort_by(fn(left, right) {
      let order = left.sort_order.compare(right.sort_order)
      if order == 0 {
        left.task_id.compare(right.task_id)
      } else {
        order
      }
    })
    let reasons : Array[String] = []
    if !truthy(principal) {
      reasons.push("missing_principal_by_bu")
    }
    if rows.is_empty() {
      reasons.push("missing_tasks")
    }
    let seen : Map[String, Bool] = {}
    for row in rows {
      if row.task_id.is_empty() || seen.get(row.task_id) is Some(_) {
        reasons.push("duplicate_task_id:" + row.task_id)
      }
      seen.set(row.task_id, true)
    }
    for row in rows {
      if !row.parent_id.is_empty() && seen.get(row.parent_id) is None {
        reasons.push("missing_parent_task:" + row.parent_id)
      }
    }
    let candidate_rows = rows.map(fn(row) { row.json })
    task_items.push(
      Json::object({
        "source_table": Json::string("jd_task"),
        "source_id": Json::string(project_id),
        "target_type": Json::string("project_task_plan"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array([
          Json::string(
            "source status/progress remains in the typed envelope; only structure is promoted",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          Json::object({
            "project_id": Json::string(project_id),
            "principal_id": principal,
            "authority_scope": Json::string("project:" + project_id),
            "rows": Json::array(candidate_rows),
          })
        } else {
          Json::null()
        },
      }),
    )
  }
  let items : Array[Json] = []
  for item in project_items {
    items.push(item)
  }
  for item in task_items {
    items.push(item)
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  let mapping_version = match config.get("mapping_version") {
    Some(value) => value
    None => Json::string("unversioned-task-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.task-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha),
    "source_sha256": Json::string(source_sha),
    "mapping_version": mapping_version,
    "summary": Json::object({
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TaskPromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: task_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    TaskPromotionPlanError::InvalidInput(message) => {
      println("task promotion plan failed: " + message)
      @sys.exit(1)
    }
    TaskPromotionPlanError::Io(_) => {
      println("task promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
