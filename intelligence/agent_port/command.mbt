///|
pub(all) enum ProposedCommandState {
  ProposalOnly
  AcceptedForReview
  Rejected
  Superseded
} derive(Debug, Eq)

///|
/// A proposed company command is inert evidence. Runtime permission may have
/// allowed the agent to prepare it, but only a later MoonProj domain command
/// with a fresh company-authority decision may create a business effect.
pub(all) struct ProposedCommand {
  protocol_version : String
  command_id : String
  request_id : String
  attempt_id : String
  principal_id : String
  proposed_by : String
  capability : String
  scope : String
  amount_minor : Int64
  payload_schema : String
  payload : String
  evidence : Array[String]
  idempotency_key : String
  state : ProposedCommandState
  runtime_permission_observed : Bool
  company_authority_granted : Bool
} derive(Debug, Eq)

///|
pub fn ProposedCommand::is_well_formed(self : ProposedCommand) -> Bool {
  self.protocol_version == protocol_version() &&
  !self.command_id.trim().is_empty() &&
  !self.request_id.trim().is_empty() &&
  !self.attempt_id.trim().is_empty() &&
  !self.principal_id.trim().is_empty() &&
  !self.proposed_by.trim().is_empty() &&
  !self.capability.trim().is_empty() &&
  !self.scope.trim().is_empty() &&
  self.amount_minor >= 0 &&
  !self.payload_schema.trim().is_empty() &&
  !self.payload.trim().is_empty() &&
  !self.evidence.is_empty() &&
  nonempty_unique(self.evidence) &&
  !self.idempotency_key.trim().is_empty() &&
  !self.company_authority_granted
}

///|
pub fn ProposedCommand::accept_for_review(
  self : ProposedCommand,
) -> ProposedCommand raise AgentPortError {
  if !self.is_well_formed() || !(self.state is ProposalOnly) {
    raise Invalid("only a well-formed inert proposal may enter review")
  }
  { ..self, state: AcceptedForReview, }
}

///|
pub(all) struct AgentResult {
  protocol_version : String
  request_id : String
  attempt_id : String
  status : String
  findings : String
  confidence_percent : Int
  evidence : Array[String]
  proposed_commands : Array[ProposedCommand]
  error_classification : String
} derive(Debug, Eq)

///|
pub fn AgentResult::is_terminal(self : AgentResult) -> Bool {
  self.status == "succeeded" ||
  self.status == "failed" ||
  self.status == "rejected" ||
  self.status == "cancelled" ||
  self.status == "quarantined"
}

///|
pub fn AgentResult::is_well_formed(self : AgentResult) -> Bool {
  self.protocol_version == protocol_version() &&
  !self.request_id.trim().is_empty() &&
  !self.attempt_id.trim().is_empty() &&
  self.is_terminal() &&
  self.confidence_percent >= 0 &&
  self.confidence_percent <= 100 &&
  nonempty_unique(self.evidence) &&
  (
    self.status != "succeeded" ||
    (!self.findings.trim().is_empty() && !self.evidence.is_empty())
  ) &&
  self.proposed_commands.iter().all(command => command.is_well_formed())
}
