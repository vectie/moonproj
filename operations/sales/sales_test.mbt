///|
fn sales_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "sales-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
test "sales agreement reaches fulfillment" {
  let agreement = SalesAgreement::new(
    agreement_id="sale-001",
    principal_id="co-001",
    customer_id="customer-001",
    project_scope="project:p-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=sales_grant("sales:create"),
  )
  let reserved = agreement.transition(
    SalesState::Reserved,
    actor_id="alice",
    grant=sales_grant("sales:reserve"),
  )
  let signed = reserved.transition(
    SalesState::Signed,
    actor_id="alice",
    grant=sales_grant("sales:sign"),
  )
  let fulfilled = signed.transition(
    SalesState::Fulfilled,
    actor_id="alice",
    grant=sales_grant("sales:fulfill"),
  )
  assert_true(fulfilled.state == SalesState::Fulfilled)
}

///|
test "fulfilled sales agreement opens a receivable through a separate gate" {
  let agreement = SalesAgreement::new(
    agreement_id="sale-receivable-001",
    principal_id="co-001",
    customer_id="customer-001",
    project_scope="project:p-001",
    amount=@finance.Money::new(minor=90000, currency="CNY"),
    actor_id="alice",
    grant=sales_grant("sales:create"),
  )
  let fulfilled = agreement
    .transition(
      SalesState::Reserved,
      actor_id="alice",
      grant=sales_grant("sales:reserve"),
    )
    .transition(
      SalesState::Signed,
      actor_id="alice",
      grant=sales_grant("sales:sign"),
    )
    .transition(
      SalesState::Fulfilled,
      actor_id="alice",
      grant=sales_grant("sales:fulfill"),
    )
  let receivable = fulfilled.open_receivable(
    receivable_id="receivable-sale-001",
    actor_id="alice",
    sales_grant=sales_grant("sales:receivable-open"),
    receivable_grant={
      grant_id: "receivable-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "receivable:open",
      scope: "customer:customer-001",
      max_amount_minor: 100000,
      active: true,
    },
  )
  assert_true(receivable.state == @receivable.ReceivableState::Open)
  assert_eq(receivable.source_id, "sale-receivable-001")
  assert_eq(receivable.outstanding_minor(), 90000L)
}
