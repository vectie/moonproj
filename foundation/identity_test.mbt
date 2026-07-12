///|
test "identity validates institutional records" {
  let entity = LegalEntity::new(
    entity_id="co-001",
    legal_name="Example Holdings",
    functional_currency="CNY",
  )
  assert_eq(entity.entity_id, "co-001")
  assert_eq(entity.functional_currency, "CNY")
  let principal = Principal::new(id="co-001", kind=PrincipalKind::Entity)
  assert_true(principal.kind == PrincipalKind::Entity)
}

///|
test "authority is scoped and amount bounded" {
  let grant : AuthorityGrant = {
    grant_id: "grant-001",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "commitment:approve",
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
  assert_true(
    grant.allows(
      principal_id="co-001",
      actor_id="alice",
      capability="commitment:approve",
      scope="project:p-001",
      amount_minor=50000,
    ),
  )
  assert_false(
    grant.allows(
      principal_id="co-001",
      actor_id="alice",
      capability="commitment:approve",
      scope="project:p-002",
      amount_minor=50000,
    ),
  )
  require_authority(
    grant,
    principal_id="co-001",
    actor_id="alice",
    capability="commitment:approve",
    scope="project:p-001",
    amount_minor=100000,
  )
}

///|
test "invalid identity is rejected" {
  try
    LegalEntity::new(
      entity_id="",
      legal_name="Example Holdings",
      functional_currency="CNY",
    )
  catch {
    IdentityError::EmptyIdentifier(_) => ()
    _ => fail("wrong identity error")
  } noraise {
    _ => fail("expected identity error")
  }
}

///|
test "user directory keeps credentials and privilege outside identity" {
  let grant : AuthorityGrant = {
    grant_id: "user-create",
    principal_id: "co-001",
    actor_id: "migration",
    capability: "identity:user:create",
    scope: "organization:bu-001",
    max_amount_minor: 0,
    active: true,
  }
  let user = UserAccount::new(
    user_id="user-001",
    user_code="alice",
    display_name="Alice",
    principal_id="co-001",
    business_unit_id="bu-001",
    department_id=Some("dept-001"),
    enabled=true,
    actor_id="migration",
    grant~,
  )
  let directory = UserDirectory::empty().append(user)
  assert_eq(directory.users.length(), 1)
  assert_true(directory.users[0].state == UserAccountState::Active)
  try directory.append(user) catch {
    IdentityError::DuplicateUser => ()
    _ => fail("wrong duplicate user error")
  } noraise {
    _ => fail("expected duplicate user error")
  }
}
