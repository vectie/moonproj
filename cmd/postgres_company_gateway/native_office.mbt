///|
fn native_office_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/office"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
// The office observes existing sessions. Never call delivery reconciliation,
// /turns, lifecycle controls, or forward personal memory from this read path.
async fn native_office_observation(
  task : Json,
  inspect : async (String, String) -> Json,
) -> Json noraise {
  let execution = native_field(task, "execution")
  let result : Json = {
    "schema": "moonproj.office-observation.v1",
    "task": task,
    "state": "recorded",
    "workers": native_field(execution, "workers"),
    "observed_at": Json::number(@env.now().to_double()),
    "error": "",
  }
  if native_text(execution, "session_id").is_empty() {
    return result
  }
  // The native task panel excludes suspended chats. Viewing a confirmed Stop
  // must not unseal its tree just to read status.
  if native_text(execution, "control_state") == "stopped" {
    return result
  }
  try {
    let panel = inspect(
      native_text(execution, "session_id"),
      native_text(execution, "workspace"),
    )
    if native_text(panel, "owner") != "moonclaw" ||
      native_text(panel, "session_id") != native_text(execution, "session_id") ||
      native_text(native_field(panel, "context"), "book_root") !=
      native_text(execution, "workspace") ||
      !(native_field(panel, "workers") is Array(_)) {
      raise fail("Office observation does not match this task's session")
    }
    let workers = native_array(panel, "workers").map(worker => {
      let fields : Map[String, Json] = Map([])
      for
        key in [
          "worker_id", "child_session_id", "child_command_id", "child_book_root",
          "status", "terminal", "successful", "terminal_evidence",
        ] {
        fields[key] = native_field(worker, key)
      }
      let output = native_field(worker, "result")
      fields["summary"] = native_field(output, "answer")
      fields["summary_truncated"] = native_field(output, "answer_truncated")
      fields["artifact_references"] = native_field(
        output, "artifact_references",
      )
      Json::object(fields)
    })
    if result is Object(fields) {
      fields["workers"] = workers.to_json()
      fields["state"] = Json::string("observed")
      fields["active_command_id"] = native_field(
        native_field(panel, "context"),
        "active_command_id",
      )
    }
  } catch {
    _ =>
      if result is Object(fields) {
        fields["state"] = Json::string("unavailable")
        fields["error"] = Json::string(
          "实时专员观察暂不可用，保留公司已记录的执行；未推断在线状态。",
        )
      }
  }
  result
}

///|
async fn native_read_office(
  bridge : NativeBridge,
  moonclaw_uri : String,
  task_id : String,
) -> ProxyResult raise GatewayError {
  let (detail, task) = native_continuation_detail(bridge, task_id)
  if detail.status != 200 {
    return detail
  }
  let observation = native_office_observation(task, (session, root) => {
    let control = native_load_control(moonclaw_uri)
    native_request(
      control,
      @http.Post,
      "/v1/code/sessions/" + native_component(session) + "/task-controls",
      ({ "action": "inspect", "book_root": root } : Json).stringify(),
    )
  })
  native_json_result(200, observation)
}
