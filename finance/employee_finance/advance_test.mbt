///|
fn advance_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-advance",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "employee:employee-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "employee advance repayment persists a projection" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let advance = EmployeeAdvance::new(
    advance_id="advance-projection",
    principal_id="co-001",
    employee_id="employee-001",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    actor_id="alice",
    grant=advance_grant("advance:create"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="employee_advance",
    aggregate_id="advance-projection",
  )
  let projection = advance.append_projection(projection)
  let repaid = advance.offset(
    amount_minor=20000,
    actor_id="alice",
    grant=advance_grant("advance:offset"),
  )
  let projection = repaid.append_projection(projection)
  match projection.latest() {
    Some(latest) => assert_true(latest.payload.contains("repaid"))
    None => fail("expected advance projection")
  }
}

///|
test "employee advance builds a separate opening accounting link" {
  let advance = EmployeeAdvance::new(
    advance_id="advance-accounting",
    principal_id="co-001",
    employee_id="employee-001",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    actor_id="alice",
    grant=advance_grant("advance:create"),
  )
  let event = advance.to_accounting_event(
    event_id="event-advance-accounting",
    event_type="advance.issued",
    advance_account="employee-advances",
    cash_account="cash",
  )
  assert_eq(event.source_type, "employee_advance")
  assert_eq(event.source_id, "advance-accounting")
  assert_eq(event.journal.postings.length(), 2)
  let log = @accounting.AccountingEventLog::empty().append(
    event,
    scope="employee:employee-001",
    actor_id="alice",
    grant=advance_grant("accounting:event:append"),
  )
  assert_eq(log.events.length(), 1)
}

///|
test "employee advance offset builds a distinct expense link" {
  let advance = EmployeeAdvance::new(
    advance_id="advance-offset-accounting",
    principal_id="co-001",
    employee_id="employee-001",
    amount=@finance.Money::new(minor=20000, currency="CNY"),
    actor_id="alice",
    grant=advance_grant("advance:create"),
  )
  let event = advance.to_offset_accounting_event(
    offset_id="offset-001",
    amount_minor=5000,
    event_id="event-advance-offset",
    event_type="advance.offset",
    expense_account="travel-expense",
    advance_account="employee-advances",
  )
  assert_eq(event.source_type, "employee_advance_offset")
  assert_eq(event.source_id, "offset-001")
  assert_eq(event.journal.postings[0].amount.minor, 5000)
}
