///|
fn envelope_fixture() -> SignedCustomerEnvelope {
  {
    message_id: "message-001",
    channel_id: "channel-customer-001",
    customer_id: "customer-001",
    sent_at_epoch: 1000L,
    nonce: "nonce-001",
    content_type: "application/json",
    body: "{\"kind\":\"delivery-feedback\",\"accepted\":true}",
    signature: "",
  }
}

///|
fn channel_fixture() -> VerifiedWebhookChannel {
  {
    channel_id: "channel-customer-001",
    principal_id: "opc-001",
    customer_id: "customer-001",
    signing_key_id: "key-2026-08",
    allowed_clock_skew_seconds: 300L,
    active: true,
  }
}

///|
test "verified customer webhook binds identity, freshness, signature, and replay" {
  let secret = "0123456789abcdef0123456789abcdef"
  let unsigned = envelope_fixture()
  let signed = { ..unsigned, signature: sign_envelope(unsigned, secret~) }
  assert_eq(
    signed.signature,
    "hmac-sha256=30f75130e13138a71dd3bfa9f50dbb7c4f2cfd70a2f33ad1e09fa66e99385b49",
  )
  let (receipt, registry) = verify_inbound(
    channel_fixture(),
    ChannelReplayRegistry::new(),
    signed,
    secret~,
    now_epoch=1010L,
  )
  assert_true(receipt.signature_verified)
  assert_true(receipt.replay_checked)
  assert_true(!receipt.company_authority_granted)
  assert_true(receipt.body_digest.has_prefix("sha256:"))
  try
    verify_inbound(
      channel_fixture(),
      registry,
      signed,
      secret~,
      now_epoch=1020L,
    )
  catch {
    ReplayDetected => ()
    _ => fail("expected replay detection")
  } noraise {
    _ => fail("expected replay to fail")
  }
}

///|
test "verified customer webhook fails closed on tampering and stale delivery" {
  let secret = "0123456789abcdef0123456789abcdef"
  let unsigned = envelope_fixture()
  let signed = { ..unsigned, signature: sign_envelope(unsigned, secret~) }
  try
    verify_inbound(
      channel_fixture(),
      ChannelReplayRegistry::new(),
      { ..signed, body: "{\"accepted\":false}" },
      secret~,
      now_epoch=1010L,
    )
  catch {
    SignatureMismatch => ()
    _ => fail("expected signature mismatch")
  } noraise {
    _ => fail("expected tampering to fail")
  }
  try
    verify_inbound(
      channel_fixture(),
      ChannelReplayRegistry::new(),
      signed,
      secret~,
      now_epoch=1400L,
    )
  catch {
    StaleMessage => ()
    _ => fail("expected stale message failure")
  } noraise {
    _ => fail("expected stale message to fail")
  }
}
