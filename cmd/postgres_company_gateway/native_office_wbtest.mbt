///|
test "office route accepts only an exact task read" {
  assert_eq(native_office_task_id("/api/company/tasks/T/office"), Some("T"))
  for
    path in [
      "/api/company/tasks/T/office/stop", "/api/company/tasks/T/child/office", "/api/company/plan/tasks/T/office",
    ] {
    assert_eq(native_office_task_id(path), None)
  }
}

///|
async test "office observation only inspects the captured native session and excludes personal memory" {
  let task : Json = {
    "taskGuid": "T",
    "execution": { "session_id": "S", "workspace": "/book" },
  }
  let calls : Array[String] = []
  let observed = native_office_observation(task, (session, root) => {
    calls.push(session + ":" + root)
    {
      "owner": "moonclaw",
      "session_id": "S",
      "context": {
        "book_root": "/book",
        "active_command_id": "C",
        "conversation": "private context",
      },
      "personal_memory": "PRIVATE PERSONAL MEMORY",
      "workers": [
        {
          "worker_id": "review",
          "child_session_id": "W",
          "status": "done",
          "terminal": true,
          "result": {
            "answer": "Reviewed actual output",
            "artifact_references": [{ "path": "review.md" }],
            "private_extra": "NO",
          },
        },
      ],
    }
  })
  assert_eq(calls, ["S:/book"])
  assert_eq(native_text(observed, "state"), "observed")
  assert_true(native_field(observed, "observed_at") is Number(_))
  assert_eq(
    native_text(native_array(observed, "workers")[0], "summary"),
    "Reviewed actual output",
  )
  assert_eq(native_field(observed, "task"), task)
  assert_false(observed.stringify().contains("PRIVATE PERSONAL MEMORY"))
  assert_false(observed.stringify().contains("private context"))
  assert_false(observed.stringify().contains("private_extra"))
}

///|
async test "office unavailable or mismatched runtime preserves recorded workers without dispatch" {
  let task : Json = {
    "taskGuid": "T",
    "execution": {
      "session_id": "S",
      "workspace": "/book",
      "workers": [{ "worker_id": "saved", "status": "done" }],
    },
  }
  let result = native_office_observation(task, (_, _) => raise fail("offline"))
  assert_eq(native_text(result, "state"), "unavailable")
  assert_eq(
    native_array(result, "workers"),
    native_array(native_field(task, "execution"), "workers"),
  )
  let mismatch = native_office_observation(task, (_, _) => {
    "owner": "moonclaw",
    "session_id": "other",
    "workers": [],
    "context": { "book_root": "/book" },
  })
  assert_eq(native_text(mismatch, "state"), "unavailable")
  let empty = native_office_observation({ "taskGuid": "new" }, (_, _) => {
    assert_true(false)
    Json::null()
  })
  assert_eq(native_text(empty, "state"), "recorded")
  let stopped = native_office_observation(
    {
      "taskGuid": "stopped",
      "execution": { "session_id": "S", "control_state": "stopped" },
    },
    (_, _) => {
      assert_true(false)
      Json::null()
    },
  )
  assert_eq(native_text(stopped, "state"), "recorded")
}
