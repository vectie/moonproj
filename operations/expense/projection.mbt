///|
fn expense_state_name(state : ExpenseState) -> String {
  match state {
    ExpenseState::Draft => "draft"
    ExpenseState::Submitted => "submitted"
    ExpenseState::Approved => "approved"
    ExpenseState::Rejected => "rejected"
    ExpenseState::Paid => "paid"
  }
}

///|
fn expense_allocations_json(allocations : Array[ExpenseAllocation]) -> Json {
  let values : Array[Json] = []
  for allocation in allocations {
    values.push(
      Json::object({
        "project_scope": Json::string(allocation.project_scope),
        "cost_subject": Json::string(allocation.cost_subject),
        "amount_minor": Json::number(
          allocation.amount.minor.to_double(),
          repr=allocation.amount.minor.to_string(),
        ),
        "currency": Json::string(allocation.amount.currency),
      }),
    )
  }
  Json::array(values)
}

///|
fn expense_projection_payload(expense : ExpenseClaim) -> String {
  Json::object({
    "expense_id": Json::string(expense.expense_id),
    "principal_id": Json::string(expense.principal_id),
    "employee_id": Json::string(expense.employee_id),
    "amount_minor": Json::number(
      expense.amount.minor.to_double(),
      repr=expense.amount.minor.to_string(),
    ),
    "offset_minor": Json::number(
      expense.offset_minor.to_double(),
      repr=expense.offset_minor.to_string(),
    ),
    "currency": Json::string(expense.amount.currency),
    "state": Json::string(expense_state_name(expense.state)),
    "allocations": expense_allocations_json(expense.allocations),
    "event_count": Json::number(
      expense.events.length().to_double(),
      repr=expense.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn ExpenseClaim::append_projection(
  self : ExpenseClaim,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ExpenseError {
  if projection.aggregate_type != "expense_claim" ||
    projection.aggregate_id != self.expense_id {
    raise ExpenseError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=expense_projection_payload(self),
    source_event_id="company:expense-claim:" +
      self.expense_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ExpenseError::Projection(error)
  }
}

///|
/// Recognition is deliberately separate from payment and advance offsetting.
pub fn ExpenseClaim::to_recognition_journal(
  self : ExpenseClaim,
  expense_account~ : String,
  payable_account~ : String,
) -> @finance.JournalEntry raise ExpenseError {
  if self.state != ExpenseState::Approved && self.state != ExpenseState::Paid {
    raise ExpenseError::InvalidState
  }
  if expense_account.trim() == "" || payable_account.trim() == "" {
    raise ExpenseError::InvalidIdentifier
  }
  let entry : @finance.JournalEntry = {
    entry_id: "expense-recognition/" + self.expense_id,
    description: "Recognize expense " + self.expense_id,
    postings: [
      {
        account: expense_account,
        side: @finance.PostingSide::Debit,
        amount: self.amount,
      },
      {
        account: payable_account,
        side: @finance.PostingSide::Credit,
        amount: self.amount,
      },
    ],
  }
  @finance.validate_journal(entry) catch {
    error => raise ExpenseError::Journal(error)
  }
  entry
}
