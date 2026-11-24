///|
fn native_coordinated(task : Json) -> Bool {
  native_text(task, "delivery_mode") == "coordinated"
}

///|
fn native_delivery_base(task : Json) -> String {
  native_text(task, "execution_workspace") +
  "/.moonproj-deliveries/" +
  native_text(task, "taskGuid")
}

///|
fn native_delivery_workspace(task : Json) -> String {
  // Keep the captured root discoverable by MoonDesk. Output and worker folders
  // remain isolated below this registered MoonBook.
  native_text(task, "execution_workspace")
}

///|
fn native_delivery_tools() -> Array[String] {
  [
    "read", "read_skill", "view_image", "write", "edit", "apply_patch", "revert_patch",
    "shell", "moon_ide", "moon_cmd", "ask_user", "finish", "mcp_list_tools", "mcp_call_tool",
    "spawn_workers", "wait_workers",
  ]
}

///|
async fn native_prepare_delivery_workspace(
  task : Json,
) -> Unit raise GatewayError {
  if !native_coordinated(task) {
    return
  }
  try {
    let root = @fs.realpath(native_text(task, "execution_workspace"))
    for name in ["coordinator", "specialist-1", "specialist-2", "reviewer"] {
      let path = root +
        "/.moonproj-deliveries/" +
        native_text(task, "taskGuid") +
        "/" +
        name
      native_delivery_directory(path)
      if !@fs.realpath(path).has_prefix(root + "/") {
        raise GatewayError::InvalidInput(
          "Delivery workspaces must remain inside the selected workspace",
        )
      }
    }
  } catch {
    GatewayError::InvalidInput(message) =>
      raise GatewayError::InvalidInput(message)
    _ =>
      raise GatewayError::Upstream("Unable to prepare the delivery workspace")
  }
}

///|
fn native_delivery_prompt(task : Json) -> String {
  if !native_coordinated(task) {
    return ""
  }
  "\nYou are explicitly authorized to coordinate this delivery with the native spawn_workers and wait_workers tools. Omit each worker's optional model field to inherit this session's actual selected model; do not send a placeholder such as 'default'. Use fresh worker IDs when retrying failed spawns. For plain-text deliverables use native read/write/edit tools; shell availability is not required. Own the complete result and perform routine preparation, handoffs, checks and recovery without asking the founder to dispatch or submit each task. Specialist MoonBooks already exist: " +
  native_delivery_base(task) +
  "/specialist-1, " +
  native_delivery_base(task) +
  "/specialist-2; independent reviewer MoonBook: " +
  native_delivery_base(task) +
  "/reviewer. Use these isolated books, not the coordinator book, for workers. Worker results are returned by wait_workers; ask workers to include their substantive contribution and limitations in their final answer. Preserve successful contributions on recovery; do not re-execute them merely to rebuild status. Have an independent reviewer examine the actual proposed artifact/criteria before final integration. Supply its exact content in the reviewer prompt when files cannot be read across books. Do not claim a review or a worker succeeded without its terminal evidence. Finish by writing the buyer-usable artifact(s) in this coordinator book and reporting acceptance checks, unresolved gaps and observed usage/cost (unknown when unavailable). A summary alone is not the requested artifact. Company signing, payments, posting, trades and external publishing remain outside this delivery permission.\nScope and limits supplied by the founder: " +
  Json::string(native_text(task, "delivery_limits")).stringify() +
  "\nThe selected parent MoonBook is the coordinator's workspace. Preserve its existing sources and working documents. Put final integrated artifacts under .moonproj-deliveries/" +
  native_text(task, "taskGuid") +
  "/coordinator/ relative to that root, not at the root or over existing material.\n"
}

///|
fn native_delivery_authority(bridge : NativeBridge, task : Json) -> Json {
  {
    "active": true,
    "principal_id": "principal-opc-dispatch",
    "actor_id": bridge.actor,
    "capability": "project:task:update",
    "scope": "project:" + native_text(task, "projGuid"),
  }
}

///|
fn native_delivery_report_body(
  task : Json,
  execution : Json,
  source : Json,
  date : String,
) -> Json {
  let command = native_text(execution, "command_id")
  {
    "idempotency_key": "delivery-report-" + command,
    "report_id": "DELIVERY-" + command,
    "task_id": native_text(task, "taskGuid"),
    "project_id": native_text(task, "projGuid"),
    "progress_pct": 100,
    "report_date": date,
    "summary": native_text(execution, "summary"),
    "evidence_ids": native_field(execution, "evidence_ids"),
    "delivery_source": source,
  }
}

///|
async fn native_delivery_report(
  bridge : NativeBridge,
  task : Json,
  reports : Array[Json],
) -> Unit raise GatewayError {
  if !native_coordinated(task) ||
    native_text(task, "status") == "done" ||
    native_text(task, "created_by") != bridge.actor {
    return
  }
  let original = native_field(task, "execution")
  let selected = native_field(task, "selected_delivery_source")
  let execution = if native_text(selected, "type") == "continuation" {
    native_array(task, "continuations")
    .filter(c => {
      native_text(c, "command_id") == native_text(selected, "command_id")
    })
    .get(0)
    .unwrap_or(Json::null())
  } else if selected is Null || native_text(selected, "type") == "original" {
    original
  } else {
    return
  }
  if native_text(execution, "state") != "completed" ||
    native_text(execution, "summary").trim().is_empty() ||
    native_array(execution, "evidence_ids").is_empty() {
    return
  }
  if reports.any(r => {
      native_text(r, "reportGuid") ==
      "DELIVERY-" + native_text(execution, "command_id")
    }) {
    return
  }
  let source = if selected is Object(_) {
    selected
  } else {
    {
      "type": "original",
      "original_run_id": native_text(original, "run_id"),
      "command_id": native_text(original, "command_id"),
    }
  }
  // One stable report per exact command. Reads/restarts reconcile reporting,
  // never rerun a provider or turn a technical result into owner acceptance.
  let date = @time.unix((@env.now() / 1000UL).to_int64())
    .to_plain_date()
    .to_string() catch {
      _ => native_text(task, "planEndDate")
    }
  let body = native_delivery_report_body(task, execution, source, date)
  let result = native_company_request(
    bridge,
    @http.Post,
    "/api/company/plan/tasks/" + native_text(task, "taskGuid") + "/report",
    body,
  )
  if result.status != 200 && result.status != 201 {
    raise GatewayError::Upstream(
      "Delivery output is preserved; its report has not yet been confirmed",
    )
  }
}

