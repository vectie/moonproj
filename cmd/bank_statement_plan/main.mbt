///|
/// Compile a reviewed bank-statement map without inferring cash or ledger
/// effects. The resulting plan is consumed by the native statement importer.
pub(all) suberror BankStatementPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> BankStatementPlanError {
  BankStatementPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise BankStatementPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise BankStatementPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise BankStatementPlanError {
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
) -> Json raise BankStatementPlanError {
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
) -> String raise BankStatementPlanError {
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
) -> Bool raise BankStatementPlanError {
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
) -> Int64 raise BankStatementPlanError {
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
) -> Array[Json] raise BankStatementPlanError {
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
) -> Unit raise BankStatementPlanError {
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
) -> Unit raise BankStatementPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.bank-statement-map.v1" {
    raise fail("unexpected bank-statement map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("bank-statement map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let statements = required_array(root, "statements", "mapping")
  let seen_statement_ids : Array[String] = []
  let seen_source_ids : Array[String] = []
  let normalized : Array[Json] = []
  let mut total_lines : Int64 = 0
  for statement_index in 0..<statements.length() {
    let path = "statements[" + statement_index.to_string() + "]"
    let statement = object(statements[statement_index], path)
    let source_table = required_string(statement, "source_table", path)
    let source_id = required_string(statement, "source_id", path)
    let statement_id = required_string(statement, "statement_id", path)
    let account_id = required_string(statement, "account_id", path)
    let principal_id = required_string(statement, "principal_id", path)
    let project_scope = required_string(statement, "project_scope", path)
    let period = required_string(statement, "period", path)
    let currency = required_string(statement, "currency", path)
    let opening_balance_minor = required_int(
      statement, "opening_balance_minor", path,
    )
    let closing_balance_minor = required_int(
      statement, "closing_balance_minor", path,
    )
    let lines = required_array(statement, "lines", path)
    let seen_line_ids : Array[String] = []
    let normalized_lines : Array[Json] = []
    for line_index in 0..<lines.length() {
      let line_path = path + ".lines[" + line_index.to_string() + "]"
      let line = object(lines[line_index], line_path)
      let line_id = required_string(line, "line_id", line_path)
      let external_reference = required_string(
        line, "external_reference", line_path,
      )
      let booked_at = required_string(line, "booked_at", line_path)
      let amount_minor = required_int(line, "amount_minor", line_path)
      let direction = required_string(line, "direction", line_path)
      if amount_minor < 1 {
        raise fail("amount_minor must be >= 1 at " + line_path)
      }
      if direction != "inflow" && direction != "outflow" {
        raise fail("invalid direction at " + line_path)
      }
      if seen_line_ids.contains(line_id) {
        raise fail(
          "duplicate line_id in statement " + statement_id + ": " + line_id,
        )
      }
      seen_line_ids.push(line_id)
      normalized_lines.push(
        Json::object({
          "line_id": Json::string(line_id),
          "external_reference": Json::string(external_reference),
          "booked_at": Json::string(booked_at),
          "amount_minor": number(amount_minor),
          "direction": Json::string(direction),
        }),
      )
      total_lines += 1
    }
    if seen_statement_ids.contains(statement_id) {
      raise fail("duplicate statement_id: " + statement_id)
    }
    if seen_source_ids.contains(source_id) {
      raise fail("duplicate source_id: " + source_id)
    }
    seen_statement_ids.push(statement_id)
    seen_source_ids.push(source_id)
    normalized.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "statement_id": Json::string(statement_id),
        "account_id": Json::string(account_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "period": Json::string(period),
        "currency": Json::string(currency),
        "opening_balance_minor": number(opening_balance_minor),
        "closing_balance_minor": number(closing_balance_minor),
        "lines": Json::array(normalized_lines),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.bank-statement-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "statements": number(normalized.length().to_int64()),
      "lines": number(total_lines),
    }),
    "statements": Json::array(normalized),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise BankStatementPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "statements": number(normalized.length().to_int64()),
      "lines": number(total_lines),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: bank_statement_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    BankStatementPlanError::InvalidInput(message) => {
      println("bank-statement plan failed: " + message)
      @sys.exit(1)
    }
    BankStatementPlanError::Io(_) => {
      println("bank-statement plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
