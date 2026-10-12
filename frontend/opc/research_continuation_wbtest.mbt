///|
test "actual continued Find exports survive Proj import local draft restore and founder packet without dispatch" {
  for kind in ["current", "changed", "removed", "refreshed"] {
    let original = drafts_test_valid()
    let choosing = research_test_update({ ..original, page: Dispatch, }, Choose)
    let loaded = research_test_update(
      choosing,
      Loaded(
        choosing.research_import.generation,
        choosing.dispatch_task_actor_id,
        continuation_export(kind),
        "",
      ),
    )
    guard loaded.research_import.brief is Some(brief) else {
      fail("exact export did not preview: " + kind)
    }
    assert_eq(loaded.dispatch_drafts, original.dispatch_drafts)
    let prepared = research_test_update(loaded, Prepare)
    let draft = dispatch_active_draft(prepared).unwrap()
    assert_eq(draft.research_brief, Some(brief))
    assert_false(draft.attempted)
    assert_eq(prepared.dispatch_task_id, original.dispatch_task_id)
    let saved = dispatch_draft_store(prepared)
    let restored = drafts_test_update(
      { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
      Restored("actor-drafts", saved),
    )
    let recovered = dispatch_draft_by_id(restored, draft.id).unwrap()
    assert_eq(recovered.research_brief, Some(brief))
    let packet = research_founder_packet(recovered)
    for
      phrase in [
        "Pilot 学习 🌒", "Learn before committing", "Interview three buyers",
        "Willingness to pay", "No signed company receipt",
      ] {
      assert_true(packet.contains(phrase), msg=kind + ": " + phrase)
    }
    if kind == "refreshed" {
      assert_true(packet.contains("Historical worksheet versions"))
      assert_eq(
        recovered.research_brief.unwrap().worksheet.options[0].source_id,
        "continuity:paper",
      )
    } else if kind != "current" {
      for
        phrase in [
          "Historical worksheet versions", "Historical source receipt", "Historical claim receipt",
          "not current evidence", "sha256:continuity", "Evidence claim", "not been revalidated",
        ] {
        assert_true(packet.contains(phrase), msg=kind + ": " + phrase)
      }
      assert_eq(
        recovered.research_brief.unwrap().worksheet.options[0].source_id,
        "",
      )
    }
  }
}
