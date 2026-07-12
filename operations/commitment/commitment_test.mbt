///|
fn grant_for(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-001",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "commitment follows contract to settlement" {
  let amount = @finance.Money::new(minor=50000, currency="CNY")
  let draft = Commitment::new(
    commitment_id="commit-001",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount~,
    actor_id="alice",
    grant=grant_for("commitment:create"),
  )
  let submitted = draft.transition(
    CommitmentState::Submitted,
    actor_id="alice",
    grant=grant_for("commitment:submit"),
  )
  let approved = submitted.transition(
    CommitmentState::Approved,
    actor_id="alice",
    grant=grant_for("commitment:approve"),
  )
  let performed = approved.transition(
    CommitmentState::Performed,
    actor_id="alice",
    grant=grant_for("commitment:perform"),
  )
  let settled = performed.transition(
    CommitmentState::Settled,
    actor_id="alice",
    grant=grant_for("commitment:settle"),
  )
  assert_true(settled.state == CommitmentState::Settled)
  assert_true(settled.is_terminal())
  assert_eq(settled.events.length(), 4)
}

///|
test "commitment rejects an invalid transition" {
  let draft = Commitment::new(
    commitment_id="commit-002",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=grant_for("commitment:create"),
  )
  try
    draft.transition(
      CommitmentState::Performed,
      actor_id="alice",
      grant=grant_for("commitment:perform"),
    )
  catch {
    CommitmentError::InvalidStateTransition => ()
    _ => fail("wrong commitment error")
  } noraise {
    _ => fail("expected commitment error")
  }
}

///|
test "commitment transitions append durable aggregate projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let draft = Commitment::new(
    commitment_id="commit-projection",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=grant_for("commitment:create"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="commitment",
    aggregate_id="commit-projection",
  )
  let projection = draft.append_projection(projection)
  let performed = draft
    .transition(
      CommitmentState::Submitted,
      actor_id="alice",
      grant=grant_for("commitment:submit"),
    )
    .transition(
      CommitmentState::Approved,
      actor_id="alice",
      grant=grant_for("commitment:approve"),
    )
    .transition(
      CommitmentState::Performed,
      actor_id="alice",
      grant=grant_for("commitment:perform"),
    )
  let projection = performed.append_projection(projection)
  assert_eq(projection.revision, 2)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("performed"))
      assert_eq(
        latest.source_event_id,
        "company:commitment:commit-projection:r2",
      )
    }
    None => fail("expected commitment projection")
  }
}
