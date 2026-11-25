///|
fn human_revision_test_fixture(
  root? : String = "/book",
  bytes? : Bytes = b"Human revision",
) -> (Json, Json, Bytes) {
  let original : Json = {
    "run_id": "R",
    "task_id": "T",
    "session_id": "S",
    "command_id": "C0",
    "workspace": root,
    "model": "original/model",
    "state": "completed",
    "artifact_refs": [
      { "command_id": "C0", "path": "answer.md", "evidence_id": "E0" },
    ],
  }
  let revision : Json = {
    "schema": "moonproj.human-revision.v1",
    "capture_scope": "immutable_human_revision",
    "revision_id": "H1",
    "task_id": "T",
    "original_run_id": "R",
    "session_id": "S",
    "original_command_id": "C0",
    "workspace": root,
    "workspace_id": "desk-workspace",
    "author_type": "human",
    "state": "saved",
    "output": { "command_id": "C0", "path": "answer.md", "evidence_id": "E0" },
    "base": {
      "scope": "current_workspace_bytes_at_edit",
      "sha256": native_context_hash(b"base"),
    },
    "content": {
      "path": human_revision_directory("H1") + "/content.txt",
      "sha256": native_context_hash(bytes),
      "size_bytes": bytes.length(),
    },
    "created_at": "2026-10-05T00:00:00Z",
  }
  (original, revision, bytes)
}

///|
test "human revision canonical manifest validates exact lineage bytes and attributed output without native promotion" {
  let (original, revision, bytes) = human_revision_test_fixture(
    bytes=@encoding/utf8.encode("人工修改\n"),
  )
  human_revision_validate(original, "H1", revision, bytes)
  human_revision_validate_output(revision, original)
  let request : Json = {
    "human_revision_id": "H1",
    "original_run_id": "R",
    "select_for_delivery": true,
    "authority": { "actor_id": "actor" },
    "summary": "browser forged summary",
    "human_revision": { "author_type": "model" },
  }
  let imported = native_human_revision_import_body(original, request, revision)
  assert_eq(native_field(imported, "human_revision"), revision)
  assert_true(native_field(imported, "continuation") is Null)
  assert_true(native_field(revision, "receipt") is Null)
  assert_true(native_field(revision, "command_id") is Null)
  assert_true(native_field(revision, "model") is Null)
}

///|
test "human revision rejects mismatched identity provenance digest size synthetic native fields and invalid UTF8" {
  let (original, revision, bytes) = human_revision_test_fixture()
  for
    (key, value) in [
      ("task_id", Json::string("other")),
      ("original_run_id", Json::string("other")),
      ("session_id", Json::string("other")),
      ("original_command_id", Json::string("other")),
      ("workspace", Json::string("/elsewhere")),
      ("revision_id", Json::string("H2")),
      ("author_type", Json::string("agent")),
      ("capture_scope", Json::string("workspace_replacement")),
      ("receipt", Json::object(Map([]))),
      ("model", Json::string("fake")),
      ("command_id", Json::string("synthetic")),
      (
        "content",
        {
          "path": "../content.txt",
          "sha256": native_context_hash(bytes),
          "size_bytes": bytes.length(),
        },
      ),
    ] {
    try
      human_revision_validate(
        original,
        "H1",
        continuation_test_field(revision, key, value),
        bytes,
      )
    catch {
      error => assert_eq(native_continuation_error(error).0, 409)
    } noraise {
      _ => raise fail("invalid revision accepted: " + key)
    }
  }
  for
    value in [b"different", b"\xff", @encoding/utf8.encode("界".repeat(90000))] {
    try human_revision_validate(original, "H1", revision, value) catch {
      _ => ()
    } noraise {
      _ => raise fail("changed or oversized content accepted")
    }
  }
  let (_, invalid_utf8, invalid) = human_revision_test_fixture(bytes=b"\xff")
  try human_revision_validate(original, "H1", invalid_utf8, invalid) catch {
    _ => ()
  } noraise {
    _ => raise fail("invalid UTF-8 bytes with matching digest accepted")
  }
  for
    output in [
      { "command_id": "C1", "path": "answer.md", "evidence_id": "E0" },
      { "command_id": "C0", "path": "other.md", "evidence_id": "E0" },
      { "command_id": "C0", "path": "answer.md", "evidence_id": "E1" },
    ] {
    try
      human_revision_validate_output(
        continuation_test_field(revision, "output", ToJson::to_json(output)),
        original,
      )
    catch {
      error => assert_eq(native_continuation_error(error).0, 409)
    } noraise {
      _ => raise fail("foreign output accepted")
    }
  }
}

///|
async test "human revision exact canonical snapshot permits empty text and rejects missing changed and symlink bytes" {
  let root = @fs.tmpdir(prefix="moonproj-human-revision-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let (original, revision, bytes) = human_revision_test_fixture(root~)
  let directory = root + "/" + human_revision_directory("H1")
  @fs.mkdir(directory, recursive=true)
  @fs.write_file(
    directory + "/revision.json",
    revision.stringify(),
    create_mode=CreateNew,
  )
  try human_revision_snapshot(original, "H1") catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => raise fail("missing snapshot accepted")
  }
  @fs.write_file(directory + "/content.txt", bytes, create_mode=CreateNew)
  assert_eq(human_revision_snapshot(original, "H1"), revision)
  assert_eq(
    human_revision_content(original, revision),
    @encoding/utf8.decode(bytes),
  )
  @fs.write_file(
    directory + "/content.txt",
    "tampered",
    create_mode=TruncateExisting,
  )
  try human_revision_snapshot(original, "H1") catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => raise fail("tampered snapshot accepted")
  }
  @fs.remove(directory + "/content.txt")
  @fs.write_file(root + "/elsewhere.txt", bytes, create_mode=CreateNew)
  @fs.symlink(target=root + "/elsewhere.txt", directory + "/content.txt")
  try human_revision_snapshot(original, "H1") catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => raise fail("symlink snapshot accepted")
  }
  @fs.remove(directory + "/content.txt")
  let (_, empty, _) = human_revision_test_fixture(root~, bytes=b"")
  @fs.write_file(
    directory + "/revision.json",
    empty.stringify(),
    create_mode=TruncateExisting,
  )
  @fs.write_file(directory + "/content.txt", b"", create_mode=CreateNew)
  assert_eq(human_revision_snapshot(original, "H1"), empty)
  assert_eq(human_revision_content(original, empty), "")
}

