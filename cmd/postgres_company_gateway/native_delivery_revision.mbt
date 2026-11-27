///|
fn native_delivery_revision_snapshot(
  task : Json,
  request : Json,
  original_command : Json,
) -> Json {
  let original = native_field(task, "execution")
  let key = native_text(request, "key")
  let id = "delivery-" +
    hmac_hex(
      "moonproj-delivery-revision-v1",
      native_text(task, "taskGuid") + ":" + key,
    )
  let command_id = id + "-turn"
  let instruction = native_text(request, "instruction")
  let prior = native_text(request, "prior_command_id")
  let input_text = "# Delivery revision\n" +
    instruction +
    "\n\n# Original brief\n" +
    native_text(task, "taskName") +
    "\n" +
    native_text(task, "remarks") +
    "\n\n# Prior result\n" +
    prior +
    "\n" +
    native_text(request, "prior_summary") +
    "\n\n" +
    native_delivery_prompt(task) +
    native_delivery_progress_prompt(task, command_id)
  let input : Json = {
    "path": native_continuation_directory(id) + "/input.md",
    "sha256": native_context_hash(@encoding/utf8.encode(input_text)),
  }
  let lineage : Json = {
    "schema": "moonproj.work-continuation.v1",
    "continuation_id": id,
    "task_id": native_text(task, "taskGuid"),
    "run_id": native_text(original, "run_id"),
    "original_command_id": native_text(original, "command_id"),
    "prior_result_command_id": prior,
    "input": input,
  }
  let command : Json = {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": native_text(original, "session_id"),
    "book_root": native_text(original, "workspace"),
    "model": native_text(original, "model"),
    "web_search": false,
    "text": input_text,
    "context_path": native_text(input, "path"),
    "packet": { "command_id": command_id, "client_turn_id": id },
    "payload": {
      "moonproj_continuation": lineage,
      "planner_allowed_tools": ToJson::to_json(native_delivery_tools()),
    },
  }
  let body = command.stringify()
  {
    "schema": "moondesk.work-continuation-snapshot.v1",
    "continuation_id": id,
    "command_id": command_id,
    "client_turn_id": id,
    "prior_result_command_id": prior,
    "model": native_text(original, "model"),
    "instruction": input_text,
    "input": input,
    "input_text": input_text,
    "request_body": body,
    "request_sha256": native_context_hash(@encoding/utf8.encode(body)),
    "source": {
      "task_id": native_text(task, "taskGuid"),
      "run_id": native_text(original, "run_id"),
      "session_id": native_text(original, "session_id"),
      "original_command_id": native_text(original, "command_id"),
      "book_root": native_text(original, "workspace"),
    },
    "original_context": {
      "path": native_text(original_command, "context_path"),
      "sha256": native_text(native_field(original, "product_context"), "sha256"),
    },
    "prior_result": { "command_id": prior },
  }
}

///|
async fn native_delivery_original_command(
  control : NativeControl,
  execution : Json,
) -> Json {
  let claims = native_request(
    control,
    @http.Get,
    "/v1/code/sessions/" +
    native_component(native_text(execution, "session_id")) +
    "/runtime-claim?book_root=" +
    native_component(native_text(execution, "workspace")),
    "",
  )
  let original = native_field(
    native_continuation_claim(
      execution,
      claims,
      native_text(execution, "command_id"),
    ),
    "command",
  )
  if native_text(original, "model") != native_text(execution, "model") {
    raise fail("Native original model differs from this delivery")
  }
  original
}

///|
async fn native_delivery_write_once(
  root : String,
  relative : String,
  text : String,
) -> Unit {
  let canonical = @fs.realpath(root)
  let parts = relative.split("/").map(p => p.to_owned()).collect()
  let directory = canonical + "/" + parts[:parts.length() - 1].join("/")
  native_delivery_directory(directory)
  if @fs.realpath(directory) != directory {
    raise fail("Delivery input directory is not canonical")
  }
  let path = canonical + "/" + relative
  @fs.write_file(path, @encoding/utf8.encode(text), create_mode=CreateNew) catch {
    _ => {
      let saved = native_continuation_read_file(root, relative, 8 * 1024 * 1024)
      if saved != @encoding/utf8.encode(text) {
        raise fail("Saved delivery revision conflicts with this request")
      }
    }
  }
}

