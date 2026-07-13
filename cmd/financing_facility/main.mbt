///|
pub(all) suberror FinancingPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Financing(@financing.FinancingError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise FinancingPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise FinancingPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise FinancingPromotionError {
  match value {
    Object(value) => value
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise FinancingPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise FinancingPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise FinancingPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise FinancingPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise FinancingPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise FinancingPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn state_name(value : @financing.FacilityState) -> String {
  match value {
    @financing.FacilityState::Draft => "draft"
    @financing.FacilityState::Approved => "approved"
    @financing.FacilityState::Active => "active"
    @financing.FacilityState::PartiallyRepaid => "partially_repaid"
    @financing.FacilityState::Closed => "closed"
    @financing.FacilityState::Defaulted => "defaulted"
    @financing.FacilityState::Cancelled => "cancelled"
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
    grant_id: "financing-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise FinancingPromotionError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise FinancingPromotionError::Money(error)
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise FinancingPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.financing-facility-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise FinancingPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for value in required_array(root, "facilities") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let facility_id = required_string(item, "facility_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let lender_id = required_string(item, "lender_id")
    let currency = required_string(item, "currency")
    let limit_minor = required_int64(item, "limit_amount_minor")
    let annual_rate_bps = required_int64(item, "annual_rate_bps")
    let draw_minor = required_int64(item, "draw_amount_minor")
    let repay_minor = required_int64(item, "repay_amount_minor")
    let interest_days = required_int64(item, "interest_days")
    let expected_state = required_string(item, "expected_state")
    let create_grant = grant(
      principal_id, "financing:create", project_scope, limit_minor,
    )
    let limit_amount = money(limit_minor, currency)
    let facility = @financing.FinancingFacility::new(
      facility_id~,
      principal_id~,
      project_scope~,
      lender_id~,
      limit_amount~,
      annual_rate_bps~,
      actor_id="migration",
      grant=create_grant,
    ) catch {
      error => raise FinancingPromotionError::Financing(error)
    }
    let facility = facility.approve(
      actor_id="migration",
      grant=grant(principal_id, "financing:approve", project_scope, limit_minor),
    ) catch {
      error => raise FinancingPromotionError::Financing(error)
    }
    let facility = facility.activate(
      actor_id="migration",
      grant=grant(
        principal_id, "financing:activate", project_scope, limit_minor,
      ),
    ) catch {
      error => raise FinancingPromotionError::Financing(error)
    }
    let facility = if draw_minor > 0L {
      let draw_amount = money(draw_minor, currency)
      facility.draw(
        amount=draw_amount,
        actor_id="migration",
        grant=grant(principal_id, "financing:draw", project_scope, draw_minor),
      ) catch {
        error => raise FinancingPromotionError::Financing(error)
      }
    } else {
      facility
    }
    let facility = if repay_minor > 0L {
      let repay_amount = money(repay_minor, currency)
      facility.repay(
        amount=repay_amount,
        actor_id="migration",
        grant=grant(principal_id, "financing:repay", project_scope, repay_minor),
      ) catch {
        error => raise FinancingPromotionError::Financing(error)
      }
    } else {
      facility
    }
    let (interest, facility) = if interest_days > 0L {
      facility.accrue_interest(
        interest_days,
        actor_id="migration",
        grant=grant(
          principal_id,
          "financing:accrue",
          project_scope,
          facility.outstanding_principal.minor,
        ),
      ) catch {
        error => raise FinancingPromotionError::Financing(error)
      }
    } else {
      (money(0L, currency), facility)
    }
    let facility = if expected_state == "defaulted" {
      facility.default(
        actor_id="migration",
        grant=grant(
          principal_id, "financing:default", project_scope, limit_minor,
        ),
      ) catch {
        error => raise FinancingPromotionError::Financing(error)
      }
    } else {
      facility
    }
    if state_name(facility.state) != expected_state {
      raise FinancingPromotionError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("financing_facility"),
        "target_id": Json::string(facility.facility_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "facility_id": Json::string(facility.facility_id),
          "principal_id": Json::string(facility.principal_id),
          "project_scope": Json::string(facility.project_scope),
          "lender_id": Json::string(facility.lender_id),
          "limit_amount_minor": number(facility.limit_amount.minor),
          "drawn_amount_minor": number(facility.drawn_amount.minor),
          "outstanding_principal_minor": number(
            facility.outstanding_principal.minor,
          ),
          "annual_rate_bps": number(facility.annual_rate_bps),
          "currency": Json::string(facility.limit_amount.currency),
          "expected_state": Json::string(expected_state),
          "actual_state": Json::string(state_name(facility.state)),
          "event_count": number(facility.events.length().to_int64()),
          "interest_days": number(interest_days),
          "interest_amount_minor": number(interest.minor),
          "facility_reviewed": Json::boolean(true),
          "lender_called": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise FinancingPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("financing-facility-v1"),
    "accepted_items": Json::array(accepted),
    "facility_count": number(accepted.length().to_int64()),
    "lender_called": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise FinancingPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: financing_facility <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      FinancingPromotionError::InvalidInput => {
        println(
          "financing facility promotion failed: invalid or unreviewed input",
        )
        @sys.exit(1)
      }
      FinancingPromotionError::Io(_) => {
        println("financing facility promotion failed: filesystem error")
        @sys.exit(1)
      }
      FinancingPromotionError::Money(_) => {
        println("financing facility promotion failed: money validation")
        @sys.exit(1)
      }
      FinancingPromotionError::Financing(_) => {
        println(
          "financing facility promotion failed: financing lifecycle validation",
        )
        @sys.exit(1)
      }
    }
  }
}
