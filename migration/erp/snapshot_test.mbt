///|
test "sanitized ERP backup inventory preserves measured table controls" {
  let inventory = sanitized_v0_1_0_snapshot()
  assert_eq(inventory.snapshot_id, "erp-v0.1.0-snapshot")
  assert_eq(inventory.tables.length(), 26)
  assert_eq(inventory.total_rows, 120L)
  assert_eq(inventory.count_disposition(SnapshotTableDisposition::Mapped), 5)
  assert_eq(inventory.count_disposition(SnapshotTableDisposition::Planned), 0)
  assert_eq(
    inventory.count_disposition(SnapshotTableDisposition::TypedStaged),
    16,
  )
  assert_eq(
    inventory.count_disposition(SnapshotTableDisposition::EmptySource),
    5,
  )
  assert_eq(inventory.rows_for(SnapshotTableDisposition::Mapped), 19L)
  assert_eq(inventory.rows_for(SnapshotTableDisposition::TypedStaged), 101L)
  match inventory.table(table_name="cb_cost") {
    Some(table) => {
      assert_eq(table.row_count, 7L)
      assert_true(table.disposition is SnapshotTableDisposition::Mapped)
    }
    None => fail("missing cb_cost control")
  }
  match inventory.table(table_name="sys_user") {
    Some(table) =>
      assert_true(table.disposition is SnapshotTableDisposition::TypedStaged)
    None => fail("missing sys_user control")
  }
}

///|
test "ERP inventory compiles into count parity for every source table" {
  let inventory = sanitized_v0_1_0_snapshot()
  let plan = inventory.to_shadow_plan(run_id="run-erp-v0-1-0")
  let comparison = plan.compare(
    @store.RecordStore::new(@schema.SchemaState::initial()),
  )
  assert_eq(comparison.report.metrics.length(), 26)
  assert_eq(comparison.summary.exact_count, 5)
  assert_eq(comparison.summary.mismatch_count, 21)
  assert_true(!comparison.summary.accepted)
}

///|
test "snapshot inventory rejects duplicate table names and negative counts" {
  let first = SnapshotTable::new(
    table_name="ep_project",
    row_count=1L,
    target_record_type="legacy/project",
    disposition=SnapshotTableDisposition::Mapped,
  )
  try
    SnapshotInventory::new(snapshot_id="erp-test", source_path="fixture.db", tables=[
      first, first,
    ])
  catch {
    SnapshotInventoryError::DuplicateTable => ()
    _ => fail("wrong duplicate error")
  } noraise {
    _ => fail("expected duplicate table error")
  }
  try
    SnapshotTable::new(
      table_name="bad",
      row_count=-1L,
      target_record_type="legacy/bad",
      disposition=SnapshotTableDisposition::Planned,
    )
  catch {
    SnapshotInventoryError::NegativeRowCount => ()
    _ => fail("wrong negative row error")
  } noraise {
    _ => fail("expected negative row error")
  }
}
