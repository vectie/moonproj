///|
pub fn pack_version() -> String {
  "0.1.0"
}

///|
pub fn operation_id() -> String {
  "project.plan.prepare"
}

///|
pub fn operation_ref() -> String {
  "moonproj/\{operation_id()}@\{pack_version()}"
}

///|
pub fn input_schema_ref() -> String {
  "moonproj/project-plan-request@1.0.0"
}

///|
pub fn output_schema_ref() -> String {
  "moonproj/project-plan-artifact@1.0.0"
}

///|
pub(all) struct ProjectIdentity {
  project_id : String
  principal_id : String
  code : String
  name : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanOwner {
  owner_id : String
  display_name : String
  role : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BudgetEnvelope {
  currency : String
  limit_minor : Int64
  contingency_minor : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanTaskInput {
  task_id : String
  name : String
  owner_id : String
  milestone_id : String
  planned_cost_minor : Int64
  dependencies : Array[String]
  acceptance_gate_ids : Array[String]
  source_evidence_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanMilestone {
  milestone_id : String
  name : String
  owner_id : String
  target_date : String
  task_ids : Array[String]
  acceptance_gate_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanRisk {
  risk_id : String
  summary : String
  severity : String
  owner_id : String
  mitigation : String
  related_task_ids : Array[String]
  source_evidence_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AcceptanceGate {
  gate_id : String
  name : String
  owner_id : String
  scope_type : String
  scope_id : String
  criteria : Array[String]
  required_evidence : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SourceEvidence {
  artifact_ref : String
  digest : String
  observed_at : String
  kind : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectPlanRequest {
  contract_id : String
  operation_ref : String
  plan_request_id : String
  project : ProjectIdentity
  prepared_by : String
  prepared_at : String
  owners : Array[PlanOwner]
  budget_envelope : BudgetEnvelope
  tasks : Array[PlanTaskInput]
  milestones : Array[PlanMilestone]
  risks : Array[PlanRisk]
  acceptance_gates : Array[AcceptanceGate]
  source_evidence : Array[SourceEvidence]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreparedProject {
  project_id : String
  principal_id : String
  code : String
  name : String
  stage : String
  state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreparedTask {
  task_id : String
  name : String
  owner_id : String
  milestone_id : String
  planned_cost_minor : Int64
  currency : String
  dependencies : Array[String]
  acceptance_gate_ids : Array[String]
  source_evidence_refs : Array[String]
  progress_bps : Int64
  state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BudgetProjection {
  currency : String
  limit_minor : Int64
  contingency_minor : Int64
  planned_total_minor : Int64
  unallocated_minor : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanWorkflowStatus {
  status : String
  current_gate : String
  review_required : Bool
  accepted : Bool
  next_actions : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanAuthorityEffects {
  spend_authorized : Bool
  accounting_posted : Bool
  payment_released : Bool
  contract_signed : Bool
  work_executed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectPlanArtifact {
  contract_id : String
  operation_ref : String
  input_schema_ref : String
  output_schema_ref : String
  plan_request_id : String
  attempt_id : String
  request_digest : String
  project : PreparedProject
  owners : Array[PlanOwner]
  budget : BudgetProjection
  tasks : Array[PreparedTask]
  milestones : Array[PlanMilestone]
  risks : Array[PlanRisk]
  acceptance_gates : Array[AcceptanceGate]
  source_evidence : Array[SourceEvidence]
  workflow : PlanWorkflowStatus
  authority_effects : PlanAuthorityEffects
  claim_ceiling : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror ProjectPlanCapabilityError {
  Invalid(String)
  Project(@project.ProjectError)
  Plan(@project.PlanError)
  Money(@finance.MoneyError)
} derive(Debug, Eq)
