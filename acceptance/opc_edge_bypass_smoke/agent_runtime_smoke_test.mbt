///|
test "fake runtime completes bounded work without company authority" {
  let request : @agent_port.AgentRequest = {
    protocol_version: @agent_port.protocol_version(),
    request_id: "request-smoke-market-brief",
    work_item_id: "produce-market-brief",
    flow_run_id: "flow-smoke-market-brief",
    principal_id: "opc-market-studio",
    actor_id: "agent-producer",
    capability: "professional-service:artifact:produce",
    scope: "engagement:smoke-market-brief",
    coordination_mode: CompanyTopDown,
    authority_ceiling_minor: 20000L,
    input_evidence: ["evidence/market-size", "evidence/customer-interviews"],
    input_digest: smoke_sha256("bounded smoke input"),
    acceptance_criteria: [
      "artifact uses market-entry-brief@1", "recommendation is independently reviewable",
    ],
    expected_result_schema: "market-entry-brief@1",
    prohibited_effects: @agent_port.reserved_company_effects(),
    idempotency_key: "agent-smoke/produce-market-brief/v1",
  }
  request.validate()
  assert_true(request.protects_reserved_effects())
  let ready = @agent_port.ExecutionAttempt::new(
    request,
    attempt_id="attempt-smoke-market-brief",
    at_epoch=1000L,
  )
  let claimed = ready.claim(
    expected_revision=ready.revision,
    claim_token="sandbox-claim-market-brief",
    executor_id="fake-moonclaw-runtime",
    now_epoch=1001L,
    lease_seconds=300L,
  )
  let running = claimed.transition(
    expected_revision=claimed.revision,
    to=Running,
    actor_id="fake-moonclaw-runtime",
    claim_token="sandbox-claim-market-brief",
    reason="sandbox provider accepted bounded work",
    at_epoch=1002L,
  )
  let artifact = render_smoke_brief(
    "artifact-runtime-smoke-v1",
    "Runtime-produced Market Brief",
    "go",
    ["evidence/market-size", "evidence/customer-interviews"],
  )
  let evidenced = running.record_artifact(
    expected_revision=running.revision,
    artifact_ref=artifact.content_digest,
  )
  let costed = evidenced.record_cost(
    expected_revision=evidenced.revision,
    additional_minor=16000L,
  )
  let waiting = costed.transition(
    expected_revision=costed.revision,
    to=WaitingForReview,
    actor_id="fake-moonclaw-runtime",
    claim_token="sandbox-claim-market-brief",
    reason="sandbox artifact ready for independent review",
    at_epoch=1003L,
  )
  let completed = waiting.transition(
    expected_revision=waiting.revision,
    to=Succeeded,
    actor_id="independent-reviewer",
    reason="artifact schema and evidence accepted",
    at_epoch=1004L,
  )
  assert_eq(completed.phase, Succeeded)
  assert_eq(completed.cost_minor, 16000L)
  assert_eq(completed.artifact_refs, [artifact.content_digest])
}
