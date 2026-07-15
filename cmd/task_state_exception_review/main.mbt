///|
pub(all) suberror TaskStateExceptionReviewError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> TaskStateExceptionReviewError {
  TaskStateExceptionReviewError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TaskStateExceptionReviewError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaskStateExceptionReviewError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TaskStateExceptionReviewError {
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
fn array(
  value : Json,
  path : String,
) -> Array[Json] raise TaskStateExceptionReviewError {
  match value {
    Array(values) => values
    _ => raise fail("expected array at " + path)
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
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise TaskStateExceptionReviewError {
  let plan = object(read_json(plan_path), "plan")
  if text(field(Json::object(plan), "format")) !=
    "moonproj.erp.task-state-promotion-plan.v1" {
    raise fail("unexpected task-state plan format")
  }
  let items = array(field(Json::object(plan), "items"), "items")
  let exceptions : Array[Json] = []
  for item_value in items {
    let item = object(item_value, "task-state item")
    if text(field(Json::object(item), "target_type")) != "project_task_state" ||
      text(field(Json::object(item), "disposition")) != "quarantined" {
      continue
    }
    let candidate = field(Json::object(item), "target_candidate")
    let observed_rows = match field(Json::object(item), "observed_rows") {
      Array(values) => Json::array(values)
      _ =>
        match candidate {
          Object(fields) =>
            match fields.get("rows") {
              Some(Array(values)) => Json::array(values)
              _ => Json::array([])
            }
          _ => Json::array([])
        }
    }
    let reasons = match field(Json::object(item), "reasons") {
      Array(values) => values
      _ => []
    }
    let conflicts : Array[Json] = []
    for reason_value in reasons {
      match reason_value {
        String(reason) if reason.has_prefix("dependency_not_completed:") => {
          let parts = reason
            .split(":")
            .map(fn(part) { part.to_owned() })
            .to_array()
          let task_id = if parts.length() > 1 { parts[1] } else { "" }
          let parent_id = if parts.length() > 2 { parts[2] } else { "" }
          conflicts.push(
            Json::object({
              "task_id": Json::string(task_id),
              "parent_task_id": Json::string(parent_id),
              "reason": Json::string(reason),
            }),
          )
        }
        _ => ()
      }
    }
    exceptions.push(
      Json::object({
        "project_id": field(Json::object(item), "target_id"),
        "source_id": field(Json::object(item), "source_id"),
        "reasons": Json::array(reasons),
        "dependency_conflicts": Json::array(conflicts),
        "observed_rows": observed_rows,
        "decision": Json::null(),
        "decision_owner": Json::null(),
        "decision_at": Json::null(),
        "decision_notes": Json::null(),
      }),
    )
  }
  if exceptions.is_empty() {
    raise fail("task-state plan contains no quarantined exceptions")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.task-state-exception-review.v1"),
    "source_snapshot_id": field(Json::object(plan), "source_snapshot_id"),
    "mapping_version": field(Json::object(plan), "mapping_version"),
    "state": Json::string("review_required"),
    "cutover_authorized": Json::boolean(false),
    "allowed_decisions": Json::array([
      Json::string("retain_source_evidence"),
      Json::string("approve_dependency_repair"),
      Json::string("map_state_as_observed_only"),
      Json::string("exclude_from_target"),
    ]),
    "exceptions": Json::array(exceptions),
    "warning": Json::string(
      "No decision is inferred; target task state remains unchanged until a named owner approves one decision per exception.",
    ),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TaskStateExceptionReviewError::Io(error)
  }
  println(
    Json::object({
      "exceptions": Json::number(
        exceptions.length().to_double(),
        repr=exceptions.length().to_string(),
      ),
      "output": Json::string(output_path),
      "state": Json::string("review_required"),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: task_state_exception_review <plan.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    TaskStateExceptionReviewError::InvalidInput(message) => {
      println("task-state exception review failed: " + message)
      @sys.exit(1)
    }
    TaskStateExceptionReviewError::Io(_) => {
      println("task-state exception review failed: filesystem error")
      @sys.exit(1)
    }
  }
}
