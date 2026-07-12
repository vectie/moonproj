///|
/// A named capability at one exact company scope. Scope inheritance is
/// deliberately not implicit: a role must contain every scope it may use.
pub(all) struct Permission {
  capability : String
  scope : String
  max_amount_minor : Int64
} derive(Debug, Eq)

///|
/// A reusable set of bounded permissions. Roles do not grant authority by
/// themselves; an active, scoped assignment is required before a grant can be
/// issued.
pub(all) struct Role {
  role_id : String
  name : String
  permissions : Array[Permission]
} derive(Debug, Eq)

///|
/// A role assignment binds one institutional principal to one acting identity
/// and one exact scope. The assignment cap can only narrow role permissions.
pub(all) struct RoleAssignment {
  assignment_id : String
  role_id : String
  principal_id : String
  actor_id : String
  scope : String
  max_amount_minor : Int64
  active : Bool
} derive(Debug, Eq)

///|
/// An exact-scope incompatibility between two capabilities. The rule prevents
/// one actor from holding both sides through active role assignments.
pub(all) struct SeparationRule {
  rule_id : String
  first_capability : String
  second_capability : String
  scope : String
} derive(Debug, Eq)

///|
/// A bounded, effective-dated delegation. Delegations are not role
/// assignments and cannot widen the capability, scope, or amount ceiling
/// declared here.
pub(all) struct Delegation {
  delegation_id : String
  principal_id : String
  delegator_id : String
  delegate_actor_id : String
  capability : String
  scope : String
  max_amount_minor : Int64
  not_before_epoch : Int64
  expires_at_epoch : Int64?
  active : Bool
} derive(Debug, Eq)

///|
/// Local RBAC directory. It is intentionally separate from authentication;
/// callers supply an already-authenticated actor and receive a bounded
/// `AuthorityGrant` for the domain operation they are about to perform.
pub(all) struct AccessDirectory {
  roles : Array[Role]
  assignments : Array[RoleAssignment]
  separation_rules : Array[SeparationRule]
  delegations : Array[Delegation]
} derive(Debug, Eq)

