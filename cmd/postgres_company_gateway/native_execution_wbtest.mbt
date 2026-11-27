///|
fn native_test_task() -> Json {
  {
    "taskGuid": "PT-native",
    "projGuid": "company-project",
    "taskName": "Review the proposal without editing files",
    "remarks": "Give a useful review and evidence",
    "execution_workspace": "/tmp/selected-book",
    "execution_model": "",
    "revision": 1,
  }
}

///|
test "formal dispatch snapshot is stable, read-only capable and uses explicit workspace" {
  let task = native_test_task()
  let first = native_execution_snapshot(task, "moongate/test", "founder")
  let second = native_execution_snapshot(task, "moongate/test", "founder")
  assert_eq(first, second)
  assert_eq(native_text(first, "task_id"), "PT-native")
  assert_eq(native_text(first, "workspace"), "/tmp/selected-book")
  let snapshot = @json.parse(native_text(first, "request_body"))
  assert_eq(native_text(snapshot, "protocol"), "mooncode.v1")
  assert_eq(native_text(snapshot, "command"), "prompt")
  assert_eq(native_field(snapshot, "execution_plan"), Json::null())
  assert_eq(native_field(snapshot, "runtime_tool_calls"), Json::null())
  assert_eq(native_text(snapshot, "model"), "moongate/test")
  assert_eq(
    native_text(native_field(snapshot, "packet"), "command_id"),
    native_text(first, "command_id"),
  )
  // Persisting JSONB around the string cannot reorder the native request bytes.
  let saved = @json.parse(first.stringify())
  assert_eq(
    native_text(saved, "request_body"),
    native_text(first, "request_body"),
  )
}

///|
test "formal dispatch optional model resolves the existing MoonGate route once" {
  let route : Json = {
    "contract": "moonclaw.moongate-route.v1",
    "ready": true,
    "default_model": "moongate/default",
    "models": [{ "name": "moongate/default" }, { "name": "moongate/other" }],
  }
  assert_eq(native_model(route, ""), "moongate/default")
  assert_eq(native_model(route, "moongate/other"), "moongate/other")
  assert_true(
    (Ok(native_model(route, "codex/not-native")) catch { e => Err(e) })
    is Err(_),
  )
  assert_true(
    (Ok(native_model({ "ready": false }, "")) catch { e => Err(e) }) is Err(_),
  )
}

///|
fn native_test_claims(
  execution : Json,
  status : String,
  command_override? : String,
) -> Json {
  let command = command_override.unwrap_or(native_text(execution, "command_id"))
  {
    "session_id": native_text(execution, "session_id"),
    "book_root": native_text(execution, "workspace"),
    "delivered_commands": [
      {
        "command_id": command,
        "session_id": native_text(execution, "session_id"),
        "receipt": {
          "id": "receipt-exact",
          "session_id": native_text(execution, "session_id"),
          "command_id": command,
          "status": status,
          "execution": {
            "tool_results": [
              {
                "tool": "finish",
                "accepted": true,
                "result": {
                  "is_error": false,
                  "metadata": { "answer": "Useful native result" },
                },
              },
            ],
          },
        },
      },
    ],
  }
}

///|
fn native_test_state(execution : Json, status : String) -> Json {
  {
    "session_id": native_text(execution, "session_id"),
    "book_root": native_text(execution, "workspace"),
    "status": status,
    "events": [],
  }
}

