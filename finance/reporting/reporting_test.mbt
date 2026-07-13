///|
fn report_grant() -> @foundation.AuthorityGrant {
  {
    grant_id: "consolidated-report-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "report:consolidate",
    scope: "report:2026-Q1",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn balanced_report(
  scope : String,
  reference : String,
  amount : Int64,
) -> @reconciliation.ReconciliationReport {
  try! @reconciliation.ReconciliationReport::new(scope~, lines=[
    {
      reference_id: reference,
      expected: try! @finance.Money::new(minor=amount, currency="CNY"),
      actual: try! @finance.Money::new(minor=amount, currency="CNY"),
    },
  ])
}

///|
test "consolidated report combines balanced sections under one snapshot" {
  let report = ConsolidatedReport::new(
    report_id="consolidated-2026-Q1",
    period_id="2026-Q1",
    principal_id="co-001",
    scope="report:2026-Q1",
    source_snapshot_id="erp-snapshot:abc123",
    mapping_versions=["mapped-accounting-v2", "mapped-treasury-v1"],
    reports=[
      balanced_report("project:p-001", "commitment-001", 120000),
      balanced_report("project:p-002", "cash-001", 80000),
    ],
    accounting_link_count=4,
    reconciled_link_count=4,
    actor_id="alice",
    grant=report_grant(),
  )
  assert_true(report.state == ConsolidatedReportState::Reconciled)
  assert_eq(report.expected_total.minor, 200000L)
  assert_eq(report.actual_total.minor, 200000L)
  assert_eq(report.sections.length(), 2)
  assert_eq(report.difference_minor, 0L)
}

///|
test "consolidated report rejects unbalanced or duplicate sections" {
  let unbalanced = try! @reconciliation.ReconciliationReport::new(
    scope="project:p-001",
    lines=[
      {
        reference_id: "bad-001",
        expected: try! @finance.Money::new(minor=100, currency="CNY"),
        actual: try! @finance.Money::new(minor=90, currency="CNY"),
      },
    ],
  )
  try
    ConsolidatedReport::new(
      report_id="consolidated-bad",
      period_id="2026-Q1",
      principal_id="co-001",
      scope="report:2026-Q1",
      source_snapshot_id="erp-snapshot:abc123",
      mapping_versions=["mapped-accounting-v2"],
      reports=[unbalanced],
      accounting_link_count=1,
      reconciled_link_count=0,
      actor_id="alice",
      grant=report_grant(),
    )
  catch {
    ReportingError::Reconciliation(_) => ()
    _ => fail("wrong consolidated report error")
  } noraise {
    _ => fail("expected unbalanced report rejection")
  }
  try
    ConsolidatedReport::new(
      report_id="consolidated-duplicate",
      period_id="2026-Q1",
      principal_id="co-001",
      scope="report:2026-Q1",
      source_snapshot_id="erp-snapshot:abc123",
      mapping_versions=["mapped-accounting-v2"],
      reports=[
        balanced_report("project:p-001", "one", 10),
        balanced_report("project:p-001", "two", 20),
      ],
      accounting_link_count=2,
      reconciled_link_count=2,
      actor_id="alice",
      grant=report_grant(),
    )
  catch {
    ReportingError::DuplicateSection => ()
    _ => fail("wrong duplicate section error")
  } noraise {
    _ => fail("expected duplicate section rejection")
  }
}

///|
test "consolidated report projection keeps non-posting controls" {
  let report = ConsolidatedReport::new(
    report_id="consolidated-projection",
    period_id="2026-Q1",
    principal_id="co-001",
    scope="report:2026-Q1",
    source_snapshot_id="erp-snapshot:abc123",
    mapping_versions=["mapped-accounting-v2"],
    reports=[balanced_report("project:p-001", "one", 1000)],
    accounting_link_count=1,
    reconciled_link_count=1,
    actor_id="alice",
    grant=report_grant(),
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
    aggregate_type="consolidated_report",
    aggregate_id="consolidated-projection",
  )
  let projection = report.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("consolidated-projection"))
      assert_true(latest.payload.contains("project:p-001"))
      assert_true(latest.payload.contains("cash_released"))
      assert_true(latest.payload.contains("period_posted"))
      assert_true(latest.payload.contains("tax_filed"))
      assert_true(latest.payload.contains("false"))
    }
    None => fail("expected consolidated report projection")
  }
}
