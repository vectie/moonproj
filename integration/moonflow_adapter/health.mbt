///|
fn health_window_seconds(
  checked_at : String,
  valid_until : String,
) -> Int64 raise {
  if !canonical_utc_timestamp(checked_at) ||
    !canonical_utc_timestamp(valid_until) {
    fail("MoonProj adapter health requires canonical UTC timestamps")
  }
  let checked = @time.PlainDateTime::from_str(checked_at[0:19])
  let until = @time.PlainDateTime::from_str(valid_until[0:19])
  let seconds = until.to_unix_second() - checked.to_unix_second()
  if seconds <= 0L || seconds > 3600L {
    fail("MoonProj adapter health must expire within one hour")
  }
  seconds
}

///|
pub async fn publish_health(
  workspace : String,
  checked_at : String,
  valid_until : String,
  attestation_ref : String,
) -> Json {
  let ttl_seconds = health_window_seconds(checked_at, valid_until)
  let root = resolve_workspace(workspace)
  let evidence : Json = {
    "contract_id": "moonproj.moonflow-adapter-health-evidence.v1",
    "adapter_id": adapter_id(),
    "product_id": "moonproj",
    "pack_id": "moonproj",
    "pack_version": @project_plan.pack_version(),
    "protocol": protocol(),
    "operation_refs": [@project_plan.operation_ref()],
    "input_schema_refs": [@project_plan.input_schema_ref()],
    "output_schema_refs": [@project_plan.output_schema_ref()],
    "authority": "workspace-mutation",
    "claim_ceiling": "digital-artifact",
    "checks": [
      "exact-capability-contract-linked", "project-plan-domain-invariants-linked",
      "immutable-attempt-store-writable", "deterministic-reconciliation-linked",
      "business-effects-disabled",
    ],
    "checked_at": checked_at,
    "ttl_seconds": ttl_seconds,
  }
  let evidence_text = evidence.stringify(indent=2) + "\n"
  let evidence_digest = sha256_text(evidence_text)
  let evidence_ref = ".moonsuite/products/moonproj/health/evidence/\{evidence_digest[7:]}.json"
  ignore(immutable_text_ref(root, evidence_ref, evidence_text))
  let attestation : Json = {
    "contract_id": "moonflow.adapter-health.v1",
    "adapter_id": adapter_id(),
    "product_id": "moonproj",
    "pack_id": "moonproj",
    "pack_version": @project_plan.pack_version(),
    "protocol": protocol(),
    "status": "healthy",
    "checked_at": checked_at,
    "valid_until": valid_until,
    "operation_refs": [@project_plan.operation_ref()],
    "evidence_ref": evidence_ref,
    "evidence_digest": evidence_digest,
  }
  ignore(immutable_json_ref(root, attestation_ref, attestation))
  attestation
}
