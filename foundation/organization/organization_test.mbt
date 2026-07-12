///|
fn organization_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-organization",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope,
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "organization registry preserves parent hierarchy" {
  let root = OrganizationUnit::new(
    unit_id="co-001",
    principal_id="co-001",
    authority_scope="organization:co-001",
    parent_id=None,
    code="CO",
    name="Example Holdings",
    kind=OrganizationKind::Company,
    actor_id="alice",
    grant=organization_grant("organization:create", "organization:co-001"),
  ).activate(
    actor_id="alice",
    grant=organization_grant("organization:activate", "organization:co-001"),
  )
  let child = OrganizationUnit::new(
    unit_id="bu-001",
    principal_id="co-001",
    authority_scope="organization:bu-001",
    parent_id=Some("co-001"),
    code="BU-001",
    name="Development",
    kind=OrganizationKind::BusinessUnit,
    actor_id="alice",
    grant=organization_grant("organization:create", "organization:bu-001"),
  )
  let registry = OrganizationRegistry::empty().append(root).append(child)
  assert_eq(registry.units.length(), 2)
  assert_true(registry.units[1].parent_id == Some("co-001"))
}

///|
test "organization registry rejects a missing parent" {
  let child = OrganizationUnit::new(
    unit_id="bu-002",
    principal_id="co-001",
    authority_scope="organization:bu-002",
    parent_id=Some("missing"),
    code="BU-002",
    name="Missing Parent",
    kind=OrganizationKind::BusinessUnit,
    actor_id="alice",
    grant=organization_grant("organization:create", "organization:bu-002"),
  )
  try OrganizationRegistry::empty().append(child) catch {
    OrganizationError::MissingParent => ()
    _ => fail("wrong organization error")
  } noraise {
    _ => fail("expected organization error")
  }
}

///|
test "organization rejects a self-parent" {
  try
    OrganizationUnit::new(
      unit_id="bu-003",
      principal_id="co-001",
      authority_scope="organization:bu-003",
      parent_id=Some("bu-003"),
      code="BU-003",
      name="Self Parent",
      kind=OrganizationKind::BusinessUnit,
      actor_id="alice",
      grant=organization_grant("organization:create", "organization:bu-003"),
    )
  catch {
    OrganizationError::SelfParent => ()
    _ => fail("wrong organization error")
  } noraise {
    _ => fail("expected organization error")
  }
}
