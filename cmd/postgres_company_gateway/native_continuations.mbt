///|
fn native_continuation_accepted(task : Json) -> Bool {
  native_text(task, "status") == "done" ||
  native_text(native_field(task, "execution"), "acceptance") == "accepted"
}

///|
fn native_continuation_envelope(
  task : Json,
  candidate : Json,
  candidates : Array[Json],
  state : String,
  error : String,
) -> Json {
  let original = native_field(task, "execution")
  {
    "schema": "moonproj.task-continuations.v1",
    "task_id": native_text(task, "taskGuid"),
    "revision": native_field(task, "revision"),
    "original_run_id": native_text(original, "run_id"),
    "session_id": native_text(original, "session_id"),
    "original_command_id": native_text(original, "command_id"),
    "workspace": native_text(original, "workspace"),
    "acceptance": if native_continuation_accepted(task) {
      "accepted"
    } else {
      "pending"
    },
    "inspection_only": native_continuation_accepted(task),
    "continuations": native_array(task, "continuations"),
    "human_revisions": native_array(task, "human_revisions"),
    "selected_delivery_source": native_field(task, "selected_delivery_source"),
    "candidate": candidate,
    "candidates": candidates,
    "candidate_state": state,
    "error": error,
  }
}

///|
fn native_continuation_error(error : Error) -> (Int32, String) {
  match error {
    NativeContinuationError::Rejected(status, message) => (status, message)
    GatewayError::InvalidInput(message) => (400, message)
    GatewayError::Upstream(message) => (503, message)
    _ =>
      (
        503, "Exact continuation readback is unavailable; preserve this command identity and retry",
      )
  }
}

///|
async fn native_continuation_candidate(
  original : Json,
  command_id : String,
  claims : Json,
  events : Json,
  service : Json,
  inspect : async (Json, Json) -> Json,
) -> Json {
  let original_command = native_field(
    native_continuation_claim(
      original,
      claims,
      native_text(original, "command_id"),
    ),
    "command",
  )
  if native_text(original_command, "model") != native_text(original, "model") {
    raise NativeContinuationError::Rejected(
      409, "Original native model does not match captured execution",
    )
  }
  let captured_context = native_field(original, "product_context")
  if captured_context is Object(_) &&
    native_text(captured_context, "context_path") !=
    native_text(original_command, "context_path") {
    raise NativeContinuationError::Rejected(
      409, "Original native context does not match captured task requirements",
    )
  }
  let command = native_field(
    native_continuation_claim(original, claims, command_id),
    "command",
  )
  let candidate = native_continuation_readback(
    original, command, claims, events, service,
  )
  // Native acceptance alone is insufficient: require the same canonical,
  // immutable local input that Desk persisted before submitting.
  ignore(inspect(command, original_command))
  candidate
}

///|
async fn native_continuation_listing(
  task : Json,
  task_id : String,
  requested_command : String,
  read : async (String) -> Json,
  inspect : async (Json, Json) -> Json,
) -> Json {
  let original = native_continuation_original(task, task_id)
  if !requested_command.is_empty() && !valid_identifier(requested_command) {
    raise NativeContinuationError::Rejected(
      400, "An exact native command identifier is required",
    )
  }
  let base = "/v1/code/sessions/" +
    native_component(native_text(original, "session_id"))
  let query = "?book_root=" +
    native_component(native_text(original, "workspace"))
  let claims = read(base + "/runtime-claim" + query)
  let events = read(base + "/runtime-events" + query)
  let service = read(base + "/runtime-service" + query)
  if !requested_command.is_empty() {
    let candidate = native_continuation_candidate(
      original, requested_command, claims, events, service, inspect,
    )
    return native_continuation_envelope(
      task,
      candidate,
      [candidate],
      "ready",
      "",
    )
  }
  // Validate C0 and all claim categories even if no attributed candidate exists.
  ignore(
    native_continuation_claim(
      original,
      claims,
      native_text(original, "command_id"),
    ),
  )
  let candidates : Array[Json] = []
  let errors : Array[Json] = []
  for
    category in [
      "claimable_commands", "claimed_commands", "order_blocked_commands", "delivered_commands",
    ] {
    for item in native_array(claims, category) {
      let command = native_field(item, "command")
      let lineage = native_field(
        native_field(command, "payload"),
        "moonproj_continuation",
      )
      if native_text(lineage, "task_id") != task_id ||
        native_text(lineage, "run_id") != native_text(original, "run_id") ||
        native_text(lineage, "original_command_id") !=
        native_text(original, "command_id") {
        continue
      }
      let command_id = native_text(item, "command_id")
      candidates.push(
        native_continuation_candidate(
          original, command_id, claims, events, service, inspect,
        ),
      ) catch {
        error =>
          errors.push({
            "command_id": command_id,
            "error": native_continuation_error(error).1,
          })
      }
    }
  }
  let envelope = native_continuation_envelope(
    task,
    Json::null(),
    candidates,
    "not_requested",
    "",
  )
  match envelope {
    Object(fields) => {
      fields["candidate_errors"] = Json::array(errors)
      Json::object(fields)
    }
    _ => envelope
  }
}

