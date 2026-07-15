///|
/// Source schema inventory used by the migration cutover boundary.
fn migration_schema_tables() -> Array[String] {
  [
    "attachment", "audit_log", "cb_change_apply", "cb_contract", "cb_contract_milestone",
    "cb_cost", "cb_expense_detail", "cb_expense_split", "cb_htfk_apply", "cb_htfkplan",
    "cb_loan_offset", "cb_plan_version", "cb_r_master", "cb_subject_dict", "contract_split",
    "ep_project", "fund_dispatch", "fund_plan", "invoice_in", "invoice_out", "jd_task",
    "jd_task_report", "mkt_campaign", "mkt_channel", "mkt_material", "mkt_placement",
    "mu_business_unit", "my_biz_param_option", "proj_lifecycle_instance", "proj_lifecycle_stage",
    "proj_output", "proj_progress", "report_share_link", "sale_contract", "sale_customer",
    "sale_mortgage", "sale_refund", "sale_revenue", "sale_subscription", "srm_category",
    "srm_provider", "srm_provider_bu", "sys_email_outbox", "sys_message", "sys_param",
    "sys_password_history", "sys_report_template", "sys_role", "sys_user", "sys_user_pref",
    "sys_user_role", "sys_warning", "sys_warning_rule_custom", "sys_warning_scan",
    "sys_warning_subscription", "sys_warning_ticket", "tender_award", "tender_plan",
    "tzsy_excel_import", "tzsy_excel_sheet", "tzsy_plan_index", "tzsy_plan_line",
    "tzsy_profit_table", "tzsy_subject_mapping", "tzsy_version", "vcb_expense", "vcb_loan_simple",
    "vys_proceeding", "wf_approval_rule", "wf_process_def", "wf_process_instance",
    "wf_runtime_assignee", "wf_step_action", "wf_step_assignee", "wf_step_def",
  ]
}

///|
fn migration_snapshot_tables() -> Map[String, Bool] {
  {
    "audit_log": true,
    "cb_contract": true,
    "cb_cost": true,
    "cb_expense_detail": true,
    "cb_expense_split": true,
    "cb_htfk_apply": true,
    "cb_htfkplan": true,
    "cb_loan_offset": true,
    "ep_project": true,
    "jd_task": true,
    "jd_task_report": true,
    "mu_business_unit": true,
    "my_biz_param_option": true,
    "proj_lifecycle_instance": true,
    "proj_lifecycle_stage": true,
    "sys_user": true,
    "tzsy_plan_index": true,
    "tzsy_version": true,
    "vcb_expense": true,
    "vcb_loan_simple": true,
    "vys_proceeding": true,
    "wf_process_def": true,
    "wf_process_instance": true,
    "wf_step_action": true,
    "wf_step_assignee": true,
    "wf_step_def": true,
  }
}

///|
async fn migration_schema_coverage_response() -> Json raise CompanyServiceError {
  let tables = migration_schema_tables()
  let counts : Map[String, Int] = {}
  for table in tables {
    counts.set(table, 0)
  }
  let output = run_sql(
    "SELECT substring(record_type from 12), count(*)::text FROM company_record WHERE record_type LIKE 'legacy/raw/%' GROUP BY record_type",
  )
  for line in output.split("\n") {
    let value = line.trim().to_owned()
    if value.is_empty() {
      continue
    }
    let fields = value.split("|").map(fn(item) { item.to_owned() }).to_array()
    if fields.length() != 2 {
      raise fail("unexpected source schema coverage shape")
    }
    let table = fields[0]
    if counts.contains(table) {
      counts.set(table, parse_decimal(fields[1]))
    }
  }
  let snapshot = migration_snapshot_tables()
  let rows : Array[Json] = []
  let empty : Array[Json] = []
  let schema_only : Array[Json] = []
  let mut imported_count = 0
  for table in tables {
    let count = counts.get_or_default(table, 0)
    let state = if count > 0 {
      imported_count += 1
      "imported"
    } else if snapshot.contains(table) {
      "empty_in_snapshot"
    } else {
      schema_only.push(Json::string(table))
      "schema_only"
    }
    if count == 0 {
      empty.push(Json::string(table))
    }
    rows.push(
      Json::object({
        "table": Json::string(table),
        "rowCount": Json::number(count.to_double()),
        "state": Json::string(state),
      }),
    )
  }
  let coverage : Map[String, Int] = counts
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "tables": Json::array(rows),
      "schemaTableCount": Json::number(tables.length().to_double()),
      "snapshotTableCount": Json::number(snapshot.length().to_double()),
      "importedTableCount": Json::number(imported_count.to_double()),
      "schemaOnlyTableCount": Json::number(schema_only.length().to_double()),
      "schemaOnlyTables": Json::array(schema_only),
    }),
    "source_kind": Json::string("migration_inventory"),
    "source_snapshot_id": Json::string(
      "erp-snapshot:4ff5dd0ad0b75c6cfc572f99047fe41c5df4b8c48d3877f707fe063aec7dea03",
    ),
    "source_export_state": Json::string("source_export_incomplete"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(empty),
    "schema_only_source_tables": Json::array(schema_only),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "promotion_authorized": Json::boolean(false),
    "cutover_authorized": Json::boolean(false),
  })
}
