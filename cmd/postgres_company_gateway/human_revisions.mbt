///|
fn human_revision_directory(id : String) -> String {
  ".moonsuite/products/moonproj/human-revisions/" + id
}

///|
fn human_revision_relative(path : String) -> Bool {
  !path.is_empty() &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.split("/").any(part => part == ".." || part == "." || part.is_empty())
}

///|
fn human_revision_validate(
  original : Json,
  id : String,
  revision : Json,
  bytes : Bytes,
) -> Unit raise {
  if !native_continuation_key(id) ||
    native_text(revision, "schema") != "moonproj.human-revision.v1" ||
    native_text(revision, "capture_scope") != "immutable_human_revision" ||
    native_text(revision, "revision_id") != id ||
    native_text(revision, "author_type") != "human" ||
    native_text(revision, "state") != "saved" {
    raise NativeContinuationError::Rejected(
      409, "The exact human revision is invalid",
    )
  }
  for
    (key, source_key) in [
      ("task_id", "task_id"),
      ("original_run_id", "run_id"),
      ("session_id", "session_id"),
      ("original_command_id", "command_id"),
    ] {
    if native_text(revision, key).is_empty() ||
      native_text(revision, key) != native_text(original, source_key) {
      raise NativeContinuationError::Rejected(
        409, "Human revision belongs to another captured task or execution",
      )
    }
  }
  if native_text(revision, "workspace") !=
    native_continuation_root(native_text(original, "workspace")) ||
    native_text(revision, "workspace_id").is_empty() ||
    native_text(revision, "created_at").is_empty() {
    raise NativeContinuationError::Rejected(
      409, "Human revision workspace does not match the captured execution",
    )
  }
  // Human edits never masquerade as native runtime commands or receipts.
  guard revision is Object(fields) else {
    raise NativeContinuationError::Rejected(
      409, "Human revision must be an object",
    )
  }
  for key, _ in fields {
    if ![
        "schema", "revision_id", "task_id", "original_run_id", "session_id", "original_command_id",
        "workspace", "workspace_id", "output", "author_type", "base", "content",
        "state", "created_at", "capture_scope",
      ].contains(key) {
      raise NativeContinuationError::Rejected(
        409,
        "Unsupported human revision field: " + key,
      )
    }
  }
  let output = native_field(revision, "output")
  let base = native_field(revision, "base")
  let content = native_field(revision, "content")
  for
    (value, allowed) in [
      (output, ["command_id", "path", "evidence_id"]),
      (base, ["scope", "sha256"]),
      (content, ["path", "sha256", "size_bytes"]),
    ] {
    guard value is Object(items) else {
      raise NativeContinuationError::Rejected(
        409, "Human revision references must be objects",
      )
    }
    for key, _ in items {
      if !allowed.contains(key) {
        raise NativeContinuationError::Rejected(
          409, "Unsupported human revision reference field",
        )
      }
    }
  }
  if !valid_identifier(native_text(output, "command_id")) ||
    !human_revision_relative(native_text(output, "path")) ||
    native_text(output, "evidence_id").is_empty() ||
    native_text(base, "scope") != "current_workspace_bytes_at_edit" ||
    !native_hex(native_text(base, "sha256"), 64) ||
    native_text(content, "path") !=
    human_revision_directory(id) + "/content.txt" ||
    !native_hex(native_text(content, "sha256"), 64) ||
    native_field(content, "size_bytes") != bytes.length().to_json() ||
    bytes.length() > 256 * 1024 ||
    native_context_hash(bytes) != native_text(content, "sha256") ||
    @encoding/utf8.encode(@encoding/utf8.decode(bytes)) != bytes {
    raise NativeContinuationError::Rejected(
      409, "Human revision content, digest or UTF-8 byte limit is invalid",
    )
  }
}

///|
fn human_revision_validate_output(revision : Json, source : Json) -> Unit raise {
  let output = native_field(revision, "output")
  let command = native_text(output, "command_id")
  if native_text(source, "command_id") != command ||
    !native_array(source, "artifact_refs").any(item => {
      native_text(item, "command_id") == command &&
      native_text(item, "path") == native_text(output, "path") &&
      native_text(item, "evidence_id") == native_text(output, "evidence_id")
    }) {
    raise NativeContinuationError::Rejected(
      409, "Human revision output does not match an exact attributed native artifact",
    )
  }
}

///|
async fn human_revision_read_file(
  root : String,
  relative : String,
  limit : Int,
) -> Bytes {
  try {
    let canonical = @fs.realpath(root)
    let path = canonical + "/" + relative
    if !human_revision_relative(relative) ||
      @fs.kind(canonical, follow_symlink=false) != Directory ||
      @fs.realpath(path) != path ||
      @fs.kind(path, follow_symlink=false) != Regular {
      raise NativeContinuationError::Rejected(
        409, "Human revision is not a canonical file in the captured workspace",
      )
    }
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let size = file.size()
    if size < 0L || size > limit.to_int64() {
      raise NativeContinuationError::Rejected(
        409, "Human revision exceeds the bounded capture limit",
      )
    }
    let bytes = file.read_exactly_at(size.to_int(), position=0L)
    if file.size() != size || @fs.realpath(path) != path {
      raise NativeContinuationError::Rejected(
        409, "Human revision changed during canonical readback",
      )
    }
    bytes
  } catch {
    NativeContinuationError::Rejected(status, message) =>
      raise NativeContinuationError::Rejected(status, message)
    _ =>
      raise NativeContinuationError::Rejected(
        409, "The exact saved human revision is unavailable; recover it in MoonDesk",
      )
  }
}

