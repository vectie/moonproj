///|
/// The disposition of a source table in a sanitized snapshot inventory.
/// `Mapped` means a target record type and domain importer seam exist;
/// `TypedStaged` means a typed preservation envelope exists but target-owned
/// state-machine validation is still pending; `Planned` records a source table
/// whose mapping is still a migration work item; `EmptySource` keeps an empty
/// table visible without creating fake targets.
pub(all) enum SnapshotTableDisposition {
  Mapped
  TypedStaged
  Planned
  EmptySource
} derive(Debug, Eq)

///|
/// A row-count control for one source table. The inventory intentionally keeps
/// metadata and counts only; it never embeds credentials, attachments, or raw
/// ERP payloads.
pub(all) struct SnapshotTable {
  table_name : String
  row_count : Int64
  target_record_type : String
  disposition : SnapshotTableDisposition
} derive(Debug, Eq)

///|
/// A sanitized, repeatable inventory of one ERP database snapshot.
pub(all) struct SnapshotInventory {
  snapshot_id : String
  source_path : String
  tables : Array[SnapshotTable]
  total_rows : Int64
} derive(Debug, Eq)

///|
pub(all) suberror SnapshotInventoryError {
  EmptyIdentifier
  NegativeRowCount
  DuplicateTable
  MissingTargetType
  Shadow(@shadow.ShadowError)
} derive(Debug, Eq)

///|
pub fn SnapshotTable::new(
  table_name~ : String,
  row_count~ : Int64,
  target_record_type~ : String,
  disposition~ : SnapshotTableDisposition,
) -> SnapshotTable raise SnapshotInventoryError {
  if table_name.trim() == "" {
    raise SnapshotInventoryError::EmptyIdentifier
  }
  if row_count < 0L {
    raise SnapshotInventoryError::NegativeRowCount
  }
  match disposition {
    SnapshotTableDisposition::EmptySource => ()
    _ =>
      if target_record_type.trim() == "" {
        raise SnapshotInventoryError::MissingTargetType
      }
  }
  { table_name, row_count, target_record_type, disposition }
}

///|
pub fn SnapshotInventory::new(
  snapshot_id~ : String,
  source_path~ : String,
  tables~ : Array[SnapshotTable],
) -> SnapshotInventory raise SnapshotInventoryError {
  if snapshot_id.trim() == "" || source_path.trim() == "" {
    raise SnapshotInventoryError::EmptyIdentifier
  }
  let mut total_rows = 0L
  let seen : Array[String] = []
  for table in tables {
    for existing in seen {
      if existing == table.table_name {
        raise SnapshotInventoryError::DuplicateTable
      }
    }
    seen.push(table.table_name)
    total_rows += table.row_count
  }
  { snapshot_id, source_path, tables: tables.copy(), total_rows }
}

///|
/// Locate one source table without exposing the underlying array to callers.
pub fn SnapshotInventory::table(
  self : SnapshotInventory,
  table_name~ : String,
) -> SnapshotTable? {
  for table in self.tables {
    if table.table_name == table_name {
      return Some(table)
    }
  }
  None
}

///|
pub fn SnapshotInventory::count_disposition(
  self : SnapshotInventory,
  disposition : SnapshotTableDisposition,
) -> Int {
  let mut count = 0
  for table in self.tables {
    if table.disposition == disposition {
      count += 1
    }
  }
  count
}

///|
pub fn SnapshotInventory::rows_for(
  self : SnapshotInventory,
  disposition : SnapshotTableDisposition,
) -> Int64 {
  let mut rows = 0L
  for table in self.tables {
    if table.disposition == disposition {
      rows += table.row_count
    }
  }
  rows
}

///|
/// Compile source row counts into target record-count expectations. Empty
/// source tables are included as zero controls, while planned tables still
/// produce a failing metric until their target importer is implemented.
pub fn SnapshotInventory::to_shadow_plan(
  self : SnapshotInventory,
  run_id~ : String,
) -> @shadow.ShadowPlan raise SnapshotInventoryError {
  let mut plan = @shadow.ShadowPlan::new(
    run_id~,
    source_snapshot_id=self.snapshot_id,
  ) catch {
    error => raise SnapshotInventoryError::Shadow(error)
  }
  for table in self.tables {
    plan = plan.add_expectation({
      metric_id: "rows:" + table.table_name,
      domain: "erp",
      dimension: table.table_name,
      measure: @shadow.ShadowMeasure::RecordCount(table.target_record_type),
      source_value: table.row_count,
      tolerance: 0L,
    }) catch {
      error => raise SnapshotInventoryError::Shadow(error)
    }
  }
  plan
}