///|
pub(all) suberror AccessError {
  EmptyIdentifier
  InvalidAmount
  DuplicateRole
  DuplicatePermission
  RoleNotFound
  DuplicateAssignment
  AssignmentNotFound
  InactiveAssignment
  DuplicateSeparationRule
  InvalidSeparationRule
  SeparationRuleNotFound
  SegregationViolation
  InvalidDelegation
  DuplicateDelegation
  DelegationNotFound
  InactiveDelegation
  DelegationNotYetEffective
  DelegationExpired
  WrongDelegate
  DelegationAmountDenied
  SelfDelegation
  WrongRequester
  PermissionDenied
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Permission::new(
  capability~ : String,
  scope~ : String,
  max_amount_minor~ : Int64,
) -> Permission raise AccessError {
  if capability.trim() == "" || scope.trim() == "" {
    raise AccessError::EmptyIdentifier
  }
  if max_amount_minor < 0L {
    raise AccessError::InvalidAmount
  }
  { capability, scope, max_amount_minor }
}

///|
pub fn Role::new(role_id~ : String, name~ : String) -> Role raise AccessError {
  if role_id.trim() == "" || name.trim() == "" {
    raise AccessError::EmptyIdentifier
  }
  { role_id, name, permissions: [] }
}

///|
pub fn Role::add_permission(
  self : Role,
  permission : Permission,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Role raise AccessError {
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="rbac:role:edit",
    scope="role:" + self.role_id,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  for existing in self.permissions {
    if existing.capability == permission.capability &&
      existing.scope == permission.scope {
      raise AccessError::DuplicatePermission
    }
  }
  let permissions = self.permissions.copy()
  permissions.push(permission)
  { ..self, permissions, }
}

///|
pub fn AccessDirectory::empty() -> AccessDirectory {
  { roles: [], assignments: [], separation_rules: [], delegations: [] }
}

///|
pub fn AccessDirectory::add_delegation(
  self : AccessDirectory,
  delegation : Delegation,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  if delegation.delegation_id.trim() == "" ||
    delegation.principal_id.trim() == "" ||
    delegation.delegator_id.trim() == "" ||
    delegation.delegate_actor_id.trim() == "" ||
    delegation.capability.trim() == "" ||
    delegation.scope.trim() == "" {
    raise AccessError::InvalidDelegation
  }
  if delegation.delegator_id == delegation.delegate_actor_id {
    raise AccessError::SelfDelegation
  }
  if delegation.max_amount_minor < 0L {
    raise AccessError::InvalidAmount
  }
  match delegation.expires_at_epoch {
    Some(expires) if expires <= delegation.not_before_epoch =>
      raise AccessError::InvalidDelegation
    _ => ()
  }
  @foundation.require_authority(
    grant,
    principal_id=delegation.principal_id,
    actor_id~,
    capability="rbac:delegation:create",
    scope=delegation.scope,
    amount_minor=delegation.max_amount_minor,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  for existing in self.delegations {
    if existing.delegation_id == delegation.delegation_id {
      raise AccessError::DuplicateDelegation
    }
  }
  let delegations = self.delegations.copy()
  delegations.push(delegation)
  { ..self, delegations, }
}

///|
pub fn AccessDirectory::issue_delegated_grant(
  self : AccessDirectory,
  delegation_id~ : String,
  requester_id~ : String,
  at_epoch~ : Int64,
  amount_minor~ : Int64,
) -> @foundation.AuthorityGrant raise AccessError {
  if amount_minor < 0L {
    raise AccessError::InvalidAmount
  }
  let mut found : Delegation? = None
  for delegation in self.delegations {
    if delegation.delegation_id == delegation_id {
      found = Some(delegation)
    }
  }
  let delegation = match found {
    Some(value) => value
    None => raise AccessError::DelegationNotFound
  }
  if !delegation.active {
    raise AccessError::InactiveDelegation
  }
  if requester_id != delegation.delegate_actor_id {
    raise AccessError::WrongDelegate
  }
  if at_epoch < delegation.not_before_epoch {
    raise AccessError::DelegationNotYetEffective
  }
  match delegation.expires_at_epoch {
    Some(expires) if at_epoch >= expires => raise AccessError::DelegationExpired
    _ => ()
  }
  if amount_minor > delegation.max_amount_minor {
    raise AccessError::DelegationAmountDenied
  }
  {
    grant_id: "delegation:" +
    delegation.delegation_id +
    ":" +
    at_epoch.to_string(),
    principal_id: delegation.principal_id,
    actor_id: delegation.delegate_actor_id,
    capability: delegation.capability,
    scope: delegation.scope,
    max_amount_minor: delegation.max_amount_minor,
    active: true,
  }
}

///|
pub fn AccessDirectory::revoke_delegation(
  self : AccessDirectory,
  delegation_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  let mut index : Int? = None
  for i in 0..<self.delegations.length() {
    if self.delegations[i].delegation_id == delegation_id {
      index = Some(i)
    }
  }
  let index = match index {
    Some(value) => value
    None => raise AccessError::DelegationNotFound
  }
  let delegation = self.delegations[index]
  @foundation.require_authority(
    grant,
    principal_id=delegation.principal_id,
    actor_id~,
    capability="rbac:delegation:revoke",
    scope=delegation.scope,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  let delegations = self.delegations.copy()
  delegations[index] = { ..delegation, active: false }
  { ..self, delegations, }
}

///|
pub fn AccessDirectory::add_separation_rule(
  self : AccessDirectory,
  rule : SeparationRule,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  if rule.rule_id.trim() == "" ||
    rule.first_capability.trim() == "" ||
    rule.second_capability.trim() == "" ||
    rule.scope.trim() == "" ||
    rule.first_capability == rule.second_capability {
    raise AccessError::InvalidSeparationRule
  }
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="rbac:sod:rule:create",
    scope=rule.scope,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  for existing in self.separation_rules {
    if existing.rule_id == rule.rule_id ||
      (
        existing.scope == rule.scope &&
        (
          (
            existing.first_capability == rule.first_capability &&
            existing.second_capability == rule.second_capability
          ) ||
          (
            existing.first_capability == rule.second_capability &&
            existing.second_capability == rule.first_capability
          )
        )
      ) {
      raise AccessError::DuplicateSeparationRule
    }
  }
  if existing_assignments_violate_rule(self, rule) {
    raise AccessError::SegregationViolation
  }
  let separation_rules = self.separation_rules.copy()
  separation_rules.push(rule)
  { ..self, separation_rules, }
}

///|
fn role_for(directory : AccessDirectory, role_id : String) -> Role? {
  for role in directory.roles {
    if role.role_id == role_id {
      return Some(role)
    }
  }
  None
}

///|
fn role_has_capability(
  role : Role,
  capability : String,
  scope : String,
) -> Bool {
  for permission in role.permissions {
    if permission.capability == capability && permission.scope == scope {
      return true
    }
  }
  false
}

///|
fn existing_assignments_violate_rule(
  directory : AccessDirectory,
  rule : SeparationRule,
) -> Bool {
  for first in directory.assignments {
    if !first.active || first.scope != rule.scope {
      continue
    }
    let first_role = match role_for(directory, first.role_id) {
      Some(value) => value
      None => continue
    }
    for second in directory.assignments {
      if !second.active ||
        second.assignment_id == first.assignment_id ||
        second.principal_id != first.principal_id ||
        second.actor_id != first.actor_id ||
        second.scope != rule.scope {
        continue
      }
      let second_role = match role_for(directory, second.role_id) {
        Some(value) => value
        None => continue
      }
      if (
          role_has_capability(first_role, rule.first_capability, rule.scope) &&
          role_has_capability(second_role, rule.second_capability, rule.scope)
        ) ||
        (
          role_has_capability(first_role, rule.second_capability, rule.scope) &&
          role_has_capability(second_role, rule.first_capability, rule.scope)
        ) {
        return true
      }
    }
  }
  false
}

///|
fn violates_separation(
  directory : AccessDirectory,
  assignment : RoleAssignment,
  role : Role,
) -> Bool {
  for rule in directory.separation_rules {
    if rule.scope != assignment.scope {
      continue
    }
    let has_first = role_has_capability(role, rule.first_capability, rule.scope)
    let has_second = role_has_capability(
      role,
      rule.second_capability,
      rule.scope,
    )
    if has_first && has_second {
      return true
    }
    for existing in directory.assignments {
      if !existing.active ||
        existing.principal_id != assignment.principal_id ||
        existing.actor_id != assignment.actor_id ||
        existing.scope != assignment.scope {
        continue
      }
      let existing_role = match role_for(directory, existing.role_id) {
        Some(value) => value
        None => continue
      }
      if (
          has_first &&
          role_has_capability(existing_role, rule.second_capability, rule.scope)
        ) ||
        (
          has_second &&
          role_has_capability(existing_role, rule.first_capability, rule.scope)
        ) {
        return true
      }
    }
  }
  false
}

///|
pub fn AccessDirectory::add_role(
  self : AccessDirectory,
  role : Role,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  @foundation.require_authority(
    grant,
    principal_id=grant.principal_id,
    actor_id~,
    capability="rbac:role:create",
    scope="role:" + role.role_id,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  for existing in self.roles {
    if existing.role_id == role.role_id {
      raise AccessError::DuplicateRole
    }
  }
  let roles = self.roles.copy()
  roles.push(role)
  { ..self, roles, }
}

///|
pub fn AccessDirectory::assign_role(
  self : AccessDirectory,
  assignment : RoleAssignment,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  if assignment.assignment_id.trim() == "" ||
    assignment.role_id.trim() == "" ||
    assignment.principal_id.trim() == "" ||
    assignment.actor_id.trim() == "" ||
    assignment.scope.trim() == "" {
    raise AccessError::EmptyIdentifier
  }
  if assignment.max_amount_minor < 0L {
    raise AccessError::InvalidAmount
  }
  let mut role_found = false
  for role in self.roles {
    if role.role_id == assignment.role_id {
      role_found = true
    }
  }
  if !role_found {
    raise AccessError::RoleNotFound
  }
  let role = match role_for(self, assignment.role_id) {
    Some(role) => role
    None => raise AccessError::RoleNotFound
  }
  if violates_separation(self, assignment, role) {
    raise AccessError::SegregationViolation
  }
  @foundation.require_authority(
    grant,
    principal_id=assignment.principal_id,
    actor_id~,
    capability="rbac:assignment:create",
    scope=assignment.scope,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  for existing in self.assignments {
    if existing.assignment_id == assignment.assignment_id {
      raise AccessError::DuplicateAssignment
    }
  }
  let assignments = self.assignments.copy()
  assignments.push(assignment)
  { ..self, assignments, }
}

///|
pub fn AccessDirectory::revoke_role(
  self : AccessDirectory,
  assignment_id~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccessDirectory raise AccessError {
  let mut index : Int? = None
  for i in 0..<self.assignments.length() {
    if self.assignments[i].assignment_id == assignment_id {
      index = Some(i)
    }
  }
  let index = match index {
    Some(index) => index
    None => raise AccessError::AssignmentNotFound
  }
  let assignment = self.assignments[index]
  @foundation.require_authority(
    grant,
    principal_id=assignment.principal_id,
    actor_id~,
    capability="rbac:assignment:revoke",
    scope=assignment.scope,
    amount_minor=0,
  ) catch {
    error => raise AccessError::NotAuthorized(error)
  }
  let assignments = self.assignments.copy()
  assignments[index] = { ..assignment, active: false }
  { ..self, assignments, }
}

///|
pub fn AccessDirectory::issue_grant(
  self : AccessDirectory,
  assignment_id~ : String,
  requester_id~ : String,
  capability~ : String,
  amount_minor~ : Int64,
) -> @foundation.AuthorityGrant raise AccessError {
  if capability.trim() == "" {
    raise AccessError::EmptyIdentifier
  }
  if amount_minor < 0L {
    raise AccessError::InvalidAmount
  }
  let mut assignment : RoleAssignment? = None
  for candidate in self.assignments {
    if candidate.assignment_id == assignment_id {
      assignment = Some(candidate)
    }
  }
  let assignment = match assignment {
    Some(assignment) => assignment
    None => raise AccessError::AssignmentNotFound
  }
  if !assignment.active {
    raise AccessError::InactiveAssignment
  }
  if assignment.actor_id != requester_id {
    raise AccessError::WrongRequester
  }
  let mut role : Role? = None
  for candidate in self.roles {
    if candidate.role_id == assignment.role_id {
      role = Some(candidate)
    }
  }
  let role = match role {
    Some(role) => role
    None => raise AccessError::RoleNotFound
  }
  let mut permission : Permission? = None
  for candidate in role.permissions {
    if candidate.capability == capability && candidate.scope == assignment.scope {
      permission = Some(candidate)
    }
  }
  let permission = match permission {
    Some(permission) => permission
    None => raise AccessError::PermissionDenied
  }
  let max_amount_minor = if permission.max_amount_minor <
    assignment.max_amount_minor {
    permission.max_amount_minor
  } else {
    assignment.max_amount_minor
  }
  if amount_minor > max_amount_minor {
    raise AccessError::PermissionDenied
  }
  {
    grant_id: "rbac:" + assignment.assignment_id + ":" + capability,
    principal_id: assignment.principal_id,
    actor_id: assignment.actor_id,
    capability,
    scope: assignment.scope,
    max_amount_minor,
    active: true,
  }
}
