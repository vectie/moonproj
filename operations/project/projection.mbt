///|
fn project_stage_name(stage : ProjectStage) -> String {
  match stage {
    ProjectStage::Initiation => "initiation"
    ProjectStage::Planning => "planning"
    ProjectStage::Design => "design"
    ProjectStage::Development => "development"
    ProjectStage::Sales => "sales"
    ProjectStage::Delivery => "delivery"
    ProjectStage::Settlement => "settlement"
    ProjectStage::Closed => "closed"
  }
}

///|
fn project_state_name(state : ProjectState) -> String {
  match state {
    ProjectState::Draft => "draft"
    ProjectState::Active => "active"
    ProjectState::Suspended => "suspended"
    ProjectState::Completed => "completed"
    ProjectState::Closed => "closed"
  }
}

///|
fn project_projection_payload(project : Project) -> String {
  Json::object({
    "project_id": Json::string(project.project_id),
    "principal_id": Json::string(project.principal_id),
    "code": Json::string(project.code),
    "name": Json::string(project.name),
    "stage": Json::string(project_stage_name(project.stage)),
    "state": Json::string(project_state_name(project.state)),
    "event_count": Json::number(
      project.events.length().to_double(),
      repr=project.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn Project::append_projection(
  self : Project,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ProjectError {
  if projection.aggregate_type != "project" ||
    projection.aggregate_id != self.project_id {
    raise ProjectError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=project_projection_payload(self),
    source_event_id="company:project:" +
      self.project_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ProjectError::Projection(error)
  }
}

///|
fn task_state_name(state : TaskState) -> String {
  match state {
    TaskState::Planned => "planned"
    TaskState::InProgress => "in_progress"
    TaskState::Completed => "completed"
    TaskState::Blocked => "blocked"
    TaskState::Cancelled => "cancelled"
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn task_json(task : ProjectTask) -> Json {
  let planned_cost : Json = match task.planned_cost {
    Some(value) =>
      Json::object({
        "amount_minor": Json::number(
          value.minor.to_double(),
          repr=value.minor.to_string(),
        ),
        "currency": Json::string(value.currency),
      })
    None => Json::null()
  }
  Json::object({
    "task_id": Json::string(task.task_id),
    "project_id": Json::string(task.project_id),
    "principal_id": Json::string(task.principal_id),
    "name": Json::string(task.name),
    "planned_cost": planned_cost,
    "dependencies": string_array_json(task.dependencies),
    "progress_bps": Json::number(
      task.progress_bps.to_double(),
      repr=task.progress_bps.to_string(),
    ),
    "state": Json::string(task_state_name(task.state)),
  })
}

///|
fn plan_projection_payload(plan : ProjectPlan) -> String {
  let tasks : Array[Json] = []
  for task in plan.tasks {
    tasks.push(task_json(task))
  }
  Json::object({
    "project_id": Json::string(plan.project_id),
    "principal_id": Json::string(plan.principal_id),
    "tasks": Json::array(tasks),
  }).stringify()
}

///|
pub fn ProjectPlan::append_projection(
  self : ProjectPlan,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise PlanError {
  if projection.aggregate_type != "project_plan" ||
    projection.aggregate_id != self.project_id {
    raise PlanError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=plan_projection_payload(self),
    source_event_id="company:project-plan:" +
      self.project_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise PlanError::Projection(error)
  }
}
