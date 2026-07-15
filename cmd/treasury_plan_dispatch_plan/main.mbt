///|
/// Compile a reviewed cash-plan/fund-dispatch map without releasing bank cash
/// or posting accounting.
pub(all) suberror TreasuryPlanDispatchPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> TreasuryPlanDispatchPlanError {
  TreasuryPlanDispatchPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TreasuryPlanDispatchPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TreasuryPlanDispatchPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TreasuryPlanDispatchPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise TreasuryPlanDispatchPlanError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise TreasuryPlanDispatchPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise TreasuryPlanDispatchPlanError {
  match required(fields, key, path) {
    True => true
    False => false
    _ => raise fail("expected boolean at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise TreasuryPlanDispatchPlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise TreasuryPlanDispatchPlanError {
  match required(fields, key, path) {
    Array(values) if !values.is_empty() => values
    _ => raise fail("expected non-empty array at " + path + "." + key)
  }
}

///|
fn secret_key(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.has_suffix("ip")
}

///|
fn reject_secret_keys(
  value : Json,
  path : String,
) -> Unit raise TreasuryPlanDispatchPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secret_keys(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secret_keys(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise TreasuryPlanDispatchPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.treasury-plan-dispatch-map.v1" {
    raise fail("unexpected treasury plan map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("treasury plan map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let plans = required_array(root, "cash_plans", "mapping")
  let dispatches = required_array(root, "fund_dispatches", "mapping")
  let plan_ids : Array[String] = []
  let normalized_plans : Array[Json] = []
  for index in 0..<plans.length() {
    let path = "cash_plans[" + index.to_string() + "]"
    let plan = object(plans[index], path)
    let source_table = required_string(plan, "source_table", path)
    let source_id = required_string(plan, "source_id", path)
    let plan_id = required_string(plan, "plan_id", path)
    let principal_id = required_string(plan, "principal_id", path)
    let project_scope = required_string(plan, "project_scope", path)
    let period = required_string(plan, "period", path)
    let category = required_string(plan, "category", path)
    let direction = required_string(plan, "direction", path)
    let expected_state = required_string(plan, "expected_state", path)
    let currency = required_string(plan, "currency", path)
    let planned = required_int(plan, "planned_amount_minor", path)
    let actual = required_int(plan, "actual_amount_minor", path)
    if planned < 1 ||
      actual < 0 ||
      actual > planned ||
      (direction != "inflow" && direction != "outflow") ||
      (
        expected_state != "planned" &&
        expected_state != "confirmed" &&
        expected_state != "actualized"
      ) {
      raise fail("cash plan values or state are invalid at " + path)
    }
    if expected_state == "actualized" && actual <= 0 {
      raise fail(
        "actualized cash plan requires positive actual amount at " + path,
      )
    }
    if expected_state != "actualized" && actual != 0 {
      raise fail("actual amount requires actualized state at " + path)
    }
    if plan_ids.contains(plan_id) {
      raise fail("duplicate plan_id: " + plan_id)
    }
    plan_ids.push(plan_id)
    normalized_plans.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "plan_id": Json::string(plan_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "period": Json::string(period),
        "category": Json::string(category),
        "direction": Json::string(direction),
        "currency": Json::string(currency),
        "planned_amount_minor": number(planned),
        "actual_amount_minor": number(actual),
        "expected_state": Json::string(expected_state),
      }),
    )
  }
  let dispatch_ids : Array[String] = []
  let normalized_dispatches : Array[Json] = []
  for index in 0..<dispatches.length() {
    let path = "fund_dispatches[" + index.to_string() + "]"
    let dispatch = object(dispatches[index], path)
    let source_table = required_string(dispatch, "source_table", path)
    let source_id = required_string(dispatch, "source_id", path)
    let dispatch_id = required_string(dispatch, "dispatch_id", path)
    let principal_id = required_string(dispatch, "principal_id", path)
    let from_project = required_string(dispatch, "from_project", path)
    let to_project = required_string(dispatch, "to_project", path)
    let amount = required_int(dispatch, "amount_minor", path)
    let currency = required_string(dispatch, "currency", path)
    let reason = required_string(dispatch, "reason", path)
    let expected_state = required_string(dispatch, "expected_state", path)
    if amount < 1 ||
      from_project == to_project ||
      (
        expected_state != "pending" &&
        expected_state != "approved" &&
        expected_state != "executed"
      ) {
      raise fail("fund dispatch values or state are invalid at " + path)
    }
    if dispatch_ids.contains(dispatch_id) {
      raise fail("duplicate dispatch_id: " + dispatch_id)
    }
    dispatch_ids.push(dispatch_id)
    normalized_dispatches.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "dispatch_id": Json::string(dispatch_id),
        "principal_id": Json::string(principal_id),
        "from_project": Json::string(from_project),
        "to_project": Json::string(to_project),
        "amount_minor": number(amount),
        "currency": Json::string(currency),
        "reason": Json::string(reason),
        "expected_state": Json::string(expected_state),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.treasury-plan-dispatch-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "cash_plans": number(normalized_plans.length().to_int64()),
      "fund_dispatches": number(normalized_dispatches.length().to_int64()),
    }),
    "cash_plans": Json::array(normalized_plans),
    "fund_dispatches": Json::array(normalized_dispatches),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TreasuryPlanDispatchPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "cash_plans": number(normalized_plans.length().to_int64()),
      "fund_dispatches": number(normalized_dispatches.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: treasury_plan_dispatch_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    TreasuryPlanDispatchPlanError::InvalidInput(message) => {
      println("treasury plan failed: " + message)
      @sys.exit(1)
    }
    TreasuryPlanDispatchPlanError::Io(_) => {
      println("treasury plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
