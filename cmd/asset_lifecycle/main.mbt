///|
pub(all) suberror AssetPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Asset(@assets.AssetError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise AssetPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AssetPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise AssetPromotionError {
  match value {
    Object(value) => value
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise AssetPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise AssetPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise AssetPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise AssetPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise AssetPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise AssetPromotionError::InvalidInput
  }
}

///|
fn required_object(
  obj : Map[String, Json],
  key : String,
) -> Map[String, Json] raise AssetPromotionError {
  object(required(obj, key))
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn state_name(value : @assets.AssetState) -> String {
  match value {
    @assets.AssetState::Proposed => "proposed"
    @assets.AssetState::Capitalized => "capitalized"
    @assets.AssetState::Active => "active"
    @assets.AssetState::Impaired => "impaired"
    @assets.AssetState::Disposed => "disposed"
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
    grant_id: "asset-migration/" + capability,
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
) -> @finance.Money raise AssetPromotionError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise AssetPromotionError::Money(error)
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise AssetPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.asset-lifecycle-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise AssetPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  let mut depreciation_count : Int64 = 0L
  let mut disposal_count : Int64 = 0L
  for value in required_array(root, "assets") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let asset_id = required_string(item, "asset_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let description = required_string(item, "description")
    let currency = required_string(item, "currency")
    let acquisition_minor = required_int64(item, "acquisition_cost_minor")
    let residual_minor = required_int64(item, "residual_value_minor")
    let useful_life_months = required_int64(item, "useful_life_months").to_int()
    let expected_state = required_string(item, "expected_state")
    let impair_before_disposal = required_bool(item, "impair_before_disposal")
    let disposal_proceeds_minor = required_int64(
      item, "disposal_proceeds_minor",
    )
    let accounts = required_object(item, "accounts")
    let depreciation_expense_account = required_string(
      accounts, "depreciation_expense_account",
    )
    let accumulated_depreciation_account = required_string(
      accounts, "accumulated_depreciation_account",
    )
    let cash_or_receivable_account = required_string(
      accounts, "cash_or_receivable_account",
    )
    let asset_account = required_string(accounts, "asset_account")
    let gain_account = required_string(accounts, "gain_account")
    let loss_account = required_string(accounts, "loss_account")
    let acquisition_cost = money(acquisition_minor, currency)
    let residual_value = money(residual_minor, currency)
    let asset = @assets.Asset::new(
      asset_id~,
      principal_id~,
      project_scope~,
      description~,
      acquisition_cost~,
      residual_value~,
      useful_life_months~,
      actor_id="migration",
      grant=grant(
        principal_id, "asset:propose", project_scope, acquisition_minor,
      ),
    ) catch {
      error => raise AssetPromotionError::Asset(error)
    }
    let asset = asset.transition(
      @assets.AssetState::Capitalized,
      actor_id="migration",
      grant=grant(
        principal_id, "asset:capitalize", project_scope, acquisition_minor,
      ),
    ) catch {
      error => raise AssetPromotionError::Asset(error)
    }
    let asset = asset.transition(
      @assets.AssetState::Active,
      actor_id="migration",
      grant=grant(
        principal_id, "asset:activate", project_scope, acquisition_minor,
      ),
    ) catch {
      error => raise AssetPromotionError::Asset(error)
    }
    let asset = if impair_before_disposal {
      asset.transition(
        @assets.AssetState::Impaired,
        actor_id="migration",
        grant=grant(
          principal_id, "asset:impair", project_scope, acquisition_minor,
        ),
      ) catch {
        error => raise AssetPromotionError::Asset(error)
      }
    } else {
      asset
    }
    let depreciation_entries : Array[Json] = []
    let mut asset = asset
    for period_value in required_array(item, "depreciation_periods") {
      let period = object(period_value)
      let period_id = required_string(period, "period_id")
      let (next, entry) = asset.depreciate(
        period_id~,
        actor_id="migration",
        grant=grant(
          principal_id, "asset:depreciate", project_scope, acquisition_minor,
        ),
      ) catch {
        error => raise AssetPromotionError::Asset(error)
      }
      let _ = entry.to_journal(
        expense_account=depreciation_expense_account,
        accumulated_depreciation_account~,
      ) catch {
        error => raise AssetPromotionError::Asset(error)
      }
      depreciation_entries.push(
        Json::object({
          "period_id": Json::string(entry.period_id),
          "amount_minor": number(entry.amount.minor),
          "remaining_book_value_minor": number(entry.remaining_book_value_minor),
          "journal_id": Json::string(
            "asset-depreciation/" + entry.asset_id + "/" + entry.period_id,
          ),
        }),
      )
      depreciation_count += 1L
      asset = next
    }
    let (asset, disposal) = if expected_state == "disposed" {
      let disposed = asset.transition(
        @assets.AssetState::Disposed,
        actor_id="migration",
        grant=grant(
          principal_id, "asset:dispose", project_scope, acquisition_minor,
        ),
      ) catch {
        error => raise AssetPromotionError::Asset(error)
      }
      let proceeds = money(disposal_proceeds_minor, currency)
      let basis = disposed.to_disposal_entry(proceeds~) catch {
        error => raise AssetPromotionError::Asset(error)
      }
      let _ = basis.to_journal(
        cash_or_receivable_account~,
        asset_account~,
        accumulated_depreciation_account~,
        gain_account~,
        loss_account~,
      ) catch {
        error => raise AssetPromotionError::Asset(error)
      }
      disposal_count += 1L
      (disposed, Some(basis))
    } else {
      (asset, None)
    }
    if state_name(asset.state) != expected_state {
      raise AssetPromotionError::InvalidInput
    }
    let disposal_json = match disposal {
      Some(basis) =>
        Json::object({
          "proceeds_minor": number(basis.proceeds.minor),
          "acquisition_cost_minor": number(basis.acquisition_cost_minor),
          "accumulated_depreciation_minor": number(
            basis.accumulated_depreciation_minor,
          ),
          "carrying_value_minor": number(basis.carrying_value_minor),
          "gain_loss_minor": number(basis.gain_loss_minor),
          "journal_id": Json::string("asset-disposal/" + basis.asset_id),
        })
      None => Json::null()
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("asset"),
        "target_id": Json::string(asset.asset_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "asset_id": Json::string(asset.asset_id),
          "principal_id": Json::string(asset.principal_id),
          "project_scope": Json::string(asset.project_scope),
          "description": Json::string(asset.description),
          "acquisition_cost_minor": number(asset.acquisition_cost.minor),
          "residual_value_minor": number(asset.residual_value.minor),
          "currency": Json::string(asset.acquisition_cost.currency),
          "useful_life_months": number(asset.useful_life_months.to_int64()),
          "accumulated_depreciation_minor": number(
            asset.accumulated_depreciation,
          ),
          "state": Json::string(state_name(asset.state)),
          "event_count": number(asset.events.length().to_int64()),
          "depreciation_entries": Json::array(depreciation_entries),
          "disposal": disposal_json,
          "asset_reviewed": Json::boolean(true),
          "depreciation_posted": Json::boolean(false),
          "disposal_posted": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise AssetPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("asset-lifecycle-v1"),
    "accepted_items": Json::array(accepted),
    "asset_count": number(accepted.length().to_int64()),
    "depreciation_entry_count": number(depreciation_count),
    "disposal_count": number(disposal_count),
    "depreciation_posted": Json::boolean(false),
    "disposal_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise AssetPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: asset_lifecycle <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      AssetPromotionError::InvalidInput => {
        println("asset lifecycle promotion failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      AssetPromotionError::Io(_) => {
        println("asset lifecycle promotion failed: filesystem error")
        @sys.exit(1)
      }
      AssetPromotionError::Money(_) => {
        println("asset lifecycle promotion failed: money validation")
        @sys.exit(1)
      }
      AssetPromotionError::Asset(_) => {
        println("asset lifecycle promotion failed: asset lifecycle validation")
        @sys.exit(1)
      }
    }
  }
}
