///|
pub(all) suberror WorkflowPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> WorkflowPromotionPlanError {
  WorkflowPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise WorkflowPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise WorkflowPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise WorkflowPromotionPlanError {
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
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(value, ..) => value.to_int().to_int64()
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
fn sorted_reasons(values : Array[String]) -> Json {
  let unique : Array[String] = []
  for value in values {
    let mut found = false
    for existing in unique {
      if existing == value {
        found = true
      }
    }
    if !found {
      unique.push(value)
    }
  }
  unique.sort_by(fn(left, right) { left.compare(right) })
  Json::array(unique.map(fn(value) { Json::string(value) }))
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise WorkflowPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let capabilities = match config.get("workflow_capability_by_step") {
    None => {}
    Some(value) => object(value, "workflow_capability_by_step")
  }
  let definitions = match
    read_json(export_dir + "/tables/wf_process_def.json") {
    Array(values) => values
    _ => raise fail("workflow definitions must be an array")
  }
  let steps = match read_json(export_dir + "/tables/wf_step_def.json") {
    Array(values) => values
    _ => raise fail("workflow steps must be an array")
  }
  let items : Array[Json] = []
  for definition in definitions {
    let process_id = text(field(definition, "process_guid"))
    let process_steps : Array[Json] = []
    for step in steps {
      if text(field(step, "process_guid")) == process_id {
        process_steps.push(step)
      }
    }
    process_steps.sort_by(fn(left, right) {
      integer(field(left, "step_order"), 0L).compare(
        integer(field(right, "step_order"), 0L),
      )
    })
    let reasons : Array[String] = []
    if process_steps.is_empty() {
      reasons.push("missing_workflow_steps")
    }
    let candidate_steps : Array[Json] = []
    let mut previous_order : Int64 = 0
    for step in process_steps {
      let step_id = text(field(step, "step_guid"))
      let order = integer(field(step, "step_order"), 0L)
      let capability = capabilities.get(step_id).unwrap_or(Json::null())
      let capability_present = match capability {
        String(value) => !value.is_empty()
        _ => false
      }
      if !capability_present {
        reasons.push("missing_capability_mapping:" + step_id)
      }
      if order <= previous_order {
        reasons.push("non_increasing_step_order:" + step_id)
      }
      previous_order = order
      let threshold_value = field(step, "threshold")
      let threshold_default = match threshold_value {
        Null | False => true
        Number(value, ..) => value == 0.0
        String(value) => value.is_empty()
        _ => false
      }
      let threshold = if threshold_default {
        1L
      } else {
        integer(threshold_value, 1L)
      }
      let capability_value = match capability {
        String(value) if !value.is_empty() => capability
        _ => Json::null()
      }
      candidate_steps.push(
        Json::object({
          "step_id": Json::string(step_id),
          "process_id": Json::string(process_id),
          "step_key": field(step, "step_key"),
          "step_order": Json::number(order.to_double(), repr=order.to_string()),
          "step_type": Json::number(
            integer(field(step, "step_type"), 1L).to_double(),
            repr=integer(field(step, "step_type"), 1L).to_string(),
          ),
          "step_name": field(step, "step_name"),
          "threshold": Json::number(
            threshold.to_double(),
            repr=threshold.to_string(),
          ),
          "remind_days": field(step, "remind_days"),
          "warn_days": field(step, "warn_days"),
          "capability": capability_value,
        }),
      )
    }
    items.push(
      Json::object({
        "source_table": Json::string("wf_process_def"),
        "source_id": Json::string(process_id),
        "target_type": Json::string("workflow_definition"),
        "target_id": Json::string(process_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array([]),
        "target_candidate": if reasons.is_empty() {
          Json::object({
            "process_id": Json::string(process_id),
            "process_key": field(definition, "process_key"),
            "process_name": field(definition, "process_name"),
            "biz_type": field(definition, "biz_type"),
            "steps": Json::array(candidate_steps),
          })
        } else {
          Json::null()
        },
      }),
    )
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  let mapping_version = match config.get("mapping_version") {
    Some(value) => value
    None => Json::string("unversioned-workflow-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.workflow-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha),
    "source_sha256": Json::string(source_sha),
    "mapping_version": mapping_version,
    "summary": Json::object({
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise WorkflowPromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: workflow_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    WorkflowPromotionPlanError::InvalidInput(message) => {
      println("workflow promotion plan failed: " + message)
      @sys.exit(1)
    }
    WorkflowPromotionPlanError::Io(_) => {
      println("workflow promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
