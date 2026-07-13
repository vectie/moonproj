///|
pub(all) suberror TaskStateEvidenceError {
  InvalidInput
  Io(@fs.IOError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise TaskStateEvidenceError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaskStateEvidenceError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise TaskStateEvidenceError {
  match value {
    Object(value) => value
    _ => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise TaskStateEvidenceError {
  match obj.get(key) {
    Some(value) => value
    None => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise TaskStateEvidenceError {
  match required(obj, key) {
    String(value) if value.trim() != "" => value
    _ => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise TaskStateEvidenceError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise TaskStateEvidenceError {
  match required(obj, key) {
    Array(value) if value.length() > 0 => value
    _ => raise TaskStateEvidenceError::InvalidInput
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise TaskStateEvidenceError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.task-state-exception-review.v1" ||
    required_string(root, "state") != "review_required" ||
    required_bool(root, "cutover_authorized") {
    raise TaskStateEvidenceError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let exceptions = required_array(root, "exceptions")
  let accepted : Array[Json] = []
  for value in exceptions {
    let exception = object(value)
    let project_id = required_string(exception, "project_id")
    let source_id = required_string(exception, "source_id")
    if source_id != "state:" + project_id {
      raise TaskStateEvidenceError::InvalidInput
    }
    let reasons = required_array(exception, "reasons")
    let conflicts = required_array(exception, "dependency_conflicts")
    let observed_rows = required_array(exception, "observed_rows")
    match required(exception, "decision") {
      Null => ()
      _ => raise TaskStateEvidenceError::InvalidInput
    }
    match required(exception, "decision_owner") {
      Null => ()
      _ => raise TaskStateEvidenceError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string("jd_task"),
        "source_id": Json::string(source_id),
        "target_type": Json::string("project_task_state_observation"),
        "target_id": Json::string(
          "project-task-state-observation:" + project_id,
        ),
        "target_candidate": Json::object({
          "project_id": Json::string(project_id),
          "observation_policy": Json::string("quarantined_source_evidence"),
          "decision_required": Json::boolean(true),
          "target_state_mutated": Json::boolean(false),
          "reasons": Json::array(reasons),
          "dependency_conflicts": Json::array(conflicts),
          "observed_rows": Json::array(observed_rows),
          "decision": Json::null(),
          "decision_owner": Json::null(),
          "decision_at": Json::null(),
          "decision_notes": Json::null(),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("task-state-exception-evidence-v1"),
    "accepted_items": Json::array(accepted),
    "observation_count": Json::number(exceptions.length().to_double()),
    "decision_required": Json::boolean(true),
    "target_state_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise TaskStateEvidenceError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: task_state_evidence <exception-review.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      TaskStateEvidenceError::InvalidInput => {
        println("task-state evidence failed: invalid or decided input")
        @sys.exit(1)
      }
      TaskStateEvidenceError::Io(_) => {
        println("task-state evidence failed: filesystem error")
        @sys.exit(1)
      }
    }
  }
}
