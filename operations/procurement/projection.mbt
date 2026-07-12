///|
fn supplier_state_name(state : SupplierState) -> String {
  match state {
    SupplierState::Draft => "draft"
    SupplierState::PendingReview => "pending_review"
    SupplierState::Active => "active"
    SupplierState::Suspended => "suspended"
    SupplierState::Blacklisted => "blacklisted"
    SupplierState::Voided => "voided"
  }
}

///|
fn supplier_evaluation_name(evaluation : SupplierEvaluation) -> String {
  match evaluation {
    SupplierEvaluation::Unrated => "unrated"
    SupplierEvaluation::Reviewed => "reviewed"
    SupplierEvaluation::Qualified => "qualified"
    SupplierEvaluation::Unqualified => "unqualified"
    SupplierEvaluation::Strategic => "strategic"
  }
}

///|
fn supplier_projection_payload(supplier : Supplier) -> String {
  Json::object({
    "supplier_id": Json::string(supplier.supplier_id),
    "principal_id": Json::string(supplier.principal_id),
    "scope": Json::string(supplier.scope),
    "supplier_code": Json::string(supplier.supplier_code),
    "name": Json::string(supplier.name),
    "category_code": Json::string(supplier.category_code),
    "state": Json::string(supplier_state_name(supplier.state)),
    "evaluation": Json::string(supplier_evaluation_name(supplier.evaluation)),
    "event_count": Json::number(
      supplier.events.length().to_double(),
      repr=supplier.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn Supplier::append_projection(
  self : Supplier,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise SupplierError {
  if projection.aggregate_type != "supplier" ||
    projection.aggregate_id != self.supplier_id {
    raise SupplierError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=supplier_projection_payload(self),
    source_event_id="company:supplier:" +
      self.supplier_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise SupplierError::Projection(error)
  }
}

///|
fn tender_state_name(state : TenderState) -> String {
  match state {
    TenderState::Planning => "planning"
    TenderState::Publishing => "publishing"
    TenderState::Bidding => "bidding"
    TenderState::Awarded => "awarded"
    TenderState::Completed => "completed"
    TenderState::Cancelled => "cancelled"
  }
}

///|
fn tender_projection_payload(tender : TenderPlan) -> String {
  let bids : Array[Json] = []
  for bid in tender.bids {
    bids.push(
      Json::object({
        "supplier_id": Json::string(bid.supplier_id),
        "amount_minor": Json::number(
          bid.amount.minor.to_double(),
          repr=bid.amount.minor.to_string(),
        ),
        "currency": Json::string(bid.amount.currency),
      }),
    )
  }
  let awarded_supplier : Json = match tender.awarded_supplier_id {
    Some(value) => Json::string(value)
    None => Json::null()
  }
  let awarded_amount : Json = match tender.awarded_amount {
    Some(value) =>
      Json::number(value.minor.to_double(), repr=value.minor.to_string())
    None => Json::null()
  }
  Json::object({
    "tender_id": Json::string(tender.tender_id),
    "principal_id": Json::string(tender.principal_id),
    "project_scope": Json::string(tender.project_scope),
    "name": Json::string(tender.name),
    "category": Json::string(tender.category),
    "estimated_amount_minor": Json::number(
      tender.estimated_amount.minor.to_double(),
      repr=tender.estimated_amount.minor.to_string(),
    ),
    "currency": Json::string(tender.estimated_amount.currency),
    "state": Json::string(tender_state_name(tender.state)),
    "bids": Json::array(bids),
    "awarded_supplier_id": awarded_supplier,
    "awarded_amount_minor": awarded_amount,
    "event_count": Json::number(
      tender.events.length().to_double(),
      repr=tender.events.length().to_string(),
    ),
  }).stringify()
}

///|
pub fn TenderPlan::append_projection(
  self : TenderPlan,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise TenderError {
  if projection.aggregate_type != "tender" ||
    projection.aggregate_id != self.tender_id {
    raise TenderError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=tender_projection_payload(self),
    source_event_id="company:tender:" +
      self.tender_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise TenderError::Projection(error)
  }
}
