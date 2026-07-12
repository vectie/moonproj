///|
fn event_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-accounting-event",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn settlement_journal() -> @finance.JournalEntry {
  let amount = try! @finance.Money::new(minor=50000, currency="CNY")
  {
    entry_id: "settlement/settlement-001",
    description: "settlement",
    postings: [
      { account: "2202", side: @finance.PostingSide::Debit, amount },
      { account: "1002", side: @finance.PostingSide::Credit, amount },
    ],
  }
}

///|
test "accounting event log links a source event to a journal" {
  let event = AccountingEvent::new(
    event_id="event-001",
    principal_id="co-001",
    source_type="settlement",
    source_id="settlement-001",
    event_type="payment.released",
    journal=settlement_journal(),
  )
  let log = AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant=event_grant("accounting:event:append"),
  )
  assert_eq(log.events.length(), 1)
  assert_eq(log.events[0].source_id, "settlement-001")
}

///|
test "accounting event log rejects replay" {
  let event = AccountingEvent::new(
    event_id="event-002",
    principal_id="co-001",
    source_type="commitment",
    source_id="commitment-001",
    event_type="commitment.performed",
    journal=settlement_journal(),
  )
  let log = AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant=event_grant("accounting:event:append"),
  )
  try
    log.append(
      event,
      scope="project:p-001",
      actor_id="alice",
      grant=event_grant("accounting:event:append"),
    )
  catch {
    AccountingEventError::DuplicateEvent => ()
    _ => fail("wrong accounting event error")
  } noraise {
    _ => fail("expected accounting event error")
  }
}

///|
test "accounting event rejects an unbalanced source journal" {
  let amount = @finance.Money::new(minor=50000, currency="CNY")
  try
    AccountingEvent::new(
      event_id="event-003",
      principal_id="co-001",
      source_type="settlement",
      source_id="settlement-003",
      event_type="payment.released",
      journal={
        entry_id: "bad",
        description: "bad",
        postings: [
          { account: "1002", side: @finance.PostingSide::Debit, amount },
        ],
      },
    )
  catch {
    AccountingEventError::Journal(@finance.LedgerError::Unbalanced) => ()
    _ => fail("wrong accounting event error")
  } noraise {
    _ => fail("expected accounting event error")
  }
}

///|
test "accounting event log rejects a second event for the same source" {
  let event = AccountingEvent::new(
    event_id="event-source-001",
    principal_id="co-001",
    source_type="settlement",
    source_id="settlement-source-001",
    event_type="payment.released",
    journal=settlement_journal(),
  )
  let log = AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant=event_grant("accounting:event:append"),
  )
  try
    log.append(
      AccountingEvent::new(
        event_id="event-source-002",
        principal_id="co-001",
        source_type="settlement",
        source_id="settlement-source-001",
        event_type="payment.released",
        journal=settlement_journal(),
      ),
      scope="project:p-001",
      actor_id="alice",
      grant=event_grant("accounting:event:append"),
    )
  catch {
    AccountingEventError::DuplicateSource => ()
    _ => fail("wrong source replay error")
  } noraise {
    _ => fail("expected source replay error")
  }
}

///|
test "accounting event links persist as reconciliable envelopes" {
  let event = AccountingEvent::new(
    event_id="event-persist-001",
    principal_id="co-001",
    source_type="settlement",
    source_id="settlement-001",
    event_type="payment.released",
    journal=settlement_journal(),
  )
  let log = AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant=event_grant("accounting:event:append"),
  )
  let records = log.to_records(schema_version=1)
  assert_eq(records.length(), 1)
  assert_true(records[0].payload.contains("payment.released"))
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema)
    .migrate(migration)
    .append_batch(records)
  assert_eq(store.count_type(record_type="accounting_event"), 1)
}