///|
async fn native_continuation_detail(
  bridge : NativeBridge,
  task_id : String,
) -> (ProxyResult, Json) raise GatewayError {
  let result = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
  if result.status != 200 {
    return (result, Json::null())
  }
  let task = native_field(
    native_field(native_result_json(result), "data"),
    "task",
  )
  if native_text(task, "taskGuid") != task_id {
    raise GatewayError::Upstream(
      "Company service returned another task identity",
    )
  }
  (result, task)
}

///|
async fn native_list_continuations(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
  requested : String,
  human_revision_id~ : String = "",
) -> ProxyResult {
  let (detail, task) = native_continuation_detail(bridge, task_id)
  if detail.status != 200 {
    return detail
  }
  try {
    let original = native_continuation_original(task, task_id)
    if !human_revision_id.is_empty() {
      if !requested.is_empty() {
        raise NativeContinuationError::Rejected(
          400, "Inspect one exact return source at a time",
        )
      }
      let candidate = native_human_revision_candidate(
        task, human_revision_id, moonclaw_uri,
      )
      let envelope = native_continuation_envelope(
        task,
        Json::null(),
        [],
        "ready",
        "",
      )
      if envelope is Object(fields) {
        fields["human_revision_candidate"] = candidate
        fields["human_revision_content"] = Json::string(
          human_revision_content(original, candidate),
        )
      }
      return native_json_result(200, envelope)
    }
    let control = native_load_control(moonclaw_uri)
    native_json_result(
      200,
      native_continuation_listing(
        task,
        task_id,
        requested,
        path => native_request(control, @http.Get, path, ""),
        (command, original_command) => {
          native_continuation_snapshot(original, command, original_command)
        },
      ),
    )
  } catch {
    error => {
      let (status, message) = native_continuation_error(error)
      native_json_result(
        status,
        native_continuation_envelope(
          task,
          Json::null(),
          [],
          if status == 404 {
            "not_found"
          } else if status == 503 {
            "runtime_unavailable"
          } else {
            "invalid_candidate"
          },
          message,
        ),
      )
    }
  }
}

