///|
pub(all) enum CustomerState {
  Active
  Blocked
  Archived
} derive(Debug, Eq)

///|
pub(all) struct Customer {
  customer_id : String
  principal_id : String
  project_scope : String
  customer_code : String
  name : String
  contact_reference : String
  state : CustomerState
} derive(Debug, Eq)

///|
pub(all) enum SubscriptionState {
  Reserved
  Converted
  Cancelled
  Refunded
} derive(Debug, Eq)

///|
pub(all) struct Reservation {
  subscription_id : String
  customer_id : String
  principal_id : String
  project_scope : String
  unit_reference : String
  amount : @finance.Money
  state : SubscriptionState
} derive(Debug, Eq)

///|
pub(all) enum MortgageState {
  Applying
  Approved
  Released
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct MortgageApplication {
  mortgage_id : String
  contract_id : String
  customer_id : String
  principal_id : String
  project_scope : String
  bank_reference : String
  loan_amount : @finance.Money
  annual_rate_bps : Int64
  state : MortgageState
} derive(Debug, Eq)

///|
pub(all) enum RefundState {
  Requested
  Approved
  Paid
  Rejected
} derive(Debug, Eq)

///|
pub(all) struct RefundRequest {
  refund_id : String
  contract_id : String
  customer_id : String
  principal_id : String
  project_scope : String
  reason : String
  amount : @finance.Money
  state : RefundState
} derive(Debug, Eq)

///|
pub(all) suberror SalesRecordError {
  EmptyIdentifier
  InvalidAmount
  InvalidRate
  CurrencyMismatch
  InvalidState
  OverRefund
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn Customer::new(
  customer_id~ : String,
  principal_id~ : String,
  project_scope~ : String,
  customer_code~ : String,
  name~ : String,
  contact_reference~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Customer raise SalesRecordError {
  if customer_id.trim() == "" ||
    principal_id.trim() == "" ||
    project_scope.trim() == "" ||
    customer_code.trim() == "" ||
    name.trim() == "" ||
    contact_reference.trim() == "" {
    raise SalesRecordError::EmptyIdentifier
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="sales:customer:create",
    scope=project_scope,
    amount_minor=0,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  {
    customer_id,
    principal_id,
    project_scope,
    customer_code,
    name,
    contact_reference,
    state: CustomerState::Active,
  }
}

///|
pub fn Customer::block(
  self : Customer,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Customer raise SalesRecordError {
  if self.state != CustomerState::Active {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:customer:block",
    scope=self.project_scope,
    amount_minor=0,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: CustomerState::Blocked }
}

///|
pub fn Reservation::new(
  subscription_id~ : String,
  customer : Customer,
  unit_reference~ : String,
  amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Reservation raise SalesRecordError {
  if subscription_id.trim() == "" || unit_reference.trim() == "" {
    raise SalesRecordError::EmptyIdentifier
  }
  if customer.state != CustomerState::Active {
    raise SalesRecordError::InvalidState
  }
  if amount.minor <= 0 {
    raise SalesRecordError::InvalidAmount
  }
  @foundation.require_authority(
    grant,
    principal_id=customer.principal_id,
    actor_id~,
    capability="sales:reserve",
    scope=customer.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  {
    subscription_id,
    customer_id: customer.customer_id,
    principal_id: customer.principal_id,
    project_scope: customer.project_scope,
    unit_reference,
    amount,
    state: SubscriptionState::Reserved,
  }
}

///|
pub fn Reservation::convert(
  self : Reservation,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> Reservation raise SalesRecordError {
  if self.state != SubscriptionState::Reserved {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:subscription:convert",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: SubscriptionState::Converted }
}

///|
pub fn MortgageApplication::new(
  mortgage_id~ : String,
  contract_id~ : String,
  customer : Customer,
  bank_reference~ : String,
  loan_amount~ : @finance.Money,
  annual_rate_bps~ : Int64,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MortgageApplication raise SalesRecordError {
  if mortgage_id.trim() == "" ||
    contract_id.trim() == "" ||
    bank_reference.trim() == "" {
    raise SalesRecordError::EmptyIdentifier
  }
  if loan_amount.minor <= 0 {
    raise SalesRecordError::InvalidAmount
  }
  if annual_rate_bps < 0L || annual_rate_bps > 10000L {
    raise SalesRecordError::InvalidRate
  }
  @foundation.require_authority(
    grant,
    principal_id=customer.principal_id,
    actor_id~,
    capability="sales:mortgage:create",
    scope=customer.project_scope,
    amount_minor=loan_amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  {
    mortgage_id,
    contract_id,
    customer_id: customer.customer_id,
    principal_id: customer.principal_id,
    project_scope: customer.project_scope,
    bank_reference,
    loan_amount,
    annual_rate_bps,
    state: MortgageState::Applying,
  }
}

///|
pub fn MortgageApplication::approve(
  self : MortgageApplication,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MortgageApplication raise SalesRecordError {
  if self.state != MortgageState::Applying {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:mortgage:approve",
    scope=self.project_scope,
    amount_minor=self.loan_amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: MortgageState::Approved }
}

///|
pub fn MortgageApplication::release(
  self : MortgageApplication,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> MortgageApplication raise SalesRecordError {
  if self.state != MortgageState::Approved {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:mortgage:release",
    scope=self.project_scope,
    amount_minor=self.loan_amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: MortgageState::Released }
}

///|
pub fn RefundRequest::new(
  refund_id~ : String,
  contract_id~ : String,
  customer : Customer,
  reason~ : String,
  amount~ : @finance.Money,
  contract_amount~ : @finance.Money,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> RefundRequest raise SalesRecordError {
  if refund_id.trim() == "" || contract_id.trim() == "" || reason.trim() == "" {
    raise SalesRecordError::EmptyIdentifier
  }
  if amount.minor <= 0 || contract_amount.minor <= 0 {
    raise SalesRecordError::InvalidAmount
  }
  if amount.currency != contract_amount.currency {
    raise SalesRecordError::CurrencyMismatch
  }
  if amount.minor > contract_amount.minor {
    raise SalesRecordError::OverRefund
  }
  @foundation.require_authority(
    grant,
    principal_id=customer.principal_id,
    actor_id~,
    capability="sales:refund:create",
    scope=customer.project_scope,
    amount_minor=amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  {
    refund_id,
    contract_id,
    customer_id: customer.customer_id,
    principal_id: customer.principal_id,
    project_scope: customer.project_scope,
    reason,
    amount,
    state: RefundState::Requested,
  }
}

///|
pub fn RefundRequest::approve(
  self : RefundRequest,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> RefundRequest raise SalesRecordError {
  if self.state != RefundState::Requested {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:refund:approve",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: RefundState::Approved }
}

///|
pub fn RefundRequest::pay(
  self : RefundRequest,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> RefundRequest raise SalesRecordError {
  if self.state != RefundState::Approved {
    raise SalesRecordError::InvalidState
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="sales:refund:pay",
    scope=self.project_scope,
    amount_minor=self.amount.minor,
  ) catch {
    error => raise SalesRecordError::NotAuthorized(error)
  }
  { ..self, state: RefundState::Paid }
}
