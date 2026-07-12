///|
fn cash_account_state_name(state : CashAccountState) -> String {
  match state {
    CashAccountState::Open => "open"
    CashAccountState::Suspended => "suspended"
    CashAccountState::Closed => "closed"
  }
}

///|
fn cash_direction_name(direction : CashDirection) -> String {
  match direction {
    CashDirection::Inflow => "inflow"
    CashDirection::Outflow => "outflow"
  }
}

///|
fn cash_movement_state_name(state : CashMovementState) -> String {
  match state {
    CashMovementState::Requested => "requested"
    CashMovementState::Approved => "approved"
    CashMovementState::Released => "released"
    CashMovementState::Reconciled => "reconciled"
    CashMovementState::Rejected => "rejected"
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn cash_account_payload(account : CashAccount) -> String {
  Json::object({
    "account_id": Json::string(account.account_id),
    "principal_id": Json::string(account.principal_id),
    "project_scope": Json::string(account.project_scope),
    "currency": Json::string(account.currency),
    "bank_reference": Json::string(account.bank_reference),
    "balance_minor": Json::number(
      account.balance.minor.to_double(),
      repr=account.balance.minor.to_string(),
    ),
    "state": Json::string(cash_account_state_name(account.state)),
    "applied_movement_ids": string_array_json(account.applied_movement_ids),
  }).stringify()
}

///|
pub fn CashAccount::append_projection(
  self : CashAccount,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise TreasuryError {
  if projection.aggregate_type != "cash_account" ||
    projection.aggregate_id != self.account_id {
    raise TreasuryError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=cash_account_payload(self),
    source_event_id="company:cash-account:" +
      self.account_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise TreasuryError::Projection(error)
  }
}

///|
fn cash_movement_payload(movement : CashMovement) -> String {
  Json::object({
    "movement_id": Json::string(movement.movement_id),
    "account_id": Json::string(movement.account_id),
    "principal_id": Json::string(movement.principal_id),
    "project_scope": Json::string(movement.project_scope),
    "reference_id": Json::string(movement.reference_id),
    "amount_minor": Json::number(
      movement.amount.minor.to_double(),
      repr=movement.amount.minor.to_string(),
    ),
    "currency": Json::string(movement.amount.currency),
    "direction": Json::string(cash_direction_name(movement.direction)),
    "state": Json::string(cash_movement_state_name(movement.state)),
    "event_count": Json::number(
      movement.events.length().to_double(),
      repr=movement.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn CashMovement::append_projection(
  self : CashMovement,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise TreasuryError {
  if projection.aggregate_type != "cash_movement" ||
    projection.aggregate_id != self.movement_id {
    raise TreasuryError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=cash_movement_payload(self),
    source_event_id="company:cash-movement:" +
      self.movement_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise TreasuryError::Projection(error)
  }
}
