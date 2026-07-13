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

///|
test "investment model evaluates explicit totals and derived ratios" {
  let version = ModelVersion::new(
    version_id="version-evaluation",
    project_id="p-001",
    principal_id="co-001",
    name="Evaluation",
    version_no=1,
    current=true,
    created_by="alice",
    created_at="2026-01-01",
    remark=None,
    actor_id="alice",
    grant=model_grant("investment:model:version:create"),
  )
  let model = InvestmentModel::new(version)
    .add_index(
      ModelIndex::new(
        index_id="revenue",
        version_id="version-evaluation",
        project_id="p-001",
        dimension="carry_over",
        full_code="CO.Revenue",
        name="Revenue",
        parent_code=None,
        unit=Some("万元"),
        value_repr=Some("18500"),
        remark=None,
        sort_order=1,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
    .add_index(
      ModelIndex::new(
        index_id="gross-profit",
        version_id="version-evaluation",
        project_id="p-001",
        dimension="carry_over",
        full_code="CO.GrossProfit",
        name="Gross profit",
        parent_code=None,
        unit=Some("万元"),
        value_repr=Some("4120"),
        remark=None,
        sort_order=2,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
    .add_index(
      ModelIndex::new(
        index_id="tax-total",
        version_id="version-evaluation",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.Total",
        name="Tax total",
        parent_code=None,
        unit=Some("万元"),
        value_repr=Some("1850"),
        remark=None,
        sort_order=3,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
    .add_index(
      ModelIndex::new(
        index_id="tax-vat",
        version_id="version-evaluation",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.VAT",
        name="VAT",
        parent_code=Some("Tax.Total"),
        unit=Some("万元"),
        value_repr=Some("720"),
        remark=None,
        sort_order=4,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
    .add_index(
      ModelIndex::new(
        index_id="tax-land",
        version_id="version-evaluation",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.LandVAT",
        name="Land VAT",
        parent_code=Some("Tax.Total"),
        unit=Some("万元"),
        value_repr=Some("1130"),
        remark=None,
        sort_order=5,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
  let evaluation = model.evaluate(
    source_snapshot_id="erp-snapshot:model-evaluation",
    mapping_version="model-map-v1",
  )
  assert_true(evaluation.validated)
  assert_eq(evaluation.parent_check_count, 1)
  assert_eq(evaluation.mismatch_count, 0)
  assert_eq(evaluation.values.length(), 5)
  assert_eq(evaluation.derived_metrics.length(), 2)
  assert_eq(evaluation.derived_metrics[0].metric_code, "CO.GrossMarginBps")
  assert_eq(evaluation.derived_metrics[0].value_bps, 2227L)
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
    aggregate_type="investment_model_evaluation",
    aggregate_id="version-evaluation",
  )
  let projection = evaluation.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("analytics_only"))
      assert_true(latest.payload.contains("investment_execution_authorized"))
      assert_true(latest.payload.contains("2227"))
    }
    None => fail("expected evaluation projection")
  }
  let mismatch_version = ModelVersion::new(
    version_id="version-mismatch",
    project_id="p-001",
    principal_id="co-001",
    name="Mismatch",
    version_no=1,
    current=false,
    created_by="alice",
    created_at="2026-01-01",
    remark=None,
    actor_id="alice",
    grant=model_grant("investment:model:version:create"),
  )
  let mismatch_model = InvestmentModel::new(mismatch_version)
    .add_index(
      ModelIndex::new(
        index_id="mismatch-parent",
        version_id="version-mismatch",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.Total",
        name="Tax total",
        parent_code=None,
        unit=Some("万元"),
        value_repr=Some("100"),
        remark=None,
        sort_order=1,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
    .add_index(
      ModelIndex::new(
        index_id="mismatch-child",
        version_id="version-mismatch",
        project_id="p-001",
        dimension="tax",
        full_code="Tax.Child",
        name="Tax child",
        parent_code=Some("Tax.Total"),
        unit=Some("万元"),
        value_repr=Some("90"),
        remark=None,
        sort_order=2,
      ),
      actor_id="alice",
      grant=model_grant("investment:model:index:add"),
    )
  let mismatch = mismatch_model.evaluate(
    source_snapshot_id="erp-snapshot:model-mismatch",
    mapping_version="model-map-v1",
  )
  assert_true(!mismatch.validated)
  assert_eq(mismatch.mismatch_count, 1)
  assert_true(mismatch.issues[0].contains("Tax.Total"))
}
