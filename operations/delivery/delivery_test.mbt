///|
fn delivery_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-delivery",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "progress report requires evidence and acceptance" {
  let report = ProgressReport::new(
      report_id="progress-001",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=4500L,
      completed_value=@finance.Money::new(minor=300000, currency="CNY"),
      evidence_ids=["photo-001", "inspection-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  assert_true(report.state == ProgressState::Accepted)
  assert_eq(report.progress_bps, 4500L)
}

///|
test "deliverable supports remediation before acceptance" {
  let deliverable = Deliverable::new(
      deliverable_id="deliverable-001",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Handover package",
      evidence_ids=["handover-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:create"),
    )
    .submit(
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:submit"),
    )
    .reject(
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:reject"),
    )
  assert_true(deliverable.state == DeliverableState::Rejected)
}

///|
test "progress report rejects missing evidence" {
  try
    ProgressReport::new(
      report_id="progress-002",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=1000L,
      completed_value=@finance.Money::new(minor=100, currency="CNY"),
      evidence_ids=[],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
  catch {
    DeliveryError::MissingEvidence => ()
    _ => fail("wrong delivery error")
  } noraise {
    _ => fail("expected delivery error")
  }
}

///|
test "accepted progress builds a recognition link without posting" {
  let report = ProgressReport::new(
      report_id="progress-recognition",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=4500L,
      completed_value=@finance.Money::new(minor=300000, currency="CNY"),
      evidence_ids=["inspection-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  let event = report.to_recognition_event(
    event_id="delivery-recognition-001",
    event_type="delivery.accepted",
    contract_asset_account="contract-asset",
    revenue_account="revenue",
  )
  assert_eq(event.source_type, "delivery_progress")
  assert_eq(event.source_id, "progress-recognition")
  assert_eq(event.journal.postings[0].amount.minor, 300000L)
  assert_eq(event.journal.postings[1].amount.minor, 300000L)
}

///|
fn recognition_grant() -> @foundation.AuthorityGrant {
  {
    grant_id: "grant-delivery-recognition",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "delivery:recognition:create",
    scope: "project:p-001",
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "reviewed delivery recognition persists without posting or cash release" {
  let report = ProgressReport::new(
      report_id="progress-reviewed-recognition",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=4500L,
      completed_value=@finance.Money::new(minor=300000, currency="CNY"),
      evidence_ids=["inspection-reviewed-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  let recognition = report.recognize(
    recognition_id="recognition-reviewed-001",
    acceptance_id="acceptance-reviewed-001",
    acceptance_evidence_ids=["acceptance-evidence-reviewed-001"],
    accepted_by="alice",
    actor_id="alice",
    contract_asset_account="contract-asset",
    revenue_account="revenue",
    grant=recognition_grant(),
  )
  assert_eq(recognition.report_id, "progress-reviewed-recognition")
  assert_eq(recognition.accepted_by, "alice")
  assert_eq(recognition.accounting_event.source_type, "delivery_progress")
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
    aggregate_type="delivery_recognition",
    aggregate_id="recognition-reviewed-001",
  )
  let projection = recognition.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("pending_posting"))
      assert_true(latest.payload.contains("cash_released"))
      assert_true(latest.payload.contains("period_closed"))
      assert_true(latest.payload.contains("false"))
      assert_true(latest.payload.contains("acceptance-reviewed-001"))
      assert_true(latest.payload.contains("acceptance-evidence-reviewed-001"))
    }
    None => fail("expected delivery recognition projection")
  }
}

///|
test "delivery recognition requires matching acceptance evidence and authority" {
  let report = ProgressReport::new(
      report_id="progress-recognition-guard",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=4500L,
      completed_value=@finance.Money::new(minor=300000, currency="CNY"),
      evidence_ids=["inspection-guard-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  try
    report.recognize(
      recognition_id="recognition-guard-001",
      acceptance_id="acceptance-guard-001",
      acceptance_evidence_ids=["acceptance-evidence-guard-001"],
      accepted_by="bob",
      actor_id="alice",
      contract_asset_account="contract-asset",
      revenue_account="revenue",
      grant=recognition_grant(),
    )
  catch {
    DeliveryError::AcceptanceMismatch => ()
    _ => fail("wrong acceptance evidence error")
  } noraise {
    _ => fail("expected acceptance evidence guard")
  }
  try
    report.recognize(
      recognition_id="recognition-guard-002",
      acceptance_id="acceptance-guard-002",
      acceptance_evidence_ids=["acceptance-evidence-guard-002"],
      accepted_by="alice",
      actor_id="alice",
      contract_asset_account="contract-asset",
      revenue_account="revenue",
      grant=delivery_grant("delivery:progress:accept"),
    )
  catch {
    DeliveryError::NotAuthorized(_) => ()
    _ => fail("wrong recognition authority error")
  } noraise {
    _ => fail("expected recognition authority guard")
  }
}

///|
test "delivery recognition link is appendable and source-identifiable" {
  let report = ProgressReport::new(
      report_id="progress-recognition-record",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=5000L,
      completed_value=@finance.Money::new(minor=125000, currency="CNY"),
      evidence_ids=["inspection-002"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  let event = report.to_recognition_event(
    event_id="delivery-recognition-record-001",
    event_type="delivery.accepted",
    contract_asset_account="contract-asset",
    revenue_account="revenue",
  )
  let log = @accounting.AccountingEventLog::empty().append(
    event,
    scope="project:p-001",
    actor_id="alice",
    grant={
      grant_id: "accounting-delivery-grant",
      principal_id: "co-001",
      actor_id: "alice",
      capability: "accounting:event:append",
      scope: "project:p-001",
      max_amount_minor: 1000000,
      active: true,
    },
  )
  let record = log.events[0].to_record(schema_version=1)
  assert_eq(log.events.length(), 1)
  assert_eq(record.record_type, "accounting_event")
  assert_true(record.payload.contains("delivery_progress"))
}

///|
test "unaccepted progress cannot build a recognition link" {
  let report = ProgressReport::new(
    report_id="progress-unaccepted-recognition",
    project_id="p-001",
    principal_id="co-001",
    project_scope="project:p-001",
    progress_bps=4500L,
    completed_value=@finance.Money::new(minor=300000, currency="CNY"),
    evidence_ids=["inspection-001"],
    actor_id="alice",
    grant=delivery_grant("delivery:progress:create"),
  )
  try
    report.to_recognition_event(
      event_id="delivery-recognition-002",
      event_type="delivery.accepted",
      contract_asset_account="contract-asset",
      revenue_account="revenue",
    )
  catch {
    DeliveryError::InvalidState => ()
    _ => fail("wrong delivery error")
  } noraise {
    _ => fail("expected delivery recognition gate")
  }
}

///|
test "accepted progress supplies the cost forecast progress input" {
  let report = ProgressReport::new(
      report_id="progress-cost-forecast",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=5000L,
      completed_value=@finance.Money::new(minor=600000, currency="CNY"),
      evidence_ids=["inspection-cost-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  let forecast = report.to_cost_forecast(
    target=@finance.Money::new(minor=1000000, currency="CNY"),
    committed=@finance.Money::new(minor=100000, currency="CNY"),
    actual=@finance.Money::new(minor=600000, currency="CNY"),
  )
  assert_eq(forecast.project_scope, "project:p-001")
  assert_eq(forecast.progress_bps, 5000L)
  assert_eq(forecast.forecast_at_completion.minor, 1200000L)
}

///|
test "accepted progress and deliverables persist evidence projections" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let store = @store.RecordStore::new(schema).migrate(migration)
  let report = ProgressReport::new(
      report_id="progress-projection",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      progress_bps=4500L,
      completed_value=@finance.Money::new(minor=300000, currency="CNY"),
      evidence_ids=["photo-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:progress:create"),
    )
    .submit(actor_id="alice", grant=delivery_grant("delivery:progress:submit"))
    .accept(actor_id="alice", grant=delivery_grant("delivery:progress:accept"))
  let report_projection = @store.AggregateProjection::new(
    store,
    aggregate_type="progress_report",
    aggregate_id="progress-projection",
  )
  let report_projection = report.append_projection(report_projection)
  let deliverable = Deliverable::new(
      deliverable_id="deliverable-projection",
      project_id="p-001",
      principal_id="co-001",
      project_scope="project:p-001",
      name="Handover package",
      evidence_ids=["handover-001"],
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:create"),
    )
    .submit(
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:submit"),
    )
    .accept(
      actor_id="alice",
      grant=delivery_grant("delivery:deliverable:accept"),
    )
  let deliverable_projection = @store.AggregateProjection::new(
    report_projection.into_store(),
    aggregate_type="deliverable",
    aggregate_id="deliverable-projection",
  )
  let deliverable_projection = deliverable.append_projection(
    deliverable_projection,
  )
  match deliverable_projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("accepted"))
      assert_true(latest.payload.contains("handover-001"))
    }
    None => fail("expected deliverable projection")
  }
}
