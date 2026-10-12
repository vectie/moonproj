///|
fn request_fixture(id : String) -> @agent_port.AgentRequest {
  {
    protocol_version: @agent_port.protocol_version(),
    request_id: "request-\{id}",
    work_item_id: "work-\{id}",
    flow_run_id: "engagement-001",
    principal_id: "opc-001",
    actor_id: "agent-001",
    capability: "professional-services.shadow.execute",
    scope: "engagement:engagement-001",
    coordination_mode: CompanyTopDown,
    authority_ceiling_minor: 0L,
    input_evidence: ["evidence/brief"],
    input_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    acceptance_criteria: ["output is evidenced"],
    expected_result_schema: "output.v1",
    prohibited_effects: @agent_port.reserved_company_effects(),
    idempotency_key: "key-\{id}",
  }
}

///|
fn attempt_in_phase(
  id : String,
  phase : @agent_port.ExecutionPhase,
) -> @agent_port.ExecutionAttempt raise {
  let ready = @agent_port.ExecutionAttempt::new(
    request_fixture(id),
    attempt_id="attempt-\{id}",
    at_epoch=1L,
  )
  let claimed = ready.claim(
    expected_revision=ready.revision,
    claim_token="claim-\{id}",
    executor_id="moonclaw-001",
    now_epoch=2L,
    lease_seconds=60L,
  )
  let running = claimed.transition(
    expected_revision=claimed.revision,
    to=Running,
    actor_id="moonclaw-001",
    claim_token="claim-\{id}",
    reason="execution started",
    at_epoch=3L,
  )
  if phase is Running {
    return running
  }
  running.transition(
    expected_revision=running.revision,
    to=phase,
    actor_id="moonclaw-001",
    claim_token="claim-\{id}",
    reason="projection fixture transition",
    at_epoch=4L,
  )
}

///|
test "execution projection turns human, review, failure, and quarantine into attention" {
  let review = attempt_in_phase("review", WaitingForReview)
  let human = attempt_in_phase("human", WaitingForHuman)
  let success = attempt_in_phase("success", Succeeded)
  let projection = project_execution_activity(
    [review, human, success],
    principal_id="opc-001",
    at_epoch=10L,
  )
  assert_eq(projection.total, 3)
  assert_eq(projection.review, 1)
  assert_eq(projection.waiting, 1)
  assert_eq(projection.succeeded, 1)
  assert_eq(projection.inbox.open_items().length(), 2)
}

///|
test "attention inbox deduplicates, acknowledges, and requires resolution evidence" {
  let item : AttentionItem = {
    attention_id: "attention-001",
    dedupe_key: "attempt:001:review",
    principal_id: "opc-001",
    source_kind: "execution-attempt",
    source_id: "attempt-001",
    work_item_id: "work-001",
    title: "Review required",
    reason: "output ready",
    requested_action: "review evidence",
    severity: Normal,
    amount_at_risk_minor: 0L,
    reversible: true,
    evidence: ["evidence/output"],
    status: Open,
    created_at_epoch: 1L,
    updated_at_epoch: 1L,
  }
  let inbox = AttentionInbox::new()
    .upsert(item)
    .upsert({
      ..item,
      attention_id: "duplicate-id",
      reason: "new reason",
      updated_at_epoch: 2L,
    })
  assert_eq(inbox.items.length(), 1)
  assert_eq(inbox.items[0].reason, "new reason")
  let resolved = inbox
    .acknowledge(attention_id="attention-001", at_epoch=3L)
    .resolve(
      attention_id="attention-001",
      resolution_evidence=["evidence/review-receipt"],
      at_epoch=4L,
    )
  assert_eq(resolved.open_items().length(), 0)
  assert_eq(resolved.items[0].status, Resolved)
}
