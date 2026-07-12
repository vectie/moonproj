///|
/// Typed source rows for tables that are present in the ERP schema but do not
/// yet have a target-owned state machine. These records normalize identity and
/// numeric fields without claiming that the source state is already accepted
/// by the company product.
pub(all) struct LegacyTaskRow {
  task_guid : String
  proj_guid : String
  bu_guid : String
  parent_task_guid : String?
  task_code : String?
  task_name : String
  task_type : String
  plan_begin_date : String
  plan_end_date : String
  actual_begin_date : String?
  actual_end_date : String?
  progress_bps : Int64
  owner_guid : String?
  status : String
  sort_order : Int
} derive(Debug, Eq)

///|
pub(all) struct LegacyTaskReportRow {
  report_guid : String
  task_guid : String
  report_date : String
  progress_bps : Int64
  summary : String?
  operator_guid : String
} derive(Debug, Eq)

///|
pub(all) struct LegacyPaymentPlanRow {
  plan_guid : String
  contract_guid : String
  bu_guid : String
  plan_period : String
  planned_date : String
  amount_minor : Int64
  currency : String
  approval_state : String
  handler_guid : String?
} derive(Debug, Eq)

///|
pub(all) struct LegacyPaymentApplicationRow {
  apply_guid : String
  apply_code : String
  contract_guid : String
  plan_guid : String?
  apply_class : Int
  apply_type_code : String?
  apply_state : String
  pay_state : String
  subject : String?
  apply_dept_guid : String
  applied_by : String
  apply_date : String
  amount_minor : Int64
  amount_bz_minor : Int64
  proj_guid : String?
  proj_type : String?
  contract_class : Int?
  bu_guid : String
} derive(Debug, Eq)

///|
pub(all) struct LegacyWorkflowDefinitionRow {
  process_guid : String
  process_key : String
  process_name : String
  biz_type : String
  active : Bool
  mandatory : Bool
  bu_guid : String?
} derive(Debug, Eq)

///|
pub(all) struct LegacyWorkflowStepRow {
  step_guid : String
  process_guid : String
  step_key : String
  step_order : Int
  step_type : Int
  step_name : String
  threshold : Int
  remind_days : Int?
  warn_days : Int?
} derive(Debug, Eq)

///|
pub(all) struct LegacyWorkflowAssigneeRow {
  assignee_guid : String
  step_guid : String
  user_guid : String?
  weight : Int
} derive(Debug, Eq)

///|
pub(all) struct LegacyLifecycleStageRow {
  stage_code : String
  stage_name : String
  stage_order : Int
} derive(Debug, Eq)

///|
pub(all) struct LegacyLifecycleInstanceRow {
  instance_id : String
  proj_guid : String
  stage_code : String
  planned_start : String?
  planned_end : String?
  actual_start : String?
  actual_end : String?
  status : String
  progress_bps : Int64
} derive(Debug, Eq)

///|
pub(all) struct LegacyInvestmentVersionRow {
  version_guid : String
  proj_guid : String
  bu_guid : String
  version_name : String
  version_no : Int
  current : Bool
  created_by : String
  created_at : String
  remark : String?
} derive(Debug, Eq)

///|
pub(all) struct LegacyInvestmentIndexRow {
  index_guid : String
  version_guid : String
  proj_guid : String
  dimension : String
  full_code : String
  index_name : String
  parent_code : String?
  unit : String?
  value_repr : String?
  remark : String?
  sort_order : Int
} derive(Debug, Eq)

///|
pub(all) struct LegacyLoanOffsetRow {
  offset_guid : String
  loan_guid : String
  amount_minor : Int64
  offset_date : String
  related_expense_guid : String?
  remark : String?
  operator_guid : String
} derive(Debug, Eq)

///|
pub(all) struct LegacyParameterRow {
  parameter_id : String
  parameter_name : String
  parameter_code : String
  parameter_value : String
  display_order : Int
  enabled : Bool
} derive(Debug, Eq)

///|
pub(all) struct LegacyProceedingRow {
  proceeding_guid : String
  proceeding_code : String
  proceeding_name : String
  manager_guid : String?
  apply_dept_guid : String?
  cost_code : String?
  enabled : Bool
} derive(Debug, Eq)

