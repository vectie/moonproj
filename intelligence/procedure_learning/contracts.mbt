///|
#derive(Debug, Eq)
pub(all) enum ProcedureCandidateState {
  Observed
  Proposed
  UnderReview
  Approved
  Rejected
  Retired
}

///|
#derive(Debug, Eq)
pub(all) enum ProcedureReviewDecision {
  Accept
  RequestChanges
  Reject
}

///|
#derive(Debug, Eq)
pub(all) struct ProcedureStep {
  step_id : String
  capability : String
  instruction : String
  acceptance_criteria : Array[String]
  evidence_required : Array[String]
}

///|
#derive(Debug, Eq)
pub(all) struct ProcedureReview {
  review_id : String
  reviewer_id : String
  decision : ProcedureReviewDecision
  rationale : String
  evidence : Array[String]
  reviewed_at_epoch : Int64
}

///|
#derive(Debug, Eq)
pub(all) struct ProcedureCandidate {
  candidate_id : String
  principal_id : String
  workflow_kind : String
  version : Int32
  proposed_by : String
  source_attempt_ids : Array[String]
  source_evidence : Array[String]
  applicability : String
  steps : Array[ProcedureStep]
  state : ProcedureCandidateState
  reviews : Array[ProcedureReview]
  validation_receipts : Array[String]
  authority_expansion_requested : Bool
  auto_activation_allowed : Bool
  revision : Int32
}

///|
#derive(Debug, Eq)
pub(all) struct AdoptedProcedure {
  procedure_id : String
  principal_id : String
  workflow_kind : String
  version : Int32
  applicability : String
  steps : Array[ProcedureStep]
  source_candidate_id : String
  approval_evidence : Array[String]
  activated_count : Int32
  authority_expansion_allowed : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct ProcedureLibrary {
  revision : Int32
  procedures : Array[AdoptedProcedure]
}

///|
#derive(Debug, Eq)
pub(all) suberror ProcedureLearningError {
  Invalid(String)
  InvalidState(ProcedureCandidateState)
  SelfReview
  DuplicateReview
  IndependentAcceptanceRequired
  ValidationRequired
  AuthorityExpansionForbidden
  DuplicateProcedure
}

///|
pub fn ProcedureLibrary::new() -> ProcedureLibrary {
  { revision: 0, procedures: [], }
}
