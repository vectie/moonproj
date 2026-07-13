///|
fn tax_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-tax",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "tax obligation calculates, files, and pays" {
  let obligation = TaxObligation::new(
    tax_id="tax-001",
    principal_id="co-001",
    project_scope="project:p-001",
    source_reference="invoice/inv-001",
    jurisdiction="CN-SH",
    category="VAT",
    base_amount=@finance.Money::new(minor=100000, currency="CNY"),
    tax_rate_bps=1300L,
    withholding_rate_bps=0L,
    actor_id="alice",
    grant=tax_grant("tax:create"),
  )
  let calculated = obligation.calculate(
    actor_id="alice",
    grant=tax_grant("tax:calculate"),
  )
  assert_eq(calculated.tax_amount.minor, 13000L)
  let reviewed = calculated.transition(
    TaxObligationState::Reviewed,
    actor_id="alice",
    grant=tax_grant("tax:review"),
  )
  let event = reviewed.to_accounting_event(
    event_id="tax-event-001",
    event_type="tax.reviewed",
    tax_expense_account="tax-expense",
    tax_payable_account="tax-payable",
  )
  assert_eq(event.source_type, "tax_obligation")
  assert_eq(event.journal.postings[0].amount.minor, 13000L)
  let filed = reviewed.transition(
    TaxObligationState::Filed,
    actor_id="alice",
    grant=tax_grant("tax:file"),
  )
  let paid = filed.transition(
    TaxObligationState::Paid,
    actor_id="alice",
    grant=tax_grant("tax:pay"),
  )
  assert_true(paid.state == TaxObligationState::Paid)
  assert_eq(paid.events.length(), 4)
}

///|
test "tax accounting link requires reviewed positive tax" {
  let calculated = TaxObligation::new(
    tax_id="tax-event-gate",
    principal_id="co-001",
    project_scope="project:p-001",
    source_reference="invoice/inv-event-gate",
    jurisdiction="CN-SH",
    category="VAT",
    base_amount=@finance.Money::new(minor=100000, currency="CNY"),
    tax_rate_bps=1300L,
    withholding_rate_bps=0L,
    actor_id="alice",
    grant=tax_grant("tax:create"),
  ).calculate(actor_id="alice", grant=tax_grant("tax:calculate"))
  try
    calculated.to_accounting_event(
      event_id="tax-event-gate-001",
      event_type="tax.calculated",
      tax_expense_account="tax-expense",
      tax_payable_account="tax-payable",
    )
  catch {
    TaxError::InvalidTransition => ()
    _ => fail("wrong tax accounting gate")
  } noraise {
    _ => fail("expected tax accounting gate")
  }
}

///|
test "tax accounting link rejects a zero calculated amount" {
  let reviewed = TaxObligation::new(
      tax_id="tax-event-zero",
      principal_id="co-001",
      project_scope="project:p-001",
      source_reference="invoice/inv-event-zero",
      jurisdiction="CN-SH",
      category="VAT",
      base_amount=@finance.Money::new(minor=100000, currency="CNY"),
      tax_rate_bps=0L,
      withholding_rate_bps=0L,
      actor_id="alice",
      grant=tax_grant("tax:create"),
    )
    .calculate(actor_id="alice", grant=tax_grant("tax:calculate"))
    .transition(
      TaxObligationState::Reviewed,
      actor_id="alice",
      grant=tax_grant("tax:review"),
    )
  try
    reviewed.to_accounting_event(
      event_id="tax-event-zero-001",
      event_type="tax.reviewed",
      tax_expense_account="tax-expense",
      tax_payable_account="tax-payable",
    )
  catch {
    TaxError::InvalidAmount => ()
    _ => fail("wrong zero-tax accounting error")
  } noraise {
    _ => fail("expected zero-tax accounting error")
  }
}