///|
async fn native_delivery_finish_detail(
  bridge : NativeBridge,
  detail : ProxyResult,
) -> ProxyResult raise GatewayError {
  if detail.status != 200 {
    return detail
  }
  let payload = native_result_json(detail)
  let data = native_field(payload, "data")
  let task = native_field(data, "task")
  if !native_coordinated(task) {
    return detail
  }
  native_delivery_report(bridge, task, native_array(data, "reports")) catch {
    error => {
      if task is Object(fields) {
        fields["delivery_report_error"] = Json::string(
          gateway_error_text(error),
        )
        fields["delivery_progress"] = native_delivery_progress(task)
      }
      return native_json_result(200, payload)
    }
  }
  let refreshed = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + native_text(task, "taskGuid"),
    Json::null(),
  )
  if refreshed.status != 200 {
    return refreshed
  }
  let payload = native_result_json(refreshed)
  let task = native_field(native_field(payload, "data"), "task")
  if task is Object(fields) {
    fields["delivery_progress"] = native_delivery_progress(task)
  }
  native_json_result(200, payload)
}

///|
fn native_delivery_route(path : String) -> (String, String)? {
  match path.split("/").map(p => p.to_owned()).collect() {
    ["", "api", "company", "plan", "tasks", task, action] if valid_identifier(
        task,
      ) &&
      ["stop", "revise-delivery", "resume-delivery"].contains(action) =>
      Some((task, action))
    _ => None
  }
}

///|
fn native_delivery_control_observation(
  execution : Json,
  state : String,
  error : String,
  receipt : Json,
) -> Json {
  let value = native_observation(execution, native_text(execution, "state"), "")
  if value is Object(fields) {
    fields["control_state"] = Json::string(state)
    fields["control_error"] = Json::string(error)
    fields["control_receipt"] = receipt
    if native_field(execution, "revision_request") is Object(_) {
      fields["revision_request"] = native_field(execution, "revision_request")
    }
  }
  value
}

///|
fn native_delivery_suspension_matches(execution : Json, result : Json) -> Bool {
  native_text(result, "owner") == "moonclaw" &&
  native_text(result, "action") == "suspend" &&
  native_text(result, "session_id") == native_text(execution, "session_id") &&
  native_bool(result, "suspended") &&
  native_array(result, "sessions").any(s => {
    native_text(s, "session_id") == native_text(execution, "session_id") &&
    native_text(s, "book_root") == native_text(execution, "workspace") &&
    native_text(s, "state") == "suspended"
  }) &&
  native_array(result, "sessions").all(s => {
    // A planned child whose spawn never created a session has nothing to stop.
    ["suspended", "archived", "deleted", "missing"].contains(
      native_text(s, "state"),
    )
  })
}

///|
async fn native_delivery_settle_stop(
  bridge : NativeBridge,
  control : NativeControl,
  task : Json,
) -> Unit raise GatewayError {
  let execution = native_field(task, "execution")
  let result = native_request(
    control,
    @http.Post,
    "/v1/code/sessions/" +
    native_component(native_text(execution, "session_id")) +
    "/lifecycle",
    (
      { "action": "suspend", "book_root": native_text(execution, "workspace") } :
      Json).stringify(),
  )
  if !native_delivery_suspension_matches(execution, result) {
    raise GatewayError::Upstream(
      "Runtime has not confirmed suspension of this delivery and its worker tree",
    )
  }
  native_company_observe(
    bridge,
    native_text(task, "taskGuid"),
    native_delivery_control_observation(execution, "stopped", "", result),
  )
}

///|
async fn native_stop_delivery(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
  body : Json,
) -> ProxyResult raise GatewayError {
  let (detail, task) = native_continuation_detail(bridge, task_id)
  if detail.status != 200 {
    return detail
  }
  let execution = native_field(task, "execution")
  if !(execution is Object(_)) {
    return native_json_result(409, {
      "error": "This task has no execution to stop",
    })
  }
  let intent = native_delivery_control_observation(
    execution,
    "stopping",
    "",
    Json::null(),
  )
  let reserved = native_company_request(
    bridge,
    @http.Post,
    "/api/company/internal/plan/tasks/" + task_id + "/execution/control",
    { "execution": intent, "authority": native_field(body, "authority") },
  )
  if reserved.status != 200 {
    return reserved
  }
  if native_text(
      native_field(native_result_json(reserved), "execution"),
      "control_state",
    ) !=
    "stopping" {
    return native_json_result(409, {
      "error": "Delivery changed before stop was recorded; refresh and retry",
    })
  }
  native_delivery_settle_stop(bridge, native_load_control(moonclaw_uri), task) catch {
    error =>
      native_company_observe(
        bridge,
        task_id,
        native_delivery_control_observation(
          execution,
          "stopping",
          gateway_error_text(error),
          Json::null(),
        ),
      )
  }
  native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
}
