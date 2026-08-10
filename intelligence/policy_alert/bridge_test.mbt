///|
fn alert_grant() -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-policy-alert",
    principal_id: "company-1",
    actor_id: "policy-agent",
    capability: "notification:create",
    scope: "policy:changping-plan",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn reviewed_alert() -> @policy.PolicyAlert {
  {
    alert_id: "policy:changping-plan:v2:1",
    severity: Critical,
    title: "市级算力节点",
    summary: "政策表述强化：全市超级算力节点",
    change_kind: SignalStrengthened,
    evidence: "全市超级算力节点",
    source_document_id: "changping-plan",
    source_version: "v2",
    source_url: "https://example.gov.cn/policy",
    review_state: InterpretationConfirmed,
    reviewed_by: "policy-owner",
    review_evidence: "source and interpretation checked",
  }
}

///|
test "reviewed policy alert becomes an in-app draft without delivery" {
  let notification = notification_for_policy_alert(
    reviewed_alert(),
    principal_id="company-1",
    recipient_id="owner-1",
    actor_id="policy-agent",
    grant=alert_grant(),
  )
  assert_true(notification.channel == @notification.NotificationChannel::InApp)
  assert_true(notification.state == @notification.NotificationState::Draft)
  assert_true(notification.body.contains("预算和采购意图仍未确认"))
}