///|
test "human revision navigation ID cannot substitute native selection or task authority" {
  let (original, revision, _) = human_revision_test_fixture()
  let request : Json = {
    "human_revision_id": "H1",
    "original_run_id": "R",
    "select_for_delivery": true,
  }
  for
    (key, value) in [
      ("human_revision_id", Json::string("H2")),
      ("original_run_id", Json::string("R2")),
      ("select_for_delivery", Json::boolean(false)),
      ("command_id", Json::string("C1")),
      ("continuation_id", Json::string("K1")),
      ("selected_delivery_source", { "type": "original" }),
    ] {
    try
      native_human_revision_import_body(
        original,
        continuation_test_field(request, key, value),
        revision,
      )
    catch {
      error => assert_eq(native_continuation_error(error).0, 409)
    } noraise {
      _ => raise fail("ambiguous identity accepted")
    }
  }
  let task : Json = {
    "status": "done",
    "execution": original,
    "human_revisions": [revision],
  }
  let envelope = native_continuation_envelope(
    task,
    Json::null(),
    [],
    "ready",
    "",
  )
  assert_true(native_bool(envelope, "inspection_only"))
  assert_eq(native_array(envelope, "human_revisions"), [revision])
}

///|
async test "human revision from unattached native continuation reads exact source without attaching or selecting it" {
  let (original, revision, _) = human_revision_test_fixture()
  let task : Json = {
    "taskGuid": "T",
    "status": "doing",
    "execution": original,
    "continuations": [],
  }
  let revised = continuation_test_field(revision, "output", {
    "command_id": "C1",
    "path": "followup.md",
    "evidence_id": "E1",
  })
  let reads : Array[String] = []
  let source : Json = {
    "command_id": "C1",
    "artifact_refs": [
      { "command_id": "C1", "path": "followup.md", "evidence_id": "E1" },
    ],
  }
  assert_eq(
    human_revision_candidate_source(task, revised, command => {
      reads.push(command)
      source
    }),
    revised,
  )
  assert_eq(reads, ["C1"])
  assert_eq(native_array(task, "continuations"), [])
  assert_true(native_field(task, "selected_delivery_source") is Null)
  assert_eq(native_field(task, "execution"), original)
  let attached = continuation_test_field(
    task,
    "continuations",
    Json::array([source]),
  )
  assert_eq(
    human_revision_candidate_source(attached, revised, _ => {
      raise fail("attached source should not need runtime discovery")
    }),
    revised,
  )
  let changed = continuation_test_field(
    revised,
    "created_at",
    Json::string("changed"),
  )
  let saved = continuation_test_field(
    attached,
    "human_revisions",
    Json::array([revised]),
  )
  try human_revision_candidate_source(saved, changed, _ => source) catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => raise fail("persisted immutable identity changed")
  }
  try human_revision_candidate_source(task, revised, _ => original) catch {
    error => assert_eq(native_continuation_error(error).0, 409)
  } noraise {
    _ => raise fail("latest or original substituted for exact continuation")
  }
}

///|
async test "actual Desk saved human revision crosses canonical task return and exact text preview" {
  let root = @env.get_env_var("MOONPROJ_HUMAN_REVISION_FIXTURE_ROOT").unwrap_or(
    "",
  )
  if root.is_empty() {
    return
  }
  let output : Json = {
    "command_id": "C0",
    "path": "result.md",
    "evidence_id": "event-C0",
  }
  let original : Json = {
    "run_id": "R",
    "task_id": "T",
    "session_id": "S",
    "command_id": "C0",
    "workspace": root,
    "artifact_refs": [output],
  }
  let task : Json = {
    "taskGuid": "T",
    "status": "doing",
    "execution": original,
    "continuations": [],
  }
  let snapshot = human_revision_snapshot(original, "human-K")
  assert_eq(native_text(snapshot, "workspace_id"), "book")
  assert_eq(native_field(snapshot, "output"), output)
  assert_eq(
    native_text(native_field(snapshot, "base"), "sha256"),
    native_context_hash(@encoding/utf8.encode("Original 书\n")),
  )
  assert_eq(
    human_revision_content(original, snapshot),
    "Human revision 人工\n  retain spaces  \n",
  )
  assert_eq(
    human_revision_candidate_source(task, snapshot, _ => {
      raise fail("original output must not invoke native discovery")
    }),
    snapshot,
  )
  let imported = native_human_revision_import_body(
    original,
    {
      "human_revision_id": "human-K",
      "original_run_id": "R",
      "select_for_delivery": true,
    },
    snapshot,
  )
  assert_eq(native_field(imported, "human_revision"), snapshot)
  assert_true(native_field(imported, "human_revision_content") is Null)
  assert_true(native_field(task, "selected_delivery_source") is Null)
}
