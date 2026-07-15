///|
pub(all) suberror AdvanceOffsetPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> AdvanceOffsetPlanError {
  AdvanceOffsetPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AdvanceOffsetPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AdvanceOffsetPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AdvanceOffsetPlanError {
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
fn non_empty(value : Json) -> Bool {
  match value {
    String(value) => !value.trim().is_empty()
    _ => false
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
  policy : Map[String, Json],
) -> Int64 raise AdvanceOffsetPlanError {
  let source = text(value).trim()
  if source.is_empty() {
    raise fail("invalid monetary value")
  }
  let scale = match field(Json::object(policy), "minor_units_per_unit") {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(
        field(Json::object(policy), "minor_units_per_unit").stringify(),
        100L,
      )
    _ => 100L
  }
  if scale <= 0 {
    raise fail("invalid money policy scale")
  }
  match field(Json::object(policy), "rounding") {
    Null => ()
    String(value) if value == "half_even" => ()
    _ => raise fail("money policy must use half_even rounding")
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
    raise fail("rounding required for monetary value: " + source.to_owned())
  }
  if result <= 0 {
    raise fail("non-positive monetary value: " + source.to_owned())
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
fn sorted_reasons(reasons : Array[String]) -> Array[Json] {
  let values = reasons.copy()
  values.sort_by(fn(left, right) { left.compare(right) })
  values.map(fn(value) { Json::string(value) })
}

///|
fn item(
  source_table : String,
  source_id : String,
  target_type : String,
  target_id : String,
  candidate : Json,
  reasons : Array[String],
  warning : String,
) -> Json {
  let values : Map[String, Json] = {}
  values.set("source_table", Json::string(source_table))
  values.set("source_id", Json::string(source_id))
  values.set("target_type", Json::string(target_type))
  values.set("target_id", Json::string(target_id))
  values.set(
    "disposition",
    Json::string(
      if reasons.is_empty() {
        "ready_for_domain_import"
      } else {
        "quarantined"
      },
    ),
  )
  values.set("reasons", Json::array(sorted_reasons(reasons)))
  values.set("warnings", Json::array([Json::string(warning)]))
  if reasons.is_empty() {
    values.set("target_candidate", candidate)
  }
  Json::object(values)
}

///|
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise AdvanceOffsetPlanError {
  let manifest = object(read_json(export_path + "/manifest.json"), "manifest")
  let source_sha256 = text(field(Json::object(manifest), "source_sha256"))
  if source_sha256.is_empty() {
    raise fail("export manifest has no source hash")
  }
  let config = object(read_json(mapping_path), "mapping")
  let principal_by_bu = object(
    field(Json::object(config), "principal_by_bu"),
    "principal_by_bu",
  )
  let employee_by_user = object(
    field(Json::object(config), "employee_by_user"),
    "employee_by_user",
  )
  let currency_by_bu = object(
    field(Json::object(config), "currency_by_bu"),
    "currency_by_bu",
  )
  let offset_mappings = object(
    field(Json::object(config), "advance_offset_by_id"),
    "advance_offset_by_id",
  )
  let policy = object(
    field(Json::object(config), "money_policy"),
    "money_policy",
  )
  let loans = match read_json(export_path + "/tables/vcb_loan_simple.json") {
    Array(values) => values
    _ => raise fail("loan export must be an array")
  }
  let offsets = match read_json(export_path + "/tables/cb_loan_offset.json") {
    Array(values) => values
    _ => raise fail("offset export must be an array")
  }
  let loans_by_id : Map[String, Json] = {}
  for row in loans {
    let loan = object(row, "loan row")
    loans_by_id.set(text(field(Json::object(loan), "loan_guid")), row)
  }
  let items : Array[Json] = []
  for row in loans {
    let loan = object(row, "loan row")
    let loan_id = text(field(Json::object(loan), "loan_guid"))
    let bu_id = text(field(Json::object(loan), "bu_guid"))
    let source_user = text(field(Json::object(loan), "applied_by"))
    let principal = principal_by_bu.get(bu_id).unwrap_or(Json::null())
    let employee = employee_by_user.get(source_user).unwrap_or(Json::null())
    let currency = currency_by_bu.get(bu_id).unwrap_or(Json::null())
    let reasons : Array[String] = []
    if loan_id.is_empty() {
      add_reason(reasons, "missing_advance_id")
    }
    if !non_empty(principal) {
      add_reason(reasons, "missing_principal_by_bu")
    }
    if !non_empty(employee) {
      add_reason(reasons, "missing_employee_by_user")
    }
    if !non_empty(currency) {
      add_reason(reasons, "missing_currency_by_bu")
    }
    let amount_minor : Int64? = match currency {
      String(_) => {
        let mut failed = false
        let parsed = money_minor(
          field(Json::object(loan), "loan_amount"),
          policy,
        ) catch {
          AdvanceOffsetPlanError::InvalidInput(message) => {
            add_reason(reasons, message)
            failed = true
            0L
          }
          AdvanceOffsetPlanError::Io(_) => {
            failed = true
            0L
          }
        }
        if failed {
          None
        } else {
          Some(parsed)
        }
      }
      _ => None
    }
    let amount = match amount_minor {
      Some(value) => Json::number(value.to_double(), repr=value.to_string())
      None => Json::null()
    }
    let candidate = Json::object({
      "advance_id": Json::string(loan_id),
      "principal_id": principal,
      "employee_id": employee,
      "business_unit_id": Json::string(bu_id),
      "authority_scope": if non_empty(employee) {
        Json::string("employee:" + text(employee))
      } else {
        Json::null()
      },
      "amount_minor": amount,
      "currency": currency,
    })
    items.push(
      item(
        "vcb_loan_simple", loan_id, "employee_advance", loan_id, candidate, reasons,
        "source balance is replayed only through explicit offset items",
      ),
    )
  }
  for row in offsets {
    let offset = object(row, "offset row")
    let offset_id = text(field(Json::object(offset), "offset_guid"))
    let loan_id = text(field(Json::object(offset), "loan_guid"))
    let loan = loans_by_id.get(loan_id)
    let mapping = match offset_mappings.get(offset_id) {
      Some(Object(values)) => values
      _ => {}
    }
    let reasons : Array[String] = []
    if offset_id.is_empty() || loan_id.is_empty() {
      add_reason(reasons, "missing_offset_or_loan_id")
    }
    if loan is None {
      add_reason(reasons, "missing_advance")
    }
    if offset_mappings.get(offset_id) is None {
      add_reason(reasons, "missing_advance_offset_mapping")
    }
    let bu_id = match loan {
      Some(value) => text(field(Json::object(object(value, "loan")), "bu_guid"))
      None => ""
    }
    let source_user = match loan {
      Some(value) =>
        text(field(Json::object(object(value, "loan")), "applied_by"))
      None => ""
    }
    let derived_principal = principal_by_bu.get(bu_id).unwrap_or(Json::null())
    let derived_employee = employee_by_user
      .get(source_user)
      .unwrap_or(Json::null())
    let derived_currency = currency_by_bu.get(bu_id).unwrap_or(Json::null())
    let principal = mapping.get("principal_id").unwrap_or(Json::null())
    let employee = mapping.get("employee_id").unwrap_or(Json::null())
    let currency = mapping.get("currency").unwrap_or(Json::null())
    let scope = mapping.get("scope").unwrap_or(Json::null())
    if !non_empty(principal) {
      add_reason(reasons, "missing_advance_offset_field:principal_id")
    }
    if !non_empty(employee) {
      add_reason(reasons, "missing_advance_offset_field:employee_id")
    }
    if !non_empty(currency) {
      add_reason(reasons, "missing_advance_offset_field:currency")
    }
    if !non_empty(scope) {
      add_reason(reasons, "missing_advance_offset_field:scope")
    }
    if principal != derived_principal {
      add_reason(reasons, "offset_principal_mismatch")
    }
    if employee != derived_employee {
      add_reason(reasons, "offset_employee_mismatch")
    }
    if currency != derived_currency {
      add_reason(reasons, "offset_currency_mismatch")
    }
    let expected_scope = if non_empty(employee) {
      "employee:" + text(employee)
    } else {
      ""
    }
    if text(scope) != expected_scope {
      add_reason(reasons, "offset_scope_mismatch")
    }
    let amount_minor : Int64? = match currency {
      String(_) => {
        let mut failed = false
        let parsed = money_minor(
          field(Json::object(offset), "offset_amount"),
          policy,
        ) catch {
          AdvanceOffsetPlanError::InvalidInput(message) => {
            add_reason(reasons, message)
            failed = true
            0L
          }
          AdvanceOffsetPlanError::Io(_) => {
            failed = true
            0L
          }
        }
        if failed {
          None
        } else {
          Some(parsed)
        }
      }
      _ => None
    }
    let amount = match amount_minor {
      Some(value) => Json::number(value.to_double(), repr=value.to_string())
      None => Json::null()
    }
    match (loan, amount_minor) {
      (Some(value), Some(offset_amount)) => {
        let loan_amount = money_minor(
          field(Json::object(object(value, "loan")), "loan_amount"),
          policy,
        ) catch {
          AdvanceOffsetPlanError::InvalidInput(message) => {
            add_reason(reasons, message)
            0L
          }
          AdvanceOffsetPlanError::Io(_) => 0L
        }
        if offset_amount > loan_amount {
          add_reason(reasons, "offset_exceeds_advance")
        }
      }
      _ => ()
    }
    let candidate = Json::object({
      "offset_id": Json::string(offset_id),
      "advance_id": Json::string(loan_id),
      "principal_id": principal,
      "employee_id": employee,
      "authority_scope": scope,
      "amount_minor": amount,
      "currency": currency,
      "offset_date": field(Json::object(offset), "offset_date"),
      "operator_id": field(Json::object(offset), "operator_guid"),
      "related_expense_id": field(Json::object(offset), "related_expense_guid"),
    })
    items.push(
      item(
        "cb_loan_offset", offset_id, "employee_advance_offset", offset_id, candidate,
        reasons, "offset mutates only the imported advance balance; cash and accounting recognition remain separate events",
      ),
    )
  }
  let mut ready = 0
  for value in items {
    if text(field(value, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let mapping_version = text(field(Json::object(config), "mapping_version"))
  let mapping_version = if mapping_version.is_empty() {
    "unversioned-advance-offset-map"
  } else {
    mapping_version
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.advance-offset-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": Json::string(mapping_version),
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
    error => raise AdvanceOffsetPlanError::Io(error)
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
    println("usage: advance_offset_plan <export> <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    AdvanceOffsetPlanError::InvalidInput(message) => {
      println("advance-offset promotion plan failed: " + message)
      @sys.exit(1)
    }
    AdvanceOffsetPlanError::Io(_) => {
      println("advance-offset promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
