///|
fn milestone_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-milestone",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn performed_commitment_for_milestone() -> @commitment.Commitment raise @commitment.CommitmentError {
  let commitment = @commitment.Commitment::new(
    commitment_id="commit-milestone",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=try! @finance.Money::new(minor=500000, currency="CNY"),
    actor_id="alice",
    grant=milestone_grant("commitment:create"),
  )
  let submitted = commitment.transition(
    @commitment.CommitmentState::Submitted,
    actor_id="alice",
    grant=milestone_grant("commitment:submit"),
  )
  let approved = submitted.transition(
    @commitment.CommitmentState::Approved,
    actor_id="alice",
    grant=milestone_grant("commitment:approve"),
  )
  approved.transition(
    @commitment.CommitmentState::Performed,
    actor_id="alice",
    grant=milestone_grant("commitment:perform"),
  )
}

///|
test "contract milestone follows planned work to payment" {
  let milestone = ContractMilestone::new(
      performed_commitment_for_milestone(),
      milestone_id="milestone-001",
      sequence=1,
      node_name="Structural completion",
      trigger=MilestoneTrigger::Progress,
      plan_amount=@finance.Money::new(minor=200000, currency="CNY"),
      plan_pct_bps=4000L,
      actor_id="alice",
      grant=milestone_grant("milestone:create"),
    )
    .mark_eligible(
      actor_id="alice",
      grant=milestone_grant("milestone:eligible"),
    )
    .reach(
      actual_amount=@finance.Money::new(minor=190000, currency="CNY"),
      actor_id="alice",
      grant=milestone_grant("milestone:reach"),
    )
    .mark_paid(actor_id="alice", grant=milestone_grant("milestone:pay"))
  assert_true(milestone.state == MilestoneState::Paid)
  assert_eq(milestone.actual_amount.minor, 190000L)
  assert_eq(milestone.events.length(), 3)
}

///|
test "reached milestone links to a requested settlement without releasing cash" {
  let commitment = performed_commitment_for_milestone()
  let milestone = ContractMilestone::new(
      commitment,
      milestone_id="milestone-settlement",
      sequence=1,
      node_name="Structural completion",
      trigger=MilestoneTrigger::Progress,
      plan_amount=@finance.Money::new(minor=200000, currency="CNY"),
      plan_pct_bps=4000L,
      actor_id="alice",
      grant=milestone_grant("milestone:create"),
    )
    .mark_eligible(
      actor_id="alice",
      grant=milestone_grant("milestone:eligible"),
    )
    .reach(
      actual_amount=@finance.Money::new(minor=190000, currency="CNY"),
      actor_id="alice",
      grant=milestone_grant("milestone:reach"),
    )
  let settlement = milestone.request_settlement(
    commitment,
    settlement_id="settlement-from-milestone",
    actor_id="alice",
    milestone_grant=milestone_grant("milestone:settlement-request"),
    settlement_grant=milestone_grant("settlement:request"),
  )
  assert_true(settlement.state == @settlement.SettlementState::Requested)
  assert_true(settlement.milestone_id == Some("milestone-settlement"))
  assert_eq(settlement.amount.minor, 190000L)
}

///|
test "milestone-to-settlement link survives separate aggregate projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let commitment = performed_commitment_for_milestone()
  let milestone = ContractMilestone::new(
      commitment,
      milestone_id="milestone-projection-link",
      sequence=1,
      node_name="Structural completion",
      trigger=MilestoneTrigger::Progress,
      plan_amount=@finance.Money::new(minor=200000, currency="CNY"),
      plan_pct_bps=4000L,
      actor_id="alice",
      grant=milestone_grant("milestone:create"),
    )
    .mark_eligible(
      actor_id="alice",
      grant=milestone_grant("milestone:eligible"),
    )
    .reach(
      actual_amount=@finance.Money::new(minor=190000, currency="CNY"),
      actor_id="alice",
      grant=milestone_grant("milestone:reach"),
    )
  let milestone_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="contract_milestone",
    aggregate_id="milestone-projection-link",
  )
  let milestone_projection = milestone.append_projection(milestone_projection)
  let settlement = milestone.request_settlement(
    commitment,
    settlement_id="settlement-projection-link",
    actor_id="alice",
    milestone_grant=milestone_grant("milestone:settlement-request"),
    settlement_grant=milestone_grant("settlement:request"),
  )
  let settlement_projection = @store.AggregateProjection::new(
    milestone_projection.into_store(),
    aggregate_type="settlement",
    aggregate_id="settlement-projection-link",
  )
  let settlement_projection = settlement.append_projection(
    settlement_projection,
  )
  match settlement_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("settlement-projection-link"))
      assert_true(latest.payload.contains("milestone-projection-link"))
      assert_true(latest.payload.contains("requested"))
    }
    None => fail("expected settlement projection")
  }
}

///|
test "contract milestone rejects an amount above its plan" {
  let milestone = ContractMilestone::new(
    performed_commitment_for_milestone(),
    milestone_id="milestone-002",
    sequence=1,
    node_name="Handover",
    trigger=MilestoneTrigger::Event,
    plan_amount=@finance.Money::new(minor=100000, currency="CNY"),
    plan_pct_bps=2000L,
    actor_id="alice",
    grant=milestone_grant("milestone:create"),
  ).mark_eligible(actor_id="alice", grant=milestone_grant("milestone:eligible"))
  try
    milestone.reach(
      actual_amount=@finance.Money::new(minor=100001, currency="CNY"),
      actor_id="alice",
      grant=milestone_grant("milestone:reach"),
    )
  catch {
    MilestoneError::AmountExceedsCommitment => ()
    _ => fail("wrong milestone error")
  } noraise {
    _ => fail("expected milestone error")
  }
}

///|
test "contract milestone persists planned and reached amounts" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let milestone = ContractMilestone::new(
      performed_commitment_for_milestone(),
      milestone_id="milestone-projection",
      sequence=1,
      node_name="Handover",
      trigger=MilestoneTrigger::Progress,
      plan_amount=@finance.Money::new(minor=200000, currency="CNY"),
      plan_pct_bps=4000L,
      actor_id="alice",
      grant=milestone_grant("milestone:create"),
    )
    .mark_eligible(
      actor_id="alice",
      grant=milestone_grant("milestone:eligible"),
    )
    .reach(
      actual_amount=@finance.Money::new(minor=190000, currency="CNY"),
      actor_id="alice",
      grant=milestone_grant("milestone:reach"),
    )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="contract_milestone",
    aggregate_id="milestone-projection",
  )
  let projection = milestone.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("reached"))
      assert_true(latest.payload.contains("190000"))
    }
    None => fail("expected milestone projection")
  }
}
