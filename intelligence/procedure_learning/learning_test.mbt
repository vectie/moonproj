///|
fn candidate_fixture() -> ProcedureCandidate raise {
  ProcedureCandidate::observe(
    candidate_id="candidate-001",
    principal_id="opc-001",
    workflow_kind="professional-service-shadow",
    proposed_by="agent-lead",
    source_attempt_ids=["attempt-001", "attempt-002"],
    source_evidence=["evidence/outcome-001"],
    applicability="market-entry briefs with an accepted customer scope",
    steps=[
      {
        step_id: "step-research",
        capability: "professional-services.shadow.execute",
        instruction: "Research each material claim against accepted sources",
        acceptance_criteria: ["every material claim has a citation"],
        evidence_required: ["research-note", "citation-map"],
      },
    ],
  )
}

///|
test "procedure learning requires validation and independent acceptance before adoption" {
  let candidate = candidate_fixture()
    .propose()
    .start_review()
    .record_validation(receipt="validation/replay-001")
    .review({
      review_id: "review-001",
      reviewer_id: "reviewer-independent",
      decision: Accept,
      rationale: "replay met every acceptance criterion",
      evidence: ["evidence/review-001"],
      reviewed_at_epoch: 10L,
    })
    .approve()
  let library = ProcedureLibrary::new().adopt(
    candidate,
    procedure_id="procedure-market-brief-001",
  )
  assert_eq(library.procedures.length(), 1)
  assert_eq(library.procedures[0].activated_count, 0)
  assert_true(!library.procedures[0].authority_expansion_allowed)
  assert_true(
    library.procedures[0].approval_evidence.contains("validation/replay-001"),
  )
}

///|
test "procedure learning rejects self-review and unvalidated promotion" {
  let candidate = candidate_fixture().propose().start_review()
  try
    candidate.review({
      review_id: "review-self",
      reviewer_id: "agent-lead",
      decision: Accept,
      rationale: "self approval",
      evidence: ["evidence/self"],
      reviewed_at_epoch: 10L,
    })
  catch {
    SelfReview => ()
    _ => fail("expected self-review rejection")
  } noraise {
    _ => fail("expected self-review to fail")
  }
  let reviewed = candidate.review({
    review_id: "review-independent",
    reviewer_id: "reviewer-independent",
    decision: Accept,
    rationale: "looks reusable",
    evidence: ["evidence/review"],
    reviewed_at_epoch: 11L,
  })
  try reviewed.approve() catch {
    ValidationRequired => ()
    _ => fail("expected validation requirement")
  } noraise {
    _ => fail("expected unvalidated approval to fail")
  }
}
