///|
fn native_continuation_validate_snapshot(
  original : Json,
  command : Json,
  original_command : Json,
  snapshot : Json,
  input_bytes : Bytes,
) -> Unit raise {
  let lineage = native_continuation_lineage(original, command)
  let source = native_field(snapshot, "source")
  let packet = native_field(command, "packet")
  let input = native_field(lineage, "input")
  if native_text(snapshot, "schema") != "moondesk.work-continuation-snapshot.v1" ||
    native_text(snapshot, "continuation_id") !=
    native_text(lineage, "continuation_id") ||
    native_text(snapshot, "command_id") != native_text(packet, "command_id") ||
    native_text(snapshot, "client_turn_id") !=
    native_text(packet, "client_turn_id") ||
    native_text(snapshot, "prior_result_command_id") !=
    native_text(lineage, "prior_result_command_id") ||
    native_text(snapshot, "model") != native_text(command, "model") ||
    native_field(snapshot, "input") != input ||
    native_text(source, "task_id") != native_text(original, "task_id") ||
    native_text(source, "run_id") != native_text(original, "run_id") ||
    native_text(source, "session_id") != native_text(original, "session_id") ||
    native_text(source, "original_command_id") !=
    native_text(original, "command_id") ||
    native_continuation_root(native_text(source, "book_root")) !=
    native_continuation_root(native_text(original, "workspace")) {
    raise NativeContinuationError::Rejected(
      409, "Saved continuation input does not match the canonical native command",
    )
  }
  let body = native_text(snapshot, "request_body")
  let parsed = @json.parse(body) catch {
    _ =>
      raise NativeContinuationError::Rejected(
        409, "Saved native request is invalid",
      )
  }
  if parsed != command ||
    native_context_hash(@encoding/utf8.encode(body)) !=
    native_text(snapshot, "request_sha256") ||
    native_context_hash(input_bytes) != native_text(input, "sha256") ||
    @encoding/utf8.encode(native_text(snapshot, "input_text")) != input_bytes {
    raise NativeContinuationError::Rejected(
      409, "Saved continuation input or request digest does not match accepted work",
    )
  }
  let instruction = native_text(snapshot, "instruction")
  if instruction.trim().is_empty() ||
    native_text(command, "text") != instruction {
    raise NativeContinuationError::Rejected(
      409, "Saved human instruction does not match the accepted prompt",
    )
  }
  let context = native_field(snapshot, "original_context")
  let context_path = native_text(original_command, "context_path")
  if native_text(context, "path") != context_path {
    raise NativeContinuationError::Rejected(
      409, "Saved input points at different original requirements",
    )
  }
  let captured_context = native_field(original, "product_context")
  if captured_context is Object(_) &&
    (
      native_text(context, "path") !=
      native_text(captured_context, "context_path") ||
      native_text(context, "sha256") != native_text(captured_context, "sha256")
    ) {
    raise NativeContinuationError::Rejected(
      409, "Saved original requirements digest does not match the captured task",
    )
  }
  let prior = native_field(snapshot, "prior_result")
  if native_text(prior, "command_id") !=
    native_text(lineage, "prior_result_command_id") {
    raise NativeContinuationError::Rejected(
      409, "Saved input names a different selected prior result",
    )
  }
}

///|
async fn native_continuation_read_file(
  root : String,
  relative : String,
  limit : Int,
) -> Bytes {
  try {
    // A trusted captured workspace may itself be a platform symlink alias.
    // Resolve that root once; feature-owned descendants must remain direct
    // canonical files inside it, matching Desk's confined storage helper.
    let canonical = @fs.realpath(root)
    let path = canonical + "/" + relative
    if @fs.kind(canonical, follow_symlink=false) != Directory ||
      @fs.realpath(path) != path ||
      @fs.kind(path, follow_symlink=false) != Regular {
      raise NativeContinuationError::Rejected(
        409, "Continuation input is not a canonical file within the captured workspace",
      )
    }
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    if file.size() <= 0L || file.size() > limit.to_int64() {
      raise NativeContinuationError::Rejected(
        409, "Continuation input is empty or exceeds the capture limit",
      )
    }
    file.read_all().binary()
  } catch {
    NativeContinuationError::Rejected(status, message) =>
      raise NativeContinuationError::Rejected(status, message)
    _ =>
      raise NativeContinuationError::Rejected(
        409, "The exact persisted continuation input is unavailable; recover it in MoonDesk before attaching",
      )
  }
}

///|
async fn native_continuation_snapshot(
  original : Json,
  command : Json,
  original_command : Json,
) -> Json {
  let lineage = native_continuation_lineage(original, command)
  let directory = native_continuation_directory(
    native_text(lineage, "continuation_id"),
  )
  let root = native_continuation_root(native_text(original, "workspace"))
  let bytes = native_continuation_read_file(
    root,
    directory + "/submission.json",
    8 * 1024 * 1024,
  )
  let snapshot = @json.parse(@encoding/utf8.decode(bytes)) catch {
    _ =>
      raise NativeContinuationError::Rejected(
        409, "Saved continuation snapshot is invalid",
      )
  }
  let input = native_continuation_read_file(
    root,
    directory + "/input.md",
    4 * 1024 * 1024,
  )
  native_continuation_validate_snapshot(
    original, command, original_command, snapshot, input,
  )
  snapshot
}

///|
fn native_continuation_readback(
  original : Json,
  command : Json,
  claims : Json,
  events : Json,
  service : Json,
) -> Json raise {
  let lineage = native_continuation_lineage(original, command)
  let command_id = native_text(native_field(command, "packet"), "command_id")
  ignore(native_continuation_claim(original, claims, command_id))
  native_continuation_validate_prior(original, claims, lineage)
  // Reuse the command-scoped receipt/evidence extractor with a distinct DTO.
  // It is never sent to original execution/observe.
  let identity : Json = {
    "run_id": native_text(original, "run_id"),
    "task_id": native_text(original, "task_id"),
    "session_id": native_text(original, "session_id"),
    "command_id": command_id,
    "workspace": native_text(claims, "book_root"),
    "output_urls": [],
  }
  let observation = native_execution_readback(identity, claims, events, service)
  let fields = match observation {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields.remove("run_id")
  fields["continuation_id"] = native_field(lineage, "continuation_id")
  fields["original_run_id"] = native_field(original, "run_id")
  fields["original_command_id"] = native_field(original, "command_id")
  fields["prior_result_command_id"] = native_field(
    lineage, "prior_result_command_id",
  )
  fields["client_turn_id"] = native_field(
    native_field(command, "packet"),
    "client_turn_id",
  )
  fields["workspace"] = native_field(original, "workspace")
  fields["model"] = native_field(command, "model")
  fields["input"] = native_field(lineage, "input")
  Json::object(fields)
}
