///|
pub(all) struct ExpenseAllocation {
  project_scope : String
  cost_subject : String
  amount : @finance.Money
} derive(Debug, Eq)

///|
pub(all) enum ExpenseState {
  Draft
  Submitted
  Approved
  Rejected
  Paid
} derive(Debug, Eq)

///|
pub(all) struct ExpenseEvent {
  from : ExpenseState
  to : ExpenseState
  actor_id : String
} derive(Debug, Eq)

///|
pub(all) struct ExpenseClaim {
  expense_id : String
  principal_id : String
  employee_id : String
  amount : @finance.Money
  allocations : Array[ExpenseAllocation]
  offset_minor : Int64
  state : ExpenseState
  events : Array[ExpenseEvent]
} derive(Debug, Eq)

///|
pub(all) suberror ExpenseError {
  EmptyIdentifier
  InvalidIdentifier
  InvalidAllocation
  AllocationCurrencyMismatch
  AllocationTotalMismatch
  InvalidAmount
  InvalidTransition
  InvalidState
  OffsetExceedsExpense
  Advance(@employee_finance.AdvanceError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
  Journal(@finance.LedgerError)
  AccountingEvent(@accounting.AccountingEventError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn ExpenseClaim::new(
  expense_id~ : String,
  principal_id~ : String,
  employee_id~ : String,
  amount~ : @finance.Money,
  allocations~ : Array[ExpenseAllocation],
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ExpenseClaim raise ExpenseError {
  if expense_id.trim() == "" ||
    principal_id.trim() == "" ||
    employee_id.trim() == "" {
    raise ExpenseError::EmptyIdentifier
  }
  if amount.minor <= 0 {
    raise ExpenseError::InvalidAmount
  }
  if allocations.length() == 0 {
    raise ExpenseError::InvalidAllocation
  }
  let mut total : Int64 = 0
  for allocation in allocations {
    if allocation.project_scope.trim() == "" ||
      allocation.cost_subject.trim() == "" ||
      allocation.amount.minor <= 0 {
      raise ExpenseError::InvalidAllocation
    }
    if allocation.amount.currency != amount.currency {
      raise ExpenseError::AllocationCurrencyMismatch
    }
    total += allocation.amount.minor
  }
  if total != amount.minor {
    raise ExpenseError::AllocationTotalMismatch
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="expense:create",
    scope="employee:\{employee_id}",
    amount_minor=amount.minor,
  ) catch {
    error => raise ExpenseError::NotAuthorized(error)
  }
  {
    expense_id,
    principal_id,
    employee_id,
    amount,
    allocations,
    offset_minor: 0,
    state: ExpenseState::Draft,
    events: [],
  }
}

///|
fn allowed_transition(from : ExpenseState, to : ExpenseState) -> Bool {
  (from == ExpenseState::Draft && to == ExpenseState::Submitted) ||
  (from == ExpenseState::Submitted && to == ExpenseState::Approved) ||
  (from == ExpenseState::Submitted && to == ExpenseState::Rejected) ||
  (from == ExpenseState::Approved && to == ExpenseState::Paid)
}

///|
fn capability_for(state : ExpenseState) -> String {
  match state {
    ExpenseState::Submitted => "expense:submit"
    ExpenseState::Approved => "expense:approve"
    ExpenseState::Rejected => "expense:reject"
    ExpenseState::Paid => "expense:pay"
    ExpenseState::Draft => "expense:create"
  }
}

///|
pub fn ExpenseClaim::transition(
  self : ExpenseClaim,
  to : ExpenseState,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ExpenseClaim raise ExpenseError {
  if !allowed_transition(self.state, to) {
    raise ExpenseError::InvalidTransition
  }
  let capability = capability_for(to)
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability~,
    scope="employee:\{self.employee_id}",
    amount_minor=self.amount.minor,
  ) catch {
    error => raise ExpenseError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push({ from: self.state, to, actor_id })
  { ..self, state: to, events }
}

///|
pub fn ExpenseClaim::offset_advance(
  self : ExpenseClaim,
  advance : @employee_finance.EmployeeAdvance,
  amount_minor~ : Int64,
  actor_id~ : String,
  expense_grant~ : @foundation.AuthorityGrant,
  advance_grant~ : @foundation.AuthorityGrant,
) -> (ExpenseClaim, @employee_finance.EmployeeAdvance) raise ExpenseError {
  if self.state != ExpenseState::Approved {
    raise ExpenseError::InvalidState
  }
  if advance.employee_id != self.employee_id ||
    advance.principal_id != self.principal_id {
    raise ExpenseError::InvalidIdentifier
  }
  if amount_minor <= 0 || amount_minor > self.amount.minor - self.offset_minor {
    raise ExpenseError::OffsetExceedsExpense
  }
  @foundation.require_authority(
    expense_grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="expense:offset",
    scope="employee:\{self.employee_id}",
    amount_minor~,
  ) catch {
    error => raise ExpenseError::NotAuthorized(error)
  }
  let updated_advance = advance.offset(
    amount_minor~,
    actor_id~,
    grant=advance_grant,
  ) catch {
    error => raise ExpenseError::Advance(error)
  }
  ({ ..self, offset_minor: self.offset_minor + amount_minor }, updated_advance)
}
