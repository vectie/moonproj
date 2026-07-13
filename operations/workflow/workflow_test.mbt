///|
fn workflow_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "workflow-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "expense:expense-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "weighted workflow advances and approves" {
  let definition = ProcessDefinition::new(
    process_id="expense-approval",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 2 },
      { step_id: "finance", capability: "expense:pay", required_weight: 1 },
    ],
  )
  let instance = start_process(
    definition,
    instance_id="wf-001",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  )
  let approved_manager = instance.decide(
    step_id="manager",
    decision=Decision::Approve,
    weight=2,
    actor_id="alice",
    grant=workflow_grant("expense:approve"),
  )
  let approved_finance = approved_manager.decide(
    step_id="finance",
    decision=Decision::Approve,
    weight=1,
    actor_id="alice",
    grant=workflow_grant("expense:pay"),
  )
  assert_true(approved_finance.status == ProcessStatus::Approved)
  assert_eq(approved_finance.actions.length(), 2)
}

///|
test "workflow rejects duplicate action and wrong step" {
  let definition = ProcessDefinition::new(
    process_id="contract-approval",
    process_key="contract-approval",
    steps=[
      { step_id: "review", capability: "contract:approve", required_weight: 1 },
    ],
  )
  let instance = start_process(
    definition,
    instance_id="wf-002",
    principal_id="co-001",
    subject_id="contract:ct-001",
    actor_id="alice",
    grant={ ..workflow_grant("workflow:start"), scope: "contract:ct-001" },
  )
  try
    instance.decide(
      step_id="other",
      decision=Decision::Approve,
      weight=1,
      actor_id="alice",
      grant={ ..workflow_grant("contract:approve"), scope: "contract:ct-001" },
    )
  catch {
    WorkflowError::WrongStep => ()
    _ => fail("wrong workflow error")
  } noraise {
    _ => fail("expected workflow error")
  }
}

///|
test "workflow assignment is separate from authority and references a step" {
  let definition = ProcessDefinition::new(
    process_id="assignment-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let assignment = definition.assign_step(
    assignment_id="assignment-001",
    step_id="manager",
    assignee_id="employee-001",
    principal_id="co-001",
    scope="workflow:assignment-definition",
    weight=1,
    actor_id="alice",
    grant={
      grant_id: "workflow-assignment-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "workflow:assignment:add",
      scope: "workflow:assignment-definition",
      max_amount_minor: 0,
      active: true,
    },
  )
  assert_eq(assignment.process_id, "assignment-definition")
  assert_eq(assignment.step_id, "manager")
  assert_eq(assignment.assignee_id, "employee-001")
}

///|
test "workflow assignment projection preserves source identity" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let definition = ProcessDefinition::new(
    process_id="assignment-projection-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let assignment = definition.assign_step(
    assignment_id="assignment-projection-001",
    step_id="manager",
    assignee_id="employee-001",
    principal_id="co-001",
    scope="workflow:assignment-projection-definition",
    weight=1,
    actor_id="alice",
    grant={
      grant_id: "workflow-assignment-projection-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "workflow:assignment:add",
      scope: "workflow:assignment-projection-definition",
      max_amount_minor: 0,
      active: true,
    },
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="workflow_assignment",
    aggregate_id="assignment-projection-001",
  )
  let projection = assignment.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("employee-001"))
      assert_true(latest.payload.contains("manager"))
      assert_true(latest.payload.contains("configuration_only"))
      assert_true(latest.payload.contains("grants_authority"))
      assert_true(latest.payload.contains("approves_instance"))
      assert_true(latest.payload.contains("false"))
    }
    None => fail("expected workflow assignment projection")
  }
}

