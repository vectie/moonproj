///|
/// Compile the reviewed commitment/milestone/settlement cohort map.
pub(all) suberror ContractMilestonePlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ContractMilestonePlanError {
  ContractMilestonePlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ContractMilestonePlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ContractMilestonePlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ContractMilestonePlanError {
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
) -> Json raise ContractMilestonePlanError {
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
) -> String raise ContractMilestonePlanError {
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
) -> String raise ContractMilestonePlanError {
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
) -> Bool raise ContractMilestonePlanError {
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
) -> Int64 raise ContractMilestonePlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
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
) -> Unit raise ContractMilestonePlanError {
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
) -> Unit raise ContractMilestonePlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.contract-milestone-cohort-map.v1" {
    raise fail("unexpected contract milestone map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("contract milestone map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let commitment = object(required(root, "commitment", "mapping"), "commitment")
  let milestone = object(required(root, "milestone", "mapping"), "milestone")
  let settlement = object(required(root, "settlement", "mapping"), "settlement")
  let commitment_source_table = required_string(
    commitment, "source_table", "commitment",
  )
  let commitment_source_id = required_string(
    commitment, "source_id", "commitment",
  )
  let milestone_source_table = required_string(
    milestone, "source_table", "milestone",
  )
  let milestone_source_id = required_string(milestone, "source_id", "milestone")
  let settlement_source_table = required_string(
    settlement, "source_table", "settlement",
  )
  let settlement_source_id = required_string(
    settlement, "source_id", "settlement",
  )
  if commitment_source_table != "cb_contract" ||
    milestone_source_table != "cb_htfkplan" ||
    settlement_source_table != "cb_htfk_apply" {
    raise fail("source table does not match contract milestone cohort")
  }
  let commitment_identity = commitment_source_table + ":" + commitment_source_id
  let milestone_identity = milestone_source_table + ":" + milestone_source_id
  let settlement_identity = settlement_source_table + ":" + settlement_source_id
  if commitment_identity == milestone_identity ||
    commitment_identity == settlement_identity ||
    milestone_identity == settlement_identity {
    raise fail("source identities must be unique")
  }
  let commitment_id = required_string(commitment, "commitment_id", "commitment")
  let principal_id = required_string(commitment, "principal_id", "commitment")
  let project_scope = required_string(commitment, "project_scope", "commitment")
  let counterparty_id = required_string(
    commitment, "counterparty_id", "commitment",
  )
  let commitment_amount = required_int(commitment, "amount_minor", "commitment")
  let currency = required_string(commitment, "currency", "commitment")
  if commitment_amount < 1 ||
    required_string(commitment, "expected_state", "commitment") != "performed" {
    raise fail("commitment state or amount is invalid")
  }
  let milestone_id = required_string(milestone, "milestone_id", "milestone")
  if required_string(milestone, "commitment_id", "milestone") != commitment_id ||
    required_string(milestone, "expected_state", "milestone") != "reached" {
    raise fail("milestone identity or state is invalid")
  }
  let sequence = required_int(milestone, "sequence", "milestone")
  let node_name = required_string(milestone, "node_name", "milestone")
  let trigger = required_string(milestone, "trigger", "milestone")
  let plan_amount = required_int(milestone, "plan_amount_minor", "milestone")
  let actual_amount = required_int(
    milestone, "actual_amount_minor", "milestone",
  )
  let plan_pct_bps = required_int(milestone, "plan_pct_bps", "milestone")
  if sequence < 1 ||
    plan_amount < 1 ||
    actual_amount < 1 ||
    plan_pct_bps < 0 ||
    plan_pct_bps > 10000 ||
    plan_amount > commitment_amount ||
    actual_amount > plan_amount ||
    (trigger != "time" && trigger != "progress" && trigger != "event") {
    raise fail("milestone amount, percentage, sequence, or trigger is invalid")
  }
  if optional_string(milestone, "currency", currency, "milestone") != currency {
    raise fail("milestone currency differs from commitment")
  }
  let settlement_id = required_string(settlement, "settlement_id", "settlement")
  if required_string(settlement, "commitment_id", "settlement") != commitment_id ||
    required_string(settlement, "milestone_id", "settlement") != milestone_id ||
    required_string(settlement, "expected_state", "settlement") != "requested" {
    raise fail("settlement identity or state is invalid")
  }
  if required_int(settlement, "amount_minor", "settlement") != actual_amount ||
    optional_string(settlement, "currency", currency, "settlement") != currency {
    raise fail("settlement amount or currency differs from milestone")
  }
  if commitment_id == milestone_id ||
    commitment_id == settlement_id ||
    milestone_id == settlement_id {
    raise fail("target identities must be unique")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.contract-milestone-cohort-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "commitment": Json::object({
      "source_table": Json::string(commitment_source_table),
      "source_id": Json::string(commitment_source_id),
      "commitment_id": Json::string(commitment_id),
      "principal_id": Json::string(principal_id),
      "project_scope": Json::string(project_scope),
      "counterparty_id": Json::string(counterparty_id),
      "amount_minor": number(commitment_amount),
      "currency": Json::string(currency),
    }),
    "milestone": Json::object({
      "source_table": Json::string(milestone_source_table),
      "source_id": Json::string(milestone_source_id),
      "milestone_id": Json::string(milestone_id),
      "commitment_id": Json::string(commitment_id),
      "sequence": number(sequence),
      "node_name": Json::string(node_name),
      "trigger": Json::string(trigger),
      "plan_amount_minor": number(plan_amount),
      "actual_amount_minor": number(actual_amount),
      "plan_pct_bps": number(plan_pct_bps),
      "currency": Json::string(currency),
    }),
    "settlement": Json::object({
      "source_table": Json::string(settlement_source_table),
      "source_id": Json::string(settlement_source_id),
      "settlement_id": Json::string(settlement_id),
      "commitment_id": Json::string(commitment_id),
      "milestone_id": Json::string(milestone_id),
      "amount_minor": number(actual_amount),
      "currency": Json::string(currency),
    }),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise ContractMilestonePlanError::Io(error)
  }
  println(
    Json::object({ "output": Json::string(output_path), "items": number(3) }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: contract_milestone_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    ContractMilestonePlanError::InvalidInput(message) => {
      println("contract milestone plan failed: " + message)
      @sys.exit(1)
    }
    ContractMilestonePlanError::Io(_) => {
      println("contract milestone plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
