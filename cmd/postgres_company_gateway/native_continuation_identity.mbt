///|
/// Candidate hints are never task authority or result evidence.
#derive(Debug)
priv suberror NativeContinuationError {
  Rejected(Int32, String)
}

///|
fn native_continuation_root(root : String) -> String {
  if !root.has_prefix("/") {
    return root
  }
  let parts : Array[String] = []
  for part in root.split("/") {
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      ignore(parts.pop())
    } else {
      parts.push(part.to_owned())
    }
  }
  "/" + parts.join("/")
}

///|
fn native_continuation_key(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(c => {
    c.is_ascii_digit() ||
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    c == '_' ||
    c == '-'
  })
}

///|
fn native_continuation_directory(key : String) -> String {
  ".moonsuite/products/moonproj/human-continuations/" + key
}

///|
fn native_continuation_task_id(path : String, mutation : Bool) -> String? {
  let prefix = if mutation {
    "/api/company/plan/tasks/"
  } else {
    "/api/company/tasks/"
  }
  let suffix = "/continuations"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
fn native_continuation_original(
  task : Json,
  task_id : String,
) -> Json raise NativeContinuationError {
  let original = native_field(task, "execution")
  if native_text(task, "taskGuid") != task_id ||
    native_text(original, "task_id") != task_id ||
    !valid_identifier(native_text(original, "run_id")) ||
    !valid_identifier(native_text(original, "session_id")) ||
    !valid_identifier(native_text(original, "command_id")) ||
    !native_text(original, "workspace").has_prefix("/") {
    raise NativeContinuationError::Rejected(
      409, "This exact task has no complete captured native execution",
    )
  }
  original
}

///|
fn native_continuation_claim(
  original : Json,
  claims : Json,
  command_id : String,
) -> Json raise NativeContinuationError {
  let session = native_text(original, "session_id")
  let root = native_continuation_root(native_text(original, "workspace"))
  if native_text(claims, "kind") != "mooncode-runtime-claim-state" ||
    native_text(claims, "protocol") != "mooncode.v1" ||
    native_text(claims, "session_id") != session ||
    native_continuation_root(native_text(claims, "book_root")) != root {
    raise NativeContinuationError::Rejected(
      409, "Native claims do not belong to the captured session and workspace",
    )
  }
  let found : Array[(Json, String)] = []
  for
    (category, status) in [
      ("claimable_commands", "claimable"),
      ("claimed_commands", "claimed"),
      ("order_blocked_commands", "order-blocked"),
      ("delivered_commands", "delivered"),
      ("invalid_commands", "invalid"),
    ] {
    guard native_field(claims, category) is Array(items) else {
      raise NativeContinuationError::Rejected(
        503, "Native command listing is incomplete",
      )
    }
    for item in items {
      if native_text(item, "command_id") == command_id {
        found.push((item, status))
      }
    }
  }
  if found.is_empty() {
    raise NativeContinuationError::Rejected(
      404, "The exact continuation command is not in the native journal",
    )
  }
  if found.length() != 1 {
    raise NativeContinuationError::Rejected(
      409, "Native journal has ambiguous command identity",
    )
  }
  let (item, status) = found[0]
  let command = native_field(item, "command")
  if native_text(item, "session_id") != session ||
    native_text(item, "claim_status") != status ||
    status == "invalid" ||
    native_text(item, "action") != "prompt" ||
    native_text(command, "command") != "prompt" ||
    native_text(command, "protocol") != "mooncode.v1" ||
    native_text(command, "session_id") != session ||
    native_text(native_field(command, "packet"), "command_id") != command_id ||
    native_continuation_root(native_text(command, "book_root")) != root {
    raise NativeContinuationError::Rejected(
      409, "Native result is not this exact prompt command",
    )
  }
  let receipt = native_field(item, "receipt")
  if !native_text(receipt, "status").is_empty() &&
    (
      native_text(receipt, "session_id") != session ||
      native_text(receipt, "command_id") != command_id
    ) {
    raise NativeContinuationError::Rejected(
      409, "Native receipt belongs to another command",
    )
  }
  item
}

///|
fn native_continuation_lineage(
  original : Json,
  command : Json,
) -> Json raise NativeContinuationError {
  let lineage = native_field(
    native_field(command, "payload"),
    "moonproj_continuation",
  )
  let key = native_text(lineage, "continuation_id")
  let command_id = native_text(native_field(command, "packet"), "command_id")
  let prior = native_text(lineage, "prior_result_command_id")
  let input = native_field(lineage, "input")
  if native_text(lineage, "schema") != "moonproj.work-continuation.v1" ||
    !native_continuation_key(key) ||
    native_text(lineage, "task_id") != native_text(original, "task_id") ||
    native_text(lineage, "run_id") != native_text(original, "run_id") ||
    native_text(lineage, "original_command_id") !=
    native_text(original, "command_id") ||
    command_id == native_text(original, "command_id") ||
    !valid_identifier(command_id) ||
    !valid_identifier(prior) ||
    prior == command_id ||
    native_text(input, "path") !=
    native_continuation_directory(key) + "/input.md" ||
    !native_hex(native_text(input, "sha256"), 64) ||
    native_text(command, "context_path") != native_text(input, "path") ||
    native_text(command, "model") != native_text(original, "model") {
    raise NativeContinuationError::Rejected(
      409, "Continuation lineage does not match this task's original execution",
    )
  }
  let client_turn = native_text(
    native_field(command, "packet"),
    "client_turn_id",
  )
  if !valid_identifier(client_turn) {
    raise NativeContinuationError::Rejected(
      409, "Continuation has no stable client-turn identity",
    )
  }
  // A fresh human prompt cannot carry old executable progress. Empty typed
  // adapter tool-call arrays are harmless; nonempty plans are never accepted.
  for
    container in [
      command,
      native_field(command, "payload"),
      native_field(command, "packet"),
    ] {
    for
      key in [
        "horizon_id", "horizon_checkpoint", "horizon_evidence", "task_contract",
        "task_intent", "execution_plan", "tool_plan", "plan", "approval_state", "next_action",
        "planner_continuation",
      ] {
      if native_field(container, key) != Json::null() {
        raise NativeContinuationError::Rejected(
          409, "Continuation contains inherited executable state",
        )
      }
    }
    for key in ["approval_id", "target_command_id", "tool_call_id"] {
      if !native_text(container, key).is_empty() {
        raise NativeContinuationError::Rejected(
          409, "Continuation targets prior executable control state",
        )
      }
    }
    for key in ["runtime_tool_calls", "tool_calls"] {
      let value = native_field(container, key)
      if value != Json::null() && value != Json::array([]) {
        raise NativeContinuationError::Rejected(
          409, "Continuation contains prebuilt tool execution",
        )
      }
    }
  }
  lineage
}

///|
fn native_continuation_validate_prior(
  original : Json,
  claims : Json,
  lineage : Json,
) -> Unit raise NativeContinuationError {
  let prior = native_text(lineage, "prior_result_command_id")
  let item = native_continuation_claim(original, claims, prior)
  if prior != native_text(original, "command_id") {
    ignore(native_continuation_lineage(original, native_field(item, "command")))
  }
}
