///|
fn continuation_test_field(value : Json, name : String, field : Json) -> Json {
  let fields = match value {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields[name] = field
  Json::object(fields)
}

///|
fn continuation_test_fixture(
  root? : String = "/tmp/continuation-test",
  original_status? : String = "runtime-completed",
  status? : String = "runtime-completed",
) -> (Json, Json, Json, Json, Json, Json, Bytes) {
  let original : Json = {
    "run_id": "R",
    "task_id": "T",
    "session_id": "S",
    "command_id": "C0",
    "workspace": root,
    "model": "moongate/captured",
    "state": "completed",
    "request_body": "UNCHANGED-C0-BYTES",
    "receipt": { "id": "original-receipt" },
  }
  let task : Json = {
    "taskGuid": "T",
    "projGuid": "P",
    "status": "doing",
    "execution": original,
    "continuations": [],
    "taskName": "changed current title",
    "execution_model": "moongate/unrelated",
    "execution_workspace": "/another/current/workspace",
  }
  let instruction = "Revise the selected result.\nKeep this exact human text."
  let input_text = instruction +
    "\n\nHistorical original requirements\nOriginal captured task.\nPrior result C0.\n"
  let input = @encoding/utf8.encode(input_text)
  let input_ref : Json = {
    "path": native_continuation_directory("K1") + "/input.md",
    "sha256": native_context_hash(input),
  }
  let lineage : Json = {
    "schema": "moonproj.work-continuation.v1",
    "continuation_id": "K1",
    "task_id": "T",
    "run_id": "R",
    "original_command_id": "C0",
    "prior_result_command_id": "C0",
    "input": input_ref,
  }
  let c0 : Json = {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": "S",
    "book_root": root,
    "model": "moongate/captured",
    "text": "Original captured task.",
    "packet": { "command_id": "C0" },
  }
  let c1 : Json = {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": "S",
    "book_root": root,
    "model": "moongate/captured",
    "text": instruction,
    "context_path": native_text(input_ref, "path"),
    "web_search": false,
    "packet": { "command_id": "C1", "client_turn_id": "U1" },
    "payload": { "moonproj_continuation": lineage },
    "runtime_tool_calls": [],
  }
  let c2 = continuation_test_field(
    continuation_test_field(c0, "packet", {
      "command_id": "C2",
      "client_turn_id": "U2",
    }),
    "text",
    "Later unrelated chat".to_json(),
  )
  let receipt = fn(id : String, state : String, answer : String) -> Json {
    {
      "id": "receipt-" + id,
      "session_id": "S",
      "command_id": id,
      "status": state,
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "accepted": true,
            "result": { "metadata": { "answer": answer } },
          },
        ],
      },
    }
  }
  let item = fn(command : Json, state : String, answer : String) -> Json {
    let id = native_text(native_field(command, "packet"), "command_id")
    {
      "command_id": id,
      "session_id": "S",
      "action": "prompt",
      "claim_status": "delivered",
      "command": command,
      "receipt": receipt(id, state, answer),
    }
  }
  let claims : Json = {
    "kind": "mooncode-runtime-claim-state",
    "protocol": "mooncode.v1",
    "session_id": "S",
    "book_root": root,
    "claimable_commands": [],
    "claimed_commands": [],
    "order_blocked_commands": [],
    "invalid_commands": [],
    "delivered_commands": [
      item(c0, original_status, "ORIGINAL"),
      item(c1, status, "CHOSEN C1"),
      item(c2, "runtime-completed", "UNRELATED C2"),
    ],
  }
  let events : Json = {
    "session_id": "S",
    "book_root": root,
    "events": [
      {
        "id": "C1-artifact",
        "session_id": "S",
        "command_id": "C1",
        "event": "tool_result",
        "tool": "write",
        "tool_result": { "ok": true },
        "path": "result/c1.md",
      },
      {
        "id": "C2-artifact",
        "session_id": "S",
        "command_id": "C2",
        "event": "tool_result",
        "tool": "write",
        "tool_result": { "ok": true },
        "path": "result/c2.md",
      },
    ],
  }
  let service : Json = {
    "session_id": "S",
    "book_root": root,
    "status": "idle",
  }
  let body = c1.stringify()
  let snapshot : Json = {
    "schema": "moondesk.work-continuation-snapshot.v1",
    "continuation_id": "K1",
    "client_turn_id": "U1",
    "command_id": "C1",
    "source": {
      "task_id": "T",
      "run_id": "R",
      "session_id": "S",
      "original_command_id": "C0",
      "book_root": root,
    },
    "prior_result_command_id": "C0",
    "instruction": instruction,
    "model": "moongate/captured",
    "original_context": { "path": "", "sha256": "" },
    "prior_result": {
      "command_id": "C0",
      "state": "completed",
      "receipt": receipt("C0", original_status, "ORIGINAL"),
    },
    "input": input_ref,
    "input_text": input_text,
    "request_body": body,
    "request_sha256": native_context_hash(@encoding/utf8.encode(body)),
  }
  (task, claims, events, service, snapshot, c1, input)
}

