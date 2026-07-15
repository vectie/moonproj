///|
/// Build an explicit workflow-assignee promotion cohort. Assignments are
/// configuration only; they do not grant permission or decision authority.
pub(all) suberror WorkflowAssignmentPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> WorkflowAssignmentPlanError {
  WorkflowAssignmentPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise WorkflowAssignmentPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise WorkflowAssignmentPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise WorkflowAssignmentPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    Some(String(value)) => value
    Some(Number(value, ..)) => value.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => ""
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise WorkflowAssignmentPlanError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn root_array(
  value : Json,
  path : String,
) -> Array[Json] raise WorkflowAssignmentPlanError {
  match value {
    Array(values) => values
    _ => raise fail("expected array at " + path)
  }
}

///|
fn required_map(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Map[String, Json] raise WorkflowAssignmentPlanError {
  match fields.get(key) {
    Some(Object(values)) if !values.is_empty() => values
    _ => raise fail("expected non-empty object at " + path + "." + key)
  }
}

///|
fn map_text(mapping : Map[String, Json], key : String) -> String {
  match mapping.get(key) {
    Some(String(value)) => value
    Some(Number(value, ..)) => value.to_string()
    Some(True) => "true"
    Some(False) => "false"
    _ => ""
  }
}

///|
fn integer_or_zero(value : Json) -> Int {
  match value {
    Number(number, ..) if number == number.trunc() => number.to_int()
    String(text) => {
      let mut sign = 1
      let mut index = 0
      match text.get_char(0) {
        Some('-') => {
          sign = -1
          index = 1
        }
        Some('+') => index = 1
        _ => ()
      }
      let mut result = 0
      while index < text.length() {
        match text.get_char(index) {
          Some(char) if char >= '0' && char <= '9' =>
            result = result * 10 + char.to_int() - '0'.to_int()
          _ => return 0
        }
        index += 1
      }
      sign * result
    }
    _ => 0
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn sorted_unique(values : Array[String]) -> Array[Json] {
  let result : Array[Json] = []
  let ordered = [
    "invalid_weight", "missing_assignee_mapping", "missing_capability_mapping", "missing_or_duplicate_assignment_id",
    "missing_principal_mapping", "missing_scope_mapping", "missing_source_user",
    "missing_workflow_definition", "missing_workflow_step",
  ]
  for value in ordered {
    if values.contains(value) {
      result.push(Json::string(value))
    }
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
fn run(
  export_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise WorkflowAssignmentPlanError {
  let export_root = export_path
  let manifest = object(read_json(export_root + "/manifest.json"), "manifest")
  let source_sha256 = required_string(manifest, "source_sha256", "manifest")
  if source_sha256.length() != 64 {
    raise fail("export manifest has no valid source hash")
  }
  let config = object(read_json(mapping_path), "mapping")
  let capabilities = required_map(
    config, "workflow_capability_by_step", "mapping",
  )
  let assignee_by_user = required_map(config, "assignee_by_user", "mapping")
  let principal_by_process = required_map(
    config, "principal_by_process", "mapping",
  )
  let scope_by_process = required_map(config, "scope_by_process", "mapping")
  let definitions = root_array(
    read_json(export_root + "/tables/wf_process_def.json"),
    "definitions",
  )
  let steps = root_array(
    read_json(export_root + "/tables/wf_step_def.json"),
    "steps",
  )
  let assignments = root_array(
    read_json(export_root + "/tables/wf_step_assignee.json"),
    "assignments",
  )
  let users = root_array(
    read_json(export_root + "/tables/sys_user.json"),
    "users",
  )
  let definition_by_id : Map[String, Json] = {}
  for value in definitions {
    let _ = object(value, "workflow definition row")
    definition_by_id.set(text(value, "process_guid"), value)
  }
  let step_by_id : Map[String, Json] = {}
  for value in steps {
    let _ = object(value, "workflow step row")
    step_by_id.set(text(value, "step_guid"), value)
  }
  let user_ids : Array[String] = []
  for value in users {
    let _ = object(value, "workflow user row")
    user_ids.push(text(value, "user_id"))
  }
  let items : Array[Json] = []
  let seen_assignments : Array[String] = []
  let mut ready = 0
  for value in assignments {
    let _ = object(value, "workflow assignment row")
    let source_id = text(value, "assignee_guid")
    let step_id = text(value, "step_guid")
    let user_id = text(value, "assignee_user_guid")
    let reasons : Array[String] = []
    if source_id.is_empty() || seen_assignments.contains(source_id) {
      add_reason(reasons, "missing_or_duplicate_assignment_id")
    }
    seen_assignments.push(source_id)
    let step = step_by_id.get(step_id)
    let process_id = match step {
      Some(value) => text(value, "process_guid")
      None => ""
    }
    if step is None {
      add_reason(reasons, "missing_workflow_step")
    }
    let definition = definition_by_id.get(process_id)
    if definition is None {
      add_reason(reasons, "missing_workflow_definition")
    }
    if !user_ids.contains(user_id) {
      add_reason(reasons, "missing_source_user")
    }
    let assignee_id = map_text(assignee_by_user, user_id)
    if assignee_id.is_empty() {
      add_reason(reasons, "missing_assignee_mapping")
    }
    let principal_id = map_text(principal_by_process, process_id)
    if principal_id.is_empty() {
      add_reason(reasons, "missing_principal_mapping")
    }
    let scope = map_text(scope_by_process, process_id)
    if scope.is_empty() {
      add_reason(reasons, "missing_scope_mapping")
    }
    let capability = map_text(capabilities, step_id)
    if capability.is_empty() {
      add_reason(reasons, "missing_capability_mapping")
    }
    let weight = integer_or_zero(field(value, "weight").unwrap_or(Json::null()))
    if weight <= 0 {
      add_reason(reasons, "invalid_weight")
    }
    let target_id = "workflow-assignment:" + source_id
    let candidate = if reasons.is_empty() {
      let definition_value = definition.unwrap()
      let step_value = step.unwrap()
      Json::object({
        "assignment_id": Json::string(target_id),
        "process_id": Json::string(process_id),
        "process_key": field(definition_value, "process_key").unwrap_or(
          Json::null(),
        ),
        "step_id": Json::string(step_id),
        "assignee_id": Json::string(assignee_id),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "weight": json_int(weight),
        "step": Json::object({
          "step_id": Json::string(step_id),
          "capability": Json::string(capability),
          "required_weight": json_int(
            integer_or_zero(
              field(step_value, "threshold").unwrap_or(Json::null()),
            ).max(1),
          ),
        }),
      })
    } else {
      Json::null()
    }
    if reasons.is_empty() {
      ready += 1
    }
    items.push(
      Json::object({
        "source_table": Json::string("wf_step_assignee"),
        "source_id": Json::string(source_id),
        "target_type": Json::string("workflow_assignment"),
        "target_id": Json::string(target_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": Json::array(sorted_unique(reasons)),
        "warnings": Json::array([
          Json::string(
            "workflow assignment is configuration only; it does not grant permission or bypass decision authority",
          ),
        ]),
        "target_candidate": candidate,
      }),
    )
  }
  let mapping_version = map_text(config, "mapping_version")
  let report = Json::object({
    "format": Json::string("moonproj.erp.workflow-assignment-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha256),
    "source_sha256": Json::string(source_sha256),
    "mapping_version": Json::string(
      if mapping_version.is_empty() {
        "unversioned-workflow-assignment-map"
      } else {
        mapping_version
      },
    ),
    "cohort": Json::string("workflow-assignments-v1"),
    "summary": Json::object({
      "items": json_int(items.length()),
      "ready": json_int(ready),
      "quarantined": json_int(items.length() - ready),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise WorkflowAssignmentPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": json_int(items.length()),
      "ready": json_int(ready),
      "quarantined": json_int(items.length() - ready),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: workflow_assignment_plan <export> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    WorkflowAssignmentPlanError::InvalidInput(message) => {
      println("workflow assignment plan failed: " + message)
      @sys.exit(1)
    }
    WorkflowAssignmentPlanError::Io(_) => {
      println("workflow assignment plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
