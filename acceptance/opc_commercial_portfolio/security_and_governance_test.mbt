///|
test "customer channel rejects replay forgery staleness and wrong identity" {
  let secret = "0123456789abcdef0123456789abcdef"
  let channel : @customer_channel.VerifiedWebhookChannel = {
    channel_id: "portfolio-webhook",
    principal_id: "opc-market-studio",
    customer_id: "customer-foxtrot",
    signing_key_id: "portfolio-key-2026-08",
    allowed_clock_skew_seconds: 300L,
    active: true,
  }
  let valid = signed_portfolio_message(
    "message-valid", "customer-foxtrot", 1000L, "nonce-valid", secret,
  )
  let (_, registry) = @customer_channel.verify_inbound(
    channel,
    @customer_channel.ChannelReplayRegistry::new(),
    valid,
    secret~,
    now_epoch=1010L,
  )
  try
    @customer_channel.verify_inbound(
      channel,
      registry,
      valid,
      secret~,
      now_epoch=1011L,
    )
  catch {
    ReplayDetected => ()
    _ => fail("expected duplicate message to be rejected")
  } noraise {
    _ => fail("replay must not be accepted")
  }

  let forged = { ..valid, message_id: "message-forged", nonce: "nonce-forged" }
  try
    @customer_channel.verify_inbound(
      channel,
      @customer_channel.ChannelReplayRegistry::new(),
      forged,
      secret~,
      now_epoch=1010L,
    )
  catch {
    SignatureMismatch => ()
    _ => fail("expected modified signed envelope to be rejected")
  } noraise {
    _ => fail("forged message must not be accepted")
  }

  let stale = signed_portfolio_message(
    "message-stale", "customer-foxtrot", 1L, "nonce-stale", secret,
  )
  try
    @customer_channel.verify_inbound(
      channel,
      @customer_channel.ChannelReplayRegistry::new(),
      stale,
      secret~,
      now_epoch=1000L,
    )
  catch {
    StaleMessage => ()
    _ => fail("expected stale message to be rejected")
  } noraise {
    _ => fail("stale message must not be accepted")
  }

  let wrong_customer = signed_portfolio_message(
    "message-wrong-customer", "customer-impostor", 1000L, "nonce-wrong-customer",
    secret,
  )
  try
    @customer_channel.verify_inbound(
      channel,
      @customer_channel.ChannelReplayRegistry::new(),
      wrong_customer,
      secret~,
      now_epoch=1010L,
    )
  catch {
    CustomerMismatch => ()
    _ => fail("expected wrong customer identity to be rejected")
  } noraise {
    _ => fail("wrong customer identity must not be accepted")
  }
}

///|
test "money authority enforces amount cap but commitment actor separation is not intrinsic" {
  try
    @payable.Payable::open(
      payable_id="payable-over-cap",
      principal_id="opc-market-studio",
      project_scope="project:authority-test",
      supplier_id="supplier-test",
      source_reference="commitment-test",
      amount=cny(120000L),
      actor_id="finance-operator",
      grant=portfolio_authority(
        "grant-payable-too-small", "finance-operator", "payable:create", "project:authority-test",
        100000L,
      ),
    )
  catch {
    @payable.PayableError::NotAuthorized(_) => ()
    _ => fail("expected capped grant to reject larger payable")
  } noraise {
    _ => fail("amount above authority cap must not be accepted")
  }

  let scope = "project:self-approval-characterization"
  let amount = cny(100000L)
  let draft = @commitment.Commitment::new(
    commitment_id="commitment-self-approval",
    principal_id="opc-market-studio",
    project_scope=scope,
    counterparty_id="supplier-test",
    amount~,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-self-create", "founder", "commitment:create", scope, 100000L,
    ),
  )
  let submitted = draft.transition(
    Submitted,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-self-submit", "founder", "commitment:submit", scope, 100000L,
    ),
  )
  let self_approved = submitted.transition(
    Approved,
    actor_id="founder",
    grant=portfolio_authority(
      "grant-self-approve", "founder", "commitment:approve", scope, 100000L,
    ),
  )
  assert_eq(self_approved.state, Approved)
  assert_eq(self_approved.events[0].actor_id, "founder")
  assert_eq(self_approved.events[1].actor_id, "founder")
}
