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
fn validate_steps(steps : Array[ProcedureStep]) -> Bool {
  if steps.is_empty() {
    return false
  }
  for index, step in steps {
    if step.step_id.trim().is_empty() ||
      step.capability.trim().is_empty() ||
      step.instruction.trim().is_empty() ||
      step.acceptance_criteria.is_empty() ||
      !nonempty_unique(step.acceptance_criteria) ||
      step.evidence_required.is_empty() ||
      !nonempty_unique(step.evidence_required) {
      return false
    }
    for previous in 0..<index {
      if steps[previous].step_id == step.step_id {
        return false
      }
    }
  }
  true
}

///|
pub fn ProcedureCandidate::observe(
  candidate_id~ : String,
  principal_id~ : String,
  workflow_kind~ : String,
  proposed_by~ : String,
  source_attempt_ids~ : Array[String],
  source_evidence~ : Array[String],
  applicability~ : String,
  steps~ : Array[ProcedureStep],
) -> ProcedureCandidate raise ProcedureLearningError {
  if candidate_id.trim().is_empty() ||
    principal_id.trim().is_empty() ||
    workflow_kind.trim().is_empty() ||
    proposed_by.trim().is_empty() ||
    source_attempt_ids.is_empty() ||
    !nonempty_unique(source_attempt_ids) ||
    source_evidence.is_empty() ||
    !nonempty_unique(source_evidence) ||
    applicability.trim().is_empty() ||
    !validate_steps(steps) {
    raise Invalid(
      "procedure observation requires identity, attempts, evidence, scope, and valid steps",
    )
  }
  {
    candidate_id,
    principal_id,
    workflow_kind,
    version: 1,
    proposed_by,
    source_attempt_ids,
    source_evidence,
    applicability,
    steps,
    state: Observed,
    reviews: [],
    validation_receipts: [],
    authority_expansion_requested: false,
    auto_activation_allowed: false,
    revision: 0,
  }
}

///|
pub fn ProcedureCandidate::propose(
  self : ProcedureCandidate,
) -> ProcedureCandidate raise ProcedureLearningError {
  if self.state != Observed {
    raise InvalidState(self.state)
  }
  if self.authority_expansion_requested || self.auto_activation_allowed {
    raise AuthorityExpansionForbidden
  }
  { ..self, state: Proposed, revision: self.revision + 1 }
}

///|
pub fn ProcedureCandidate::start_review(
  self : ProcedureCandidate,
) -> ProcedureCandidate raise ProcedureLearningError {
  if self.state != Proposed {
    raise InvalidState(self.state)
  }
  { ..self, state: UnderReview, revision: self.revision + 1 }
}

///|
pub fn ProcedureCandidate::record_validation(
  self : ProcedureCandidate,
  receipt~ : String,
) -> ProcedureCandidate raise ProcedureLearningError {
  if self.state != UnderReview ||
    receipt.trim().is_empty() ||
    self.validation_receipts.contains(receipt) {
    raise Invalid("unique validation receipt requires a candidate under review")
  }
  let validation_receipts = self.validation_receipts.copy()
  validation_receipts.push(receipt)
  { ..self, validation_receipts, revision: self.revision + 1 }
}

///|
pub fn ProcedureCandidate::review(
  self : ProcedureCandidate,
  review : ProcedureReview,
) -> ProcedureCandidate raise ProcedureLearningError {
  if self.state != UnderReview {
    raise InvalidState(self.state)
  }
  if review.reviewer_id == self.proposed_by {
    raise SelfReview
  }
  if review.review_id.trim().is_empty() ||
    review.reviewer_id.trim().is_empty() ||
    review.rationale.trim().is_empty() ||
    review.evidence.is_empty() ||
    !nonempty_unique(review.evidence) ||
    review.reviewed_at_epoch < 0 {
    raise Invalid("review identity, rationale, evidence, and time are required")
  }
  if self.reviews
    .iter()
    .any(existing => {
      existing.review_id == review.review_id ||
      existing.reviewer_id == review.reviewer_id
    }) {
    raise DuplicateReview
  }
  let reviews = self.reviews.copy()
  reviews.push(review)
  let state = if review.decision is Reject { Rejected } else { UnderReview }
  { ..self, state, reviews, revision: self.revision + 1 }
}

///|
pub fn ProcedureCandidate::approve(
  self : ProcedureCandidate,
) -> ProcedureCandidate raise ProcedureLearningError {
  if self.state != UnderReview {
    raise InvalidState(self.state)
  }
  if self.authority_expansion_requested || self.auto_activation_allowed {
    raise AuthorityExpansionForbidden
  }
  if !self.reviews.iter().any(review => review.decision is Accept) {
    raise IndependentAcceptanceRequired
  }
  if self.reviews.iter().any(review => review.decision is RequestChanges) {
    raise IndependentAcceptanceRequired
  }
  if self.validation_receipts.is_empty() {
    raise ValidationRequired
  }
  { ..self, state: Approved, revision: self.revision + 1 }
}

///|
pub fn ProcedureLibrary::adopt(
  self : ProcedureLibrary,
  candidate : ProcedureCandidate,
  procedure_id~ : String,
) -> ProcedureLibrary raise ProcedureLearningError {
  if candidate.state != Approved || procedure_id.trim().is_empty() {
    raise Invalid(
      "only an approved candidate with a procedure id may be adopted",
    )
  }
  if candidate.authority_expansion_requested ||
    candidate.auto_activation_allowed {
    raise AuthorityExpansionForbidden
  }
  if self.procedures
    .iter()
    .any(procedure => {
      procedure.procedure_id == procedure_id ||
      (
        procedure.principal_id == candidate.principal_id &&
        procedure.workflow_kind == candidate.workflow_kind &&
        procedure.version == candidate.version
      )
    }) {
    raise DuplicateProcedure
  }
  let approval_evidence = candidate.source_evidence.copy()
  for receipt in candidate.validation_receipts {
    approval_evidence.push(receipt)
  }
  for review in candidate.reviews {
    for evidence in review.evidence {
      if !approval_evidence.contains(evidence) {
        approval_evidence.push(evidence)
      }
    }
  }
  let procedures = self.procedures.copy()
  procedures.push({
    procedure_id,
    principal_id: candidate.principal_id,
    workflow_kind: candidate.workflow_kind,
    version: candidate.version,
    applicability: candidate.applicability,
    steps: candidate.steps,
    source_candidate_id: candidate.candidate_id,
    approval_evidence,
    activated_count: 0,
    authority_expansion_allowed: false,
  })
  { revision: self.revision + 1, procedures }
}
