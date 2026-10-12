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
fn ProfessionalServiceShadow::work_index(
  self : ProfessionalServiceShadow,
  work_id : String,
) -> Int? {
  for index, item in self.work {
    if item.work_id == work_id {
      return Some(index)
    }
  }
  None
}

///|
fn ProfessionalServiceShadow::assert_shadow_only(
  self : ProfessionalServiceShadow,
) -> Unit raise ProfessionalServiceError {
  if self.external_delivery_sent ||
    self.contract_signed ||
    self.accounting_posted ||
    self.payment_collected {
    raise Invalid("shadow engagement recorded a forbidden company effect")
  }
}

///|
pub fn ProfessionalServiceShadow::new(
  engagement_id~ : String,
  principal_id~ : String,
  customer_id~ : String,
  owner_id~ : String,
  title~ : String,
  currency~ : String,
  proposed_fee_minor~ : Int64,
  source_evidence~ : Array[String],
) -> ProfessionalServiceShadow raise ProfessionalServiceError {
  if engagement_id.trim().is_empty() ||
    principal_id.trim().is_empty() ||
    customer_id.trim().is_empty() ||
    owner_id.trim().is_empty() ||
    title.trim().is_empty() ||
    currency.length() != 3 ||
    proposed_fee_minor < 0 ||
    source_evidence.is_empty() ||
    !nonempty_unique(source_evidence) {
    raise Invalid(
      "complete engagement identity, fee, and evidence are required",
    )
  }
  {
    engagement_id,
    principal_id,
    customer_id,
    owner_id,
    title,
    currency,
    proposed_fee_minor,
    source_evidence,
    stage: Draft,
    revision: 0,
    work: [],
    activities: [],
    accepted_evidence: [],
    invoice_proposal: None,
    external_delivery_sent: false,
    contract_signed: false,
    accounting_posted: false,
    payment_collected: false,
  }
}

///|
pub fn ProfessionalServiceShadow::add_work(
  self : ProfessionalServiceShadow,
  work_id~ : String,
  title~ : String,
  role~ : ServiceRole,
  assigned_actor_id~ : String,
  dependencies~ : Array[String],
  acceptance_criteria~ : Array[String],
  expected_result_schema~ : String,
) -> ProfessionalServiceShadow raise ProfessionalServiceError {
  if self.stage != Draft {
    raise InvalidStage(self.stage)
  }
  if self.work_index(work_id) is Some(_) {
    raise DuplicateWork(work_id)
  }
  if work_id.trim().is_empty() ||
    title.trim().is_empty() ||
    assigned_actor_id.trim().is_empty() ||
    dependencies.contains(work_id) ||
    !nonempty_unique(dependencies) ||
    acceptance_criteria.is_empty() ||
    !nonempty_unique(acceptance_criteria) ||
    expected_result_schema.trim().is_empty() {
    raise Invalid(
      "work identity, dependencies, acceptance, and schema are invalid",
    )
  }
  let work = self.work.copy()
  work.push({
    work_id,
    title,
    role,
    assigned_actor_id,
    dependencies,
    acceptance_criteria,
    expected_result_schema,
    state: Planned,
    request_id: "",
    attempt_id: "",
    output_evidence: [],
    findings: "",
  })
  { ..self, revision: self.revision + 1, work }
}

///|
fn ProfessionalServiceShadow::validate_graph(
  self : ProfessionalServiceShadow,
) -> Unit raise ProfessionalServiceError {
  let resolved : Array[String] = []
  for _ in 0..<self.work.length() {
    let mut progressed = false
    for item in self.work {
      if !resolved.contains(item.work_id) &&
        item.dependencies
        .iter()
        .all(dependency => resolved.contains(dependency)) {
        resolved.push(item.work_id)
        progressed = true
      }
    }
    if !progressed {
      break
    }
  }
  if resolved.length() != self.work.length() {
    for item in self.work {
      for dependency in item.dependencies {
        if self.work_index(dependency) is None {
          raise UnknownDependency(dependency)
        }
      }
    }
    raise DependencyCycle
  }
}

///|
pub fn ProfessionalServiceShadow::release(
  self : ProfessionalServiceShadow,
) -> ProfessionalServiceShadow raise ProfessionalServiceError {
  if self.stage != Draft || self.work.is_empty() {
    raise InvalidStage(self.stage)
  }
  self.validate_graph()
  for required in [EngagementLead, Producer, IndependentReviewer] {
    if !self.work.iter().any(item => item.role == required) {
      raise MissingRole(required)
    }
  }
  for item in self.work {
    if item.role == IndependentReviewer &&
      item.assigned_actor_id == self.owner_id {
      raise ReviewIndependenceRequired
    }
  }
  let work = self.work.map(item => { ..item, state: Released })
  let released = { ..self, stage: Ready, revision: self.revision + 1, work }
  released.assert_shadow_only()
  released
}

///|
fn append_unique(into : Array[String], values : Array[String]) -> Array[String] {
  let result = into.copy()
  for value in values {
    if !result.contains(value) {
      result.push(value)
    }
  }
  result
}