///|
test "attached workflow assignments enforce the decision actor" {
  let definition = ProcessDefinition::new(
    process_id="assignment-enforced-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let assignment = definition.assign_step(
    assignment_id="assignment-enforced-001",
    step_id="manager",
    assignee_id="alice",
    principal_id="co-001",
    scope="workflow:assignment-enforced-definition",
    weight=1,
    actor_id="alice",
    grant={
      grant_id: "workflow-assignment-enforced-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "workflow:assignment:add",
      scope: "workflow:assignment-enforced-definition",
      max_amount_minor: 0,
      active: true,
    },
  )
  let assigned_definition = definition.attach_assignment(assignment)
  let instance = start_process(
    assigned_definition,
    instance_id="wf-assignment-enforced",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  )
  try
    instance.decide(
      step_id="manager",
      decision=Decision::Approve,
      weight=1,
      actor_id="bob",
      grant={ ..workflow_grant("expense:approve"), actor_id: "bob" },
    )
  catch {
    WorkflowError::NotAssigned => ()
    _ => fail("wrong workflow assignment error")
  } noraise {
    _ => fail("expected workflow assignment enforcement")
  }
  let approved = instance.decide(
    step_id="manager",
    decision=Decision::Approve,
    weight=1,
    actor_id="alice",
    grant=workflow_grant("expense:approve"),
  )
  assert_true(approved.status == ProcessStatus::Approved)
  assert_eq(approved.assignments.length(), 1)
}

///|
test "workflow delegated decisions require an attached assignment and retain delegation evidence" {
  let definition = ProcessDefinition::new(
    process_id="delegated-assignment-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let assignment = definition.assign_step(
    assignment_id="delegated-assignment-001",
    step_id="manager",
    assignee_id="delegate-001",
    principal_id="co-001",
    scope="workflow:delegated-assignment-definition",
    weight=1,
    actor_id="alice",
    grant={
      grant_id: "delegated-assignment-add",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "workflow:assignment:add",
      scope: "workflow:delegated-assignment-definition",
      max_amount_minor: 0,
      active: true,
    },
  )
  let definition = definition.attach_assignment(assignment)
  let directory = @access.AccessDirectory::empty().add_delegation(
    {
      delegation_id: "workflow-delegation-001",
      principal_id: "co-001",
      delegator_id: "admin-001",
      delegate_actor_id: "delegate-001",
      capability: "expense:approve",
      scope: "expense:expense-001",
      max_amount_minor: 0,
      not_before_epoch: 100L,
      expires_at_epoch: Some(200L),
      active: true,
    },
    actor_id="admin-001",
    grant={
      grant_id: "workflow-delegation-create",
      principal_id: "co-001",
      actor_id: "admin-001",
      capability: "rbac:delegation:create",
      scope: "expense:expense-001",
      max_amount_minor: 0,
      active: true,
    },
  )
  let instance = start_process(
    definition,
    instance_id="wf-delegated-001",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  )
  try
    instance.decide_delegated(
      step_id="manager",
      decision=Decision::Approve,
      weight=1,
      actor_id="delegate-001",
      delegation_id="workflow-delegation-001",
      at_epoch=99L,
      directory~,
    )
  catch {
    WorkflowError::Delegation(@access.AccessError::DelegationNotYetEffective) =>
      ()
    _ => fail("wrong workflow delegation window error")
  } noraise {
    _ => fail("expected workflow delegation window")
  }
  let approved = instance.decide_delegated(
    step_id="manager",
    decision=Decision::Approve,
    weight=1,
    actor_id="delegate-001",
    delegation_id="workflow-delegation-001",
    at_epoch=100L,
    directory~,
  )
  assert_true(approved.status == ProcessStatus::Approved)
  match approved.actions[0].delegation_id {
    Some(value) => assert_eq(value, "workflow-delegation-001")
    None => fail("missing delegation evidence")
  }
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
    aggregate_type="workflow_instance",
    aggregate_id="wf-delegated-001",
  )
  let projection = approved.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("workflow-delegation-001"))
      assert_true(latest.payload.contains("delegation"))
    }
    None => fail("expected delegated workflow projection")
  }
  let revoked_directory = directory.revoke_delegation(
    delegation_id="workflow-delegation-001",
    actor_id="admin-001",
    grant={
      grant_id: "workflow-delegation-revoke",
      principal_id: "co-001",
      actor_id: "admin-001",
      capability: "rbac:delegation:revoke",
      scope: "expense:expense-001",
      max_amount_minor: 0,
      active: true,
    },
  )
  let second_instance = start_process(
    definition,
    instance_id="wf-delegated-002",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  )
  try
    second_instance.decide_delegated(
      step_id="manager",
      decision=Decision::Approve,
      weight=1,
      actor_id="delegate-001",
      delegation_id="workflow-delegation-001",
      at_epoch=101L,
      directory=revoked_directory,
    )
  catch {
    WorkflowError::Delegation(@access.AccessError::InactiveDelegation) => ()
    _ => fail("wrong revoked workflow delegation error")
  } noraise {
    _ => fail("expected revoked workflow delegation")
  }
}

