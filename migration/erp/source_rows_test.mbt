///|
test "typed ERP source rows preserve workflow, payment, and investment identity" {
  let task = task_record(
    {
      task_guid: "task-001",
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      parent_task_guid: None,
      task_code: Some("T-001"),
      task_name: "Foundation",
      task_type: "key_node",
      plan_begin_date: "2026-01-01",
      plan_end_date: "2026-02-01",
      actual_begin_date: None,
      actual_end_date: None,
      progress_bps: 2500L,
      owner_guid: Some("user-001"),
      status: "in_progress",
      sort_order: 1,
    },
    schema_version=1,
  )
  let payment = payment_application_record(
    {
      apply_guid: "apply-001",
      apply_code: "AP-001",
      contract_guid: "contract-001",
      plan_guid: Some("plan-001"),
      apply_class: 0,
      apply_type_code: None,
      apply_state: "已审核",
      pay_state: "未支付",
      subject: Some("Progress payment"),
      apply_dept_guid: "bu-001",
      applied_by: "user-001",
      apply_date: "2026-02-01",
      amount_minor: 100000L,
      amount_bz_minor: 100000L,
      proj_guid: Some("proj-001"),
      proj_type: None,
      contract_class: Some(0),
      bu_guid: "bu-001",
    },
    schema_version=1,
  )
  let workflow = workflow_step_record(
    {
      step_guid: "step-001",
      process_guid: "process-001",
      step_key: "approve",
      step_order: 1,
      step_type: 1,
      step_name: "Approve",
      threshold: 1,
      remind_days: Some(2),
      warn_days: Some(5),
    },
    schema_version=1,
  )
  let index = investment_index_record(
    {
      index_guid: "index-001",
      version_guid: "version-001",
      proj_guid: "proj-001",
      dimension: "tax",
      full_code: "Tax.VAT.Output",
      index_name: "Output VAT",
      parent_code: Some("Tax.VAT"),
      unit: Some("%"),
      value_repr: Some("0.13"),
      remark: None,
      sort_order: 1,
    },
    schema_version=1,
  )
  let user = user_record(
    {
      user_id: "user-001",
      user_code: "U-001",
      user_name: "Operator",
      emp_name: Some("Operator"),
      super_user: false,
      bu_guid: Some("bu-001"),
      dept_guid: None,
      enabled: true,
      fail_login_count: 0,
      last_login_time: None,
    },
    schema_version=1,
  )
  let audit = audit_record(
    {
      log_id: "1",
      user_id: Some("user-001"),
      action: "LOGIN",
      target_type: None,
      target_id: None,
      ip: None,
      created_at: "2026-01-01T00:00:00Z",
    },
    schema_version=1,
  )
  assert_eq(task.record_type, "legacy/task")
  assert_eq(payment.record_type, "legacy/payment_application")
  assert_eq(workflow.source_id, "erp:wf_step_def:step-001")
  assert_true(index.payload.contains("Tax.VAT.Output"))
  assert_true(!user.payload.contains("password_hash"))
  assert_eq(audit.record_type, "legacy/audit_event")
}

///|
test "typed ERP source rows reject missing identity" {
  try
    lifecycle_stage_record(
      { stage_code: "", stage_name: "stage", stage_order: 1 },
      schema_version=1,
    )
  catch {
    ErpImportError::MissingIdentifier => ()
    _ => fail("wrong lifecycle identity error")
  } noraise {
    _ => fail("expected lifecycle identity error")
  }
}

///|
test "typed ERP source rows reject invalid progress and money" {
  try
    task_record(
      {
        task_guid: "task-bad",
        proj_guid: "proj-001",
        bu_guid: "bu-001",
        parent_task_guid: None,
        task_code: None,
        task_name: "Bad",
        task_type: "task",
        plan_begin_date: "2026-01-01",
        plan_end_date: "2026-02-01",
        actual_begin_date: None,
        actual_end_date: None,
        progress_bps: 10001L,
        owner_guid: None,
        status: "pending",
        sort_order: 1,
      },
      schema_version=1,
    )
  catch {
    ErpImportError::InvalidValue => ()
    _ => fail("wrong progress error")
  } noraise {
    _ => fail("expected progress error")
  }
  try
    loan_offset_record(
      {
        offset_guid: "offset-bad",
        loan_guid: "loan-001",
        amount_minor: -1L,
        offset_date: "2026-01-01",
        related_expense_guid: None,
        remark: None,
        operator_guid: "user-001",
      },
      schema_version=1,
    )
  catch {
    ErpImportError::InvalidValue => ()
    _ => fail("wrong amount error")
  } noraise {
    _ => fail("expected amount error")
  }
}