///|
pub fn ProfessionalServiceShadow::request_work(
  self : ProfessionalServiceShadow,
  work_id~ : String,
  request_id~ : String,
  attempt_id~ : String,
  input_digest~ : String,
) -> (@agent_port.AgentRequest, ProfessionalServiceShadow) raise {
  if !(self.stage is (Ready | InExecution | WaitingForReview)) {
    raise InvalidStage(self.stage)
  }
  guard self.work_index(work_id) is Some(index) else {
    raise Invalid("unknown work contract")
  }
  let item = self.work[index]
  if item.state is Complete {
    raise Invalid("completed work cannot be dispatched again")
  }
  let mut evidence = self.source_evidence.copy()
  for dependency in item.dependencies {
    guard self.work_index(dependency) is Some(dependency_index) else {
      raise UnknownDependency(dependency)
    }
    let predecessor = self.work[dependency_index]
    if predecessor.state != Complete {
      raise DependencyIncomplete(dependency)
    }
    evidence = append_unique(evidence, predecessor.output_evidence)
  }
  let request : @agent_port.AgentRequest = {
    protocol_version: @agent_port.protocol_version(),
    request_id,
    work_item_id: item.work_id,
    flow_run_id: self.engagement_id,
    principal_id: self.principal_id,
    actor_id: item.assigned_actor_id,
    capability: "professional-services.shadow.execute",
    scope: "engagement:\{self.engagement_id}/work:\{item.work_id}",
    coordination_mode: CompanyTopDown,
    authority_ceiling_minor: 0,
    input_evidence: evidence,
    input_digest,
    acceptance_criteria: item.acceptance_criteria,
    expected_result_schema: item.expected_result_schema,
    prohibited_effects: @agent_port.reserved_company_effects(),
    idempotency_key: "\{self.engagement_id}/\{item.work_id}/\{attempt_id}",
  }
  request.validate()
  let work = self.work.copy()
  work[index] = { ..item, request_id, attempt_id }
  let stage = if item.role is IndependentReviewer {
    WaitingForReview
  } else {
    InExecution
  }
  (request, { ..self, stage, revision: self.revision + 1, work })
}

///|
pub fn ProfessionalServiceShadow::record_result(
  self : ProfessionalServiceShadow,
  result : @agent_port.AgentResult,
  activity_id~ : String,
  at_epoch~ : Int64,
) -> ProfessionalServiceShadow raise ProfessionalServiceError {
  self.assert_shadow_only()
  if !result.is_well_formed() ||
    result.status != "succeeded" ||
    !result.proposed_commands.is_empty() {
    raise Invalid("shadow workflow records only well-formed successful results")
  }
  let mut match_index : Int? = None
  for index, item in self.work {
    if item.request_id == result.request_id &&
      item.attempt_id == result.attempt_id {
      match_index = Some(index)
    }
  }
  guard match_index is Some(index) else { raise ResultMismatch }
  let item = self.work[index]
  let work = self.work.copy()
  work[index] = {
    ..item,
    state: Complete,
    output_evidence: result.evidence,
    findings: result.findings,
  }
  let activities = self.activities.copy()
  activities.push({
    activity_id,
    work_id: item.work_id,
    actor_id: item.assigned_actor_id,
    kind: "agent-result-recorded",
    evidence: result.evidence,
    at_epoch,
  })
  let non_review_complete = work
    .iter()
    .all(candidate => {
      candidate.role == IndependentReviewer || candidate.state == Complete
    })
  let reviewer_complete = work
    .iter()
    .any(candidate => {
      candidate.role == IndependentReviewer && candidate.state == Complete
    })
  let stage = if reviewer_complete {
    WaitingForReview
  } else if non_review_complete {
    WaitingForReview
  } else {
    InExecution
  }
  { ..self, stage, revision: self.revision + 1, work, activities }
}

///|
pub fn ProfessionalServiceShadow::accept_shadow_delivery(
  self : ProfessionalServiceShadow,
  reviewer_id~ : String,
  acceptance_evidence~ : Array[String],
  proposal_id~ : String,
) -> ProfessionalServiceShadow raise ProfessionalServiceError {
  self.assert_shadow_only()
  if self.stage != WaitingForReview ||
    reviewer_id.trim().is_empty() ||
    reviewer_id == self.owner_id ||
    acceptance_evidence.is_empty() ||
    !nonempty_unique(acceptance_evidence) ||
    !self.work
    .iter()
    .any(item => {
      item.role == IndependentReviewer &&
      item.assigned_actor_id == reviewer_id &&
      item.state == Complete
    }) ||
    !self.work.iter().all(item => item.state == Complete) {
    raise Invalid(
      "independent acceptance requires all work and review evidence",
    )
  }
  let all_evidence = append_unique(self.source_evidence, acceptance_evidence)
  let proposal : @agent_port.ProposedCommand = {
    protocol_version: @agent_port.protocol_version(),
    command_id: proposal_id,
    request_id: "shadow-acceptance-\{self.engagement_id}",
    attempt_id: "shadow-review-\{self.revision}",
    principal_id: self.principal_id,
    proposed_by: reviewer_id,
    capability: "receivables.invoice.draft",
    scope: "customer:\{self.customer_id}/engagement:\{self.engagement_id}",
    amount_minor: self.proposed_fee_minor,
    payload_schema: "moonproj.invoice-draft-proposal.v1",
    payload: "engagement=\{self.engagement_id};currency=\{self.currency}",
    evidence: all_evidence,
    idempotency_key: "shadow-invoice/\{self.engagement_id}",
    state: ProposalOnly,
    runtime_permission_observed: true,
    company_authority_granted: false,
  }
  if !proposal.is_well_formed() {
    raise Invalid("invoice proposal is not well formed")
  }
  {
    ..self,
    stage: ShadowAccepted,
    revision: self.revision + 1,
    accepted_evidence: acceptance_evidence,
    invoice_proposal: Some(proposal),
  }
}
