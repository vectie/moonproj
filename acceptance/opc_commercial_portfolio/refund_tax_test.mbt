///|
test "partial customer refund is bounded and independently approved" {
  let scope = "engagement:delta-refund"
  let customer = @sales.Customer::new(
    customer_id="customer-delta",
    principal_id="opc-market-studio",
    project_scope=scope,
    customer_code="DELTA",
    name="Delta Ventures",
    contact_reference="crm/customer-delta",
    actor_id="founder",
    grant=portfolio_authority(
      "grant-customer-delta-create", "founder", "sales:customer:create", scope, 0L,
    ),
  )
  let requested = @sales.RefundRequest::new(
    refund_id="refund-delta-partial",
    contract_id="sale-delta-brief",
    customer,
    reason="one appendix missed the accepted scope",
    amount=cny(50000L),
    contract_amount=cny(250000L),
    actor_id="customer-success",
    grant=portfolio_authority(
      "grant-refund-create", "customer-success", "sales:refund:create", scope, 50000L,
    ),
  )
  let approved = requested.approve(
    actor_id="commercial-reviewer",
    grant=portfolio_authority(
      "grant-refund-approve", "commercial-reviewer", "sales:refund:approve", scope,
      50000L,
    ),
  )
  let paid = approved.pay(
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-refund-pay", "finance-operator", "sales:refund:pay", scope, 50000L,
    ),
  )
  assert_eq(paid.state, Paid)
  try
    @sales.RefundRequest::new(
      refund_id="refund-delta-over",
      contract_id="sale-delta-brief",
      customer,
      reason="invalid over-refund request",
      amount=cny(250001L),
      contract_amount=cny(250000L),
      actor_id="customer-success",
      grant=portfolio_authority(
        "grant-refund-over", "customer-success", "sales:refund:create", scope, 250001L,
      ),
    )
  catch {
    @sales.SalesRecordError::OverRefund => ()
    _ => fail("expected refund greater than contract value to be rejected")
  } noraise {
    _ => fail("over-refund must not be accepted")
  }
}

///|
test "cancelled customer order cannot create phantom revenue" {
  let scope = "engagement:cancelled-golf"
  let amount = cny(250000L)
  let draft = @sales.SalesAgreement::new(
    agreement_id="sale-cancelled-golf",
    principal_id="opc-market-studio",
    customer_id="customer-golf",
    project_scope=scope,
    amount~,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-sale-golf-create", "founder", "sales:create", scope, 250000L,
    ),
  )
  let reserved = draft.transition(
    Reserved,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-sale-golf-reserve", "founder", "sales:reserve", scope, 250000L,
    ),
  )
  let cancelled = reserved.transition(
    Cancelled,
    actor_id="commercial-reviewer",
    grant=portfolio_authority(
      "grant-sale-golf-cancel", "commercial-reviewer", "sales:cancel", scope, 250000L,
    ),
  )
  assert_eq(cancelled.state, Cancelled)
  try
    cancelled.open_receivable(
      receivable_id="receivable-cancelled-golf",
      actor_id="finance-operator",
      sales_grant=portfolio_authority(
        "grant-sale-golf-receivable", "finance-operator", "sales:receivable-open",
        scope, 250000L,
      ),
      receivable_grant=portfolio_authority(
        "grant-receivable-golf-open", "finance-operator", "receivable:open", "customer:customer-golf",
        250000L,
      ),
    )
  catch {
    InvalidTransition => ()
    _ => fail("expected cancelled sale to reject receivable creation")
  } noraise {
    _ => fail("cancelled sale must not recognize a receivable")
  }
}

///|
test "two sales produce reviewed tax and an accepted filing" {
  let scope = "tax:2026-08-service-revenue"
  let draft = @tax.TaxObligation::new(
    tax_id="tax-service-revenue-2026-08",
    principal_id="opc-market-studio",
    project_scope=scope,
    source_reference="sales-batch-2026-08",
    jurisdiction="CN",
    category="service-revenue-vat",
    base_amount=cny(500000L),
    tax_rate_bps=600L,
    withholding_rate_bps=100L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-tax-create", "finance-operator", "tax:create", scope, 500000L,
    ),
  )
  let calculated = draft.calculate(
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-tax-calculate", "finance-operator", "tax:calculate", scope, 500000L,
    ),
  )
  assert_eq(calculated.tax_amount.minor, 30000L)
  assert_eq(calculated.withholding_amount.minor, 5000L)
  let reviewed = calculated.transition(
    Reviewed,
    actor_id="tax-reviewer",
    grant=portfolio_authority(
      "grant-tax-review", "tax-reviewer", "tax:review", scope, 500000L,
    ),
  )
  let filing = reviewed
    .prepare_filing(
      filing_id="filing-service-revenue-2026-08",
      filing_period="2026-08",
      authority_reference="cn-tax-authority",
      actor_id="finance-operator",
      grant=portfolio_authority(
        "grant-tax-filing-prepare", "finance-operator", "tax:filing:prepare", scope,
        30000L,
      ),
    )
    .transition(
      Submitted,
      actor_id="finance-operator",
      grant=portfolio_authority(
        "grant-tax-filing-submit", "finance-operator", "tax:filing:submit", scope,
        30000L,
      ),
    )
    .transition(
      Accepted,
      actor_id="tax-reviewer",
      grant=portfolio_authority(
        "grant-tax-filing-accept", "tax-reviewer", "tax:filing:accept", scope, 30000L,
      ),
    )
  let filed = reviewed.transition(
    Filed,
    actor_id="tax-reviewer",
    grant=portfolio_authority(
      "grant-tax-file", "tax-reviewer", "tax:file", scope, 500000L,
    ),
  )
  let paid = filed.transition(
    Paid,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-tax-pay", "finance-operator", "tax:pay", scope, 500000L,
    ),
  )
  let tax_event = reviewed.to_accounting_event(
    event_id="event-tax-service-revenue-2026-08",
    event_type="service_revenue_tax_recognized",
    tax_expense_account="6100-tax-expense",
    tax_payable_account="2200-tax-payable",
  )
  assert_eq(filing.state, Accepted)
  assert_eq(paid.state, Paid)
  assert_eq(tax_event.journal.postings.length(), 2)
}
