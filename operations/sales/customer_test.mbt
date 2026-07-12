///|
fn sales_record_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-sales-record",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn active_customer() -> Customer raise SalesRecordError {
  Customer::new(
    customer_id="customer-001",
    principal_id="co-001",
    project_scope="project:p-001",
    customer_code="CUS-001",
    name="Customer One",
    contact_reference="phone:001",
    actor_id="alice",
    grant=sales_record_grant("sales:customer:create"),
  )
}

///|
test "customer reservation converts and mortgage releases" {
  let customer = active_customer()
  let reservation = Reservation::new(
    subscription_id="sub-001",
    customer,
    unit_reference="building-1/unit-1",
    amount=@finance.Money::new(minor=100000, currency="CNY"),
    actor_id="alice",
    grant=sales_record_grant("sales:reserve"),
  ).convert(
    actor_id="alice",
    grant=sales_record_grant("sales:subscription:convert"),
  )
  let mortgage = MortgageApplication::new(
      mortgage_id="mortgage-001",
      contract_id="sales-contract-001",
      customer,
      bank_reference="bank-001",
      loan_amount=@finance.Money::new(minor=800000, currency="CNY"),
      annual_rate_bps=485L,
      actor_id="alice",
      grant=sales_record_grant("sales:mortgage:create"),
    )
    .approve(
      actor_id="alice",
      grant=sales_record_grant("sales:mortgage:approve"),
    )
    .release(
      actor_id="alice",
      grant=sales_record_grant("sales:mortgage:release"),
    )
  assert_true(reservation.state == SubscriptionState::Converted)
  assert_true(mortgage.state == MortgageState::Released)
}

///|
test "refund requires approval before payment" {
  let customer = active_customer()
  let refund = RefundRequest::new(
      refund_id="refund-001",
      contract_id="sales-contract-001",
      customer,
      reason="Customer cancellation",
      amount=@finance.Money::new(minor=50000, currency="CNY"),
      contract_amount=@finance.Money::new(minor=100000, currency="CNY"),
      actor_id="alice",
      grant=sales_record_grant("sales:refund:create"),
    )
    .approve(actor_id="alice", grant=sales_record_grant("sales:refund:approve"))
    .pay(actor_id="alice", grant=sales_record_grant("sales:refund:pay"))
  assert_true(refund.state == RefundState::Paid)
}

///|
test "refund rejects an amount above the contract" {
  let customer = active_customer()
  try
    RefundRequest::new(
      refund_id="refund-002",
      contract_id="sales-contract-001",
      customer,
      reason="Invalid refund",
      amount=@finance.Money::new(minor=100001, currency="CNY"),
      contract_amount=@finance.Money::new(minor=100000, currency="CNY"),
      actor_id="alice",
      grant=sales_record_grant("sales:refund:create"),
    )
  catch {
    SalesRecordError::OverRefund => ()
    _ => fail("wrong sales record error")
  } noraise {
    _ => fail("expected sales record error")
  }
}
