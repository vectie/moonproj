///|
fn domain_import_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "domain-import-grant",
    principal_id: "bu-001",
    actor_id: "migration",
    capability,
    scope: "project:proj-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn domain_import_amount_grant(
  capability : String,
) -> @foundation.AuthorityGrant {
  { ..domain_import_grant(capability), max_amount_minor: 100000 }
}

///|
test "task rows become a target project plan without replaying source effects" {
  let project = import_project(
    {
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      proj_code: "P-001",
      proj_name: "Project",
    },
    actor_id="migration",
    grant=domain_import_grant("project:create"),
  )
  let plan = import_project_tasks(
    project,
    [
      {
        task_guid: "task-001",
        proj_guid: "proj-001",
        bu_guid: "bu-001",
        parent_task_guid: None,
        task_code: None,
        task_name: "Foundation",
        task_type: "task",
        plan_begin_date: "2026-01-01",
        plan_end_date: "2026-02-01",
        actual_begin_date: None,
        actual_end_date: None,
        progress_bps: 0L,
        owner_guid: None,
        status: "pending",
        sort_order: 1,
      },
      {
        task_guid: "task-002",
        proj_guid: "proj-001",
        bu_guid: "bu-001",
        parent_task_guid: Some("task-001"),
        task_code: None,
        task_name: "Structure",
        task_type: "task",
        plan_begin_date: "2026-02-01",
        plan_end_date: "2026-03-01",
        actual_begin_date: None,
        actual_end_date: None,
        progress_bps: 0L,
        owner_guid: None,
        status: "pending",
        sort_order: 2,
      },
    ],
    actor_id="migration",
    grant=domain_import_grant("project:task:add"),
  )
  assert_eq(plan.tasks.length(), 2)
  assert_eq(plan.tasks[1].dependencies.length(), 1)
  assert_eq(plan.tasks[1].dependencies[0], "task-001")
  assert_true(plan.tasks[1].state is @project.TaskState::Planned)
}

