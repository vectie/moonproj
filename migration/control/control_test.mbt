///|
test "opening controls compile into a reproducible shadow plan" {
  let controls = OpeningControlSet::new(source_snapshot_id="erp-opening-001")
    .add({
      metric_id: "cash:company:co-001:CNY",
      domain: "treasury",
      dimension: "company:co-001",
      value: 100000L,
      tolerance: 0L,
    })
    .add({
      metric_id: "ar:company:co-001:CNY",
      domain: "receivable",
      dimension: "company:co-001",
      value: 250000L,
      tolerance: 100L,
    })
  let plan = controls.to_shadow_plan(run_id="run-opening-001")
  let comparison = plan.compare(
    @store.RecordStore::new(@schema.SchemaState::initial()),
  )
  assert_true(comparison.summary.accepted)
  assert_eq(comparison.summary.within_tolerance_count, 0)
  assert_eq(comparison.summary.exact_count, 2)
}

///|
test "opening controls reject duplicate or negative totals" {
  let controls = OpeningControlSet::new(source_snapshot_id="erp-opening-002")
  let controls = controls.add({
    metric_id: "cash",
    domain: "treasury",
    dimension: "company:co-001",
    value: 1L,
    tolerance: 0L,
  })
  try
    controls.add({
      metric_id: "cash",
      domain: "treasury",
      dimension: "company:co-002",
      value: 2L,
      tolerance: 0L,
    })
  catch {
    ControlError::DuplicateMetric => ()
    _ => fail("wrong control error")
  } noraise {
    _ => fail("expected duplicate control")
  }
  try
    controls.add({
      metric_id: "bad",
      domain: "treasury",
      dimension: "company:co-001",
      value: -1L,
      tolerance: 0L,
    })
  catch {
    ControlError::NegativeValue => ()
    _ => fail("wrong negative control error")
  } noraise {
    _ => fail("expected negative control")
  }
}
