///|
fn field(value : Json, key : String) -> Json {
  guard value is Object(fields) else { abort("fixture object") }
  fields.get(key).unwrap()
}

///|
fn set(value : Json, key : String, replacement : Json) -> Json {
  guard value is Object(fields) else { abort("fixture object") }
  let copy = fields.copy()
  copy[key] = replacement
  Json::object(copy)
}

///|
fn parsed(kind : String) -> @research_handoff.Brief {
  guard @research_handoff.decode(producer_export(kind)) is Ok(brief) else {
    abort("producer fixture rejected")
  }
  brief
}

///|
test "actual final MoonFind export round-trips every known field and Unicode" {
  for kind in ["current", "historical", "undecided"] {
    let brief = parsed(kind)
    assert_eq(ToJson::to_json(brief), @json.parse(producer_export(kind)))
    assert_eq(
      @research_handoff.decode(ToJson::to_json(brief).stringify()),
      Ok(brief),
    )
    assert_eq(
      brief.worksheet.evidence.papers[0].retrieved_at,
      Some(1790000000000L),
    )
    assert_true(brief.markdown().contains("Local pilot 学习 🌒"))
  }
}

///|
test "decision packet retains exact dates citations conflicts unknowns and falsifier" {
  let brief = parsed("current")
  let markdown = brief.markdown()
  for
    text in [
      "independent-handoff source <evidence>", "independent-handoff:paper-v2", "sha256:independent-handoff",
      "https://example.org/independent-handoff.pdf", "2026-09-12", "2026-09-14",
      "1790000000000", "Measured evidence for independent-handoff", "Observed interviews disagree",
      "Willingness to pay", "Interview three buyers", "One founder day", "Reduce uncertainty before committing",
      "Prepare the interview questions", "commitment-review-17", "Replication missing",
      "Table 2", "limited", "Can it replicate?", "Small sample", "No formal task",
      "not independently checked here", "Unknown / not recorded",
    ] {
    assert_true(markdown.contains(text), msg=text)
  }
  assert_eq(brief.preparation_blocker(), "")
  assert_true(
    parsed("historical")
    .markdown()
    .contains("Historical or unavailable current context"),
  )
}

///|
test "undecided remains visible but cannot prepare work" {
  let brief = parsed("undecided")
  assert_eq(brief.chosen(), None)
  assert_false(brief.preparation_blocker().is_empty())
  assert_true(brief.markdown().contains("Undecided"))
  let no_action = {
    ..parsed("current"),
    worksheet: { ..parsed("current").worksheet, next_action: "", },
  }
  assert_false(no_action.preparation_blocker().is_empty())
}

///|
test "unknown authority credential and execution metadata is excluded at every typed level" {
  let original = @json.parse(producer_export("current"))
  let sheet = field(original, "worksheet")
  let evidence = field(sheet, "evidence")
  let dirty = set(
    set(
      set(original, "actor_id", "SECRET-ACTOR"),
      "access_token",
      "SECRET-TOKEN",
    ),
    "worksheet",
    set(
      set(sheet, "authority", { "scope": "SECRET-SCOPE" }),
      "evidence",
      set(evidence, "credentials", "SECRET-CREDENTIAL"),
    ),
  )
  guard @research_handoff.decode(dirty.stringify()) is Ok(clean) else {
    fail("metadata should be ignored")
  }
  assert_eq(ToJson::to_json(clean), original)
  assert_false(ToJson::to_json(clean).stringify().contains("SECRET-"))
  assert_false(clean.markdown().contains("SECRET-"))
}

///|
test "unknown contract malformed typed fields authority and source status fail closed" {
  let original = @json.parse(producer_export("current"))
  for
    invalid in [
      "{",
      "[]",
      "null",
      field(original, "worksheet").stringify(),
      set(original, "contract_id", "moonfind.decision-brief.v2").stringify(),
      set(original, "company_decision_recorded", true).stringify(),
      set(original, "evidence_status", "verified demand").stringify(),
      set(original, "worksheet", {}).stringify(),
    ] {
    assert_true(@research_handoff.decode(invalid) is Err(_))
  }
}

///|
test "missing selected option and malformed retained source or claim references reject" {
  let brief = parsed("current")
  let first = brief.worksheet.options[0]
  let second = brief.worksheet.options[1]
  let paper = brief.worksheet.evidence.papers[0]
  let summary = brief.worksheet.evidence.summaries[0]
  let claim = summary.claims[0]
  for
    sheet in [
      { ..brief.worksheet, chosen_option_id: "gone", },
      { ..brief.worksheet, options: [{ ..first, source_id: "gone", }, second], },
      { ..brief.worksheet, options: [{ ..first, claim_id: "gone", }, second], },
      { ..brief.worksheet, options: [first, { ..second, id: first.id, }], },
      {
        ..brief.worksheet,
        evidence: { ..brief.worksheet.evidence, papers: [paper, paper], },
      },
      {
        ..brief.worksheet,
        evidence: {
          ..brief.worksheet.evidence,
          summaries: [{ ..summary, paper_id: "gone", }],
        },
      },
      {
        ..brief.worksheet,
        evidence: {
          ..brief.worksheet.evidence,
          summaries: [
            { ..summary, claims: [{ ..claim, paper_ids: ["gone"], }], },
          ],
        },
      },
      {
        ..brief.worksheet,
        evidence: {
          ..brief.worksheet.evidence,
          summaries: [
            { ..summary, claims: [claim, { ..claim, statement: "changed", }], },
          ],
        },
      },
    ] {
    assert_true(
      @research_handoff.decode(
        ToJson::to_json({ ..brief, worksheet: sheet, }).stringify(),
      )
      is Err(_),
    )
  }
}

///|
test "input size bound rejects before parsing and optional source dates stay unknown" {
  assert_true(
    @research_handoff.decode(Array::make(2000001, "x").join("")) is Err(_),
  )
  let brief = parsed("current")
  let source = {
    ..brief.worksheet.evidence.papers[0],
    published_at: None,
    updated_at: None,
    retrieved_at: None,
  }
  let undated = {
    ..brief,
    worksheet: {
      ..brief.worksheet,
      evidence: { ..brief.worksheet.evidence, papers: [source], },
    },
  }
  guard @research_handoff.decode(ToJson::to_json(undated).stringify())
    is Ok(restored) else {
    fail("optional dates rejected")
  }
  assert_true(
    restored.markdown().contains("Retrieved (epoch milliseconds): Unknown"),
  )
}
