///|
fn evidence_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-evidence",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "evidence preserves provenance through verification and archive" {
  let evidence = Evidence::new(
      evidence_id="evidence-001",
      principal_id="co-001",
      scope="project:p-001",
      source_reference="inspection/report-001",
      media_type="application/pdf",
      content_hash="sha256:abc",
      actor_id="alice",
      grant=evidence_grant("evidence:attach"),
    )
    .verify(actor_id="alice", grant=evidence_grant("evidence:verify"))
    .archive(actor_id="alice", grant=evidence_grant("evidence:archive"))
  assert_true(evidence.state == EvidenceState::Archived)
  assert_eq(evidence.content_hash, "sha256:abc")
  assert_eq(evidence.events.length(), 2)
}

///|
test "audit trail is append-only and rejects replay" {
  let record : AuditRecord = {
    audit_id: "audit-001",
    principal_id: "co-001",
    actor_id: "alice",
    scope: "project:p-001",
    action: "progress.accept",
    target_type: "progress_report",
    target_id: "progress-001",
    outcome: "accepted",
    evidence_id: Some("evidence-001"),
  }
  let trail = AuditTrail::empty().append(
    record,
    grant=evidence_grant("audit:append"),
  )
  assert_eq(trail.records.length(), 1)
  try trail.append(record, grant=evidence_grant("audit:append")) catch {
    EvidenceError::DuplicateAudit => ()
    _ => fail("wrong audit error")
  } noraise {
    _ => fail("expected audit error")
  }
}

///|
test "evidence rejects an empty content hash" {
  try
    Evidence::new(
      evidence_id="evidence-002",
      principal_id="co-001",
      scope="project:p-001",
      source_reference="upload-002",
      media_type="image/png",
      content_hash="",
      actor_id="alice",
      grant=evidence_grant("evidence:attach"),
    )
  catch {
    EvidenceError::InvalidHash => ()
    _ => fail("wrong evidence error")
  } noraise {
    _ => fail("expected evidence error")
  }
}
