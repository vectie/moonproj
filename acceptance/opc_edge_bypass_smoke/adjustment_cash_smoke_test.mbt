///|
fn cash_event(
  event_id : String,
  source_type : String,
  source_id : String,
  debit_account : String,
  credit_account : String,
  amount : @finance.Money,
) -> @accounting.AccountingEvent raise {
  let journal : @finance.JournalEntry = {
    entry_id: "journal/" + event_id,
    description: source_type + " " + source_id,
    postings: [
      { account: debit_account, side: Debit, amount },
      { account: credit_account, side: Credit, amount },
    ],
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id="opc-market-studio",
    source_type~,
    source_id~,
    event_type=source_type,
    journal~,
  )
}

///|
fn release_sandbox_outflow(
  account : @treasury.CashAccount,
  movement_id : String,
  reference_id : String,
  amount : @finance.Money,
) -> (@treasury.CashAccount, @treasury.CashMovement) raise {
  let scope = account.project_scope
  let requested = @treasury.CashMovement::request(
    account,
    movement_id~,
    reference_id~,
    amount~,
    direction=Outflow,
    actor_id="finance-operator",
    grant=smoke_authority(
      "grant-request-" + movement_id,
      "finance-operator",
      "treasury:request",
      scope,
      amount.minor,
    ),
  )
  let approved = requested.approve(
    actor_id="treasury-reviewer",
    grant=smoke_authority(
      "grant-approve-" + movement_id,
      "treasury-reviewer",
      "treasury:approve",
      scope,
      amount.minor,
    ),
  )
  account.release(
    approved,
    actor_id="finance-operator",
    grant=smoke_authority(
      "grant-release-" + movement_id,
      "finance-operator",
      "treasury:release",
      scope,
      amount.minor,
    ),
  )
}

///|
test "refund and tax payment bridge to treasury and balanced journals" {
  let sales_scope = "engagement:smoke-adjustment"
  let customer = @sales.Customer::new(
    customer_id="customer-smoke-adjustment",
    principal_id="opc-market-studio",
    project_scope=sales_scope,
    customer_code="SMOKE-ADJUSTMENT",
    name="Smoke Adjustment Customer",
    contact_reference="sandbox/customer-smoke-adjustment",
    actor_id="founder",
    grant=smoke_authority(
      "grant-smoke-customer-create", "founder", "sales:customer:create", sales_scope,
      0L,
    ),
  )
  let refund = @sales.RefundRequest::new(
      refund_id="refund-smoke-001",
      contract_id="contract-smoke-001",
      customer,
      reason="sandbox partial service credit",
      amount=smoke_cny(50000L),
      contract_amount=smoke_cny(250000L),
      actor_id="customer-success",
      grant=smoke_authority(
        "grant-smoke-refund-create", "customer-success", "sales:refund:create", sales_scope,
        50000L,
      ),
    )
    .approve(
      actor_id="commercial-reviewer",
      grant=smoke_authority(
        "grant-smoke-refund-approve", "commercial-reviewer", "sales:refund:approve",
        sales_scope, 50000L,
      ),
    )
    .pay(
      actor_id="finance-operator",
      grant=smoke_authority(
        "grant-smoke-refund-pay", "finance-operator", "sales:refund:pay", sales_scope,
        50000L,
      ),
    )
  let tax_scope = "tax:smoke-adjustment"
  let tax = @tax.TaxObligation::new(
      tax_id="tax-smoke-001",
      principal_id="opc-market-studio",
      project_scope=tax_scope,
      source_reference="invoice-smoke-001",
      jurisdiction="CN",
      category="service-revenue-vat",
      base_amount=smoke_cny(500000L),
      tax_rate_bps=600L,
      withholding_rate_bps=0L,
      actor_id="finance-operator",
      grant=smoke_authority(
        "grant-smoke-tax-create", "finance-operator", "tax:create", tax_scope, 500000L,
      ),
    )
    .calculate(
      actor_id="finance-operator",
      grant=smoke_authority(
        "grant-smoke-tax-calculate", "finance-operator", "tax:calculate", tax_scope,
        500000L,
      ),
    )
    .transition(
      Reviewed,
      actor_id="tax-reviewer",
      grant=smoke_authority(
        "grant-smoke-tax-review", "tax-reviewer", "tax:review", tax_scope, 500000L,
      ),
    )
    .transition(
      Filed,
      actor_id="tax-reviewer",
      grant=smoke_authority(
        "grant-smoke-tax-file", "tax-reviewer", "tax:file", tax_scope, 500000L,
      ),
    )
    .transition(
      Paid,
      actor_id="finance-operator",
      grant=smoke_authority(
        "grant-smoke-tax-pay", "finance-operator", "tax:pay", tax_scope, 500000L,
      ),
    )
  assert_eq(refund.state, Paid)
  assert_eq(tax.tax_amount.minor, 30000L)

  let treasury_scope = "treasury:smoke-operating"
  let account = @treasury.CashAccount::open(
    account_id="cash-smoke-operating",
    principal_id="opc-market-studio",
    project_scope=treasury_scope,
    currency="CNY",
    bank_reference="sandbox-bank/account-operating",
    opening_balance=smoke_cny(500000L),
    actor_id="finance-operator",
    grant=smoke_authority(
      "grant-smoke-account-open", "finance-operator", "treasury:account:create",
      treasury_scope, 500000L,
    ),
  )
  let refund_provider = sandbox_receipt(
    "sandbox-refund-provider-001",
    "sandbox-payment-provider",
    refund.refund_id,
    50000L,
  )
  let (after_refund, refund_movement) = release_sandbox_outflow(
    account,
    "movement-refund-smoke-001",
    refund_provider.receipt_id,
    smoke_cny(50000L),
  )
  let tax_provider = sandbox_receipt(
    "sandbox-tax-provider-001",
    "sandbox-tax-bank",
    tax.tax_id,
    30000L,
  )
  let (after_tax, tax_movement) = release_sandbox_outflow(
    after_refund,
    "movement-tax-smoke-001",
    tax_provider.receipt_id,
    smoke_cny(30000L),
  )
  let refund_event = cash_event(
    "event-refund-smoke-001",
    "customer_refund",
    refund.refund_id,
    "4200-sales-returns",
    "1000-bank",
    smoke_cny(50000L),
  )
  let tax_event = cash_event(
    "event-tax-payment-smoke-001",
    "tax_payment",
    tax.tax_id,
    "2200-tax-payable",
    "1000-bank",
    smoke_cny(30000L),
  )
  assert_eq(after_tax.balance.minor, 420000L)
  assert_eq(refund_movement.state, Released)
  assert_eq(tax_movement.state, Released)
  @finance.validate_journal(refund_event.journal)
  @finance.validate_journal(tax_event.journal)
  assert_eq(@finance.journal_total(refund_event.journal).minor, 100000L)
  assert_eq(@finance.journal_total(tax_event.journal).minor, 60000L)
}
