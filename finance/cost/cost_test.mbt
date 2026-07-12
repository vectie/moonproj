///|
test "dynamic cost preserves B equals D plus E plus F plus G" {
  let breakdown = CostBreakdown::new(
    direct_minor=100000,
    indirect_minor=20000,
    contingency_minor=5000,
    other_minor=3000,
  )
  let cost = calculate_dynamic_cost(currency="CNY", breakdown)
  assert_eq(cost.total_minor, 128000)
  assert_eq(cost.total_minor, cost.breakdown.total_minor())
}

///|
test "dynamic cost rejects negative components" {
  try
    CostBreakdown::new(
      direct_minor=-1,
      indirect_minor=0,
      contingency_minor=0,
      other_minor=0,
    )
  catch {
    CostError::NegativeComponent => ()
    _ => fail("wrong cost error")
  } noraise {
    _ => fail("expected cost error")
  }
}

///|
test "dynamic cost persists the four-component invariant" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let cost = calculate_dynamic_cost(
    currency="CNY",
    CostBreakdown::new(
      direct_minor=100000,
      indirect_minor=20000,
      contingency_minor=5000,
      other_minor=3000,
    ),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="dynamic_cost",
    aggregate_id="cost-001",
  )
  let projection = cost.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("128000"))
      assert_true(latest.payload.contains("contingency_minor"))
    }
    None => fail("expected cost projection")
  }
}
