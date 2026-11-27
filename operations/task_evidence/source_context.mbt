///|
#derive(Debug, Eq)
pub suberror SourceContextError {
  InvalidSourceContext(String)
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
/// Optional source context extends the existing signed request. Empty/absent
/// input retains the exact legacy request shape. It confers no authority.
pub fn with_source_context(
  request : Json,
  body : Json,
) -> Json raise SourceContextError {
  let source = match field(body, "source_context") {
    Null => return request
    Object(fields) => fields
    _ => raise InvalidSourceContext("source_context must be an object")
  }
  for key, _ in source {
    if key != "reference" && key != "problem" {
      raise InvalidSourceContext(
        "source_context accepts only reference and problem",
      )
    }
  }
  let normalized : Map[String, Json] = Map([])
  for key in ["reference", "problem"] {
    let value = match source.get(key) {
      None | Some(Null) => ""
      Some(String(value)) => value.trim().to_owned()
      _ => raise InvalidSourceContext("source_context." + key + " must be text")
    }
    if value.length() > 8192 {
      raise InvalidSourceContext("source_context." + key + " is too long")
    }
    normalized[key] = Json::string(value)
  }
  if normalized.values().all(value => value == Json::string("")) {
    return request
  }
  let fields = match request {
    Object(fields) => fields.copy()
    _ => raise InvalidSourceContext("task request must be an object")
  }
  fields["source_context"] = Json::object(normalized)
  Json::object(fields)
}

///|
/// Shared prompt fragment for both product-bound and standalone task execution.
/// The surrounding native request already supplies immutable execution bytes.
pub fn source_prompt(task : Json) -> String {
  let source = field(task, "source_context")
  let reference = text(source, "reference")
  let problem = text(source, "problem")
  if reference.is_empty() && problem.is_empty() {
    ""
  } else {
    "\nSource reference (context, not additional authority): " +
    Json::string(reference).stringify() +
    "\nObserved problem: " +
    Json::string(problem).stringify() +
    "\n"
  }
}