///|
/// A credential-safe user row. Password hashes and authentication secrets are
/// intentionally excluded; credential migration requires a separate security
/// approval path.
pub(all) struct LegacyUserRow {
  user_id : String
  user_code : String
  user_name : String
  emp_name : String?
  super_user : Bool
  bu_guid : String?
  dept_guid : String?
  enabled : Bool
  fail_login_count : Int
  last_login_time : String?
} derive(Debug, Eq)

///|
pub(all) struct LegacyAuditRow {
  log_id : String
  user_id : String?
  action : String
  target_type : String?
  target_id : String?
  ip : String?
  created_at : String
} derive(Debug, Eq)

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn int64_json(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn validate_progress(value : Int64) -> Unit raise ErpImportError {
  if value < 0L || value > 10000L {
    raise ErpImportError::InvalidValue
  }
}

///|
fn validate_nonnegative(value : Int64) -> Unit raise ErpImportError {
  if value < 0L {
    raise ErpImportError::InvalidValue
  }
}

///|
fn typed_source_record(
  table_name~ : String,
  record_type~ : String,
  record_id~ : String,
  schema_version~ : Int,
  payload~ : Json,
) -> @store.StoredRecord raise ErpImportError {
  if table_name.trim() == "" ||
    record_type.trim() == "" ||
    record_id.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  legacy_record(
    record_type~,
    record_id~,
    source_id="erp:" + table_name + ":" + record_id,
    schema_version~,
    payload=payload.stringify(),
  )
}

///|
pub fn task_record(
  row : LegacyTaskRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_progress(row.progress_bps)
  typed_source_record(
    table_name="jd_task",
    record_type="legacy/task",
    record_id=row.task_guid,
    schema_version~,
    payload=Json::object({
      "task_guid": Json::string(row.task_guid),
      "proj_guid": Json::string(row.proj_guid),
      "bu_guid": Json::string(row.bu_guid),
      "parent_task_guid": optional_string_json(row.parent_task_guid),
      "task_code": optional_string_json(row.task_code),
      "task_name": Json::string(row.task_name),
      "task_type": Json::string(row.task_type),
      "plan_begin_date": Json::string(row.plan_begin_date),
      "plan_end_date": Json::string(row.plan_end_date),
      "actual_begin_date": optional_string_json(row.actual_begin_date),
      "actual_end_date": optional_string_json(row.actual_end_date),
      "progress_bps": int64_json(row.progress_bps),
      "owner_guid": optional_string_json(row.owner_guid),
      "status": Json::string(row.status),
      "sort_order": int_json(row.sort_order),
    }),
  )
}

///|
pub fn task_report_record(
  row : LegacyTaskReportRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_progress(row.progress_bps)
  typed_source_record(
    table_name="jd_task_report",
    record_type="legacy/task_report",
    record_id=row.report_guid,
    schema_version~,
    payload=Json::object({
      "report_guid": Json::string(row.report_guid),
      "task_guid": Json::string(row.task_guid),
      "report_date": Json::string(row.report_date),
      "progress_bps": int64_json(row.progress_bps),
      "summary": optional_string_json(row.summary),
      "operator_guid": Json::string(row.operator_guid),
    }),
  )
}

///|
pub fn payment_plan_record(
  row : LegacyPaymentPlanRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_nonnegative(row.amount_minor)
  typed_source_record(
    table_name="cb_htfkplan",
    record_type="legacy/payment_plan",
    record_id=row.plan_guid,
    schema_version~,
    payload=Json::object({
      "plan_guid": Json::string(row.plan_guid),
      "contract_guid": Json::string(row.contract_guid),
      "bu_guid": Json::string(row.bu_guid),
      "plan_period": Json::string(row.plan_period),
      "planned_date": Json::string(row.planned_date),
      "amount_minor": int64_json(row.amount_minor),
      "currency": Json::string(row.currency),
      "approval_state": Json::string(row.approval_state),
      "handler_guid": optional_string_json(row.handler_guid),
    }),
  )
}

///|
pub fn payment_application_record(
  row : LegacyPaymentApplicationRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_nonnegative(row.amount_minor)
  validate_nonnegative(row.amount_bz_minor)
  typed_source_record(
    table_name="cb_htfk_apply",
    record_type="legacy/payment_application",
    record_id=row.apply_guid,
    schema_version~,
    payload=Json::object({
      "apply_guid": Json::string(row.apply_guid),
      "apply_code": Json::string(row.apply_code),
      "contract_guid": Json::string(row.contract_guid),
      "plan_guid": optional_string_json(row.plan_guid),
      "apply_class": int_json(row.apply_class),
      "apply_type_code": optional_string_json(row.apply_type_code),
      "apply_state": Json::string(row.apply_state),
      "pay_state": Json::string(row.pay_state),
      "subject": optional_string_json(row.subject),
      "apply_dept_guid": Json::string(row.apply_dept_guid),
      "applied_by": Json::string(row.applied_by),
      "apply_date": Json::string(row.apply_date),
      "amount_minor": int64_json(row.amount_minor),
      "amount_bz_minor": int64_json(row.amount_bz_minor),
      "proj_guid": optional_string_json(row.proj_guid),
      "proj_type": optional_string_json(row.proj_type),
      "contract_class": match row.contract_class {
        Some(value) => int_json(value)
        None => Json::null()
      },
      "bu_guid": Json::string(row.bu_guid),
    }),
  )
}

///|
pub fn workflow_definition_record(
  row : LegacyWorkflowDefinitionRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="wf_process_def",
    record_type="legacy/workflow_process_definition",
    record_id=row.process_guid,
    schema_version~,
    payload=Json::object({
      "process_guid": Json::string(row.process_guid),
      "process_key": Json::string(row.process_key),
      "process_name": Json::string(row.process_name),
      "biz_type": Json::string(row.biz_type),
      "active": Json::boolean(row.active),
      "mandatory": Json::boolean(row.mandatory),
      "bu_guid": optional_string_json(row.bu_guid),
    }),
  )
}

