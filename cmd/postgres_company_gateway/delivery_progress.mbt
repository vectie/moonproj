///|
// A disposable, agent-authored explanation, not a scheduler or completion fact.
fn native_delivery_progress_command(task : Json) -> String {
  let execution = native_field(task, "execution")
  let revision = native_field(
    native_field(execution, "revision_request"),
    "snapshot",
  )
  if !native_text(revision, "command_id").is_empty() {
    native_text(revision, "command_id")
  } else {
    native_text(execution, "command_id")
  }
}

///|
fn native_delivery_progress_projection(
  task : Json,
  command : String,
  note : Json,
) -> Json {
  if native_text(note, "schema") != "moonproj.delivery-progress.v1" ||
    native_text(note, "task_id") != native_text(task, "taskGuid") ||
    command.is_empty() ||
    native_text(note, "command_id") != command {
    return Json::null()
  }
  let fields : Map[String, Json] = Map([])
  for
    key in [
      "schema", "task_id", "command_id", "deliverable", "now", "next", "needs_user",
      "output_path",
    ] {
    fields[key] = Json::string(native_text(note, key))
  }
  fields["contributions"] = Json::array(
    native_array(note, "contributions").map(item => {
      let contribution : Map[String, Json] = Map([])
      for key in ["worker_id", "responsibility", "contributes_to"] {
        contribution[key] = Json::string(native_text(item, key))
      }
      Json::object(contribution)
    }),
  )
  Json::object(fields)
}

///|
async fn native_delivery_progress(task : Json) -> Json noraise {
  let command = native_delivery_progress_command(task)
  if !native_coordinated(task) || !valid_identifier(command) {
    return Json::null()
  }
  try {
    let bytes = native_continuation_read_file(
      native_text(native_field(task, "execution"), "workspace"),
      ".moonproj-progress-" + command + ".json",
      65536,
    )
    native_delivery_progress_projection(
      task,
      command,
      @json.parse(@encoding/utf8.decode(bytes)),
    )
  } catch {
    _ => Json::null()
  }
}

///|
fn native_delivery_progress_prompt(task : Json, command : String) -> String {
  if !native_coordinated(task) {
    return ""
  }
  let example : Json = {
    "schema": "moonproj.delivery-progress.v1",
    "task_id": native_text(task, "taskGuid"),
    "command_id": command,
    "deliverable": "Describe the concrete final deliverable, not agent activity",
    "now": "What is actually happening, or what is blocked",
    "next": "The next step toward the integrated deliverable",
    "needs_user": "Only a specific decision or input required from the owner; otherwise empty",
    "output_path": "Relative path of the integrated deliverable once written; otherwise empty",
    "contributions": [
      {
        "worker_id": "Exact ID passed to spawn_workers",
        "responsibility": "Plain-language assignment",
        "contributes_to": "Which part of the final deliverable this improves and why",
      },
    ],
  }
  "\nKeep the owner informed without technical jargon. Before delegating, write " +
  ".moonproj-progress-" +
  command +
  ".json in this coordinator book using this JSON shape: " +
  example.stringify() +
  ". Replace example text with this task's real plan, use the owner's language, and update after delegation, worker results, integration, review, or a blocker. Only list real worker IDs you assign; preserve useful prior contributions. This note explains intent and progress, never certifies completion or acceptance. After all workers are terminal, stop waiting and integrate their substantive results; report a concrete blocker if integration cannot proceed. This note is not the deliverable and must not be listed as a final artifact.\n"
}

///|
fn native_delivery_worker_projection(worker : Json) -> Json {
  let fields : Map[String, Json] = Map([])
  for
    key in [
      "worker_id", "child_session_id", "child_command_id", "child_book_root", "status",
      "terminal", "successful", "terminal_evidence",
    ] {
    fields[key] = native_field(worker, key)
  }
  let output = native_field(worker, "result")
  fields["summary"] = native_field(output, "answer")
  fields["summary_truncated"] = native_field(output, "answer_truncated")
  fields["artifact_references"] = native_field(output, "artifact_references")
  Json::object(fields)
}