///|
async fn human_revision_snapshot(original : Json, id : String) -> Json {
  if !native_continuation_key(id) {
    raise NativeContinuationError::Rejected(
      400, "An exact human revision identifier is required",
    )
  }
  let root = native_continuation_root(native_text(original, "workspace"))
  let directory = human_revision_directory(id)
  let manifest_bytes = human_revision_read_file(
    root,
    directory + "/revision.json",
    128 * 1024,
  )
  if @encoding/utf8.encode(@encoding/utf8.decode(manifest_bytes)) !=
    manifest_bytes {
    raise NativeContinuationError::Rejected(
      409, "Saved human revision manifest must be UTF-8",
    )
  }
  let revision = @json.parse(@encoding/utf8.decode(manifest_bytes)) catch {
    _ =>
      raise NativeContinuationError::Rejected(
        409, "Saved human revision manifest is invalid",
      )
  }
  let bytes = human_revision_read_file(
    root,
    directory + "/content.txt",
    256 * 1024,
  )
  human_revision_validate(original, id, revision, bytes)
  if human_revision_read_file(root, directory + "/revision.json", 128 * 1024) !=
    manifest_bytes {
    raise NativeContinuationError::Rejected(
      409, "Human revision manifest changed during readback",
    )
  }
  revision
}

///|
/// Read-only display bytes. They never cross the service mutation boundary or
/// replace the immutable manifest pinned by a report.
async fn human_revision_content(original : Json, revision : Json) -> String {
  let id = native_text(revision, "revision_id")
  if !native_continuation_key(id) {
    raise NativeContinuationError::Rejected(
      400, "An exact human revision identifier is required",
    )
  }
  let bytes = human_revision_read_file(
    native_continuation_root(native_text(original, "workspace")),
    human_revision_directory(id) + "/content.txt",
    256 * 1024,
  )
  human_revision_validate(original, id, revision, bytes)
  @encoding/utf8.decode(bytes)
}

///|
async fn human_revision_candidate_source(
  task : Json,
  revision : Json,
  read_continuation : async (String) -> Json,
) -> Json {
  let original = native_continuation_original(
    task,
    native_text(task, "taskGuid"),
  )
  let id = native_text(revision, "revision_id")
  let command = native_text(native_field(revision, "output"), "command_id")
  let source = if command == native_text(original, "command_id") {
    original
  } else {
    let attached = native_array(task, "continuations").filter(item => {
      native_text(item, "command_id") == command
    })
    if attached.length() == 1 {
      attached[0]
    } else if attached.is_empty() {
      // An exact native Desk continuation may be edited before attaching its
      // agent result. Read it canonically without selecting or importing it.
      read_continuation(command)
    } else {
      raise NativeContinuationError::Rejected(
        409, "Ambiguous historical native command identity",
      )
    }
  }
  human_revision_validate_output(revision, source)
  for saved in native_array(task, "human_revisions") {
    if native_text(saved, "revision_id") == id && saved != revision {
      raise NativeContinuationError::Rejected(
        409, "Saved human revision identity is immutable",
      )
    }
  }
  revision
}

///|
async fn native_human_revision_candidate(
  task : Json,
  id : String,
  moonclaw_uri : String,
) -> Json {
  let original = native_continuation_original(
    task,
    native_text(task, "taskGuid"),
  )
  let revision = human_revision_snapshot(original, id)
  human_revision_candidate_source(task, revision, command => {
    let control = native_load_control(moonclaw_uri)
    let listing = native_continuation_listing(
      task,
      native_text(task, "taskGuid"),
      command,
      path => native_request(control, @http.Get, path, ""),
      (candidate, original_command) => {
        native_continuation_snapshot(original, candidate, original_command)
      },
    )
    native_field(listing, "candidate")
  })
}

///|
fn native_human_revision_import_body(
  original : Json,
  requested : Json,
  candidate : Json,
) -> Json raise {
  if native_text(requested, "original_run_id") !=
    native_text(original, "run_id") ||
    native_text(requested, "human_revision_id") !=
    native_text(candidate, "revision_id") ||
    native_text(candidate, "original_run_id") != native_text(original, "run_id") ||
    native_field(requested, "select_for_delivery") != Json::boolean(true) ||
    !native_text(requested, "command_id").is_empty() ||
    !native_text(requested, "continuation_id").is_empty() ||
    !(native_field(requested, "selected_delivery_source") is Null) {
    raise NativeContinuationError::Rejected(
      409, "Human revision selection requires its exact captured identity",
    )
  }
  {
    "human_revision": candidate,
    "select_for_delivery": true,
    "authority": native_field(requested, "authority"),
  }
}
