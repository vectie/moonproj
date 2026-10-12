///|
fn portfolio_authority(
  grant_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  max_amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id: "opc-market-studio",
    actor_id,
    capability,
    scope,
    max_amount_minor,
    active: true,
  }
}

///|
fn cny(minor : Int64) -> @finance.Money raise {
  @finance.Money::new(minor~, currency="CNY")
}

///|
fn fulfilled_sale(
  cycle_id : String,
  customer_id : String,
  amount_minor : Int64,
) -> @receivable.Receivable raise {
  let scope = "engagement:" + cycle_id
  let amount = cny(amount_minor)
  let draft = @sales.SalesAgreement::new(
    agreement_id="sale-" + cycle_id,
    principal_id="opc-market-studio",
    customer_id~,
    project_scope=scope,
    amount~,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-sale-create-" + cycle_id,
      "founder",
      "sales:create",
      scope,
      amount_minor,
    ),
  )
  let reserved = draft.transition(
    Reserved,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-sale-reserve-" + cycle_id,
      "founder",
      "sales:reserve",
      scope,
      amount_minor,
    ),
  )
  let signed = reserved.transition(
    Signed,
    actor_id="commercial-reviewer",
    grant=portfolio_authority(
      "grant-sale-sign-" + cycle_id,
      "commercial-reviewer",
      "sales:sign",
      scope,
      amount_minor,
    ),
  )
  let fulfilled = signed.transition(
    Fulfilled,
    actor_id="delivery-reviewer",
    grant=portfolio_authority(
      "grant-sale-fulfill-" + cycle_id,
      "delivery-reviewer",
      "sales:fulfill",
      scope,
      amount_minor,
    ),
  )
  fulfilled.open_receivable(
    receivable_id="receivable-" + cycle_id,
    actor_id="finance-operator",
    sales_grant=portfolio_authority(
      "grant-sale-receivable-" + cycle_id,
      "finance-operator",
      "sales:receivable-open",
      scope,
      amount_minor,
    ),
    receivable_grant=portfolio_authority(
      "grant-receivable-open-" + cycle_id,
      "finance-operator",
      "receivable:open",
      "customer:" + customer_id,
      amount_minor,
    ),
  )
}

///|
fn signed_portfolio_message(
  message_id : String,
  customer_id : String,
  sent_at_epoch : Int64,
  nonce : String,
  secret : String,
) -> @customer_channel.SignedCustomerEnvelope raise {
  let unsigned : @customer_channel.SignedCustomerEnvelope = {
    message_id,
    channel_id: "portfolio-webhook",
    customer_id,
    sent_at_epoch,
    nonce,
    content_type: "application/json",
    body: "{\"kind\":\"order\",\"offer\":\"decision-brief\"}",
    signature: "",
  }
  { ..unsigned, signature: @customer_channel.sign_envelope(unsigned, secret~) }
}
