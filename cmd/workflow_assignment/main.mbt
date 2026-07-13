///|
pub(all) suberror AssignmentError {
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Workflow(@workflow.WorkflowError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise AssignmentError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AssignmentError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise AssignmentError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise AssignmentError {
  match value {
    Object(value) => value
    _ => raise AssignmentError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise AssignmentError {
  match obj.get(key) {
    Some(value) => value
    None => raise AssignmentError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise AssignmentError {
  match required(obj, key) {
    String(value) => value
    _ => raise AssignmentError::InvalidInput
  }
}

///|
fn required_int(
  obj : Map[String, Json],
  key : String,
) -> Int raise AssignmentError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise AssignmentError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise AssignmentError {
  match required(obj, key) {
    Array(value) => value
    _ => raise AssignmentError::InvalidInput
  }
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  actor_id : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id,
    capability: "workflow:assignment:add",
    scope,
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn strings_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn run(plan_path : String, output_path : String) -> Unit raise AssignmentError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.workflow-assignment-plan.v1" {
    raise AssignmentError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = required_array(root, "items")
  let actor_id = "migration"
  let accepted : Array[Json] = []
  let assignment_ids : Array[String] = []
  let attachment_ids : Array[String] = []
  for item_value in items {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    if required_string(item, "target_type") != "workflow_assignment" {
      raise AssignmentError::InvalidInput
    }
    if required_string(item, "disposition") != "ready_for_domain_import" {
      raise AssignmentError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = object(required(item, "target_candidate"))
    let step = object(required(candidate, "step"))
    let process_id = required_string(candidate, "process_id")
    let process_key = required_string(candidate, "process_key")
    let principal_id = required_string(candidate, "principal_id")
    let scope = required_string(candidate, "scope")
    let definition = @workflow.ProcessDefinition::new(
      process_id~,
      process_key~,
      steps=[
        {
          step_id: required_string(step, "step_id"),
          capability: required_string(step, "capability"),
          required_weight: required_int(step, "required_weight"),
        },
      ],
    ) catch {
      _ => raise AssignmentError::InvalidInput
    }
    let assignment = definition.assign_step(
      assignment_id=required_string(candidate, "assignment_id"),
      step_id=required_string(candidate, "step_id"),
      assignee_id=required_string(candidate, "assignee_id"),
      principal_id~,
      scope~,
      weight=required_int(candidate, "weight"),
      actor_id~,
      grant=grant(
        "workflow-assignment/" + source_id,
        principal_id,
        actor_id,
        scope,
      ),
    ) catch {
      _ => raise AssignmentError::InvalidInput
    }
    let attached_definition = definition.attach_assignment(assignment) catch {
      _ => raise AssignmentError::InvalidInput
    }
    if attached_definition.assignments.length() != 1 {
      raise AssignmentError::InvalidInput
    }
    let attachment = attached_definition.assignment_attachment(
      assignment_id=assignment.assignment_id,
    ) catch {
      _ => raise AssignmentError::InvalidInput
    }
    if attachment.grants_authority || attachment.approves_instance {
      raise AssignmentError::InvalidInput
    }
    let attached_candidate = match candidate.get("attachment_state") {
      None | Some(Null) =>
        Json::object({
          "attachment_id": Json::string(attachment.attachment_id),
          "attachment_state": Json::string("attached"),
          "attachment_process_id": Json::string(attachment.process_id),
          "attachment_step_id": Json::string(attachment.step_id),
          "configuration_only": Json::boolean(true),
          "grants_authority": Json::boolean(attachment.grants_authority),
          "approves_instance": Json::boolean(attachment.approves_instance),
        })
      Some(String(value)) if value == "attached" =>
        Json::object({
          "attachment_id": Json::string(attachment.attachment_id),
          "attachment_state": Json::string(value),
          "attachment_process_id": Json::string(attachment.process_id),
          "attachment_step_id": Json::string(attachment.step_id),
          "configuration_only": Json::boolean(true),
          "grants_authority": Json::boolean(attachment.grants_authority),
          "approves_instance": Json::boolean(attachment.approves_instance),
        })
      _ => raise AssignmentError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("workflow_assignment"),
        "target_id": Json::string(assignment.assignment_id),
        "target_candidate": Json::object({
          "assignment": candidate,
          "attachment": attached_candidate,
        }),
      }),
    )
    assignment_ids.push(assignment.assignment_id)
    attachment_ids.push("workflow-attachment:" + assignment.assignment_id)
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("workflow-assignments-v1"),
    "accepted_items": Json::array(accepted),
    "workflow_assignment_ids": strings_json(assignment_ids),
    "workflow_assignment_attachment_ids": strings_json(attachment_ids),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise AssignmentError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: workflow_assignment <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      AssignmentError::Quarantined(source) => {
        println("workflow assignment refused quarantined item: " + source)
        @sys.exit(1)
      }
      AssignmentError::InvalidInput => {
        println("workflow assignment failed: invalid input")
        @sys.exit(1)
      }
      AssignmentError::Io(_) => {
        println("workflow assignment failed: filesystem error")
        @sys.exit(1)
      }
      AssignmentError::Workflow(_) => {
        println("workflow assignment failed: \\{to_repr(error)}")
        @sys.exit(1)
      }
    }
  }
}
