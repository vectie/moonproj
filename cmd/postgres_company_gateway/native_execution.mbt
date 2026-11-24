///|
/// MoonProj's native bridge uses the same operator-owned control contract as Desk.
/// It only reads an existing control file; it never creates or changes credentials.
struct NativeControl {
  uri : String
  instance_id : String
  auth_token : String
}

///|
fn native_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn native_text(value : Json, key : String) -> String {
  json_text(value, key).unwrap_or("")
}

///|
fn native_array(value : Json, key : String) -> Array[Json] {
  match native_field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn native_bool(value : Json, key : String) -> Bool {
  native_field(value, key) == Json::boolean(true)
}

///|
fn native_hex(value : String, length : Int32) -> Bool {
  value.length() == length &&
  value.iter().all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f'))
}

///|
fn native_control_root(configured : String) -> String {
  // The explicit cross-app path belongs to Desk; this gateway's generic
  // LEPUSA_APP_DATA_DIR belongs to MoonProj and cannot identify Desk's root.
  match configured.rev_find("/") {
    Some(index) => configured[:index].to_owned()
    None => ""
  }
}

///|
fn native_loopback_port(uri : String) -> String? {
  let prefix = if uri.has_prefix("http://127.0.0.1:") {
    "http://127.0.0.1:"
  } else if uri.has_prefix("http://localhost:") {
    "http://localhost:"
  } else {
    return None
  }
  let port = uri[prefix.length():].to_owned()
  if port.is_empty() || !port.iter().all(c => c.is_ascii_digit()) {
    None
  } else {
    Some(port)
  }
}

///|
fn native_daemon_info_path(workspace : String) -> String {
  let parent = native_control_root(workspace)
  let root = if parent.has_suffix("/books") {
    native_control_root(parent)
  } else {
    workspace
  }
  root + "/.moonsuite/products/moonclaw/daemon.json"
}

///|
fn native_control_uri(
  override_uri : String,
  daemon_port : String,
) -> String raise GatewayError {
  let parsed = parse_uint(daemon_port)
  if parsed is None || parsed.unwrap() == 0UL || parsed.unwrap() > 65535UL {
    raise GatewayError::Upstream(
      "Existing MoonClaw daemon metadata has no valid loopback port",
    )
  }
  if override_uri.is_empty() {
    return "http://127.0.0.1:" + daemon_port
  }
  let port = match native_loopback_port(override_uri) {
    Some(value) => value
    None =>
      raise GatewayError::Upstream(
        "MoonClaw native control requires the existing loopback daemon URI",
      )
  }
  if port != daemon_port {
    raise GatewayError::Upstream(
      "Explicit MoonClaw URI does not match the existing configured daemon",
    )
  }
  override_uri
}

///|
async fn native_load_control(uri : String) -> NativeControl raise GatewayError {
  let configured = @env.get_env_var("MOONDESK_EXECUTION_SANDBOX_CONFIG").unwrap_or(
    "",
  )
  if configured.is_empty() {
    raise GatewayError::Upstream(
      "Existing MoonClaw control config is unavailable: MOONDESK_EXECUTION_SANDBOX_CONFIG is not set",
    )
  }
  let root = native_control_root(configured)
  let root_prefix = root + "/"
  if !root.has_suffix("/control/execution-sandbox") ||
    !configured.has_prefix(root_prefix) ||
    configured[root_prefix.length():].is_empty() {
    raise GatewayError::Upstream(
      "MoonClaw control config must name the existing private control directory",
    )
  }
  try {
    if @fs.realpath(root) != root ||
      @fs.realpath(configured) != configured ||
      !(@fs.kind(configured, follow_symlink=false) is Regular) {
      raise GatewayError::Upstream(
        "MoonClaw control config is not a canonical regular file",
      )
    }
    let file = @fs.open(configured, mode=ReadOnly)
    defer file.close()
    if file.size() > 65536L {
      raise GatewayError::Upstream("MoonClaw control config is invalid")
    }
    let config = @json.parse(@encoding/utf8.decode(file.read_all().binary()))
    if native_field(config, "protocol_version") != Json::number(1) ||
      !native_hex(native_text(config, "instance_id"), 32) ||
      !native_hex(native_text(config, "auth_token"), 64) {
      raise GatewayError::Upstream("MoonClaw control config is invalid")
    }
    let workspace = native_text(config, "workspace_root")
    if workspace.is_empty() ||
      @fs.realpath(workspace) != workspace ||
      !(@fs.kind(workspace, follow_symlink=false) is Directory) {
      raise GatewayError::Upstream(
        "MoonClaw control config has no valid workspace root",
      )
    }
    let daemon = @json.parse(
      @encoding/utf8.decode(
        @fs.read_file(native_daemon_info_path(workspace)).binary(),
      ),
    )
    let daemon_port = match native_field(daemon, "port") {
      Number(value, ..) => value.to_int().to_string()
      _ => ""
    }
    let selected_uri = native_control_uri(uri, daemon_port)
    {
      uri: selected_uri,
      instance_id: native_text(config, "instance_id"),
      auth_token: native_text(config, "auth_token"),
    }
  } catch {
    GatewayError::Upstream(message) => raise GatewayError::Upstream(message)
    _ =>
      raise GatewayError::Upstream(
        "Existing MoonClaw control config could not be read",
      )
  }
}

///|
fn native_response_status_allowed(
  status : Int32,
  method : @http.RequestMethod,
  path : String,
  body : String,
) -> Bool {
  (status >= 200 && status <= 299) ||
  (
    status == 503 &&
    method == @http.Get &&
    path == "/v1/moongate-route" &&
    body == ""
  )
}

///|
fn native_catalog_only_route_response(route : Json) -> Bool {
  route
  is {
    "contract": "moonclaw.moongate-route.v1",
    "ready": false,
    "default_ready": false,
    "catalog_ready": true,
    "default_model": "",
    "models": Array(models),
    ..
  } &&
  !models.is_empty() &&
  models.all(model => {
    model is { "name": String(name), .. } &&
    name.has_prefix("moongate/") &&
    name.length() > 9 &&
    name == name.trim().to_owned()
  })
}

///|
fn native_validate_response(
  control : NativeControl,
  method : @http.RequestMethod,
  path : String,
  body : String,
  status : Int32,
  instance : String,
  data : Bytes,
) -> Json raise {
  if instance != control.instance_id ||
    !native_response_status_allowed(status, method, path, body) {
    raise GatewayError::Upstream(
      "MoonClaw native control unavailable or rejected request (HTTP " +
      status.to_string() +
      ")",
    )
  }
  let text = @encoding/utf8.decode(data)
  if text.contains(control.auth_token) {
    raise GatewayError::Upstream(
      "MoonClaw returned an invalid control response",
    )
  }
  let response = @json.parse(text)
  if status == 503 && !native_catalog_only_route_response(response) {
    raise GatewayError::Upstream(
      "MoonClaw native control unavailable or rejected request (HTTP 503)",
    )
  }
  response
}

///|
async fn native_request(
  control : NativeControl,
  method : @http.RequestMethod,
  path : String,
  body : String,
) -> Json raise GatewayError {
  try {
    let client = @http.Client(control.uri)
    defer client.close()
    client.request(method, path, extra_headers={
      "Content-Type": "application/json",
      "X-MoonClaw-Execution-Token": control.auth_token,
      "X-MoonClaw-Instance-ID": control.instance_id,
    })
    if !body.is_empty() {
      client.write(@encoding/utf8.encode(body))
    }
    let response = client.end_request()
    let echoed = response.headers
      .get("x-moonclaw-instance-id")
      .unwrap_or(response.headers.get("X-MoonClaw-Instance-ID").unwrap_or(""))
    if echoed != control.instance_id ||
      !native_response_status_allowed(response.code, method, path, body) {
      raise GatewayError::Upstream(
        "MoonClaw native control unavailable or rejected request (HTTP " +
        response.code.to_string() +
        ")",
      )
    }
    native_validate_response(
      control,
      method,
      path,
      body,
      response.code,
      echoed,
      client.read_all().binary(),
    )
  } catch {
    GatewayError::Upstream(message) => raise GatewayError::Upstream(message)
    _ =>
      raise GatewayError::Upstream(
        "MoonClaw native runtime is unavailable; retry the same task after restoring it",
      )
  }
}

///|
fn native_component(value : String) -> String {
  let out = StringBuilder::new()
  let digits = "0123456789ABCDEF"
  for byte in @encoding/utf8.encode(value) {
    if (byte >= b'a' && byte <= b'z') ||
      (byte >= b'A' && byte <= b'Z') ||
      (byte >= b'0' && byte <= b'9') ||
      byte == b'-' ||
      byte == b'_' ||
      byte == b'.' ||
      byte == b'~' {
      out.write_char(byte.to_char())
    } else {
      out.write_char('%')
      out.write_char(digits.get_char(byte.to_int() / 16).unwrap())
      out.write_char(digits.get_char(byte.to_int() % 16).unwrap())
    }
  }
  out.to_string()
}

///|
fn native_model(route : Json, requested : String) -> String raise GatewayError {
  // Older route payloads expose only ready. An explicit catalog flag is
  // authoritative, including false, so stale entries cannot become a fallback.
  let catalog_ready = match route {
    Object(fields) =>
      match fields.get("catalog_ready") {
        None => native_bool(route, "ready")
        Some(value) => value == Json::boolean(true)
      }
    _ => false
  }
  if native_text(route, "contract") != "moonclaw.moongate-route.v1" ||
    !catalog_ready ||
    (requested.is_empty() && !native_bool(route, "ready")) {
    raise GatewayError::Upstream(
      "MoonClaw has no ready native MoonGate model route",
    )
  }
  let selected = if requested.is_empty() {
    native_text(route, "default_model")
  } else {
    requested
  }
  if !selected.has_prefix("moongate/") ||
    selected.length() <= "moongate/".length() ||
    !native_array(route, "models").any(model => {
      native_text(model, "name") == selected
    }) {
    raise GatewayError::Upstream(
      "Select an available moongate/ model from the existing MoonClaw runtime",
    )
  }
  selected
}

///|
fn native_execution_snapshot(
  task : Json,
  model : String,
  actor : String,
  product_context? : Json,
  book_guidance? : Json,
) -> Json {
  let task_id = native_text(task, "taskGuid")
  let run_id = "mp-" +
    hmac_hex(
      "moonproj-native-execution-v1",
      actor + ":" + native_text(task, "projGuid") + ":" + task_id,
    )
  let session_id = run_id
  let command_id = run_id + "-start"
  let workspace = native_delivery_workspace(task)
  let prompt = if product_context is Some(context) {
    native_context_prompt(task, context)
  } else {
    "MoonProj formal task " +
    task_id +
    " in project " +
    native_text(task, "projGuid") +
    ".\nTask: " +
    native_text(task, "taskName") +
    "\nRequirements and acceptance criteria:\n" +
    native_text(task, "remarks") +
    "\nExecute this task in the selected workspace. Return the concrete result, evidence and any remaining limits. Execution completion is separate from founder/customer acceptance."
  }
  let prompt = prompt +
    native_delivery_prompt(task) +
    native_delivery_progress_prompt(task, command_id) +
    native_objective_delivery_prompt(task) +
    @task_evidence.source_prompt(task) +
    @task_evidence.guidance_prompt(book_guidance.unwrap_or(Json::null()))
  let request : Json = {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "text": prompt,
    "model": model,
    "session_id": session_id,
    "book_root": workspace,
    "packet": { "command_id": command_id },
    "web_search": false,
  }
  let request = match request {
    Object(fields) => fields
    _ => Map::new()
  }
  if native_coordinated(task) {
    request["payload"] = {
      "planner_allowed_tools": native_delivery_tools().to_json(),
    }
  }
  match product_context {
    Some(context) =>
      request.set("context_path", native_field(context, "context_path"))
    None => ()
  }
  let snapshot : Json = {
    "run_id": run_id,
    "task_id": task_id,
    "session_id": session_id,
    "command_id": command_id,
    "workspace": workspace,
    "model": model,
    "state": "queued",
    "summary": "",
    "error": "",
    "evidence_ids": [],
    "output_urls": [],
    "artifact_refs": [],
    "receipt": null,
    // JSONB must preserve bytes in this string, not reorder the native object.
    "request_body": Json::object(request).stringify(),
  }
  if snapshot is Object(fields) && native_coordinated(task) {
    fields["delivery_mode"] = Json::string("coordinated")
  }
  if snapshot is Object(fields) && book_guidance is Some(selection) {
    fields.set("book_guidance", selection)
    fields.set(
      "book_guidance_sha256",
      Json::string(native_guidance_digest(selection)),
    )
  }
  match (snapshot, product_context) {
    (Object(fields), Some(context)) => {
      fields.set("product_context", context)
      fields.set(
        "product_context_artifact",
        native_context_availability("pending", ""),
      )
      Json::object(fields)
    }
    _ => snapshot
  }
}

///|
fn native_objective_delivery_prompt(task : Json) -> String {
  if native_text(task, "parentTaskGuid").is_empty() {
    return ""
  }
  "\nDelivery responsibility: this work contributes to objective " +
  native_text(task, "parentTaskGuid") +
  ". Own one integrated deliverable, not just a task list. Use available specialist capabilities when useful, and integrate their contributions. Do not invent specialist work or independent review that did not happen. Return the artifact, checks against acceptance criteria, unresolved gaps, and actual cost when available. Continue routine preparation, checks and recovery within the existing brief and permissions; surface material scope or budget changes and consequential decisions. The parent link is context, not an execution dependency or additional authority.\n"
}

///|
fn native_terminal(state : String) -> Bool {
  ["completed", "failed", "cancelled"].contains(state)
}

///|
fn native_observation(execution : Json, state : String, error : String) -> Json {
  {
    "run_id": native_text(execution, "run_id"),
    "task_id": native_text(execution, "task_id"),
    "session_id": native_text(execution, "session_id"),
    "command_id": native_text(execution, "command_id"),
    "state": state,
    "summary": native_text(execution, "summary"),
    "error": error,
    "evidence_ids": native_field(execution, "evidence_ids"),
    "output_urls": native_field(execution, "output_urls"),
  }
}

///|
fn native_receipt_answer(receipt : Json) -> String {
  let mut answer = ""
  for item in native_array(native_field(receipt, "execution"), "tool_results") {
    if native_text(item, "tool") != "finish" || !native_bool(item, "accepted") {
      continue
    }
    let nested = native_field(item, "result")
    let result = if nested is Object(fields) && fields.length() > 0 {
      nested
    } else {
      item
    }
    if native_bool(result, "is_error") {
      continue
    }
    let explicit_answer = native_text(
      native_field(result, "metadata"),
      "answer",
    )
    answer = if explicit_answer.is_empty() {
      native_text(result, "output")
    } else {
      explicit_answer
    }
  }
  answer
}

///|
fn native_output_paths(event : Json) -> Array[String] {
  let paths : Array[String] = []
  let tool = native_text(event, "tool")
  let kind = native_text(event, "event")
  let result = native_field(event, "tool_result")
  if (
      (kind == "tool_result" && ["write", "edit"].contains(tool)) ||
      (kind == "patch_applied" && tool == "apply_patch")
    ) &&
    native_bool(result, "ok") &&
    !native_bool(result, "is_error") {
    paths.push(native_text(event, "path"))
    for path in native_array(event, "changed_paths") {
      if path is String(value) {
        paths.push(value)
      }
    }
  }
  if ["package_built", "package_verified"].contains(kind) {
    let package_result = native_field(event, "package_result")
    paths.push(native_text(event, "path"))
    paths.push(native_text(package_result, "path"))
    let manifest = native_field(package_result, "package_manifest")
    paths.push(native_text(manifest, "manifest_path"))
    for path in native_array(manifest, "candidate_paths") {
      if path is String(value) {
        paths.push(value)
      }
    }
    for source in native_array(manifest, "source_inventory") {
      paths.push(native_text(source, "path"))
      paths.push(native_text(source, "promoted_path"))
    }
    paths.push(
      native_text(
        native_field(package_result, "package_index"),
        "manifest_path",
      ),
    )
  }
  let result : Array[String] = []
  for path in paths {
    if path.is_empty() ||
      path.has_prefix(".moonproj-progress-") ||
      path.has_prefix("/") ||
      path.split("/").any(piece => piece == "..") ||
      result.contains(path) {
      continue
    }
    result.push(path)
  }
  result
}

///|
fn native_execution_readback(
  execution : Json,
  claims : Json,
  events : Json,
  service : Json,
) -> Json raise GatewayError {
  let session_id = native_text(execution, "session_id")
  let command_id = native_text(execution, "command_id")
  let workspace = native_text(execution, "workspace")
  for payload in [claims, events, service] {
    if native_text(payload, "session_id") != session_id ||
      native_text(payload, "book_root") != workspace {
      raise GatewayError::Upstream(
        "MoonClaw returned another task session or workspace",
      )
    }
  }
  let mut selected = Json::null()
  let mut state = "unknown"
  for
    category in [
      "claimable_commands", "claimed_commands", "order_blocked_commands", "delivered_commands",
      "invalid_commands",
    ] {
    for item in native_array(claims, category) {
      if native_text(item, "command_id") == command_id {
        selected = item
        state = if category == "claimed_commands" {
          "running"
        } else if category == "invalid_commands" {
          "unknown"
        } else {
          "queued"
        }
      }
    }
  }
  let receipt = native_field(selected, "receipt")
  let receipt_status = native_text(receipt, "status")
  if !receipt_status.is_empty() &&
    (
      native_text(receipt, "command_id") != command_id ||
      native_text(receipt, "session_id") != session_id
    ) {
    raise GatewayError::Upstream(
      "MoonClaw receipt does not match the reserved task command",
    )
  }
  state = match receipt_status {
    "runtime-completed" => "completed"
    "runtime-failed" => "failed"
    "runtime-cancelled" => "cancelled"
    "runtime-claimed" => "running"
    _ => state
  }
  let evidence : Array[Json] = []
  let artifacts : Array[Json] = []
  let mut checkpoint_state = ""
  let mut checkpoint_approval_id = ""
  let explicit_receipt_id = native_text(receipt, "id")
  let sequence = native_text(receipt, "journal_sequence")
  let receipt_id = if !explicit_receipt_id.is_empty() {
    explicit_receipt_id
  } else if !sequence.is_empty() {
    "moonclaw:" + session_id + ":journal:" + sequence
  } else {
    native_text(receipt, "claim_id")
  }
  if !receipt_id.is_empty() {
    evidence.push(Json::string(receipt_id))
  }
  for event in native_array(events, "events") {
    if native_text(event, "command_id") != command_id ||
      native_text(event, "session_id") != session_id {
      continue
    }
    if native_text(event, "kind") == "runtime.turn_checkpointed" {
      checkpoint_state = native_text(event, "state")
      checkpoint_approval_id = native_text(event, "approval_id")
    } else if ["runtime.turn_started", "runtime.planner_started"].contains(
        native_text(event, "kind"),
      ) &&
      ["planner-quantum-paused", "planner-replan-paused"].contains(
        checkpoint_state,
      ) {
      checkpoint_state = "resumed"
    } else if ["tool.approval_approved", "tool.approval_rejected"].contains(
        native_text(event, "kind"),
      ) &&
      !checkpoint_approval_id.is_empty() &&
      native_text(event, "approval_id") == checkpoint_approval_id {
      checkpoint_state = "after-decision"
    }
    let event_id = native_text(event, "id")
    let output_paths = native_output_paths(event)
    if !event_id.is_empty() &&
      (
        !output_paths.is_empty() ||
        [
          "tool.approval_approved", "tool.approval_rejected", "runtime.turn_completed",
          "runtime.turn_failed",
        ].contains(native_text(event, "kind"))
      ) {
      evidence.push(Json::string(event_id))
    }
    for path in output_paths {
      artifacts.push(
        Json::object({
          "path": Json::string(path),
          "evidence_id": Json::string(event_id),
          "command_id": Json::string(command_id),
        }),
      )
    }
  }
  if !native_terminal(state) && checkpoint_state == "awaiting-approval" {
    state = "waiting_approval"
  }
  if !native_terminal(state) &&
    state != "waiting_approval" &&
    (
      checkpoint_state == "planner-quantum-paused" ||
      checkpoint_state == "planner-replan-paused" ||
      native_text(service, "status") == "waiting"
    ) {
    state = "interrupted"
  }
  if !native_terminal(state) &&
    state != "waiting_approval" &&
    ["failed", "cancelled", "stopped", "idle", "done"].contains(
      native_text(service, "status"),
    ) &&
    receipt_status == "runtime-claimed" {
    state = "interrupted"
  }
  let fields = match native_observation(execution, state, "") {
    Object(values) => values
    _ => Map::new()
  }
  fields.set(
    "summary",
    Json::string(
      if state == "completed" {
        native_receipt_answer(receipt)
      } else {
        ""
      },
    ),
  )
  fields.set(
    "error",
    Json::string(
      if state == "failed" {
        "Native command failed; inspect the linked receipt"
      } else {
        ""
      },
    ),
  )
  fields.set("evidence_ids", Json::array(evidence))
  fields.set("artifact_refs", Json::array(artifacts))
  fields.set(
    "receipt",
    if receipt_status.is_empty() {
      Json::null()
    } else {
      Json::object({
        "id": Json::string(receipt_id),
        "session_id": Json::string(session_id),
        "command_id": Json::string(command_id),
        "status": Json::string(receipt_status),
        "claim_id": native_field(receipt, "claim_id"),
        "journal_sequence": native_field(receipt, "journal_sequence"),
      })
    },
  )
  Json::object(fields)
}

///|
struct NativeBridge {
  service_uri : String
  service_token : String
  actor_signing_secret : String
  actor : String
}

///|
fn native_json_result(status : Int32, value : Json) -> ProxyResult {
  {
    status,
    content_type: "application/json; charset=utf-8",
    body: @encoding/utf8.encode(value.stringify()),
    www_authenticate: None,
  }
}

///|
fn native_result_json(result : ProxyResult) -> Json raise GatewayError {
  @json.parse(@encoding/utf8.decode(result.body)) catch {
    _ =>
      raise GatewayError::Upstream("Company service returned invalid task JSON")
  }
}

///|
async fn native_company_request(
  bridge : NativeBridge,
  method : @http.RequestMethod,
  path : String,
  body : Json,
) -> ProxyResult raise GatewayError {
  let request : @http.Request = {
    meth: method,
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
    method,
    path,
    request,
    if method is @http.Get {
      b""
    } else {
      @encoding/utf8.encode(body.stringify())
    },
    None,
  )
}

///|
async fn native_company_observe(
  bridge : NativeBridge,
  task_id : String,
  observation : Json,
) -> Unit raise GatewayError {
  let result = native_company_request(
    bridge,
    @http.Post,
    "/api/company/internal/plan/tasks/" + task_id + "/execution/observe",
    { "execution": observation },
  )
  if result.status != 200 {
    raise GatewayError::Upstream(
      "Native task result could not be persisted; refresh this task to reconcile it",
    )
  }
}

///|
async fn native_poll_task(
  bridge : NativeBridge,
  control : NativeControl,
  task_id : String,
  execution : Json,
  coordinated~ : Bool = false,
) -> Unit raise GatewayError {
  let base = "/v1/code/sessions/" +
    native_component(native_text(execution, "session_id"))
  let query = "?book_root=" +
    native_component(native_text(execution, "workspace"))
  let claims = native_request(
    control,
    @http.Get,
    base + "/runtime-claim" + query,
    "",
  )
  let events = native_request(
    control,
    @http.Get,
    base + "/runtime-events" + query,
    "",
  )
  let service = native_request(
    control,
    @http.Get,
    base + "/runtime-service" + query,
    "",
  )
  let observation = native_execution_readback(
    execution, claims, events, service,
  )
  if coordinated {
    try {
      let panel = native_request(
        control,
        @http.Post,
        base + "/task-controls",
        (
          {
            "action": "inspect",
            "book_root": native_text(execution, "workspace"),
          } : Json).stringify(),
      )
      if native_text(panel, "session_id") !=
        native_text(execution, "session_id") {
        raise GatewayError::Upstream(
          "Worker observation returned a different delivery",
        )
      }
      let workers = native_array(panel, "workers").map(
        native_delivery_worker_projection,
      )
      if observation is Object(fields) {
        fields["workers"] = workers.to_json()
        fields["worker_error"] = Json::string("")
      }
    } catch {
      error =>
        if observation is Object(fields) {
          fields["worker_error"] = Json::string(gateway_error_text(error))
        }
    }
  }
  native_company_observe(bridge, task_id, observation)
}

///|
async fn native_refresh_task(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
) -> ProxyResult raise GatewayError {
  let path = "/api/company/tasks/" + task_id
  let detail = native_company_request(bridge, @http.Get, path, Json::null())
  if detail.status != 200 {
    return detail
  }
  let task = native_field(
    native_field(native_result_json(detail), "data"),
    "task",
  )
  let execution = native_field(task, "execution")
  if !(execution is Object(_)) {
    return detail
  }
  let availability = native_inspect_context_artifact(execution) catch {
    _ =>
      native_context_availability(
        "unavailable", "Captured context artifact could not be inspected",
      )
  }
  if availability is Object(_) {
    let observation = native_observation(
      execution,
      native_text(execution, "state"),
      native_text(execution, "error"),
    )
    if observation is Object(fields) {
      fields.set("product_context_artifact", availability)
      native_company_observe(bridge, task_id, Json::object(fields))
    }
  }
  try {
    let control = native_load_control(moonclaw_uri)
    if native_text(execution, "control_state") == "stopping" {
      native_delivery_settle_stop(bridge, control, task)
    }
    if native_text(execution, "control_state") == "revising" {
      native_delivery_progress_revision(bridge, control, task)
    }
    if !["stopping", "stopped", "revising"].contains(
        native_text(execution, "control_state"),
      ) {
      native_poll_task(
        bridge,
        control,
        task_id,
        execution,
        coordinated=native_coordinated(task),
      )
    }
  } catch {
    error =>
      native_company_observe(
        bridge,
        task_id,
        if ["stopping", "revising"].contains(
            native_text(execution, "control_state"),
          ) {
          native_delivery_control_observation(
            execution,
            native_text(execution, "control_state"),
            gateway_error_text(error),
            Json::null(),
          )
        } else {
          native_observation(
            execution,
            "runtime_unavailable",
            gateway_error_text(error),
          )
        },
      )
  }
  native_delivery_finish_detail(
    bridge,
    native_company_request(bridge, @http.Get, path, Json::null()),
  )
}

///|
async fn native_dispatch_task(
  bridge : NativeBridge,
  resources : ProductResources,
  moonclaw_uri : String,
  task_id : String,
  body : Json,
) -> ProxyResult raise GatewayError {
  let detail_path = "/api/company/tasks/" + task_id
  let detail = native_company_request(
    bridge,
    @http.Get,
    detail_path,
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
    raise GatewayError::Upstream(
      "Company service returned another task identity",
    )
  }
  let existing = native_field(task, "execution")
  if ["stopping", "stopped", "resuming", "revising"].contains(
      native_text(existing, "control_state"),
    ) {
    return native_json_result(409, {
      "error": "This delivery is stopped or its control outcome is unknown; explicitly continue the existing delivery",
    })
  }
  let book_guidance = native_book_guidance(task, body)
  let snapshot = if existing is Object(_) {
    existing
  } else {
    let workspace = native_text(task, "execution_workspace")
    if workspace.is_empty() {
      return native_json_result(422, {
        "error": "Set this task's execution_workspace to its MoonBook/workspace path before Start",
        "missing_field": "execution_workspace",
        "task_id": task_id,
      })
    }
    if !workspace.has_prefix("/") ||
      !((@fs.kind(workspace) catch { _ => @fs.FileKind::Regular }) is Directory) {
      return native_json_result(422, {
        "error": "execution_workspace must name an existing absolute MoonBook/workspace directory",
        "missing_field": "execution_workspace",
        "task_id": task_id,
      })
    }
    let control = native_load_control(moonclaw_uri)
    native_prepare_delivery_workspace(task)
    let route = native_request(control, @http.Get, "/v1/moongate-route", "")
    native_propose_execution(
      task,
      resources,
      native_model(route, native_text(task, "execution_model")),
      bridge.actor,
      book_guidance?,
    )
  }
  let reservation_body = native_reservation_body(task, body, snapshot)
  if !native_reservation_fits(reservation_body) {
    return native_json_result(413, {
      "error": "Complete execution context exceeds the existing 128 KiB reservation limit; no requirements were truncated",
      "task_id": task_id,
    })
  }
  let reservation = native_company_request(
    bridge,
    @http.Post,
    "/api/company/internal/plan/tasks/" + task_id + "/execution/reserve",
    reservation_body,
  )
  if reservation.status != 200 {
    return reservation
  }
  // Always send the snapshot returned by the durable reservation, even first time.
  let execution = native_field(native_result_json(reservation), "execution")
  if native_text(execution, "task_id") != task_id {
    raise GatewayError::Upstream(
      "Company service did not reserve this exact task",
    )
  }
  // A concurrent first Start may have won after our initial task read. Do not
  // dispatch a winner with different optional guidance on the losing caller's
  // behalf. The next explicit resume can inspect/use that captured input.
  if !(existing is Object(_)) &&
    native_text(execution, "book_guidance_sha256") !=
    native_text(snapshot, "book_guidance_sha256") {
    raise GatewayError::InvalidInput(
      "Another Start reserved different optional guidance; refresh to inspect the captured input, remove the new selection and explicitly resume the original execution",
    )
  }
  let availability = native_materialize_context(execution) catch {
    _ =>
      native_context_availability(
        "unavailable", "Captured context input could not be materialized",
      )
  }
  if availability is Object(_) {
    let observation = native_observation(
      execution,
      native_text(execution, "state"),
      native_text(execution, "error"),
    )
    if observation is Object(fields) {
      fields.set("product_context_artifact", availability)
      if native_text(availability, "state") != "available" &&
        !native_terminal(native_text(execution, "state")) {
        fields.set("state", Json::string("runtime_unavailable"))
        fields.set("error", Json::string(native_text(availability, "error")))
      }
      native_company_observe(bridge, task_id, Json::object(fields))
    }
    // A real input-file conflict must never expose the wrong bytes as context.
    // Missing catalog/PRD does not reach this branch: its partial task context is staged.
    if native_text(availability, "state") != "available" {
      return native_company_request(
        bridge,
        @http.Get,
        detail_path,
        Json::null(),
      )
    }
  }
  try {
    let control = native_load_control(moonclaw_uri)
    if !native_terminal(native_text(execution, "state")) {
      let accepted = native_request(
        control,
        @http.Post,
        "/v1/code/sessions/" +
        native_component(native_text(execution, "session_id")) +
        "/turns",
        native_text(execution, "request_body"),
      )
      if !native_bool(accepted, "accepted") ||
        native_text(accepted, "session_id") !=
        native_text(execution, "session_id") ||
        native_text(accepted, "command_id") !=
        native_text(execution, "command_id") ||
        native_text(accepted, "book_root") !=
        native_text(execution, "workspace") {
        raise GatewayError::Upstream(
          "MoonClaw did not acknowledge the reserved task command",
        )
      }
      let observation = native_observation(execution, "queued", "")
      let fields = match observation {
        Object(fields) => fields
        _ => Map::new()
      }
      fields.set("dispatched", Json::boolean(true))
      native_company_observe(bridge, task_id, Json::object(fields))
    }
    native_poll_task(
      bridge,
      control,
      task_id,
      execution,
      coordinated=native_coordinated(task),
    )
  } catch {
    error =>
      native_company_observe(
        bridge,
        task_id,
        native_observation(
          execution,
          "runtime_unavailable",
          gateway_error_text(error),
        ),
      )
  }
  native_delivery_finish_detail(
    bridge,
    native_company_request(bridge, @http.Get, detail_path, Json::null()),
  )
}

///|
fn native_dispatch_id(path : String) -> String? {
  let prefix = "/api/company/plan/tasks/"
  let suffix = "/dispatch"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
fn native_detail_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  if path.has_prefix(prefix) {
    let id = path[prefix.length():].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}