///|
async fn native_delivery_directory(path : String) -> Unit {
  if (@fs.kind(path, follow_symlink=false) catch { _ => @fs.FileKind::Regular })
    is Directory {
    if @fs.realpath(path) != path {
      raise fail("Delivery directory is not canonical")
    }
    return
  }
  // Check existing parents before creation, so a feature-owned symlink cannot
  // create directories outside the founder-selected book even on a failed run.
  let parent = native_control_root(path)
  if parent == path || parent.is_empty() {
    raise fail("Invalid delivery directory")
  }
  native_delivery_directory(parent)
  @fs.mkdir(path) catch {
    error =>
      if !((@fs.kind(path, follow_symlink=false) catch {
          _ => @fs.FileKind::Regular
        })
        is Directory) {
        raise error
      }
  }
}

///|
async fn native_delivery_progress_revision(
  bridge : NativeBridge,
  control : NativeControl,
  task : Json,
) -> Unit raise GatewayError {
  if native_text(task, "created_by") != bridge.actor {
    return
  }
  let execution = native_field(task, "execution")
  let request = native_field(execution, "revision_request")
  if !(request is Object(_)) ||
    native_text(execution, "control_state") != "revising" {
    return
  }
  try {
    let snapshot = native_field(request, "snapshot")
    let command = @json.parse(native_text(snapshot, "request_body"))
    let id = native_text(snapshot, "continuation_id")
    let directory = native_continuation_directory(id)
    let root = native_text(execution, "workspace")
    native_delivery_write_once(
      root,
      directory + "/input.md",
      native_text(snapshot, "input_text"),
    )
    native_delivery_write_once(
      root,
      directory + "/submission.json",
      snapshot.stringify(),
    )
    let original_command = native_delivery_original_command(control, execution)
    native_continuation_validate_snapshot(
      execution,
      command,
      original_command,
      snapshot,
      @encoding/utf8.encode(native_text(snapshot, "input_text")),
    )
    let base = "/v1/code/sessions/" +
      native_component(native_text(execution, "session_id"))
    if native_bool(request, "supersedes_unfinished") {
      // Suspension seals sessions but does not settle their paused commands.
      // Replaying this exact native cancel cannot cancel its later successor.
      let cancellation = native_delivery_replacement_command(execution, request)
      let settled = native_request(
        control,
        @http.Post,
        base + "/turns",
        cancellation.stringify(),
      )
      if !native_bool(settled, "accepted") ||
        native_text(settled, "command_id") !=
        native_text(native_field(cancellation, "packet"), "command_id") ||
        native_text(settled, "session_id") !=
        native_text(execution, "session_id") {
        raise fail("Paused command settlement is not yet confirmed")
      }
    }
    let accepted = native_request(
      control,
      @http.Post,
      base + "/turns",
      native_text(snapshot, "request_body"),
    )
    if !native_bool(accepted, "accepted") ||
      native_text(accepted, "command_id") != native_text(snapshot, "command_id") ||
      native_text(accepted, "session_id") !=
      native_text(execution, "session_id") ||
      native_text(accepted, "book_root") != root {
      raise fail("Runtime has not acknowledged this exact revision")
    }
    let listing = native_continuation_listing(
      task,
      native_text(task, "taskGuid"),
      native_text(snapshot, "command_id"),
      path => native_request(control, @http.Get, path, ""),
      (candidate, original) => {
        native_continuation_snapshot(execution, candidate, original)
      },
    )
    let candidate = native_field(listing, "candidate")
    let completed = native_text(candidate, "state") == "completed"
    let body : Json = {
      "continuation": candidate,
      "select_for_delivery": completed,
      "authority": native_delivery_authority(bridge, task),
    }
    let result = native_continuation_observe(
      bridge,
      native_text(task, "taskGuid"),
      body,
      "delivery-observe-" + hmac_hex("delivery-observation", body.stringify()),
    )
    if result.status != 200 && result.status != 201 {
      raise fail("Company service has not confirmed this revision")
    }
    native_company_observe(
      bridge,
      native_text(task, "taskGuid"),
      native_delivery_control_observation(
        execution,
        if completed ||
          ["failed", "cancelled"].contains(native_text(candidate, "state")) {
          "active"
        } else {
          "revising"
        },
        "",
        Json::null(),
      ),
    )
  } catch {
    _ =>
      raise GatewayError::Upstream(
        "Delivery revision is not yet confirmed; retry the saved request without creating another turn",
      )
  }
}

