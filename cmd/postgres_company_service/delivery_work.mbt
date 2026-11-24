///|
fn plan_task_delivery_changes(
  current : Json,
  body : Json,
) -> Json raise CompanyServiceError {
  let fields : Map[String, Json] = Map([])
  for key in ["delivery_mode", "delivery_limits"] {
    if json_field(body, key) is Some(value) {
      guard value is String(text) else {
        raise reject(422, key + " must be text")
      }
      if key == "delivery_mode" && !["", "coordinated"].contains(text) {
        raise reject(422, "unsupported delivery mode")
      }
      if json_field(current, "execution") is Some(Object(_)) &&
        text != json_text(current, key, "") {
        raise reject(
          409, "delivery scope is captured by the existing execution",
        )
      }
      fields[key] = value
    }
  }
  Json::object(fields)
}

///|
fn plan_task_execution_workspace(task : Json) -> String {
  let root = json_text(task, "execution_workspace", "")
  if json_text(task, "delivery_mode", "") == "coordinated" {
    root +
    "/.moonproj-deliveries/" +
    json_text(task, "task_id", "") +
    "/coordinator"
  } else {
    root
  }
}
