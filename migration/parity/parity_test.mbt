///|
test "parity report classifies exact, tolerant, and mismatched metrics" {
  let report = ParityReport::new(
      run_id="run-parity-001",
      source_snapshot_id="erp-snapshot-001",
    )
    .add_metric({
      metric_id: "project-count",
      domain: "project",
      dimension: "company:co-001",
      source_value: 10L,
      target_value: 10L,
      tolerance: 0L,
    })
    .add_metric({
      metric_id: "receivable-minor",
      domain: "receivable",
      dimension: "period:2026-06",
      source_value: 100000L,
      target_value: 100005L,
      tolerance: 10L,
    })
    .add_metric({
      metric_id: "payable-minor",
      domain: "payable",
      dimension: "period:2026-06",
      source_value: 200000L,
      target_value: 199000L,
      tolerance: 10L,
    })
  let summary = report.evaluate()
  assert_eq(summary.exact_count, 1)
  assert_eq(summary.within_tolerance_count, 1)
  assert_eq(summary.mismatch_count, 1)
  assert_true(!summary.accepted)
}

///|
test "parity report rejects duplicate metrics and negative tolerance" {
  let report = ParityReport::new(
    run_id="run-parity-002",
    source_snapshot_id="erp-snapshot-001",
  ).add_metric({
    metric_id: "project-count",
    domain: "project",
    dimension: "company:co-001",
    source_value: 1L,
    target_value: 1L,
    tolerance: 0L,
  })
  try
    report.add_metric({
      metric_id: "project-count",
      domain: "project",
      dimension: "company:co-002",
      source_value: 1L,
      target_value: 1L,
      tolerance: 0L,
    })
  catch {
    ParityError::DuplicateMetric => ()
    _ => fail("wrong parity error")
  } noraise {
    _ => fail("expected duplicate metric error")
  }
  try
    report.add_metric({
      metric_id: "bad-tolerance",
      domain: "project",
      dimension: "company:co-001",
      source_value: 1L,
      target_value: 1L,
      tolerance: -1L,
    })
  catch {
    ParityError::NegativeTolerance => ()
    _ => fail("wrong tolerance error")
  } noraise {
    _ => fail("expected tolerance error")
  }
}
