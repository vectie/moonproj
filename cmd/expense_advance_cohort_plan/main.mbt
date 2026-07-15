///|
/// Compile a reviewed employee advance/expense/offset cohort map.
pub(all) suberror ExpenseAdvanceCohortPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ExpenseAdvanceCohortPlanError {
  ExpenseAdvanceCohortPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ExpenseAdvanceCohortPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ExpenseAdvanceCohortPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ExpenseAdvanceCohortPlanError {
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
) -> Json raise ExpenseAdvanceCohortPlanError {
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
) -> String raise ExpenseAdvanceCohortPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
  fallback : String,
  path : String,
) -> String raise ExpenseAdvanceCohortPlanError {
  match fields.get(key) {
    None => fallback
    Some(String(value)) if !value.trim().is_empty() => value
    Some(_) => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise ExpenseAdvanceCohortPlanError {
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
) -> Int64 raise ExpenseAdvanceCohortPlanError {
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
) -> Array[Json] raise ExpenseAdvanceCohortPlanError {
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
) -> Unit raise ExpenseAdvanceCohortPlanError {
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
fn source_fields(
  value : Map[String, Json],
  path : String,
  expected_table : String,
) -> (String, String) raise ExpenseAdvanceCohortPlanError {
  let table = required_string(value, "source_table", path)
  let source_id = required_string(value, "source_id", path)
  if table != expected_table {
    raise fail(path + ".source_table must be " + expected_table)
  }
  (table, source_id)
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise ExpenseAdvanceCohortPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.expense-advance-cohort-map.v1" {
    raise fail("unexpected expense/advance map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("expense/advance map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let advance = object(required(root, "advance", "mapping"), "advance")
  let expense = object(required(root, "expense", "mapping"), "expense")
  let offset = object(required(root, "offset", "mapping"), "offset")
  let (advance_table, advance_source_id) = source_fields(
    advance, "advance", "vcb_loan_simple",
  )
  let (expense_table, expense_source_id) = source_fields(
    expense, "expense", "vcb_expense",
  )
  let (offset_table, offset_source_id) = source_fields(
    offset, "offset", "cb_loan_offset",
  )
  let advance_id = required_string(advance, "advance_id", "advance")
  let principal_id = required_string(advance, "principal_id", "advance")
  let employee_id = required_string(advance, "employee_id", "advance")
  let currency = required_string(advance, "currency", "advance")
  let advance_amount = required_int(advance, "amount_minor", "advance")
  if employee_id.has_prefix("employee:") ||
    advance_amount < 1 ||
    required_string(advance, "expected_state", "advance") != "partially_repaid" {
    raise fail("advance identity, amount, or state is invalid")
  }
  let expense_id = required_string(expense, "expense_id", "expense")
  if optional_string(expense, "principal_id", principal_id, "expense") !=
    principal_id ||
    optional_string(expense, "employee_id", employee_id, "expense") !=
    employee_id ||
    required_string(expense, "expected_state", "expense") != "approved" {
    raise fail("expense identity or state differs from advance")
  }
  let expense_amount = required_int(expense, "amount_minor", "expense")
  let expense_currency = optional_string(
    expense, "currency", currency, "expense",
  )
  if expense_amount < 1 || expense_currency != currency {
    raise fail("expense amount or currency is invalid")
  }
  let allocations = required_array(expense, "allocations", "expense")
  let normalized_allocations : Array[Json] = []
  let mut allocation_total : Int64 = 0
  for index in 0..<allocations.length() {
    let path = "expense.allocations[" + index.to_string() + "]"
    let allocation = object(allocations[index], path)
    let project_scope = required_string(allocation, "project_scope", path)
    let cost_subject = required_string(allocation, "cost_subject", path)
    let amount = required_int(allocation, "amount_minor", path)
    let allocation_currency = optional_string(
      allocation, "currency", currency, path,
    )
    if amount < 1 || allocation_currency != currency {
      raise fail("expense allocation is invalid at " + path)
    }
    allocation_total += amount
    normalized_allocations.push(
      Json::object({
        "project_scope": Json::string(project_scope),
        "cost_subject": Json::string(cost_subject),
        "amount_minor": number(amount),
        "currency": Json::string(currency),
      }),
    )
  }
  if allocation_total != expense_amount {
    raise fail("expense allocations do not equal expense amount")
  }
  let offset_id = required_string(offset, "offset_id", "offset")
  if required_string(offset, "advance_id", "offset") != advance_id ||
    optional_string(offset, "expense_id", expense_id, "offset") != expense_id {
    raise fail("offset identity differs from advance or expense")
  }
  let offset_amount = required_int(offset, "amount_minor", "offset")
  if offset_amount < 1 ||
    offset_amount > advance_amount ||
    offset_amount > expense_amount ||
    optional_string(offset, "currency", currency, "offset") != currency {
    raise fail("offset amount or currency is invalid")
  }
  if required_int(advance, "expected_repaid_minor", "advance") != offset_amount {
    raise fail("advance expected repaid amount differs from offset")
  }
  let identities = [
    advance_table + ":" + advance_source_id,
    expense_table + ":" + expense_source_id,
    offset_table + ":" + offset_source_id,
  ]
  if identities[0] == identities[1] ||
    identities[0] == identities[2] ||
    identities[1] == identities[2] ||
    advance_id == expense_id ||
    advance_id == offset_id ||
    expense_id == offset_id {
    raise fail("source or target identities must be unique")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.expense-advance-cohort-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "advance": Json::object({
      "source_table": Json::string(advance_table),
      "source_id": Json::string(advance_source_id),
      "advance_id": Json::string(advance_id),
      "principal_id": Json::string(principal_id),
      "employee_id": Json::string(employee_id),
      "amount_minor": number(advance_amount),
      "offset_minor": number(offset_amount),
      "currency": Json::string(currency),
    }),
    "expense": Json::object({
      "source_table": Json::string(expense_table),
      "source_id": Json::string(expense_source_id),
      "expense_id": Json::string(expense_id),
      "principal_id": Json::string(principal_id),
      "employee_id": Json::string(employee_id),
      "amount_minor": number(expense_amount),
      "currency": Json::string(currency),
      "allocations": Json::array(normalized_allocations),
    }),
    "offset": Json::object({
      "source_table": Json::string(offset_table),
      "source_id": Json::string(offset_source_id),
      "offset_id": Json::string(offset_id),
      "advance_id": Json::string(advance_id),
      "expense_id": Json::string(expense_id),
      "amount_minor": number(offset_amount),
      "currency": Json::string(currency),
    }),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise ExpenseAdvanceCohortPlanError::Io(error)
  }
  println(
    Json::object({ "output": Json::string(output_path), "items": number(3) }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: expense_advance_cohort_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    ExpenseAdvanceCohortPlanError::InvalidInput(message) => {
      println("expense/advance cohort plan failed: " + message)
      @sys.exit(1)
    }
    ExpenseAdvanceCohortPlanError::Io(_) => {
      println("expense/advance cohort plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
