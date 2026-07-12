///|
fn access_admin_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "admin/" + capability,
    principal_id: "co-001",
    actor_id: "admin-001",
    capability,
    scope,
    max_amount_minor: 1_000_000L,
    active: true,
  }
}

///|
fn delegation_admin_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "delegation-admin/" + capability,
    principal_id: "co-001",
    actor_id: "admin-001",
    capability,
    scope,
    max_amount_minor: 1_000_000L,
    active: true,
  }
}

///|
test "role assignment issues a bounded authority grant" {
  let role = Role::new(role_id="approver", name="Approver")
  let role = role.add_permission(
    Permission::new(
      capability="commitment:approve",
      scope="project:p-001",
      max_amount_minor=500_000L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:approver"),
  )
  let directory = AccessDirectory::empty()
  let directory = directory.add_role(
    role,
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:create", "role:approver"),
  )
  let directory = directory.assign_role(
    {
      assignment_id: "assign-001",
      role_id: "approver",
      principal_id: "co-001",
      actor_id: "user-001",
      scope: "project:p-001",
      max_amount_minor: 300_000L,
      active: true,
    },
    actor_id="admin-001",
    grant=access_admin_grant("rbac:assignment:create", "project:p-001"),
  )
  let grant = directory.issue_grant(
    assignment_id="assign-001",
    requester_id="user-001",
    capability="commitment:approve",
    amount_minor=250_000L,
  )
  assert_true(
    grant.allows(
      principal_id="co-001",
      actor_id="user-001",
      capability="commitment:approve",
      scope="project:p-001",
      amount_minor=250_000L,
    ),
  )
  assert_false(
    grant.allows(
      principal_id="co-001",
      actor_id="user-001",
      capability="commitment:approve",
      scope="project:p-001",
      amount_minor=300_001L,
    ),
  )
}

///|
test "role assignment rejects wrong requester and scope permission" {
  let role = Role::new(role_id="reader", name="Reader")
  let role = role.add_permission(
    Permission::new(
      capability="report:read",
      scope="organization:bu-001",
      max_amount_minor=0L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:reader"),
  )
  let directory = AccessDirectory::empty().add_role(
    role,
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:create", "role:reader"),
  )
  let directory = directory.assign_role(
    {
      assignment_id: "assign-002",
      role_id: "reader",
      principal_id: "co-001",
      actor_id: "user-002",
      scope: "organization:bu-001",
      max_amount_minor: 0L,
      active: true,
    },
    actor_id="admin-001",
    grant=access_admin_grant("rbac:assignment:create", "organization:bu-001"),
  )
  let _grant = directory.issue_grant(
    assignment_id="assign-002",
    requester_id="user-002",
    capability="report:read",
    amount_minor=0L,
  )
  try
    directory.issue_grant(
      assignment_id="assign-002",
      requester_id="user-003",
      capability="report:read",
      amount_minor=0L,
    )
  catch {
    AccessError::WrongRequester => ()
    _ => fail("wrong access error")
  } noraise {
    _ => fail("expected requester rejection")
  }
  try
    directory.issue_grant(
      assignment_id="assign-002",
      requester_id="user-002",
      capability="report:write",
      amount_minor=0L,
    )
  catch {
    AccessError::PermissionDenied => ()
    _ => fail("wrong access error")
  } noraise {
    _ => fail("expected capability rejection")
  }
}

///|
test "revoking an assignment prevents future grants" {
  let role = Role::new(role_id="operator", name="Operator")
  let role = role.add_permission(
    Permission::new(
      capability="task:update",
      scope="project:p-002",
      max_amount_minor=0L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:operator"),
  )
  let directory = AccessDirectory::empty().add_role(
    role,
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:create", "role:operator"),
  )
  let directory = directory.assign_role(
    {
      assignment_id: "assign-003",
      role_id: "operator",
      principal_id: "co-001",
      actor_id: "user-003",
      scope: "project:p-002",
      max_amount_minor: 0L,
      active: true,
    },
    actor_id="admin-001",
    grant=access_admin_grant("rbac:assignment:create", "project:p-002"),
  )
  let directory = directory.revoke_role(
    assignment_id="assign-003",
    actor_id="admin-001",
    grant=access_admin_grant("rbac:assignment:revoke", "project:p-002"),
  )
  try
    directory.issue_grant(
      assignment_id="assign-003",
      requester_id="user-003",
      capability="task:update",
      amount_minor=0L,
    )
  catch {
    AccessError::InactiveAssignment => ()
    _ => fail("wrong access error")
  } noraise {
    _ => fail("expected inactive assignment")
  }
}

///|
test "separation rule blocks incompatible role assignments at one scope" {
  let preparer = Role::new(role_id="preparer", name="Preparer").add_permission(
    Permission::new(
      capability="expense:submit",
      scope="project:p-003",
      max_amount_minor=100000L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:preparer"),
  )
  let approver = Role::new(role_id="approver-sod", name="Approver").add_permission(
    Permission::new(
      capability="expense:approve",
      scope="project:p-003",
      max_amount_minor=100000L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:approver-sod"),
  )
  let directory = AccessDirectory::empty()
    .add_role(
      preparer,
      actor_id="admin-001",
      grant=access_admin_grant("rbac:role:create", "role:preparer"),
    )
    .add_role(
      approver,
      actor_id="admin-001",
      grant=access_admin_grant("rbac:role:create", "role:approver-sod"),
    )
    .add_separation_rule(
      {
        rule_id: "sod-expense-submit-approve",
        first_capability: "expense:submit",
        second_capability: "expense:approve",
        scope: "project:p-003",
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:sod:rule:create", "project:p-003"),
    )
    .assign_role(
      {
        assignment_id: "sod-preparer-assignment",
        role_id: "preparer",
        principal_id: "co-001",
        actor_id: "user-sod-001",
        scope: "project:p-003",
        max_amount_minor: 100000L,
        active: true,
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:assignment:create", "project:p-003"),
    )
  try
    directory.assign_role(
      {
        assignment_id: "sod-approver-assignment",
        role_id: "approver-sod",
        principal_id: "co-001",
        actor_id: "user-sod-001",
        scope: "project:p-003",
        max_amount_minor: 100000L,
        active: true,
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:assignment:create", "project:p-003"),
    )
  catch {
    AccessError::SegregationViolation => ()
    _ => fail("wrong separation-of-duties error")
  } noraise {
    _ => fail("expected separation-of-duties rejection")
  }
}

///|
test "adding a separation rule rejects an existing conflict" {
  let preparer = Role::new(role_id="preparer-late", name="Preparer").add_permission(
    Permission::new(
      capability="expense:submit",
      scope="project:p-004",
      max_amount_minor=100000L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:preparer-late"),
  )
  let approver = Role::new(role_id="approver-late", name="Approver").add_permission(
    Permission::new(
      capability="expense:approve",
      scope="project:p-004",
      max_amount_minor=100000L,
    ),
    actor_id="admin-001",
    grant=access_admin_grant("rbac:role:edit", "role:approver-late"),
  )
  let existing = AccessDirectory::empty()
    .add_role(
      preparer,
      actor_id="admin-001",
      grant=access_admin_grant("rbac:role:create", "role:preparer-late"),
    )
    .add_role(
      approver,
      actor_id="admin-001",
      grant=access_admin_grant("rbac:role:create", "role:approver-late"),
    )
    .assign_role(
      {
        assignment_id: "late-preparer",
        role_id: "preparer-late",
        principal_id: "co-001",
        actor_id: "user-sod-002",
        scope: "project:p-004",
        max_amount_minor: 100000L,
        active: true,
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:assignment:create", "project:p-004"),
    )
    .assign_role(
      {
        assignment_id: "late-approver",
        role_id: "approver-late",
        principal_id: "co-001",
        actor_id: "user-sod-002",
        scope: "project:p-004",
        max_amount_minor: 100000L,
        active: true,
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:assignment:create", "project:p-004"),
    )
  try
    existing.add_separation_rule(
      {
        rule_id: "late-sod-rule",
        first_capability: "expense:submit",
        second_capability: "expense:approve",
        scope: "project:p-004",
      },
      actor_id="admin-001",
      grant=access_admin_grant("rbac:sod:rule:create", "project:p-004"),
    )
  catch {
    AccessError::SegregationViolation => ()
    _ => fail("wrong late separation error")
  } noraise {
    _ => fail("expected late separation rejection")
  }
}

///|
test "effective-dated delegation issues bounded grants and expires" {
  let directory = AccessDirectory::empty().add_delegation(
    {
      delegation_id: "delegation-001",
      principal_id: "co-001",
      delegator_id: "admin-001",
      delegate_actor_id: "user-delegate-001",
      capability: "payment:approve",
      scope: "project:p-005",
      max_amount_minor: 500000L,
      not_before_epoch: 100L,
      expires_at_epoch: Some(200L),
      active: true,
    },
    actor_id="admin-001",
    grant=delegation_admin_grant("rbac:delegation:create", "project:p-005"),
  )
  try
    directory.issue_delegated_grant(
      delegation_id="delegation-001",
      requester_id="user-delegate-001",
      at_epoch=99L,
      amount_minor=100000L,
    )
  catch {
    AccessError::DelegationNotYetEffective => ()
    _ => fail("wrong delegation time error")
  } noraise {
    _ => fail("expected not-yet-effective delegation")
  }
  let grant = directory.issue_delegated_grant(
    delegation_id="delegation-001",
    requester_id="user-delegate-001",
    at_epoch=100L,
    amount_minor=400000L,
  )
  assert_true(
    grant.allows(
      principal_id="co-001",
      actor_id="user-delegate-001",
      capability="payment:approve",
      scope="project:p-005",
      amount_minor=400000L,
    ),
  )
  try
    directory.issue_delegated_grant(
      delegation_id="delegation-001",
      requester_id="user-delegate-001",
      at_epoch=200L,
      amount_minor=1L,
    )
  catch {
    AccessError::DelegationExpired => ()
    _ => fail("wrong delegation expiry error")
  } noraise {
    _ => fail("expected expired delegation")
  }
}

///|
test "revoking delegation prevents future grants" {
  let directory = AccessDirectory::empty().add_delegation(
    {
      delegation_id: "delegation-revoke-001",
      principal_id: "co-001",
      delegator_id: "admin-001",
      delegate_actor_id: "user-delegate-002",
      capability: "report:read",
      scope: "organization:bu-001",
      max_amount_minor: 0L,
      not_before_epoch: 0L,
      expires_at_epoch: None,
      active: true,
    },
    actor_id="admin-001",
    grant=delegation_admin_grant(
      "rbac:delegation:create", "organization:bu-001",
    ),
  )
  let directory = directory.revoke_delegation(
    delegation_id="delegation-revoke-001",
    actor_id="admin-001",
    grant=delegation_admin_grant(
      "rbac:delegation:revoke", "organization:bu-001",
    ),
  )
  try
    directory.issue_delegated_grant(
      delegation_id="delegation-revoke-001",
      requester_id="user-delegate-002",
      at_epoch=1L,
      amount_minor=0L,
    )
  catch {
    AccessError::InactiveDelegation => ()
    _ => fail("wrong revoked delegation error")
  } noraise {
    _ => fail("expected revoked delegation")
  }
}
