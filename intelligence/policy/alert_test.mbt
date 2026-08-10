///|
test "high-impact policy alerts require source review before interpretation" {
  let previous = policy_document("v1", "布局算力中心。")
  let current = policy_document("v2", "建设“全市超级算力节点”。")
  let analysis = analyze_policy(
    Some(previous),
    current,
    changping_development_signal_rules(),
  )
  let alerts = build_policy_alerts(analysis, minimum_importance=80)
  assert_true(!alerts.is_empty())
  assert_true(alerts.any(alert => alert.severity == Critical))
  let alert = alerts[0]
  try
    alert.confirm_interpretation(
      reviewer_id="policy-owner",
      evidence="interpretation note",
    )
  catch {
    InvalidState => ()
    _ => fail("expected review-order failure")
  } noraise {
    _ => fail("interpretation must not precede source confirmation")
  }
  let reviewed = alert
    .confirm_source(
      reviewer_id="source-owner",
      evidence="canonical official page and publication date checked",
    )
    .confirm_interpretation(
      reviewer_id="policy-owner",
      evidence="wording comparison approved; no funding claim inferred",
    )
  assert_true(reviewed.review_state == InterpretationConfirmed)
  assert_true(reviewed.review_evidence.contains("no funding claim"))
}
