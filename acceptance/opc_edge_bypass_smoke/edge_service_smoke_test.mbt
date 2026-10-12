///|
test "sandbox edge service persists artifact delivery payment and survives restart" {
  let artifact = render_smoke_brief(
    "artifact-market-brief-acme-v1",
    "ACME Market Entry Decision Brief",
    "experiment",
    ["evidence/market-size", "evidence/customer-interviews"],
  )
  assert_true(artifact.rendered_markdown.contains("Recommendation"))
  assert_eq(artifact.content_digest.length(), 71)
  let delivery = sandbox_receipt(
    "sandbox-delivery-acme-v1",
    "sandbox-email",
    artifact.content_digest,
    0L,
  )
  let payment = sandbox_receipt(
    "sandbox-payment-acme-v1", "sandbox-payment-provider", "invoice-acme-v1", 250000L,
  )
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="opc-edge-smoke-v1",
    checksum="sha256:opc-edge-smoke-v1",
    description="sandbox sellable-engagement persistence envelope",
  )
  let store = @store.RecordStore::new(@schema.SchemaState::initial())
    .migrate(migration)
    .append_batch([
      smoke_record(
        "engagement", "engagement-acme-v1", "state=customer-accepted;price_minor=250000",
        "command/order-acme-v1",
      ),
      smoke_record(
        "artifact",
        artifact.artifact_id,
        artifact.rendered_markdown,
        artifact.content_digest,
      ),
      smoke_record(
        "sandbox_provider_receipt",
        delivery.receipt_id,
        "provider=" + delivery.provider + ";sandbox=true",
        "provider-event/delivery-acme-v1",
      ),
      smoke_record(
        "sandbox_provider_receipt",
        payment.receipt_id,
        "provider=" + payment.provider + ";amount_minor=250000;sandbox=true",
        "provider-event/payment-acme-v1",
      ),
    ])
  let restarted = @store.RecordStore::from_snapshot(store.to_snapshot())
  assert_eq(restarted.count_type(record_type="engagement"), 1)
  assert_eq(restarted.count_type(record_type="artifact"), 1)
  assert_eq(restarted.count_type(record_type="sandbox_provider_receipt"), 2)
  guard restarted.get(record_type="artifact", record_id=artifact.artifact_id)
    is Some(restored_artifact) else {
    fail("artifact must survive restart")
  }
  assert_eq(restored_artifact.source_id, artifact.content_digest)
  assert_true(delivery.sandbox && payment.sandbox)

  try
    restarted.append(
      smoke_record(
        "sandbox_provider_receipt", "duplicate-payment-receipt", "sandbox replay",
        "provider-event/payment-acme-v1",
      ),
    )
  catch {
    @store.StoreError::DuplicateSource => ()
    _ => fail("expected provider-event replay to be rejected")
  } noraise {
    _ => fail("provider-event replay must not append")
  }
}
