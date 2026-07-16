///|
pub(all) suberror PromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> PromotionPlanError {
  PromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PromotionPlanError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise PromotionPlanError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PromotionPlanError {
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
) -> String raise PromotionPlanError {
  let result = text(value)
  if result.trim().is_empty() {
    raise fail(key + " must be a non-empty string")
  }
  result
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), default)
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
fn mapping(
  config : Map[String, Json],
  key : String,
) -> Map[String, String] raise PromotionPlanError {
  let value = config.get(key).unwrap_or(Json::object({}))
  let fields = object(value, key)
  let result : Map[String, String] = {}
  for name, value in fields {
    result.set(name, text(value))
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
) -> Int64 raise PromotionPlanError {
  if currency.length() != 3 {
    raise fail("invalid currency for amount: " + currency)
  }
  let source = text(value).trim().to_owned()
  if source.is_empty() {
    raise fail("invalid monetary value")
  }
  let scale = integer(
    policy.get("minor_units_per_unit").unwrap_or(Json::number(100.0)),
    100L,
  )
  if scale <= 0 {
    raise fail("minor_units_per_unit must be positive")
  }
  match policy.get("rounding") {
    None | Some(String("half_even")) => ()
    _ => raise fail("only half_even rounding is supported by this plan tool")
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
        raise fail("invalid monetary value: " + source)
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
      raise fail("invalid monetary value: " + source)
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
  if remainder != 0 && policy.get("allow_rounding") != Some(Json::boolean(true)) {
    raise fail("amount requires rounding under the declared policy: " + source)
  }
  let result = rounded * sign
  if result < 0 {
    raise fail("negative monetary value: " + source)
  }
  result
}

///|
fn reason(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}

///|
fn reasons_json(values : Array[String]) -> Json {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.lexical_compare(right) })
  Json::array(sorted.map(fn(value) { Json::string(value) }))
}

///|
fn item(
  table : String,
  source_id : String,
  target_type : String,
  target_id : String,
  candidate : Json?,
  reasons : Array[String],
  warnings : Array[String],
) -> Json {
  let fields : Map[String, Json] = {
    "source_table": Json::string(table),
    "source_id": Json::string(source_id),
    "target_type": Json::string(target_type),
    "target_id": Json::string(target_id),
    "disposition": Json::string(
      if reasons.is_empty() {
        "ready_for_domain_import"
      } else {
        "quarantined"
      },
    ),
    "reasons": reasons_json(reasons),
    "warnings": reasons_json(warnings),
  }
  match candidate {
    Some(value) if reasons.is_empty() => fields.set("target_candidate", value)
    _ => ()
  }
  Json::object(fields)
}

///|
fn rows(
  export_dir : String,
  table : String,
) -> Array[Json] raise PromotionPlanError {
  match read_json(export_dir + "/tables/" + table + ".json") {
    Array(values) => {
      for value in values {
        let _ = object(value, table)
      }
      values
    }
    _ => raise fail("export table is not an object array: " + table)
  }
}

///|
fn bool_nonzero(value : Json) -> Bool {
  match value {
    Null => false
    Number(number, ..) => number != 0.0
    String(text) => {
      let normalized = text.trim()
      normalized != "" && normalized != "0" && normalized != "0.0"
    }
    _ => true
  }
}

