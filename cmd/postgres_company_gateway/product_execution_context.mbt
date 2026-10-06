///|
fn native_context_hash(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn native_context_int(value : Json, key : String) -> Int {
  match native_field(value, key) {
    Number(number, ..) => number.to_int()
    _ => -1
  }
}

///|
async fn native_context_read(path : String, limit : Int) -> Bytes? {
  try {
    let file = @fs.open(path, mode=@fs.ReadOnly)
    defer file.close()
    if file.size() <= 0L || file.size() > limit.to_int64() {
      return None
    }
    Some(file.read_all().binary())
  } catch {
    _ => None
  }
}

///|
/// Text is copied only from the declared derivative of the exact packaged DOCX.
/// Failure is context information, never a product admission decision.
async fn native_context_prd(
  resources : ProductResources,
  product : @registry.Product,
) -> (String, Json, Array[String]) {
  let documents = product.documents.filter(document => {
    native_text(Json::object(document.metadata), "type") == "prd"
  })
  if documents.length() != 1 {
    return ("", Json::null(), ["PRD declaration is missing or ambiguous"])
  }
  let document = documents[0]
  let declared = Json::object(document.metadata)
  let base : Json = {
    "document_id": document.id,
    "source_sha256": native_text(declared, "sha256"),
    "source_size_bytes": native_field(declared, "size_bytes"),
    "version": native_text(declared, "version"),
    "coverage": "unavailable",
  }
  if document.source_kind != "packaged" || !document.path.has_suffix(".docx") {
    return ("", base, ["PRD format has no supported text extraction"])
  }
  let manifest = try {
    let path = match
      contained_product_path(resources.document_root, "manifest.json", false) {
      Some(path) => path
      None => return ("", base, ["PRD text manifest is unavailable"])
    }
    let bytes = match native_context_read(path, 2 * 1024 * 1024) {
      Some(bytes) => bytes
      None => return ("", base, ["PRD text manifest is unavailable"])
    }
    @json.parse(@encoding/utf8.decode(bytes))
  } catch {
    _ => return ("", base, ["PRD text manifest is unavailable"])
  }
  if native_text(manifest, "schema") != "moonsuite.product-documents.v1" {
    return ("", base, ["PRD text manifest schema is unsupported"])
  }
  let matches = native_array(manifest, "assets").filter(asset => {
    native_text(asset, "product_id") == product.id &&
    native_text(asset, "document_id") == document.id &&
    native_text(asset, "path") == document.path
  })
  if matches.length() != 1 {
    return ("", base, ["PRD text manifest entry is missing or ambiguous"])
  }
  let extraction = native_field(matches[0], "text_extraction")
  if native_text(extraction, "schema") != "moonsuite.product-document-text.v1" ||
    native_text(extraction, "extraction_version") != "docx-body-v1" ||
    native_text(extraction, "media_type") != "text/plain; charset=utf-8" ||
    !["complete", "partial"].contains(native_text(extraction, "coverage")) {
    return ("", base, ["PRD text extraction is missing or unsupported"])
  }
  let source_path = product_document_path(resources, product, document)
  let source = match source_path {
    Some(path) => native_context_read(path, 16 * 1024 * 1024)
    None => None
  }
  let source = match source {
    Some(bytes) => bytes
    None => return ("", base, ["Declared PRD source is unavailable"])
  }
  let source_hash = native_context_hash(source)
  if source_hash != native_text(declared, "sha256") ||
    source.length() != native_context_int(declared, "size_bytes") ||
    source_hash != native_text(extraction, "source_docx_sha256") ||
    source.length() != native_context_int(extraction, "source_docx_size_bytes") {
    return (
      "",
      base,
      ["PRD source or text extraction is stale (source identity mismatch)"],
    )
  }
  let text_path = contained_product_path(
    resources.document_root,
    native_text(extraction, "path"),
    false,
  )
  let text_bytes = match text_path {
    Some(path) => native_context_read(path, 2 * 1024 * 1024)
    None => None
  }
  let text_bytes = match text_bytes {
    Some(bytes) => bytes
    None => return ("", base, ["Declared PRD text is unavailable"])
  }
  if native_context_hash(text_bytes) != native_text(extraction, "text_sha256") ||
    text_bytes.length() != native_context_int(extraction, "size_bytes") {
    return ("", base, ["PRD text extraction is stale (text identity mismatch)"])
  }
  let text = @encoding/utf8.decode(text_bytes) catch {
    _ => return ("", base, ["PRD text is not valid UTF-8"])
  }
  let fields = match base {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  for key in ["text_sha256", "extraction_version", "coverage", "limitations"] {
    fields.set(key, native_field(extraction, key))
  }
  fields.set("text_size_bytes", native_field(extraction, "size_bytes"))
  fields.set("text_path", native_field(extraction, "path"))
  let issues = if native_text(extraction, "coverage") == "partial" {
    ["PRD extraction covers only supported text; inspect its limitations"]
  } else {
    []
  }
  (text, Json::object(fields), issues)
}

///|
fn native_context_snapshot(
  task : Json,
  product_name : String,
  purpose : String,
  philosophy : Json,
  prd_text : String,
  prd : Json,
  catalog_sha256 : String,
  coverage : String,
  issues : Array[String],
) -> Json {
  let provenance : Json = {
    "task_id": native_text(task, "taskGuid"),
    "project_id": native_text(task, "projGuid"),
    "task_revision": native_field(task, "revision"),
    "product_id": native_text(task, "product_id"),
    "catalog_sha256": catalog_sha256,
    "philosophy_source": {
      "source_kind": native_field(philosophy, "source_kind"),
      "source": native_field(philosophy, "source"),
      "version": native_field(philosophy, "version"),
      "sha256": native_field(philosophy, "sha256"),
    },
    "prd": prd,
    "coverage": coverage,
    "issues": issues,
  }
  let text = "# MoonProj captured execution context\n\n" +
    "## Task title\n" +
    native_text(task, "taskName") +
    "\n\n## Task requirements and acceptance criteria\n" +
    native_text(task, "remarks") +
    @task_evidence.source_prompt(task) +
    "\n\n## Product identity and purpose\n" +
    native_text(task, "product_id") +
    " / " +
    product_name +
    "\n" +
    purpose +
    "\n\n## Current captured product philosophy (direction)\n" +
    philosophy.stringify(indent=2) +
    "\n\n## Source provenance and capture limits\n" +
    provenance.stringify(indent=2) +
    "\n\n## Full supported PRD body text (dated supporting requirements)\n" +
    prd_text +
    "\n"
  let bytes = @encoding/utf8.encode(text)
  let hash = native_context_hash(bytes)
  {
    "schema": "moonproj.product-context.v1",
    "product_id": native_text(task, "product_id"),
    "product_name": product_name,
    "direction_excerpt": native_text(philosophy, "excerpt"),
    "coverage": coverage,
    "issues": issues,
    "context_path": ".moonsuite/products/moonproj/execution-context/" +
    hash +
    "/context.md",
    "sha256": hash,
    "size_bytes": bytes.length(),
    "prd": prd,
    "provenance": provenance,
    "text": text,
  }
}

///|
async fn native_capture_product_context(
  task : Json,
  resources : ProductResources,
) -> Json {
  let product_id = native_text(task, "product_id")
  if product_id.is_empty() {
    return native_context_snapshot(
      task,
      "",
      "",
      Json::null(),
      "",
      Json::null(),
      "",
      "untagged",
      ["Task has no product association"],
    )
  }
  let catalog_bytes = match
    native_context_read(resources.catalog_path, 2 * 1024 * 1024) {
    Some(bytes) => bytes
    None =>
      return native_context_snapshot(
        task,
        "",
        "",
        Json::null(),
        "",
        Json::null(),
        "",
        "unavailable",
        ["Product catalog is missing or invalid"],
      )
  }
  let catalog = @registry.parse(@encoding/utf8.decode(catalog_bytes)) catch {
    _ =>
      return native_context_snapshot(
        task,
        "",
        "",
        Json::null(),
        "",
        Json::null(),
        "",
        "unavailable",
        ["Product catalog is missing or invalid"],
      )
  }
  let hash = native_context_hash(catalog_bytes)
  let product = match catalog.find(product_id) {
    Some(product) => product
    None =>
      return native_context_snapshot(
        task,
        "",
        "",
        Json::null(),
        "",
        Json::null(),
        hash,
        "unavailable",
        ["Product association is not in the captured catalog"],
      )
  }
  let metadata = Json::object(product.metadata)
  let (text, prd, issues) = native_context_prd(resources, product)
  native_context_snapshot(
    task,
    native_text(metadata, "name"),
    native_text(metadata, "purpose"),
    native_field(metadata, "philosophy"),
    text,
    prd,
    hash,
    if issues.is_empty() {
      "complete"
    } else {
      "partial"
    },
    issues,
  )
}

///|
fn native_context_prompt(task : Json, context : Json) -> String {
  "MoonProj formal task " +
  native_text(task, "taskGuid") +
  " in project " +
  native_text(task, "projGuid") +
  ". Product: " +
  native_text(context, "product_id") +
  " (" +
  native_text(context, "product_name") +
  ").\n" +
  "Captured product direction (context): " +
  Json::string(native_text(context, "direction_excerpt")).stringify() +
  "\n" +
  "Read the captured task, current product philosophy, provenance, and PRD body from context_path: " +
  native_text(context, "context_path") +
  ". Expected SHA-256: " +
  native_text(context, "sha256") +
  "; UTF-8 bytes: " +
  native_field(context, "size_bytes").stringify() +
  ".\n" +
  "Capture coverage: " +
  native_text(context, "coverage") +
  "; limits: " +
  native_field(context, "issues").stringify() +
  ".\n" +
  "This is a staged input artifact inside the selected workspace, including for Review-only tasks. Read it with the native read tool in line ranges through its end; a path or snapshot alone is not evidence that you read it. The gateway verified staged bytes before dispatch; native read provides line counts and truncation metadata, not a hash. Never claim PRD coverage without successful reads through the relevant requirements and acceptance tests. If absent, conflicting, or incomplete, explain the exact limitation and proceed only where the task and available context suffice.\n" +
  "Use the captured current philosophy as product direction and the dated PRD as supporting requirements. Preserve the task's bounded intent and acceptance criteria. A review remains a review; PRD implementation vocabulary does not authorize source edits, extra milestones, new approval gates, or wider work. Produce the concrete requested result and evidence; execution completion remains separate from founder/customer acceptance.\n" +
  "Original task: " +
  native_text(task, "taskName") +
  "\nOriginal requirements and acceptance criteria:\n" +
  native_text(task, "remarks")
}

///|
fn native_context_availability(state : String, error : String) -> Json {
  { "state": state, "error": error }
}

///|
async fn native_inspect_context_artifact(execution : Json) -> Json {
  let context = native_field(execution, "product_context")
  if !(context is Object(_)) {
    return Json::null()
  }
  let workspace = native_text(execution, "workspace")
  let relative = native_text(context, "context_path")
  let path = contained_product_path(workspace, relative, false)
  let bytes = match path {
    Some(path) => native_context_read(path, 2 * 1024 * 1024)
    None => None
  }
  match bytes {
    Some(bytes) =>
      if native_context_hash(bytes) == native_text(context, "sha256") &&
        bytes.length() == native_context_int(context, "size_bytes") {
        native_context_availability("available", "")
      } else {
        native_context_availability(
          "conflict", "Existing context artifact differs from the reserved snapshot; it was not overwritten",
        )
      }
    None =>
      native_context_availability(
        "missing", "Captured context artifact is not currently readable",
      )
  }
}

///|
/// Called only with the execution returned by durable reservation. A competing
/// proposal cannot write input bytes. Retries never consult the current catalog.
async fn native_materialize_context(execution : Json) -> Json {
  let context = native_field(execution, "product_context")
  if !(context is Object(_)) {
    return Json::null()
  }
  let relative = native_text(context, "context_path")
  let bytes = @encoding/utf8.encode(native_text(context, "text"))
  if native_text(context, "schema") != "moonproj.product-context.v1" ||
    !@registry.valid_relative_path(relative) ||
    native_context_hash(bytes) != native_text(context, "sha256") ||
    bytes.length() != native_context_int(context, "size_bytes") {
    return native_context_availability(
      "unavailable", "Saved context snapshot has no valid immutable input bytes",
    )
  }
  try {
    let root = @fs.realpath(native_text(execution, "workspace"))
    let parts = relative.split("/").to_array()
    let mut parent = root
    for index = 0; index < parts.length() - 1; index = index + 1 {
      parent = parent + "/" + parts[index].to_owned()
      if !@fs.exists(parent) {
        @fs.mkdir(parent, permission=0o700) catch {
          error => if !@fs.exists(parent) { raise error }
        }
      }
      if @fs.realpath(parent) != parent ||
        @fs.kind(parent, follow_symlink=false) != @fs.Directory {
        return native_context_availability(
          "unavailable", "Context artifact parent is not a canonical workspace directory",
        )
      }
    }
    let path = root + "/" + relative
    if !@fs.exists(path) {
      @fs.write_file(
        path,
        bytes,
        create_mode=@fs.CreateNew,
        permission=0o600,
        sync=@fs.Full,
      ) catch {
        _ => () // A concurrent canonical writer is accepted only by the byte check below.
      }
    }
    native_inspect_context_artifact(execution)
  } catch {
    _ =>
      native_context_availability(
        "unavailable", "Captured context input could not be materialized in the selected workspace",
      )
  }
}

///|
fn native_reservation_body(task : Json, body : Json, execution : Json) -> Json {
  {
    "source_revision": native_field(task, "revision"),
    "authority": native_field(body, "authority"),
    "execution": execution,
  }
}

///|
fn native_reservation_fits(body : Json) -> Bool {
  @encoding/utf8.encode(body.stringify()).length() <= 128 * 1024
}

///|
async fn native_propose_execution(
  task : Json,
  resources : ProductResources,
  model : String,
  actor : String,
  book_guidance? : Json,
) -> Json noraise {
  // Untagged tasks retain their existing request and need no workspace writes.
  if native_text(task, "product_id").is_empty() {
    return native_execution_snapshot(task, model, actor, book_guidance?)
  }
  let context = native_capture_product_context(task, resources) catch {
    _ =>
      native_context_snapshot(
        task,
        "",
        "",
        Json::null(),
        "",
        Json::null(),
        "",
        "unavailable",
        ["Product context capture failed"],
      )
  }
  native_execution_snapshot(
    task,
    model,
    actor,
    product_context=context,
    book_guidance?,
  )
}
