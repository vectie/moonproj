///|
fn sha256_bytes(value : String) -> FixedArray[Byte] {
  @crypto.sha256(@utf8.encode(value))
}

///|
fn sha256_hex(value : String) -> String {
  @crypto.bytes_to_hex_string(sha256_bytes(value))
}

///|
fn hmac_sha256_hex(secret : String, message : String) -> String {
  let encoded = @utf8.encode(secret)
  let key = if encoded.length() > 64 {
    Bytes::from_iter(@crypto.sha256(encoded).iter())
  } else {
    encoded
  }
  let block = Bytes::makei(64, index => {
    (if index < key.length() { key[index] } else { 0 }).lxor(0x36)
  })
  let outer = Bytes::makei(64, index => {
    (if index < key.length() { key[index] } else { 0 }).lxor(0x5c)
  })
  let inner = @crypto.sha256(block + @utf8.encode(message))
  @crypto.bytes_to_hex_string(
    @crypto.sha256(outer + Bytes::from_iter(inner.iter())),
  )
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  let a = @utf8.encode(left)
  let b = @utf8.encode(right)
  if a.length() != b.length() {
    return false
  }
  let mut difference : Byte = 0
  for index in 0..<a.length() {
    difference = difference.lor(a[index].lxor(b[index]))
  }
  difference == 0
}

///|
pub fn canonical_payload(envelope : SignedCustomerEnvelope) -> String {
  [
    "moonproj.customer-webhook.v1",
    envelope.channel_id,
    envelope.message_id,
    envelope.customer_id,
    envelope.sent_at_epoch.to_string(),
    envelope.nonce,
    envelope.content_type,
    "sha256:\{sha256_hex(envelope.body)}",
  ].join("\n")
}

///|
pub fn sign_envelope(
  envelope : SignedCustomerEnvelope,
  secret~ : String,
) -> String raise CustomerChannelError {
  if secret.length() < 32 {
    raise Invalid("webhook signing secret must contain at least 32 bytes")
  }
  "hmac-sha256=\{hmac_sha256_hex(secret, canonical_payload(envelope))}"
}

///|
pub fn verify_inbound(
  channel : VerifiedWebhookChannel,
  registry : ChannelReplayRegistry,
  envelope : SignedCustomerEnvelope,
  secret~ : String,
  now_epoch~ : Int64,
) -> (VerifiedCustomerReceipt, ChannelReplayRegistry) raise CustomerChannelError {
  if !channel.active {
    raise InactiveChannel
  }
  if channel.channel_id.trim().is_empty() ||
    channel.principal_id.trim().is_empty() ||
    channel.customer_id.trim().is_empty() ||
    channel.signing_key_id.trim().is_empty() ||
    channel.allowed_clock_skew_seconds <= 0 ||
    envelope.message_id.trim().is_empty() ||
    envelope.nonce.trim().is_empty() ||
    envelope.content_type != "application/json" ||
    envelope.body.trim().is_empty() ||
    now_epoch < 0 {
    raise Invalid(
      "channel and signed envelope require complete identity and JSON content",
    )
  }
  if envelope.channel_id != channel.channel_id {
    raise ChannelMismatch
  }
  if envelope.customer_id != channel.customer_id {
    raise CustomerMismatch
  }
  let age = if now_epoch >= envelope.sent_at_epoch {
    now_epoch - envelope.sent_at_epoch
  } else {
    envelope.sent_at_epoch - now_epoch
  }
  if age > channel.allowed_clock_skew_seconds {
    raise StaleMessage
  }
  if registry.message_ids.contains(envelope.message_id) ||
    registry.nonces.contains(envelope.nonce) {
    raise ReplayDetected
  }
  let expected = sign_envelope(envelope, secret~)
  if !constant_time_equal(envelope.signature, expected) {
    raise SignatureMismatch
  }
  let message_ids = registry.message_ids.copy()
  let nonces = registry.nonces.copy()
  message_ids.push(envelope.message_id)
  nonces.push(envelope.nonce)
  (
    {
      receipt_id: "customer-webhook-receipt-\{envelope.message_id}",
      principal_id: channel.principal_id,
      customer_id: channel.customer_id,
      channel_id: channel.channel_id,
      message_id: envelope.message_id,
      body_digest: "sha256:\{sha256_hex(envelope.body)}",
      signing_key_id: channel.signing_key_id,
      sent_at_epoch: envelope.sent_at_epoch,
      verified_at_epoch: now_epoch,
      signature_verified: true,
      replay_checked: true,
      company_authority_granted: false,
    },
    { message_ids, nonces },
  )
}
