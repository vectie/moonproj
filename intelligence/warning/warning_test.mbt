///|
fn warning_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-warning",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "cost forecast warning is deterministic and resolvable" {
  let forecast = @cost.CostForecast::new(
    project_scope="project:p-001",
    target=@finance.Money::new(minor=100000, currency="CNY"),
    committed=@finance.Money::new(minor=10000, currency="CNY"),
    actual=@finance.Money::new(minor=60000, currency="CNY"),
    progress_bps=5000L,
  )
  let warning = warning_for_cost_forecast(
    warning_id="warning-001",
    principal_id="co-001",
    forecast,
    actor_id="alice",
    grant=warning_grant("warning:create"),
  ).unwrap()
  let resolved = warning
    .acknowledge(actor_id="alice", grant=warning_grant("warning:acknowledge"))
    .resolve(actor_id="alice", grant=warning_grant("warning:resolve"))
  assert_true(resolved.state == WarningState::Resolved)
  assert_true(resolved.severity == WarningSeverity::Critical)
}

///|
test "warning rule stays silent for an on-target forecast" {
  let forecast = @cost.CostForecast::new(
    project_scope="project:p-001",
    target=@finance.Money::new(minor=100000, currency="CNY"),
    committed=@finance.Money::new(minor=0, currency="CNY"),
    actual=@finance.Money::new(minor=0, currency="CNY"),
    progress_bps=0L,
  )
  assert_true(
    warning_for_cost_forecast(
      warning_id="warning-002",
      principal_id="co-001",
      forecast,
      actor_id="alice",
      grant=warning_grant("warning:create"),
    )
    is None,
  )
}
