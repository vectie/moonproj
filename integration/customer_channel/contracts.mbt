///|
/// The first verified channel is a signed customer webhook. It is intentionally
/// narrow: one configured customer identity, one signing key, inbound only.
#derive(Debug, Eq)
pub(all) struct VerifiedWebhookChannel {
  channel_id : String
  principal_id : String
  customer_id : String
  signing_key_id : String
  allowed_clock_skew_seconds : Int64
  active : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct SignedCustomerEnvelope {
  message_id : String
  channel_id : String
  customer_id : String
  sent_at_epoch : Int64
  nonce : String
  content_type : String
  body : String
  signature : String
}

///|
#derive(Debug, Eq)
pub(all) struct ChannelReplayRegistry {
  message_ids : Array[String]
  nonces : Array[String]
}

///|
#derive(Debug, Eq)
pub(all) struct VerifiedCustomerReceipt {
  receipt_id : String
  principal_id : String
  customer_id : String
  channel_id : String
  message_id : String
  body_digest : String
  signing_key_id : String
  sent_at_epoch : Int64
  verified_at_epoch : Int64
  signature_verified : Bool
  replay_checked : Bool
  company_authority_granted : Bool
}

///|
#derive(Debug, Eq)
pub(all) suberror CustomerChannelError {
  Invalid(String)
  InactiveChannel
  ChannelMismatch
  CustomerMismatch
  StaleMessage
  ReplayDetected
  SignatureMismatch
}

///|
pub fn ChannelReplayRegistry::new() -> ChannelReplayRegistry {
  { message_ids: [], nonces: [], }
}
