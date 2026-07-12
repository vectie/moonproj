///|
fn plan_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-project-plan",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
fn plan_project() -> Project raise ProjectError {
  Project::new(
    project_id="p-001",
    principal_id="co-001",
    code="P-001",
    name="Project One",
    actor_id="alice",
    grant=plan_grant("project:create"),
  )
}

///|
test "project plan enforces task dependencies" {
  let plan = ProjectPlan::new(plan_project())
    .add_task(
      task_id="task-001",
      name="Foundation",
      planned_cost=Some(@finance.Money::new(minor=100000, currency="CNY")),
      dependencies=[],
      actor_id="alice",
      grant=plan_grant("project:task:add"),
    )
    .add_task(
      task_id="task-002",
      name="Structure",
      planned_cost=None,
      dependencies=["task-001"],
      actor_id="alice",
      grant=plan_grant("project:task:add"),
    )
  try
    plan.start_task(
      task_id="task-002",
      actor_id="alice",
      grant=plan_grant("project:task:start"),
    )
  catch {
    PlanError::MissingDependency => ()
    _ => fail("wrong plan error")
  } noraise {
    _ => fail("expected plan error")
  }
  let plan = plan
    .start_task(
      task_id="task-001",
      actor_id="alice",
      grant=plan_grant("project:task:start"),
    )
    .report_progress(
      task_id="task-001",
      progress_bps=10000L,
      actor_id="alice",
      grant=plan_grant("project:task:progress"),
    )
    .start_task(
      task_id="task-002",
      actor_id="alice",
      grant=plan_grant("project:task:start"),
    )
  assert_true(plan.tasks[1].state == TaskState::InProgress)
}

///|
test "project plan rejects progress outside the bounded range" {
  let plan = ProjectPlan::new(plan_project())
    .add_task(
      task_id="task-003",
      name="Planning",
      planned_cost=None,
      dependencies=[],
      actor_id="alice",
      grant=plan_grant("project:task:add"),
    )
    .start_task(
      task_id="task-003",
      actor_id="alice",
      grant=plan_grant("project:task:start"),
    )
  try
    plan.report_progress(
      task_id="task-003",
      progress_bps=10001L,
      actor_id="alice",
      grant=plan_grant("project:task:progress"),
    )
  catch {
    PlanError::InvalidProgress => ()
    _ => fail("wrong plan error")
  } noraise {
    _ => fail("expected plan error")
  }
}