///|
test "tax obligation rejects rates outside the jurisdiction range" {
  try
    TaxObligation::new(
      tax_id="tax-002",
      principal_id="co-001",
      project_scope="project:p-001",
      source_reference="invoice/inv-002",
      jurisdiction="CN-SH",
      category="VAT",
      base_amount=@finance.Money::new(minor=100, currency="CNY"),
      tax_rate_bps=10001L,
      withholding_rate_bps=0L,
      actor_id="alice",
      grant=tax_grant("tax:create"),
    )
  catch {
    TaxError::InvalidRate => ()
    _ => fail("wrong tax error")
  } noraise {
    _ => fail("expected tax error")
  }
}

///|
test "tax filing has separate submission lifecycle and projection" {
  let reviewed = TaxObligation::new(
      tax_id="tax-filing-001",
      principal_id="co-001",
      project_scope="project:p-001",
      source_reference="invoice/inv-filing-001",
      jurisdiction="CN-SH",
      category="VAT",
      base_amount=@finance.Money::new(minor=100000, currency="CNY"),
      tax_rate_bps=1300L,
      withholding_rate_bps=0L,
      actor_id="alice",
      grant=tax_grant("tax:create"),
    )
    .calculate(actor_id="alice", grant=tax_grant("tax:calculate"))
    .transition(
      TaxObligationState::Reviewed,
      actor_id="alice",
      grant=tax_grant("tax:review"),
    )
  let filing = reviewed.prepare_filing(
    filing_id="filing-001",
    filing_period="2026-Q1",
    authority_reference="tax-authority-draft-001",
    actor_id="alice",
    grant=tax_grant("tax:filing:prepare"),
  )
  let filing = filing
    .transition(
      TaxFilingState::Submitted,
      actor_id="alice",
      grant=tax_grant("tax:filing:submit"),
    )
    .transition(
      TaxFilingState::Accepted,
      actor_id="alice",
      grant=tax_grant("tax:filing:accept"),
    )
  assert_true(filing.state == TaxFilingState::Accepted)
  assert_eq(filing.reported_tax_amount.minor, 13000L)
  assert_true(reviewed.state == TaxObligationState::Reviewed)
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="tax_filing",
    aggregate_id="filing-001",
  )
  let projection = filing.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("2026-Q1"))
      assert_true(latest.payload.contains("accepted"))
    }
    None => fail("expected tax filing projection")
  }
}

///|
test "tax filing requires reviewed obligation" {
  let calculated = TaxObligation::new(
    tax_id="tax-filing-002",
    principal_id="co-001",
    project_scope="project:p-001",
    source_reference="invoice/inv-filing-002",
    jurisdiction="CN-SH",
    category="VAT",
    base_amount=@finance.Money::new(minor=100000, currency="CNY"),
    tax_rate_bps=1300L,
    withholding_rate_bps=0L,
    actor_id="alice",
    grant=tax_grant("tax:create"),
  ).calculate(actor_id="alice", grant=tax_grant("tax:calculate"))
  try
    calculated.prepare_filing(
      filing_id="filing-002",
      filing_period="2026-Q1",
      authority_reference="tax-authority-draft-002",
      actor_id="alice",
      grant=tax_grant("tax:filing:prepare"),
    )
  catch {
    TaxError::InvalidFilingState => ()
    _ => fail("wrong tax filing error")
  } noraise {
    _ => fail("expected reviewed tax filing gate")
  }
}

///|
test "tax obligation persists calculated and filed evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let calculated = TaxObligation::new(
    tax_id="tax-projection",
    principal_id="co-001",
    project_scope="project:p-001",
    source_reference="invoice/inv-projection",
    jurisdiction="CN-SH",
    category="VAT",
    base_amount=@finance.Money::new(minor=100000, currency="CNY"),
    tax_rate_bps=1300L,
    withholding_rate_bps=0L,
    actor_id="alice",
    grant=tax_grant("tax:create"),
  ).calculate(actor_id="alice", grant=tax_grant("tax:calculate"))
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="tax_obligation",
    aggregate_id="tax-projection",
  )
  let projection = calculated.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("13000"))
      assert_true(latest.payload.contains("calculated"))
    }
    None => fail("expected tax projection")
  }
}
