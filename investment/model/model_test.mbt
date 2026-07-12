///|
fn model_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "model-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
test "investment model preserves versioned index evidence" {
  let version = ModelVersion::new(
    version_id="version-001",
    project_id="p-001",
    principal_id="co-001",
    name="Base case",
    version_no=1,
    current=true,
    created_by="alice",
    created_at="2026-01-01",
    remark=Some("source version"),
    actor_id="alice",
    grant=model_grant("investment:model:version:create"),
  )
  let model = InvestmentModel::new(version).add_index(
    ModelIndex::new(
      index_id="index-001",
      version_id="version-001",
      project_id="p-001",
      dimension="tax",
      full_code="Tax.VAT.Output",
      name="Output VAT",
      parent_code=Some("Tax.VAT"),
      unit=Some("%"),
      value_repr=Some("0.13"),
      remark=None,
      sort_order=1,
    ),
    actor_id="alice",
    grant=model_grant("investment:model:index:add"),
  )
  assert_eq(model.indexes.length(), 1)
  match model.indexes[0].value_repr {
    Some(value) => assert_eq(value, "0.13")
    None => fail("expected index value")
  }
  try
    model.add_index(
      ModelIndex::new(
        index_id="index-002",
        version_id="version-001",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.VAT.Output",
        name="Duplicate",
        parent_code=None,
        unit=None,
        value_repr=None,
        remark=None,
        sort_order=2,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
  catch {
    ModelError::DuplicateIndex => ()
    _ => fail("wrong duplicate index error")
  } noraise {
    _ => fail("expected duplicate index error")
  }
}

///|
test "investment model projection is identity-bound" {
  let version = ModelVersion::new(
    version_id="version-projection",
    project_id="p-001",
    principal_id="co-001",
    name="Projection",
    version_no=1,
    current=false,
    created_by="alice",
    created_at="2026-01-01",
    remark=None,
    actor_id="alice",
    grant=model_grant("investment:model:version:create"),
  )
  let model = InvestmentModel::new(version)
  let store = @store.RecordStore::new(@schema.SchemaState::initial()).migrate(
    @schema.MigrationStep::new(
      version=1,
      migration_id="V1__foundation",
      checksum="sha256:one",
      description="Create foundation tables",
    ),
  )
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="investment_model",
    aggregate_id="version-projection",
  )
  let projection = model.append_projection(projection)
  assert_true(projection.latest() is Some(_))
  try
    model.append_projection(
      @store.AggregateProjection::new(
        store,
        aggregate_type="investment_model",
        aggregate_id="other",
      ),
    )
  catch {
    ModelError::ProjectionIdentity => ()
    _ => fail("wrong model projection error")
  } noraise {
    _ => fail("expected model projection error")
  }
}
