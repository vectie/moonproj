///|
pub(all) suberror NotificationPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Notification(@notification_domain.NotificationError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise NotificationPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise NotificationPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise NotificationPromotionError {
  match value {
    Object(value) => value
    _ => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise NotificationPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise NotificationPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise NotificationPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn optional_string(
  obj : Map[String, Json],
  key : String,
  fallback : String,
) -> String {
  match obj.get(key) {
    Some(String(value)) => value
    _ => fallback
  }
}

///|
fn channel(
  value : String,
) -> @notification_domain.NotificationChannel raise NotificationPromotionError {
  match value {
    "in_app" => @notification_domain.NotificationChannel::InApp
    "email" => @notification_domain.NotificationChannel::Email
    "webhook" => @notification_domain.NotificationChannel::Webhook
    _ => raise NotificationPromotionError::InvalidInput
  }
}

///|
fn channel_name(channel : @notification_domain.NotificationChannel) -> String {
  match channel {
    @notification_domain.NotificationChannel::InApp => "in_app"
    @notification_domain.NotificationChannel::Email => "email"
    @notification_domain.NotificationChannel::Webhook => "webhook"
  }
}

///|
fn state_name(state : @notification_domain.NotificationState) -> String {
  match state {
    @notification_domain.NotificationState::Draft => "draft"
    @notification_domain.NotificationState::Queued => "queued"
    @notification_domain.NotificationState::Attempted => "attempted"
    @notification_domain.NotificationState::Delivered => "delivered"
    @notification_domain.NotificationState::Failed => "failed"
    @notification_domain.NotificationState::Suppressed => "suppressed"
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "notification-promotion/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise NotificationPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.company.notification-plan.v1" {
    raise NotificationPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let evidence_id = required_string(root, "evidence_id")
  let source_table = optional_string(root, "source_table", "sys_message")
  let source_id = required_string(root, "source_id")
  let principal_id = required_string(root, "principal_id")
  let scope = required_string(root, "scope")
  let channel_value = channel(required_string(root, "channel"))
  let notification_id = required_string(root, "notification_id")
  let recipient_id = required_string(root, "recipient_id")
  let template_code = required_string(root, "template_code")
  let subject = optional_string(root, "subject", "")
  let body = required_string(root, "body")
  let source_event_id = required_string(root, "source_event_id")
  let idempotency_key = required_string(root, "idempotency_key")
  let notification = @notification_domain.Notification::new(
    notification_id~,
    principal_id~,
    recipient_id~,
    scope~,
    channel=channel_value,
    template_code~,
    subject~,
    body~,
    source_event_id~,
    idempotency_key~,
    actor_id="migration",
    grant=grant(principal_id, "notification:create", scope),
  ) catch {
    error => raise NotificationPromotionError::Notification(error)
  }
  let queued = if required_bool(root, "queue") {
    notification.queue(
      actor_id="migration",
      grant=grant(principal_id, "notification:queue", scope),
    ) catch {
      error => raise NotificationPromotionError::Notification(error)
    }
  } else {
    notification
  }
  let evidence = queued.bind_evidence(
    source_snapshot_id~,
    mapping_version~,
    evidence_id~,
  ) catch {
    error => raise NotificationPromotionError::Notification(error)
  }
  let candidate = Json::object({
    "notification_id": Json::string(queued.notification_id),
    "principal_id": Json::string(queued.principal_id),
    "recipient_id": Json::string(queued.recipient_id),
    "scope": Json::string(queued.scope),
    "channel": Json::string(channel_name(queued.channel)),
    "template_code": Json::string(queued.template_code),
    "subject": Json::string(queued.subject),
    "body": Json::string(queued.body),
    "source_event_id": Json::string(queued.source_event_id),
    "idempotency_key": Json::string(queued.idempotency_key),
    "state": Json::string(state_name(queued.state)),
    "source_snapshot_id": Json::string(evidence.source_snapshot_id),
    "mapping_version": Json::string(evidence.mapping_version),
    "evidence_id": Json::string(evidence.evidence_id),
    "delivery_requested": Json::boolean(
      queued.state != @notification_domain.NotificationState::Draft,
    ),
    "external_delivery_confirmed": Json::boolean(false),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("notification-outbox-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("notification_outbox"),
        "target_id": Json::string(queued.notification_id),
        "target_candidate": candidate,
      }),
    ]),
    "delivery_requested": Json::boolean(
      queued.state != @notification_domain.NotificationState::Draft,
    ),
    "external_delivery_confirmed": Json::boolean(false),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise NotificationPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: notification <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      NotificationPromotionError::InvalidInput => {
        println("notification promotion failed: invalid input")
        @sys.exit(1)
      }
      NotificationPromotionError::Io(_) => {
        println("notification promotion failed: filesystem error")
        @sys.exit(1)
      }
      NotificationPromotionError::Notification(_) => {
        println("notification promotion failed: notification validation")
        @sys.exit(1)
      }
    }
  }
}
