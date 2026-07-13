///|
fn notification_channel_name(channel : NotificationChannel) -> String {
  match channel {
    NotificationChannel::InApp => "in_app"
    NotificationChannel::Email => "email"
    NotificationChannel::Webhook => "webhook"
  }
}

///|
fn notification_state_name(state : NotificationState) -> String {
  match state {
    NotificationState::Draft => "draft"
    NotificationState::Queued => "queued"
    NotificationState::Attempted => "attempted"
    NotificationState::Delivered => "delivered"
    NotificationState::Failed => "failed"
    NotificationState::Suppressed => "suppressed"
  }
}

///|
fn notification_events_json(events : Array[NotificationEvent]) -> Json {
  let values : Array[Json] = []
  for event in events {
    values.push(
      Json::object({
        "from": Json::string(notification_state_name(event.from)),
        "to": Json::string(notification_state_name(event.to)),
        "actor_id": Json::string(event.actor_id),
        "capability": Json::string(event.capability),
        "note": Json::string(event.note),
      }),
    )
  }
  Json::array(values)
}

///|
pub fn NotificationEvidence::append_projection(
  self : NotificationEvidence,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise NotificationError {
  let notification = self.notification
  if projection.aggregate_type != "notification_outbox" ||
    projection.aggregate_id != notification.notification_id {
    raise NotificationError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "notification_id": Json::string(notification.notification_id),
    "principal_id": Json::string(notification.principal_id),
    "recipient_id": Json::string(notification.recipient_id),
    "scope": Json::string(notification.scope),
    "channel": Json::string(notification_channel_name(notification.channel)),
    "template_code": Json::string(notification.template_code),
    "subject": Json::string(notification.subject),
    "body": Json::string(notification.body),
    "source_event_id": Json::string(notification.source_event_id),
    "idempotency_key": Json::string(notification.idempotency_key),
    "provider_message_id": Json::string(notification.provider_message_id),
    "failure_reason": Json::string(notification.failure_reason),
    "state": Json::string(notification_state_name(notification.state)),
    "events": notification_events_json(notification.events),
    "source_snapshot_id": Json::string(self.source_snapshot_id),
    "mapping_version": Json::string(self.mapping_version),
    "evidence_id": Json::string(self.evidence_id),
    "delivery_requested": Json::boolean(
      notification.state != NotificationState::Draft,
    ),
    "external_delivery_confirmed": Json::boolean(
      notification.state == NotificationState::Delivered,
    ),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:notification:" +
      notification.notification_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise NotificationError::Projection(error)
  }
}