///|
test "business unit import requires explicit principal and scoped grants" {
  let registry = import_business_units(
    [
      {
        bu_guid: "bu-root",
        parent_guid: None,
        bu_code: "ROOT",
        bu_name: "Root",
        bu_type: "group",
      },
      {
        bu_guid: "bu-child",
        parent_guid: Some("bu-root"),
        bu_code: "CHILD",
        bu_name: "Child",
        bu_type: "company",
      },
    ],
    [
      {
        bu_guid: "bu-root",
        principal_id: "co-001",
        authority_scope: "organization:bu-root",
      },
      {
        bu_guid: "bu-child",
        principal_id: "co-001",
        authority_scope: "organization:bu-child",
      },
    ],
    [
      {
        grant_id: "bu-root-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "organization:create",
        scope: "organization:bu-root",
        max_amount_minor: 0,
        active: true,
      },
      {
        grant_id: "bu-child-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "organization:create",
        scope: "organization:bu-child",
        max_amount_minor: 0,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(registry.units.length(), 2)
  assert_true(registry.units[1].parent_id is Some("bu-root"))
  try
    import_business_units(
      [
        {
          bu_guid: "bu-orphan",
          parent_guid: None,
          bu_code: "ORPHAN",
          bu_name: "Orphan",
          bu_type: "company",
        },
      ],
      [],
      [],
      actor_id="migration",
    )
  catch {
    ErpImportError::MissingMapping => ()
    _ => fail("wrong business-unit mapping error")
  } noraise {
    _ => fail("expected missing business-unit mapping")
  }
}

///|
test "project import maps BU relationships to explicit legal principals" {
  let projects = import_projects(
    [
      {
        proj_guid: "proj-001",
        bu_guid: "bu-child",
        proj_code: "P-001",
        proj_name: "Project",
      },
    ],
    [
      {
        project_id: "proj-001",
        principal_id: "co-001",
        authority_scope: "project:proj-001",
      },
    ],
    [
      {
        grant_id: "project-import-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "project:create",
        scope: "project:proj-001",
        max_amount_minor: 0,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(projects.length(), 1)
  assert_eq(projects[0].principal_id, "co-001")
  assert_true(projects[0].state is @project.ProjectState::Draft)
}

///|
test "user import preserves safe identity without granting legacy super-user" {
  let directory = import_users(
    [
      {
        user_id: "user-001",
        user_code: "alice",
        user_name: "Alice",
        emp_name: Some("Alice Employee"),
        super_user: true,
        bu_guid: Some("bu-001"),
        dept_guid: Some("dept-001"),
        enabled: true,
        fail_login_count: 0,
        last_login_time: None,
      },
    ],
    [
      {
        user_id: "user-001",
        principal_id: "co-001",
        authority_scope: "organization:bu-001",
      },
    ],
    [
      {
        grant_id: "user-import-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "identity:user:create",
        scope: "organization:bu-001",
        max_amount_minor: 0,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(directory.users.length(), 1)
  assert_eq(directory.users[0].display_name, "Alice Employee")
  assert_true(directory.users[0].state == @foundation.UserAccountState::Active)
}

///|
test "audit import requires explicit target interpretation and actor grant" {
  let trail = import_audit_records(
    [
      {
        log_id: "1",
        user_id: Some("user-001"),
        action: "login",
        target_type: None,
        target_id: None,
        ip: None,
        created_at: "2026-01-01",
      },
    ],
    [
      {
        audit_id: "1",
        principal_id: "co-001",
        scope: "organization:bu-001",
        target_type: "authentication",
        target_id: "user-001",
        outcome: "observed",
      },
    ],
    [
      {
        grant_id: "audit-import-grant",
        principal_id: "co-001",
        actor_id: "user-001",
        capability: "audit:append",
        scope: "organization:bu-001",
        max_amount_minor: 0,
        active: true,
      },
    ],
  )
  assert_eq(trail.records.length(), 1)
  assert_eq(trail.records[0].target_type, "authentication")
  assert_eq(trail.records[0].actor_id, "user-001")
  try
    import_audit_records(
      [
        {
          log_id: "2",
          user_id: Some("user-001"),
          action: "logout",
          target_type: None,
          target_id: None,
          ip: None,
          created_at: "2026-01-01",
        },
      ],
      [],
      [],
    )
  catch {
    ErpImportError::MissingMapping => ()
    _ => fail("wrong audit mapping error")
  } noraise {
    _ => fail("expected missing audit mapping")
  }
}

///|
test "parameter dictionary import preserves opaque options" {
  let dictionaries = import_parameter_dictionaries(
    [
      [
        {
          parameter_id: "1",
          parameter_name: "cost_subject",
          parameter_code: "CS-001",
          parameter_value: "Office",
          display_order: 1,
          enabled: true,
        },
        {
          parameter_id: "2",
          parameter_name: "cost_subject",
          parameter_code: "CS-002",
          parameter_value: "Travel",
          display_order: 2,
          enabled: false,
        },
      ],
    ],
    [
      {
        parameter_name: "cost_subject",
        principal_id: "co-001",
        scope: "parameter:cost_subject",
      },
    ],
    [
      {
        grant_id: "parameter-create",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "parameter:create",
        scope: "parameter:cost_subject",
        max_amount_minor: 0,
        active: true,
      },
      {
        grant_id: "parameter-edit",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "parameter:edit",
        scope: "parameter:cost_subject",
        max_amount_minor: 0,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(dictionaries.length(), 1)
  assert_eq(dictionaries[0].options.length(), 2)
  assert_true(!dictionaries[0].options[1].enabled)
}

///|
test "contract promotion requires a reviewed counterparty identity map" {
  let commitments = import_contracts(
    [
      {
        contract_guid: "contract-001",
        bu_guid: "bu-child",
        proj_guid: "proj-001",
        provider_guid: "legacy-provider-name-map",
        ht_amount_minor: 50000L,
        currency: "CNY",
      },
    ],
    [
      {
        contract_id: "contract-001",
        principal_id: "co-001",
        project_scope: "project:proj-001",
        counterparty_id: "supplier-001",
      },
    ],
    [
      {
        grant_id: "contract-import-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "commitment:create",
        scope: "project:proj-001",
        max_amount_minor: 100000,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(commitments.length(), 1)
  assert_eq(commitments[0].counterparty_id, "supplier-001")
  try
    import_contracts(
      [
        {
          contract_guid: "contract-002",
          bu_guid: "bu-child",
          proj_guid: "proj-001",
          provider_guid: "unmapped-provider",
          ht_amount_minor: 50000L,
          currency: "CNY",
        },
      ],
      [],
      [],
      actor_id="migration",
    )
  catch {
    ErpImportError::MissingMapping => ()
    _ => fail("wrong contract mapping error")
  } noraise {
    _ => fail("expected missing contract mapping")
  }
}

///|
test "employee advance promotion separates BU and employee ownership" {
  let advances = import_advances(
    [
      {
        loan_guid: "loan-001",
        bu_guid: "bu-child",
        employee_guid: "legacy-employee",
        amount_minor: 20000L,
        currency: "CNY",
      },
    ],
    [
      {
        advance_id: "loan-001",
        principal_id: "co-001",
        employee_id: "employee-001",
        authority_scope: "employee:employee-001",
      },
    ],
    [
      {
        grant_id: "advance-import-grant",
        principal_id: "co-001",
        actor_id: "migration",
        capability: "advance:create",
        scope: "employee:employee-001",
        max_amount_minor: 50000,
        active: true,
      },
    ],
    actor_id="migration",
  )
  assert_eq(advances.length(), 1)
  assert_eq(advances[0].employee_id, "employee-001")
  assert_eq(advances[0].outstanding_minor(), 20000L)
}

///|
test "dynamic-cost promotion retains source identity and project scope" {
  let costs = import_costs([
    {
      cost_id: "cost-001",
      project_scope: "project:proj-001",
      cost: {
        currency: "CNY",
        direct_minor: 100000L,
        indirect_minor: 20000L,
        contingency_minor: 5000L,
        other_minor: 3000L,
      },
    },
  ])
  assert_eq(costs.length(), 1)
  assert_eq(costs[0].cost_id, "cost-001")
  assert_eq(costs[0].value.total_minor, 128000L)
  try
    import_costs([
      {
        cost_id: "cost-001",
        project_scope: "project:proj-001",
        cost: {
          currency: "CNY",
          direct_minor: 0L,
          indirect_minor: 0L,
          contingency_minor: 0L,
          other_minor: 0L,
        },
      },
      {
        cost_id: "cost-001",
        project_scope: "project:proj-001",
        cost: {
          currency: "CNY",
          direct_minor: 0L,
          indirect_minor: 0L,
          contingency_minor: 0L,
          other_minor: 0L,
        },
      },
    ])
  catch {
    ErpImportError::InvalidValue => ()
    _ => fail("wrong cost promotion error")
  } noraise {
    _ => fail("expected duplicate cost error")
  }
}

///|
test "lifecycle rows replay only the ordered current stage" {
  let project = import_project(
    {
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      proj_code: "P-001",
      proj_name: "Project",
    },
    actor_id="migration",
    grant=domain_import_grant("project:create"),
  )
  let imported = import_project_lifecycle(
    project,
    [
      {
        instance_id: "1",
        proj_guid: "proj-001",
        stage_code: "initiation",
        planned_start: None,
        planned_end: None,
        actual_start: None,
        actual_end: None,
        status: "done",
        progress_bps: 10000L,
      },
      {
        instance_id: "2",
        proj_guid: "proj-001",
        stage_code: "acquisition",
        planned_start: None,
        planned_end: None,
        actual_start: None,
        actual_end: None,
        status: "done",
        progress_bps: 10000L,
      },
      {
        instance_id: "3",
        proj_guid: "proj-001",
        stage_code: "planning",
        planned_start: None,
        planned_end: None,
        actual_start: None,
        actual_end: None,
        status: "in_progress",
        progress_bps: 7000L,
      },
      {
        instance_id: "4",
        proj_guid: "proj-001",
        stage_code: "development",
        planned_start: None,
        planned_end: None,
        actual_start: None,
        actual_end: None,
        status: "pending",
        progress_bps: 0L,
      },
    ],
    [
      {
        source_code: "initiation",
        target_stage: @project.ProjectStage::Initiation,
      },
      {
        source_code: "acquisition",
        target_stage: @project.ProjectStage::Planning,
      },
      { source_code: "planning", target_stage: @project.ProjectStage::Design },
      {
        source_code: "development",
        target_stage: @project.ProjectStage::Development,
      },
    ],
    actor_id="migration",
    grant=domain_import_grant("project:advance"),
  )
  assert_true(imported.stage == @project.ProjectStage::Design)
  assert_eq(imported.events.length(), 2)
}

///|
test "task state replay is explicit and dependency ordered" {
  let project = import_project(
    {
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      proj_code: "P-001",
      proj_name: "Project",
    },
    actor_id="migration",
    grant=domain_import_grant("project:create"),
  )
  let rows : Array[LegacyTaskRow] = [
    {
      task_guid: "task-001",
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      parent_task_guid: None,
      task_code: None,
      task_name: "Foundation",
      task_type: "task",
      plan_begin_date: "2026-01-01",
      plan_end_date: "2026-02-01",
      actual_begin_date: Some("2026-01-02"),
      actual_end_date: Some("2026-01-31"),
      progress_bps: 10000L,
      owner_guid: None,
      status: "done",
      sort_order: 1,
    },
    {
      task_guid: "task-002",
      proj_guid: "proj-001",
      bu_guid: "bu-001",
      parent_task_guid: Some("task-001"),
      task_code: None,
      task_name: "Structure",
      task_type: "task",
      plan_begin_date: "2026-02-01",
      plan_end_date: "2026-03-01",
      actual_begin_date: Some("2026-02-02"),
      actual_end_date: None,
      progress_bps: 4500L,
      owner_guid: None,
      status: "in_progress",
      sort_order: 2,
    },
  ]
  let plan = import_project_tasks(
    project,
    rows,
    actor_id="migration",
    grant=domain_import_grant("project:task:add"),
  )
  let plan = import_project_task_states(
    plan,
    rows,
    actor_id="migration",
    start_grant=domain_import_grant("project:task:start"),
    progress_grant=domain_import_grant("project:task:progress"),
    block_grant=domain_import_grant("project:task:block"),
  )
  assert_true(plan.tasks[0].state is @project.TaskState::Completed)
  assert_eq(plan.tasks[1].progress_bps, 4500L)
  assert_true(plan.tasks[1].state is @project.TaskState::InProgress)
}

///|
test "payment application becomes a requested settlement without cash release" {
  let commitment = import_contract(
    {
      contract_guid: "contract-001",
      bu_guid: "bu-001",
      proj_guid: "proj-001",
      provider_guid: "supplier-001",
      ht_amount_minor: 50000L,
      currency: "CNY",
    },
    actor_id="migration",
    grant=domain_import_amount_grant("commitment:create"),
  )
  let submitted = commitment.transition(
    @commitment.CommitmentState::Submitted,
    actor_id="migration",
    grant=domain_import_amount_grant("commitment:submit"),
  )
  let approved = submitted.transition(
    @commitment.CommitmentState::Approved,
    actor_id="migration",
    grant=domain_import_amount_grant("commitment:approve"),
  )
  let performed = approved.transition(
    @commitment.CommitmentState::Performed,
    actor_id="migration",
    grant=domain_import_amount_grant("commitment:perform"),
  )
  let settlement = import_payment_application(
    {
      apply_guid: "apply-001",
      apply_code: "AP-001",
      contract_guid: "contract-001",
      plan_guid: None,
      apply_class: 0,
      apply_type_code: None,
      apply_state: "已审核",
      pay_state: "未支付",
      subject: Some("first payment"),
      apply_dept_guid: "bu-001",
      applied_by: "migration",
      apply_date: "2026-01-01",
      amount_minor: 20000L,
      amount_bz_minor: 20000L,
      proj_guid: Some("proj-001"),
      proj_type: None,
      contract_class: None,
      bu_guid: "bu-001",
    },
    performed,
    currency="CNY",
    actor_id="migration",
    grant=domain_import_amount_grant("settlement:request"),
  )
  assert_true(settlement.state is @settlement.SettlementState::Requested)
  assert_eq(settlement.amount.minor, 20000L)
}

///|
test "commitment state replay requires every explicit transition grant" {
  let commitment = import_contract(
    {
      contract_guid: "contract-state-001",
      bu_guid: "bu-001",
      proj_guid: "proj-001",
      provider_guid: "supplier-001",
      ht_amount_minor: 50000L,
      currency: "CNY",
    },
    actor_id="migration",
    grant=domain_import_amount_grant("commitment:create"),
  )
  let grants = [
    domain_import_amount_grant("commitment:submit"),
    domain_import_amount_grant("commitment:approve"),
    domain_import_amount_grant("commitment:perform"),
  ]
  let performed = import_commitment_state(
    commitment,
    @commitment.CommitmentState::Performed,
    grants,
    actor_id="migration",
  )
  assert_true(performed.state == @commitment.CommitmentState::Performed)
  assert_eq(performed.events.length(), 3)
  try
    import_commitment_state(
      commitment,
      @commitment.CommitmentState::Performed,
      [grants[0], grants[1]],
      actor_id="migration",
    )
  catch {
    ErpImportError::MissingMapping => ()
    _ => fail("expected missing transition grant")
  } noraise {
    _ => fail("expected missing transition grant")
  }
}

///|
test "workflow translation requires explicit capability mappings" {
  let definition = import_workflow_definition(
    {
      process_guid: "process-001",
      process_key: "expense",
      process_name: "Expense",
      biz_type: "expense",
      active: true,
      mandatory: true,
      bu_guid: Some("bu-001"),
    },
    [
      {
        step_guid: "step-001",
        process_guid: "process-001",
        step_key: "manager",
        step_order: 1,
        step_type: 1,
        step_name: "Manager",
        threshold: 1,
        remind_days: None,
        warn_days: None,
      },
    ],
    [{ step_guid: "step-001", capability: "expense:approve" }],
  )
  assert_eq(definition.steps[0].capability, "expense:approve")
  try
    import_workflow_definition(
      {
        process_guid: "process-002",
        process_key: "expense",
        process_name: "Expense",
        biz_type: "expense",
        active: true,
        mandatory: true,
        bu_guid: None,
      },
      [
        {
          step_guid: "step-002",
          process_guid: "process-002",
          step_key: "manager",
          step_order: 1,
          step_type: 1,
          step_name: "Manager",
          threshold: 1,
          remind_days: None,
          warn_days: None,
        },
      ],
      [],
    )
  catch {
    ErpImportError::MissingMapping => ()
    _ => fail("wrong workflow mapping error")
  } noraise {
    _ => fail("expected missing workflow mapping")
  }
}

///|
test "workflow definition cohort keeps process steps isolated" {
  let definitions = import_workflow_definitions(
    [
      {
        process_guid: "process-001",
        process_key: "expense",
        process_name: "Expense",
        biz_type: "expense",
        active: true,
        mandatory: true,
        bu_guid: None,
      },
      {
        process_guid: "process-002",
        process_key: "payment",
        process_name: "Payment",
        biz_type: "payment",
        active: true,
        mandatory: false,
        bu_guid: None,
      },
    ],
    [
      {
        step_guid: "step-001",
        process_guid: "process-001",
        step_key: "manager",
        step_order: 1,
        step_type: 1,
        step_name: "Manager",
        threshold: 1,
        remind_days: None,
        warn_days: None,
      },
      {
        step_guid: "step-002",
        process_guid: "process-002",
        step_key: "finance",
        step_order: 1,
        step_type: 1,
        step_name: "Finance",
        threshold: 1,
        remind_days: None,
        warn_days: None,
      },
    ],
    [
      { step_guid: "step-001", capability: "expense:approve" },
      { step_guid: "step-002", capability: "settlement:approve" },
    ],
  )
  assert_eq(definitions.length(), 2)
  assert_eq(definitions[1].steps[0].capability, "settlement:approve")
}

///|
test "investment version and indexes become a governed local model" {
  let model = import_investment_model(
    {
      version_guid: "version-001",
      proj_guid: "p-001",
      bu_guid: "bu-001",
      version_name: "Base case",
      version_no: 1,
      current: true,
      created_by: "alice",
      created_at: "2026-01-01",
      remark: None,
    },
    [
      {
        index_guid: "index-001",
        version_guid: "version-001",
        proj_guid: "p-001",
        dimension: "tax",
        full_code: "Tax.VAT.Output",
        index_name: "Output VAT",
        parent_code: Some("Tax.VAT"),
        unit: Some("%"),
        value_repr: Some("0.13"),
        remark: None,
        sort_order: 1,
      },
    ],
    principal_id="co-001",
    actor_id="alice",
    version_grant={
      ..domain_import_grant("investment:model:version:create"),
      principal_id: "co-001",
      actor_id: "alice",
      scope: "project:p-001",
    },
    index_grant={
      ..domain_import_grant("investment:model:index:add"),
      principal_id: "co-001",
      actor_id: "alice",
      scope: "project:p-001",
    },
  )
  assert_eq(model.indexes.length(), 1)
  assert_eq(model.version.version_id, "version-001")
}

///|
test "investment model cohort isolates versions and rejects stray indexes" {
  let models = import_investment_models(
    [
      {
        version_guid: "version-001",
        proj_guid: "p-001",
        bu_guid: "bu-001",
        version_name: "Base case",
        version_no: 1,
        current: true,
        created_by: "migration",
        created_at: "2026-01-01",
        remark: None,
      },
    ],
    [
      {
        index_guid: "index-001",
        version_guid: "version-001",
        proj_guid: "p-001",
        dimension: "tax",
        full_code: "Tax.VAT.Output",
        index_name: "Output VAT",
        parent_code: None,
        unit: Some("%"),
        value_repr: Some("0.13"),
        remark: None,
        sort_order: 1,
      },
    ],
    [
      {
        version_id: "version-001",
        principal_id: "co-001",
        version_grant: {
          ..domain_import_grant("investment:model:version:create"),
          principal_id: "co-001",
          actor_id: "migration",
          scope: "project:p-001",
        },
        index_grant: {
          ..domain_import_grant("investment:model:index:add"),
          principal_id: "co-001",
          actor_id: "migration",
          scope: "project:p-001",
        },
      },
    ],
    actor_id="migration",
  )
  assert_eq(models.length(), 1)
  assert_eq(models[0].indexes.length(), 1)
  try
    import_investment_models(
      [],
      [
        {
          index_guid: "stray-index",
          version_guid: "missing-version",
          proj_guid: "p-001",
          dimension: "tax",
          full_code: "Tax.Stray",
          index_name: "Stray",
          parent_code: None,
          unit: None,
          value_repr: None,
          remark: None,
          sort_order: 1,
        },
      ],
      [],
      actor_id="migration",
    )
  catch {
    ErpImportError::InvalidValue => ()
    _ => fail("wrong investment cohort error")
  } noraise {
    _ => fail("expected stray investment index error")
  }
}
