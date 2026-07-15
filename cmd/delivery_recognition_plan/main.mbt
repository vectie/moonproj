///|
pub(all) suberror DeliveryRecognitionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> DeliveryRecognitionPlanError {
  DeliveryRecognitionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise DeliveryRecognitionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise DeliveryRecognitionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise DeliveryRecognitionPlanError {
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
fn text(value : Json, key : String) -> String {
  text_value(field(value, key).unwrap_or(Json::null()))
}

///|
fn non_empty(value : Json) -> Bool {
  match value {
    String(value) => !value.trim().is_empty()
    _ => false
  }
}

///|
fn root_array(
  value : Json,
  path : String,
) -> Array[Json] raise DeliveryRecognitionPlanError {
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
fn integer(value : Json) -> Int64? {
  match value {
    Number(number, ..) if number == number.trunc() =>
      Some(number.to_int().to_int64())
    _ => None
  }
}

///|
fn progress_bps(value : Json) -> Int64 raise DeliveryRecognitionPlanError {
  let source = match value {
    String(value) => value.trim()
    Number(value, ..) => value.to_string()
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
fn valid_string_array(value : Json) -> Json? {
  match value {
    Array(values) if !values.is_empty() => {
      for item in values {
        if !non_empty(item) {
          return None
        }
      }
      Some(Json::array(values))
    }
    _ => None
  }
}

///|
fn add_reason(reasons : Array[String], reason : String) -> Unit {
  if !reasons.contains(reason) {
    reasons.push(reason)
  }
}

///|
fn sorted_reasons(reasons : Array[String]) -> Array[Json] {
  let values = reasons.copy()
  values.sort_by(fn(left, right) { left.compare(right) })
  let result : Array[Json] = []
  for value in values {
    result.push(Json::string(value))
  }
  result
}

///|
fn required_mapping_string(
  mapping : Map[String, Json],
  key : String,
  reasons : Array[String],
) -> Json {
  let value = mapping.get(key).unwrap_or(Json::null())
  if !non_empty(value) {
    add_reason(reasons, "missing_" + key)
  }
  value
}

///|
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise DeliveryRecognitionPlanError {
  let manifest = object(read_json(export_path + "/manifest.json"), "manifest")
  let source_sha256 = match manifest.get("source_sha256") {
    Some(String(value)) if value.length() == 64 => value
    _ => raise fail("export manifest has no valid source hash")
  }
  let config = object(read_json(mapping_path), "mapping")
  let mappings = match config.get("recognition_by_report") {
    None => {}
    Some(Object(values)) => values
    Some(_) => raise fail("recognition_by_report must be an object")
  }
  let reports = root_array(
    read_json(export_path + "/tables/jd_task_report.json"),
    "reports",
  )
  let tasks = root_array(
    read_json(export_path + "/tables/jd_task.json"),
    "tasks",
  )
  let projects = root_array(
    read_json(export_path + "/tables/ep_project.json"),
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
  for row in reports {
    let _ = object(row, "task report row")
    let report_id = text(row, "report_guid")
    let reasons : Array[String] = []
    if report_id.is_empty() || seen.contains(report_id) {
      add_reason(reasons, "missing_or_duplicate_report_id")
    }
    seen.push(report_id)
    let mapping = match mappings.get(report_id) {
      Some(Object(values)) => values
      _ => {
        add_reason(reasons, "missing_recognition_mapping")
        {}
      }
    }
    let task_id = text(row, "task_guid")
    let task = task_by_id.get(task_id)
    if task is None {
      add_reason(reasons, "missing_task")
    }
    let source_project_id = match task {
      Some(value) => text(value, "proj_guid")
      None => ""
    }
    let project_id = mapping.get("project_id").unwrap_or(Json::null())
    if !non_empty(project_id) {
      add_reason(reasons, "missing_target_project")
    } else if !project_ids.contains(text_value(project_id)) {
      add_reason(reasons, "unknown_target_project")
    } else if source_project_id != text_value(project_id) {
      add_reason(reasons, "task_project_mismatch")
    }
    if text_value(mapping.get("review_state").unwrap_or(Json::null())) !=
      "accepted" {
      add_reason(reasons, "missing_reviewed_acceptance")
    }
    if text_value(mapping.get("amount_basis").unwrap_or(Json::null())) !=
      "reviewed_measurement" {
      add_reason(reasons, "missing_reviewed_amount_basis")
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
    match integer(amount) {
      Some(value) if value > 0 => ()
      _ => add_reason(reasons, "missing_or_non_positive_completed_value")
    }
    let evidence_ids = match
      valid_string_array(mapping.get("evidence_ids").unwrap_or(Json::null())) {
      Some(value) => value
      None => {
        add_reason(reasons, "missing_progress_evidence_mapping")
        Json::null()
      }
    }
    let acceptance_evidence_ids = match
      valid_string_array(
        mapping.get("acceptance_evidence_ids").unwrap_or(Json::null()),
      ) {
      Some(value) => value
      None => {
        add_reason(reasons, "missing_acceptance_evidence_mapping")
        Json::null()
      }
    }
    let recognition_id = required_mapping_string(
      mapping, "recognition_id", reasons,
    )
    let acceptance_id = required_mapping_string(
      mapping, "acceptance_id", reasons,
    )
    let accepted_by = required_mapping_string(mapping, "accepted_by", reasons)
    let created_by = required_mapping_string(mapping, "created_by", reasons)
    let contract_asset_account = required_mapping_string(
      mapping, "contract_asset_account", reasons,
    )
    let revenue_account = required_mapping_string(
      mapping, "revenue_account", reasons,
    )
    let bps = progress_bps(field(row, "progress_pct").unwrap_or(Json::null())) catch {
      DeliveryRecognitionPlanError::InvalidInput(message) => {
        add_reason(reasons, message)
        0L
      }
      DeliveryRecognitionPlanError::Io(_) => 0L
    }
    let candidate = Json::object({
      "recognition_id": recognition_id,
      "report_id": Json::string(report_id),
      "task_id": Json::string(task_id),
      "project_id": project_id,
      "principal_id": principal_id,
      "project_scope": project_scope,
      "progress_bps": json_int(bps),
      "completed_value_minor": amount,
      "amount_basis": mapping.get("amount_basis").unwrap_or(Json::null()),
      "currency": currency,
      "evidence_ids": evidence_ids,
      "acceptance_id": acceptance_id,
      "acceptance_evidence_ids": acceptance_evidence_ids,
      "accepted_by": accepted_by,
      "created_by": created_by,
      "contract_asset_account": contract_asset_account,
      "revenue_account": revenue_account,
      "review_state": mapping.get("review_state").unwrap_or(Json::null()),
      "reported_on": field(row, "report_date").unwrap_or(Json::null()),
      "summary": field(row, "summary").unwrap_or(Json::null()),
      "source_operator_id": field(row, "operator_guid").unwrap_or(Json::null()),
    })
    let disposition = if reasons.is_empty() {
      ready += 1
      "ready_for_domain_import"
    } else {
      "quarantined"
    }
    let target_id = if non_empty(recognition_id) {
      text_value(recognition_id)
    } else {
      "delivery-recognition:" + report_id
    }
    items.push(
      Json::object({
        "source_table": Json::string("jd_task_report"),
        "source_id": Json::string(report_id),
        "target_type": Json::string("delivery_recognition"),
        "target_id": Json::string(target_id),
        "disposition": Json::string(disposition),
        "reasons": Json::array(sorted_reasons(reasons)),
        "warnings": Json::array([
          Json::string(
            "recognition requires separately reviewed acceptance evidence",
          ),
          Json::string(
            "native import creates a pending-posting source-to-journal link; it does not post, release cash, determine tax, or close a period",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          candidate
        } else {
          Json::null()
        },
      }),
    )
  }
  let mapping_version = text_value(
    config
    .get("mapping_version")
    .unwrap_or(Json::string("unversioned-delivery-recognition-map")),
  )
  let report = Json::object({
    "format": Json::string(
      "moonproj.erp.delivery-recognition-promotion-plan.v1",
    ),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": Json::string(mapping_version),
    "cohort": Json::string("delivery-recognition-v1"),
    "summary": Json::object({
      "items": json_int(items.length().to_int64()),
      "ready": json_int(ready.to_int64()),
      "quarantined": json_int((items.length() - ready).to_int64()),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise DeliveryRecognitionPlanError::Io(error)
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
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: delivery_recognition_plan <export> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    DeliveryRecognitionPlanError::InvalidInput(message) => {
      println("delivery-recognition plan failed: " + message)
      @sys.exit(1)
    }
    DeliveryRecognitionPlanError::Io(_) => {
      println("delivery-recognition plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
