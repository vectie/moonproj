///|
test "progress notes never enter the deliverable artifact list" {
  assert_eq(
    native_output_paths({
      "event": "tool_result",
      "tool": "write",
      "path": ".moonproj-progress-C.json",
      "tool_result": { "ok": true },
    }),
    [],
  )
  assert_eq(
    native_output_paths({
      "event": "tool_result",
      "tool": "write",
      "path": "review.md",
      "tool_result": { "ok": true },
    }),
    ["review.md"],
  )
}

///|
fn delivery_progress_test_note(task : Json, command : String) -> Json {
  {
    "schema": "moonproj.delivery-progress.v1",
    "task_id": native_text(task, "taskGuid"),
    "command_id": command,
    "deliverable": "Dissertation review and revision plan",
    "now": "Checking methods",
    "next": "Integrate comments",
    "contributions": [
      {
        "worker_id": "methods",
        "responsibility": "Methods review",
        "contributes_to": "Chapter 3",
        "private": "NO",
      },
    ],
    "private": "NO",
    "state": "completed",
  }
}

///|
test "progress is explanatory and exact task command scoped without completion authority" {
  let task = delivery_test_task()
  let note = delivery_progress_test_note(task, "C")
  let projected = native_delivery_progress_projection(task, "C", note)
  assert_eq(native_text(projected, "now"), "Checking methods")
  assert_false(projected.stringify().contains("private"))
  assert_false(projected.stringify().contains("completed"))
  assert_true(native_delivery_progress_projection(task, "other", note) is Null)
  assert_true(
    native_delivery_progress_projection(
      continuation_test_field(task, "taskGuid", Json::string("other")),
      "C",
      note,
    )
    is Null,
  )
}

///|
async test "progress reads only bounded canonical current command notes and is optional" {
  let root = @fs.tmpdir(prefix="moonproj-progress-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let task = continuation_test_field(delivery_test_task(), "execution", {
    "workspace": root,
    "command_id": "C",
  })
  assert_true(native_delivery_progress(task) is Null)
  @fs.write_file(
    root + "/.moonproj-progress-C.json",
    @encoding/utf8.encode(delivery_progress_test_note(task, "C").stringify()),
    create_mode=CreateNew,
  )
  assert_eq(
    native_text(native_delivery_progress(task), "now"),
    "Checking methods",
  )
  let newer = continuation_test_field(task, "execution", {
    "workspace": root,
    "command_id": "C",
    "revision_request": { "snapshot": { "command_id": "NEW" } },
  })
  assert_true(native_delivery_progress(newer) is Null)
  @fs.symlink(
    target=root + "/.moonproj-progress-C.json",
    root + "/.moonproj-progress-LINK.json",
  )
  assert_true(
    native_delivery_progress(
      continuation_test_field(task, "execution", {
        "workspace": root,
        "command_id": "LINK",
      }),
    )
    is Null,
  )
}

///|
test "saved workers retain substantive answers without private runtime context" {
  let projected = native_delivery_worker_projection({
    "worker_id": "methods",
    "child_book_root": "/book/worker",
    "status": "done",
    "personal_memory": "NO",
    "prompt": "NO",
    "result": {
      "answer": "Sampling rationale needs clarification",
      "answer_truncated": true,
      "private": "NO",
    },
  })
  assert_eq(
    native_text(projected, "summary"),
    "Sampling rationale needs clarification",
  )
  assert_true(native_bool(projected, "summary_truncated"))
  assert_eq(native_text(projected, "child_book_root"), "/book/worker")
  assert_false(projected.stringify().contains("NO"))
  let snapshot = native_execution_snapshot(
    delivery_test_task(),
    "configured-model",
    "founder",
  )
  let prompt = native_text(
    @json.parse(native_text(snapshot, "request_body")),
    "text",
  )
  assert_true(
    prompt.contains(
      ".moonproj-progress-" + native_text(snapshot, "command_id") + ".json",
    ),
  )
  assert_true(prompt.contains("contributes_to"))
}
