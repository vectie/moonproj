///|
fn dispatch_task_inspection_only(model : Model) -> Bool {
  ["accepted", "done"].contains(model.dispatch_task_stage)
}

///|
fn dispatch_human_revision_digest(value : String) -> Bool {
  value.length() == 64 &&
  value.iter().all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))
}

///|
fn dispatch_human_revision_id_valid(value : String) -> Bool {
  value != "" &&
  value.length() <= 128 &&
  value
  .iter()
  .all(ch => {
    (ch >= '0' && ch <= '9') ||
    (ch >= 'a' && ch <= 'z') ||
    (ch >= 'A' && ch <= 'Z') ||
    ch == '_' ||
    ch == '-'
  })
}

///|
fn dispatch_human_revision_workspace(value : String) -> String {
  if !value.has_prefix("/") || value.contains("\\") || value.contains("\u0000") {
    return ""
  }
  let parts : Array[String] = []
  for part in value.split("/") {
    if part == ".." {
      ignore(parts.pop())
    } else if part != "" && part != "." {
      parts.push(part.to_owned())
    }
  }
  "/" + parts.join("/")
}

///|
fn dispatch_human_revision_content_valid(record : Json, value : Json) -> Bool {
  guard value is String(text) else { return false }
  match
    dispatch_json_field(dispatch_json_field(record, "content"), "size_bytes") {
    Number(size, ..) =>
      size >= 0.0 &&
      size <= 262144.0 &&
      dispatch_human_revision_utf8_size(text).to_double() == size
    _ => false
  }
}

///|
#cfg(target="js")
extern "js" fn dispatch_human_revision_utf8_size(value : String) -> Int32 =
  #| value => new TextEncoder().encode(value).length

///|
// A human-authored snapshot is a sibling source, never a synthetic native run.
// The server verifies the immutable bytes; this boundary validates attribution.
fn dispatch_human_revision_valid(model : Model, record : Json) -> Bool {
  guard model.dispatch_run is Some(run) else { return false }
  let output = dispatch_json_field(record, "output")
  let base = dispatch_json_field(record, "base")
  let content = dispatch_json_field(record, "content")
  let revision_id = dispatch_json_text(record, "revision_id")
  let workspace = dispatch_human_revision_workspace(run.workspace)
  let size_valid = match dispatch_json_field(content, "size_bytes") {
    Number(size, ..) =>
      dispatch_product_context_bytes_valid(size) && size <= 262144.0
    _ => false
  }
  dispatch_json_text(record, "schema") == "moonproj.human-revision.v1" &&
  dispatch_json_text(record, "capture_scope") == "immutable_human_revision" &&
  dispatch_json_text(record, "task_id") == model.dispatch_task_id &&
  dispatch_json_text(record, "original_run_id") == run.run_id &&
  dispatch_json_text(record, "session_id") == run.session_id &&
  dispatch_json_text(record, "original_command_id") == run.command_id &&
  workspace != "" &&
  dispatch_json_text(record, "workspace") == workspace &&
  dispatch_json_text(record, "workspace_id") != "" &&
  dispatch_human_revision_id_valid(revision_id) &&
  dispatch_json_text(record, "author_type") == "human" &&
  dispatch_json_text(record, "state") == "saved" &&
  dispatch_json_text(record, "created_at") != "" &&
  dispatch_json_field(record, "command_id") is Null &&
  dispatch_json_field(record, "model") is Null &&
  dispatch_json_field(record, "receipt") is Null &&
  dispatch_json_text(output, "command_id") != "" &&
  dispatch_json_text(output, "evidence_id") != "" &&
  dispatch_output_valid_path(dispatch_json_text(output, "path")) &&
  dispatch_json_text(base, "scope") == "current_workspace_bytes_at_edit" &&
  dispatch_human_revision_digest(dispatch_json_text(base, "sha256")) &&
  dispatch_json_text(content, "path") ==
  ".moonsuite/products/moonproj/human-revisions/" + revision_id + "/content.txt" &&
  dispatch_human_revision_digest(dispatch_json_text(content, "sha256")) &&
  size_valid
}

///|
fn dispatch_delivery_source_valid(
  model : Model,
  selected : Json,
  continuations : Array[Json],
  human_revisions : Array[Json],
) -> Bool {
  if selected is Null {
    return true
  }
  guard model.dispatch_run is Some(run) else { return false }
  if dispatch_json_text(selected, "original_run_id") != run.run_id {
    return false
  }
  match dispatch_json_text(selected, "type") {
    "original" => dispatch_json_text(selected, "command_id") == run.command_id
    "continuation" =>
      continuations.any(record => {
        dispatch_continuation_valid(model, record) &&
        dispatch_json_text(record, "command_id") ==
        dispatch_json_text(selected, "command_id") &&
        dispatch_json_text(record, "continuation_id") ==
        dispatch_json_text(selected, "continuation_id")
      })
    "human_revision" =>
      dispatch_json_field(selected, "command_id") is Null &&
      human_revisions.any(record => {
        dispatch_human_revision_valid(model, record) &&
        dispatch_json_text(record, "revision_id") ==
        dispatch_json_text(selected, "revision_id")
      })
    _ => false
  }
}

///|
fn dispatch_human_revision_selected(model : Model) -> Json? {
  let state = model.dispatch_continuation
  if state.actor != model.dispatch_task_actor_id ||
    state.task_id != model.dispatch_task_id ||
    state.selection != model.dispatch_task_selection ||
    !state.source_verified ||
    dispatch_json_text(state.selected, "type") != "human_revision" ||
    !dispatch_delivery_source_valid(
      model,
      state.selected,
      state.records,
      state.human_revisions,
    ) {
    return None
  }
  state.human_revisions
  .filter(record => {
    dispatch_json_text(record, "revision_id") ==
    dispatch_json_text(state.selected, "revision_id")
  })
  .get(0)
}

///|
fn dispatch_delivery_source_label(source : Json) -> String {
  if dispatch_json_text(source, "type") == "human_revision" {
    "人工修订 / " + dispatch_json_text(source, "revision_id")
  } else {
    dispatch_json_text(source, "type") +
    " / " +
    dispatch_json_text(source, "command_id")
  }
}

///|
#cfg(target="js")
extern "js" fn dispatch_human_revision_return_hint(
  page : String,
  task : String,
) -> String =
  #| (page, task) => { try { const url = new URL(page); return url.searchParams.get('task') === task ? url.searchParams.get('human_revision_id') || '' : ''; } catch (_) { return ''; } }
