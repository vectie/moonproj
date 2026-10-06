///|
fn native_context_test_task(product : String, workspace : String) -> Json {
  let fields = match native_test_task() {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields.set("product_id", Json::string(product))
  fields.set("execution_workspace", Json::string(workspace))
  Json::object(fields)
}

///|
fn native_context_test_resources() -> ProductResources {
  {
    catalog_path: "config/moonsuite-engineering.json",
    document_root: "resources/product-documents",
    workspace_root: "..",
  }
}

///|
async test "all twenty real PRDs fit the serialized reservation and preserve exact full text" {
  let resources = native_context_test_resources()
  let catalog = read_product_catalog(resources)
  let mut largest = 0
  for product in catalog.products {
    let task = native_context_test_task(product.id, "/tmp/selected-book")
    let context = native_capture_product_context(task, resources)
    assert_eq(native_text(context, "coverage"), "complete")
    let prd = native_field(context, "prd")
    let bytes = @fs.read_file(
      resources.document_root + "/" + native_text(prd, "text_path"),
    ).binary()
    assert_eq(native_context_int(prd, "text_size_bytes"), bytes.length())
    assert_eq(native_text(prd, "text_sha256"), native_context_hash(bytes))
    assert_true(
      native_text(context, "text").contains(@encoding/utf8.decode(bytes)),
    )
    assert_true(bytes.length() > 12000)
    let run = native_propose_execution(
      task, resources, "moongate/test", "founder",
    )
    let request = @json.parse(native_text(run, "request_body"))
    assert_true(native_text(request, "text").length() < 4000)
    assert_eq(
      native_text(request, "context_path"),
      native_text(context, "context_path"),
    )
    let envelope = native_reservation_body(
      task,
      { "authority": { "actor": "founder", "reason": "authorized task" } },
      run,
    )
    let size = @encoding/utf8.encode(envelope.stringify()).length()
    largest = largest.max(size)
    assert_true(native_reservation_fits(envelope))
  }
  println(
    "Product context actual twenty-document maximum reservation bytes: " +
    largest.to_string(),
  )
}

///|
test "reservation byte boundary is exact and never truncates Unicode or escaped requirements" {
  let run = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  let exact = native_reservation_body(
    native_test_task(),
    { "authority": { "reason": "" } },
    run,
  )
  let overhead = @encoding/utf8.encode(exact.stringify()).length()
  let authority = native_field(exact, "authority")
  if authority is Object(fields) {
    fields.set("reason", Json::string("a".repeat(128 * 1024 - overhead)))
  }
  assert_eq(@encoding/utf8.encode(exact.stringify()).length(), 128 * 1024)
  assert_true(native_reservation_fits(exact))
  if authority is Object(fields) {
    fields.set("reason", Json::string("a".repeat(128 * 1024 - overhead + 1)))
  }
  assert_false(native_reservation_fits(exact))
  assert_false(native_reservation_fits({ "x": "界\n\"".repeat(30000) }))
}

///|
async test "two product tags in one company project capture different philosophy and PRD" {
  let resources = native_context_test_resources()
  let first = native_propose_execution(
    native_context_test_task("moonproj", "/tmp/book"),
    resources,
    "moongate/test",
    "founder",
  )
  let second = native_propose_execution(
    native_context_test_task("moonbook", "/tmp/book"),
    resources,
    "moongate/test",
    "founder",
  )
  let one = native_field(first, "product_context")
  let two = native_field(second, "product_context")
  assert_eq(native_text(first, "run_id"), native_text(second, "run_id"))
  assert_true(native_text(one, "text").contains("Top-down management"))
  assert_true(native_text(two, "text").contains("Experienced agent and memory"))
  assert_false(native_text(one, "sha256") == native_text(two, "sha256"))
  assert_false(
    native_text(native_field(one, "prd"), "source_sha256") ==
    native_text(native_field(two, "prd"), "source_sha256"),
  )
}

///|
async test "canonical reservation alone stages bytes and replay restores saved text after catalog edit and retag" {
  let root = @fs.tmpdir(prefix="moonproj-context-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let resources = native_context_test_resources()
  let winning = native_propose_execution(
    native_context_test_task("moonproj", root),
    resources,
    "moongate/test",
    "founder",
  )
  let losing = native_propose_execution(
    native_context_test_task("moonbook", root),
    resources,
    "moongate/other",
    "founder",
  )
  let reserved = @json.parse(winning.stringify())
  let context = native_field(reserved, "product_context")
  let losing_path = root +
    "/" +
    native_text(native_field(losing, "product_context"), "context_path")
  let path = root + "/" + native_text(context, "context_path")
  // Both callers receive the winning execution from reserve, regardless of proposal.
  assert_eq(
    native_text(native_materialize_context(reserved), "state"),
    "available",
  )
  assert_eq(
    native_text(native_materialize_context(reserved), "state"),
    "available",
  )
  assert_false(@fs.exists(losing_path))
  let request_bytes = native_text(reserved, "request_body")
  let before = @fs.read_file(path).text()
  assert_eq(before, native_text(context, "text"))
  @fs.remove(path)
  assert_eq(
    native_text(native_inspect_context_artifact(reserved), "state"),
    "missing",
  )
  // A changed/current tag/catalog is deliberately not an input to replay.
  let edited_resources : ProductResources = {
    ..resources,
    catalog_path: root + "/missing-edited-catalog.json",
  }
  let retagged = native_propose_execution(
    native_context_test_task("moonbook", root),
    edited_resources,
    "moongate/changed",
    "founder",
  )
  assert_eq(
    native_text(native_field(retagged, "product_context"), "coverage"),
    "unavailable",
  )
  assert_eq(
    native_text(native_materialize_context(reserved), "state"),
    "available",
  )
  assert_eq(@fs.read_file(path).text(), before)
  assert_eq(native_text(reserved, "request_body"), request_bytes)
  assert_eq(native_text(context, "coverage"), "complete")
  @fs.write_file(
    path,
    "wrong product requirements",
    create_mode=@fs.CreateOrTruncate,
  )
  assert_eq(
    native_text(native_materialize_context(reserved), "state"),
    "conflict",
  )
  assert_eq(@fs.read_file(path).text(), "wrong product requirements")
  assert_eq(native_text(reserved, "request_body"), request_bytes)
}

///|
async test "legacy and untagged review need no input artifact even in an unwritable workspace" {
  let root = @fs.tmpdir(prefix="moonproj-untagged-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.chmod(root, 0o500)
  defer (@fs.chmod(root, 0o700) catch { _ => () })
  let task = native_context_test_task("", root)
  let run = native_propose_execution(
    task,
    native_context_test_resources(),
    "moongate/test",
    "founder",
  )
  assert_eq(run, native_execution_snapshot(task, "moongate/test", "founder"))
  assert_eq(native_field(run, "product_context"), Json::null())
  assert_eq(native_materialize_context(run), Json::null())
  assert_eq(native_inspect_context_artifact(run), Json::null())
  assert_eq(@fs.readdir(root, include_hidden=true).length(), 0)
}

///|
async test "tagged input failure reports availability separately without altering captured completeness or request" {
  let root = @fs.tmpdir(prefix="moonproj-unavailable-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let run = native_propose_execution(
    native_context_test_task("moonproj", root),
    native_context_test_resources(),
    "moongate/test",
    "founder",
  )
  let saved = run.stringify()
  // A regular file in place of an artifact parent is an actual input IO failure.
  @fs.write_file(
    root + "/.moonsuite",
    "existing workspace content",
    create_mode=@fs.CreateNew,
  )
  let availability = native_materialize_context(run)
  assert_eq(native_text(availability, "state"), "unavailable")
  assert_false(native_text(availability, "error").is_empty())
  assert_eq(
    native_text(native_field(run, "product_context"), "coverage"),
    "complete",
  )
  assert_eq(run.stringify(), saved)
  assert_eq(
    @fs.read_file(root + "/.moonsuite").text(),
    "existing workspace content",
  )
}

///|
async test "unknown missing stale and unsupported context remain explicit partial inputs" {
  let root = @fs.tmpdir(prefix="moonproj-partial-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let resources = native_context_test_resources()
  let unknown = native_propose_execution(
    native_context_test_task("unknown-product", root),
    resources,
    "moongate/test",
    "founder",
  )
  assert_eq(
    native_text(native_field(unknown, "product_context"), "coverage"),
    "unavailable",
  )
  assert_eq(
    native_text(native_materialize_context(unknown), "state"),
    "available",
  )
  let missing : ProductResources = { ..resources, document_root: root, }
  let partial = native_propose_execution(
    native_context_test_task("moonproj", root),
    missing,
    "moongate/test",
    "founder",
  )
  assert_eq(
    native_text(native_field(partial, "product_context"), "coverage"),
    "partial",
  )
  assert_eq(
    native_text(native_materialize_context(partial), "state"),
    "available",
  )
  let manifest = @json.parse(
    @fs.read_file(resources.document_root + "/manifest.json").text(),
  )
  let asset = native_array(manifest, "assets")[0]
  let extraction = native_field(asset, "text_extraction")
  @fs.write_file(
    root + "/MoonProj_PRD.docx",
    @fs.read_file(resources.document_root + "/MoonProj_PRD.docx"),
    create_mode=@fs.CreateNew,
  )
  @fs.mkdir(root + "/text")
  @fs.write_file(
    root + "/text/MoonProj_PRD.txt",
    "stale text",
    create_mode=@fs.CreateNew,
  )
  @fs.write_file(
    root + "/manifest.json",
    manifest.stringify(),
    create_mode=@fs.CreateNew,
  )
  let stale = native_capture_product_context(
    native_context_test_task("moonproj", root),
    missing,
  )
  assert_eq(native_text(stale, "coverage"), "partial")
  assert_true(
    native_field(stale, "issues").stringify().contains("text identity mismatch"),
  )
  if extraction is Object(fields) {
    fields.set("extraction_version", Json::string("future-unsupported"))
  }
  @fs.write_file(
    root + "/manifest.json",
    manifest.stringify(),
    create_mode=@fs.CreateOrTruncate,
  )
  let unsupported = native_capture_product_context(
    native_context_test_task("moonproj", root),
    missing,
  )
  assert_true(
    native_field(unsupported, "issues").stringify().contains("unsupported"),
  )
  if extraction is Object(fields) {
    fields.set("extraction_version", Json::string("docx-body-v1"))
  }
  @fs.write_file(
    root + "/manifest.json",
    manifest.stringify(),
    create_mode=@fs.CreateOrTruncate,
  )
  @fs.write_file(
    root + "/MoonProj_PRD.docx",
    "changed source",
    create_mode=@fs.CreateOrTruncate,
  )
  let stale_source = native_capture_product_context(
    native_context_test_task("moonproj", root),
    missing,
  )
  assert_true(
    native_field(stale_source, "issues")
    .stringify()
    .contains("source identity mismatch"),
  )
}

///|
async test "tagged review stages only input and emits real producer fixtures when requested" {
  let configured = @env.get_env_var("MOONPROJ_CONTEXT_FIXTURE_OUTPUT").unwrap_or(
    "",
  )
  let root = if configured.is_empty() {
    @fs.tmpdir(prefix="moonproj-producer-")
  } else {
    configured
  }
  defer (if configured.is_empty() {
    @fs.rmdir(root, recursive=true) catch {
      _ => ()
    }
  })
  if !@fs.exists(root) {
    @fs.mkdir(root, recursive=true)
  }
  for intent in ["review", "implement", "untagged", "unknown"] {
    let product = if intent == "untagged" {
      ""
    } else if intent == "unknown" {
      "unknown-product"
    } else {
      "moonproj"
    }
    let task = native_context_test_task(product, root)
    if task is Object(fields) {
      fields.set(
        "taskName",
        Json::string(
          if intent != "implement" {
            "Review the proposal without editing files"
          } else {
            "Implement the requested product behavior"
          },
        ),
      )
      fields.set(
        "remarks",
        Json::string(
          if intent != "implement" {
            "Give a useful review and evidence"
          } else {
            "Fix the behavior and run its tests"
          },
        ),
      )
    }
    let run = native_propose_execution(
      task,
      native_context_test_resources(),
      "moongate/test",
      "founder",
    )
    let context = native_field(run, "product_context")
    let availability = native_materialize_context(run)
    if intent == "untagged" {
      assert_eq(availability, Json::null())
    } else {
      assert_eq(native_text(availability, "state"), "available")
    }
    let request = @json.parse(native_text(run, "request_body"))
    if intent != "untagged" {
      assert_true(
        native_text(request, "text").contains("gateway verified staged bytes"),
      )
      assert_true(
        native_text(request, "text").contains("inside the selected workspace"),
      )
      assert_true(
        native_text(request, "text").contains("A review remains a review"),
      )
    }
    if intent == "review" || intent == "implement" {
      assert_true(native_text(context, "text").length() > 12000)
    }
    assert_eq(native_field(request, "execution_plan"), Json::null())
    if !configured.is_empty() {
      @fs.write_file(
        root + "/" + intent + "-request.json",
        native_text(run, "request_body"),
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        root + "/" + intent + "-execution.json",
        run.stringify(),
        create_mode=@fs.CreateOrTruncate,
      )
    }
  }
}
