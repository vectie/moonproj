///|
pub(all) suberror CbsBudgetPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Cbs(@cbs.CbsError)
  Money(@finance.MoneyError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise CbsBudgetPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise CbsBudgetPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise CbsBudgetPromotionError {
  match value {
    Object(value) => value
    _ => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise CbsBudgetPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise CbsBudgetPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise CbsBudgetPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise CbsBudgetPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise CbsBudgetPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise CbsBudgetPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise CbsBudgetPromotionError::InvalidInput
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
    grant_id: "cbs-budget/migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn reservation_state_name(state : @cbs.CbsBudgetReservationState) -> String {
  match state {
    @cbs.CbsBudgetReservationState::Reserved => "reserved"
    @cbs.CbsBudgetReservationState::Consumed => "consumed"
    @cbs.CbsBudgetReservationState::Released => "released"
  }
}

///|
fn reservations_json(reservations : Array[@cbs.CbsBudgetReservation]) -> Json {
  let encoded : Array[Json] = []
  for reservation in reservations {
    encoded.push(
      Json::object({
        "reservation_id": Json::string(reservation.reservation_id),
        "source_id": Json::string(reservation.source_id),
        "version_id": Json::string(reservation.version_id),
        "project_scope": Json::string(reservation.project_scope),
        "subject_code": Json::string(reservation.subject_code),
        "principal_id": Json::string(reservation.principal_id),
        "amount_minor": Json::number(
          reservation.amount.minor.to_double(),
          repr=reservation.amount.minor.to_string(),
        ),
        "currency": Json::string(reservation.amount.currency),
        "state": Json::string(reservation_state_name(reservation.state)),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise CbsBudgetPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.company.cbs-budget-plan.v1" {
    raise CbsBudgetPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let version_id = required_string(root, "version_id")
  let project_scope = required_string(root, "project_scope")
  let principal_id = required_string(root, "principal_id")
  let currency = required_string(root, "currency")
  let mut version = @cbs.CbsVersion::new(
    version_id~,
    project_scope~,
    actor_id="migration",
    grant=grant(principal_id, "cbs:create", project_scope, 0L),
  ) catch {
    error => raise CbsBudgetPromotionError::Cbs(error)
  }
  for subject_value in required_array(root, "subjects") {
    let subject = object(subject_value)
    let subject_id = required_string(subject, "subject_id")
    let subject_code = required_string(subject, "code")
    let subject_name = required_string(subject, "name")
    let parent_code = required_string(subject, "parent_code")
    let target_minor = required_int64(subject, "target_minor")
    version = version.add_subject(
      subject={
        subject_id,
        code: subject_code,
        name: subject_name,
        parent_code,
        target_minor,
      },
      actor_id="migration",
      grant=grant(principal_id, "cbs:edit", project_scope, target_minor),
    ) catch {
      error => raise CbsBudgetPromotionError::Cbs(error)
    }
  }
  version = version.activate(
    actor_id="migration",
    grant=grant(principal_id, "cbs:activate", project_scope, 0L),
  ) catch {
    error => raise CbsBudgetPromotionError::Cbs(error)
  }
  let mut ledger = @cbs.CbsBudgetLedger::new(version, principal_id~, currency~) catch {
    error => raise CbsBudgetPromotionError::Cbs(error)
  }
  for link_value in required_array(root, "links") {
    let item = object(link_value)
    let amount_minor = required_int64(item, "amount_minor")
    let amount_currency = required_string(item, "currency")
    let link_id = required_string(item, "link_id")
    let source_id = required_string(item, "source_id")
    let subject_code = required_string(item, "subject_code")
    let reservation_id = required_string(item, "reservation_id")
    let consume = required_bool(item, "consume")
    let amount = @finance.Money::new(
      minor=amount_minor,
      currency=amount_currency,
    ) catch {
      error => raise CbsBudgetPromotionError::Money(error)
    }
    let link = version.link_cost(
      link_id~,
      source_id~,
      subject_code~,
      amount~,
      actor_id="migration",
      grant=grant(principal_id, "cbs:cost:link", project_scope, amount_minor),
    ) catch {
      error => raise CbsBudgetPromotionError::Cbs(error)
    }
    let (reserved, reservation) = ledger.reserve(
      version,
      link,
      reservation_id~,
      actor_id="migration",
      grant=grant(
        principal_id, "cbs:budget:reserve", project_scope, amount_minor,
      ),
    ) catch {
      error => raise CbsBudgetPromotionError::Cbs(error)
    }
    ledger = reserved
    if consume {
      ledger = ledger.consume(
        reservation_id=reservation.reservation_id,
        actor_id="migration",
        grant=grant(
          principal_id, "cbs:budget:consume", project_scope, amount_minor,
        ),
      ) catch {
        error => raise CbsBudgetPromotionError::Cbs(error)
      }
    }
  }
  let candidate = Json::object({
    "version_id": Json::string(ledger.version_id),
    "project_scope": Json::string(ledger.project_scope),
    "principal_id": Json::string(ledger.principal_id),
    "currency": Json::string(ledger.currency),
    "reserved_minor": Json::number(
      ledger.reserved_minor().to_double(),
      repr=ledger.reserved_minor().to_string(),
    ),
    "consumed_minor": Json::number(
      ledger.consumed_minor().to_double(),
      repr=ledger.consumed_minor().to_string(),
    ),
    "reservations": reservations_json(ledger.reservations),
    "budget_control_only": Json::boolean(true),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("cbs-budget-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string("cbs_budget"),
        "source_id": Json::string(version_id),
        "target_type": Json::string("cbs_budget_ledger"),
        "target_id": Json::string(version_id),
        "target_candidate": candidate,
      }),
    ]),
    "budget_control_only": Json::boolean(true),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise CbsBudgetPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: cbs_budget <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      CbsBudgetPromotionError::InvalidInput => {
        println("CBS budget failed: invalid input")
        @sys.exit(1)
      }
      CbsBudgetPromotionError::Io(_) => {
        println("CBS budget failed: filesystem error")
        @sys.exit(1)
      }
      CbsBudgetPromotionError::Cbs(_) => {
        println("CBS budget failed: CBS validation")
        @sys.exit(1)
      }
      CbsBudgetPromotionError::Money(_) => {
        println("CBS budget failed: invalid money")
        @sys.exit(1)
      }
    }
  }
}
