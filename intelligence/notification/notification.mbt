///|
pub(all) enum NotificationChannel {
  InApp
  Email
  Webhook
} derive(Debug, Eq)

///|
pub(all) enum NotificationState {
  Draft
  Queued
  Attempted
  Delivered
  Failed
  Suppressed
} derive(Debug, Eq)

///|
pub(all) struct NotificationEvent {
  from : NotificationState
  to : NotificationState
  actor_id : String
  capability : String
  note : String
} derive(Debug, Eq)

///|
/// A company-owned notification outbox item. Queueing and delivery confirmation
/// are separate authority-bearing events; this aggregate never sends a network
/// request or mutates workflow approval state.
pub(all) struct Notification {
  notification_id : String
  principal_id : String
  recipient_id : String
  scope : String
  channel : NotificationChannel
  template_code : String
  subject : String
  body : String
  source_event_id : String
  idempotency_key : String
  provider_message_id : String
  failure_reason : String
  state : NotificationState
  events : Array[NotificationEvent]
} derive(Debug, Eq)

///|
/// Source-bound notification evidence. It preserves the source request and
/// mapping identity without treating source messages as delivered mail.
pub(all) struct NotificationEvidence {
  notification : Notification
  source_snapshot_id : String
  mapping_version : String
  evidence_id : String
} derive(Debug, Eq)

///|
pub(all) suberror NotificationError {
  EmptyIdentifier
  InvalidChannelContent
  InvalidState
  MissingProviderMessage
  MissingFailureReason
  NotAuthorized(@foundation.AuthorityError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn Notification::new(
  notification_id~ : String,
  principal_id~ : String,
  recipient_id~ : String,
  scope~ : String,
  channel~ : NotificationChannel,
  template_code~ : String,
  subject~ : String,
  body~ : String,
  source_event_id~ : String,
  idempotency_key~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  if notification_id.trim() == "" ||
    principal_id.trim() == "" ||
    recipient_id.trim() == "" ||
    scope.trim() == "" ||
    template_code.trim() == "" ||
    body.trim() == "" ||
    source_event_id.trim() == "" ||
    idempotency_key.trim() == "" {
    raise NotificationError::EmptyIdentifier
  }
  if channel == NotificationChannel::Email && subject.trim() == "" {
    raise NotificationError::InvalidChannelContent
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="notification:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise NotificationError::NotAuthorized(error)
  }
  {
    notification_id,
    principal_id,
    recipient_id,
    scope,
    channel,
    template_code,
    subject,
    body,
    source_event_id,
    idempotency_key,
    provider_message_id: "",
    failure_reason: "",
    state: NotificationState::Draft,
    events: [],
  }
}

///|
fn Notification::notification_transition(
  self : Notification,
  to : NotificationState,
  capability : String,
  note : String,
  actor_id : String,
  grant : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  let allowed = (
      self.state == NotificationState::Draft &&
      (to == NotificationState::Queued || to == NotificationState::Suppressed)
    ) ||
    (
      self.state == NotificationState::Queued &&
      (
        to == NotificationState::Attempted ||
        to == NotificationState::Suppressed
      )
    ) ||
    (
      self.state == NotificationState::Attempted &&
      (
        to == NotificationState::Delivered ||
        to == NotificationState::Failed ||
        to == NotificationState::Suppressed
      )
    ) ||
    (
      self.state == NotificationState::Failed &&
      (to == NotificationState::Queued || to == NotificationState::Suppressed)
    )
  if !allowed {
    raise NotificationError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise NotificationError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id, capability, note })
  { ..self, state: to, events }
}

///|
pub fn Notification::queue(
  self : Notification,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  self.notification_transition(
    NotificationState::Queued,
    "notification:queue",
    "delivery requested",
    actor_id,
    grant,
  )
}

///|
pub fn Notification::attempt(
  self : Notification,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  self.notification_transition(
    NotificationState::Attempted,
    "notification:attempt",
    "provider attempt recorded; no network side effect is implied",
    actor_id,
    grant,
  )
}

///|
pub fn Notification::confirm_delivered(
  self : Notification,
  provider_message_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  if provider_message_id.trim() == "" {
    raise NotificationError::MissingProviderMessage
  }
  let next = self.notification_transition(
    NotificationState::Delivered,
    "notification:confirm",
    "external provider confirmation attached",
    actor_id,
    grant,
  )
  { ..next, provider_message_id, }
}

///|
pub fn Notification::fail(
  self : Notification,
  reason~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  if reason.trim() == "" {
    raise NotificationError::MissingFailureReason
  }
  let next = self.notification_transition(
    NotificationState::Failed,
    "notification:fail",
    reason,
    actor_id,
    grant,
  )
  { ..next, failure_reason: reason }
}

///|
pub fn Notification::suppress(
  self : Notification,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Notification raise NotificationError {
  self.notification_transition(
    NotificationState::Suppressed,
    "notification:suppress",
    "delivery suppressed by authority",
    actor_id,
    grant,
  )
}

///|
pub fn Notification::bind_evidence(
  self : Notification,
  source_snapshot_id~ : String,
  mapping_version~ : String,
  evidence_id~ : String,
) -> NotificationEvidence raise NotificationError {
  if source_snapshot_id.trim() == "" ||
    mapping_version.trim() == "" ||
    evidence_id.trim() == "" {
    raise NotificationError::EmptyIdentifier
  }
  { notification: self, source_snapshot_id, mapping_version, evidence_id }
}
