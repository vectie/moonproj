///|
suberror SmokeError {
  InvalidArtifact
  InvalidReceipt
  SelfApproval
  MarginBelowFloor
  CapacityExceeded
  InvalidRetainerState
  InvalidCollectionState
} derive(Debug, Eq)

///|
struct SmokeArtifact {
  artifact_id : String
  schema : String
  title : String
  recommendation : String
  evidence : Array[String]
  rendered_markdown : String
  content_digest : String
} derive(Debug, Eq)

///|
struct SandboxProviderReceipt {
  receipt_id : String
  provider : String
  reference_id : String
  amount_minor : Int64
  status : String
  sandbox : Bool
} derive(Debug, Eq)

///|
fn smoke_authority(
  grant_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  max_amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id: "opc-market-studio",
    actor_id,
    capability,
    scope,
    max_amount_minor,
    active: true,
  }
}

///|
fn smoke_cny(minor : Int64) -> @finance.Money raise {
  @finance.Money::new(minor~, currency="CNY")
}

///|
fn smoke_sha256(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn render_smoke_brief(
  artifact_id : String,
  title : String,
  recommendation : String,
  evidence : Array[String],
) -> SmokeArtifact raise SmokeError {
  if artifact_id.trim().is_empty() ||
    title.trim().is_empty() ||
    !(recommendation is ("go" | "no-go" | "experiment")) ||
    evidence.length() < 2 ||
    evidence.any(item => item.trim().is_empty()) {
    raise InvalidArtifact
  }
  let rendered_markdown = [
    "# " + title,
    "",
    "Recommendation: **" + recommendation + "**",
    "",
    "Evidence:",
    evidence.map(item => "- " + item).join("\n"),
  ].join("\n")
  {
    artifact_id,
    schema: "market-entry-brief@1",
    title,
    recommendation,
    evidence: evidence.copy(),
    rendered_markdown,
    content_digest: smoke_sha256(rendered_markdown),
  }
}

///|
fn sandbox_receipt(
  receipt_id : String,
  provider : String,
  reference_id : String,
  amount_minor : Int64,
) -> SandboxProviderReceipt raise SmokeError {
  if receipt_id.trim().is_empty() ||
    provider.trim().is_empty() ||
    reference_id.trim().is_empty() ||
    amount_minor < 0 {
    raise InvalidReceipt
  }
  {
    receipt_id,
    provider,
    reference_id,
    amount_minor,
    status: "sandbox-confirmed",
    sandbox: true,
  }
}

///|
fn smoke_record(
  record_type : String,
  record_id : String,
  payload : String,
  source_id : String,
) -> @store.StoredRecord raise {
  @store.StoredRecord::new(
    record_type~,
    record_id~,
    schema_version=1,
    payload~,
    source_id~,
  )
}