///|
pub fn workflow_step_record(
  row : LegacyWorkflowStepRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="wf_step_def",
    record_type="legacy/workflow_step_definition",
    record_id=row.step_guid,
    schema_version~,
    payload=Json::object({
      "step_guid": Json::string(row.step_guid),
      "process_guid": Json::string(row.process_guid),
      "step_key": Json::string(row.step_key),
      "step_order": int_json(row.step_order),
      "step_type": int_json(row.step_type),
      "step_name": Json::string(row.step_name),
      "threshold": int_json(row.threshold),
      "remind_days": match row.remind_days {
        Some(value) => int_json(value)
        None => Json::null()
      },
      "warn_days": match row.warn_days {
        Some(value) => int_json(value)
        None => Json::null()
      },
    }),
  )
}

///|
pub fn workflow_assignee_record(
  row : LegacyWorkflowAssigneeRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="wf_step_assignee",
    record_type="legacy/workflow_step_assignee",
    record_id=row.assignee_guid,
    schema_version~,
    payload=Json::object({
      "assignee_guid": Json::string(row.assignee_guid),
      "step_guid": Json::string(row.step_guid),
      "user_guid": optional_string_json(row.user_guid),
      "weight": int_json(row.weight),
    }),
  )
}

///|
pub fn lifecycle_stage_record(
  row : LegacyLifecycleStageRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="proj_lifecycle_stage",
    record_type="legacy/project_lifecycle_stage",
    record_id=row.stage_code,
    schema_version~,
    payload=Json::object({
      "stage_code": Json::string(row.stage_code),
      "stage_name": Json::string(row.stage_name),
      "stage_order": int_json(row.stage_order),
    }),
  )
}

///|
pub fn lifecycle_instance_record(
  row : LegacyLifecycleInstanceRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_progress(row.progress_bps)
  typed_source_record(
    table_name="proj_lifecycle_instance",
    record_type="legacy/project_lifecycle_instance",
    record_id=row.instance_id,
    schema_version~,
    payload=Json::object({
      "instance_id": Json::string(row.instance_id),
      "proj_guid": Json::string(row.proj_guid),
      "stage_code": Json::string(row.stage_code),
      "planned_start": optional_string_json(row.planned_start),
      "planned_end": optional_string_json(row.planned_end),
      "actual_start": optional_string_json(row.actual_start),
      "actual_end": optional_string_json(row.actual_end),
      "status": Json::string(row.status),
      "progress_bps": int64_json(row.progress_bps),
    }),
  )
}

