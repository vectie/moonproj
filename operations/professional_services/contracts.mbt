///|
#derive(Debug, Eq)
pub(all) enum ShadowStage {
  Draft
  Ready
  InExecution
  WaitingForReview
  ShadowAccepted
  Archived
}

///|
#derive(Debug, Eq)
pub(all) enum ServiceRole {
  EngagementLead
  Researcher
  Producer
  IndependentReviewer
}

///|
#derive(Debug, Eq)
pub(all) enum ShadowWorkState {
  Planned
  Released
  Complete
  ReworkRequired
}

///|
#derive(Debug, Eq)
pub(all) struct ShadowWorkContract {
  work_id : String
  title : String
  role : ServiceRole
  assigned_actor_id : String
  dependencies : Array[String]
  acceptance_criteria : Array[String]
  expected_result_schema : String
  state : ShadowWorkState
  request_id : String
  attempt_id : String
  output_evidence : Array[String]
  findings : String
}

///|
#derive(Debug, Eq)
pub(all) struct ShadowActivity {
  activity_id : String
  work_id : String
  actor_id : String
  kind : String
  evidence : Array[String]
  at_epoch : Int64
}

///|
/// A shadow engagement can prepare delivery evidence and an invoice proposal,
/// but it cannot deliver externally, sign, post, or collect cash.
#derive(Debug, Eq)
pub(all) struct ProfessionalServiceShadow {
  engagement_id : String
  principal_id : String
  customer_id : String
  owner_id : String
  title : String
  currency : String
  proposed_fee_minor : Int64
  source_evidence : Array[String]
  stage : ShadowStage
  revision : Int32
  work : Array[ShadowWorkContract]
  activities : Array[ShadowActivity]
  accepted_evidence : Array[String]
  invoice_proposal : @agent_port.ProposedCommand?
  external_delivery_sent : Bool
  contract_signed : Bool
  accounting_posted : Bool
  payment_collected : Bool
}

///|
#derive(Debug, Eq)
pub(all) suberror ProfessionalServiceError {
  Invalid(String)
  InvalidStage(ShadowStage)
  DuplicateWork(String)
  UnknownDependency(String)
  DependencyCycle
  DependencyIncomplete(String)
  MissingRole(ServiceRole)
  ResultMismatch
  ReviewIndependenceRequired
}
