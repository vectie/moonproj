///|
pub(all) suberror WarningPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> WarningPlanError {
  WarningPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise WarningPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise WarningPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise WarningPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
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
fn required_string(value : Json, key : String) -> String raise WarningPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn field(obj : Map[String, Json], key : String) -> Json {
  obj.get(key).unwrap_or(Json::null())
}

///|
fn required_field(
  obj : Map[String, Json],
  key : String,
) -> String raise WarningPlanError {
  required_string(field(obj, key), key)
}

///|
fn bool_value(value : Json) -> Bool {
  match value {
    True => true
    _ => false
  }
}

///|
fn string_array(
  value : Json,
  name : String,
) -> Array[String] raise WarningPlanError {
  let values = match value {
    Array(values) if !values.is_empty() => values
    _ => raise fail(name + " must be a non-empty array")
  }
  let result : Array[String] = []
  for item in values {
    result.push(required_string(item, name + " item"))
  }
  result
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
) -> Int64 raise WarningPlanError {
  if currency.length() != 3 {
    raise fail("invalid currency: " + currency)
  }
  let source = text(value).trim()
  if source.is_empty() {
    raise fail("invalid monetary value")
  }
  let scale = match field(policy, "minor_units_per_unit") {
    Number(number, ..) if number == number.trunc() => number.to_int().to_int64()
    _ => 100L
  }
  if scale <= 0 {
    raise fail(
      "money policy must declare positive scale and half_even rounding",
    )
  }
  match field(policy, "rounding") {
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
  let allow_rounding = bool_value(field(policy, "allow_rounding"))
  if !allow_rounding && remainder != 0 {
    raise fail("amount requires rounding: " + source.to_owned())
  }
  if result < 0 {
    raise fail("amount must not be negative: " + source.to_owned())
  }
  result
}

///|
fn sorted_strings(values : Array[String]) -> Array[String] {
  let result = values.copy()
  result.sort_by(fn(left, right) { left.compare(right) })
  result
}

///|
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise WarningPlanError {
  let manifest = object(read_json(export_path + "/manifest.json"), "manifest")
  let source_sha256 = required_field(manifest, "source_sha256")
  if source_sha256.length() != 64 {
    raise fail("source_sha256 must be a 64-character hash")
  }
  let rows = match read_json(export_path + "/tables/cb_cost.json") {
    Array(values) => values
    _ => raise fail("cb_cost export must be an object array")
  }
  let config = object(read_json(mapping_path), "warning mapping")
  let project_id = required_field(config, "project_id")
  let scope = required_field(config, "scope")
  if scope != "project:" + project_id {
    raise fail("scope must match project_id")
  }
  let principal_id = required_field(config, "principal_id")
  let target_field = required_field(config, "target_field")
  let component_fields = string_array(
    field(config, "component_fields"),
    "component_fields",
  )
  let selected_ids = string_array(field(config, "source_ids"), "source_ids")
  let unique_ids : Array[String] = []
  for value in selected_ids {
    if unique_ids.contains(value) {
      raise fail("source_ids must be unique")
    }
    unique_ids.push(value)
  }
  let currency = required_field(config, "currency")
  if currency.length() != 3 {
    raise fail("currency must be an ISO-like three-letter code")
  }
  let warning_id = required_field(config, "warning_id")
  let evidence_id = required_field(config, "evidence_id")
  let mapping_version = required_field(config, "mapping_version")
  let rule_code = required_field(config, "rule_code")
  let target_type = required_field(config, "target_type")
  let target_id = required_field(config, "target_id")
  let message_prefix = required_field(config, "message_prefix")
  let severity = required_field(config, "severity")
  if severity != "info" && severity != "warning" && severity != "critical" {
    raise fail("severity must be info, warning, or critical")
  }
  let policy = object(field(config, "money_policy"), "money_policy") catch {
    WarningPlanError::InvalidInput(_) => {}
    WarningPlanError::Io(_) => {}
  }
  let by_id : Map[String, Json] = {}
  for row in rows {
    let row_obj = object(row, "cb_cost row")
    let source_id = required_field(row_obj, "cost_guid")
    if by_id.get(source_id) is Some(_) {
      raise fail("duplicate cost_guid: " + source_id)
    }
    by_id.set(source_id, row)
  }
  for source_id in selected_ids {
    let row = match by_id.get(source_id) {
      Some(value) => object(value, "selected cb_cost row")
      None => raise fail("source id is not present in cb_cost: " + source_id)
    }
    if text(field(row, "proj_guid")) != project_id {
      raise fail("source row is outside project scope: " + source_id)
    }
  }
  let positive : Map[String, Int64] = {}
  for row in rows {
    let row_obj = object(row, "cb_cost row")
    if text(field(row_obj, "proj_guid")) != project_id {
      continue
    }
    let source_id = required_field(row_obj, "cost_guid")
    let target = money_minor(field(row_obj, target_field), currency, policy)
    let mut components : Int64 = 0
    for component_field in component_fields {
      components += money_minor(
        field(row_obj, component_field),
        currency,
        policy,
      )
    }
    let overrun = components - target
    if overrun > 0 {
      positive.set(source_id, overrun)
    }
  }
  let missing : Array[String] = []
  for value in positive.keys() {
    if !selected_ids.contains(value) {
      missing.push(value)
    }
  }
  let extra : Array[String] = []
  for value in selected_ids {
    if positive.get(value) is None {
      extra.push(value)
    }
  }
  if !missing.is_empty() || !extra.is_empty() {
    raise fail(
      "source_ids must exactly cover positive overruns; missing=" +
      sorted_strings(missing).join(";") +
      ", extra=" +
      sorted_strings(extra).join(";"),
    )
  }
  let mut total : Int64 = 0
  for value in selected_ids {
    total += positive.get(value).unwrap()
  }
  let message = message_prefix +
    ": " +
    total.to_string() +
    " minor units across " +
    selected_ids.join(",")
  let output = Json::object({
    "format": Json::string("moonproj.company.warning-plan.v1"),
    "warning_id": Json::string(warning_id),
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "rule_code": Json::string(rule_code),
    "target_type": Json::string(target_type),
    "target_id": Json::string(target_id),
    "message": Json::string(message),
    "severity": Json::string(severity),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "mapping_version": Json::string(mapping_version),
    "evidence_id": Json::string(evidence_id),
    "source_table": Json::string("cb_cost"),
    "source_ids": Json::array(
      selected_ids.map(fn(value) { Json::string(value) }),
    ),
    "overrun_minor": Json::number(total.to_double(), repr=total.to_string()),
    "scan_policy": Json::string(
      "explicit-source-rows-no-parent-child-double-count",
    ),
  })
  @fs.write_string_to_file(output_path, output.stringify(indent=2) + "\n") catch {
    error => raise WarningPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "mapping_version": Json::string(mapping_version),
      "source_ids": Json::number(
        selected_ids.length().to_double(),
        repr=selected_ids.length().to_string(),
      ),
      "overrun_minor": Json::number(total.to_double(), repr=total.to_string()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: warning_plan <export> <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    WarningPlanError::InvalidInput(message) => {
      println("warning plan failed: " + message)
      @sys.exit(1)
    }
    WarningPlanError::Io(_) => {
      println("warning plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