///|
test "continuation routes and input keys cannot escape the exact task or workspace" {
  assert_eq(
    native_continuation_task_id("/api/company/tasks/T/continuations", false),
    Some("T"),
  )
  assert_eq(
    native_continuation_task_id("/api/company/plan/tasks/T/continuations", true),
    Some("T"),
  )
  assert_eq(
    native_continuation_task_id(
      "/api/company/tasks/T/latest/continuations", false,
    ),
    None,
  )
  assert_eq(
    native_continuation_task_id("/api/company/tasks/T/continuations", true),
    None,
  )
  for key in ["../K", ".", "..", "K/a", "K%2fa", "", "K:other"] {
    assert_false(native_continuation_key(key))
  }
  assert_true(native_continuation_key("K_1-2"))
  assert_eq(native_continuation_root("/book///"), "/book")
  assert_eq(native_continuation_root("//book/../book//."), "/book")
}

///|
test "completed failed and cancelled original commands retain bytes and yield separate C1" {
  for state in ["runtime-completed", "runtime-failed", "runtime-cancelled"] {
    let (task, claims, events, service, snapshot, c1, input) = continuation_test_fixture(
      original_status=state,
    )
    let before = task.stringify()
    let original = native_continuation_original(task, "T")
    let c0 = native_field(
      native_continuation_claim(original, claims, "C0"),
      "command",
    )
    native_continuation_validate_snapshot(original, c1, c0, snapshot, input)
    let candidate = native_continuation_readback(
      original, c1, claims, events, service,
    )
    assert_eq(native_text(candidate, "command_id"), "C1")
    assert_eq(native_text(candidate, "original_command_id"), "C0")
    assert_eq(native_text(candidate, "summary"), "CHOSEN C1")
    assert_eq(native_text(candidate, "workspace"), "/tmp/continuation-test")
    assert_eq(native_text(candidate, "model"), "moongate/captured")
    assert_eq(native_array(candidate, "artifact_refs").length(), 1)
    assert_eq(
      native_text(native_array(candidate, "artifact_refs")[0], "path"),
      "result/c1.md",
    )
    assert_false(
      native_array(candidate, "evidence_ids").contains("C2-artifact".to_json()),
    )
    assert_eq(task.stringify(), before)
  }
}

///|
test "snapshot reload preserves exact instruction and detects changed bytes or native request" {
  let (task, claims, _, _, snapshot, c1, input) = continuation_test_fixture()
  let original = native_field(task, "execution")
  let c0 = native_field(
    native_continuation_claim(original, claims, "C0"),
    "command",
  )
  let loaded = @json.parse(snapshot.stringify())
  native_continuation_validate_snapshot(original, c1, c0, loaded, input)
  assert_eq(native_text(loaded, "request_body"), c1.stringify())
  for
    changed in [
      continuation_test_field(
        loaded,
        "instruction",
        "different human input".to_json(),
      ),
      continuation_test_field(loaded, "request_body", "{}".to_json()),
      continuation_test_field(
        loaded,
        "input_text",
        "modified requirements".to_json(),
      ),
      continuation_test_field(loaded, "prior_result_command_id", "C2".to_json()),
      continuation_test_field(loaded, "original_context", {
        "path": "today/catalog/context.md",
      }),
    ] {
    try
      native_continuation_validate_snapshot(original, c1, c0, changed, input)
    catch {
      error => assert_eq(native_continuation_error(error).0, 409)
    } noraise {
      _ => assert_true(false, msg="changed immutable snapshot must fail")
    }
  }
  try
    native_continuation_validate_snapshot(
      original, c1, c0, loaded, b"different input bytes",
    )
  catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => assert_true(false, msg="changed input file must fail")
  }
}