///|
fn num(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise PromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let source_sha256 = required_string(
    field(Json::object(manifest), "source_sha256"),
    "source_sha256",
  )
  if source_sha256.length() != 64 {
    raise fail("export manifest has no valid source hash")
  }
  let config = object(read_json(mapping_path), "promotion mapping")
  let principal_by_bu = mapping(config, "principal_by_bu")
  let counterparty_by_provider = mapping(config, "counterparty_by_provider")
  let employee_by_user = mapping(config, "employee_by_user")
  let currency_by_bu = mapping(config, "currency_by_bu")
  let policy = object(
    config.get("money_policy").unwrap_or(Json::object({})),
    "money_policy",
  )
  let cost_map = object(
    config.get("cost_component_map").unwrap_or(Json::object({})),
    "cost_component_map",
  )
  let required_cost_fields = ["direct", "indirect", "contingency", "other"]
  for name in required_cost_fields {
    if cost_map.get(name) is None {
      raise fail(
        "cost_component_map must name direct/indirect/contingency/other",
      )
    }
  }
  let business_units = rows(export_dir, "mu_business_unit")
  let projects = rows(export_dir, "ep_project")
  let contracts = rows(export_dir, "cb_contract")
  let costs = rows(export_dir, "cb_cost")
  let loans = rows(export_dir, "vcb_loan_simple")
  let bu_ids : Map[String, Bool] = {}
  for row in business_units {
    bu_ids.set(text(field(row, "bu_guid")), true)
  }
  let project_ids : Map[String, Bool] = {}
  for row in projects {
    project_ids.set(text(field(row, "proj_guid")), true)
  }
  let items : Array[Json] = []
  for row in business_units {
    let id = text(field(row, "bu_guid"))
    let principal = principal_by_bu.get(id).unwrap_or("")
    let why : Array[String] = []
    if principal.is_empty() {
      reason(why, "missing_principal_by_bu")
    }
    let parent = field(row, "parent_guid")
    let parent_text = text(parent)
    if !parent_text.is_empty() && bu_ids.get(parent_text) is None {
      reason(why, "missing_parent_business_unit")
    }
    let candidate = if principal.is_empty() {
      None
    } else {
      Some(
        Json::object({
          "unit_id": Json::string(id),
          "principal_id": Json::string(principal),
          "authority_scope": Json::string("organization:" + id),
          "parent_id": parent,
          "code": field(row, "bu_code"),
          "name": field(row, "bu_name"),
          "kind": Json::string(text(field(row, "bu_type")).to_lower()),
        }),
      )
    }
    items.push(
      item("mu_business_unit", id, "organization_unit", id, candidate, why, []),
    )
  }
  for row in projects {
    let id = text(field(row, "proj_guid"))
    let bu_id = text(field(row, "bu_guid"))
    let principal = principal_by_bu.get(bu_id).unwrap_or("")
    let why : Array[String] = []
    if principal.is_empty() {
      reason(why, "missing_principal_by_bu")
    }
    let candidate = if principal.is_empty() {
      None
    } else {
      Some(
        Json::object({
          "project_id": Json::string(id),
          "principal_id": Json::string(principal),
          "authority_scope": Json::string("project:" + id),
          "code": field(row, "proj_code"),
          "name": field(row, "proj_name"),
          "business_unit_id": Json::string(bu_id),
        }),
      )
    }
    items.push(item("ep_project", id, "project", id, candidate, why, []))
  }
  for row in contracts {
    let id = text(field(row, "contract_guid"))
    let bu_id = text(field(row, "bu_guid"))
    let project_id = text(field(row, "proj_guid"))
    let provider = text(field(row, "yf_provider_name"))
    let principal = principal_by_bu.get(bu_id).unwrap_or("")
    let counterparty = counterparty_by_provider.get(provider).unwrap_or("")
    let currency = currency_by_bu.get(bu_id).unwrap_or("")
    let why : Array[String] = []
    if principal.is_empty() {
      reason(why, "missing_principal_by_bu")
    }
    if project_ids.get(project_id) is None {
      reason(why, "missing_project")
    }
    if counterparty.is_empty() {
      reason(why, "missing_counterparty_by_provider_name")
    }
    if currency.is_empty() {
      reason(why, "missing_currency_by_bu")
    }
    let amount : Int64? = if currency.is_empty() {
      None
    } else {
      Some(
        money_minor(field(row, "ht_amount"), currency, policy) catch {
          PromotionPlanError::InvalidInput(message) => {
            reason(why, message)
            0L
          }
          PromotionPlanError::Io(_) => 0L
        },
      )
    }
    let candidate = if why.is_empty() {
      Some(
        Json::object({
          "commitment_id": Json::string(id),
          "principal_id": Json::string(principal),
          "project_scope": Json::string("project:" + project_id),
          "business_unit_id": Json::string(bu_id),
          "counterparty_id": Json::string(counterparty),
          "amount_minor": num(amount.unwrap()),
          "currency": Json::string(currency),
        }),
      )
    } else {
      None
    }
    items.push(item("cb_contract", id, "commitment", id, candidate, why, []))
  }
  for row in costs {
    let id = text(field(row, "cost_guid"))
    let bu_id = text(field(row, "bu_guid"))
    let project_id = text(field(row, "proj_guid"))
    let currency = currency_by_bu.get(bu_id).unwrap_or("")
    let why : Array[String] = []
    if project_ids.get(project_id) is None {
      reason(why, "missing_project")
    }
    if currency.is_empty() {
      reason(why, "missing_currency_by_bu")
    }
    let components : Map[String, Json] = {}
    if !currency.is_empty() {
      for name in required_cost_fields {
        let source_name = text(cost_map.get(name).unwrap())
        let amount = money_minor(field(row, source_name), currency, policy) catch {
          PromotionPlanError::InvalidInput(message) => {
            reason(why, name + ": " + message)
            0L
          }
          PromotionPlanError::Io(_) => 0L
        }
        components.set(name, num(amount))
      }
    }
    let candidate = if why.is_empty() {
      Some(
        Json::object({
          "cost_id": Json::string(id),
          "project_scope": Json::string("project:" + project_id),
          "currency": Json::string(currency),
          "components_minor": Json::object(components),
        }),
      )
    } else {
      None
    }
    items.push(item("cb_cost", id, "dynamic_cost", id, candidate, why, []))
  }
  for row in loans {
    let id = text(field(row, "loan_guid"))
    let bu_id = text(field(row, "bu_guid"))
    let source_user = text(field(row, "applied_by"))
    let principal = principal_by_bu.get(bu_id).unwrap_or("")
    let employee = employee_by_user.get(source_user).unwrap_or("")
    let currency = currency_by_bu.get(bu_id).unwrap_or("")
    let why : Array[String] = []
    let warnings : Array[String] = []
    if principal.is_empty() {
      reason(why, "missing_principal_by_bu")
    }
    if employee.is_empty() {
      reason(why, "missing_employee_by_user")
    }
    if currency.is_empty() {
      reason(why, "missing_currency_by_bu")
    }
    let amount : Int64? = if currency.is_empty() {
      None
    } else {
      Some(
        money_minor(field(row, "loan_amount"), currency, policy) catch {
          PromotionPlanError::InvalidInput(message) => {
            reason(why, message)
            0L
          }
          PromotionPlanError::Io(_) => 0L
        },
      )
    }
    if bool_nonzero(field(row, "balance_amount")) {
      warnings.push("source_balance_requires_explicit_offset_event")
    }
    let candidate = if why.is_empty() {
      Some(
        Json::object({
          "advance_id": Json::string(id),
          "principal_id": Json::string(principal),
          "employee_id": Json::string(employee),
          "business_unit_id": Json::string(bu_id),
          "authority_scope": Json::string("employee:" + employee),
          "amount_minor": num(amount.unwrap()),
          "currency": Json::string(currency),
        }),
      )
    } else {
      None
    }
    items.push(
      item(
        "vcb_loan_simple", id, "employee_advance", id, candidate, why, warnings,
      ),
    )
  }
  let ready = items
    .filter(fn(value) {
      text(field(value, "disposition")) == "ready_for_domain_import"
    })
    .length()
  let quarantined = items.length() - ready
  let plan = Json::object({
    "format": Json::string("moonproj.erp.promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": config
    .get("mapping_version")
    .unwrap_or(Json::string("unversioned-explicit-map")),
    "money_policy": Json::object(policy),
    "cost_component_map": Json::object(cost_map),
    "cohort": Json::string("mapped-economic-v1"),
    "summary": Json::object({
      "items": num(items.length().to_int64()),
      "ready": num(ready.to_int64()),
      "quarantined": num(quarantined.to_int64()),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, plan.stringify(indent=2) + "\n") catch {
    error => raise PromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": num(items.length().to_int64()),
      "ready": num(ready.to_int64()),
      "quarantined": num(quarantined.to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  } else {
    run(args[1], args[2], args[3]) catch {
      PromotionPlanError::InvalidInput(message) => {
        println("promotion plan failed: " + message)
        @sys.exit(1)
      }
      PromotionPlanError::Io(_) => {
        println("promotion plan failed: filesystem error")
        @sys.exit(1)
      }
    }
  }
}