///|
fn native_continuation_import_body(
  original : Json,
  requested : Json,
  candidate : Json,
) -> Json raise NativeContinuationError {
  if native_text(requested, "original_run_id") !=
    native_text(original, "run_id") {
    raise NativeContinuationError::Rejected(
      409, "Return hint belongs to a different original run",
    )
  }
  if native_field(requested, "select_for_delivery") != Json::boolean(true) &&
    native_field(requested, "select_for_delivery") != Json::boolean(false) {
    raise NativeContinuationError::Rejected(
      400, "Choose explicitly whether to select this result for delivery",
    )
  }
  let source = native_field(requested, "selected_delivery_source")
  if native_text(source, "type") == "original" {
    if native_text(source, "original_run_id") != native_text(original, "run_id") ||
      native_text(source, "command_id") != native_text(original, "command_id") ||
      !native_bool(requested, "select_for_delivery") ||
      !native_text(requested, "continuation_id").is_empty() {
      raise NativeContinuationError::Rejected(
        409, "Original delivery source must match the captured execution",
      )
    }
    return {
      "selected_delivery_source": {
        "type": "original",
        "original_run_id": native_text(original, "run_id"),
        "command_id": native_text(original, "command_id"),
      },
      "select_for_delivery": true,
      "authority": native_field(requested, "authority"),
    }
  }
  if native_text(candidate, "continuation_id") !=
    native_text(requested, "continuation_id") ||
    native_text(candidate, "command_id") != native_text(requested, "command_id") ||
    native_text(candidate, "original_run_id") != native_text(original, "run_id") {
    raise NativeContinuationError::Rejected(
      409, "Return hint does not identify this exact canonical continuation",
    )
  }
  // Only canonical fields cross the internal boundary. Browser summaries,
  // receipts, workspace hints and result snapshots are deliberately ignored.
  {
    "continuation": candidate,
    "select_for_delivery": native_field(requested, "select_for_delivery"),
    "authority": native_field(requested, "authority"),
  }
}

///|
async fn native_continuation_observe(
  bridge : NativeBridge,
  task_id : String,
  body : Json,
  key : String,
) -> ProxyResult raise GatewayError {
  if @encoding/utf8.encode(body.stringify()).length() > MAX_BODY_BYTES {
    return native_json_result(413, {
      "schema": "moonproj.task-continuations.v1",
      "task_id": task_id,
      "candidate": native_field(body, "continuation"),
      "candidate_state": "attachment_too_large",
      "error": "The exact native result exceeds the existing 128 KiB company observation limit; native work is preserved and no evidence was truncated or task source changed",
    })
  }
  let path = "/api/company/internal/plan/tasks/" +
    task_id +
    "/continuations/observe"
  let request : @http.Request = {
    meth: @http.Post,
    path,
    headers: {
      "X-Moonproj-Actor": bridge.actor,
      "Content-Type": "application/json",
    },
  }
  proxy_request(
    bridge.service_uri,
    bridge.service_token,
    bridge.actor_signing_secret,
    @http.Post,
    path,
    request,
    @encoding/utf8.encode(body.stringify()),
    Some(key),
  )
}

///|
async fn native_import_continuation(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
  requested : Json,
  key : String,
) -> ProxyResult {
  let (detail, task) = native_continuation_detail(bridge, task_id)
  if detail.status != 200 {
    return detail
  }
  let original = native_continuation_original(task, task_id)
  if native_continuation_accepted(task) {
    return native_json_result(
      200,
      native_continuation_envelope(
        task,
        Json::null(),
        [],
        "inspection_only",
        "Accepted work is inspection-only; its report and selected source were not changed",
      ),
    )
  }
  if !native_text(requested, "human_revision_id").is_empty() {
    let candidate = native_human_revision_candidate(
      task,
      native_text(requested, "human_revision_id"),
      moonclaw_uri,
    )
    return native_continuation_observe(
      bridge,
      task_id,
      native_human_revision_import_body(original, requested, candidate),
      key,
    )
  }
  let candidate = if native_text(
      native_field(requested, "selected_delivery_source"),
      "type",
    ) ==
    "original" {
    Json::null()
  } else {
    let command_id = native_text(requested, "command_id")
    if !valid_identifier(command_id) {
      raise NativeContinuationError::Rejected(
        400, "An exact continuation command identifier is required",
      )
    }
    let control = native_load_control(moonclaw_uri)
    let listing = native_continuation_listing(
      task,
      task_id,
      command_id,
      path => native_request(control, @http.Get, path, ""),
      (command, original_command) => {
        native_continuation_snapshot(original, command, original_command)
      },
    )
    native_field(listing, "candidate")
  }
  let observation = native_continuation_import_body(
    original, requested, candidate,
  )
  native_continuation_observe(bridge, task_id, observation, key)
}
