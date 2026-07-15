///|
pub(all) suberror TaskStatePromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct TaskRow {
  json : Json
  task_id : String
  parent_id : String
  status : String
  progress_bps : Int64
  sort_order : Int64
}

///|
fn fail(message : String) -> TaskStatePromotionPlanError {
  TaskStatePromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TaskStatePromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaskStatePromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TaskStatePromotionPlanError {
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
fn array(
  value : Json,
  path : String,
) -> Array[Json] raise TaskStatePromotionPlanError {
  match value {
    Array(values) => values
    _ => raise fail("expected array at " + path)
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    Null => ""
    _ => ""
  }
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) => number.to_int().to_int64()
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
fn progress_bps(value : Json) -> Int64 raise TaskStatePromotionPlanError {
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
fn task_row(
  value : Json,
  project_id : String,
) -> TaskRow raise TaskStatePromotionPlanError {
  let task_id = text(field(value, "task_guid"))
  let parent_id = text(field(value, "parent_task_guid"))
  let status = text(field(value, "status"))
  let progress = progress_bps(
    field_or(value, "progress_pct", Json::number(0.0, repr="0.0")),
  )
  let sort_order = integer(field_or(value, "sort_order", number(0L)), 0L)
  let candidate = Json::object({
    "task_guid": Json::string(task_id),
    "proj_guid": Json::string(project_id),
    "bu_guid": Json::string(text(field(value, "bu_guid"))),
    "parent_task_guid": field(value, "parent_task_guid"),
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
  TaskRow::{
    json: candidate,
    task_id,
    parent_id,
    status,
    progress_bps: progress,
    sort_order,
  }
}

///|
fn clone_strings(values : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(value)
  }
  result
}

///|
fn sorted_reason_json(values : Array[String]) -> Json {
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
fn project_item(
  project : Json,
  project_id : String,
  bu_id : String,
  principal : Json,
  reasons : Array[String],
) -> Json {
  Json::object({
    "source_table": Json::string("ep_project"),
    "source_id": Json::string(project_id),
    "target_type": Json::string("project"),
    "target_id": Json::string(project_id),
    "disposition": Json::string(
      if reasons.is_empty() {
        "ready_for_domain_import"
      } else {
        "quarantined"
      },
    ),
    "reasons": Json::array(reasons.map(fn(value) { Json::string(value) })),
    "warnings": Json::array([]),
    "target_candidate": if reasons.is_empty() {
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
  })
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
  project_filter : String?,
) -> Unit raise TaskStatePromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let all_projects = array(
    read_json(export_dir + "/tables/ep_project.json"),
    "projects",
  )
  let tasks = array(read_json(export_dir + "/tables/jd_task.json"), "tasks")
  let projects : Array[Json] = []
  for project in all_projects {
    let project_id = text(field(project, "proj_guid"))
    match project_filter {
      Some(filter) if project_id == filter => projects.push(project)
      Some(_) => ()
      None => projects.push(project)
    }
  }
  match project_filter {
    Some(filter) if projects.is_empty() =>
      raise fail("project not found: " + filter)
    _ => ()
  }
  let project_items : Array[Json] = []
  let structure_items : Array[Json] = []
  let state_items : Array[Json] = []
  for project in projects {
    let project_id = text(field(project, "proj_guid"))
    let bu_id = text(field(project, "bu_guid"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let principal_present = match principal {
      Null => false
      String(value) => !value.is_empty()
      False => false
      _ => true
    }
    let project_reasons : Array[String] = []
    if !principal_present {
      project_reasons.push("missing_principal_by_bu")
    }
    project_items.push(
      project_item(project, project_id, bu_id, principal, project_reasons),
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
    let candidate_rows : Array[Json] = rows.map(fn(row) { row.json })
    let ids : Map[String, Bool] = {}
    for row in rows {
      ids.set(row.task_id, true)
    }

    let structure_reasons = clone_strings(project_reasons)
    if rows.is_empty() {
      structure_reasons.push("missing_tasks")
    }
    for row in rows {
      if !row.parent_id.is_empty() && ids.get(row.parent_id) is None {
        structure_reasons.push("missing_parent_task:" + row.parent_id)
      }
    }
    structure_items.push(
      Json::object({
        "source_table": Json::string("jd_task"),
        "source_id": Json::string(project_id),
        "target_type": Json::string("project_task_plan"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if structure_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reason_json(structure_reasons),
        "warnings": Json::array([
          Json::string("task state is replayed by a separate dependency gate"),
        ]),
        "target_candidate": if structure_reasons.is_empty() {
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

    let state_reasons = clone_strings(project_reasons)
    let completed : Map[String, Bool] = {}
    let seen : Map[String, Bool] = {}
    for row in rows {
      if row.task_id.is_empty() || seen.get(row.task_id) is Some(_) {
        state_reasons.push("duplicate_or_missing_task:" + row.task_id)
      }
      seen.set(row.task_id, true)
      if !row.parent_id.is_empty() && ids.get(row.parent_id) is None {
        state_reasons.push("missing_parent_task:" + row.parent_id)
      }
      match row.status {
        "pending" =>
          if row.progress_bps != 0 {
            state_reasons.push("pending_task_has_progress:" + row.task_id)
          }
        "in_progress" | "done" | "blocked" => {
          if !row.parent_id.is_empty() && completed.get(row.parent_id) is None {
            state_reasons.push(
              "dependency_not_completed:" + row.task_id + ":" + row.parent_id,
            )
          }
          if row.status == "done" {
            if row.progress_bps != 10000 {
              state_reasons.push("done_task_not_complete:" + row.task_id)
            } else {
              completed.set(row.task_id, true)
            }
          } else if row.status == "in_progress" {
            if row.progress_bps >= 10000 {
              state_reasons.push("in_progress_task_complete:" + row.task_id)
            }
          } else if row.progress_bps >= 10000 {
            state_reasons.push("blocked_task_complete:" + row.task_id)
          }
        }
        _ =>
          state_reasons.push(
            "invalid_task_status:" + row.task_id + ":" + row.status,
          )
      }
    }
    state_items.push(
      Json::object({
        "source_table": Json::string("jd_task"),
        "source_id": Json::string("state:" + project_id),
        "target_type": Json::string("project_task_state"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if state_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reason_json(state_reasons),
        "warnings": Json::array([
          Json::string(
            "state replay is accepted only when dependencies are completed in target order",
          ),
        ]),
        "observed_rows": Json::array(candidate_rows),
        "target_candidate": if state_reasons.is_empty() {
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
  for item in structure_items {
    items.push(item)
  }
  for item in state_items {
    items.push(item)
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  if source_sha.is_empty() {
    raise fail("manifest.source_sha256 must be present")
  }
  let mapping_version = field_or(
    Json::object(config),
    "mapping_version",
    Json::string("unversioned-task-state-map"),
  )
  let report = Json::object({
    "format": Json::string("moonproj.erp.task-state-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha),
    "source_sha256": Json::string(source_sha),
    "mapping_version": mapping_version,
    "summary": Json::object({
      "items": number(items.length().to_int64()),
      "ready": number(ready.to_int64()),
      "quarantined": number((items.length() - ready).to_int64()),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TaskStatePromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "quarantined": number((items.length() - ready).to_int64()),
      "ready": number(ready.to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: task_state_promotion_plan <export> <mapping> <output> [--project-id <id>]",
    )
    @sys.exit(2)
  }
  let mut filter : String? = None
  if args.length() >= 6 && args[4] == "--project-id" {
    filter = Some(args[5])
  }
  run(args[1], args[2], args[3], filter) catch {
    TaskStatePromotionPlanError::InvalidInput(message) => {
      println("task-state promotion plan failed: " + message)
      @sys.exit(1)
    }
    TaskStatePromotionPlanError::Io(_) => {
      println("task-state promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
