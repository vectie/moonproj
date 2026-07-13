///|
pub(all) suberror MarketingCohortError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Marketing(@marketing.MarketingError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise MarketingCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise MarketingCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise MarketingCohortError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise MarketingCohortError {
  match value {
    Object(value) => value
    _ => raise MarketingCohortError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise MarketingCohortError {
  match obj.get(key) {
    Some(value) => value
    None => raise MarketingCohortError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise MarketingCohortError {
  match required(obj, key) {
    String(value) => value
    _ => raise MarketingCohortError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise MarketingCohortError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise MarketingCohortError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise MarketingCohortError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise MarketingCohortError::InvalidInput
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
) -> @finance.Money raise MarketingCohortError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise MarketingCohortError::Money(error)
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
    grant_id: "marketing-cohort-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn campaign_state_name(value : @marketing.CampaignState) -> String {
  match value {
    @marketing.CampaignState::Planning => "planning"
    @marketing.CampaignState::Active => "active"
    @marketing.CampaignState::Completed => "completed"
    @marketing.CampaignState::Cancelled => "cancelled"
  }
}

///|
fn placement_state_name(value : @marketing.PlacementState) -> String {
  match value {
    @marketing.PlacementState::Planned => "planned"
    @marketing.PlacementState::Placed => "placed"
    @marketing.PlacementState::Cancelled => "cancelled"
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
) -> Unit raise MarketingCohortError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.marketing-cohort-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise MarketingCohortError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let campaign_map = object(required(root, "campaign"))
  let principal_id = required_string(campaign_map, "principal_id")
  let scope = required_string(campaign_map, "project_scope")
  let campaign_id = required_string(campaign_map, "campaign_id")
  let budget_minor = required_int64(campaign_map, "budget_amount_minor")
  let spend_minor = required_int64(campaign_map, "spend_amount_minor")
  let currency = required_string(campaign_map, "currency")
  let budget = money(budget_minor, currency)
  let campaign_name = required_string(campaign_map, "name")
  let campaign = @marketing.MarketingCampaign::new(
    campaign_id~,
    principal_id~,
    project_scope=scope,
    name=campaign_name,
    budget~,
    actor_id="migration",
    grant=grant(principal_id, "marketing:campaign:create", scope, budget_minor),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }
  let campaign = campaign.activate(
    actor_id="migration",
    grant=grant(
      principal_id, "marketing:campaign:activate", scope, budget_minor,
    ),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }

  let placement_map = object(required(root, "placement"))
  let placement_id = required_string(placement_map, "placement_id")
  let channel = required_string(placement_map, "channel")
  let placement_minor = required_int64(placement_map, "amount_minor")
  let placement_amount = money(placement_minor, currency)
  let placement = @marketing.MarketingPlacement::new(
    placement_id~,
    campaign,
    channel~,
    amount=placement_amount,
    actor_id="migration",
    grant=grant(
      principal_id, "marketing:placement:create", scope, placement_minor,
    ),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }
  let leads = required_int64(placement_map, "leads")
  let placement = placement.place(
    leads=leads.to_int(),
    actor_id="migration",
    grant=grant(
      principal_id, "marketing:placement:place", scope, placement_minor,
    ),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }
  let spend_amount = money(spend_minor, currency)
  let campaign = campaign.record_spend(
    amount=spend_amount,
    actor_id="migration",
    grant=grant(principal_id, "marketing:spend", scope, spend_minor),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }
  let campaign = campaign.complete(
    actor_id="migration",
    grant=grant(principal_id, "marketing:campaign:complete", scope, spend_minor),
  ) catch {
    error => raise MarketingCohortError::Marketing(error)
  }

  let accepted : Array[Json] = []
  accepted.push(
    item(
      required_string(campaign_map, "source_table"),
      required_string(campaign_map, "source_id"),
      "marketing_campaign",
      campaign.campaign_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "campaign_id": Json::string(campaign.campaign_id),
        "principal_id": Json::string(campaign.principal_id),
        "scope": Json::string(campaign.project_scope),
        "name": Json::string(campaign.name),
        "budget_amount_minor": number(campaign.budget.minor),
        "actual_cost_minor": number(campaign.actual_cost.minor),
        "amount_minor": number(campaign.actual_cost.minor),
        "currency": Json::string(campaign.budget.currency),
        "state": Json::string(campaign_state_name(campaign.state)),
        "budget_consumed": Json::boolean(false),
        "provider_called": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  accepted.push(
    item(
      required_string(placement_map, "source_table"),
      required_string(placement_map, "source_id"),
      "marketing_placement",
      placement.placement_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "placement_id": Json::string(placement.placement_id),
        "campaign_id": Json::string(placement.campaign_id),
        "principal_id": Json::string(placement.principal_id),
        "scope": Json::string(placement.project_scope),
        "channel": Json::string(placement.channel),
        "amount_minor": number(placement.amount.minor),
        "currency": Json::string(placement.amount.currency),
        "leads": number(placement.leads.to_int64()),
        "state": Json::string(placement_state_name(placement.state)),
        "provider_called": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let channel_map = object(required(root, "channel"))
  accepted.push(
    item(
      required_string(channel_map, "source_table"),
      required_string(channel_map, "source_id"),
      "marketing_channel",
      required_string(channel_map, "channel_id"),
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "channel_id": Json::string(required_string(channel_map, "channel_id")),
        "channel_code": Json::string(
          required_string(channel_map, "channel_code"),
        ),
        "name": Json::string(required_string(channel_map, "name")),
        "evidence_state": Json::string("catalog_evidence_only"),
        "budget_consumed": Json::boolean(false),
        "provider_called": Json::boolean(false),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  let material_map = object(required(root, "material"))
  accepted.push(
    item(
      required_string(material_map, "source_table"),
      required_string(material_map, "source_id"),
      "marketing_material",
      required_string(material_map, "material_id"),
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "material_id": Json::string(
          required_string(material_map, "material_id"),
        ),
        "material_code": Json::string(
          required_string(material_map, "material_code"),
        ),
        "name": Json::string(required_string(material_map, "name")),
        "evidence_state": Json::string("catalog_evidence_only"),
        "budget_consumed": Json::boolean(false),
        "provider_called": Json::boolean(false),
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
    "cohort": Json::string("marketing-cohort-v1"),
    "accepted_items": Json::array(accepted),
    "budget_consumed": Json::boolean(false),
    "provider_called": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise MarketingCohortError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: marketing_cohort <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      MarketingCohortError::InvalidInput => {
        println("marketing cohort failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      MarketingCohortError::Io(_) => {
        println("marketing cohort failed: filesystem error")
        @sys.exit(1)
      }
      MarketingCohortError::Money(_) => {
        println("marketing cohort failed: money validation")
        @sys.exit(1)
      }
      MarketingCohortError::Marketing(_) => {
        println("marketing cohort failed: marketing validation")
        @sys.exit(1)
      }
    }
  }
}
