///|
pub(all) suberror SalesCohortError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Sales(@sales.SalesError)
  SalesRecord(@sales.SalesRecordError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise SalesCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SalesCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise SalesCohortError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise SalesCohortError {
  match value {
    Object(value) => value
    _ => raise SalesCohortError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise SalesCohortError {
  match obj.get(key) {
    Some(value) => value
    None => raise SalesCohortError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise SalesCohortError {
  match required(obj, key) {
    String(value) => value
    _ => raise SalesCohortError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise SalesCohortError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise SalesCohortError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise SalesCohortError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise SalesCohortError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise SalesCohortError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise SalesCohortError::Money(error)
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "sales-cohort-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn customer_state_name(value : @sales.CustomerState) -> String {
  match value {
    @sales.CustomerState::Active => "active"
    @sales.CustomerState::Blocked => "blocked"
    @sales.CustomerState::Archived => "archived"
  }
}

///|
fn subscription_state_name(value : @sales.SubscriptionState) -> String {
  match value {
    @sales.SubscriptionState::Reserved => "reserved"
    @sales.SubscriptionState::Converted => "converted"
    @sales.SubscriptionState::Cancelled => "cancelled"
    @sales.SubscriptionState::Refunded => "refunded"
  }
}

///|
fn sales_state_name(value : @sales.SalesState) -> String {
  match value {
    @sales.SalesState::Draft => "draft"
    @sales.SalesState::Reserved => "reserved"
    @sales.SalesState::Signed => "signed"
    @sales.SalesState::Fulfilled => "fulfilled"
    @sales.SalesState::Cancelled => "cancelled"
  }
}

///|
fn mortgage_state_name(value : @sales.MortgageState) -> String {
  match value {
    @sales.MortgageState::Applying => "applying"
    @sales.MortgageState::Approved => "approved"
    @sales.MortgageState::Released => "released"
    @sales.MortgageState::Rejected => "rejected"
  }
}

///|
fn refund_state_name(value : @sales.RefundState) -> String {
  match value {
    @sales.RefundState::Requested => "requested"
    @sales.RefundState::Approved => "approved"
    @sales.RefundState::Paid => "paid"
    @sales.RefundState::Rejected => "rejected"
  }
}

///|
fn receivable_state_name(value : @receivable.ReceivableState) -> String {
  match value {
    @receivable.ReceivableState::Open => "open"
    @receivable.ReceivableState::PartiallyCollected => "partially_collected"
    @receivable.ReceivableState::Collected => "collected"
    @receivable.ReceivableState::WrittenOff => "written_off"
  }
}

///|
fn item(
  source_table : String,
  source_id : String,
  target_type : String,
  target_id : String,
  source_snapshot_id : String,
  mapping_version : String,
  run_id : String,
  candidate : Map[String, Json],
) -> Json {
  let enriched = candidate.copy()
  enriched.set("source_snapshot_id", Json::string(source_snapshot_id))
  enriched.set("mapping_version", Json::string(mapping_version))
  enriched.set("run_id", Json::string(run_id))
  Json::object({
    "source_table": Json::string(source_table),
    "source_id": Json::string(source_id),
    "target_type": Json::string(target_type),
    "target_id": Json::string(target_id),
    "target_candidate": Json::object(enriched),
  })
}

///|
fn run(plan_path : String, output_path : String) -> Unit raise SalesCohortError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.sales-cohort-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise SalesCohortError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let customer_map = object(required(root, "customer"))
  let principal_id = required_string(customer_map, "principal_id")
  let project_scope = required_string(customer_map, "project_scope")
  let customer_id = required_string(customer_map, "customer_id")
  let customer_code = required_string(customer_map, "customer_code")
  let customer_name = required_string(customer_map, "name")
  let contact_reference = required_string(customer_map, "contact_reference")
  let customer = @sales.Customer::new(
    customer_id~,
    principal_id~,
    project_scope~,
    customer_code~,
    name=customer_name,
    contact_reference~,
    actor_id="migration",
    grant=grant(principal_id, "sales:customer:create", project_scope, 0),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let accepted : Array[Json] = []
  accepted.push(
    item(
      required_string(customer_map, "source_table"),
      required_string(customer_map, "source_id"),
      "customer",
      customer.customer_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "customer_id": Json::string(customer.customer_id),
        "principal_id": Json::string(customer.principal_id),
        "scope": Json::string(customer.project_scope),
        "customer_code": Json::string(customer.customer_code),
        "name": Json::string(customer.name),
        "state": Json::string(customer_state_name(customer.state)),
        "amount_minor": number(0L),
        "currency": Json::string("CNY"),
        "customer_reviewed": Json::boolean(true),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let subscription_map = object(required(root, "subscription"))
  let subscription_id = required_string(subscription_map, "subscription_id")
  let unit_reference = required_string(subscription_map, "unit_reference")
  let subscription_amount_minor = required_int64(
    subscription_map, "amount_minor",
  )
  let subscription_currency = required_string(subscription_map, "currency")
  let subscription_amount = money(
    subscription_amount_minor, subscription_currency,
  )
  let reservation = @sales.Reservation::new(
    subscription_id~,
    customer,
    unit_reference~,
    amount=subscription_amount,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:reserve", project_scope, subscription_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let reservation = reservation.convert(
    actor_id="migration",
    grant=grant(
      principal_id, "sales:subscription:convert", project_scope, subscription_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  accepted.push(
    item(
      required_string(subscription_map, "source_table"),
      required_string(subscription_map, "source_id"),
      "subscription",
      reservation.subscription_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "subscription_id": Json::string(reservation.subscription_id),
        "customer_id": Json::string(reservation.customer_id),
        "principal_id": Json::string(reservation.principal_id),
        "scope": Json::string(reservation.project_scope),
        "unit_reference": Json::string(reservation.unit_reference),
        "amount_minor": number(reservation.amount.minor),
        "currency": Json::string(reservation.amount.currency),
        "state": Json::string(subscription_state_name(reservation.state)),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let agreement_map = object(required(root, "agreement"))
  let agreement_id = required_string(agreement_map, "agreement_id")
  let agreement_amount_minor = required_int64(agreement_map, "amount_minor")
  let agreement_currency = required_string(agreement_map, "currency")
  let agreement_amount = money(agreement_amount_minor, agreement_currency)
  let agreement = @sales.SalesAgreement::new(
    agreement_id~,
    principal_id~,
    customer_id~,
    project_scope~,
    amount=agreement_amount,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:create", project_scope, agreement_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::Sales(error)
  }
  let agreement = agreement.transition(
    @sales.SalesState::Reserved,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:reserve", project_scope, agreement_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::Sales(error)
  }
  let agreement = agreement.transition(
    @sales.SalesState::Signed,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:sign", project_scope, agreement_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::Sales(error)
  }
  let agreement = agreement.transition(
    @sales.SalesState::Fulfilled,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:fulfill", project_scope, agreement_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::Sales(error)
  }
  let receivable_id = required_string(agreement_map, "receivable_id")
  let receivable = agreement.open_receivable(
    receivable_id~,
    actor_id="migration",
    sales_grant=grant(
      principal_id, "sales:receivable-open", project_scope, agreement_amount_minor,
    ),
    receivable_grant={
      grant_id: "sales-cohort-migration/receivable:open",
      principal_id,
      actor_id: "migration",
      capability: "receivable:open",
      scope: "customer:" + customer_id,
      max_amount_minor: agreement_amount_minor,
      active: true,
    },
  ) catch {
    error => raise SalesCohortError::Sales(error)
  }
  accepted.push(
    item(
      required_string(agreement_map, "source_table"),
      required_string(agreement_map, "source_id"),
      "sales_agreement",
      agreement.agreement_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "agreement_id": Json::string(agreement.agreement_id),
        "customer_id": Json::string(agreement.customer_id),
        "principal_id": Json::string(agreement.principal_id),
        "scope": Json::string(agreement.project_scope),
        "amount_minor": number(agreement.amount.minor),
        "currency": Json::string(agreement.amount.currency),
        "state": Json::string(sales_state_name(agreement.state)),
        "event_count": number(agreement.events.length().to_int64()),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  accepted.push(
    item(
      required_string(agreement_map, "source_table"),
      required_string(agreement_map, "source_id"),
      "receivable",
      receivable.receivable_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "receivable_id": Json::string(receivable.receivable_id),
        "source_id": Json::string(receivable.source_id),
        "customer_id": Json::string(receivable.customer_id),
        "principal_id": Json::string(receivable.principal_id),
        "scope": Json::string(project_scope),
        "amount_minor": number(receivable.amount.minor),
        "outstanding_minor": number(receivable.outstanding_minor()),
        "currency": Json::string(receivable.amount.currency),
        "state": Json::string(receivable_state_name(receivable.state)),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let mortgage_map = object(required(root, "mortgage"))
  let mortgage_id = required_string(mortgage_map, "mortgage_id")
  let bank_reference = required_string(mortgage_map, "bank_reference")
  let loan_amount_minor = required_int64(mortgage_map, "loan_amount_minor")
  let mortgage_rate_bps = required_int64(mortgage_map, "annual_rate_bps")
  let mortgage_amount = money(loan_amount_minor, agreement_currency)
  let mortgage = @sales.MortgageApplication::new(
    mortgage_id~,
    contract_id=agreement.agreement_id,
    customer,
    bank_reference~,
    loan_amount=mortgage_amount,
    annual_rate_bps=mortgage_rate_bps,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:mortgage:create", project_scope, loan_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let mortgage = mortgage.approve(
    actor_id="migration",
    grant=grant(
      principal_id, "sales:mortgage:approve", project_scope, loan_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let mortgage = mortgage.release(
    actor_id="migration",
    grant=grant(
      principal_id, "sales:mortgage:release", project_scope, loan_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  accepted.push(
    item(
      required_string(mortgage_map, "source_table"),
      required_string(mortgage_map, "source_id"),
      "mortgage",
      mortgage.mortgage_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "mortgage_id": Json::string(mortgage.mortgage_id),
        "contract_id": Json::string(mortgage.contract_id),
        "customer_id": Json::string(mortgage.customer_id),
        "principal_id": Json::string(mortgage.principal_id),
        "scope": Json::string(mortgage.project_scope),
        "bank_reference": Json::string(mortgage.bank_reference),
        "loan_amount_minor": number(mortgage.loan_amount.minor),
        "amount_minor": number(mortgage.loan_amount.minor),
        "currency": Json::string(mortgage.loan_amount.currency),
        "annual_rate_bps": number(mortgage.annual_rate_bps),
        "state": Json::string(mortgage_state_name(mortgage.state)),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let refund_map = object(required(root, "refund"))
  let refund_id = required_string(refund_map, "refund_id")
  let refund_reason = required_string(refund_map, "reason")
  let refund_amount_minor = required_int64(refund_map, "amount_minor")
  let refund_amount = money(refund_amount_minor, agreement_currency)
  let refund = @sales.RefundRequest::new(
    refund_id~,
    contract_id=agreement.agreement_id,
    customer,
    reason=refund_reason,
    amount=refund_amount,
    contract_amount=agreement.amount,
    actor_id="migration",
    grant=grant(
      principal_id, "sales:refund:create", project_scope, refund_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let refund = refund.approve(
    actor_id="migration",
    grant=grant(
      principal_id, "sales:refund:approve", project_scope, refund_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  let refund = refund.pay(
    actor_id="migration",
    grant=grant(
      principal_id, "sales:refund:pay", project_scope, refund_amount_minor,
    ),
  ) catch {
    error => raise SalesCohortError::SalesRecord(error)
  }
  accepted.push(
    item(
      required_string(refund_map, "source_table"),
      required_string(refund_map, "source_id"),
      "refund",
      refund.refund_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "refund_id": Json::string(refund.refund_id),
        "contract_id": Json::string(refund.contract_id),
        "customer_id": Json::string(refund.customer_id),
        "principal_id": Json::string(refund.principal_id),
        "scope": Json::string(refund.project_scope),
        "reason": Json::string(refund.reason),
        "amount_minor": number(refund.amount.minor),
        "currency": Json::string(refund.amount.currency),
        "state": Json::string(refund_state_name(refund.state)),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let revenue_map = object(required(root, "revenue"))
  let revenue_status = required_string(revenue_map, "status")
  if revenue_status != "expected" &&
    revenue_status != "received" &&
    revenue_status != "pending" &&
    revenue_status != "overdue" {
    raise SalesCohortError::InvalidInput
  }
  let revenue_amount_minor = required_int64(revenue_map, "amount_minor")
  if revenue_amount_minor != agreement_amount_minor ||
    required_string(revenue_map, "currency") != agreement_currency ||
    required_string(revenue_map, "contract_code") != agreement.agreement_id {
    raise SalesCohortError::InvalidInput
  }
  accepted.push(
    item(
      required_string(revenue_map, "source_table"),
      required_string(revenue_map, "source_id"),
      "sale_revenue",
      required_string(revenue_map, "revenue_id"),
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "revenue_id": Json::string(required_string(revenue_map, "revenue_id")),
        "revenue_code": Json::string(
          required_string(revenue_map, "revenue_code"),
        ),
        "contract_code": Json::string(
          required_string(revenue_map, "contract_code"),
        ),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(project_scope),
        "amount_minor": number(revenue_amount_minor),
        "currency": Json::string(agreement_currency),
        "status": Json::string(revenue_status),
        "evidence_state": Json::string("source_evidence_only"),
        "revenue_recognized": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("sales-cohort-v1"),
    "accepted_items": Json::array(accepted),
    "revenue_recognized": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise SalesCohortError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: sales_cohort <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      SalesCohortError::InvalidInput => {
        println("sales cohort failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      SalesCohortError::Io(_) => {
        println("sales cohort failed: filesystem error")
        @sys.exit(1)
      }
      SalesCohortError::Money(_) => {
        println("sales cohort failed: money validation")
        @sys.exit(1)
      }
      SalesCohortError::Sales(_) => {
        println("sales cohort failed: sales validation")
        @sys.exit(1)
      }
      SalesCohortError::SalesRecord(_) => {
        println("sales cohort failed: sales record validation")
        @sys.exit(1)
      }
    }
  }
}
