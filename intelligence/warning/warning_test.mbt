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
  let evidence = resolved.bind_evidence(
    source_snapshot_id="erp-snapshot:warning-001",
    mapping_version="warning-map-v1",
    evidence_id="scan:cost-forecast:warning-001",
  )
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="warning_finding",
    aggregate_id="warning-001",
  )
  let projection = evidence.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("erp-snapshot:warning-001"))
      assert_true(latest.payload.contains("resolved"))
      assert_true(latest.payload.contains("notification_delivered"))
      assert_true(latest.payload.contains("workflow_mutated"))
      assert_true(latest.payload.contains("cash_released"))
    }
    None => fail("expected warning projection")
  }
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
