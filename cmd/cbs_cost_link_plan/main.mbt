///|
struct Subject {
  subject_id : String
  code : String
  name : String
  parent_code : String
  target_minor : Int64
}

///|
struct ProjectConfig {
  version_id : String
  principal_id : String
  project_scope : String
  amount_field : String
  currency : String
  subjects : Array[Subject]
  subjects_by_source : Map[String, Subject]
}

///|
pub(all) suberror CbsCostLinkPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> CbsCostLinkPlanError {
  CbsCostLinkPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise CbsCostLinkPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise CbsCostLinkPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise CbsCostLinkPlanError {
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
fn required_string(
  value : Json,
  key : String,
) -> String raise CbsCostLinkPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim()
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
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), default)
    _ => default
  }
}

///|
fn power10(digits : Int) -> Int64 {
  let mut result : Int64 = 1
  for _ in 0..<digits {
    result *= 10
  }
  result
}

///|
fn money_minor(
  value : Json,
  currency : String,
  policy : Map[String, Json],
) -> Int64 raise CbsCostLinkPlanError {
  if currency.length() != 3 {
    raise fail("invalid currency: " + currency)
  }
  let source = text(value).trim()
  if source.is_empty() {
    raise fail("invalid monetary value")
  }
  let scale = integer(field(Json::object(policy), "minor_units_per_unit"), 100L)
  if scale <= 0 {
    raise fail(
      "money policy must declare positive scale and half_even rounding",
    )
  }
  match field(Json::object(policy), "rounding") {
    Null => ()
    String(value) if value == "half_even" => ()
    _ =>
      raise fail(
        "money policy must declare positive scale and half_even rounding",
      )
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
  let mut whole : Int64 = 0
  let mut fraction : Int64 = 0
  let mut digits = 0
  let mut after_decimal = false
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char == '.' {
      if after_decimal {
        raise fail("invalid monetary value: " + source.to_owned())
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      let digit = (char.to_int() - '0'.to_int()).to_int64()
      if after_decimal {
        fraction = fraction * 10 + digit
        digits += 1
      } else {
        whole = whole * 10 + digit
      }
    } else {
      raise fail("invalid monetary value: " + source.to_owned())
    }
    index += 1
  }
  let denominator = power10(digits)
  let numerator = (whole * denominator + fraction) * scale
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  let rounded = if remainder * 2 > denominator ||
    (remainder * 2 == denominator && quotient % 2 != 0) {
    quotient + 1
  } else {
    quotient
  }
  let result = rounded * sign
  let allow_rounding = match field(Json::object(policy), "allow_rounding") {
    True => true
    _ => false
  }
  if !allow_rounding && remainder != 0 {
    raise fail("amount requires rounding: " + source.to_owned())
  }
  if result <= 0 {
    raise fail("amount must be positive: " + source.to_owned())
  }
  result
}

///|
fn subject_json(subject : Subject) -> Json {
  Json::object({
    "subject_id": Json::string(subject.subject_id),
    "code": Json::string(subject.code),
    "name": Json::string(subject.name),
    "parent_code": Json::string(subject.parent_code),
    "target_minor": Json::number(
      subject.target_minor.to_double(),
      repr=subject.target_minor.to_string(),
    ),
  })
}

///|
fn sorted_reasons(values : Array[String]) -> Array[Json] {
  let ordered = values.copy()
  ordered.sort_by(fn(left, right) { left.compare(right) })
  ordered.map(fn(value) { Json::string(value) })
}

///|
fn add_reason(values : Array[String], reason : String) -> Unit {
  if !values.contains(reason) {
    values.push(reason)
  }
}

///|
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise CbsCostLinkPlanError {
  let manifest = object(read_json(export_path + "/manifest.json"), "manifest")
  let source_sha256 = required_string(
    field(Json::object(manifest), "source_sha256"),
    "source_sha256",
  )
  if source_sha256.length() != 64 {
    raise fail("export manifest has no valid source hash")
  }
  let rows = match read_json(export_path + "/tables/cb_cost.json") {
    Array(values) => values
    _ => raise fail("cb_cost export is not an object array")
  }
  let config = object(read_json(mapping_path), "CBS mapping")
  let projects = object(
    field(Json::object(config), "cbs_by_project"),
    "cbs_by_project",
  )
  if projects.is_empty() {
    raise fail("cbs_by_project must be a non-empty object")
  }
  let policy = object(
    field(Json::object(config), "money_policy"),
    "money_policy",
  ) catch {
    CbsCostLinkPlanError::InvalidInput(_) => {}
    CbsCostLinkPlanError::Io(_) => {}
  }
  let plan_by_project : Map[String, ProjectConfig] = {}
  let seen_versions : Array[String] = []
  for project_id, raw_value in projects {
    let raw = object(raw_value, "CBS project mapping")
    let version_id = required_string(
      field(Json::object(raw), "version_id"),
      "version_id",
    )
    if seen_versions.contains(version_id) {
      raise fail("duplicate CBS version_id across projects: " + version_id)
    }
    seen_versions.push(version_id)
    let principal_id = required_string(
      field(Json::object(raw), "principal_id"),
      "principal_id",
    )
    let project_scope = required_string(
      field(Json::object(raw), "project_scope"),
      "project_scope",
    )
    let amount_field = required_string(
      field(Json::object(raw), "amount_field"),
      "amount_field",
    )
    let currency = required_string(
      field(Json::object(raw), "currency"),
      "currency",
    )
    if project_scope != "project:" + project_id {
      raise fail("CBS project scope does not match project: " + project_id)
    }
    let raw_subjects = object(
      field(Json::object(raw), "subject_by_cost_code"),
      "subject_by_cost_code",
    )
    if raw_subjects.is_empty() {
      raise fail("subject_by_cost_code must be non-empty: " + project_id)
    }
    let subjects : Array[Subject] = []
    let subjects_by_source : Map[String, Subject] = {}
    let seen_codes : Array[String] = []
    for source_code, subject_value in raw_subjects {
      let subject_obj = object(subject_value, "subject mapping")
      let subject = Subject::{
        subject_id: required_string(
          field(Json::object(subject_obj), "subject_id"),
          "subject_id",
        ),
        code: required_string(field(Json::object(subject_obj), "code"), "code"),
        name: required_string(field(Json::object(subject_obj), "name"), "name"),
        parent_code: text(field(Json::object(subject_obj), "parent_code")),
        target_minor: integer(
          field(Json::object(subject_obj), "target_minor"),
          0L,
        ),
      }
      if subject.target_minor < 0 {
        raise fail("negative subject target: " + project_id + "/" + source_code)
      }
      if seen_codes.contains(subject.code) {
        raise fail(
          "duplicate target subject code: " + project_id + "/" + subject.code,
        )
      }
      seen_codes.push(subject.code)
      subjects.push(subject)
      subjects_by_source.set(source_code, subject)
    }
    subjects.sort_by(fn(left, right) { left.code.compare(right.code) })
    plan_by_project.set(project_id, ProjectConfig::{
      version_id,
      principal_id,
      project_scope,
      amount_field,
      currency,
      subjects,
      subjects_by_source,
    })
  }
  let items : Array[Json] = []
  let mut ready = 0
  for row_value in rows {
    let row = object(row_value, "cb_cost row")
    let source_id = text(field(Json::object(row), "cost_guid"))
    let project_id = text(field(Json::object(row), "proj_guid"))
    let cost_code = text(field(Json::object(row), "cost_code"))
    let target_id = "cbs-link:" + source_id
    let reasons : Array[String] = []
    if source_id.is_empty() || project_id.is_empty() || cost_code.is_empty() {
      add_reason(reasons, "missing_cost_identity")
    }
    let project_config = plan_by_project.get(project_id)
    if project_config is None {
      add_reason(reasons, "missing_cbs_project_mapping")
    }
    let subject = match project_config {
      Some(value) => value.subjects_by_source.get(cost_code)
      None => None
    }
    if subject is None && project_config is Some(_) {
      add_reason(reasons, "missing_cbs_subject_mapping")
    }
    let mut amount_minor : Int64? = None
    let currency = match project_config {
      Some(value) => value.currency
      None => ""
    }
    match project_config {
      Some(value) =>
        amount_minor = Some(
          money_minor(
            field(Json::object(row), value.amount_field),
            currency,
            policy,
          ) catch {
            CbsCostLinkPlanError::InvalidInput(message) => {
              add_reason(reasons, message)
              0L
            }
            CbsCostLinkPlanError::Io(_) => 0L
          },
        )
      None => ()
    }
    let candidate = match (project_config, subject, amount_minor) {
      (Some(value), Some(subject), Some(amount)) if reasons.is_empty() => {
        let subjects_json = value.subjects.map(fn(subject) {
          subject_json(subject)
        })
        Some(
          Json::object({
            "link_id": Json::string(target_id),
            "source_id": Json::string(source_id),
            "version_id": Json::string(value.version_id),
            "project_scope": Json::string(value.project_scope),
            "subject_code": Json::string(subject.code),
            "principal_id": Json::string(value.principal_id),
            "amount_minor": Json::number(
              amount.to_double(),
              repr=amount.to_string(),
            ),
            "currency": Json::string(value.currency),
            "cbs_version": Json::object({
              "version_id": Json::string(value.version_id),
              "project_scope": Json::string(value.project_scope),
              "principal_id": Json::string(value.principal_id),
              "subjects": Json::array(subjects_json),
            }),
          }),
        )
      }
      _ => None
    }
    if candidate is Some(_) && reasons.is_empty() {
      ready += 1
    }
    items.push(
      Json::object({
        "source_table": Json::string("cb_cost"),
        "source_id": Json::string(source_id),
        "target_type": Json::string("cbs_cost_link"),
        "target_id": Json::string(target_id),
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
            "CBS link allocates a source amount only; it does not consume budget or post accounting",
          ),
        ]),
        "target_candidate": match candidate {
          Some(value) => value
          None => Json::null()
        },
      }),
    )
  }
  let mapping_version = text(field(Json::object(config), "mapping_version"))
  let mapping_version = if mapping_version.is_empty() {
    "unversioned-cbs-cost-map"
  } else {
    mapping_version
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.cbs-cost-link-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": Json::string(mapping_version),
    "cohort": Json::string("cbs-cost-links-v1"),
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
    error => raise CbsCostLinkPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: cbs_cost_link_plan <export> <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    CbsCostLinkPlanError::InvalidInput(message) => {
      println("CBS cost-link plan failed: " + message)
      @sys.exit(1)
    }
    CbsCostLinkPlanError::Io(_) => {
      println("CBS cost-link plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
