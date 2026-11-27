///|
test "execution attempt claims, runs, records evidence and succeeds" {
  let ready = @agent_port.ExecutionAttempt::new(
    execution_request(),
    attempt_id="attempt-001",
    at_epoch=100,
  )
  let claimed = ready.claim(
    expected_revision=1,
    claim_token="claim-001",
    executor_id="moonclaw:delivery-agent",
    now_epoch=110,
    lease_seconds=30,
  )
  assert_true(claimed.phase is Claimed)
  assert_eq(claimed.attempt_number, 1)
  let running = claimed.transition(
    expected_revision=2,
    to=Running,
    actor_id="moonclaw:delivery-agent",
    claim_token="claim-001",
    reason="execution started",
    at_epoch=111,
  )
  let with_artifact = running.record_artifact(
    expected_revision=3,
    artifact_ref="artifact:deliverable-001",
  )
  let with_cost = with_artifact.record_cost(
    expected_revision=4,
    additional_minor=250,
  )
  let succeeded = with_cost.transition(
    expected_revision=5,
    to=Succeeded,
    actor_id="moonclaw:delivery-agent",
    claim_token="claim-001",
    reason="acceptance packet prepared",
    at_epoch=120,
  )
  assert_true(succeeded.phase.is_terminal())
  assert_eq(succeeded.artifact_refs, ["artifact:deliverable-001"])
  assert_eq(succeeded.cost_minor, 250L)
  assert_true(succeeded.claim is None)
}

///|
test "expired active claim becomes dispatchable without becoming company success" {
  let ready = @agent_port.ExecutionAttempt::new(
    execution_request(),
    attempt_id="attempt-recover",
    at_epoch=100,
  )
  let claimed = ready.claim(
    expected_revision=1,
    claim_token="claim-recover",
    executor_id="moonflow:worker",
    now_epoch=110,
    lease_seconds=10,
  )
  let running = claimed.transition(
    expected_revision=2,
    to=Running,
    actor_id="moonflow:worker",
    claim_token="claim-recover",
    reason="execution started",
    at_epoch=111,
  )
  let recovered = running.recover_expired_claim(
    expected_revision=3,
    now_epoch=121,
  )
  assert_true(recovered.phase is Ready)
  assert_true(recovered.phase.is_dispatchable())
  assert_eq(recovered.interrupted_streak, 1)
  assert_true(recovered.claim is None)
}

///|
test "three consecutive crashes quarantine an attempt" {
  let initial = @agent_port.ExecutionAttempt::new(
    execution_request(),
    attempt_id="attempt-crash",
    at_epoch=100,
  )
  let claim1 = initial.claim(
    expected_revision=1,
    claim_token="claim-1",
    executor_id="moonclaw:worker",
    now_epoch=101,
    lease_seconds=10,
  )
  let crash1 = claim1.record_crash(
    expected_revision=2,
    claim_token="claim-1",
    at_epoch=102,
    reason="provider crash",
  )
  let claim2 = crash1.claim(
    expected_revision=3,
    claim_token="claim-2",
    executor_id="moonclaw:worker",
    now_epoch=103,
    lease_seconds=10,
  )
  let crash2 = claim2.record_crash(
    expected_revision=4,
    claim_token="claim-2",
    at_epoch=104,
    reason="provider crash",
  )
  let claim3 = crash2.claim(
    expected_revision=5,
    claim_token="claim-3",
    executor_id="moonclaw:worker",
    now_epoch=105,
    lease_seconds=10,
  )
  let crash3 = claim3.record_crash(
    expected_revision=6,
    claim_token="claim-3",
    at_epoch=106,
    reason="provider crash",
  )
  assert_true(crash3.phase is Quarantined)
  assert_eq(crash3.crash_streak, 3)
  assert_false(crash3.phase.is_dispatchable())
}

///|
test "review rework opens a new claimable round" {
  let ready = @agent_port.ExecutionAttempt::new(
    execution_request(),
    attempt_id="attempt-review",
    at_epoch=100,
  )
  let claimed = ready.claim(
    expected_revision=1,
    claim_token="claim-review",
    executor_id="moonclaw:worker",
    now_epoch=101,
    lease_seconds=20,
  )
  let running = claimed.transition(
    expected_revision=2,
    to=Running,
    actor_id="moonclaw:worker",
    claim_token="claim-review",
    reason="execution started",
    at_epoch=102,
  )
  let review = running.transition(
    expected_revision=3,
    to=WaitingForReview,
    actor_id="moonclaw:worker",
    claim_token="claim-review",
    reason="artifact ready for independent review",
    at_epoch=103,
  )
  assert_true(review.claim is None)
  let rework = review.request_rework(
    expected_revision=4,
    reviewer_id="owner",
    reason="missing customer citation",
    at_epoch=104,
  )
  assert_true(rework.phase is ReadyForRework)
  assert_eq(rework.rework_round, 1)
}

///|
test "stale revision and mismatched claim fail closed" {
  let ready = @agent_port.ExecutionAttempt::new(
    execution_request(),
    attempt_id="attempt-cas",
    at_epoch=100,
  )
  try
    ready.claim(
      expected_revision=0,
      claim_token="claim-cas",
      executor_id="moonclaw:worker",
      now_epoch=101,
      lease_seconds=10,
    )
  catch {
    RevisionConflict(expected=0, actual=1) => ()
    _ => fail("expected revision conflict")
  } noraise {
    _ => fail("stale compare-and-set must fail")
  }
  let claimed = ready.claim(
    expected_revision=1,
    claim_token="claim-cas",
    executor_id="moonclaw:worker",
    now_epoch=101,
    lease_seconds=10,
  )
  try
    claimed.transition(
      expected_revision=2,
      to=Running,
      actor_id="moonclaw:worker",
      claim_token="wrong-claim",
      reason="must not run",
      at_epoch=102,
    )
  catch {
    ClaimMismatch => ()
    _ => fail("expected claim mismatch")
  } noraise {
    _ => fail("wrong claim token must fail")
  }
}
