///|
fn notification_grant(capability : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "notification-test-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability,
    scope: "project:p-001",
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn draft_notification() -> Notification {
  try! Notification::new(
    notification_id="notification-001",
    principal_id="co-001",
    recipient_id="user-lmj-0001",
    scope="project:p-001",
    channel=NotificationChannel::InApp,
    template_code="task.overdue",
    subject="",
    body="Task requires review",
    source_event_id="workflow:instance-001",
    idempotency_key="workflow:instance-001:task.overdue:user-lmj-0001",
    actor_id="alice",
    grant=notification_grant("notification:create"),
  )
}

///|
test "notification outbox queues and confirms delivery explicitly" {
  let delivered = draft_notification()
    .queue(actor_id="alice", grant=notification_grant("notification:queue"))
    .attempt(actor_id="alice", grant=notification_grant("notification:attempt"))
    .confirm_delivered(
      provider_message_id="provider-msg-001",
      actor_id="alice",
      grant=notification_grant("notification:confirm"),
    )
  assert_true(delivered.state == NotificationState::Delivered)
  assert_eq(delivered.provider_message_id, "provider-msg-001")
  assert_eq(delivered.events.length(), 3)
}

///|
test "notification rejects invalid transitions and missing provider evidence" {
  try
    draft_notification().confirm_delivered(
      provider_message_id="provider-msg-001",
      actor_id="alice",
      grant=notification_grant("notification:confirm"),
    )
  catch {
    NotificationError::InvalidState => ()
    _ => fail("wrong notification state error")
  } noraise {
    _ => fail("expected notification state error")
  }
  try
    draft_notification()
    .queue(actor_id="alice", grant=notification_grant("notification:queue"))
    .attempt(actor_id="alice", grant=notification_grant("notification:attempt"))
    .confirm_delivered(
      provider_message_id="",
      actor_id="alice",
      grant=notification_grant("notification:confirm"),
    )
  catch {
    NotificationError::MissingProviderMessage => ()
    _ => fail("wrong provider evidence error")
  } noraise {
    _ => fail("expected provider evidence error")
  }
}

///|
test "notification projection keeps delivery and business effects separate" {
  let evidence = draft_notification()
    .queue(actor_id="alice", grant=notification_grant("notification:queue"))
    .bind_evidence(
      source_snapshot_id="erp-snapshot:notification-001",
      mapping_version="notification-map-v1",
      evidence_id="workflow:instance-001:notification-001",
    )
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
    aggregate_type="notification_outbox",
    aggregate_id="notification-001",
  )
  let projection = evidence.append_projection(projection)
  match projection.latest() {
    Some(latest) => {
      assert_true(latest.payload.contains("delivery_requested"))
      assert_true(latest.payload.contains("external_delivery_confirmed"))
      assert_true(latest.payload.contains("workflow_mutated"))
      assert_true(latest.payload.contains("accounting_posted"))
      assert_true(latest.payload.contains("erp-snapshot:notification-001"))
    }
    None => fail("expected notification projection")
  }
}