///|
test "unrelated C2 controls and executable-state imports are rejected" {
  let (task, claims, events, service, _, c1, _) = continuation_test_fixture()
  let original = native_field(task, "execution")
  let c2 = native_field(
    native_continuation_claim(original, claims, "C2"),
    "command",
  )
  try
    native_continuation_readback(original, c2, claims, events, service)
  catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => assert_true(false, msg="latest unrelated C2 is not a candidate")
  }
  for
    key in [
      "horizon_id", "horizon_checkpoint", "next_action", "approval_state", "execution_plan",
      "planner_continuation",
    ] {
    try
      native_continuation_lineage(
        original,
        continuation_test_field(c1, key, "copied".to_json()),
      )
    catch {
      NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
    } noraise {
      _ => assert_true(false, msg="copied executable state must fail")
    }
  }
  let altered = continuation_test_field(c1, "runtime_tool_calls", [
    { "tool": "finish" },
  ])
  try native_continuation_lineage(original, altered) catch {
    NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
  } noraise {
    _ => assert_true(false, msg="prebuilt tool plan must fail")
  }
  let payload = continuation_test_field(
    native_field(c1, "payload"),
    "task_contract",
    { "horizon_id": "C0", "milestones": [{ "state": "done" }] },
  )
  try
    native_continuation_lineage(
      original,
      continuation_test_field(c1, "payload", payload),
    )
  catch {
    NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
  } noraise {
    _ => assert_true(false, msg="nested original horizon contract must fail")
  }
  let delivered = native_array(claims, "delivered_commands").copy()
  delivered[1] = continuation_test_field(
    delivered[1],
    "action",
    "steer".to_json(),
  )
  try
    native_continuation_claim(
      original,
      continuation_test_field(claims, "delivered_commands", delivered.to_json()),
      "C1",
    )
  catch {
    NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
  } noraise {
    _ => assert_true(false, msg="control receipt is not deliverable")
  }
}

///|
test "candidate lineage rejects wrong run workspace session receipt and selected prior" {
  let (task, claims, _, _, _, c1, _) = continuation_test_fixture()
  let original = native_field(task, "execution")
  for
    changed in [
      continuation_test_field(claims, "session_id", "other".to_json()),
      continuation_test_field(claims, "book_root", "/another/book".to_json()),
    ] {
    try native_continuation_claim(original, changed, "C1") catch {
      NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
    } noraise {
      _ => assert_true(false, msg="wrong source must fail")
    }
  }
  let lineage = native_field(
    native_field(c1, "payload"),
    "moonproj_continuation",
  )
  for key in ["task_id", "run_id", "original_command_id", "continuation_id"] {
    let changed = continuation_test_field(c1, "payload", {
      "moonproj_continuation": continuation_test_field(
        lineage,
        key,
        "../different".to_json(),
      ),
    })
    try native_continuation_lineage(original, changed) catch {
      NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
    } noraise {
      _ => assert_true(false, msg="tampered lineage must fail")
    }
  }
  try
    native_continuation_validate_prior(
      original,
      claims,
      continuation_test_field(
        lineage,
        "prior_result_command_id",
        "C2".to_json(),
      ),
    )
  catch {
    NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
  } noraise {
    _ => assert_true(false, msg="unrelated selected prior must fail")
  }
}

///|
async test "candidate listing is read-only and exact requested identity wins over newer C2" {
  let (task, claims, events, service, snapshot, c1, input) = continuation_test_fixture()
  let original = native_field(task, "execution")
  let reads : Array[String] = []
  let read = async fn(path : String) -> Json {
    reads.push(path)
    if path.contains("runtime-claim?") {
      claims
    } else if path.contains("runtime-events?") {
      events
    } else {
      service
    }
  }
  let inspect = async fn(command : Json, c0 : Json) -> Json {
    assert_eq(command, c1)
    native_continuation_validate_snapshot(
      original, command, c0, snapshot, input,
    )
    snapshot
  }
  let exact = native_continuation_listing(task, "T", "C1", read, inspect)
  assert_eq(
    native_text(native_field(exact, "candidate"), "summary"),
    "CHOSEN C1",
  )
  assert_eq(reads.length(), 3)
  assert_true(
    reads.all(path => path.has_prefix("/v1/code/sessions/S/runtime-")),
  )
  let listed = native_continuation_listing(task, "T", "", read, inspect)
  assert_eq(native_field(listed, "candidate"), Json::null())
  assert_eq(native_array(listed, "candidates").length(), 1)
  assert_eq(native_field(listed, "selected_delivery_source"), Json::null())
  try native_continuation_listing(task, "T", "missing", read, inspect) catch {
    error => assert_eq(native_continuation_error(error).0, 404)
  } noraise {
    _ => assert_true(false, msg="missing candidate must remain exact")
  }
}

