///|
fn safe_artifact_ref(reference : String) -> Bool {
  let normalized = reference.trim().replace(old="\\", new="/")
  !normalized.is_empty() &&
  !normalized.has_prefix("/") &&
  !normalized
  .split("/")
  .any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn scoped_path(root : String, reference : String) -> String raise {
  if !safe_artifact_ref(reference) {
    fail("MoonProj artifact must be workspace-relative: \{reference}")
  }
  @pathx.join(root, reference)
}

///|
async fn resolve_workspace(workspace : String) -> String {
  @fs.realpath(@pathx.normalize(workspace))
}

///|
fn within_workspace(root : String, resolved : String) -> Bool {
  let physical_root = if root == "/tmp" ||
    root.has_prefix("/tmp/") ||
    root == "/var" ||
    root.has_prefix("/var/") {
    "/private" + root
  } else {
    root
  }
  resolved == root ||
  resolved.has_prefix(root + "/") ||
  resolved == physical_root ||
  resolved.has_prefix(physical_root + "/")
}

///|
async fn checked_input_path(root : String, reference : String) -> String {
  let path = scoped_path(root, reference)
  let resolved = @fs.realpath(path)
  if !within_workspace(root, resolved) {
    fail(
      "MoonProj input artifact escapes the workspace: \{reference}; root=\{root}; resolved=\{resolved}",
    )
  }
  resolved
}

///|
async fn ensure_output_parent(root : String, reference : String) -> String {
  let path = scoped_path(root, reference)
  let parent = @pathx.dirname(path).to_owned()
  @fsx.make_directory(parent, recursive=true, exists_ok=true)
  let resolved_parent = @fs.realpath(parent)
  if !within_workspace(root, resolved_parent) {
    fail("MoonProj output parent escapes the workspace: \{reference}")
  }
  path
}

///|
async fn read_text_ref(root : String, reference : String) -> String {
  @fs.read_file(checked_input_path(root, reference)).text()
}

///|
async fn read_json_ref(root : String, reference : String) -> Json {
  @json.parse(read_text_ref(root, reference))
}

///|
async fn read_optional_json_ref(root : String, reference : String) -> Json? {
  let path = scoped_path(root, reference)
  if !@fs.exists(path) {
    return None
  }
  Some(@json.parse(@fs.read_file(checked_input_path(root, reference)).text()))
}

///|
fn sha256_bytes(bytes : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes))}"
}

///|
fn sha256_text(text : String) -> String {
  sha256_bytes(@utf8.encode(text))
}

///|
async fn digest_ref(root : String, reference : String) -> String {
  sha256_bytes(@fs.read_file(checked_input_path(root, reference)).binary())
}

///|
async fn immutable_text_ref(
  root : String,
  reference : String,
  text : String,
) -> String {
  let path = ensure_output_parent(root, reference)
  if @fs.exists(path) {
    let resolved = @fs.realpath(path)
    if !within_workspace(root, resolved) ||
      @fs.read_file(resolved).text() != text {
      fail("MoonProj immutable artifact conflicts: \{reference}")
    }
    return text
  }
  @fs.write_file(
    path,
    text,
    create_mode=@fs.CreateNew,
    permission=0o644,
    sync=@fs.Full,
  ) catch {
    _ =>
      if !@fs.exists(path) ||
        @fs.read_file(checked_input_path(root, reference)).text() != text {
        fail("MoonProj could not create immutable artifact: \{reference}")
      }
  }
  text
}

///|
async fn immutable_json_ref(
  root : String,
  reference : String,
  value : Json,
) -> String {
  immutable_text_ref(root, reference, value.stringify(indent=2) + "\n")
}

///|
async fn declared_input_digest(
  root : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for reference in artifacts {
    identities.push("\{reference}|\{digest_ref(root, reference)}")
  }
  sha256_text(identities.join("\n"))
}
