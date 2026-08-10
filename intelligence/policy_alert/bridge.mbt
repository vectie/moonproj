///|
pub(all) suberror PolicyAlertBridgeError {
  AlertNotReviewed
  Notification(@notification.NotificationError)
} derive(Debug, Eq)

///|
fn severity_label(severity : @policy.PolicyAlertSeverity) -> String {
  match severity {
    Information => "提示"
    Attention => "关注"
    Critical => "重要"
  }
}

///|
/// Create an in-app outbox draft from a reviewed policy alert. This function
/// does not queue or deliver the notification and cannot send network traffic.
pub fn notification_for_policy_alert(
  alert : @policy.PolicyAlert,
  principal_id~ : String,
  recipient_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @notification.Notification raise PolicyAlertBridgeError {
  if alert.review_state !=
    @policy.PolicyAlertReviewState::InterpretationConfirmed {
    raise AlertNotReviewed
  }
  @notification.Notification::new(
    notification_id="notification:\{alert.alert_id}",
    principal_id~,
    recipient_id~,
    scope="policy:\{alert.source_document_id}",
    channel=@notification.NotificationChannel::InApp,
    template_code="policy-change-reviewed-v1",
    subject="[\{severity_label(alert.severity)}] \{alert.title}",
    body="\{alert.summary}\n证据：\{alert.evidence}\n来源：\{alert.source_url}\n状态：来源与解读已人工复核；预算和采购意图仍未确认。",
    source_event_id=alert.alert_id,
    idempotency_key="policy-alert:\{alert.alert_id}",
    actor_id~,
    grant~,
  ) catch {
    error => raise Notification(error)
  }
}
