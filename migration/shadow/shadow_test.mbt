///|
test "shadow plan derives record counts and provided control totals" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema)
    .migrate(migration)
    .append_batch([
      @store.StoredRecord::new(
        record_type="legacy/project",
        record_id="p-shadow-001",
        schema_version=1,
        payload="{\"proj_guid\":\"p-shadow-001\"}",
        source_id="erp:ep_project:p-shadow-001",
      ),
      @store.StoredRecord::new(
        record_type="legacy/project",
        record_id="p-shadow-002",
        schema_version=1,
        payload="{\"proj_guid\":\"p-shadow-002\"}",
        source_id="erp:ep_project:p-shadow-002",
      ),
    ])
  let plan = ShadowPlan::new(
      run_id="run-shadow-001",
      source_snapshot_id="erp-shadow-001",
    )
    .add_expectation({
      metric_id: "project-count",
      domain: "project",
      dimension: "company:co-001",
      measure: ShadowMeasure::RecordCount("legacy/project"),
      source_value: 2L,
      tolerance: 0L,
    })
    .add_expectation({
      metric_id: "opening-cash",
      domain: "treasury",
      dimension: "currency:CNY",
      measure: ShadowMeasure::ProvidedValue(100000L),
      source_value: 100005L,
      tolerance: 10L,
    })
  let comparison = plan.compare(store)
  assert_true(comparison.summary.accepted)
  assert_eq(comparison.summary.exact_count, 1)
  assert_eq(comparison.summary.within_tolerance_count, 1)
}

///|
test "shadow plan exposes a mismatched source control total" {
  let plan = ShadowPlan::new(
    run_id="run-shadow-002",
    source_snapshot_id="erp-shadow-002",
  ).add_expectation({
    metric_id: "project-count",
    domain: "project",
    dimension: "company:co-001",
    measure: ShadowMeasure::RecordCount("legacy/project"),
    source_value: 1L,
    tolerance: 0L,
  })
  let comparison = plan.compare(
    @store.RecordStore::new(@schema.SchemaState::initial()),
  )
  assert_true(!comparison.summary.accepted)
  assert_eq(comparison.summary.mismatch_count, 1)
}
