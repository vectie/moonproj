///|
fn project_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "project-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn projection_project_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-project-projection",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-projection",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "project lifecycle follows the ERP stage order" {
  let project = Project::new(
    project_id="p-001",
    principal_id="co-001",
    code="P-001",
    name="Example Project",
    actor_id="alice",
    grant=project_grant("project:create"),
  )
  let planning = project.advance(
    ProjectStage::Planning,
    actor_id="alice",
    grant=project_grant("project:advance"),
  )
  let design = planning.advance(
    ProjectStage::Design,
    actor_id="alice",
    grant=project_grant("project:advance"),
  )
  assert_true(design.state == ProjectState::Active)
  assert_eq(design.events.length(), 2)
}

///|
test "project rejects skipping a lifecycle stage" {
  let project = Project::new(
    project_id="p-001",
    principal_id="co-001",
    code="P-001",
    name="Example Project",
    actor_id="alice",
    grant=project_grant("project:create"),
  )
  try
    project.advance(
      ProjectStage::Development,
      actor_id="alice",
      grant=project_grant("project:advance"),
    )
  catch {
    ProjectError::InvalidStageTransition => ()
    _ => fail("wrong project error")
  } noraise {
    _ => fail("expected project error")
  }
}

///|
test "project and plan snapshots persist lifecycle and task evidence" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let project = Project::new(
    project_id="p-projection",
    principal_id="co-001",
    code="P-PROJECTION",
    name="Projection Project",
    actor_id="alice",
    grant=projection_project_grant("project:create"),
  ).advance(
    ProjectStage::Planning,
    actor_id="alice",
    grant=projection_project_grant("project:advance"),
  )
  let project_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="project",
    aggregate_id="p-projection",
  )
  let project_projection = project.append_projection(project_projection)
  let plan = ProjectPlan::new(project).add_task(
    task_id="task-001",
    name="Foundation",
    planned_cost=Some(@finance.Money::new(minor=10000, currency="CNY")),
    dependencies=[],
    actor_id="alice",
    grant=projection_project_grant("project:task:add"),
  )
  let plan_projection = @store.AggregateProjection::new(
    project_projection.into_store(),
    aggregate_type="project_plan",
    aggregate_id="p-projection",
  )
  let plan_projection = plan.append_projection(plan_projection)
  match plan_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("task-001"))
      assert_true(latest.payload.contains("Foundation"))
    }
    None => fail("expected project plan projection")
  }
}
