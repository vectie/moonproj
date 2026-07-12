///|
fn settlement_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-settlement",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
fn performed_commitment() -> @commitment.Commitment {
  let commitment = try! @commitment.Commitment::new(
    commitment_id="commit-settlement",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=try! @finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=settlement_grant("commitment:create"),
  )
  let submitted = try! commitment.transition(
    @commitment.CommitmentState::Submitted,
    actor_id="alice",
    grant=settlement_grant("commitment:submit"),
  )
  let approved = try! submitted.transition(
    @commitment.CommitmentState::Approved,
    actor_id="alice",
    grant=settlement_grant("commitment:approve"),
  )
  try! approved.transition(
    @commitment.CommitmentState::Performed,
    actor_id="alice",
    grant=settlement_grant("commitment:perform"),
  )
}

///|
test "settlement releases a performed commitment and journals payment" {
  let settlement = Settlement::request(
    performed_commitment(),
    settlement_id="settlement-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=settlement_grant("settlement:request"),
  )
  let approved = settlement.transition(
    SettlementState::Approved,
    actor_id="alice",
    grant=settlement_grant("settlement:approve"),
  )
  let released = approved.transition(
    SettlementState::Released,
    actor_id="alice",
    grant=settlement_grant("settlement:release"),
  )
  let journal = released.to_journal(payable_account="2202", cash_account="1002")
  assert_true(released.state == SettlementState::Released)
  assert_eq(journal.postings.length(), 2)
  @finance.validate_journal(journal)
}

///|
test "settlement cannot exceed the commitment" {
  try
    Settlement::request(
      performed_commitment(),
      settlement_id="settlement-002",
      amount=@finance.Money::new(minor=50001, currency="CNY"),
      actor_id="alice",
      grant=settlement_grant("settlement:request"),
    )
  catch {
    SettlementError::AmountExceedsCommitment => ()
    _ => fail("wrong settlement error")
  } noraise {
    _ => fail("expected settlement error")
  }
}

///|
test "released settlement creates an appendable accounting event link" {
  let released = Settlement::request(
      performed_commitment(),
      settlement_id="settlement-accounting",
      amount=@finance.Money::new(minor=50000, currency="CNY"),
      actor_id="alice",
      grant=settlement_grant("settlement:request"),
    )
    .transition(
      SettlementState::Approved,
      actor_id="alice",
      grant=settlement_grant("settlement:approve"),
    )
    .transition(
      SettlementState::Released,
      actor_id="alice",
      grant=settlement_grant("settlement:release"),
    )
  let event = released.to_accounting_event(
    event_id="event-settlement-accounting",
    event_type="payment.released",
    payable_account="2202",
    cash_account="1002",
  )
  assert_eq(event.source_type, "settlement")
  let log = @accounting.AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant=settlement_grant("accounting:event:append"),
  )
  assert_eq(log.events.length(), 1)
}

///|
test "settlement snapshots persist released payment state" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let requested = Settlement::request(
    performed_commitment(),
    settlement_id="settlement-projection",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant=settlement_grant("settlement:request"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="settlement",
    aggregate_id="settlement-projection",
  )
  let projection = requested.append_projection(projection)
  let released = requested
    .transition(
      SettlementState::Approved,
      actor_id="alice",
      grant=settlement_grant("settlement:approve"),
    )
    .transition(
      SettlementState::Released,
      actor_id="alice",
      grant=settlement_grant("settlement:release"),
    )
  let projection = released.append_projection(projection)
  assert_eq(projection.revision, 2)
  match projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("released"))
    None => fail("expected settlement projection")
  }
}