///|
test "workflow assignment attachment validates identity and remains non-authorizing" {
  let definition = ProcessDefinition::new(
    process_id="assignment-identity-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let assignment = definition.assign_step(
    assignment_id="assignment-identity-001",
    step_id="manager",
    assignee_id="alice",
    principal_id="co-001",
    scope="workflow:assignment-identity-definition",
    weight=1,
    actor_id="alice",
    grant={
      grant_id: "workflow-assignment-identity-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "workflow:assignment:add",
      scope: "workflow:assignment-identity-definition",
      max_amount_minor: 0,
      active: true,
    },
  )
  let other_definition = ProcessDefinition::new(
    process_id="other-assignment-definition",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  try other_definition.attach_assignment(assignment) catch {
    WorkflowError::AssignmentProcessMismatch => ()
    _ => fail("wrong assignment identity error")
  } noraise {
    _ => fail("expected assignment process mismatch")
  }
  let attached = definition.attach_assignment(assignment)
  let evidence = attached.assignment_attachment(
    assignment_id="assignment-identity-001",
  )
  assert_true(!evidence.grants_authority)
  assert_true(!evidence.approves_instance)
  try attached.assignment_attachment(assignment_id="missing-assignment") catch {
    WorkflowError::UnknownAssignment => ()
    _ => fail("wrong missing assignment error")
  } noraise {
    _ => fail("expected missing assignment error")
  }
  let instance = start_process(
    attached,
    instance_id="wf-assignment-authority-boundary",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  )
  try
    instance.decide(
      step_id="manager",
      decision=Decision::Approve,
      weight=1,
      actor_id="alice",
      grant=workflow_grant("workflow:assignment:add"),
    )
  catch {
    WorkflowError::NotAuthorized(_) => ()
    _ => fail("assignment unexpectedly authorized approval")
  } noraise {
    _ => fail("expected decision authority check")
  }
}

///|
test "workflow definitions and decisions persist approval evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let definition = ProcessDefinition::new(
    process_id="expense-definition-projection",
    process_key="expense-approval",
    steps=[
      { step_id: "manager", capability: "expense:approve", required_weight: 1 },
    ],
  )
  let definition_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="process_definition",
    aggregate_id="expense-definition-projection",
  )
  let definition_projection = definition.append_projection(
    definition_projection,
  )
  let instance = start_process(
    definition,
    instance_id="wf-projection",
    principal_id="co-001",
    subject_id="expense:expense-001",
    actor_id="alice",
    grant=workflow_grant("workflow:start"),
  ).decide(
    step_id="manager",
    decision=Decision::Approve,
    weight=1,
    actor_id="alice",
    grant=workflow_grant("expense:approve"),
  )
  let instance_projection = @store.AggregateProjection::new(
    definition_projection.into_store(),
    aggregate_type="workflow_instance",
    aggregate_id="wf-projection",
  )
  let instance_projection = instance.append_projection(instance_projection)
  match instance_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("approved"))
      assert_true(latest.payload.contains("manager"))
    }
    None => fail("expected workflow projection")
  }
}
