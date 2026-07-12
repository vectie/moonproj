///|
fn statement_state_name(state : BankStatementState) -> String {
  match state {
    BankStatementState::Imported => "imported"
    BankStatementState::Reconciled => "reconciled"
    BankStatementState::LedgerReconciled => "ledger_reconciled"
    BankStatementState::Rejected => "rejected"
  }
}

///|
fn statement_direction_name(direction : CashDirection) -> String {
  match direction {
    CashDirection::Inflow => "inflow"
    CashDirection::Outflow => "outflow"
  }
}

///|
fn statement_lines_json(lines : Array[BankStatementLine]) -> Json {
  let values : Array[Json] = []
  for line in lines {
    values.push(
      Json::object({
        "line_id": Json::string(line.line_id),
        "external_reference": Json::string(line.external_reference),
        "booked_at": Json::string(line.booked_at),
        "amount_minor": Json::number(
          line.amount.minor.to_double(),
          repr=line.amount.minor.to_string(),
        ),
        "direction": Json::string(statement_direction_name(line.direction)),
      }),
    )
  }
  Json::array(values)
}

///|
fn statement_matches_json(matches : Array[StatementMatch]) -> Json {
  let values : Array[Json] = []
  for item in matches {
    values.push(
      Json::object({
        "line_id": Json::string(item.line_id),
        "movement_id": Json::string(item.movement_id),
      }),
    )
  }
  Json::array(values)
}

///|
fn statement_ledger_matches_json(matches : Array[StatementLedgerMatch]) -> Json {
  let values : Array[Json] = []
  for item in matches {
    values.push(
      Json::object({
        "line_id": Json::string(item.line_id),
        "event_id": Json::string(item.event_id),
      }),
    )
  }
  Json::array(values)
}

///|
pub fn BankStatement::append_projection(
  self : BankStatement,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise StatementError {
  if projection.aggregate_type != "bank_statement" ||
    projection.aggregate_id != self.statement_id {
    raise StatementError::ProjectionIdentity
  }
  let payload = Json::object({
    "statement_id": Json::string(self.statement_id),
    "account_id": Json::string(self.account_id),
    "principal_id": Json::string(self.principal_id),
    "project_scope": Json::string(self.project_scope),
    "period": Json::string(self.period),
    "opening_balance_minor": Json::number(
      self.opening_balance.minor.to_double(),
      repr=self.opening_balance.minor.to_string(),
    ),
    "closing_balance_minor": Json::number(
      self.closing_balance.minor.to_double(),
      repr=self.closing_balance.minor.to_string(),
    ),
    "currency": Json::string(self.opening_balance.currency),
    "lines": statement_lines_json(self.lines),
    "matches": statement_matches_json(self.matches),
    "ledger_matches": statement_ledger_matches_json(self.ledger_matches),
    "state": Json::string(statement_state_name(self.state)),
  }).stringify()
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:bank-statement:" +
      self.statement_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise StatementError::Projection(error)
  }
}
