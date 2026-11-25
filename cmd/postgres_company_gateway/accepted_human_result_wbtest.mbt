///|
fn accepted_result_test_field(value : Json, key : String, item : Json) -> Json {
  let fields = match value {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields[key] = item
  Json::object(fields)
}

///|
fn accepted_result_test_data(
  root : String,
  bytes : Bytes,
  revision_id? : String = "H1",
  report_id? : String = "report-T",
) -> Json {
  let (original, captured, _) = human_revision_test_fixture(root~, bytes~)
  let revision = accepted_result_test_field(
    accepted_result_test_field(
      captured,
      "revision_id",
      Json::string(revision_id),
    ),
    "content",
    accepted_result_test_field(
      native_field(captured, "content"),
      "path",
      Json::string(human_revision_directory(revision_id) + "/content.txt"),
    ),
  )
  let source : Json = {
    "type": "human_revision",
    "revision_id": revision_id,
    "original_run_id": "R",
  }
  let receipts : Array[Json] = ["report", "internal_acceptance"].map(action => {
    "action": action,
    "actor_id": "synthetic-reviewer",
    "event_id": action + "-event",
    "audit_id": action + "-audit",
    "audit_state": "available",
    "revision": if action == "report" {
      2
    } else {
      3
    },
    "report_id": report_id,
    "delivery_source": source,
  })
  {
    "task": {
      "taskGuid": "T",
      "projGuid": "P",
      "taskName": "Synthetic human result",
      "status": "done",
      "revision": 3,
      "accepted_report_id": report_id,
      "accepted_delivery_source": source,
      "execution": original,
      "human_revisions": [revision],
      "continuations": [],
    },
    "reports": [
      {
        "reportGuid": report_id,
        "task_id": "T",
        "summary": "Accepted internal human revision, no customer or Book assertion",
        "delivery_source": source,
        "delivery_source_snapshot": revision,
      },
    ],
    "commitment": { "task_id": "T", "receipts": receipts },
  }
}

///|
async fn accepted_result_test_store(data : Json, bytes : Bytes) -> Unit {
  let task = native_field(data, "task")
  let revision = native_array(task, "human_revisions")[0]
  let root = native_text(native_field(task, "execution"), "workspace")
  let directory = root +
    "/" +
    human_revision_directory(native_text(revision, "revision_id"))
  @fs.mkdir(directory, recursive=true) catch {
    _ => ()
  }
  @fs.write_file(
    directory + "/revision.json",
    revision.stringify(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    directory + "/content.txt",
    bytes,
    create_mode=CreateOrTruncate,
  )
}

///|
async test "accepted human result exports immutable exact Unicode empty and max bytes deterministically" {
  let root = @fs.tmpdir(prefix="moonproj-accepted-result-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  for
    text in [
      "Human revision 人工 🌕\n  retain spaces  \n",
      "",
      "x".repeat(256 * 1024),
      "🌕".repeat(65536),
    ] {
    let bytes = @encoding/utf8.encode(text)
    let data = accepted_result_test_data(root, bytes)
    accepted_result_test_store(data, bytes)
    let before = data.stringify()
    let result = accepted_human_result_projection(data)
    assert_eq(
      result.stringify(),
      accepted_human_result_projection(data).stringify(),
    )
    assert_eq(data.stringify(), before)
    assert_eq(
      native_text(result, "contract_version"),
      "moonproj.accepted-human-result.v1",
    )
    assert_eq(
      native_text(result, "provenance_scope"),
      "captured_accepted_human_revision",
    )
    assert_eq(
      native_text(result, "authenticity"),
      "unsigned_source_observation",
    )
    assert_eq(native_field(result, "authorizing"), Json::boolean(false))
    assert_eq(native_text(native_field(result, "task"), "record_version"), "3")
    assert_eq(
      native_text(native_field(result, "report"), "record_version"),
      "2",
    )
    let content = native_field(result, "content")
    assert_eq(@base64.decode(native_text(content, "data")), bytes)
    assert_eq(
      native_field(content, "size_bytes"),
      ToJson::to_json(bytes.length()),
    )
    assert_eq(
      native_text(content, "sha256"),
      "sha256:" + native_context_hash(bytes),
    )
    let snapshot = native_array(native_field(data, "task"), "human_revisions")[0]
    // Whitespace in the manifest file is not the captured snapshot digest.
    @fs.write_file(
      root + "/" + human_revision_directory("H1") + "/revision.json",
      snapshot.stringify(indent=2),
      create_mode=TruncateExisting,
    )
    assert_eq(result, accepted_human_result_projection(data))
    assert_eq(
      native_text(native_field(result, "revision"), "revision_snapshot_digest"),
      "sha256:" +
      native_context_hash(@encoding/utf8.encode(snapshot.stringify())),
    )
    assert_false(result.stringify().contains(root))
    assert_false(result.stringify().contains("answer.md"))
    assert_false(result.stringify().contains(".moonsuite"))
    // The live workspace file is not the accepted immutable source.
    @fs.write_file(
      root + "/answer.md",
      "Live file changed",
      create_mode=CreateOrTruncate,
    )
    assert_eq(result, accepted_human_result_projection(data))
  }
}

///|
async test "accepted human result rejects wrong source report receipts manifest missing tampered and symlink bytes" {
  let root = @fs.tmpdir(prefix="moonproj-accepted-reject-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let bytes = @encoding/utf8.encode("Accepted body 人工\n")
  let data = accepted_result_test_data(root, bytes)
  accepted_result_test_store(data, bytes)
  let task = native_field(data, "task")
  for
    (key, value) in [
      ("status", Json::string("doing")),
      ("accepted_report_id", Json::string("another")),
      ("accepted_delivery_source", { "type": "original" }),
      ("human_revisions", Json::array([])),
      (
        "human_revisions",
        Json::array(
          native_array(task, "human_revisions") +
          native_array(task, "human_revisions"),
        ),
      ),
      ("revision", Json::number(2147483648)),
    ] {
    assert_true(
      (try
        Ok(
          accepted_human_result_projection(
            accepted_result_test_field(
              data,
              "task",
              accepted_result_test_field(task, key, value),
            ),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
      msg=key,
    )
  }
  let report = native_array(data, "reports")[0]
  for
    (key, value) in [
      ("delivery_source", ({ "type": "original" } : Json)),
      ("delivery_source_snapshot", Json::null()),
      ("reportGuid", Json::string("another")),
      ("task_id", Json::string("another")),
    ] {
    assert_true(
      (try
        Ok(
          accepted_human_result_projection(
            accepted_result_test_field(
              data,
              "reports",
              Json::array([accepted_result_test_field(report, key, value)]),
            ),
          ),
        )
      catch {
        e => Err(e)
      })
      is Err(_),
      msg=key,
    )
  }
  assert_true(
    (try
      Ok(
        accepted_human_result_projection(
          accepted_result_test_field(data, "commitment", {
            "task_id": "T",
            "receipts": [],
          }),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
  let directory = root + "/" + human_revision_directory("H1")
  let revision = native_array(task, "human_revisions")[0]
  @fs.write_file(
    directory + "/revision.json",
    accepted_result_test_field(revision, "created_at", Json::string("changed")).stringify(),
    create_mode=TruncateExisting,
  )
  assert_true(
    (try Ok(accepted_human_result_projection(data)) catch { e => Err(e) })
    is Err(_),
  )
  accepted_result_test_store(data, bytes)
  @fs.write_file(
    directory + "/content.txt",
    "tampered",
    create_mode=TruncateExisting,
  )
  assert_true(
    (try Ok(accepted_human_result_projection(data)) catch { e => Err(e) })
    is Err(_),
  )
  @fs.remove(directory + "/content.txt")
  assert_true(
    (try Ok(accepted_human_result_projection(data)) catch { e => Err(e) })
    is Err(_),
  )
  @fs.write_file(root + "/outside.txt", bytes, create_mode=CreateNew)
  @fs.symlink(target=root + "/outside.txt", directory + "/content.txt")
  assert_true(
    (try Ok(accepted_human_result_projection(data)) catch { e => Err(e) })
    is Err(_),
  )
}

///|
async test "accepted human result portability rejects NUL invalid UTF8 and over limit bytes" {
  let root = @fs.tmpdir(prefix="moonproj-accepted-bounds-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  for
    bytes in [
      b"a\x00b",
      b"\xff",
      @encoding/utf8.encode("x".repeat(256 * 1024 + 1)),
    ] {
    let data = accepted_result_test_data(root, bytes)
    accepted_result_test_store(data, bytes)
    assert_true(
      (try Ok(accepted_human_result_projection(data)) catch { e => Err(e) })
      is Err(_),
    )
  }
}

///|
async test "accepted human result preserves accepted unattached attribution and rejects contradictory attached output" {
  let root = @fs.tmpdir(prefix="moonproj-accepted-attribution-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let data = accepted_result_test_data(root, b"Accepted")
  let task = native_field(data, "task")
  let revision = accepted_result_test_field(
    native_array(task, "human_revisions")[0],
    "output",
    {
      "command_id": "C1",
      "path": "followup.md",
      "evidence_id": "C1:event/result",
    },
  )
  let revised_task = accepted_result_test_field(
    task,
    "human_revisions",
    Json::array([revision]),
  )
  let revised = accepted_result_test_field(
    accepted_result_test_field(data, "task", revised_task),
    "reports",
    Json::array([
      accepted_result_test_field(
        native_array(data, "reports")[0],
        "delivery_source_snapshot",
        revision,
      ),
    ]),
  )
  accepted_result_test_store(revised, b"Accepted")
  let result = accepted_human_result_projection(revised)
  assert_eq(
    native_text(native_field(result, "revision"), "output_command_id"),
    "C1",
  )
  assert_eq(
    native_text(native_field(result, "revision"), "output_evidence_id"),
    "C1:event/result",
  )
  assert_true(
    (try
      Ok(
        accepted_human_result_projection(
          accepted_result_test_field(
            revised,
            "task",
            accepted_result_test_field(
              revised_task,
              "continuations",
              Json::array([{ "command_id": "C1", "artifact_refs": [] }]),
            ),
          ),
        ),
      )
    catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "accepted human result route and opaque evidence IDs remain bounded and path safe" {
  assert_eq(
    accepted_human_result_task_id("/api/company/tasks/T/accepted-human-result"),
    Some("T"),
  )
  for
    path in [
      "/api/company/tasks/../accepted-human-result", "/api/company/tasks/T/extra/accepted-human-result",
      "/api/company/tasks/T/accepted-human-result/", "/api/company/tasks/T/lesson-handoff",
    ] {
    assert_eq(accepted_human_result_task_id(path), None)
  }
  for
    id in [
      "",
      " ",
      "/tmp/file",
      "C:/file",
      "file:///tmp/file",
      "FILE:abc",
      "e\\id",
      "e\nid",
      "event:/book/secret",
      "x".repeat(4097),
    ] {
    assert_false(accepted_human_result_evidence_id(id, "/book"), msg=id)
  }
  for id in ["E0", "C1:event/result", "opaque/../identity", "event:.moonsuite"] {
    assert_true(accepted_human_result_evidence_id(id, "/book"), msg=id)
  }
}
