///|
/// Representative legacy project row from `ep_project` and lifecycle metadata.
pub(all) struct LegacyProjectRow {
  proj_guid : String
  bu_guid : String
  proj_code : String
  proj_name : String
} derive(Debug, Eq)

///|
/// Representative `mu_business_unit` row.
pub(all) struct LegacyBusinessUnitRow {
  bu_guid : String
  parent_guid : String?
  bu_code : String
  bu_name : String
  bu_type : String
} derive(Debug, Eq)

///|
/// Representative legacy contract row from `cb_contract`.
pub(all) struct LegacyContractRow {
  contract_guid : String
  bu_guid : String
  proj_guid : String
  provider_guid : String
  ht_amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
/// Representative legacy dynamic-cost row after CBS classification.
pub(all) struct LegacyCostRow {
  currency : String
  direct_minor : Int64
  indirect_minor : Int64
  contingency_minor : Int64
  other_minor : Int64
} derive(Debug, Eq)

///|
/// Representative `srm_provider` row.
pub(all) struct LegacySupplierRow {
  provider_guid : String
  bu_guid : String
  provider_code : String
  provider_name : String
  category_code : String
} derive(Debug, Eq)

///|
/// Representative `tender_plan` row.
pub(all) struct LegacyTenderRow {
  tender_guid : String
  bu_guid : String
  proj_guid : String
  tender_name : String
  category : String
  estimated_amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
/// Representative `cb_contract_milestone` row.
pub(all) struct LegacyMilestoneRow {
  milestone_guid : String
  contract_guid : String
  sequence : Int
  node_name : String
  trigger_type : String
  plan_amount_minor : Int64
  plan_pct_bps : Int64
} derive(Debug, Eq)

///|
/// Representative invoice row normalized for the target.
pub(all) struct LegacyInvoiceRow {
  invoice_guid : String
  bu_guid : String
  customer_guid : String
  source_id : String
  amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
/// Representative expense row plus its primary split.
pub(all) struct LegacyExpenseRow {
  expense_guid : String
  bu_guid : String
  employee_guid : String
  proj_guid : String
  cost_subject : String
  amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
/// Representative `vcb_loan_simple` row.
pub(all) struct LegacyAdvanceRow {
  loan_guid : String
  bu_guid : String
  employee_guid : String
  amount_minor : Int64
  currency : String
} derive(Debug, Eq)

///|
/// Representative repayment/expense-offset row from `cb_loan_offset`.
pub(all) struct LegacyAdvanceOffsetRow {
  offset_guid : String
  loan_guid : String
  amount_minor : Int64
  offset_date : String
  related_expense_guid : String?
  operator_guid : String
} derive(Debug, Eq)

///|
pub(all) suberror ErpImportError {
  MissingIdentifier
  InvalidValue
  DuplicateRecord
  DuplicateSource
  Organization(@organization.OrganizationError)
  Project(@project.ProjectError)
  Plan(@project.PlanError)
  Workflow(@workflow.WorkflowError)
  Model(@model.ModelError)
  Commitment(@commitment.CommitmentError)
  Settlement(@settlement.SettlementError)
  Supplier(@procurement.SupplierError)
  Tender(@procurement.TenderError)
  Milestone(@contract.MilestoneError)
  Invoice(@invoice.InvoiceError)
  Expense(@expense.ExpenseError)
  Advance(@employee_finance.AdvanceError)
  Cost(@cost.CostError)
  Money(@finance.MoneyError)
  Store(@store.StoreError)
  MissingMapping
  Identity(@foundation.IdentityError)
  Evidence(@evidence.EvidenceError)
  Parameter(@foundation.ParameterError)
} derive(Debug, Eq)

///|
pub fn import_business_unit(
  row : LegacyBusinessUnitRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @organization.OrganizationUnit raise ErpImportError {
  if row.bu_guid.trim() == "" ||
    row.bu_code.trim() == "" ||
    row.bu_name.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let kind = match row.bu_type.to_lower() {
    "group" => @organization.OrganizationKind::Group
    "company" => @organization.OrganizationKind::Company
    "department" => @organization.OrganizationKind::Department
    "businessunit" | "business_unit" | "bu" =>
      @organization.OrganizationKind::BusinessUnit
    _ => raise ErpImportError::InvalidValue
  }
  @organization.OrganizationUnit::new(
    unit_id=row.bu_guid,
    principal_id=row.bu_guid,
    authority_scope="organization:\{row.bu_guid}",
    parent_id=row.parent_guid,
    code=row.bu_code,
    name=row.bu_name,
    kind~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Organization(error)
  }
}

///|
pub fn import_project(
  row : LegacyProjectRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @project.Project raise ErpImportError {
  if row.proj_guid.trim() == "" || row.bu_guid.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  @project.Project::new(
    project_id=row.proj_guid,
    principal_id=row.bu_guid,
    code=row.proj_code,
    name=row.proj_name,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Project(error)
  }
}

///|
pub fn import_contract(
  row : LegacyContractRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @commitment.Commitment raise ErpImportError {
  if row.contract_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.proj_guid.trim() == "" ||
    row.provider_guid.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let amount = @finance.Money::new(
    minor=row.ht_amount_minor,
    currency=row.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  @commitment.Commitment::new(
    commitment_id=row.contract_guid,
    principal_id=row.bu_guid,
    project_scope="project:\{row.proj_guid}",
    counterparty_id=row.provider_guid,
    amount~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Commitment(error)
  }
}

///|
pub fn import_cost(
  row : LegacyCostRow,
) -> @cost.DynamicCost raise ErpImportError {
  let breakdown = @cost.CostBreakdown::new(
    direct_minor=row.direct_minor,
    indirect_minor=row.indirect_minor,
    contingency_minor=row.contingency_minor,
    other_minor=row.other_minor,
  ) catch {
    error => raise ErpImportError::Cost(error)
  }
  @cost.calculate_dynamic_cost(currency=row.currency, breakdown) catch {
    error => raise ErpImportError::Cost(error)
  }
}

///|
pub fn import_supplier(
  row : LegacySupplierRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @procurement.Supplier raise ErpImportError {
  if row.provider_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.provider_code.trim() == "" ||
    row.provider_name.trim() == "" ||
    row.category_code.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  @procurement.Supplier::new(
    supplier_id=row.provider_guid,
    principal_id=row.bu_guid,
    scope="company:\{row.bu_guid}",
    supplier_code=row.provider_code,
    name=row.provider_name,
    category_code=row.category_code,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Supplier(error)
  }
}

///|
pub fn import_tender(
  row : LegacyTenderRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @procurement.TenderPlan raise ErpImportError {
  if row.tender_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.proj_guid.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let amount = @finance.Money::new(
    minor=row.estimated_amount_minor,
    currency=row.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  @procurement.TenderPlan::new(
    tender_id=row.tender_guid,
    principal_id=row.bu_guid,
    project_scope="project:\{row.proj_guid}",
    name=row.tender_name,
    category=row.category,
    estimated_amount=amount,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Tender(error)
  }
}

///|
pub fn import_milestone(
  row : LegacyMilestoneRow,
  commitment : @commitment.Commitment,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @contract.ContractMilestone raise ErpImportError {
  if row.milestone_guid.trim() == "" ||
    row.contract_guid.trim() == "" ||
    row.node_name.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  if row.contract_guid != commitment.commitment_id {
    raise ErpImportError::InvalidValue
  }
  let trigger = match row.trigger_type.to_lower() {
    "time" | "date" => @contract.MilestoneTrigger::Time
    "progress" => @contract.MilestoneTrigger::Progress
    "event" => @contract.MilestoneTrigger::Event
    _ => raise ErpImportError::InvalidValue
  }
  let amount = @finance.Money::new(
    minor=row.plan_amount_minor,
    currency=commitment.amount.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  @contract.ContractMilestone::new(
    commitment,
    milestone_id=row.milestone_guid,
    sequence=row.sequence,
    node_name=row.node_name,
    trigger~,
    plan_amount=amount,
    plan_pct_bps=row.plan_pct_bps,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Milestone(error)
  }
}

///|
pub fn import_invoice(
  row : LegacyInvoiceRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @invoice.Invoice raise ErpImportError {
  if row.invoice_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.customer_guid.trim() == "" ||
    row.source_id.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let amount = @finance.Money::new(
    minor=row.amount_minor,
    currency=row.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  @invoice.Invoice::new(
    invoice_id=row.invoice_guid,
    principal_id=row.bu_guid,
    customer_id=row.customer_guid,
    source_id=row.source_id,
    amount~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Invoice(error)
  }
}

///|
pub fn import_expense(
  row : LegacyExpenseRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @expense.ExpenseClaim raise ErpImportError {
  if row.expense_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.employee_guid.trim() == "" ||
    row.proj_guid.trim() == "" ||
    row.cost_subject.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let amount = @finance.Money::new(
    minor=row.amount_minor,
    currency=row.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  let allocations : Array[@expense.ExpenseAllocation] = [
    {
      project_scope: "project:\{row.proj_guid}",
      cost_subject: row.cost_subject,
      amount,
    },
  ]
  @expense.ExpenseClaim::new(
    expense_id=row.expense_guid,
    principal_id=row.bu_guid,
    employee_id=row.employee_guid,
    amount~,
    allocations~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Expense(error)
  }
}

///|
pub fn import_advance(
  row : LegacyAdvanceRow,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @employee_finance.EmployeeAdvance raise ErpImportError {
  if row.loan_guid.trim() == "" ||
    row.bu_guid.trim() == "" ||
    row.employee_guid.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  let amount = @finance.Money::new(
    minor=row.amount_minor,
    currency=row.currency,
  ) catch {
    error => raise ErpImportError::Money(error)
  }
  @employee_finance.EmployeeAdvance::new(
    advance_id=row.loan_guid,
    principal_id=row.bu_guid,
    employee_id=row.employee_guid,
    amount~,
    actor_id~,
    grant~,
  ) catch {
    error => raise ErpImportError::Advance(error)
  }
}
