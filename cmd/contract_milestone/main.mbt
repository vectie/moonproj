///|
pub(all) suberror ContractMilestoneCohortError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Commitment(@commitment.CommitmentError)
  Contract(@contract.MilestoneError)
  Settlement(@settlement.SettlementError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ContractMilestoneCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ContractMilestoneCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ContractMilestoneCohortError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ContractMilestoneCohortError {
  match value {
    Object(value) => value
    _ => raise ContractMilestoneCohortError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ContractMilestoneCohortError {
  match obj.get(key) {
    Some(value) => value
    None => raise ContractMilestoneCohortError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ContractMilestoneCohortError {
  match required(obj, key) {
    String(value) => value
    _ => raise ContractMilestoneCohortError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise ContractMilestoneCohortError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise ContractMilestoneCohortError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ContractMilestoneCohortError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ContractMilestoneCohortError::InvalidInput
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
) -> @finance.Money raise ContractMilestoneCohortError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise ContractMilestoneCohortError::Money(error)
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
    grant_id: "contract-milestone-cohort-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn trigger(
  value : String,
) -> @contract.MilestoneTrigger raise ContractMilestoneCohortError {
  match value {
    "time" => @contract.MilestoneTrigger::Time
    "progress" => @contract.MilestoneTrigger::Progress
    "event" => @contract.MilestoneTrigger::Event
    _ => raise ContractMilestoneCohortError::InvalidInput
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
fn milestone_state_name(value : @contract.MilestoneState) -> String {
  match value {
    @contract.MilestoneState::Planned => "planned"
    @contract.MilestoneState::Eligible => "eligible"
    @contract.MilestoneState::Reached => "reached"
    @contract.MilestoneState::Paid => "paid"
    @contract.MilestoneState::Overdue => "overdue"
    @contract.MilestoneState::Cancelled => "cancelled"
  }
}

///|
fn settlement_state_name(value : @settlement.SettlementState) -> String {
  match value {
    @settlement.SettlementState::Requested => "requested"
    @settlement.SettlementState::Approved => "approved"
    @settlement.SettlementState::Released => "released"
    @settlement.SettlementState::Reconciled => "reconciled"
    @settlement.SettlementState::Rejected => "rejected"
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
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ContractMilestoneCohortError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.contract-milestone-cohort-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise ContractMilestoneCohortError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")

  let commitment_map = object(required(root, "commitment"))
  let principal_id = required_string(commitment_map, "principal_id")
  let scope = required_string(commitment_map, "project_scope")
  let commitment_id = required_string(commitment_map, "commitment_id")
  let counterparty_id = required_string(commitment_map, "counterparty_id")
  let commitment_minor = required_int64(commitment_map, "amount_minor")
  let currency = required_string(commitment_map, "currency")
  let commitment_amount = money(commitment_minor, currency)
  let commitment = @commitment.Commitment::new(
    commitment_id~,
    principal_id~,
    project_scope=scope,
    counterparty_id~,
    amount=commitment_amount,
    actor_id="migration",
    grant=grant(principal_id, "commitment:create", scope, commitment_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Commitment(error)
  }
  let commitment = commitment.transition(
    @commitment.CommitmentState::Submitted,
    actor_id="migration",
    grant=grant(principal_id, "commitment:submit", scope, commitment_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Commitment(error)
  }
  let commitment = commitment.transition(
    @commitment.CommitmentState::Approved,
    actor_id="migration",
    grant=grant(principal_id, "commitment:approve", scope, commitment_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Commitment(error)
  }
  let commitment = commitment.transition(
    @commitment.CommitmentState::Performed,
    actor_id="migration",
    grant=grant(principal_id, "commitment:perform", scope, commitment_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Commitment(error)
  }

  let milestone_map = object(required(root, "milestone"))
  let milestone_id = required_string(milestone_map, "milestone_id")
  let sequence = required_int64(milestone_map, "sequence").to_int()
  let node_name = required_string(milestone_map, "node_name")
  let milestone_trigger = trigger(required_string(milestone_map, "trigger"))
  let plan_minor = required_int64(milestone_map, "plan_amount_minor")
  let actual_minor = required_int64(milestone_map, "actual_amount_minor")
  let plan_pct_bps = required_int64(milestone_map, "plan_pct_bps")
  let plan_amount = money(plan_minor, currency)
  let actual_amount = money(actual_minor, currency)
  let milestone = @contract.ContractMilestone::new(
    commitment,
    milestone_id~,
    sequence~,
    node_name~,
    trigger=milestone_trigger,
    plan_amount~,
    plan_pct_bps~,
    actor_id="migration",
    grant=grant(principal_id, "milestone:create", scope, plan_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Contract(error)
  }
  let milestone = milestone.mark_eligible(
    actor_id="migration",
    grant=grant(principal_id, "milestone:eligible", scope, plan_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Contract(error)
  }
  let milestone = milestone.reach(
    actual_amount~,
    actor_id="migration",
    grant=grant(principal_id, "milestone:reach", scope, actual_minor),
  ) catch {
    error => raise ContractMilestoneCohortError::Contract(error)
  }

  let settlement_map = object(required(root, "settlement"))
  let settlement_id = required_string(settlement_map, "settlement_id")
  let settlement = milestone.request_settlement(
    commitment,
    settlement_id~,
    actor_id="migration",
    milestone_grant=grant(
      principal_id, "milestone:settlement-request", scope, actual_minor,
    ),
    settlement_grant=grant(
      principal_id, "settlement:request", scope, actual_minor,
    ),
  ) catch {
    error => raise ContractMilestoneCohortError::Contract(error)
  }

  let accepted : Array[Json] = []
  let commitment_map_source_table = required_string(
    commitment_map, "source_table",
  )
  let commitment_map_source_id = required_string(commitment_map, "source_id")
  accepted.push(
    item(
      commitment_map_source_table,
      commitment_map_source_id,
      "commitment",
      commitment.commitment_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "commitment_id": Json::string(commitment.commitment_id),
        "principal_id": Json::string(commitment.principal_id),
        "project_scope": Json::string(commitment.project_scope),
        "counterparty_id": Json::string(commitment.counterparty_id),
        "amount_minor": number(commitment.amount.minor),
        "currency": Json::string(commitment.amount.currency),
        "state": Json::string(commitment_state_name(commitment.state)),
        "event_count": number(commitment.events.length().to_int64()),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  let milestone_map_source_table = required_string(
    milestone_map, "source_table",
  )
  let milestone_map_source_id = required_string(milestone_map, "source_id")
  accepted.push(
    item(
      milestone_map_source_table,
      milestone_map_source_id,
      "contract_milestone",
      milestone.milestone_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "milestone_id": Json::string(milestone.milestone_id),
        "commitment_id": Json::string(milestone.commitment_id),
        "principal_id": Json::string(milestone.principal_id),
        "project_scope": Json::string(milestone.project_scope),
        "sequence": number(milestone.sequence.to_int64()),
        "node_name": Json::string(milestone.node_name),
        "trigger": Json::string(required_string(milestone_map, "trigger")),
        "plan_amount_minor": number(milestone.plan_amount.minor),
        "actual_amount_minor": number(milestone.actual_amount.minor),
        "plan_pct_bps": number(milestone.plan_pct_bps),
        "currency": Json::string(milestone.plan_amount.currency),
        "state": Json::string(milestone_state_name(milestone.state)),
        "event_count": number(milestone.events.length().to_int64()),
        "settlement_linked": Json::boolean(true),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  let settlement_map_source_table = required_string(
    settlement_map, "source_table",
  )
  let settlement_map_source_id = required_string(settlement_map, "source_id")
  accepted.push(
    item(
      settlement_map_source_table,
      settlement_map_source_id,
      "settlement",
      settlement.settlement_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "settlement_id": Json::string(settlement.settlement_id),
        "commitment_id": Json::string(settlement.commitment_id),
        "milestone_id": Json::string(milestone.milestone_id),
        "principal_id": Json::string(settlement.principal_id),
        "project_scope": Json::string(settlement.project_scope),
        "amount_minor": number(settlement.amount.minor),
        "currency": Json::string(settlement.amount.currency),
        "state": Json::string(settlement_state_name(settlement.state)),
        "event_count": number(settlement.events.length().to_int64()),
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
    "cohort": Json::string("contract-milestone-cohort-v1"),
    "accepted_items": Json::array(accepted),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise ContractMilestoneCohortError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: contract_milestone <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ContractMilestoneCohortError::InvalidInput => {
        println("contract milestone cohort failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      ContractMilestoneCohortError::Io(_) => {
        println("contract milestone cohort failed: filesystem error")
        @sys.exit(1)
      }
      ContractMilestoneCohortError::Money(_) => {
        println("contract milestone cohort failed: money validation")
        @sys.exit(1)
      }
      ContractMilestoneCohortError::Commitment(_) => {
        println("contract milestone cohort failed: commitment validation")
        @sys.exit(1)
      }
      ContractMilestoneCohortError::Contract(_) => {
        println("contract milestone cohort failed: milestone validation")
        @sys.exit(1)
      }
      ContractMilestoneCohortError::Settlement(_) => {
        println("contract milestone cohort failed: settlement validation")
        @sys.exit(1)
      }
    }
  }
}
