///|
test "sanitized ERP backup inventory preserves measured table controls" {
  let inventory = @erp.sanitized_v0_1_0_snapshot()
  assert_eq(inventory.snapshot_id, "erp-v0.1.0-snapshot")
  assert_eq(inventory.tables.length(), 26)
  assert_eq(inventory.total_rows, 120L)
  assert_eq(
    inventory.count_disposition(@erp.SnapshotTableDisposition::Mapped),
    5,
  )
  assert_eq(
    inventory.count_disposition(@erp.SnapshotTableDisposition::Planned),
    0,
  )
  assert_eq(
    inventory.count_disposition(@erp.SnapshotTableDisposition::TypedStaged),
    16,
  )
  assert_eq(
    inventory.count_disposition(@erp.SnapshotTableDisposition::EmptySource),
    5,
  )
  assert_eq(inventory.rows_for(@erp.SnapshotTableDisposition::Mapped), 19L)
  assert_eq(
    inventory.rows_for(@erp.SnapshotTableDisposition::TypedStaged),
    101L,
  )
  match inventory.table(table_name="cb_cost") {
    Some(table) => {
      assert_eq(table.row_count, 7L)
      assert_true(table.disposition is @erp.SnapshotTableDisposition::Mapped)
    }
    None => fail("missing cb_cost control")
  }
  match inventory.table(table_name="sys_user") {
    Some(table) =>
      assert_true(
        table.disposition is @erp.SnapshotTableDisposition::TypedStaged,
      )
    None => fail("missing sys_user control")
  }
}

///|
test "ERP inventory compiles into count parity for every source table" {
  let inventory = @erp.sanitized_v0_1_0_snapshot()
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
  let first = @erp.SnapshotTable::new(
    table_name="ep_project",
    row_count=1L,
    target_record_type="legacy/project",
    disposition=@erp.SnapshotTableDisposition::Mapped,
  )
  try
    @erp.SnapshotInventory::new(
      snapshot_id="erp-test",
      source_path="fixture.db",
      tables=[first, first],
    )
  catch {
    @erp.SnapshotInventoryError::DuplicateTable => ()
    _ => fail("wrong duplicate error")
  } noraise {
    _ => fail("expected duplicate table error")
  }
  try
    @erp.SnapshotTable::new(
      table_name="bad",
      row_count=-1L,
      target_record_type="legacy/bad",
      disposition=@erp.SnapshotTableDisposition::Planned,
    )
  catch {
    @erp.SnapshotInventoryError::NegativeRowCount => ()
    _ => fail("wrong negative row error")
  } noraise {
    _ => fail("expected negative row error")
  }
}