///|
async fn native_revise_delivery(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
  body : Json,
  is_resume : Bool,
) -> ProxyResult raise GatewayError {
  let (detail, task) = native_continuation_detail(bridge, task_id)
  if detail.status != 200 {
    return detail
  }
  if !native_coordinated(task) || native_continuation_accepted(task) {
    return native_json_result(409, {
      "error": "Open an unaccepted coordinated delivery before revising it",
    })
  }
  let execution = native_field(task, "execution")
  if !(execution is Object(_)) {
    return native_json_result(409, { "error": "Start this delivery first" })
  }
  let previous = native_field(execution, "revision_request")
  let key = native_text(body, "idempotency_key")
  let request = if is_resume &&
    native_text(execution, "control_state") == "revising" {
    previous
  } else if native_text(previous, "key") == key {
    previous
  } else {
    if native_text(execution, "control_state") == "revising" {
      return native_json_result(409, {
        "error": "Recover the existing delivery revision before requesting another one",
      })
    }
    let instruction = if is_resume {
      "Continue this delivery from its retained work. Reuse completed contributions, finish the unfinished work and produce the integrated artifact. Do not repeat already successful operations."
    } else {
      native_text(body, "instruction").trim().to_owned()
    }
    if instruction.is_empty() || !valid_identifier(key) {
      return native_json_result(422, {
        "error": "Describe the requested changes",
      })
    }
    let selected = native_field(task, "selected_delivery_source")
    let prior = if native_text(selected, "type") == "continuation" {
      native_text(selected, "command_id")
    } else {
      native_text(execution, "command_id")
    }
    let prior_record = native_array(task, "continuations")
      .filter(c => native_text(c, "command_id") == prior)
      .get(0)
      .unwrap_or(execution)
    if !native_terminal(native_text(prior_record, "state")) &&
      native_text(execution, "control_state") != "stopped" {
      return native_json_result(409, {
        "error": "Stop or finish the current work before starting a new delivery revision",
      })
    }
    let request : Json = {
      "key": key,
      "instruction": instruction,
      "prior_command_id": prior,
      "prior_summary": native_text(prior_record, "summary"),
      "supersedes_unfinished": !native_terminal(
        native_text(prior_record, "state"),
      ),
    }
    let snapshot = native_delivery_revision_snapshot(
      task,
      request,
      native_delivery_original_command(
        native_load_control(moonclaw_uri),
        execution,
      ),
    ) catch {
      _ =>
        raise GatewayError::InvalidInput("Unable to capture delivery revision")
    }
    if request is Object(fields) {
      fields["snapshot"] = snapshot
    }
    request
  }
  let intent = native_delivery_control_observation(
    execution,
    "revising",
    "",
    Json::null(),
  )
  if intent is Object(fields) {
    fields["revision_request"] = request
  }
  let persisted = native_company_request(
    bridge,
    @http.Post,
    "/api/company/internal/plan/tasks/" + task_id + "/execution/control",
    { "execution": intent, "authority": native_field(body, "authority") },
  )
  if persisted.status != 200 {
    return persisted
  }
  if native_field(
      native_field(native_result_json(persisted), "execution"),
      "revision_request",
    ) !=
    request {
    return native_json_result(409, {
      "error": "Another delivery revision won; refresh to inspect it",
    })
  }
  // Only an explicit founder request may unseal the session. Background reads
  // can reconcile the exact queued turn, but must never undo a later Stop.
  let control = native_load_control(moonclaw_uri)
  let resumed = native_request(
    control,
    @http.Post,
    "/v1/code/sessions/" +
    native_component(native_text(execution, "session_id")) +
    "/lifecycle",
    (
      { "action": "resume", "book_root": native_text(execution, "workspace") } :
      Json).stringify(),
  )
  if native_text(resumed, "session_id") != native_text(execution, "session_id") ||
    native_bool(resumed, "suspended") {
    raise GatewayError::Upstream(
      "Runtime did not confirm this delivery can continue; retry the saved request",
    )
  }
  native_refresh_task(bridge, moonclaw_uri, task_id)
}

///|
fn native_delivery_replacement_command(
  execution : Json,
  request : Json,
) -> Json {
  {
    "protocol": "mooncode.v1",
    "session_id": native_text(execution, "session_id"),
    "book_root": native_text(execution, "workspace"),
    "command": "cancel",
    "packet": {
      "command_id": native_text(native_field(request, "snapshot"), "command_id") +
      "-replace-paused",
    },
  }
}
