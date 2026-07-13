///|
fn cbs_grant(capability : String, scope : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "cbs-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope,
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "CBS version protects subjects and freezes target cost" {
  let version = CbsVersion::new(
    version_id="cbs-v1",
    project_scope="project:p-001",
    actor_id="alice",
    grant=cbs_grant("cbs:create", "project:p-001"),
  )
  let version = version.add_subject(
    subject={
      subject_id: "s-001",
      code: "D",
      name: "Direct cost",
      parent_code: "",
      target_minor: 100000,
    },
    actor_id="alice",
    grant=cbs_grant("cbs:edit", "project:p-001"),
  )
  let version = version.add_subject(
    subject={
      subject_id: "s-002",
      code: "E",
      name: "Indirect cost",
      parent_code: "",
      target_minor: 20000,
    },
    actor_id="alice",
    grant=cbs_grant("cbs:edit", "project:p-001"),
  )
  let active = version.activate(
    actor_id="alice",
    grant=cbs_grant("cbs:activate", "project:p-001"),
  )
  let frozen = active.freeze(
    actor_id="alice",
    grant=cbs_grant("cbs:freeze", "project:p-001"),
  )
  assert_true(frozen.state == CbsVersionState::Frozen)
  assert_eq(frozen.target_total_minor(), 120000)
}

///|
test "CBS version rejects duplicate subject codes" {
  let version = CbsVersion::new(
    version_id="cbs-v2",
    project_scope="project:p-001",
    actor_id="alice",
    grant=cbs_grant("cbs:create", "project:p-001"),
  )
  let version = version.add_subject(
    subject={
      subject_id: "s-001",
      code: "D",
      name: "Direct cost",
      parent_code: "",
      target_minor: 100000,
    },
    actor_id="alice",
    grant=cbs_grant("cbs:edit", "project:p-001"),
  )
  try
    version.add_subject(
      subject={
        subject_id: "s-002",
        code: "D",
        name: "Duplicate",
        parent_code: "",
        target_minor: 1,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
  catch {
    CbsError::DuplicateCode => ()
    _ => fail("wrong cbs error")
  } noraise {
    _ => fail("expected cbs error")
  }
}

///|
test "CBS activation rejects an unknown parent" {
  let version = CbsVersion::new(
    version_id="cbs-parent-missing",
    project_scope="project:p-001",
    actor_id="alice",
    grant=cbs_grant("cbs:create", "project:p-001"),
  ).add_subject(
    subject={
      subject_id: "s-child",
      code: "CHILD",
      name: "Child",
      parent_code: "MISSING",
      target_minor: 1,
    },
    actor_id="alice",
    grant=cbs_grant("cbs:edit", "project:p-001"),
  )
  try
    version.activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  catch {
    CbsError::UnknownParent => ()
    _ => fail("wrong CBS parent error")
  } noraise {
    _ => fail("expected unknown CBS parent")
  }
}

///|
test "CBS activation rejects hierarchy cycles" {
  let version = CbsVersion::new(
      version_id="cbs-parent-cycle",
      project_scope="project:p-001",
      actor_id="alice",
      grant=cbs_grant("cbs:create", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-a",
        code: "A",
        name: "A",
        parent_code: "B",
        target_minor: 1,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-b",
        code: "B",
        name: "B",
        parent_code: "A",
        target_minor: 1,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
  try
    version.activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  catch {
    CbsError::HierarchyCycle => ()
    _ => fail("wrong CBS cycle error")
  } noraise {
    _ => fail("expected CBS hierarchy cycle")
  }
}

///|
test "active CBS version links a cost source to a governed subject" {
  let version = CbsVersion::new(
      version_id="cbs-link-v1",
      project_scope="project:p-001",
      actor_id="alice",
      grant=cbs_grant("cbs:create", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-link",
        code: "D",
        name: "Direct cost",
        parent_code: "",
        target_minor: 100000,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
    .activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  let link = version.link_cost(
    link_id="cbs-link-001",
    source_id="cost-001",
    subject_code="D",
    amount=@finance.Money::new(minor=60000, currency="CNY"),
    actor_id="alice",
    grant=cbs_grant("cbs:cost:link", "project:p-001"),
  )
  assert_eq(link.source_id, "cost-001")
  assert_eq(link.subject_code, "D")
  assert_eq(link.amount.minor, 60000L)
}

///|
test "CBS cost link rejects an unknown subject" {
  let version = CbsVersion::new(
      version_id="cbs-link-v2",
      project_scope="project:p-001",
      actor_id="alice",
      grant=cbs_grant("cbs:create", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-link-2",
        code: "D",
        name: "Direct cost",
        parent_code: "",
        target_minor: 100000,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
    .activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  try
    version.link_cost(
      link_id="cbs-link-002",
      source_id="cost-002",
      subject_code="UNKNOWN",
      amount=@finance.Money::new(minor=1, currency="CNY"),
      actor_id="alice",
      grant=cbs_grant("cbs:cost:link", "project:p-001"),
    )
  catch {
    CbsError::UnknownSubject => ()
    _ => fail("wrong cbs error")
  } noraise {
    _ => fail("expected unknown subject error")
  }
}

///|
test "CBS versions persist subjects and target totals" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let version = CbsVersion::new(
      version_id="cbs-projection",
      project_scope="project:p-001",
      actor_id="alice",
      grant=cbs_grant("cbs:create", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-projection",
        code: "D",
        name: "Direct cost",
        parent_code: "",
        target_minor: 100000,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
    .activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="cbs_version",
    aggregate_id="cbs-projection",
  )
  let projection = version.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("target_total_minor"))
      assert_true(latest.payload.contains("s-projection"))
    }
    None => fail("expected CBS projection")
  }
}

///|
test "CBS cost links persist source and subject identity" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let version = CbsVersion::new(
      version_id="cbs-link-projection",
      project_scope="project:p-001",
      actor_id="alice",
      grant=cbs_grant("cbs:create", "project:p-001"),
    )
    .add_subject(
      subject={
        subject_id: "s-link-projection",
        code: "D",
        name: "Direct cost",
        parent_code: "",
        target_minor: 100000,
      },
      actor_id="alice",
      grant=cbs_grant("cbs:edit", "project:p-001"),
    )
    .activate(
      actor_id="alice",
      grant=cbs_grant("cbs:activate", "project:p-001"),
    )
  let link = version.link_cost(
    link_id="cbs-link-projection-001",
    source_id="cost-projection-001",
    subject_code="D",
    amount=@finance.Money::new(minor=60000, currency="CNY"),
    actor_id="alice",
    grant=cbs_grant("cbs:cost:link", "project:p-001"),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="cbs_cost_link",
    aggregate_id="cbs-link-projection-001",
  )
  let projection = link.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("cost-projection-001"))
      assert_true(latest.payload.contains("\"subject_code\":\"D\""))
    }
    None => fail("expected cbs cost link projection")
  }
}
