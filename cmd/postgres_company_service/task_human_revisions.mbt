///|
/// Immutable human-authored snapshots are siblings of native executions.
fn plan_task_human_revisions(task : Json) -> Array[Json] {
  match json_field(task, "human_revisions") {
    Some(Array(items)) => items.copy()
    _ => []
  }
}

///|
fn plan_task_human_revision_source(revision : Json) -> Json {
  {
    "type": "human_revision",
    "revision_id": json_text(revision, "revision_id", ""),
    "original_run_id": json_text(revision, "original_run_id", ""),
  }
}

///|
fn plan_task_human_revision_root(root : String) -> String {
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
fn plan_task_human_revision_validate(
  task : Json,
  revision : Json,
) -> Unit raise CompanyServiceError {
  let original = json_field(task, "execution").unwrap_or(Json::null())
  let id = json_text(revision, "revision_id", "")
  if id.is_empty() ||
    id.length() > 128 ||
    !id.iter().all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-')) ||
    json_text(revision, "schema", "") != "moonproj.human-revision.v1" ||
    json_text(revision, "capture_scope", "") != "immutable_human_revision" ||
    json_text(revision, "author_type", "") != "human" ||
    json_text(revision, "state", "") != "saved" ||
    json_text(original, "task_id", "") != json_text(task, "task_id", "") {
    raise reject(422, "invalid human revision identity or author type")
  }
  guard revision is Object(fields) else {
    raise reject(422, "human revision must be an object")
  }
  for key, _ in fields {
    if ![
        "schema", "revision_id", "task_id", "original_run_id", "session_id", "original_command_id",
        "workspace", "workspace_id", "output", "author_type", "base", "content",
        "state", "created_at", "capture_scope",
      ].contains(key) {
      raise reject(422, "unsupported human revision field: " + key)
    }
  }
  for
    (key, original_key) in [
      ("task_id", "task_id"),
      ("original_run_id", "run_id"),
      ("session_id", "session_id"),
      ("original_command_id", "command_id"),
    ] {
    if json_text(revision, key, "").is_empty() ||
      json_text(revision, key, "") != json_text(original, original_key, "") {
      raise reject(
        409, "human revision belongs to another captured task or execution",
      )
    }
  }
  let workspace = json_text(original, "workspace", "")
  if !workspace.has_prefix("/") ||
    json_text(revision, "workspace", "") !=
    plan_task_human_revision_root(workspace) ||
    json_text(revision, "workspace_id", "").is_empty() ||
    json_text(revision, "created_at", "").is_empty() {
    raise reject(
      409, "human revision workspace does not match captured execution",
    )
  }
  let content = json_field(revision, "content").unwrap_or(Json::null())
  let base = json_field(revision, "base").unwrap_or(Json::null())
  let output = json_field(revision, "output").unwrap_or(Json::null())
  for
    (value, keys) in [
      (content, ["path", "sha256", "size_bytes"]),
      (base, ["scope", "sha256"]),
      (output, ["command_id", "path", "evidence_id"]),
    ] {
    guard value is Object(items) else {
      raise reject(422, "human revision references must be objects")
    }
    for key, _ in items {
      if !keys.contains(key) {
        raise reject(422, "unsupported human revision reference field")
      }
    }
  }
  for value in [content, base] {
    let digest = json_text(value, "sha256", "")
    if digest.length() != 64 ||
      !digest.iter().all(c => c is ('0'..='9' | 'a'..='f')) {
      raise reject(422, "human revision requires lowercase SHA-256 digests")
    }
  }
  let path = json_text(output, "path", "")
  let size = json_int(content, "size_bytes", -1)
  if json_text(content, "path", "") !=
    ".moonsuite/products/moonproj/human-revisions/" + id + "/content.txt" ||
    size < 0 ||
    size > 256 * 1024 ||
    json_field(content, "size_bytes") != Some(size.to_json()) ||
    json_text(base, "scope", "") != "current_workspace_bytes_at_edit" ||
    !valid_identifier(json_text(output, "command_id", "")) ||
    json_text(output, "evidence_id", "").is_empty() ||
    path.is_empty() ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.split("/").any(part => part == "." || part == ".." || part.is_empty()) {
    raise reject(
      422, "human revision requires bounded content and exact output references",
    )
  }
}

///|
fn plan_task_human_revision_apply(
  task : Json,
  revision : Json,
) -> Json raise CompanyServiceError {
  plan_task_human_revision_validate(task, revision)
  let items = plan_task_human_revisions(task)
  let matches = items.filter(item => {
    json_text(item, "revision_id", "") == json_text(revision, "revision_id", "")
  })
  if matches.length() > 1 ||
    (matches.length() == 1 && !json_equal(matches[0], revision)) {
    raise reject(
      409, "human revision identity and captured content are immutable",
    )
  }
  if matches.is_empty() {
    items.push(revision)
  }
  let fields = match task {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields.set("human_revisions", items.to_json())
  Json::object(fields)
}
