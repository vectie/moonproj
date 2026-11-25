///|
fn book_guidance_query_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/guidance-query"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) && id != "." && id != ".." {
      return Some(id)
    }
  }
  None
}

///|
/// A minimal source identity for a later-task query, separate from the accepted
/// outcome/report handoff. No actor, workspace, task text or source body leaves.
fn book_guidance_query_projection(task : Json) -> Json raise GatewayError {
  let id = native_text(task, "taskGuid")
  let project = native_text(task, "projGuid")
  let product = native_text(task, "product_id")
  guard valid_identifier(id) &&
    valid_identifier(project) &&
    (product.is_empty() || valid_identifier(product)) &&
    native_field(task, "revision") is Number(revision, ..) &&
    revision >= 1 &&
    revision <= 9007199254740991.0 &&
    revision.trunc() == revision &&
    ["pending", "in_progress"].contains(native_text(task, "status")) &&
    !(native_field(task, "execution") is Object(_)) else {
    raise GatewayError::InvalidInput(
      "Refresh a canonical formal task before its first Start to choose optional Book guidance",
    )
  }
  let snapshot = (
    {
      "task_id": id,
      "project_id": project,
      "product_id": product,
      "revision": native_field(task, "revision"),
    } : Json).stringify()
  let conditions : Array[Json] = [{ "key": "project_id", "value": project }]
  if !product.is_empty() {
    conditions.push({ "key": "suite_product_id", "value": product })
  }
  {
    "contract_version": "moonproj.book-guidance-query.v1",
    "source_product": "moonproj",
    "target_task": lesson_handoff_ref(
      id,
      native_field(task, "revision"),
      snapshot,
    ),
    "task_snapshot": snapshot,
    "conditions": Json::array(conditions),
    "authorizing": false,
  }
}

///|
async fn book_guidance_query_task(
  bridge : NativeBridge,
  task_id : String,
) -> ProxyResult raise GatewayError {
  let detail = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
  if detail.status != 200 {
    return detail
  }
  let task = native_field(
    native_field(native_result_json(detail), "data"),
    "task",
  )
  if native_text(task, "taskGuid") != task_id {
    raise GatewayError::Upstream("Company service returned another task")
  }
  native_json_result(200, book_guidance_query_projection(task))
}

///|
/// Check optional selection before touching runtime configuration. Once an
/// execution exists, only its original captured bytes can be resumed. A reload
/// may omit selection; a newly supplied differing selection is never ignored.
fn native_book_guidance(task : Json, body : Json) -> Json? raise GatewayError {
  let supplied = native_field(body, "book_guidance")
  let existing = native_field(task, "execution")
  if existing is Object(_) {
    let stored_digest = if native_text(existing, "book_guidance_sha256").is_empty() {
      native_text(native_field(existing, "book_guidance"), "sha256")
    } else {
      native_text(existing, "book_guidance_sha256")
    }
    if supplied != Json::null() &&
      native_guidance_digest(supplied) != stored_digest {
      raise GatewayError::InvalidInput(
        "This task already has a reserved execution input; remove the new optional guidance and resume the original execution",
      )
    }
    return None
  }
  if supplied == Json::null() {
    return None
  }
  let handoff = book_guidance_query_projection(task)
  @task_evidence.validate_guidance_selection(supplied, handoff) catch {
    _ =>
      raise GatewayError::InvalidInput(
        "Selected Book guidance is invalid or the task changed; refresh or remove the optional selection before Start",
      )
  }
  Some(supplied)
}

///|
fn native_guidance_normalized(value : Json) -> Json {
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      let normalized : Map[String, Json] = Map([])
      for key in keys {
        normalized[key] = native_guidance_normalized(fields[key])
      }
      Json::object(normalized)
    }
    Array(items) => Json::array(items.map(native_guidance_normalized))
    Number(value, ..) => Json::number(value)
    _ => value
  }
}

///|
fn native_guidance_digest(selection : Json) -> String {
  native_context_hash(
    @encoding/utf8.encode(native_guidance_normalized(selection).stringify()),
  )
}
