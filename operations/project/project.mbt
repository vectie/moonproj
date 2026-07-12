///|
pub(all) enum ProjectStage {
  Initiation
  Planning
  Design
  Development
  Sales
  Delivery
  Settlement
  Closed
} derive(Debug, Eq)

///|
pub(all) enum ProjectState {
  Draft
  Active
  Suspended
  Completed
  Closed
} derive(Debug, Eq)

///|
pub(all) struct ProjectEvent {
  from_stage : ProjectStage
  to_stage : ProjectStage
  actor_id : String
} derive(Debug, Eq)

///|
pub(all) struct Project {
  project_id : String
  principal_id : String
  code : String
  name : String
  stage : ProjectStage
  state : ProjectState
  events : Array[ProjectEvent]
} derive(Debug, Eq)

///|
pub(all) suberror ProjectError {
  EmptyIdentifier
  EmptyName
  InvalidStageTransition
  InvalidStateTransition
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Project::new(
  project_id~ : String,
  principal_id~ : String,
  code~ : String,
  name~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Project raise ProjectError {
  if project_id.trim() == "" || principal_id.trim() == "" || code.trim() == "" {
    raise ProjectError::EmptyIdentifier
  }
  if name.trim() == "" {
    raise ProjectError::EmptyName
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="project:create",
    scope="project:\{project_id}",
    amount_minor=0,
  ) catch {
    error => raise ProjectError::NotAuthorized(error)
  }
  {
    project_id,
    principal_id,
    code,
    name,
    stage: ProjectStage::Initiation,
    state: ProjectState::Draft,
    events: [],
  }
}

///|
fn next_stage(current : ProjectStage, next : ProjectStage) -> Bool {
  (current == ProjectStage::Initiation && next == ProjectStage::Planning) ||
  (current == ProjectStage::Planning && next == ProjectStage::Design) ||
  (current == ProjectStage::Design && next == ProjectStage::Development) ||
  (current == ProjectStage::Development && next == ProjectStage::Sales) ||
  (current == ProjectStage::Sales && next == ProjectStage::Delivery) ||
  (current == ProjectStage::Delivery && next == ProjectStage::Settlement) ||
  (current == ProjectStage::Settlement && next == ProjectStage::Closed)
}

///|
pub fn Project::advance(
  self : Project,
  to : ProjectStage,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Project raise ProjectError {
  if !next_stage(self.stage, to) {
    raise ProjectError::InvalidStageTransition
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:advance",
    scope="project:\{self.project_id}",
    amount_minor=0,
  ) catch {
    error => raise ProjectError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from_stage: self.stage, to_stage: to, actor_id })
  let state = if to == ProjectStage::Closed {
    ProjectState::Closed
  } else if to == ProjectStage::Settlement {
    ProjectState::Completed
  } else {
    ProjectState::Active
  }
  { ..self, stage: to, state, events }
}

///|
pub fn Project::suspend(
  self : Project,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Project raise ProjectError {
  if self.state == ProjectState::Closed {
    raise ProjectError::InvalidStateTransition
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="project:suspend",
    scope="project:\{self.project_id}",
    amount_minor=0,
  ) catch {
    error => raise ProjectError::NotAuthorized(error)
  }
  { ..self, state: ProjectState::Suspended }
}
