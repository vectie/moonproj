///|
/// A product-owned capability request. A runtime such as MoonClaw may implement it.
pub(all) struct AgentRequest {
  request_id : String
  principal_id : String
  actor_id : String
  capability : String
  authority_ceiling_minor : Int64
  input_evidence : Array[String]
  expected_result_schema : String
  idempotency_key : String
} derive(Debug, Eq)

///|
pub(all) struct ProposedCommand {
  command_id : String
  capability : String
  payload : String
} derive(Debug, Eq)

///|
pub(all) struct AgentResult {
  request_id : String
  status : String
  findings : String
  confidence_percent : Int
  evidence : Array[String]
  proposed_commands : Array[ProposedCommand]
  error_classification : String
} derive(Debug, Eq)

///|
pub fn AgentRequest::is_well_formed(self : AgentRequest) -> Bool {
  self.request_id.trim() != "" &&
  self.principal_id.trim() != "" &&
  self.actor_id.trim() != "" &&
  self.capability.trim() != "" &&
  self.authority_ceiling_minor >= 0 &&
  self.expected_result_schema.trim() != "" &&
  self.idempotency_key.trim() != ""
}

///|
pub fn AgentResult::is_terminal(self : AgentResult) -> Bool {
  self.status == "succeeded" ||
  self.status == "failed" ||
  self.status == "rejected"
}