///|
test "import discards browser evidence and preserves exact selected result source" {
  let (task, claims, events, service, _, c1, _) = continuation_test_fixture()
  let original = native_field(task, "execution")
  let candidate = native_continuation_readback(
    original, c1, claims, events, service,
  )
  let requested : Json = {
    "original_run_id": "R",
    "continuation_id": "K1",
    "command_id": "C1",
    "select_for_delivery": true,
    "authority": { "actor_id": "founder" },
    "summary": "FORGED",
    "receipt": { "status": "runtime-completed" },
    "workspace": "/wrong",
  }
  let forwarded = native_continuation_import_body(
    original, requested, candidate,
  )
  assert_eq(native_field(forwarded, "continuation"), candidate)
  assert_eq(
    native_text(native_field(forwarded, "continuation"), "summary"),
    "CHOSEN C1",
  )
  assert_eq(native_field(forwarded, "receipt"), Json::null())
  for key in ["original_run_id", "continuation_id", "command_id"] {
    try
      native_continuation_import_body(
        original,
        continuation_test_field(requested, key, "other".to_json()),
        candidate,
      )
    catch {
      NativeContinuationError::Rejected(status, _) => assert_eq(status, 409)
    } noraise {
      _ => assert_true(false, msg="tampered return hint must fail")
    }
  }
  let original_selection : Json = {
    "original_run_id": "R",
    "select_for_delivery": true,
    "selected_delivery_source": {
      "type": "original",
      "original_run_id": "R",
      "command_id": "C0",
    },
    "authority": { "actor_id": "founder" },
  }
  let selected = native_continuation_import_body(
    original,
    original_selection,
    Json::null(),
  )
  assert_eq(
    native_text(
      native_field(selected, "selected_delivery_source"),
      "command_id",
    ),
    "C0",
  )
  assert_eq(native_field(selected, "continuation"), Json::null())
}

///|
test "continuation command normalization preserves gateway idempotency precedence" {
  let request : @http.Request = {
    meth: @http.Post,
    path: "/api/company/plan/tasks/T/continuations?idempotency_key=query",
    headers: { "Idempotency-Key": "header" },
  }
  let (body, key) = normalized_command_body(
    b"{\"idempotency_key\":\"body\",\"command_id\":\"C1\"}", request, true,
  )
  assert_eq(key, Some("body"))
  assert_eq(
    native_field(@json.parse(@encoding/utf8.decode(body)), "idempotency_key"),
    Json::null(),
  )
  assert_eq(normalized_command_body(b"{}", request, true).1, Some("header"))
}

///|
async test "canonical input storage is required and corruption cannot be attached" {
  let root = @fs.tmpdir(prefix="moonproj-continuation-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let (task, claims, _, _, snapshot, c1, input) = continuation_test_fixture(
    root~,
  )
  let original = native_field(task, "execution")
  let c0 = native_field(
    native_continuation_claim(original, claims, "C0"),
    "command",
  )
  let directory = root + "/" + native_continuation_directory("K1")
  @fs.mkdir(directory, recursive=true)
  @fs.write_file(
    directory + "/submission.json",
    snapshot.stringify(),
    create_mode=CreateNew,
  )
  try native_continuation_snapshot(original, c1, c0) catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ =>
      assert_true(
        false,
        msg="native acceptance without persisted input must fail",
      )
  }
  @fs.write_file(directory + "/input.md", input, create_mode=CreateNew)
  assert_eq(native_continuation_snapshot(original, c1, c0), snapshot)
  @fs.write_file(
    directory + "/input.md",
    "changed after capture",
    create_mode=TruncateExisting,
  )
  try native_continuation_snapshot(original, c1, c0) catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => assert_true(false, msg="changed context must fail")
  }
}

///|
test "follow up destination mode is explicit and accepted work stays inspection only" {
  let (task, _, _, _, _, _, _) = continuation_test_fixture()
  let ordinary = desk_handoff_projection(task, "https://desk.example")
  assert_eq(native_text(ordinary, "mode"), "inspect")
  assert_eq(
    native_text(
      desk_handoff_projection(
        task,
        "https://desk.example",
        requested_mode="follow_up",
      ),
      "mode",
    ),
    "follow_up",
  )
  let accepted = continuation_test_field(task, "status", "done".to_json())
  assert_eq(
    native_text(
      desk_handoff_projection(
        accepted,
        "https://desk.example",
        requested_mode="follow_up",
      ),
      "mode",
    ),
    "inspect",
  )
  assert_true(
    native_bool(
      native_continuation_envelope(accepted, Json::null(), [], "ready", ""),
      "inspection_only",
    ),
  )
}

