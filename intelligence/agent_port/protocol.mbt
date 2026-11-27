///|
/// The stable wire-level identity for MoonProj-owned execution requests.
pub fn protocol_version() -> String {
  "moonproj.agent-execution.v1"
}

///|
/// Coordination products keep distinct ownership even when they cooperate.
/// MoonProj owns the top-down company contract, MoonFlow owns one declared
/// workflow, and MoonTown owns bottom-up standing observation/orchestration.
#derive(Debug, Eq)
pub(all) enum CoordinationMode {
  CompanyTopDown
  MoonFlowSingleAgent
  MoonTownBottomUp
}

///|
/// Host/runtime permission and company authority are deliberately separate.
/// A runtime permission can allow a tool call but can never authorize a
/// payment, posting, filing, contract, trade, or other company effect.
#derive(Debug, Eq)
pub(all) enum AuthorizationPlane {
  RuntimePermission
  CompanyAuthority
}

///|
/// A product-owned capability request. A runtime such as MoonClaw may execute
/// it, MoonFlow may progress one declared workflow, and MoonTown may supply
/// observations. None of those products acquires company authority from this
/// request.
#derive(Debug, Eq)
pub(all) struct AgentRequest {
  protocol_version : String
  request_id : String
  work_item_id : String
  flow_run_id : String
  principal_id : String
  actor_id : String
  capability : String
  scope : String
  coordination_mode : CoordinationMode
  authority_ceiling_minor : Int64
  input_evidence : Array[String]
  input_digest : String
  acceptance_criteria : Array[String]
  expected_result_schema : String
  prohibited_effects : Array[String]
  idempotency_key : String
}

///|
#derive(Debug, Eq)
pub(all) suberror AgentPortError {
  Invalid(String)
  RevisionConflict(expected~ : Int32, actual~ : Int32)
  InvalidTransition(from~ : ExecutionPhase, to~ : ExecutionPhase)
  ClaimRequired
  ClaimMismatch
  ClaimAlreadyHeld
  LeaseNotExpired
  AttemptQuarantined
}

///|
fn nonempty_unique(values : Array[String]) -> Bool {
  for index, value in values {
    if value.trim().is_empty() {
      return false
    }
    for previous in 0..<index {
      if values[previous] == value {
        return false
      }
    }
  }
  true
}

///|
fn digest_well_formed(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].iter().all(ch => ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f'))
}

///|
pub fn AgentRequest::is_well_formed(self : AgentRequest) -> Bool {
  self.protocol_version == protocol_version() &&
  !self.request_id.trim().is_empty() &&
  !self.work_item_id.trim().is_empty() &&
  !self.flow_run_id.trim().is_empty() &&
  !self.principal_id.trim().is_empty() &&
  !self.actor_id.trim().is_empty() &&
  !self.capability.trim().is_empty() &&
  !self.scope.trim().is_empty() &&
  self.authority_ceiling_minor >= 0 &&
  !self.input_evidence.is_empty() &&
  nonempty_unique(self.input_evidence) &&
  digest_well_formed(self.input_digest) &&
  !self.acceptance_criteria.is_empty() &&
  nonempty_unique(self.acceptance_criteria) &&
  !self.expected_result_schema.trim().is_empty() &&
  !self.prohibited_effects.is_empty() &&
  nonempty_unique(self.prohibited_effects) &&
  !self.idempotency_key.trim().is_empty()
}

///|
pub fn AgentRequest::validate(self : AgentRequest) -> Unit raise AgentPortError {
  if !self.is_well_formed() {
    raise Invalid("malformed agent execution request")
  }
}

///|
/// The effects reserved to MoonProj company commands in the first protocol.
/// Callers may add stricter prohibitions but may not omit these effects.
pub fn reserved_company_effects() -> Array[String] {
  [
    "accounting.post", "cash.release", "contract.sign", "payment.release", "tax.file",
    "trade.execute",
  ]
}

///|
pub fn AgentRequest::protects_reserved_effects(self : AgentRequest) -> Bool {
  for required in reserved_company_effects() {
    if !self.prohibited_effects.contains(required) {
      return false
    }
  }
  true
}
