///|
test "actual continued MoonFind current changed removed exports retain full typed historical context" {
  for kind in ["current", "changed", "removed", "refreshed"] {
    let encoded = continuation_export(kind)
    guard @research_handoff.decode(encoded) is Ok(brief) else {
      fail("continued producer rejected: " + kind)
    }
    assert_eq(ToJson::to_json(brief), @json.parse(encoded))
    assert_eq(@research_handoff.decode(ToJson::to_json(brief).stringify()), Ok(brief))
    assert_eq(brief.worksheet.chosen_option_id, "option-1")
    assert_eq(brief.worksheet.reasoning, "Learn before committing")
    assert_eq(brief.worksheet.next_action, "Interview three buyers")
    if kind == "current" {
      assert_true(brief.worksheet.history is None)
      assert_eq(brief.worksheet.options[0].source_id, "continuity:paper")
    } else if kind == "refreshed" {
      assert_eq(brief.worksheet.options[0].source_id, "continuity:paper")
      assert_eq(brief.worksheet.options[0].claim_id, "continuity:claim")
      assert_eq(
        brief.worksheet.evidence.papers[0].retrieved_at,
        Some(1800000000000L),
      )
      assert_true(
        brief.worksheet.history.unwrap()[0].evidence.papers[0].retrieved_at
        is None,
      )
      assert_true(brief.markdown().contains("Historical worksheet versions"))
    } else {
      assert_eq(brief.worksheet.options[0].source_id, "")
      assert_eq(brief.worksheet.options[0].claim_id, "")
      assert_eq(
        brief.worksheet.options[0].retained_source.unwrap().source_digest,
        "sha256:continuity",
      )
      assert_eq(
        brief.worksheet.options[0].retained_claim.unwrap().statement,
        "Evidence claim",
      )
      assert_eq(brief.worksheet.history.unwrap().length(), 1)
      assert_eq(
        brief.worksheet.history.unwrap()[0].options[0].source_id,
        "continuity:paper",
      )
      for
        phrase in [
          "Historical worksheet versions", "Historical source receipt", "not current evidence",
          "sha256:continuity", "Evidence claim", "not been revalidated",
        ] {
        assert_true(brief.markdown().contains(phrase), msg=kind + ": " + phrase)
      }
      if kind == "removed" {
        assert_true(brief.worksheet.evidence.papers.is_empty())
      } else {
        assert_true(brief.markdown().contains("sha256:revised"))
      }
    }
  }
}

///|
test "continued research consumer rejects ambiguous cross-run oversized history and unknown metadata stays excluded" {
  guard @research_handoff.decode(continuation_export("changed")) is Ok(brief) else {
    fail("fixture")
  }
  let archive = brief.worksheet.history.unwrap()[0]
  for
    history in [
      [archive, archive],
      [{ ..archive, revision: brief.worksheet.revision, }],
      [{ ..archive, evidence: { ..archive.evidence, run_id: "different", }, }],
      Array::make(21, archive),
    ] {
    let invalid = {
      ..brief,
      worksheet: { ..brief.worksheet, history: Some(history), },
    }
    assert_true(
      @research_handoff.decode(ToJson::to_json(invalid).stringify()) is Err(_),
    )
  }
  let original = @json.parse(continuation_export("changed"))
  let worksheet = field(original, "worksheet")
  guard field(worksheet, "history") is Array(history) else { fail("history") }
  let dirty = set(
    original,
    "worksheet",
    set(
      worksheet,
      "history",
      Json::array([set(history[0], "api_key", "do-not-retain")]),
    ),
  )
  guard @research_handoff.decode(dirty.stringify()) is Ok(clean) else {
    fail("unknown metadata blocked")
  }
  assert_false(ToJson::to_json(clean).stringify().contains("do-not-retain"))
  assert_eq(clean, brief)
}