///|
/// Row-count inventory measured from the checked-in ERP backup snapshot. This
/// is metadata-only and deliberately excludes raw rows and sensitive fields.
pub fn sanitized_v0_1_0_snapshot() -> SnapshotInventory {
  try! SnapshotInventory::new(
    snapshot_id="erp-v0.1.0-snapshot",
    source_path="../erp/erp_new/backup/erp-v0.1.0-snapshot.db",
    tables=[
      try! SnapshotTable::new(
        table_name="audit_log",
        row_count=2L,
        target_record_type="legacy/audit_event",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="cb_contract",
        row_count=2L,
        target_record_type="legacy/contract",
        disposition=SnapshotTableDisposition::Mapped,
      ),
      try! SnapshotTable::new(
        table_name="cb_cost",
        row_count=7L,
        target_record_type="legacy/cost",
        disposition=SnapshotTableDisposition::Mapped,
      ),
      try! SnapshotTable::new(
        table_name="cb_expense_detail",
        row_count=0L,
        target_record_type="legacy/expense_detail",
        disposition=SnapshotTableDisposition::EmptySource,
      ),
      try! SnapshotTable::new(
        table_name="cb_expense_split",
        row_count=0L,
        target_record_type="legacy/expense_split",
        disposition=SnapshotTableDisposition::EmptySource,
      ),
      try! SnapshotTable::new(
        table_name="vcb_expense",
        row_count=0L,
        target_record_type="legacy/expense",
        disposition=SnapshotTableDisposition::EmptySource,
      ),
      try! SnapshotTable::new(
        table_name="cb_htfk_apply",
        row_count=3L,
        target_record_type="legacy/payment_application",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="cb_htfkplan",
        row_count=4L,
        target_record_type="legacy/payment_plan",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="cb_loan_offset",
        row_count=1L,
        target_record_type="legacy/advance_offset",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="ep_project",
        row_count=2L,
        target_record_type="legacy/project",
        disposition=SnapshotTableDisposition::Mapped,
      ),
      try! SnapshotTable::new(
        table_name="jd_task",
        row_count=9L,
        target_record_type="legacy/task",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="jd_task_report",
        row_count=1L,
        target_record_type="legacy/task_report",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="mu_business_unit",
        row_count=7L,
        target_record_type="legacy/business_unit",
        disposition=SnapshotTableDisposition::Mapped,
      ),
      try! SnapshotTable::new(
        table_name="my_biz_param_option",
        row_count=5L,
        target_record_type="legacy/parameter",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="proj_lifecycle_instance",
        row_count=14L,
        target_record_type="legacy/project_lifecycle_instance",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="proj_lifecycle_stage",
        row_count=7L,
        target_record_type="legacy/project_lifecycle_stage",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="sys_user",
        row_count=5L,
        target_record_type="legacy/user",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="tzsy_plan_index",
        row_count=26L,
        target_record_type="legacy/investment_index",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="tzsy_version",
        row_count=1L,
        target_record_type="legacy/investment_version",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="vys_proceeding",
        row_count=3L,
        target_record_type="legacy/proceeding",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="vcb_loan_simple",
        row_count=1L,
        target_record_type="legacy/advance",
        disposition=SnapshotTableDisposition::Mapped,
      ),
      try! SnapshotTable::new(
        table_name="wf_process_def",
        row_count=2L,
        target_record_type="legacy/workflow_process_definition",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="wf_process_instance",
        row_count=0L,
        target_record_type="legacy/workflow_process_instance",
        disposition=SnapshotTableDisposition::EmptySource,
      ),
      try! SnapshotTable::new(
        table_name="wf_step_action",
        row_count=0L,
        target_record_type="legacy/workflow_step_action",
        disposition=SnapshotTableDisposition::EmptySource,
      ),
      try! SnapshotTable::new(
        table_name="wf_step_assignee",
        row_count=6L,
        target_record_type="legacy/workflow_step_assignee",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
      try! SnapshotTable::new(
        table_name="wf_step_def",
        row_count=12L,
        target_record_type="legacy/workflow_step_definition",
        disposition=SnapshotTableDisposition::TypedStaged,
      ),
    ],
  )
}
