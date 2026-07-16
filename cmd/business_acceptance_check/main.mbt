///|
pub(all) suberror BusinessAcceptanceError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> BusinessAcceptanceError {
  BusinessAcceptanceError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise BusinessAcceptanceError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise BusinessAcceptanceError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise BusinessAcceptanceError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object: " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise BusinessAcceptanceError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing " + key + ": " + path)
  }
}

///|
fn non_empty(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise BusinessAcceptanceError {
  match required(fields, key, path) {
    String(text) if !text.trim().is_empty() => text
    _ => raise fail("missing non-empty field: " + key)
  }
}

///|
fn array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise BusinessAcceptanceError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail(key + " must be an array")
  }
}

///|
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise BusinessAcceptanceError {
  match value {
    Object(fields) =>
      for key, child in fields {
        let lowered = key.to_lower()
        if lowered.contains("password") ||
          lowered.contains("secret") ||
          lowered.contains("token") ||
          lowered.contains("private") ||
          lowered.contains("credential") {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn integer_or_null(fields : Map[String, Json], key : String) -> Json {
  fields.get(key).unwrap_or(Json::null())
}

///|
fn validate(
  work_dir : String,
  manifest : Json,
) -> Json raise BusinessAcceptanceError {
  let root = object(manifest, "manifest")
  reject_secrets(manifest, "manifest")
  if non_empty(root, "format", "manifest") !=
    "moonproj.erp.business-acceptance.v1" {
    raise fail("unsupported business-acceptance format")
  }
  let source_contract = object(
    read_json(work_dir + "/source-export-contract.json"),
    "source contract",
  )
  let row_coverage = object(
    read_json(work_dir + "/row-coverage.json"),
    "row coverage",
  )
  if non_empty(source_contract, "format", "source contract") !=
    "moonproj.erp.export-contract.v1" {
    raise fail("source export contract is missing or invalid")
  }
  if non_empty(row_coverage, "format", "row coverage") !=
    "moonproj.erp.row-coverage.v1" {
    raise fail("row coverage evidence is missing or invalid")
  }
  let source_hash = match source_contract.get("source_sha256") {
    Some(String(value)) => value
    Some(Number(number, repr~)) =>
      match repr {
        Some(value) => value
        None => number.to_string()
      }
    _ => "None"
  }
  let expected_snapshot = "erp-snapshot:" + source_hash
  let source_snapshot_id = match root.get("source_snapshot_id") {
    Some(String(value)) if value == "from-source-export-evidence" =>
      expected_snapshot
    Some(String(value)) => value
    _ => raise fail("acceptance source snapshot is missing")
  }
  if source_snapshot_id != expected_snapshot {
    raise fail("acceptance source snapshot does not match export evidence")
  }
  let decisions = array(root, "decisions", "manifest")
  let required_roles : Map[String, String] = {
    "task-state-proj-0001": "business",
    "erp-schema-coverage": "migration-owner",
    "production-database-deployment": "operations",
    "accounting-reconciliation": "finance",
    "shadow-period": "operations",
  }
  let shadow_ids = [
    "production-database-deployment", "accounting-reconciliation", "shadow-period",
  ]
  let seen : Map[String, Map[String, Json]] = {}
  for index in 0..<decisions.length() {
    let path = "decisions[" + index.to_string() + "]"
    let decision = object(decisions[index], path)
    let decision_id = non_empty(decision, "id", path)
    if !required_roles.contains(decision_id) {
      raise fail("unexpected decision ID: " + decision_id)
    }
    if seen.contains(decision_id) {
      raise fail("decision IDs must be unique non-empty strings")
    }
    let owner_role = non_empty(decision, "owner_role", path)
    if owner_role != required_roles.get(decision_id).unwrap() {
      raise fail("wrong owner role for " + decision_id)
    }
    match decision.get("decision") {
      None | Some(Null) => ()
      Some(String(value)) => {
        if value != "accept_for_shadow" && value != "defer" && value != "reject" {
          raise fail("unsupported decision for " + decision_id + ": " + value)
        }
        for key in ["decided_by", "decided_at", "rationale"] {
          ignore(non_empty(decision, key, path))
        }
        let refs = array(decision, "evidence_refs", path)
        if refs.is_empty() {
          raise fail(decision_id + " requires evidence_refs")
        }
        for reference in refs {
          match reference {
            String(value) if !value.trim().is_empty() => ()
            _ => raise fail(decision_id + " requires evidence_refs")
          }
        }
      }
      Some(_) => raise fail("unsupported decision for " + decision_id)
    }
    seen.set(decision_id, decision)
  }
  let required_ids = required_roles.keys().to_array()
  let missing : Array[String] = []
  for decision_id in required_ids {
    if !seen.contains(decision_id) {
      missing.push(decision_id)
    }
  }
  missing.sort_by(fn(left, right) { left.lexical_compare(right) })
  if !missing.is_empty() {
    raise fail("required decisions missing: " + missing.join(","))
  }
  let pending : Array[String] = []
  let rejected : Array[String] = []
  let deferred : Array[String] = []
  let accepted : Array[String] = []
  for decision_id in required_ids {
    let decision = seen.get(decision_id).unwrap()
    match decision.get("decision") {
      None | Some(Null) => pending.push(decision_id)
      Some(String("reject")) => rejected.push(decision_id)
      Some(String("defer")) => deferred.push(decision_id)
      Some(String("accept_for_shadow")) => accepted.push(decision_id)
      _ => ()
    }
  }
  pending.sort_by(fn(left, right) { left.lexical_compare(right) })
  rejected.sort_by(fn(left, right) { left.lexical_compare(right) })
  deferred.sort_by(fn(left, right) { left.lexical_compare(right) })
  accepted.sort_by(fn(left, right) { left.lexical_compare(right) })
  let mut authorized = pending.is_empty() && rejected.is_empty()
  for decision_id in shadow_ids {
    let decision = seen.get(decision_id).unwrap()
    if decision.get("decision") != Some(Json::string("accept_for_shadow")) {
      authorized = false
    }
  }
  Json::object({
    "format": Json::string("moonproj.erp.business-acceptance-result.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "state": Json::string(
      if pending.is_empty() && rejected.is_empty() {
        "ready_for_shadow"
      } else {
        "acceptance_pending"
      },
    ),
    "acceptance_authorized": Json::boolean(authorized),
    "shadow_authorized": Json::boolean(authorized),
    "cutover_authorized": Json::boolean(false),
    "required_decisions": Json::number(
      required_roles.keys().length().to_double(),
      repr=required_roles.keys().length().to_string(),
    ),
    "pending_decisions": strings(pending),
    "rejected_decisions": strings(rejected),
    "deferred_decisions": strings(deferred),
    "accepted_for_shadow": strings(accepted),
    "technical_evidence": Json::object({
      "source_export_state": source_contract
      .get("state")
      .unwrap_or(Json::null()),
      "source_rows": integer_or_null(row_coverage, "source_rows"),
      "covered_rows": integer_or_null(row_coverage, "covered_rows"),
      "uncovered_rows": integer_or_null(row_coverage, "uncovered_rows"),
    }),
    "decisions": Json::array(decisions),
  })
}

///|
fn result_field(result : Json, key : String) -> Json {
  match result {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn result_array_count(result : Json, key : String) -> Json {
  match result_field(result, key) {
    Array(values) =>
      Json::number(
        values.length().to_double(),
        repr=values.length().to_string(),
      )
    _ => Json::number(0, repr="0")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: business_acceptance_check <work_dir> <manifest> <output>")
    @sys.exit(2)
  } else {
    let result = validate(args[1], read_json(args[2])) catch {
      BusinessAcceptanceError::InvalidInput(message) => {
        println("business acceptance check failed: " + message)
        @sys.exit(1)
        Json::null()
      }
      BusinessAcceptanceError::Io(_) => {
        println("business acceptance check failed: filesystem error")
        @sys.exit(1)
        Json::null()
      }
    }
    @fs.write_string_to_file(args[3], result.stringify(indent=2) + "\n") catch {
      _ => {
        println("business acceptance check failed: filesystem error")
        @sys.exit(1)
      }
    }
    println(
      Json::object({
        "output": Json::string(args[3]),
        "state": result_field(result, "state"),
        "acceptance_authorized": result_field(result, "acceptance_authorized"),
        "pending_decisions": result_array_count(result, "pending_decisions"),
        "deferred_decisions": result_array_count(result, "deferred_decisions"),
      }).stringify(),
    )
  }
}
