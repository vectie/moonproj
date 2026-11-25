///|
fn delivery_test_task() -> Json {
  let fields = match native_test_task() {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields["delivery_mode"] = Json::string("coordinated")
  fields["delivery_limits"] = Json::string("Local draft only; no publishing")
  fields["parentTaskGuid"] = Json::string("G")
  Json::object(fields)
}

///|
async test "delivery preparation and immutable revision writes recover in existing directories" {
  let suite = @fs.tmpdir(prefix="moonproj-delivery-recovery-")
  defer (@fs.rmdir(suite, recursive=true) catch { _ => () })
  let root = suite + "/selected-book"
  @fs.mkdir(root)
  let task = continuation_test_field(
    delivery_test_task(),
    "execution_workspace",
    Json::string(root),
  )
  native_prepare_delivery_workspace(task)
  native_prepare_delivery_workspace(task)
  let book = native_delivery_workspace(task)
  let worker_one = native_delivery_workers_base(task) + "/specialist-1"
  assert_false(worker_one.has_prefix(book + "/"))
  assert_true(
    (@fs.kind(worker_one) catch { _ => @fs.FileKind::Regular }) is Directory,
  )
  native_delivery_write_once(
    book, ".moonsuite/products/moonproj/human-continuations/test/input.md", "Saved brief",
  )
  native_delivery_write_once(
    book, ".moonsuite/products/moonproj/human-continuations/test/submission.json",
    "{}",
  )
  native_delivery_write_once(
    book, ".moonsuite/products/moonproj/human-continuations/test/input.md", "Saved brief",
  )
  try
    native_delivery_write_once(
      book, ".moonsuite/products/moonproj/human-continuations/test/input.md", "Different brief",
    )
  catch {
    _ => ()
  } noraise {
    _ => assert_true(false)
  }
}

///|
async test "delivery rejects a feature-owned symlink before creating descendants" {
  let root = @fs.tmpdir(prefix="moonproj-delivery-scope-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/outside")
  @fs.symlink(target=root + "/outside", root + "/escape")
  try native_delivery_write_once(root, "escape/new/input.md", "text") catch {
    _ => ()
  } noraise {
    _ => assert_true(false)
  }
  let created = (@fs.kind(root + "/outside/new") catch {
      _ => @fs.FileKind::Regular
    })
    is Directory
  assert_false(created)
}

///|
test "valid native journals are not rejected after an arbitrary response size" {
  let body : Json = {
    "session_id": "S",
    "events": [{ "text": "x".repeat(2_000_001) }],
  }
  assert_eq(
    native_transport_fixture(
      body.stringify(),
      status=200,
      path="/v1/code/sessions/S/runtime-events?book_root=/book",
    ),
    body,
  )
}

///|
test "paused queue settlement has one stable native control identity per successor" {
  let execution : Json = { "session_id": "S", "workspace": "/book" }
  let request : Json = { "snapshot": { "command_id": "revision-1" } }
  let control = native_delivery_replacement_command(execution, request)
  assert_eq(native_text(control, "command"), "cancel")
  assert_eq(
    native_text(native_field(control, "packet"), "command_id"),
    "revision-1-replace-paused",
  )
  assert_eq(native_delivery_replacement_command(execution, request), control)
}

///|
test "coordinated delivery exposes actual worker tools in the captured native command" {
  let task = delivery_test_task()
  let run = native_execution_snapshot(task, "moongate/test", "founder")
  let command = @json.parse(native_text(run, "request_body"))
  assert_eq(native_text(run, "workspace"), "/tmp/selected-book")
  assert_eq(native_text(command, "book_root"), native_text(run, "workspace"))
  let tools = native_array(
    native_field(command, "payload"),
    "planner_allowed_tools",
  )
  assert_true(tools.contains(Json::string("spawn_workers")))
  assert_true(tools.contains(Json::string("wait_workers")))
  assert_true(native_text(command, "text").contains("no publishing"))
  assert_true(native_text(command, "text").contains("independent reviewer"))
  assert_true(
    native_text(command, "text").contains(
      ".moonproj-deliveries/PT-native/coordinator/",
    ),
  )
  let ordinary = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  assert_eq(native_text(ordinary, "workspace"), "/tmp/selected-book")
  assert_true(
    native_field(@json.parse(native_text(ordinary, "request_body")), "payload")
    is Null,
  )
}

///|
test "stop is confirmed only by the correct suspended runtime tree" {
  let run : Json = { "session_id": "S", "workspace": "/book" }
  let proof : Json = {
    "owner": "moonclaw",
    "action": "suspend",
    "session_id": "S",
    "suspended": true,
    "sessions": [
      { "session_id": "S", "book_root": "/book", "state": "suspended" },
      { "session_id": "worker", "state": "suspended" },
    ],
  }
  assert_true(native_delivery_suspension_matches(run, proof))
  assert_true(
    native_delivery_suspension_matches(
      run,
      continuation_test_field(proof, "sessions", [
        { "session_id": "S", "book_root": "/book", "state": "suspended" },
        { "session_id": "never-started", "state": "missing" },
      ]),
    ),
  )
  for
    (field, value) in [
      ("suspended", Json::boolean(false)),
      ("session_id", Json::string("other")),
      ("sessions", Json::array([])),
    ] {
    assert_false(
      native_delivery_suspension_matches(
        run,
        continuation_test_field(proof, field, value),
      ),
    )
  }
  assert_false(
    native_delivery_suspension_matches(
      run,
      continuation_test_field(proof, "sessions", [
        { "session_id": "S", "book_root": "/book", "state": "suspended" },
        { "session_id": "worker", "state": "running" },
      ]),
    ),
  )
}

///|
test "automatic report names one exact command and never accepts a task" {
  let task = delivery_test_task()
  let run : Json = {
    "command_id": "C",
    "summary": "Produced artifact with remaining gaps",
    "evidence_ids": ["E"],
  }
  let source : Json = {
    "type": "original",
    "original_run_id": "R",
    "command_id": "C",
  }
  let body = native_delivery_report_body(task, run, source, "2026-11-24")
  assert_eq(native_text(body, "report_id"), "DELIVERY-C")
  assert_eq(native_text(body, "task_id"), "PT-native")
  assert_eq(native_field(body, "delivery_source"), source)
  assert_true(native_field(body, "status") is Null)
  assert_true(native_field(body, "objective_result") is Null)
}

///|
test "delivery revision reuses exact continuation format without changing C0" {
  let task = delivery_test_task()
  let original = native_execution_snapshot(task, "moongate/test", "founder")
  let current = continuation_test_field(task, "execution", original)
  let request : Json = {
    "key": "revision-1",
    "instruction": "Clarify buyer setup instructions",
    "prior_command_id": native_text(original, "command_id"),
    "prior_summary": "First delivery",
  }
  let c0 = @json.parse(native_text(original, "request_body"))
  let public_task = continuation_test_field(
    current,
    "execution",
    continuation_test_field(original, "request_body", Json::null()),
  )
  let snapshot = native_delivery_revision_snapshot(public_task, request, c0)
  assert_eq(
    native_delivery_revision_snapshot(public_task, request, c0),
    snapshot,
  )
  let command = @json.parse(native_text(snapshot, "request_body"))
  assert_true(
    native_text(command, "text").contains(
      "Omit each worker's optional model field",
    ),
  )
  native_continuation_validate_snapshot(
    original,
    command,
    c0,
    snapshot,
    @encoding/utf8.encode(native_text(snapshot, "input_text")),
  )
  assert_eq(native_text(command, "model"), "moongate/test")
  assert_true(native_text(snapshot, "input_text").contains("First delivery"))
  assert_eq(
    native_text(original, "command_id"),
    native_text(native_field(current, "execution"), "command_id"),
  )
}
