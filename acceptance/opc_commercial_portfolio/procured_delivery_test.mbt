///|
test "supplier-backed brand kit remains profitable and budget controlled" {
  let project_scope = "project:brand-kit-charlie"
  let supplier_scope = "procurement:creative-suppliers"
  let supplier = @procurement.Supplier::new(
      supplier_id="supplier-layout-co",
      principal_id="opc-market-studio",
      scope=supplier_scope,
      supplier_code="LAYOUT-01",
      name="Layout Cooperative",
      category_code="design-production",
      actor_id="founder",
      grant=portfolio_authority(
        "grant-supplier-create", "founder", "supplier:create", supplier_scope, 0L,
      ),
    )
    .submit_review(
      actor_id="founder",
      grant=portfolio_authority(
        "grant-supplier-submit", "founder", "supplier:submit", supplier_scope, 0L,
      ),
    )
    .review(
      evaluation=Qualified,
      actor_id="procurement-reviewer",
      grant=portfolio_authority(
        "grant-supplier-review", "procurement-reviewer", "supplier:review", supplier_scope,
        0L,
      ),
    )
  assert_eq(supplier.state, Active)

  let tender = @procurement.TenderPlan::new(
      tender_id="tender-brand-kit-charlie",
      principal_id="opc-market-studio",
      project_scope~,
      name="Brand-kit production",
      category="design-production",
      estimated_amount=cny(150000L),
      actor_id="founder",
      grant=portfolio_authority(
        "grant-tender-create", "founder", "tender:create", project_scope, 150000L,
      ),
    )
    .publish(
      actor_id="founder",
      grant=portfolio_authority(
        "grant-tender-publish", "founder", "tender:publish", project_scope, 150000L,
      ),
    )
    .open_bidding(
      actor_id="procurement-reviewer",
      grant=portfolio_authority(
        "grant-tender-open", "procurement-reviewer", "tender:open", project_scope,
        150000L,
      ),
    )
    .add_bid(
      supplier,
      amount=cny(120000L),
      actor_id="procurement-reviewer",
      grant=portfolio_authority(
        "grant-tender-bid", "procurement-reviewer", "tender:bid", project_scope,
        120000L,
      ),
    )
    .award(
      supplier,
      actor_id="commercial-reviewer",
      grant=portfolio_authority(
        "grant-tender-award", "commercial-reviewer", "tender:award", project_scope,
        120000L,
      ),
    )
  let commitment = tender.create_commitment(
    commitment_id="commitment-brand-kit-layout",
    actor_id="commercial-reviewer",
    award_grant=portfolio_authority(
      "grant-award-to-commitment", "commercial-reviewer", "tender:award-to-commitment",
      project_scope, 120000L,
    ),
    commitment_grant=portfolio_authority(
      "grant-brand-kit-commitment", "commercial-reviewer", "commitment:create", project_scope,
      120000L,
    ),
  )
  let budget = @finance.BudgetLine::new(
    line_id="budget-brand-kit",
    principal_id="opc-market-studio",
    scope=project_scope,
    currency="CNY",
    allocated_minor=150000L,
  )
  let (reservation, reserved_budget) = @commitment.reserve_budget(
    commitment,
    budget,
    reservation_id="reservation-layout",
    amount_minor=120000L,
  )
  assert_eq(reserved_budget.available_minor(), 30000L)

  let submitted = commitment.transition(
    Submitted,
    actor_id="commercial-reviewer",
    grant=portfolio_authority(
      "grant-supplier-commitment-submit", "commercial-reviewer", "commitment:submit",
      project_scope, 120000L,
    ),
  )
  let approved = submitted.transition(
    Approved,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-supplier-commitment-approve", "founder", "commitment:approve", project_scope,
      120000L,
    ),
  )
  let consumed_budget = reservation.consume(reserved_budget)
  assert_eq(consumed_budget.consumed_minor, 120000L)
  let performed = approved.transition(
    Performed,
    actor_id="delivery-reviewer",
    grant=portfolio_authority(
      "grant-supplier-commitment-perform", "delivery-reviewer", "commitment:perform",
      project_scope, 120000L,
    ),
  )

  let payable = @payable.Payable::open(
    payable_id="payable-layout",
    principal_id="opc-market-studio",
    project_scope~,
    supplier_id=supplier.supplier_id,
    source_reference=performed.commitment_id,
    amount=cny(120000L),
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-payable-open", "finance-operator", "payable:create", project_scope,
      120000L,
    ),
  )
  let opening_event = payable.to_opening_event(
    event_id="event-payable-layout-open",
    event_type="supplier_payable_opened",
    expense_account="5200-production-cost",
    payable_account="2100-accounts-payable",
  )
  let partially_paid = payable.record_payment(
    payment=cny(60000L),
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-payable-partial", "finance-operator", "payable:pay", project_scope,
      60000L,
    ),
  )
  let payment_event = partially_paid.to_payment_event(
    payment_id="payment-layout-balance",
    event_id="event-payable-layout-payment",
    event_type="supplier_payment",
    amount=cny(60000L),
    payable_account="2100-accounts-payable",
    cash_account="1000-bank",
  )
  let paid = partially_paid.record_payment(
    payment=cny(60000L),
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-payable-final", "finance-operator", "payable:pay", project_scope, 60000L,
    ),
  )
  assert_eq(opening_event.journal.postings.length(), 2)
  assert_eq(payment_event.journal.postings.length(), 2)
  assert_eq(paid.state, Paid)

  let customer_receivable = fulfilled_sale(
    "charlie-brand-kit", "customer-charlie", 500000L,
  )
  let customer_paid = customer_receivable.collect(
    amount_minor=500000L,
    actor_id="finance-operator",
    grant=portfolio_authority(
      "grant-collect-charlie", "finance-operator", "receivable:collect", "customer:customer-charlie",
      500000L,
    ),
  )
  assert_eq(customer_paid.state, Collected)
  assert_eq(500000L - paid.amount.minor, 380000L)
  assert_eq((500000L - paid.amount.minor) * 100L / 500000L, 76L)
}
