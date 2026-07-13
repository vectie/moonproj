///|
pub(all) suberror TreasuryPlanPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  TreasuryPlan(@treasury.TreasuryPlanError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise TreasuryPlanPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TreasuryPlanPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise TreasuryPlanPromotionError {
  match value {
    Object(value) => value
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise TreasuryPlanPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise TreasuryPlanPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise TreasuryPlanPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise TreasuryPlanPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise TreasuryPlanPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn plan_direction(
  value : String,
) -> @treasury.CashPlanDirection raise TreasuryPlanPromotionError {
  match value {
    "inflow" => @treasury.CashPlanDirection::Inflow
    "outflow" => @treasury.CashPlanDirection::Outflow
    _ => raise TreasuryPlanPromotionError::InvalidInput
  }
}

///|
fn direction_name(value : @treasury.CashPlanDirection) -> String {
  match value {
    @treasury.CashPlanDirection::Inflow => "inflow"
    @treasury.CashPlanDirection::Outflow => "outflow"
  }
}

///|
fn plan_state_name(value : @treasury.CashPlanState) -> String {
  match value {
    @treasury.CashPlanState::Planned => "planned"
    @treasury.CashPlanState::Confirmed => "confirmed"
    @treasury.CashPlanState::Actualized => "actualized"
    @treasury.CashPlanState::Cancelled => "cancelled"
  }
}

///|
fn dispatch_state_name(value : @treasury.DispatchState) -> String {
  match value {
    @treasury.DispatchState::Pending => "pending"
    @treasury.DispatchState::Approved => "approved"
    @treasury.DispatchState::Executed => "executed"
    @treasury.DispatchState::Cancelled => "cancelled"
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
    grant_id: "treasury-plan-migration/" + capability,
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
) -> @finance.Money raise TreasuryPlanPromotionError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise TreasuryPlanPromotionError::Money(error)
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise TreasuryPlanPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.treasury-plan-dispatch-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise TreasuryPlanPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for value in required_array(root, "cash_plans") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let plan_id = required_string(item, "plan_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let period = required_string(item, "period")
    let category = required_string(item, "category")
    let direction_value = required_string(item, "direction")
    let expected_state = required_string(item, "expected_state")
    let currency = required_string(item, "currency")
    let planned_minor = required_int64(item, "planned_amount_minor")
    let actual_minor = required_int64(item, "actual_amount_minor")
    let direction = plan_direction(direction_value)
    let planned_amount = money(planned_minor, currency)
    let cash_plan = @treasury.CashPlan::new(
      plan_id~,
      principal_id~,
      project_scope~,
      period~,
      category~,
      direction~,
      planned_amount~,
      actor_id="migration",
      grant=grant(
        principal_id, "treasury:plan:create", project_scope, planned_minor,
      ),
    ) catch {
      error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
    }
    let cash_plan = if expected_state == "planned" {
      cash_plan
    } else {
      cash_plan.confirm(
        actor_id="migration",
        grant=grant(
          principal_id, "treasury:plan:confirm", project_scope, planned_minor,
        ),
      ) catch {
        error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
      }
    }
    let cash_plan = if expected_state == "actualized" {
      let actual_amount = money(actual_minor, currency)
      cash_plan.actualize(
        actual_amount~,
        actor_id="migration",
        grant=grant(
          principal_id, "treasury:plan:actualize", project_scope, actual_minor,
        ),
      ) catch {
        error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
      }
    } else {
      cash_plan
    }
    if plan_state_name(cash_plan.state) != expected_state {
      raise TreasuryPlanPromotionError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("cash_plan"),
        "target_id": Json::string(cash_plan.plan_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "plan_id": Json::string(cash_plan.plan_id),
          "principal_id": Json::string(cash_plan.principal_id),
          "project_scope": Json::string(cash_plan.project_scope),
          "period": Json::string(cash_plan.period),
          "category": Json::string(cash_plan.category),
          "direction": Json::string(direction_name(cash_plan.direction)),
          "planned_amount_minor": number(cash_plan.planned_amount.minor),
          "actual_amount_minor": number(cash_plan.actual_amount.minor),
          "currency": Json::string(cash_plan.planned_amount.currency),
          "state": Json::string(plan_state_name(cash_plan.state)),
          "planning_reviewed": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  for value in required_array(root, "fund_dispatches") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let dispatch_id = required_string(item, "dispatch_id")
    let principal_id = required_string(item, "principal_id")
    let from_project = required_string(item, "from_project")
    let to_project = required_string(item, "to_project")
    let reason = required_string(item, "reason")
    let currency = required_string(item, "currency")
    let amount_minor = required_int64(item, "amount_minor")
    let expected_state = required_string(item, "expected_state")
    let amount = money(amount_minor, currency)
    let dispatch = @treasury.FundDispatch::new(
      dispatch_id~,
      principal_id~,
      from_project~,
      to_project~,
      amount~,
      reason~,
      actor_id="migration",
      grant=grant(
        principal_id, "treasury:dispatch:create", from_project, amount_minor,
      ),
    ) catch {
      error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
    }
    let dispatch = if expected_state == "pending" {
      dispatch
    } else {
      dispatch.approve(
        actor_id="migration",
        grant=grant(
          principal_id, "treasury:dispatch:approve", from_project, amount_minor,
        ),
      ) catch {
        error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
      }
    }
    let dispatch = if expected_state == "executed" {
      dispatch.execute(
        actor_id="migration",
        grant=grant(
          principal_id, "treasury:dispatch:execute", from_project, amount_minor,
        ),
      ) catch {
        error => raise TreasuryPlanPromotionError::TreasuryPlan(error)
      }
    } else {
      dispatch
    }
    if dispatch_state_name(dispatch.state) != expected_state {
      raise TreasuryPlanPromotionError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("fund_dispatch"),
        "target_id": Json::string(dispatch.dispatch_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "dispatch_id": Json::string(dispatch.dispatch_id),
          "principal_id": Json::string(dispatch.principal_id),
          "from_project": Json::string(dispatch.from_project),
          "to_project": Json::string(dispatch.to_project),
          "amount_minor": number(dispatch.amount.minor),
          "currency": Json::string(dispatch.amount.currency),
          "reason": Json::string(dispatch.reason),
          "state": Json::string(dispatch_state_name(dispatch.state)),
          "dispatch_reviewed": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise TreasuryPlanPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("treasury-plan-dispatch-v1"),
    "accepted_items": Json::array(accepted),
    "cash_plan_count": number(
      required_array(root, "cash_plans").length().to_int64(),
    ),
    "fund_dispatch_count": number(
      required_array(root, "fund_dispatches").length().to_int64(),
    ),
    "cash_released": Json::boolean(false),
    "dispatch_settled": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise TreasuryPlanPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: treasury_plan_dispatch <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      TreasuryPlanPromotionError::InvalidInput => {
        println("treasury plan promotion failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      TreasuryPlanPromotionError::Io(_) => {
        println("treasury plan promotion failed: filesystem error")
        @sys.exit(1)
      }
      TreasuryPlanPromotionError::Money(_) => {
        println("treasury plan promotion failed: money validation")
        @sys.exit(1)
      }
      TreasuryPlanPromotionError::TreasuryPlan(_) => {
        println("treasury plan promotion failed: treasury lifecycle validation")
        @sys.exit(1)
      }
    }
  }
}