///|
async test "oversized canonical observation reports the existing byte limit without service I O" {
  let summary = "界".repeat(50000)
  let candidate : Json = {
    "continuation_id": "K1",
    "command_id": "C1",
    "summary": summary,
  }
  let body : Json = {
    "continuation": candidate,
    "select_for_delivery": true,
    "authority": {},
  }
  let bridge : NativeBridge = {
    service_uri: "invalid-no-transport",
    service_token: "",
    actor_signing_secret: "",
    actor: "founder",
  }
  assert_true(body.stringify().length() < MAX_BODY_BYTES)
  assert_true(@encoding/utf8.encode(body.stringify()).length() > MAX_BODY_BYTES)
  let response = native_continuation_observe(bridge, "T", body, "operation-key")
  assert_eq(response.status, 413)
  let result = native_result_json(response)
  assert_eq(native_text(result, "candidate_state"), "attachment_too_large")
  assert_eq(native_field(result, "candidate"), candidate)
}

///|
async test "captured workspace root aliases work while descendant input aliases are rejected" {
  let root = @fs.tmpdir(prefix="moonproj-continuation-alias-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/physical")
  @fs.write_file(
    root + "/physical/input.md",
    "captured bytes",
    create_mode=CreateNew,
  )
  @fs.symlink(target=root + "/physical", root + "/alias")
  assert_eq(
    native_continuation_read_file(root + "/alias", "input.md", 100),
    b"captured bytes",
  )
  @fs.symlink(target=root + "/physical/input.md", root + "/physical/linked.md")
  try native_continuation_read_file(root + "/alias", "linked.md", 100) catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ =>
      assert_true(
        false,
        msg="descendant aliases cannot replace captured input identity",
      )
  }
}

///|
async test "actual Desk producer snapshot crosses gateway filesystem validation unchanged when configured" {
  let directory = @env.get_env_var("MOONPROJ_CONTINUATION_FIXTURE_OUTPUT").unwrap_or(
    "",
  )
  if directory.is_empty() {
    return
  }
  let fixture = @json.parse(@fs.read_file(directory + "/fixture.json").text())
  let claims = @json.parse(@fs.read_file(directory + "/claims.json").text())
  let events = @json.parse(@fs.read_file(directory + "/events.json").text())
  let service = @json.parse(@fs.read_file(directory + "/service.json").text())
  let root = native_text(fixture, "book_root")
  let snapshot = @json.parse(
    @fs.read_file(root + "/" + native_text(fixture, "submission_path")).text(),
  )
  let original_context = native_field(snapshot, "original_context")
  let original : Json = {
    "task_id": native_text(fixture, "task_id"),
    "run_id": native_text(fixture, "run_id"),
    "session_id": native_text(fixture, "session_id"),
    "command_id": native_text(fixture, "original_command_id"),
    "workspace": root,
    "model": native_text(snapshot, "model"),
    "product_context": {
      "context_path": native_text(original_context, "path"),
      "sha256": native_text(original_context, "sha256"),
    },
  }
  let task : Json = {
    "taskGuid": native_text(fixture, "task_id"),
    "projGuid": "P",
    "status": "doing",
    "execution": original,
    "continuations": [],
  }
  let listing = native_continuation_listing(
    task,
    native_text(fixture, "task_id"),
    native_text(fixture, "command_id"),
    path => {
      if path.contains("runtime-claim?") {
        claims
      } else if path.contains("runtime-events?") {
        events
      } else {
        service
      }
    },
    (command, c0) => native_continuation_snapshot(original, command, c0),
  )
  let candidate = native_field(listing, "candidate")
  let desk = @json.parse(
    @fs.read_file(directory + "/continuation-response.json").text(),
  )
  assert_eq(
    native_text(candidate, "command_id"),
    native_text(desk, "command_id"),
  )
  assert_eq(native_text(candidate, "summary"), native_text(desk, "summary"))
  assert_eq(native_text(candidate, "state"), "completed")
  assert_eq(native_field(candidate, "input"), native_field(desk, "input"))
  assert_eq(
    native_text(snapshot, "request_body"),
    @fs.read_file(directory + "/accepted-command.json").text(),
  )
  let exported : Json = {
    "task": task,
    "candidate": candidate,
    "native_io": "injected",
    "provider_called": false,
  }
  @fs.write_file(
    directory + "/gateway-candidate.json",
    exported.stringify(),
    create_mode=CreateOrTruncate,
  )
}
