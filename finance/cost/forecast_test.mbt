///|
test "cost forecast links accepted progress to an expected overrun" {
  let forecast = CostForecast::new(
    project_scope="project:p-001",
    target=@finance.Money::new(minor=1000000, currency="CNY"),
    committed=@finance.Money::new(minor=100000, currency="CNY"),
    actual=@finance.Money::new(minor=600000, currency="CNY"),
    progress_bps=5000L,
  )
  assert_eq(forecast.forecast_at_completion.minor, 1200000L)
  assert_eq(forecast.variance_minor, -200000L)
}

///|
test "cost forecast uses target before progress is accepted" {
  let forecast = CostForecast::new(
    project_scope="project:p-001",
    target=@finance.Money::new(minor=1000000, currency="CNY"),
    committed=@finance.Money::new(minor=100000, currency="CNY"),
    actual=@finance.Money::new(minor=0, currency="CNY"),
    progress_bps=0L,
  )
  assert_eq(forecast.forecast_at_completion.minor, 1000000L)
  assert_eq(forecast.variance_minor, 0L)
}

///|
test "cost forecast persists progress-linked variance" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let forecast = CostForecast::new(
    project_scope="project:p-001",
    target=@finance.Money::new(minor=1000000, currency="CNY"),
    committed=@finance.Money::new(minor=100000, currency="CNY"),
    actual=@finance.Money::new(minor=600000, currency="CNY"),
    progress_bps=5000L,
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="cost_forecast",
    aggregate_id="project:p-001",
  )
  let projection = forecast.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("-200000"))
      assert_true(latest.payload.contains("5000"))
    }
    None => fail("expected forecast projection")
  }
}
