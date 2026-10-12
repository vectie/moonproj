///|
pub(all) enum ProductInGateDecision {
  Unknown
  Experiment
  Pass
  Park
} derive(Debug, Eq)

///|
pub(all) struct WorkflowAdoptionEvidence {
  principal_id : String
  product_id : String
  workflow_id : String
  decision : ProductInGateDecision
  product_in_gate_receipt : String
  accepted_customer_evidence : Array[String]
  owner_id : String
  adoption_count : Int
  successful_completions : Int
  reviewed_at_epoch : Int64
} derive(Debug, Eq)

///|
pub(all) struct TransactionalPack {
  pack : ExtensionPack
  price_currency : String
  price_minor : Int64
  transaction_provider : String
} derive(Debug, Eq)

///|
pub(all) struct TransactionalPackActivationReceipt {
  receipt_id : String
  principal_id : String
  product_id : String
  workflow_id : String
  extension_id : String
  product_in_gate_receipt : String
  payment_receipt : String
  activated_by : String
  activated_at_epoch : Int64
} derive(Debug, Eq)

///|
pub(all) enum AutonomousExpansion {
  AutonomousStaffing
  AgentMarketplace
} derive(Debug, Eq)

///|
pub(all) struct AutonomousExpansionReview {
  review_id : String
  principal_id : String
  product_id : String
  feature : AutonomousExpansion
  requested_by : String
  reviewed_by : String
  scope : String
  risk_evidence : Array[String]
  approved : Bool
  reviewed_at_epoch : Int64
} derive(Debug, Eq)

///|
pub(all) struct AutonomousExpansionGateReceipt {
  receipt_id : String
  feature : AutonomousExpansion
  principal_id : String
  product_id : String
  workflow_id : String
  review_id : String
  enabled : Bool
  company_authority_granted : Bool
} derive(Debug, Eq)

///|
pub(all) suberror ProductAdoptionError {
  Invalid(String)
  ProductInGatePassRequired
  FirstWorkflowAdoptionRequired
  SuccessfulCompletionRequired
  CustomerEvidenceRequired
  PaymentReceiptRequired
  IndependentReviewRequired
  ExpansionReviewRejected
  Catalog(ProductCatalogError)
} derive(Debug, Eq)

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
pub fn WorkflowAdoptionEvidence::qualifies(
  self : WorkflowAdoptionEvidence,
) -> Bool {
  self.decision is Pass &&
  !self.principal_id.trim().is_empty() &&
  !self.product_id.trim().is_empty() &&
  !self.workflow_id.trim().is_empty() &&
  !self.product_in_gate_receipt.trim().is_empty() &&
  !self.owner_id.trim().is_empty() &&
  self.adoption_count >= 1 &&
  self.successful_completions >= 1 &&
  !self.accepted_customer_evidence.is_empty() &&
  nonempty_unique(self.accepted_customer_evidence) &&
  self.reviewed_at_epoch >= 0
}

///|
fn validate_adoption(
  adoption : WorkflowAdoptionEvidence,
) -> Unit raise ProductAdoptionError {
  if adoption.decision != Pass ||
    adoption.product_in_gate_receipt.trim().is_empty() {
    raise ProductInGatePassRequired
  }
  if adoption.adoption_count < 1 || adoption.workflow_id.trim().is_empty() {
    raise FirstWorkflowAdoptionRequired
  }
  if adoption.successful_completions < 1 {
    raise SuccessfulCompletionRequired
  }
  if adoption.accepted_customer_evidence.is_empty() {
    raise CustomerEvidenceRequired
  }
  if !adoption.qualifies() {
    raise Invalid("workflow adoption evidence is incomplete")
  }
}

///|
pub fn ProductProfile::activate_transactional(
  self : ProductProfile,
  transactional : TransactionalPack,
  adoption : WorkflowAdoptionEvidence,
  payment_receipt~ : String,
  activated_by~ : String,
  activated_at_epoch~ : Int64,
) -> (ProductProfile, TransactionalPackActivationReceipt) raise ProductAdoptionError {
  validate_adoption(adoption)
  if adoption.product_id != self.profile_id ||
    transactional.price_currency.length() != 3 ||
    transactional.price_minor <= 0 ||
    transactional.transaction_provider.trim().is_empty() ||
    activated_by.trim().is_empty() ||
    activated_at_epoch < 0 {
    raise Invalid(
      "transactional pack, product, actor, price, or time is invalid",
    )
  }
  if payment_receipt.trim().is_empty() {
    raise PaymentReceiptRequired
  }
  let profile = self.activate(transactional.pack) catch {
    error => raise Catalog(error)
  }
  (
    profile,
    {
      receipt_id: "pack-activation-\{transactional.pack.extension_id}-\{adoption.workflow_id}",
      principal_id: adoption.principal_id,
      product_id: adoption.product_id,
      workflow_id: adoption.workflow_id,
      extension_id: transactional.pack.extension_id,
      product_in_gate_receipt: adoption.product_in_gate_receipt,
      payment_receipt,
      activated_by,
      activated_at_epoch,
    },
  )
}

///|
pub fn authorize_autonomous_expansion(
  adoption : WorkflowAdoptionEvidence,
  review : AutonomousExpansionReview,
) -> AutonomousExpansionGateReceipt raise ProductAdoptionError {
  validate_adoption(adoption)
  if review.principal_id != adoption.principal_id ||
    review.product_id != adoption.product_id ||
    review.review_id.trim().is_empty() ||
    review.scope.trim().is_empty() ||
    review.risk_evidence.is_empty() ||
    !nonempty_unique(review.risk_evidence) ||
    review.reviewed_at_epoch < adoption.reviewed_at_epoch {
    raise Invalid(
      "autonomous expansion review does not bind the adopted workflow",
    )
  }
  if review.requested_by == review.reviewed_by ||
    review.reviewed_by.trim().is_empty() {
    raise IndependentReviewRequired
  }
  if !review.approved {
    raise ExpansionReviewRejected
  }
  {
    receipt_id: "autonomy-gate-\{review.review_id}",
    feature: review.feature,
    principal_id: review.principal_id,
    product_id: review.product_id,
    workflow_id: adoption.workflow_id,
    review_id: review.review_id,
    enabled: true,
    company_authority_granted: false,
  }
}
