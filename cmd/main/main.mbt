///|
fn grant_for(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-cli",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
}

///|
fn migration_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-cli-migration",
    principal_id: "co-001",
    actor_id: "migration",
    capability,
    scope: "erp-snapshot-cli",
    max_amount_minor: 0,
    active: true,
  }
}

///|
/// First executable parity slice: an authorized commitment moves through
/// approval, performance, and settlement while retaining transition evidence.
fn main {
  let entity = try! @foundation.LegalEntity::new(
    entity_id="co-001",
    legal_name="Example Holdings",
    functional_currency="CNY",
  )
  let amount = try! @finance.Money::new(
    minor=50000,
    currency=entity.functional_currency,
  )
  let draft = try! @commitment.Commitment::new(
    commitment_id="commit-001",
    principal_id=entity.entity_id,
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount~,
    actor_id="alice",
    grant=grant_for("commitment:create"),
  )
  let submitted = try! draft.transition(
    @commitment.CommitmentState::Submitted,
    actor_id="alice",
    grant=grant_for("commitment:submit"),
  )
  let approved = try! submitted.transition(
    @commitment.CommitmentState::Approved,
    actor_id="alice",
    grant=grant_for("commitment:approve"),
  )
  let performed = try! approved.transition(
    @commitment.CommitmentState::Performed,
    actor_id="alice",
    grant=grant_for("commitment:perform"),
  )
  let requested = try! @settlement.Settlement::request(
    performed,
    settlement_id="settlement-001",
    amount~,
    actor_id="alice",
    grant=grant_for("settlement:request"),
  )
  let settlement_approved = try! requested.transition(
    @settlement.SettlementState::Approved,
    actor_id="alice",
    grant=grant_for("settlement:approve"),
  )
  let released = try! settlement_approved.transition(
    @settlement.SettlementState::Released,
    actor_id="alice",
    grant=grant_for("settlement:release"),
  )
  let journal = try! released.to_journal(
    payable_account="2202",
    cash_account="1002",
  )
  try! @finance.validate_journal(journal)
  let state_name = match performed.state {
    @commitment.CommitmentState::Draft => "draft"
    @commitment.CommitmentState::Submitted => "submitted"
    @commitment.CommitmentState::Approved => "approved"
    @commitment.CommitmentState::Performed => "performed"
    @commitment.CommitmentState::Settled => "settled"
    @commitment.CommitmentState::Cancelled => "cancelled"
  }
  println("Company foundation ready: \{entity.legal_name}")
  println(
    "Commitment state: \{state_name}; settlement journal: \{journal.entry_id}",
  )

  let schema = @schema.SchemaState::initial()
  let schema_step = try! @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = try! @store.RecordStore::new(schema).migrate(schema_step)
  let manifest = try! @manifest.MigrationManifest::new(
      run_id="run-cli",
      source_snapshot_id="erp-snapshot-cli",
      principal_id=entity.entity_id,
      actor_id="migration",
      grant=migration_grant("migration:run:create"),
    )
    .add_item(
      {
        source_type: "ep_project",
        source_id: "project-cli",
        target_type: "legacy/project",
        target_id: Some("project-cli"),
        disposition: @manifest.MigrationDisposition::Imported,
        reason: "stable source identity",
      },
      actor_id="migration",
      grant=migration_grant("migration:item:add"),
    )
    .validate(
      actor_id="migration",
      grant=migration_grant("migration:run:validate"),
    )
  let envelope = try! @store.StoredRecord::new(
    record_type="legacy/project",
    record_id="project-cli",
    schema_version=1,
    payload="{\"proj_guid\":\"project-cli\"}",
    source_id="erp:ep_project:project-cli",
  )
  let receipt = try! @run.MigrationReceipt::apply(
    manifest,
    store,
    [envelope],
    actor_id="migration",
    grant=migration_grant("migration:run:apply"),
  )
  let shadow = try! @shadow.ShadowPlan::new(
    run_id="run-cli",
    source_snapshot_id="erp-snapshot-cli",
  ).add_expectation({
    metric_id: "project-count",
    domain: "project",
    dimension: "company:co-001",
    measure: @shadow.ShadowMeasure::RecordCount("legacy/project"),
    source_value: 1L,
    tolerance: 0L,
  })
  let comparison = shadow.compare(receipt.applied)
  let receipt = try! receipt.record_parity(comparison.report).certify()
  let migration_state = match receipt.state {
    @run.MigrationReceiptState::Certified => "certified"
    @run.MigrationReceiptState::Applied => "applied"
    @run.MigrationReceiptState::RolledBack => "rolled-back"
  }
  println(
    "Migration state: \{migration_state}; envelopes: \{receipt.applied.count_type(record_type="legacy/project")}",
  )
  let inventory = @erp.sanitized_v0_1_0_snapshot()
  println(
    "ERP snapshot controls: tables=\{inventory.tables.length()}; rows=\{inventory.total_rows}; mapped_rows=\{inventory.rows_for(@erp.SnapshotTableDisposition::Mapped)}; typed_rows=\{inventory.rows_for(@erp.SnapshotTableDisposition::TypedStaged)}; untyped_tables=\{inventory.count_disposition(@erp.SnapshotTableDisposition::Planned)}",
  )
  println("SQL catalog migrations: \{@sql.company_catalog().length()}")
}