///|
pub fn investment_version_record(
  row : LegacyInvestmentVersionRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="tzsy_version",
    record_type="legacy/investment_version",
    record_id=row.version_guid,
    schema_version~,
    payload=Json::object({
      "version_guid": Json::string(row.version_guid),
      "proj_guid": Json::string(row.proj_guid),
      "bu_guid": Json::string(row.bu_guid),
      "version_name": Json::string(row.version_name),
      "version_no": int_json(row.version_no),
      "current": Json::boolean(row.current),
      "created_by": Json::string(row.created_by),
      "created_at": Json::string(row.created_at),
      "remark": optional_string_json(row.remark),
    }),
  )
}

///|
pub fn investment_index_record(
  row : LegacyInvestmentIndexRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="tzsy_plan_index",
    record_type="legacy/investment_index",
    record_id=row.index_guid,
    schema_version~,
    payload=Json::object({
      "index_guid": Json::string(row.index_guid),
      "version_guid": Json::string(row.version_guid),
      "proj_guid": Json::string(row.proj_guid),
      "dimension": Json::string(row.dimension),
      "full_code": Json::string(row.full_code),
      "index_name": Json::string(row.index_name),
      "parent_code": optional_string_json(row.parent_code),
      "unit": optional_string_json(row.unit),
      "value_repr": optional_string_json(row.value_repr),
      "remark": optional_string_json(row.remark),
      "sort_order": int_json(row.sort_order),
    }),
  )
}

///|
pub fn loan_offset_record(
  row : LegacyLoanOffsetRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  validate_nonnegative(row.amount_minor)
  typed_source_record(
    table_name="cb_loan_offset",
    record_type="legacy/advance_offset",
    record_id=row.offset_guid,
    schema_version~,
    payload=Json::object({
      "offset_guid": Json::string(row.offset_guid),
      "loan_guid": Json::string(row.loan_guid),
      "amount_minor": int64_json(row.amount_minor),
      "offset_date": Json::string(row.offset_date),
      "related_expense_guid": optional_string_json(row.related_expense_guid),
      "remark": optional_string_json(row.remark),
      "operator_guid": Json::string(row.operator_guid),
    }),
  )
}

///|
pub fn parameter_record(
  row : LegacyParameterRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="my_biz_param_option",
    record_type="legacy/parameter",
    record_id=row.parameter_id,
    schema_version~,
    payload=Json::object({
      "parameter_id": Json::string(row.parameter_id),
      "parameter_name": Json::string(row.parameter_name),
      "parameter_code": Json::string(row.parameter_code),
      "parameter_value": Json::string(row.parameter_value),
      "display_order": int_json(row.display_order),
      "enabled": Json::boolean(row.enabled),
    }),
  )
}

///|
pub fn proceeding_record(
  row : LegacyProceedingRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="vys_proceeding",
    record_type="legacy/proceeding",
    record_id=row.proceeding_guid,
    schema_version~,
    payload=Json::object({
      "proceeding_guid": Json::string(row.proceeding_guid),
      "proceeding_code": Json::string(row.proceeding_code),
      "proceeding_name": Json::string(row.proceeding_name),
      "manager_guid": optional_string_json(row.manager_guid),
      "apply_dept_guid": optional_string_json(row.apply_dept_guid),
      "cost_code": optional_string_json(row.cost_code),
      "enabled": Json::boolean(row.enabled),
    }),
  )
}

///|
pub fn user_record(
  row : LegacyUserRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="sys_user",
    record_type="legacy/user",
    record_id=row.user_id,
    schema_version~,
    payload=Json::object({
      "user_id": Json::string(row.user_id),
      "user_code": Json::string(row.user_code),
      "user_name": Json::string(row.user_name),
      "emp_name": optional_string_json(row.emp_name),
      "super_user": Json::boolean(row.super_user),
      "bu_guid": optional_string_json(row.bu_guid),
      "dept_guid": optional_string_json(row.dept_guid),
      "enabled": Json::boolean(row.enabled),
      "fail_login_count": int_json(row.fail_login_count),
      "last_login_time": optional_string_json(row.last_login_time),
    }),
  )
}

///|
pub fn audit_record(
  row : LegacyAuditRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  typed_source_record(
    table_name="audit_log",
    record_type="legacy/audit_event",
    record_id=row.log_id,
    schema_version~,
    payload=Json::object({
      "log_id": Json::string(row.log_id),
      "user_id": optional_string_json(row.user_id),
      "action": Json::string(row.action),
      "target_type": optional_string_json(row.target_type),
      "target_id": optional_string_json(row.target_id),
      "ip": optional_string_json(row.ip),
      "created_at": Json::string(row.created_at),
    }),
  )
}
