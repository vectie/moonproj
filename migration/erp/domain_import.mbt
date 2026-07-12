///|
/// Import task structure into a target-owned project plan. Source status and
/// historical progress remain in the typed envelope; replaying those effects
/// requires separate authority grants and is intentionally not inferred here.
pub fn import_project_tasks(
  project : @project.Project,
  rows : Array[LegacyTaskRow],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @project.ProjectPlan raise ErpImportError {
  let mut plan = @project.ProjectPlan::new(project)
  for row in rows {
    if row.proj_guid != project.project_id {
      raise ErpImportError::InvalidValue
    }
    let dependencies : Array[String] = match row.parent_task_guid {
      Some(parent) => [parent]
      None => []
    }
    plan = plan.add_task(
      task_id=row.task_guid,
      name=row.task_name,
      planned_cost=None,
      dependencies~,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Plan(error)
    }
  }
  plan
}

///|
/// Explicit ownership and authority mapping for a legacy business unit. The
/// source row's BU identifier is not assumed to be a legal principal.
pub(all) struct LegacyBusinessUnitMapping {
  bu_guid : String
  principal_id : String
  authority_scope : String
} derive(Debug, Eq)

///|
fn business_unit_kind(
  value : String,
) -> @organization.OrganizationKind raise ErpImportError {
  match value.to_lower() {
    "group" => @organization.OrganizationKind::Group
    "company" => @organization.OrganizationKind::Company
    "department" | "dept" => @organization.OrganizationKind::Department
    "businessunit" | "business_unit" | "bu" =>
      @organization.OrganizationKind::BusinessUnit
    _ => raise ErpImportError::InvalidValue
  }
}

///|
fn business_unit_mapping_for(
  mappings : Array[LegacyBusinessUnitMapping],
  bu_guid : String,
) -> LegacyBusinessUnitMapping? {
  for mapping in mappings {
    if mapping.bu_guid == bu_guid {
      return Some(mapping)
    }
  }
  None
}

///|
fn organization_grant_for(
  grants : Array[@foundation.AuthorityGrant],
  principal_id : String,
  actor_id : String,
  authority_scope : String,
) -> @foundation.AuthorityGrant? {
  for grant in grants {
    if grant.principal_id == principal_id &&
      grant.actor_id == actor_id &&
      grant.capability == "organization:create" &&
      grant.scope == authority_scope {
      return Some(grant)
    }
  }
  None
}

///|
/// Import a business-unit hierarchy only when principal ownership, authority
/// scope, and per-unit creation grants are explicitly supplied. Parent order
/// is validated by the target registry; a child before its parent fails closed.
pub fn import_business_units(
  rows : Array[LegacyBusinessUnitRow],
  mappings : Array[LegacyBusinessUnitMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> @organization.OrganizationRegistry raise ErpImportError {
  let mut registry = @organization.OrganizationRegistry::empty()
  for row in rows {
    let mapping = match business_unit_mapping_for(mappings, row.bu_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" || mapping.authority_scope.trim() == "" {
      raise ErpImportError::MissingMapping
    }
    let grant = match
      organization_grant_for(
        grants,
        mapping.principal_id,
        actor_id,
        mapping.authority_scope,
      ) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let kind = business_unit_kind(row.bu_type)
    let unit = @organization.OrganizationUnit::new(
      unit_id=row.bu_guid,
      principal_id=mapping.principal_id,
      authority_scope=mapping.authority_scope,
      parent_id=row.parent_guid,
      code=row.bu_code,
      name=row.bu_name,
      kind~,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Organization(error)
    }
    registry = registry.append(unit) catch {
      error => raise ErpImportError::Organization(error)
    }
  }
  registry
}

///|
/// Explicit legal-principal and organization-scope mapping for a credential-
/// free ERP user. Passwords, network addresses, and legacy super-user flags
/// remain source evidence; they never become target authority implicitly.
pub(all) struct LegacyUserMapping {
  user_id : String
  principal_id : String
  authority_scope : String
} derive(Debug, Eq)

///|
fn user_mapping_for(
  mappings : Array[LegacyUserMapping],
  user_id : String,
) -> LegacyUserMapping? {
  for mapping in mappings {
    if mapping.user_id == user_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Promote the safe identity portion of a user cohort. A source `super_user`
/// bit is retained in the legacy envelope and cannot grant target privileges.
pub fn import_users(
  rows : Array[LegacyUserRow],
  mappings : Array[LegacyUserMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> @foundation.UserDirectory raise ErpImportError {
  let mut directory = @foundation.UserDirectory::empty()
  for row in rows {
    let bu_guid = match row.bu_guid {
      Some(value) if value.trim() != "" => value
      _ => raise ErpImportError::MissingMapping
    }
    let mapping = match user_mapping_for(mappings, row.user_id) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.authority_scope != "organization:" + bu_guid {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "identity:user:create" &&
        grant.scope == mapping.authority_scope {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let display_name = match row.emp_name {
      Some(value) if value.trim() != "" => value
      _ => row.user_name
    }
    let user = @foundation.UserAccount::new(
      user_id=row.user_id,
      user_code=row.user_code,
      display_name~,
      principal_id=mapping.principal_id,
      business_unit_id=bu_guid,
      department_id=row.dept_guid,
      enabled=row.enabled,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Identity(error)
    }
    directory = directory.append(user) catch {
      error => raise ErpImportError::Identity(error)
    }
  }
  directory
}

///|
/// Explicit target interpretation for a legacy audit row. Login rows in the
/// ERP often have no target; the target identity and outcome must be named by
/// migration policy rather than manufactured by the importer.
pub(all) struct LegacyAuditMapping {
  audit_id : String
  principal_id : String
  scope : String
  target_type : String
  target_id : String
  outcome : String
} derive(Debug, Eq)

///|
fn audit_mapping_for(
  mappings : Array[LegacyAuditMapping],
  audit_id : String,
) -> LegacyAuditMapping? {
  for mapping in mappings {
    if mapping.audit_id == audit_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Promote audit events only when the source actor, target interpretation, and
/// append authority are explicit. Redacted network fields never enter the
/// company audit record.
pub fn import_audit_records(
  rows : Array[LegacyAuditRow],
  mappings : Array[LegacyAuditMapping],
  grants : Array[@foundation.AuthorityGrant],
) -> @evidence.AuditTrail raise ErpImportError {
  let mut trail = @evidence.AuditTrail::empty()
  for row in rows {
    let actor_id = match row.user_id {
      Some(value) if value.trim() != "" => value
      _ => raise ErpImportError::MissingMapping
    }
    let mapping = match audit_mapping_for(mappings, row.log_id) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.scope.trim() == "" ||
      mapping.target_type.trim() == "" ||
      mapping.target_id.trim() == "" ||
      mapping.outcome.trim() == "" {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "audit:append" &&
        grant.scope == mapping.scope {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let record : @evidence.AuditRecord = {
      audit_id: row.log_id,
      principal_id: mapping.principal_id,
      actor_id,
      scope: mapping.scope,
      action: row.action,
      target_type: mapping.target_type,
      target_id: mapping.target_id,
      outcome: mapping.outcome,
      evidence_id: None,
    }
    trail = trail.append(record, grant~) catch {
      error => raise ErpImportError::Evidence(error)
    }
  }
  trail
}

///|
/// Explicit ownership/scope mapping for one parameter dictionary. Parameter
/// values remain opaque configuration; this importer does not classify them as
/// accounts, cost subjects, tax codes, or authority.
pub(all) struct LegacyParameterMapping {
  parameter_name : String
  principal_id : String
  scope : String
} derive(Debug, Eq)

///|
fn parameter_mapping_for(
  mappings : Array[LegacyParameterMapping],
  parameter_name : String,
) -> LegacyParameterMapping? {
  for mapping in mappings {
    if mapping.parameter_name == parameter_name {
      return Some(mapping)
    }
  }
  None
}

///|
pub fn import_parameter_dictionaries(
  rows : Array[Array[LegacyParameterRow]],
  mappings : Array[LegacyParameterMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> Array[@foundation.ParameterDictionary] raise ErpImportError {
  let dictionaries : Array[@foundation.ParameterDictionary] = []
  let seen_names : Array[String] = []
  for group in rows {
    if group.length() == 0 {
      raise ErpImportError::InvalidValue
    }
    let parameter_name = group[0].parameter_name
    for existing in seen_names {
      if existing == parameter_name {
        raise ErpImportError::DuplicateRecord
      }
    }
    seen_names.push(parameter_name)
    let mapping = match parameter_mapping_for(mappings, parameter_name) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" || mapping.scope.trim() == "" {
      raise ErpImportError::MissingMapping
    }
    let mut create_grant : @foundation.AuthorityGrant? = None
    let mut edit_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.scope == mapping.scope {
        if grant.capability == "parameter:create" {
          create_grant = Some(grant)
        }
        if grant.capability == "parameter:edit" {
          edit_grant = Some(grant)
        }
      }
    }
    let create = match create_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let edit = match edit_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let mut dictionary = @foundation.ParameterDictionary::new(
      parameter_name~,
      principal_id=mapping.principal_id,
      scope=mapping.scope,
      actor_id~,
      grant=create,
    ) catch {
      error => raise ErpImportError::Parameter(error)
    }
    for row in group {
      let option : @foundation.ParameterOption = {
        parameter_id: row.parameter_id,
        code: row.parameter_code,
        value: row.parameter_value,
        display_order: row.display_order,
        enabled: row.enabled,
      }
      dictionary = dictionary.add_option(option, actor_id~, grant=edit) catch {
        error => raise ErpImportError::Parameter(error)
      }
    }
    dictionaries.push(dictionary)
  }
  dictionaries
}

///|
/// Explicit ownership mapping for a project. A legacy BU identifier is a
/// relationship, not automatically the legal principal that owns the target
/// project.
pub(all) struct LegacyProjectMapping {
  project_id : String
  principal_id : String
  authority_scope : String
} derive(Debug, Eq)

///|
fn project_mapping_for(
  mappings : Array[LegacyProjectMapping],
  project_id : String,
) -> LegacyProjectMapping? {
  for mapping in mappings {
    if mapping.project_id == project_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Promote a project-master cohort under explicit principal and project-scope
/// mappings. No source BU is silently treated as a legal entity.
pub fn import_projects(
  rows : Array[LegacyProjectRow],
  mappings : Array[LegacyProjectMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> Array[@project.Project] raise ErpImportError {
  let projects : Array[@project.Project] = []
  let seen : Array[String] = []
  for row in rows {
    for existing in seen {
      if existing == row.proj_guid {
        raise ErpImportError::InvalidValue
      }
    }
    seen.push(row.proj_guid)
    let mapping = match project_mapping_for(mappings, row.proj_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.authority_scope != "project:" + row.proj_guid {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "project:create" &&
        grant.scope == mapping.authority_scope {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let project = @project.Project::new(
      project_id=row.proj_guid,
      principal_id=mapping.principal_id,
      code=row.proj_code,
      name=row.proj_name,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Project(error)
    }
    projects.push(project)
  }
  projects
}

///|
/// Explicit target identity mapping for a legacy contract. In particular, the
/// source provider name/GUID is not accepted as a counterparty identity until
/// the migration map names the target counterparty.
pub(all) struct LegacyContractMapping {
  contract_id : String
  principal_id : String
  project_scope : String
  counterparty_id : String
} derive(Debug, Eq)

///|
fn contract_mapping_for(
  mappings : Array[LegacyContractMapping],
  contract_id : String,
) -> LegacyContractMapping? {
  for mapping in mappings {
    if mapping.contract_id == contract_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Promote contract rows into target commitments only with explicit
/// principal, project-scope, counterparty, and amount-bounded grants.
pub fn import_contracts(
  rows : Array[LegacyContractRow],
  mappings : Array[LegacyContractMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> Array[@commitment.Commitment] raise ErpImportError {
  let commitments : Array[@commitment.Commitment] = []
  let seen : Array[String] = []
  for row in rows {
    for existing in seen {
      if existing == row.contract_guid {
        raise ErpImportError::InvalidValue
      }
    }
    seen.push(row.contract_guid)
    let mapping = match contract_mapping_for(mappings, row.contract_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.counterparty_id.trim() == "" ||
      mapping.project_scope != "project:" + row.proj_guid {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "commitment:create" &&
        grant.scope == mapping.project_scope &&
        grant.max_amount_minor >= row.ht_amount_minor {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let amount = @finance.Money::new(
      minor=row.ht_amount_minor,
      currency=row.currency,
    ) catch {
      error => raise ErpImportError::Money(error)
    }
    let commitment = @commitment.Commitment::new(
      commitment_id=row.contract_guid,
      principal_id=mapping.principal_id,
      project_scope=mapping.project_scope,
      counterparty_id=mapping.counterparty_id,
      amount~,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Commitment(error)
    }
    commitments.push(commitment)
  }
  commitments
}

///|
fn commitment_state_rank(state : @commitment.CommitmentState) -> Int {
  match state {
    @commitment.CommitmentState::Draft => 0
    @commitment.CommitmentState::Submitted => 1
    @commitment.CommitmentState::Approved => 2
    @commitment.CommitmentState::Performed => 3
    @commitment.CommitmentState::Settled => 4
    @commitment.CommitmentState::Cancelled => 5
  }
}

///|
fn commitment_next_state(
  state : @commitment.CommitmentState,
) -> @commitment.CommitmentState? {
  match state {
    @commitment.CommitmentState::Draft =>
      Some(@commitment.CommitmentState::Submitted)
    @commitment.CommitmentState::Submitted =>
      Some(@commitment.CommitmentState::Approved)
    @commitment.CommitmentState::Approved =>
      Some(@commitment.CommitmentState::Performed)
    @commitment.CommitmentState::Performed =>
      Some(@commitment.CommitmentState::Settled)
    @commitment.CommitmentState::Settled
    | @commitment.CommitmentState::Cancelled => None
  }
}

///|
fn commitment_capability(state : @commitment.CommitmentState) -> String {
  match state {
    @commitment.CommitmentState::Submitted => "commitment:submit"
    @commitment.CommitmentState::Approved => "commitment:approve"
    @commitment.CommitmentState::Performed => "commitment:perform"
    @commitment.CommitmentState::Settled => "commitment:settle"
    @commitment.CommitmentState::Cancelled => "commitment:cancel"
    @commitment.CommitmentState::Draft => "commitment:create"
  }
}

///|
fn commitment_grant_for(
  grants : Array[@foundation.AuthorityGrant],
  commitment : @commitment.Commitment,
  state : @commitment.CommitmentState,
  actor_id : String,
) -> @foundation.AuthorityGrant? {
  let capability = commitment_capability(state)
  for grant in grants {
    if grant.principal_id == commitment.principal_id &&
      grant.actor_id == actor_id &&
      grant.capability == capability &&
      grant.scope == commitment.project_scope &&
      grant.max_amount_minor >= commitment.amount.minor {
      return Some(grant)
    }
  }
  None
}

///|
fn transition_commitment_to(
  commitment : @commitment.Commitment,
  target_state : @commitment.CommitmentState,
  grants : Array[@foundation.AuthorityGrant],
  actor_id : String,
) -> @commitment.Commitment raise ErpImportError {
  if commitment.state == target_state {
    return commitment
  }
  let next = if target_state == @commitment.CommitmentState::Cancelled {
    @commitment.CommitmentState::Cancelled
  } else {
    match commitment_next_state(commitment.state) {
      Some(value) => value
      None => raise ErpImportError::InvalidValue
    }
  }
  if target_state != @commitment.CommitmentState::Cancelled &&
    commitment_state_rank(next) > commitment_state_rank(target_state) {
    raise ErpImportError::InvalidValue
  }
  let grant = match commitment_grant_for(grants, commitment, next, actor_id) {
    Some(value) => value
    None => raise ErpImportError::MissingMapping
  }
  let transitioned = commitment.transition(next, actor_id~, grant~) catch {
    error => raise ErpImportError::Commitment(error)
  }
  transition_commitment_to(transitioned, target_state, grants, actor_id)
}

///|
/// Replay an explicitly mapped legacy commitment state through every local
/// transition and grant. Source labels are never guessed, and a payment
/// application must use the resulting performed commitment before settlement
/// can be requested.
pub fn import_commitment_state(
  commitment : @commitment.Commitment,
  target_state : @commitment.CommitmentState,
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> @commitment.Commitment raise ErpImportError {
  transition_commitment_to(commitment, target_state, grants, actor_id)
}

///|
/// Explicit ownership mapping for an employee advance. The source BU remains
/// an organizational relationship; the target principal and employee scope
/// must be named independently.
pub(all) struct LegacyAdvanceMapping {
  advance_id : String
  principal_id : String
  employee_id : String
  authority_scope : String
} derive(Debug, Eq)

///|
fn advance_mapping_for(
  mappings : Array[LegacyAdvanceMapping],
  advance_id : String,
) -> LegacyAdvanceMapping? {
  for mapping in mappings {
    if mapping.advance_id == advance_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Promote employee-loan rows only with explicit employee identity, principal,
/// scope, currency, and amount-bounded creation grants.
pub fn import_advances(
  rows : Array[LegacyAdvanceRow],
  mappings : Array[LegacyAdvanceMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> Array[@employee_finance.EmployeeAdvance] raise ErpImportError {
  let advances : Array[@employee_finance.EmployeeAdvance] = []
  let seen : Array[String] = []
  for row in rows {
    for existing in seen {
      if existing == row.loan_guid {
        raise ErpImportError::InvalidValue
      }
    }
    seen.push(row.loan_guid)
    let mapping = match advance_mapping_for(mappings, row.loan_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.employee_id.trim() == "" ||
      mapping.authority_scope != "employee:" + mapping.employee_id {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "advance:create" &&
        grant.scope == mapping.authority_scope {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let amount = @finance.Money::new(
      minor=row.amount_minor,
      currency=row.currency,
    ) catch {
      error => raise ErpImportError::Money(error)
    }
    let advance = @employee_finance.EmployeeAdvance::new(
      advance_id=row.loan_guid,
      principal_id=mapping.principal_id,
      employee_id=mapping.employee_id,
      amount~,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Advance(error)
    }
    advances.push(advance)
  }
  advances
}

///|
/// Explicit mapping for an advance repayment or expense offset. The source
/// amount is applied only to an already imported target advance; it cannot
/// create a repayment against an unknown loan or exceed its outstanding
/// balance.
pub(all) struct LegacyAdvanceOffsetMapping {
  offset_id : String
  principal_id : String
  employee_id : String
  authority_scope : String
} derive(Debug, Eq)

///|
fn advance_offset_mapping_for(
  mappings : Array[LegacyAdvanceOffsetMapping],
  offset_id : String,
) -> LegacyAdvanceOffsetMapping? {
  for mapping in mappings {
    if mapping.offset_id == offset_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Replay explicit loan-offset rows against imported advances. The returned
/// array is the updated advance state; source dates, operators, and expense
/// references remain migration evidence until a separate accounting event is
/// reviewed.
pub fn import_advance_offsets(
  advances : Array[@employee_finance.EmployeeAdvance],
  rows : Array[LegacyAdvanceOffsetRow],
  mappings : Array[LegacyAdvanceOffsetMapping],
  grants : Array[@foundation.AuthorityGrant],
  actor_id~ : String,
) -> Array[@employee_finance.EmployeeAdvance] raise ErpImportError {
  let updated = advances.copy()
  let seen : Array[String] = []
  for row in rows {
    if row.offset_guid.trim() == "" ||
      row.loan_guid.trim() == "" ||
      row.offset_date.trim() == "" ||
      row.operator_guid.trim() == "" {
      raise ErpImportError::MissingIdentifier
    }
    for existing in seen {
      if existing == row.offset_guid {
        raise ErpImportError::DuplicateRecord
      }
    }
    seen.push(row.offset_guid)
    let mapping = match advance_offset_mapping_for(mappings, row.offset_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    if mapping.principal_id.trim() == "" ||
      mapping.employee_id.trim() == "" ||
      mapping.authority_scope != "employee:" + mapping.employee_id {
      raise ErpImportError::MissingMapping
    }
    let mut found_index : Int? = None
    for index in 0..<updated.length() {
      if updated[index].advance_id == row.loan_guid {
        found_index = Some(index)
      }
    }
    let index = match found_index {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let advance = updated[index]
    if advance.principal_id != mapping.principal_id ||
      advance.employee_id != mapping.employee_id {
      raise ErpImportError::MissingMapping
    }
    let mut found_grant : @foundation.AuthorityGrant? = None
    for grant in grants {
      if grant.principal_id == mapping.principal_id &&
        grant.actor_id == actor_id &&
        grant.capability == "advance:offset" &&
        grant.scope == mapping.authority_scope &&
        grant.max_amount_minor >= row.amount_minor {
        found_grant = Some(grant)
      }
    }
    let grant = match found_grant {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let offset = advance.offset(
      amount_minor=row.amount_minor,
      actor_id~,
      grant~,
    ) catch {
      error => raise ErpImportError::Advance(error)
    }
    updated[index] = offset
  }
  updated
}

///|
/// A cost value is pure arithmetic, but its source identity and project scope
/// still need to survive promotion. This wrapper prevents seven source cost
/// rows from collapsing into an anonymous total.
pub(all) struct LegacyCostPromotionRow {
  cost_id : String
  project_scope : String
  cost : LegacyCostRow
} derive(Debug, Eq)

///|
pub(all) struct ImportedDynamicCost {
  cost_id : String
  project_scope : String
  value : @cost.DynamicCost
} derive(Debug, Eq)

///|
/// Translate a dynamic-cost cohort while retaining source identity and project
/// scope. Negative components and duplicate cost IDs fail before promotion.
pub fn import_costs(
  rows : Array[LegacyCostPromotionRow],
) -> Array[ImportedDynamicCost] raise ErpImportError {
  let costs : Array[ImportedDynamicCost] = []
  let seen : Array[String] = []
  for row in rows {
    if row.cost_id.trim() == "" || row.project_scope.trim() == "" {
      raise ErpImportError::MissingIdentifier
    }
    for existing in seen {
      if existing == row.cost_id {
        raise ErpImportError::InvalidValue
      }
    }
    seen.push(row.cost_id)
    let value = import_cost(row.cost)
    costs.push({ cost_id: row.cost_id, project_scope: row.project_scope, value })
  }
  costs
}

///|
/// An explicit lifecycle translation. The source ERP has an `acquisition`
/// stage while the local product has `planning`; the mapping must therefore be
/// supplied by migration policy instead of guessed from labels. Historical
/// status/progress remains in the source envelope; only the current ordered
/// target stage is replayed under a fresh authority grant.
pub(all) struct LegacyLifecycleMapping {
  source_code : String
  target_stage : @project.ProjectStage
} derive(Debug, Eq)

///|
fn lifecycle_mapping_for(
  mappings : Array[LegacyLifecycleMapping],
  source_code : String,
) -> @project.ProjectStage? {
  for mapping in mappings {
    if mapping.source_code == source_code {
      return Some(mapping.target_stage)
    }
  }
  None
}

///|
fn lifecycle_stage_rank(stage : @project.ProjectStage) -> Int {
  match stage {
    @project.ProjectStage::Initiation => 0
    @project.ProjectStage::Planning => 1
    @project.ProjectStage::Design => 2
    @project.ProjectStage::Development => 3
    @project.ProjectStage::Sales => 4
    @project.ProjectStage::Delivery => 5
    @project.ProjectStage::Settlement => 6
    @project.ProjectStage::Closed => 7
  }
}

///|
pub fn import_project_lifecycle(
  project : @project.Project,
  rows : Array[LegacyLifecycleInstanceRow],
  mappings : Array[LegacyLifecycleMapping],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @project.Project raise ErpImportError {
  let mut target = project
  let mut last_rank = lifecycle_stage_rank(@project.ProjectStage::Initiation)
  let seen_codes : Array[String] = []
  let mut halted = false
  for row in rows {
    if row.proj_guid != project.project_id {
      raise ErpImportError::InvalidValue
    }
    for existing in seen_codes {
      if existing == row.stage_code {
        raise ErpImportError::InvalidValue
      }
    }
    seen_codes.push(row.stage_code)
    let stage = match lifecycle_mapping_for(mappings, row.stage_code) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let rank = lifecycle_stage_rank(stage)
    if rank < last_rank {
      raise ErpImportError::InvalidValue
    }
    if row.status != "done" &&
      row.status != "in_progress" &&
      row.status != "pending" {
      raise ErpImportError::InvalidValue
    }
    if !halted && row.status != "pending" {
      if rank > last_rank {
        target = target.advance(stage, actor_id~, grant~) catch {
          error => raise ErpImportError::Project(error)
        }
        last_rank = rank
      }
      if row.status == "in_progress" {
        halted = true
      }
    } else if row.status == "pending" {
      halted = true
    }
  }
  target
}

///|
/// Replay current task state only after the task structure has been imported.
/// This is a separate, authority-bearing operation: creating a target plan
/// never silently replays historical starts, completions, or blocks.
pub fn import_project_task_states(
  plan : @project.ProjectPlan,
  rows : Array[LegacyTaskRow],
  actor_id~ : String,
  start_grant~ : @foundation.AuthorityGrant,
  progress_grant~ : @foundation.AuthorityGrant,
  block_grant~ : @foundation.AuthorityGrant,
) -> @project.ProjectPlan raise ErpImportError {
  let mut target = plan
  for row in rows {
    if row.proj_guid != plan.project_id {
      raise ErpImportError::InvalidValue
    }
    match row.status {
      "pending" =>
        if row.progress_bps != 0L {
          raise ErpImportError::InvalidValue
        }
      "in_progress" => {
        if row.progress_bps >= 10000L {
          raise ErpImportError::InvalidValue
        }
        target = target.start_task(
          task_id=row.task_guid,
          actor_id~,
          grant=start_grant,
        ) catch {
          error => raise ErpImportError::Plan(error)
        }
        if row.progress_bps > 0L {
          target = target.report_progress(
            task_id=row.task_guid,
            progress_bps=row.progress_bps,
            actor_id~,
            grant=progress_grant,
          ) catch {
            error => raise ErpImportError::Plan(error)
          }
        }
      }
      "done" => {
        if row.progress_bps != 10000L {
          raise ErpImportError::InvalidValue
        }
        target = target.start_task(
          task_id=row.task_guid,
          actor_id~,
          grant=start_grant,
        ) catch {
          error => raise ErpImportError::Plan(error)
        }
        target = target.report_progress(
          task_id=row.task_guid,
          progress_bps=10000L,
          actor_id~,
          grant=progress_grant,
        ) catch {
          error => raise ErpImportError::Plan(error)
        }
      }
      "blocked" => {
        if row.progress_bps >= 10000L {
          raise ErpImportError::InvalidValue
        }
        target = target.start_task(
          task_id=row.task_guid,
          actor_id~,
          grant=start_grant,
        ) catch {
          error => raise ErpImportError::Plan(error)
        }
        target = target.block_task(
          task_id=row.task_guid,
          actor_id~,
          grant=block_grant,
        ) catch {
          error => raise ErpImportError::Plan(error)
        }
      }
      _ => raise ErpImportError::InvalidValue
    }
  }
  target
}

///|
/// Translate a payment application into a requested settlement only when an
/// already-authorized performed commitment is supplied. Source approval and
/// payment flags are retained as evidence; they never silently release cash.
pub fn import_payment_application(
  row : LegacyPaymentApplicationRow,
  commitment : @commitment.Commitment,
  currency~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @settlement.Settlement raise ErpImportError {
  if row.contract_guid != commitment.commitment_id || row.amount_minor <= 0L {
    raise ErpImportError::InvalidValue
  }
  let amount = @finance.Money::new(minor=row.amount_minor, currency~) catch {
    error => raise ErpImportError::Money(error)
  }
  @settlement.Settlement::request(
    commitment,
    settlement_id=row.apply_guid,
    amount~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Settlement(error)
  }
}

///|
/// Explicit mapping from a legacy workflow step to a local authority
/// capability. The capability is never guessed from a source label.
pub(all) struct LegacyWorkflowCapability {
  step_guid : String
  capability : String
} derive(Debug, Eq)

///|
fn capability_for_step(
  mappings : Array[LegacyWorkflowCapability],
  step_guid : String,
) -> String? {
  for mapping in mappings {
    if mapping.step_guid == step_guid {
      return Some(mapping.capability)
    }
  }
  None
}

///|
/// Translate a legacy workflow definition only when every step has an explicit
/// local capability mapping. Source flags such as `active` and `mandatory`
/// remain in the source envelope until the target policy models them.
pub fn import_workflow_definition(
  row : LegacyWorkflowDefinitionRow,
  steps : Array[LegacyWorkflowStepRow],
  capabilities : Array[LegacyWorkflowCapability],
) -> @workflow.ProcessDefinition raise ErpImportError {
  let target_steps : Array[@workflow.ApprovalStep] = []
  let mut previous_order = 0
  for step in steps {
    if step.process_guid != row.process_guid ||
      step.step_order <= previous_order {
      raise ErpImportError::InvalidValue
    }
    previous_order = step.step_order
    let capability = match capability_for_step(capabilities, step.step_guid) {
      Some(value) if value.trim() != "" => value
      _ => raise ErpImportError::MissingMapping
    }
    target_steps.push({
      step_id: step.step_guid,
      capability,
      required_weight: step.threshold,
    })
  }
  @workflow.ProcessDefinition::new(
    process_id=row.process_guid,
    process_key=row.process_key,
    steps=target_steps,
  ) catch {
    error => raise ErpImportError::Workflow(error)
  }
}

///|
/// Import a workflow-definition cohort. Each definition receives only its own
/// ordered steps, and every step still needs an explicit local capability map.
pub fn import_workflow_definitions(
  rows : Array[LegacyWorkflowDefinitionRow],
  steps : Array[LegacyWorkflowStepRow],
  capabilities : Array[LegacyWorkflowCapability],
) -> Array[@workflow.ProcessDefinition] raise ErpImportError {
  let definitions : Array[@workflow.ProcessDefinition] = []
  let seen : Array[String] = []
  for row in rows {
    for existing in seen {
      if existing == row.process_guid {
        raise ErpImportError::InvalidValue
      }
    }
    seen.push(row.process_guid)
    let process_steps : Array[LegacyWorkflowStepRow] = []
    for step in steps {
      if step.process_guid == row.process_guid {
        process_steps.push(step)
      }
    }
    let definition = import_workflow_definition(
      row, process_steps, capabilities,
    )
    definitions.push(definition)
  }
  definitions
}

///|
/// Translate an ERP investment version and its indexes into the local governed
/// model. The index value remains a source representation; interpreting units
/// and formulas is a later, explicit modeling decision.
pub fn import_investment_model(
  version_row : LegacyInvestmentVersionRow,
  index_rows : Array[LegacyInvestmentIndexRow],
  principal_id~ : String,
  actor_id~ : String,
  version_grant~ : @foundation.AuthorityGrant,
  index_grant~ : @foundation.AuthorityGrant,
) -> @model.InvestmentModel raise ErpImportError {
  let version = @model.ModelVersion::new(
    version_id=version_row.version_guid,
    project_id=version_row.proj_guid,
    principal_id~,
    name=version_row.version_name,
    version_no=version_row.version_no,
    current=version_row.current,
    created_by=version_row.created_by,
    created_at=version_row.created_at,
    remark=version_row.remark,
    actor_id~,
    grant=version_grant,
  ) catch {
    error => raise ErpImportError::Model(error)
  }
  let mut model = @model.InvestmentModel::new(version)
  for row in index_rows {
    if row.version_guid != version_row.version_guid ||
      row.proj_guid != version_row.proj_guid {
      raise ErpImportError::InvalidValue
    }
    let index = @model.ModelIndex::new(
      index_id=row.index_guid,
      version_id=row.version_guid,
      project_id=row.proj_guid,
      dimension=row.dimension,
      full_code=row.full_code,
      name=row.index_name,
      parent_code=row.parent_code,
      unit=row.unit,
      value_repr=row.value_repr,
      remark=row.remark,
      sort_order=row.sort_order,
    ) catch {
      error => raise ErpImportError::Model(error)
    }
    model = model.add_index(index, actor_id~, grant=index_grant) catch {
      error => raise ErpImportError::Model(error)
    }
  }
  model
}

///|
/// Per-version authority and principal mapping for an investment-model cohort.
pub(all) struct LegacyInvestmentModelMapping {
  version_id : String
  principal_id : String
  version_grant : @foundation.AuthorityGrant
  index_grant : @foundation.AuthorityGrant
} derive(Debug, Eq)

///|
fn investment_model_mapping_for(
  mappings : Array[LegacyInvestmentModelMapping],
  version_id : String,
) -> LegacyInvestmentModelMapping? {
  for mapping in mappings {
    if mapping.version_id == version_id {
      return Some(mapping)
    }
  }
  None
}

///|
/// Import all source investment versions while keeping each version's indexes
/// isolated. A stray index or duplicate version is rejected before any model
/// is considered target-owned.
pub fn import_investment_models(
  versions : Array[LegacyInvestmentVersionRow],
  indexes : Array[LegacyInvestmentIndexRow],
  mappings : Array[LegacyInvestmentModelMapping],
  actor_id~ : String,
) -> Array[@model.InvestmentModel] raise ErpImportError {
  let models : Array[@model.InvestmentModel] = []
  let seen_versions : Array[String] = []
  for version in versions {
    for existing in seen_versions {
      if existing == version.version_guid {
        raise ErpImportError::InvalidValue
      }
    }
    seen_versions.push(version.version_guid)
    let mapping = match
      investment_model_mapping_for(mappings, version.version_guid) {
      Some(value) => value
      None => raise ErpImportError::MissingMapping
    }
    let version_indexes : Array[LegacyInvestmentIndexRow] = []
    for index in indexes {
      if index.version_guid == version.version_guid {
        version_indexes.push(index)
      }
    }
    let model = import_investment_model(
      version,
      version_indexes,
      principal_id=mapping.principal_id,
      actor_id~,
      version_grant=mapping.version_grant,
      index_grant=mapping.index_grant,
    )
    models.push(model)
  }
  for index in indexes {
    let mut found = false
    for version in versions {
      if version.version_guid == index.version_guid {
        found = true
      }
    }
    if !found {
      raise ErpImportError::InvalidValue
    }
  }
  models
}
