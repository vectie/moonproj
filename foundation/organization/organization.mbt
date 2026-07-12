///|
pub(all) enum OrganizationKind {
  Group
  Company
  Department
  BusinessUnit
} derive(Debug, Eq)

///|
pub(all) enum OrganizationState {
  Draft
  Active
  Suspended
  Closed
} derive(Debug, Eq)

///|
pub(all) struct OrganizationUnit {
  unit_id : String
  principal_id : String
  authority_scope : String
  parent_id : String?
  code : String
  name : String
  kind : OrganizationKind
  state : OrganizationState
} derive(Debug, Eq)

///|
pub(all) struct OrganizationRegistry {
  units : Array[OrganizationUnit]
} derive(Debug, Eq)

///|
pub(all) suberror OrganizationError {
  EmptyIdentifier
  SelfParent
  MissingParent
  DuplicateUnit
  InvalidState
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn OrganizationUnit::new(
  unit_id~ : String,
  principal_id~ : String,
  authority_scope~ : String,
  parent_id~ : String?,
  code~ : String,
  name~ : String,
  kind~ : OrganizationKind,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> OrganizationUnit raise OrganizationError {
  if unit_id.trim() == "" ||
    principal_id.trim() == "" ||
    authority_scope.trim() == "" ||
    code.trim() == "" ||
    name.trim() == "" {
    raise OrganizationError::EmptyIdentifier
  }
  match parent_id {
    Some(value) if value == unit_id => raise OrganizationError::SelfParent
    _ => ()
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="organization:create",
    scope=authority_scope,
    amount_minor=0,
  ) catch {
    error => raise OrganizationError::NotAuthorized(error)
  }
  {
    unit_id,
    principal_id,
    authority_scope,
    parent_id,
    code,
    name,
    kind,
    state: OrganizationState::Draft,
  }
}

///|
pub fn OrganizationRegistry::empty() -> OrganizationRegistry {
  { units: [] }
}

///|
pub fn OrganizationRegistry::append(
  self : OrganizationRegistry,
  unit : OrganizationUnit,
) -> OrganizationRegistry raise OrganizationError {
  for existing in self.units {
    if existing.unit_id == unit.unit_id {
      raise OrganizationError::DuplicateUnit
    }
  }
  match unit.parent_id {
    Some(parent_id) => {
      let mut found = false
      for existing in self.units {
        if existing.unit_id == parent_id {
          found = true
        }
      }
      if !found {
        raise OrganizationError::MissingParent
      }
    }
    None => ()
  }
  let units = self.units.copy()
  units.push(unit)
  { units, }
}

///|
pub fn OrganizationUnit::activate(
  self : OrganizationUnit,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> OrganizationUnit raise OrganizationError {
  if self.state != OrganizationState::Draft &&
    self.state != OrganizationState::Suspended {
    raise OrganizationError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="organization:activate",
    scope=self.authority_scope,
    amount_minor=0,
  ) catch {
    error => raise OrganizationError::NotAuthorized(error)
  }
  { ..self, state: OrganizationState::Active }
}

///|
pub fn OrganizationUnit::suspend(
  self : OrganizationUnit,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> OrganizationUnit raise OrganizationError {
  if self.state != OrganizationState::Active {
    raise OrganizationError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="organization:suspend",
    scope=self.authority_scope,
    amount_minor=0,
  ) catch {
    error => raise OrganizationError::NotAuthorized(error)
  }
  { ..self, state: OrganizationState::Suspended }
}
