///|
fn expense_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "expense-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope,
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "expense allocates and offsets an employee advance" {
  let amount = @finance.Money::new(minor=30000, currency="CNY")
  let expense = ExpenseClaim::new(
    expense_id="expense-001",
    principal_id="co-001",
    employee_id="alice",
    amount~,
    allocations=[
      {
        project_scope: "project:p-001",
        cost_subject: "travel",
        amount: @finance.Money::new(minor=20000, currency="CNY"),
      },
      {
        project_scope: "project:p-001",
        cost_subject: "meals",
        amount: @finance.Money::new(minor=10000, currency="CNY"),
      },
    ],
    actor_id="alice",
    grant=expense_grant("expense:create", "employee:alice"),
  )
  let submitted = expense.transition(
    ExpenseState::Submitted,
    actor_id="alice",
    grant=expense_grant("expense:submit", "employee:alice"),
  )
  let approved = submitted.transition(
    ExpenseState::Approved,
    actor_id="alice",
    grant=expense_grant("expense:approve", "employee:alice"),
  )
  let advance = @employee_finance.EmployeeAdvance::new(
    advance_id="advance-001",
    principal_id="co-001",
    employee_id="alice",
    amount=@finance.Money::new(minor=30000, currency="CNY"),
    actor_id="alice",
    grant=expense_grant("advance:create", "employee:alice"),
  )
  let (offset, repaid) = approved.offset_advance(
    advance,
    amount_minor=30000,
    actor_id="alice",
    expense_grant=expense_grant("expense:offset", "employee:alice"),
    advance_grant=expense_grant("advance:offset", "employee:alice"),
  )
  assert_eq(offset.offset_minor, 30000)
  assert_true(repaid.state == @employee_finance.AdvanceState::Repaid)
}

///|
test "expense rejects allocation mismatch" {
  try
    ExpenseClaim::new(
      expense_id="expense-002",
      principal_id="co-001",
      employee_id="alice",
      amount=@finance.Money::new(minor=30000, currency="CNY"),
      allocations=[
        {
          project_scope: "project:p-001",
          cost_subject: "travel",
          amount: @finance.Money::new(minor=20000, currency="CNY"),
        },
      ],
      actor_id="alice",
      grant=expense_grant("expense:create", "employee:alice"),
    )
  catch {
    ExpenseError::AllocationTotalMismatch => ()
    _ => fail("wrong expense error")
  } noraise {
    _ => fail("expected expense error")
  }
}

///|
test "expense offset and recognition persist allocation evidence" {
  let amount = @finance.Money::new(minor=30000, currency="CNY")
  let expense = ExpenseClaim::new(
      expense_id="expense-projection",
      principal_id="co-001",
      employee_id="alice",
      amount~,
      allocations=[
        {
          project_scope: "project:p-001",
          cost_subject: "travel",
          amount: @finance.Money::new(minor=30000, currency="CNY"),
        },
      ],
      actor_id="alice",
      grant=expense_grant("expense:create", "employee:alice"),
    )
    .transition(
      ExpenseState::Submitted,
      actor_id="alice",
      grant=expense_grant("expense:submit", "employee:alice"),
    )
    .transition(
      ExpenseState::Approved,
      actor_id="alice",
      grant=expense_grant("expense:approve", "employee:alice"),
    )
  let journal = expense.to_recognition_journal(
    expense_account="6602",
    payable_account="2202",
  )
  @finance.validate_journal(journal)
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let projection = @store.AggregateProjection::new(
    @store.RecordStore::new(schema).migrate(migration),
    aggregate_type="expense_claim",
    aggregate_id="expense-projection",
  )
  let projection = expense.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("offset_minor"))
      assert_true(latest.payload.contains("travel"))
    }
    None => fail("expected expense projection")
  }
}

///|
test "approved expense creates a source accounting event" {
  let expense = ExpenseClaim::new(
      expense_id="expense-accounting",
      principal_id="co-001",
      employee_id="alice",
      amount=@finance.Money::new(minor=30000, currency="CNY"),
      allocations=[
        {
          project_scope: "project:p-001",
          cost_subject: "travel",
          amount: @finance.Money::new(minor=30000, currency="CNY"),
        },
      ],
      actor_id="alice",
      grant=expense_grant("expense:create", "employee:alice"),
    )
    .transition(
      ExpenseState::Submitted,
      actor_id="alice",
      grant=expense_grant("expense:submit", "employee:alice"),
    )
    .transition(
      ExpenseState::Approved,
      actor_id="alice",
      grant=expense_grant("expense:approve", "employee:alice"),
    )
  let event = expense.to_accounting_event(
    event_id="event-expense-accounting",
    event_type="expense.approved",
    expense_account="6602",
    payable_account="2202",
  )
  assert_eq(event.source_type, "expense_claim")
  assert_eq(event.source_id, "expense-accounting")
}
