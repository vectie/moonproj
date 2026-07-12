///|
fn asset_grant(
  capability : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-asset",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-asset",
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn proposed_asset() -> Asset {
  try! Asset::new(
    asset_id="asset-001",
    principal_id="co-001",
    project_scope="project:p-asset",
    description="Production machine",
    acquisition_cost=try! @finance.Money::new(minor=12000, currency="CNY"),
    residual_value=try! @finance.Money::new(minor=2000, currency="CNY"),
    useful_life_months=10,
    actor_id="alice",
    grant=asset_grant("asset:propose", 12000),
  )
}

///|
test "asset lifecycle depreciates to residual value and journals" {
  let capitalized = proposed_asset().transition(
    AssetState::Capitalized,
    actor_id="alice",
    grant=asset_grant("asset:capitalize", 12000),
  )
  let active = capitalized.transition(
    AssetState::Active,
    actor_id="alice",
    grant=asset_grant("asset:activate", 12000),
  )
  let (after_first, first) = active.depreciate(
    period_id="2026-01",
    actor_id="alice",
    grant=asset_grant("asset:depreciate", 1000),
  )
  assert_eq(first.amount.minor, 1000)
  assert_eq(first.remaining_book_value_minor, 11000)
  let journal = first.to_journal(
    expense_account="6602",
    accumulated_depreciation_account="1602",
  )
  @finance.validate_journal(journal)
  let event = first.to_accounting_event(
    event_id="event-asset-depreciation",
    event_type="asset.depreciation",
    principal_id="co-001",
    expense_account="6602",
    accumulated_depreciation_account="1602",
  )
  assert_eq(event.source_type, "asset_depreciation")
  let (_, final_entry) = after_first.depreciate(
    period_id="2026-02",
    actor_id="alice",
    grant=asset_grant("asset:depreciate", 1000),
  )
  assert_eq(final_entry.amount.minor, 1000)
}

///|
test "asset rejects invalid residual value and depreciation state" {
  try
    Asset::new(
      asset_id="asset-bad",
      principal_id="co-001",
      project_scope="project:p-asset",
      description="Bad asset",
      acquisition_cost=@finance.Money::new(minor=100, currency="CNY"),
      residual_value=@finance.Money::new(minor=101, currency="CNY"),
      useful_life_months=1,
      actor_id="alice",
      grant=asset_grant("asset:propose", 101),
    )
  catch {
    AssetError::InvalidResidualValue => ()
    _ => fail("wrong asset error")
  } noraise {
    _ => fail("expected asset error")
  }
  try
    proposed_asset().depreciate(
      period_id="2026-01",
      actor_id="alice",
      grant=asset_grant("asset:depreciate", 1000),
    )
  catch {
    AssetError::InvalidDepreciationState => ()
    _ => fail("wrong depreciation error")
  } noraise {
    _ => fail("expected depreciation error")
  }
}

///|
test "disposed asset creates balanced gain disposal journal and link" {
  let active = proposed_asset()
    .transition(
      AssetState::Capitalized,
      actor_id="alice",
      grant=asset_grant("asset:capitalize", 12000),
    )
    .transition(
      AssetState::Active,
      actor_id="alice",
      grant=asset_grant("asset:activate", 12000),
    )
  let (active, _) = active.depreciate(
    period_id="2026-01",
    actor_id="alice",
    grant=asset_grant("asset:depreciate", 1000),
  )
  let disposed = active.transition(
    AssetState::Disposed,
    actor_id="alice",
    grant=asset_grant("asset:dispose", 12000),
  )
  let basis = disposed.to_disposal_entry(
    proceeds=@finance.Money::new(minor=12000, currency="CNY"),
  )
  assert_eq(basis.carrying_value_minor, 11000L)
  assert_eq(basis.gain_loss_minor, 1000L)
  let journal = basis.to_journal(
    cash_or_receivable_account="1001",
    asset_account="1601",
    accumulated_depreciation_account="1602",
    gain_account="6301",
    loss_account="6701",
  )
  @finance.validate_journal(journal)
  assert_eq(journal.postings.length(), 4)
  let event = basis.to_accounting_event(
    event_id="event-asset-disposal-gain",
    event_type="asset.disposal",
    principal_id="co-001",
    cash_or_receivable_account="1001",
    asset_account="1601",
    accumulated_depreciation_account="1602",
    gain_account="6301",
    loss_account="6701",
  )
  assert_eq(event.source_type, "asset_disposal")
  assert_eq(event.journal.postings.length(), 4)
}

///|
test "disposed asset creates balanced loss disposal journal" {
  let disposed = proposed_asset()
    .transition(
      AssetState::Capitalized,
      actor_id="alice",
      grant=asset_grant("asset:capitalize", 12000),
    )
    .transition(
      AssetState::Active,
      actor_id="alice",
      grant=asset_grant("asset:activate", 12000),
    )
    .transition(
      AssetState::Disposed,
      actor_id="alice",
      grant=asset_grant("asset:dispose", 12000),
    )
  let basis = disposed.to_disposal_entry(
    proceeds=@finance.Money::new(minor=8000, currency="CNY"),
  )
  assert_eq(basis.carrying_value_minor, 12000L)
  assert_eq(basis.gain_loss_minor, -4000L)
  let journal = basis.to_journal(
    cash_or_receivable_account="1001",
    asset_account="1601",
    accumulated_depreciation_account="1602",
    gain_account="6301",
    loss_account="6701",
  )
  @finance.validate_journal(journal)
  assert_eq(journal.postings.length(), 3)
}

///|
test "disposal basis requires disposed state" {
  try
    proposed_asset().to_disposal_entry(
      proceeds=@finance.Money::new(minor=100, currency="CNY"),
    )
  catch {
    AssetError::InvalidDisposalState => ()
    _ => fail("wrong disposal error")
  } noraise {
    _ => fail("expected disposal state gate")
  }
}

///|
test "asset register projection preserves lifecycle and depreciation state" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let projection = @store.AggregateProjection::new(
    store,
    aggregate_type="asset",
    aggregate_id="asset-001",
  )
  let asset = proposed_asset()
    .transition(
      AssetState::Capitalized,
      actor_id="alice",
      grant=asset_grant("asset:capitalize", 12000),
    )
    .transition(
      AssetState::Active,
      actor_id="alice",
      grant=asset_grant("asset:activate", 12000),
    )
  let (asset, _) = asset.depreciate(
    period_id="2026-01",
    actor_id="alice",
    grant=asset_grant("asset:depreciate", 1000),
  )
  let projection = asset.append_projection(projection)
  match projection.latest() {
    Some(record) => {
      assert_true(record.payload.contains("\"state\":\"active\""))
      assert_true(record.payload.contains("accumulated_depreciation_minor"))
    }
    None => fail("expected asset projection")
  }
  try
    asset.append_projection(
      @store.AggregateProjection::new(
        store,
        aggregate_type="project",
        aggregate_id="asset-001",
      ),
    )
  catch {
    AssetError::ProjectionIdentity => ()
    _ => fail("wrong asset projection identity error")
  } noraise {
    _ => fail("expected asset projection identity error")
  }
}
