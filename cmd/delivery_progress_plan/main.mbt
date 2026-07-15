///|
/// Build a fail-closed plan for draft delivery-progress intake. A task report
/// is evidence only; the native importer creates Draft progress reports.
pub(all) suberror DeliveryProgressPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> DeliveryProgressPlanError {
  DeliveryProgressPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise DeliveryProgressPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise DeliveryProgressPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise DeliveryProgressPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    Some(String(value)) => value
    Some(Number(value, ..)) => value.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => ""
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise DeliveryProgressPlanError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn root_array(
  value : Json,
  path : String,
) -> Array[Json] raise DeliveryProgressPlanError {
  match value {
    Array(values) => values
    _ => raise fail("expected array at " + path)
  }
}

///|
fn json_int(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_int_value(value : Json) -> Int64? {
  match value {
    Number(number, ..) if number == number.trunc() =>
      Some(number.to_int().to_int64())
    _ => None
  }
}

///|
fn non_empty(value : Json) -> Bool {
  match value {
    String(text) => !text.trim().is_empty()
    _ => false
  }
}

///|
fn parse_progress_bps(value : Json) -> Int64 raise DeliveryProgressPlanError {
  let source = match value {
    String(text) => text.trim()
    Number(number, ..) => number.to_string()
    _ => raise fail("invalid progress percentage")
  }
  if source.is_empty() {
    raise fail("invalid progress percentage")
  }
  let mut sign : Int64 = 1
  let mut index = 0
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut whole : Int64 = 0
  let mut fractional : Int64 = 0
  let mut denominator : Int64 = 1
  let mut after_decimal = false
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char == '.' {
      if after_decimal {
        raise fail("invalid progress percentage: " + source.to_owned())
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      let digit = (char.to_int() - '0'.to_int()).to_int64()
      if after_decimal {
        fractional = fractional * 10 + digit
        denominator *= 10
      } else {
        whole = whole * 10 + digit
      }
    } else {
      raise fail("invalid progress percentage: " + source.to_owned())
    }
    index += 1
  }
  let numerator = whole * 100 * denominator + fractional * 100
  let scaled = numerator / denominator
  let remainder = numerator % denominator
  let rounded = if remainder * 2 > denominator ||
    (remainder * 2 == denominator && scaled % 2 != 0) {
    scaled + 1
  } else {
    scaled
  }
  let result = rounded * sign
  if result < 0 || result > 10000 {
    raise fail("progress outside 0..10000 bps: " + result.to_string())
  }
  result
}

///|
fn sorted_reasons(reasons : Array[String]) -> Array[Json] {
  let ordered = [
    "incomplete_principal_or_scope_mapping", "invalid_currency_mapping", "missing_evidence_mapping",
    "missing_migration_actor", "missing_or_duplicate_report_id", "missing_report_mapping",
    "missing_task", "missing_target_project", "missing_or_negative_completed_value",
    "task_project_mismatch", "unknown_target_project",
  ]
  let result : Array[Json] = []
  for value in ordered {
    if reasons.contains(value) {
      result.push(Json::string(value))
    }
  }
  for value in reasons {
    if !ordered.contains(value) {
      result.push(Json::string(value))
    }
  }
  result
}

///|
fn add_reason(reasons : Array[String], reason : String) -> Unit {
  if !reasons.contains(reason) {
    reasons.push(reason)
  }
}

///|
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise DeliveryProgressPlanError {
  let export_root = export_path
  let manifest = object(read_json(export_root + "/manifest.json"), "manifest")
  let source_sha256 = required_string(manifest, "source_sha256", "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let report_mappings = match config.get("report_by_id") {
    None => {}
    Some(Object(values)) => values
    Some(_) => raise fail("report_by_id must be an object")
  }
  let reports = root_array(
    read_json(export_root + "/tables/jd_task_report.json"),
    "reports",
  )
  let tasks = root_array(
    read_json(export_root + "/tables/jd_task.json"),
    "tasks",
  )
  let projects = root_array(
    read_json(export_root + "/tables/ep_project.json"),
    "projects",
  )
  let task_by_id : Map[String, Json] = {}
  for value in tasks {
    let _ = object(value, "task row")
    task_by_id.set(text(value, "task_guid"), value)
  }
  let project_ids : Array[String] = []
  for value in projects {
    let _ = object(value, "project row")
    project_ids.push(text(value, "proj_guid"))
  }
  let items : Array[Json] = []
  let seen : Array[String] = []
  let mut ready = 0
  for row_value in reports {
    let _ = object(row_value, "task report row")
    let report_id = text(row_value, "report_guid")
    let reasons : Array[String] = []
    if report_id.is_empty() || seen.contains(report_id) {
      add_reason(reasons, "missing_or_duplicate_report_id")
    }
    seen.push(report_id)
    let mapping = match report_mappings.get(report_id) {
      Some(Object(values)) => values
      _ => {
        add_reason(reasons, "missing_report_mapping")
        {}
      }
    }
    let task_id = text(row_value, "task_guid")
    let task = task_by_id.get(task_id)
    if task is None {
      add_reason(reasons, "missing_task")
    }
    let source_project_id = match task {
      Some(value) => text(value, "proj_guid")
      None => ""
    }
    let project_id = match mapping.get("project_id") {
      Some(value) => value
      None => Json::null()
    }
    if !non_empty(project_id) {
      add_reason(reasons, "missing_target_project")
    } else if !project_ids.contains(text_value(project_id)) {
      add_reason(reasons, "unknown_target_project")
    } else if source_project_id != text_value(project_id) {
      add_reason(reasons, "task_project_mismatch")
    }
    let principal_id = mapping.get("principal_id").unwrap_or(Json::null())
    let project_scope = mapping.get("project_scope").unwrap_or(Json::null())
    if !non_empty(principal_id) || !non_empty(project_scope) {
      add_reason(reasons, "incomplete_principal_or_scope_mapping")
    }
    let currency = mapping.get("currency").unwrap_or(Json::null())
    if !non_empty(currency) || text_value(currency).length() != 3 {
      add_reason(reasons, "invalid_currency_mapping")
    }
    let amount = mapping.get("completed_value_minor").unwrap_or(Json::null())
    match json_int_value(amount) {
      Some(value) if value >= 0 => ()
      _ => add_reason(reasons, "missing_or_negative_completed_value")
    }
    let evidence_ids = match mapping.get("evidence_ids") {
      Some(Array(values)) => {
        let mut valid = !values.is_empty()
        for value in values {
          if !non_empty(value) {
            valid = false
          }
        }
        if valid {
          Json::array(values)
        } else {
          Json::null()
        }
      }
      _ => Json::null()
    }
    if evidence_ids is Null {
      add_reason(reasons, "missing_evidence_mapping")
    }
    let actor_id = mapping.get("actor_id").unwrap_or(Json::string("migration"))
    if !non_empty(actor_id) {
      add_reason(reasons, "missing_migration_actor")
    }
    let progress = parse_progress_bps(
      field(row_value, "progress_pct").unwrap_or(Json::null()),
    ) catch {
      DeliveryProgressPlanError::InvalidInput(message) => {
        add_reason(reasons, message)
        0L
      }
      DeliveryProgressPlanError::Io(_) => 0L
    }
    let target_candidate = Json::object({
      "report_id": Json::string(report_id),
      "task_id": Json::string(task_id),
      "project_id": project_id,
      "principal_id": principal_id,
      "project_scope": project_scope,
      "progress_bps": json_int(progress),
      "completed_value_minor": amount,
      "currency": currency,
      "evidence_ids": evidence_ids,
      "actor_id": actor_id,
      "reported_on": field(row_value, "report_date").unwrap_or(Json::null()),
      "summary": field(row_value, "summary").unwrap_or(Json::null()),
      "source_operator_id": field(row_value, "operator_guid").unwrap_or(
        Json::null(),
      ),
      "state_policy": Json::string("draft_only"),
    })
    if reasons.is_empty() {
      ready += 1
    }
    items.push(
      Json::object({
        "source_table": Json::string("jd_task_report"),
        "source_id": Json::string(report_id),
        "target_type": Json::string("progress_report"),
        "target_id": Json::string(report_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": Json::array(sorted_reasons(reasons)),
        "warnings": Json::array([
          Json::string(
            "native import creates Draft only; source report does not prove submission or acceptance",
          ),
          Json::string(
            "accounting recognition, cash, cost consumption, and task-state mutation remain separate gates",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          target_candidate
        } else {
          Json::null()
        },
      }),
    )
  }
  let mapping_version = match config.get("mapping_version") {
    Some(value) => text_value(value)
    None => "unversioned-delivery-progress-map"
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.delivery-progress-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": Json::string(mapping_version),
    "summary": Json::object({
      "items": json_int(items.length().to_int64()),
      "ready": json_int(ready.to_int64()),
      "quarantined": json_int((items.length() - ready).to_int64()),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise DeliveryProgressPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": json_int(items.length().to_int64()),
      "ready": json_int(ready.to_int64()),
      "quarantined": json_int((items.length() - ready).to_int64()),
    }).stringify(),
  )
}

///|
fn text_value(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: delivery_progress_plan <export> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    DeliveryProgressPlanError::InvalidInput(message) => {
      println("delivery-progress promotion plan failed: " + message)
      @sys.exit(1)
    }
    DeliveryProgressPlanError::Io(_) => {
      println("delivery-progress promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
