///|
struct Subject {
  subject_id : String
  code : String
  name : String
  parent_code : String
  target_minor : Int64
}

///|
pub(all) suberror CbsBudgetPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> CbsBudgetPlanError {
  CbsBudgetPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise CbsBudgetPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise CbsBudgetPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise CbsBudgetPlanError {
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
) -> String raise CbsBudgetPlanError {
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
) -> Int64 raise CbsBudgetPlanError {
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
  if currency.length() != 3 {
    raise fail("invalid currency: " + currency)
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
  if result < 0 {
    raise fail("amount must not be negative: " + source.to_owned())
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
fn run(
  export_path : String,
  cbs_mapping_path : String,
  budget_mapping_path : String,
  output_path : String,
) -> Unit raise CbsBudgetPlanError {
  let manifest = object(read_json(export_path + "/manifest.json"), "manifest")
  let source_sha256 = required_string(
    field(Json::object(manifest), "source_sha256"),
    "source_sha256",
  )
  if source_sha256.length() != 64 {
    raise fail("source_sha256 must be a 64-character hash")
  }
  let rows = match read_json(export_path + "/tables/cb_cost.json") {
    Array(values) => values
    _ => raise fail("cb_cost export must be an object array")
  }
  let cbs = object(read_json(cbs_mapping_path), "CBS mapping")
  let budget = object(read_json(budget_mapping_path), "budget mapping")
  let project_id = required_string(
    field(Json::object(budget), "project_id"),
    "project_id",
  )
  let amount_field = required_string(
    field(Json::object(budget), "budget_amount_field"),
    "budget_amount_field",
  )
  let reservation_prefix = required_string(
    field(Json::object(budget), "reservation_id_prefix"),
    "reservation_id_prefix",
  )
  let consume_by_source = object(
    field(Json::object(budget), "consume_by_source"),
    "consume_by_source",
  )
  let cbs_projects = object(
    field(Json::object(cbs), "cbs_by_project"),
    "cbs_by_project",
  )
  let project = object(
    cbs_projects.get(project_id).unwrap_or(Json::null()),
    "CBS project",
  ) catch {
    CbsBudgetPlanError::InvalidInput(_) =>
      raise fail("CBS mapping has no project: " + project_id)
    CbsBudgetPlanError::Io(_) =>
      raise fail("CBS mapping has no project: " + project_id)
  }
  let version_id = required_string(
    field(Json::object(project), "version_id"),
    "version_id",
  )
  let principal_id = required_string(
    field(Json::object(project), "principal_id"),
    "principal_id",
  )
  let project_scope = required_string(
    field(Json::object(project), "project_scope"),
    "project_scope",
  )
  if project_scope != "project:" + project_id {
    raise fail("project_scope must match project_id")
  }
  let currency = required_string(
    field(Json::object(project), "currency"),
    "currency",
  )
  if currency.length() != 3 {
    raise fail("currency must be an ISO-like three-letter code")
  }
  let raw_subjects = object(
    field(Json::object(project), "subject_by_cost_code"),
    "subject_by_cost_code",
  )
  if raw_subjects.is_empty() {
    raise fail("subject_by_cost_code must be a non-empty object")
  }
  let subjects : Array[Subject] = []
  let subjects_by_source : Map[String, Subject] = {}
  for source_code, raw_value in raw_subjects {
    let raw = object(raw_value, "subject mapping")
    let subject = Subject::{
      subject_id: required_string(
        field(Json::object(raw), "subject_id"),
        "subject_id",
      ),
      code: required_string(field(Json::object(raw), "code"), "code"),
      name: required_string(field(Json::object(raw), "name"), "name"),
      parent_code: text(field(Json::object(raw), "parent_code")),
      target_minor: integer(field(Json::object(raw), "target_minor"), 0L),
    }
    subjects.push(subject)
    subjects_by_source.set(source_code, subject)
  }
  subjects.sort_by(fn(left, right) { left.code.compare(right.code) })
  let policy = object(field(Json::object(cbs), "money_policy"), "money_policy") catch {
    CbsBudgetPlanError::InvalidInput(_) => {}
    CbsBudgetPlanError::Io(_) => {}
  }
  let positive_ids : Array[String] = []
  let links : Array[Json] = []
  for row_value in rows {
    let row = object(row_value, "cb_cost row")
    if text(field(Json::object(row), "proj_guid")) != project_id {
      continue
    }
    let source_id = required_string(
      field(Json::object(row), "cost_guid"),
      "cost_guid",
    )
    let amount = money_minor(
      field(Json::object(row), amount_field),
      currency,
      policy,
    )
    if amount == 0 {
      continue
    }
    positive_ids.push(source_id)
    let cost_code = required_string(
      field(Json::object(row), "cost_code"),
      "cost_code",
    )
    let subject = match subjects_by_source.get(cost_code) {
      Some(value) => value
      None => raise fail("missing CBS subject mapping: " + cost_code)
    }
    let consume = match consume_by_source.get(source_id) {
      Some(True) => true
      Some(False) => false
      _ => raise fail("missing consume decision: " + source_id)
    }
    links.push(
      Json::object({
        "link_id": Json::string("cbs-budget-link:" + source_id),
        "source_id": Json::string(source_id),
        "subject_code": Json::string(subject.code),
        "reservation_id": Json::string(reservation_prefix + source_id),
        "amount_minor": Json::number(
          amount.to_double(),
          repr=amount.to_string(),
        ),
        "currency": Json::string(currency),
        "consume": Json::boolean(consume),
      }),
    )
  }
  let extra : Array[String] = []
  for source_id, _ in consume_by_source {
    if !positive_ids.contains(source_id) {
      extra.push(source_id)
    }
  }
  if !extra.is_empty() {
    extra.sort_by(fn(left, right) { left.compare(right) })
    raise fail(
      "consume decisions must name exactly positive source amounts: " +
      extra.join(","),
    )
  }
  if links.is_empty() {
    raise fail(
      "no positive " + amount_field + " values for project: " + project_id,
    )
  }
  let mapping_version = required_string(
    field(Json::object(budget), "mapping_version"),
    "mapping_version",
  )
  let report = Json::object({
    "format": Json::string("moonproj.company.cbs-budget-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "mapping_version": Json::string(mapping_version),
    "version_id": Json::string(version_id),
    "project_scope": Json::string(project_scope),
    "principal_id": Json::string(principal_id),
    "currency": Json::string(currency),
    "subjects": Json::array(subjects.map(fn(subject) { subject_json(subject) })),
    "links": Json::array(links),
    "source_table": Json::string("cb_cost"),
    "source_amount_field": Json::string(amount_field),
    "budget_control_only": Json::boolean(true),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise CbsBudgetPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(
        links.length().to_double(),
        repr=links.length().to_string(),
      ),
      "mapping_version": Json::string(mapping_version),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 5 {
    println(
      "usage: cbs_budget_plan <export> <cbs_mapping.json> <budget_mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3], args[4]) catch {
    CbsBudgetPlanError::InvalidInput(message) => {
      println("CBS budget plan failed: " + message)
      @sys.exit(1)
    }
    CbsBudgetPlanError::Io(_) => {
      println("CBS budget plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
