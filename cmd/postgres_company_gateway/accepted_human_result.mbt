///|
fn accepted_human_result_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/accepted-human-result"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if accepted_human_result_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
fn accepted_human_result_identifier(value : String) -> Bool {
  valid_identifier(value) && value != "." && value != ".."
}

///|
// Evidence identities are opaque, never dereferenced. Preserve relative slash
// and colon forms while refusing machine-local absolute path disclosure.
fn accepted_human_result_evidence_id(
  value : String,
  workspace : String,
) -> Bool {
  !value.trim().is_empty() &&
  @encoding/utf8.encode(value).length() <= 4096 &&
  !value.iter().any(c => c < ' ' || c == '\u007f') &&
  !value.contains("\\") &&
  !value.has_prefix("/") &&
  !value.to_lower().has_prefix("file:") &&
  !(value.length() >= 3 &&
  value[0] is ('a'..='z' | 'A'..='Z') &&
  value[1] == ':' &&
  value[2] == '/') &&
  !value.contains(workspace)
}

///|
/// Export only the immutable human revision pinned by the exact accepted
/// report. The task/report references identify captured projections, not live
/// authenticity, a signature, a Book review, or permission to execute anything.
async fn accepted_human_result_projection(data : Json) -> Json {
  let handoff = book_lesson_handoff_projection(data)
  let task = native_field(data, "task")
  let report_snapshot = @json.parse(native_text(handoff, "report_snapshot"))
  let report = native_field(report_snapshot, "report")
  let pinned = native_field(report, "delivery_source_snapshot")
  let id = native_text(pinned, "revision_id")
  let original = native_continuation_original(
    task,
    native_text(task, "taskGuid"),
  )
  let source : Json = {
    "type": "human_revision",
    "revision_id": id,
    "original_run_id": native_text(original, "run_id"),
  }
  if !native_continuation_key(id) ||
    native_field(report, "delivery_source") != source {
    raise NativeContinuationError::Rejected(
      409, "The accepted report must pin this exact human revision",
    )
  }
  let saved = native_array(task, "human_revisions").filter(item => {
    native_text(item, "revision_id") == id
  })
  if saved.length() != 1 || saved[0] != pinned {
    raise NativeContinuationError::Rejected(
      409, "The accepted report's immutable human revision is missing or ambiguous",
    )
  }
  let revision = human_revision_snapshot(original, id)
  if revision != pinned {
    raise NativeContinuationError::Rejected(
      409, "The saved human revision no longer equals the accepted report snapshot",
    )
  }
  // Acceptance already pinned the validated native attribution. Check any
  // retained original/attached output for contradictions, but never discover,
  // attach, or require a new live runtime result for an accepted revision.
  let output = native_field(revision, "output")
  let command = native_text(output, "command_id")
  if command == native_text(original, "command_id") {
    human_revision_validate_output(revision, original)
  } else {
    let attached = native_array(task, "continuations").filter(item => {
      native_text(item, "command_id") == command
    })
    if attached.length() > 1 {
      raise NativeContinuationError::Rejected(
        409, "The captured native output identity is ambiguous",
      )
    }
    if attached.length() == 1 {
      human_revision_validate_output(revision, attached[0])
    }
  }
  let bytes = @encoding/utf8.encode(human_revision_content(original, revision))
  if bytes.iter().any(byte => byte == 0) {
    raise NativeContinuationError::Rejected(
      409, "Portable human revision text must not contain NUL bytes",
    )
  }
  if human_revision_snapshot(original, id) != pinned {
    raise NativeContinuationError::Rejected(
      409, "The accepted human revision changed during export readback",
    )
  }
  for
    value in [
      native_text(native_field(handoff, "task"), "record_id"),
      native_text(native_field(handoff, "report"), "record_id"),
      native_text(revision, "original_run_id"),
      native_text(revision, "session_id"),
      native_text(revision, "original_command_id"),
      native_text(output, "command_id"),
    ] {
    if !accepted_human_result_identifier(value) {
      raise NativeContinuationError::Rejected(
        409, "The captured result requires bounded, path-free source identifiers",
      )
    }
  }
  if !accepted_human_result_evidence_id(
      native_text(output, "evidence_id"),
      native_continuation_root(native_text(original, "workspace")),
    ) {
    raise NativeContinuationError::Rejected(
      409, "The captured evidence identity contains unavailable or machine-local metadata",
    )
  }
  for
    (value, reference) in [
      (task, native_field(handoff, "task")),
      (
        native_field(report_snapshot, "receipt"),
        native_field(handoff, "report"),
      ),
    ] {
    guard native_field(value, "revision") is Number(version, ..) &&
      version >= 1 &&
      version <= 2147483647 &&
      version.trunc() == version &&
      native_text(reference, "record_version") == version.to_int().to_string() else {
      raise NativeContinuationError::Rejected(
        409, "The captured record version is outside the portable integer range",
      )
    }
  }
  {
    "contract_version": "moonproj.accepted-human-result.v1",
    "source_product": "moonproj",
    "provenance_scope": "captured_accepted_human_revision",
    "authenticity": "unsigned_source_observation",
    "authorizing": false,
    "task": native_field(handoff, "task"),
    "report": native_field(handoff, "report"),
    "revision": {
      "revision_id": id,
      "original_run_id": native_text(revision, "original_run_id"),
      "session_id": native_text(revision, "session_id"),
      "original_command_id": native_text(revision, "original_command_id"),
      "output_command_id": native_text(output, "command_id"),
      "output_evidence_id": native_text(output, "evidence_id"),
      // This hashes the accepted parsed snapshot's deterministic stringify(),
      // not the original manifest file's lexical bytes or whitespace.
      "revision_snapshot_digest": "sha256:" +
      native_context_hash(@encoding/utf8.encode(pinned.stringify())),
    },
    "content": {
      "encoding": "base64",
      "media_type": "text/plain;charset=utf-8",
      "size_bytes": bytes.length(),
      "sha256": "sha256:" + native_context_hash(bytes),
      "data": @base64.encode(bytes),
    },
  }
}

///|
/// Authenticated read-only company projection and canonical saved bytes only.
/// No runtime command, mutation, ledger write, or downstream transmission.
async fn accepted_human_result_task(
  bridge : NativeBridge,
  task_id : String,
) -> ProxyResult {
  let detail = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
  if detail.status != 200 {
    return detail
  }
  let data = native_field(native_result_json(detail), "data")
  if native_text(native_field(data, "task"), "taskGuid") != task_id {
    raise NativeContinuationError::Rejected(
      409, "Company service returned another task",
    )
  }
  native_json_result(200, accepted_human_result_projection(data))
}
