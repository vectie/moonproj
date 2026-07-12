///|
pub(all) enum TaskState {
  Planned
  InProgress
  Completed
  Blocked
  Cancelled
} derive(Debug, Eq)

///|
pub(all) struct ProjectTask {
  task_id : String
  project_id : String
  principal_id : String
  name : String
  planned_cost : @finance.Money?
  dependencies : Array[String]
  progress_bps : Int64
  state : TaskState
} derive(Debug, Eq)

///|
pub(all) struct ProjectPlan {
  project_id : String
  principal_id : String
  tasks : Array[ProjectTask]
} derive(Debug, Eq)

///|
pub(all) suberror PlanError {
  EmptyIdentifier
  DuplicateTask
  SelfDependency
  MissingDependency
  InvalidProgress
  InvalidState
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn ProjectPlan::new(project : Project) -> ProjectPlan {
  {
    project_id: project.project_id,
    principal_id: project.principal_id,
    tasks: [],
  }
}

///|
pub fn ProjectPlan::add_task(
  self : ProjectPlan,
  task_id~ : String,
  name~ : String,
  planned_cost~ : @finance.Money?,
  dependencies~ : Array[String],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProjectPlan raise PlanError {
  if task_id.trim() == "" || name.trim() == "" {
    raise PlanError::EmptyIdentifier
  }
  for task in self.tasks {
    if task.task_id == task_id {
      raise PlanError::DuplicateTask
    }
  }
  for dependency in dependencies {
    if dependency == task_id {
      raise PlanError::SelfDependency
    }
    let mut found = false
    for task in self.tasks {
      if task.task_id == dependency {
        found = true
      }
    }
    if !found {
      raise PlanError::MissingDependency
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:task:add",
    scope="project:\{self.project_id}",
    amount_minor=match planned_cost {
      Some(amount) => amount.minor
      None => 0
    },
  ) catch {
    error => raise PlanError::NotAuthorized(error)
  }
  let tasks = self.tasks.copy()
  tasks.push({
    task_id,
    project_id: self.project_id,
    principal_id: self.principal_id,
    name,
    planned_cost,
    dependencies: dependencies.copy(),
    progress_bps: 0L,
    state: TaskState::Planned,
  })
  { ..self, tasks, }
}

///|
fn find_task_index(tasks : Array[ProjectTask], task_id : String) -> Int? {
  for i in 0..<tasks.length() {
    if tasks[i].task_id == task_id {
      return Some(i)
    }
  }
  None
}

///|
pub fn ProjectPlan::start_task(
  self : ProjectPlan,
  task_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProjectPlan raise PlanError {
  let index = match find_task_index(self.tasks, task_id) {
    Some(value) => value
    None => raise PlanError::EmptyIdentifier
  }
  let task = self.tasks[index]
  if task.state != TaskState::Planned && task.state != TaskState::Blocked {
    raise PlanError::InvalidState
  }
  for dependency in task.dependencies {
    let dependency_index = match find_task_index(self.tasks, dependency) {
      Some(value) => value
      None => raise PlanError::MissingDependency
    }
    if self.tasks[dependency_index].state != TaskState::Completed {
      raise PlanError::MissingDependency
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:task:start",
    scope="project:\{self.project_id}",
    amount_minor=match task.planned_cost {
      Some(amount) => amount.minor
      None => 0
    },
  ) catch {
    error => raise PlanError::NotAuthorized(error)
  }
  let tasks = self.tasks.copy()
  tasks[index] = { ..task, state: TaskState::InProgress }
  { ..self, tasks, }
}

///|
pub fn ProjectPlan::report_progress(
  self : ProjectPlan,
  task_id~ : String,
  progress_bps~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProjectPlan raise PlanError {
  if progress_bps < 0L || progress_bps > 10000L {
    raise PlanError::InvalidProgress
  }
  let index = match find_task_index(self.tasks, task_id) {
    Some(value) => value
    None => raise PlanError::EmptyIdentifier
  }
  let task = self.tasks[index]
  if task.state != TaskState::InProgress {
    raise PlanError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:task:progress",
    scope="project:\{self.project_id}",
    amount_minor=match task.planned_cost {
      Some(amount) => amount.minor
      None => 0
    },
  ) catch {
    error => raise PlanError::NotAuthorized(error)
  }
  let state = if progress_bps == 10000L {
    TaskState::Completed
  } else {
    TaskState::InProgress
  }
  let tasks = self.tasks.copy()
  tasks[index] = { ..task, progress_bps, state }
  { ..self, tasks, }
}

///|
pub fn ProjectPlan::block_task(
  self : ProjectPlan,
  task_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ProjectPlan raise PlanError {
  let index = match find_task_index(self.tasks, task_id) {
    Some(value) => value
    None => raise PlanError::EmptyIdentifier
  }
  let task = self.tasks[index]
  if task.state != TaskState::InProgress {
    raise PlanError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:task:block",
    scope="project:\{self.project_id}",
    amount_minor=0,
  ) catch {
    error => raise PlanError::NotAuthorized(error)
  }
  let tasks = self.tasks.copy()
  tasks[index] = { ..task, state: TaskState::Blocked }
  { ..self, tasks, }
}
