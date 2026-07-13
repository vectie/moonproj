///|
pub(all) suberror ProcurementCohortError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Supplier(@procurement.SupplierError)
  Tender(@procurement.TenderError)
  Commitment(@commitment.CommitmentError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ProcurementCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ProcurementCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ProcurementCohortError {
  match value {
    Object(value) => value
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ProcurementCohortError {
  match obj.get(key) {
    Some(value) => value
    None => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ProcurementCohortError {
  match required(obj, key) {
    String(value) => value
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise ProcurementCohortError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ProcurementCohortError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ProcurementCohortError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ProcurementCohortError::InvalidInput
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
) -> @finance.Money raise ProcurementCohortError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise ProcurementCohortError::Money(error)
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
    grant_id: "procurement-cohort-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn supplier_state_name(value : @procurement.SupplierState) -> String {
  match value {
    @procurement.SupplierState::Draft => "draft"
    @procurement.SupplierState::PendingReview => "pending_review"
    @procurement.SupplierState::Active => "active"
    @procurement.SupplierState::Suspended => "suspended"
    @procurement.SupplierState::Blacklisted => "blacklisted"
    @procurement.SupplierState::Voided => "voided"
  }
}

///|
fn supplier_evaluation_name(value : @procurement.SupplierEvaluation) -> String {
  match value {
    @procurement.SupplierEvaluation::Unrated => "unrated"
    @procurement.SupplierEvaluation::Reviewed => "reviewed"
    @procurement.SupplierEvaluation::Qualified => "qualified"
    @procurement.SupplierEvaluation::Unqualified => "unqualified"
    @procurement.SupplierEvaluation::Strategic => "strategic"
  }
}

///|
fn tender_state_name(value : @procurement.TenderState) -> String {
  match value {
    @procurement.TenderState::Planning => "planning"
    @procurement.TenderState::Publishing => "publishing"
    @procurement.TenderState::Bidding => "bidding"
    @procurement.TenderState::Awarded => "awarded"
    @procurement.TenderState::Completed => "completed"
    @procurement.TenderState::Cancelled => "cancelled"
  }
}

///|
fn commitment_state_name(value : @commitment.CommitmentState) -> String {
  match value {
    @commitment.CommitmentState::Draft => "draft"
    @commitment.CommitmentState::Submitted => "submitted"
    @commitment.CommitmentState::Approved => "approved"
    @commitment.CommitmentState::Performed => "performed"
    @commitment.CommitmentState::Settled => "settled"
    @commitment.CommitmentState::Cancelled => "cancelled"
  }
}

///|
fn find_supplier(
  suppliers : Array[@procurement.Supplier],
  supplier_id : String,
) -> @procurement.Supplier raise ProcurementCohortError {
  for supplier in suppliers {
    if supplier.supplier_id == supplier_id {
      return supplier
    }
  }
  raise ProcurementCohortError::InvalidInput
}

///|
fn evaluation(
  value : String,
) -> @procurement.SupplierEvaluation raise ProcurementCohortError {
  match value {
    "qualified" => @procurement.SupplierEvaluation::Qualified
    "strategic" => @procurement.SupplierEvaluation::Strategic
    _ => raise ProcurementCohortError::InvalidInput
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ProcurementCohortError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.procurement-cohort-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise ProcurementCohortError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let suppliers : Array[@procurement.Supplier] = []
  let accepted : Array[Json] = []
  for value in required_array(root, "suppliers") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let supplier_id = required_string(item, "supplier_id")
    let principal_id = required_string(item, "principal_id")
    let scope = required_string(item, "scope")
    let supplier_code = required_string(item, "supplier_code")
    let name = required_string(item, "name")
    let category_code = required_string(item, "category_code")
    let expected_evaluation = required_string(item, "expected_evaluation")
    let expected_state = required_string(item, "expected_state")
    let supplier = @procurement.Supplier::new(
      supplier_id~,
      principal_id~,
      scope~,
      supplier_code~,
      name~,
      category_code~,
      actor_id="migration",
      grant=grant(principal_id, "supplier:create", scope, 0),
    ) catch {
      error => raise ProcurementCohortError::Supplier(error)
    }
    let supplier = supplier.submit_review(
      actor_id="migration",
      grant=grant(principal_id, "supplier:submit", scope, 0),
    ) catch {
      error => raise ProcurementCohortError::Supplier(error)
    }
    let supplier_evaluation = evaluation(expected_evaluation)
    let supplier = supplier.review(
      evaluation=supplier_evaluation,
      actor_id="migration",
      grant=grant(principal_id, "supplier:review", scope, 0),
    ) catch {
      error => raise ProcurementCohortError::Supplier(error)
    }
    if supplier_state_name(supplier.state) != expected_state ||
      supplier_evaluation_name(supplier.evaluation) != expected_evaluation {
      raise ProcurementCohortError::InvalidInput
    }
    suppliers.push(supplier)
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("supplier"),
        "target_id": Json::string(supplier.supplier_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "supplier_id": Json::string(supplier.supplier_id),
          "principal_id": Json::string(supplier.principal_id),
          "scope": Json::string(supplier.scope),
          "supplier_code": Json::string(supplier.supplier_code),
          "name": Json::string(supplier.name),
          "category_code": Json::string(supplier.category_code),
          "state": Json::string(supplier_state_name(supplier.state)),
          "evaluation": Json::string(
            supplier_evaluation_name(supplier.evaluation),
          ),
          "event_count": number(supplier.events.length().to_int64()),
          "supplier_reviewed": Json::boolean(true),
          "qualified": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  for value in required_array(root, "tenders") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let tender_id = required_string(item, "tender_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let name = required_string(item, "name")
    let category = required_string(item, "category")
    let currency = required_string(item, "currency")
    let estimated_amount_minor = required_int64(item, "estimated_amount_minor")
    let awarded_supplier_id = required_string(item, "awarded_supplier_id")
    let awarded_amount_minor = required_int64(item, "awarded_amount_minor")
    let commitment_id = required_string(item, "commitment_id")
    let expected_tender_state = required_string(item, "expected_tender_state")
    let expected_commitment_state = required_string(
      item, "expected_commitment_state",
    )
    let estimated_amount = money(estimated_amount_minor, currency)
    let tender = @procurement.TenderPlan::new(
      tender_id~,
      principal_id~,
      project_scope~,
      name~,
      category~,
      estimated_amount~,
      actor_id="migration",
      grant=grant(
        principal_id, "tender:create", project_scope, estimated_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Tender(error)
    }
    let tender = tender.publish(
      actor_id="migration",
      grant=grant(
        principal_id, "tender:publish", project_scope, estimated_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Tender(error)
    }
    let tender = tender.open_bidding(
      actor_id="migration",
      grant=grant(
        principal_id, "tender:open", project_scope, estimated_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Tender(error)
    }
    let mut tender = tender
    for bid_value in required_array(item, "bids") {
      let bid = object(bid_value)
      let bid_supplier_id = required_string(bid, "supplier_id")
      let bid_amount_minor = required_int64(bid, "amount_minor")
      let bid_currency = required_string(bid, "currency")
      let supplier = find_supplier(suppliers, bid_supplier_id)
      let bid_amount = money(bid_amount_minor, bid_currency)
      tender = tender.add_bid(
        supplier,
        amount=bid_amount,
        actor_id="migration",
        grant=grant(principal_id, "tender:bid", project_scope, bid_amount_minor),
      ) catch {
        error => raise ProcurementCohortError::Tender(error)
      }
    }
    let awarded_supplier = find_supplier(suppliers, awarded_supplier_id)
    let tender = tender.award(
      awarded_supplier,
      actor_id="migration",
      grant=grant(
        principal_id, "tender:award", project_scope, awarded_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Tender(error)
    }
    if tender_state_name(tender.state) != expected_tender_state {
      raise ProcurementCohortError::InvalidInput
    }
    let commitment = tender.create_commitment(
      commitment_id~,
      actor_id="migration",
      award_grant=grant(
        principal_id, "tender:award-to-commitment", project_scope, awarded_amount_minor,
      ),
      commitment_grant=grant(
        principal_id, "commitment:create", project_scope, awarded_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Tender(error)
    }
    let commitment = commitment.transition(
      @commitment.CommitmentState::Submitted,
      actor_id="migration",
      grant=grant(
        principal_id, "commitment:submit", project_scope, awarded_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Commitment(error)
    }
    let commitment = commitment.transition(
      @commitment.CommitmentState::Approved,
      actor_id="migration",
      grant=grant(
        principal_id, "commitment:approve", project_scope, awarded_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Commitment(error)
    }
    let commitment = commitment.transition(
      @commitment.CommitmentState::Performed,
      actor_id="migration",
      grant=grant(
        principal_id, "commitment:perform", project_scope, awarded_amount_minor,
      ),
    ) catch {
      error => raise ProcurementCohortError::Commitment(error)
    }
    if commitment_state_name(commitment.state) != expected_commitment_state {
      raise ProcurementCohortError::InvalidInput
    }
    let bids : Array[Json] = []
    for bid in tender.bids {
      bids.push(
        Json::object({
          "supplier_id": Json::string(bid.supplier_id),
          "amount_minor": number(bid.amount.minor),
          "currency": Json::string(bid.amount.currency),
        }),
      )
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("tender"),
        "target_id": Json::string(tender.tender_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "tender_id": Json::string(tender.tender_id),
          "principal_id": Json::string(tender.principal_id),
          "project_scope": Json::string(tender.project_scope),
          "name": Json::string(tender.name),
          "category": Json::string(tender.category),
          "estimated_amount_minor": number(tender.estimated_amount.minor),
          "currency": Json::string(tender.estimated_amount.currency),
          "state": Json::string(tender_state_name(tender.state)),
          "bids": Json::array(bids),
          "awarded_supplier_id": Json::string(awarded_supplier_id),
          "awarded_amount_minor": number(awarded_amount_minor),
          "commitment_id": Json::string(commitment.commitment_id),
          "event_count": number(tender.events.length().to_int64()),
          "tender_reviewed": Json::boolean(true),
          "award_recorded": Json::boolean(true),
          "commitment_created": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("commitment"),
        "target_id": Json::string(commitment.commitment_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "commitment_id": Json::string(commitment.commitment_id),
          "principal_id": Json::string(commitment.principal_id),
          "project_scope": Json::string(commitment.project_scope),
          "counterparty_id": Json::string(commitment.counterparty_id),
          "amount_minor": number(commitment.amount.minor),
          "currency": Json::string(commitment.amount.currency),
          "state": Json::string(commitment_state_name(commitment.state)),
          "tender_id": Json::string(tender.tender_id),
          "event_count": number(commitment.events.length().to_int64()),
          "procurement_reviewed": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("procurement-cohort-v1"),
    "accepted_items": Json::array(accepted),
    "supplier_count": number(
      required_array(root, "suppliers").length().to_int64(),
    ),
    "tender_count": number(required_array(root, "tenders").length().to_int64()),
    "commitment_count": number(
      required_array(root, "tenders").length().to_int64(),
    ),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise ProcurementCohortError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: procurement_cohort <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ProcurementCohortError::InvalidInput => {
        println("procurement cohort failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      ProcurementCohortError::Io(_) => {
        println("procurement cohort failed: filesystem error")
        @sys.exit(1)
      }
      ProcurementCohortError::Money(_) => {
        println("procurement cohort failed: money validation")
        @sys.exit(1)
      }
      ProcurementCohortError::Supplier(error) => {
        println(
          "procurement cohort failed: supplier validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      ProcurementCohortError::Tender(error) => {
        println(
          "procurement cohort failed: tender validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      ProcurementCohortError::Commitment(error) => {
        println(
          "procurement cohort failed: commitment validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
    }
  }
}