///|
test "formal task completion requires exact command terminal receipt" {
  let run = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  let events = native_test_state(run, "")
  let service = native_test_state(run, "idle")
  for
    pair in [
      ("runtime-completed", "completed"),
      ("runtime-failed", "failed"),
      ("runtime-cancelled", "cancelled"),
      ("runtime-claimed", "interrupted"),
    ] {
    let result = native_execution_readback(
      run,
      native_test_claims(run, pair.0),
      events,
      service,
    )
    assert_eq(native_text(result, "state"), pair.1)
    assert_eq(native_text(result, "task_id"), "PT-native")
    if pair.1 == "completed" {
      assert_eq(native_text(result, "summary"), "Useful native result")
    } else {
      assert_eq(native_text(result, "summary"), "")
    }
  }
  let unrelated = native_execution_readback(
    run,
    native_test_claims(
      run,
      "runtime-completed",
      command_override="other-command",
    ),
    events,
    service,
  )
  assert_eq(native_text(unrelated, "state"), "unknown")
  assert_eq(native_text(unrelated, "summary"), "")
  assert_true(
    (Ok(
      native_execution_readback(run, { "session_id": "other" }, events, service),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "formal task approval wait and late artifacts remain visible without acceptance" {
  let run = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  let event : Json = {
    "id": "event-exact",
    "session_id": native_text(run, "session_id"),
    "command_id": native_text(run, "command_id"),
    "kind": "runtime.turn_checkpointed",
    "state": "awaiting-approval",
  }
  let events : Json = {
    "session_id": native_text(run, "session_id"),
    "book_root": native_text(run, "workspace"),
    "events": [event],
  }
  let waiting = native_execution_readback(
    run,
    native_test_claims(run, "runtime-claimed"),
    events,
    native_test_state(run, "waiting"),
  )
  assert_eq(native_text(waiting, "state"), "waiting_approval")
  assert_eq(native_text(waiting, "summary"), "")
  let artifact : Json = {
    "id": "artifact-event",
    "session_id": native_text(run, "session_id"),
    "command_id": native_text(run, "command_id"),
    "path": "results/review.md",
    "event": "tool_result",
    "tool": "write",
    "tool_result": { "ok": true },
  }
  let later : Json = {
    "session_id": native_text(run, "session_id"),
    "book_root": native_text(run, "workspace"),
    "events": [artifact],
  }
  let completed = native_execution_readback(
    run,
    native_test_claims(run, "runtime-completed"),
    later,
    native_test_state(run, "idle"),
  )
  assert_eq(native_array(completed, "artifact_refs").length(), 1)
  assert_eq(native_array(completed, "output_urls").length(), 0)
  assert_eq(native_field(completed, "acceptance"), Json::null())
}

///|
test "formal task routes preserve exact identity and encode workspace query" {
  assert_eq(
    native_dispatch_id("/api/company/plan/tasks/PT-1/dispatch"),
    Some("PT-1"),
  )
  assert_eq(
    native_dispatch_id("/api/company/plan/tasks/PT-1/other/dispatch"),
    None,
  )
  assert_eq(native_detail_id("/api/company/tasks/PT-1"), Some("PT-1"))
  assert_eq(native_detail_id("/api/company/tasks/PT-1/delay-impact"), None)
  assert_eq(native_component("/books/one & two"), "%2Fbooks%2Fone%20%26%20two")
}

///|
test "native control config uses explicit Desk path across different app data roots" {
  let path = "/Users/founder/Library/Application Support/app.vectie.moondesk/control/execution-sandbox/native.json"
  assert_eq(
    native_control_root(path),
    "/Users/founder/Library/Application Support/app.vectie.moondesk/control/execution-sandbox",
  )
  // MoonProj's app-data root never participates in resolving that explicit path.
  assert_false(native_control_root(path).contains("app.vectie.moonproj"))
  assert_eq(native_loopback_port("http://127.0.0.1:18123"), Some("18123"))
  assert_eq(
    native_loopback_port("http://localhost:18123@foreign.example"),
    None,
  )
  assert_eq(
    native_daemon_info_path("/suite/books/example"),
    "/suite/.moonsuite/products/moonclaw/daemon.json",
  )
  assert_eq(
    native_daemon_info_path("/suite"),
    "/suite/.moonsuite/products/moonclaw/daemon.json",
  )
}

///|
async test "formal task reads actual cold native receipts and ignores a later command" {
  // Captured from actual MoonClaw submit/runtime/write/finish/retry and a fresh
  // Daemon's durable builders, using explicit deterministic tools, no provider.
  let root = "cmd/postgres_company_gateway/testdata/"
  let claims = @json.parse(
    @encoding/utf8.decode(@fs.read_file(root + "cold-claim.json").binary()),
  )
  let events = @json.parse(
    @encoding/utf8.decode(@fs.read_file(root + "cold-events.json").binary()),
  )
  let service = @json.parse(
    @encoding/utf8.decode(@fs.read_file(root + "cold-service.json").binary()),
  )
  let execution : Json = {
    "task_id": "PT-exact",
    "run_id": "run-exact",
    "session_id": native_text(claims, "session_id"),
    "command_id": "moonproj-native-command-1",
    "workspace": native_text(claims, "book_root"),
    "state": "queued",
    "output_urls": [],
  }
  let result = native_execution_readback(execution, claims, events, service)
  assert_eq(native_text(result, "state"), "completed")
  assert_eq(native_text(result, "summary"), "NATIVE_ANSWER_42")
  assert_eq(native_text(result, "task_id"), "PT-exact")
  assert_true(
    native_array(result, "artifact_refs").any(item => {
      native_text(item, "path") == "finding.txt"
    }),
  )
  assert_true(native_array(result, "evidence_ids").length() > 0)
  assert_false(result.stringify().contains("LATER_UNRELATED_ANSWER"))
}

///|
test "native dispatch discovers configured dynamic port rather than generic audit default" {
  assert_eq(native_control_uri("", "23456"), "http://127.0.0.1:23456")
  assert_eq(
    native_control_uri("http://localhost:23456", "23456"),
    "http://localhost:23456",
  )
  assert_true(
    (Ok(native_control_uri("http://localhost:18123", "23456")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true((Ok(native_control_uri("", "0")) catch { e => Err(e) }) is Err(_))
}

///|
test "objective delivery instructions use the existing native run without inventing a workforce" {
  assert_eq(native_objective_delivery_prompt(native_test_task()), "")
  let fields = match native_test_task() {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields["parentTaskGuid"] = Json::string("objective-1")
  let task = Json::object(fields)
  let snapshot = native_execution_snapshot(task, "moongate/test", "founder")
  let request = @json.parse(native_text(snapshot, "request_body"))
  let prompt = native_text(request, "text")
  // Inspect the captured command, not a UI-only instruction.
  assert_true(prompt.contains("objective-1"))
  assert_true(prompt.contains("one integrated deliverable"))
  assert_true(prompt.contains("Do not invent specialist work"))
  assert_eq(native_text(snapshot, "task_id"), native_text(task, "taskGuid"))
}

///|
test "native output references exclude read inputs and include changed files and package manifests" {
  assert_eq(
    native_output_paths({
      "event": "tool_result",
      "tool": "read",
      "path": "input.md",
      "tool_result": { "ok": true },
    }),
    [],
  )
  assert_eq(
    native_output_paths({
      "event": "patch_applied",
      "tool": "apply_patch",
      "path": "",
      "changed_paths": ["one.mbt", "two.mbt"],
      "tool_result": { "ok": true },
    }),
    ["one.mbt", "two.mbt"],
  )
  assert_eq(
    native_output_paths({
      "event": "package_built",
      "path": "bundle.zip",
      "package_result": {
        "package_manifest": {
          "manifest_path": "manifest.json",
          "candidate_paths": ["dist/app"],
          "source_inventory": [
            {
              "path": "sources/main.mbt",
              "promoted_path": "published/main.mbt",
            },
          ],
        },
        "package_index": { "manifest_path": "index.json" },
      },
    }),
    [
      "bundle.zip", "manifest.json", "dist/app", "sources/main.mbt", "published/main.mbt",
      "index.json",
    ],
  )
  assert_eq(
    native_output_paths({
      "event": "tool_result",
      "tool": "write",
      "path": "/external/file",
      "tool_result": { "ok": true },
    }),
    [],
  )
}

///|
test "native approval decision clears only matching checkpoint and paused service is resumable" {
  let run = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  let session = native_text(run, "session_id")
  let command = native_text(run, "command_id")
  let checkpoint : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "runtime.turn_checkpointed",
    "state": "awaiting-approval",
    "approval_id": "approval-exact",
  }
  let approved : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "tool.approval_approved",
    "state": "approved",
    "approval_id": "approval-exact",
  }
  let other : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "tool.approval_approved",
    "state": "approved",
    "approval_id": "other-approval",
  }
  fn events(items : Array[Json]) -> Json {
    {
      "session_id": session,
      "book_root": native_text(run, "workspace"),
      "events": Json::array(items),
    }
  }
  let claims = native_test_claims(run, "runtime-claimed")
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([checkpoint, other]),
        native_test_state(run, "running"),
      ),
      "state",
    ),
    "waiting_approval",
  )
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([checkpoint, approved]),
        native_test_state(run, "running"),
      ),
      "state",
    ),
    "running",
  )
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([checkpoint, approved]),
        native_test_state(run, "waiting"),
      ),
      "state",
    ),
    "interrupted",
  )
  let paused : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "runtime.turn_checkpointed",
    "state": "planner-quantum-paused",
  }
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([paused]),
        native_test_state(run, "running"),
      ),
      "state",
    ),
    "interrupted",
  )
}

///|
test "paused native task resumes only on active progress for its exact command" {
  let run = native_execution_snapshot(
    native_test_task(),
    "moongate/test",
    "founder",
  )
  let session = native_text(run, "session_id")
  let command = native_text(run, "command_id")
  let paused : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "runtime.turn_checkpointed",
    "state": "planner-quantum-paused",
  }
  let resumed : Json = {
    "session_id": session,
    "command_id": command,
    "kind": "runtime.turn_started",
  }
  let unrelated : Json = {
    "session_id": session,
    "command_id": "other-command",
    "kind": "runtime.turn_started",
  }
  fn events(items : Array[Json]) -> Json {
    {
      "session_id": session,
      "book_root": native_text(run, "workspace"),
      "events": Json::array(items),
    }
  }
  let claims = native_test_claims(run, "runtime-claimed")
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([paused, unrelated]),
        native_test_state(run, "running"),
      ),
      "state",
    ),
    "interrupted",
  )
  assert_eq(
    native_text(
      native_execution_readback(
        run,
        claims,
        events([paused, resumed]),
        native_test_state(run, "running"),
      ),
      "state",
    ),
    "running",
  )
}
