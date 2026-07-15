///|
/// Compile a reviewed asset lifecycle map. The plan preserves capitalization,
/// depreciation, impairment, disposal, and account evidence without authorizing
/// journal posting, cash settlement, or period close.
pub(all) suberror AssetLifecyclePlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> AssetLifecyclePlanError {
  AssetLifecyclePlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AssetLifecyclePlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AssetLifecyclePlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AssetLifecyclePlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise AssetLifecyclePlanError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise AssetLifecyclePlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  key : String,
  fallback : Bool,
  path : String,
) -> Bool raise AssetLifecyclePlanError {
  match fields.get(key) {
    None => fallback
    Some(True) => true
    Some(False) => false
    Some(_) => raise fail("expected boolean at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise AssetLifecyclePlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise AssetLifecyclePlanError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail("expected array at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise AssetLifecyclePlanError {
  let values = array(fields, key, path)
  if values.is_empty() {
    raise fail("expected non-empty array at " + path + "." + key)
  }
  values
}

///|
fn secret_key(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.has_suffix("ip")
}

///|
fn reject_secret_keys(
  value : Json,
  path : String,
) -> Unit raise AssetLifecyclePlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secret_keys(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secret_keys(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise AssetLifecyclePlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.asset-lifecycle-map.v1" {
    raise fail("unexpected asset lifecycle map format")
  }
  match required(root, "reviewed", "mapping") {
    True => ()
    _ => raise fail("asset lifecycle map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let assets = required_array(root, "assets", "mapping")
  let seen : Array[String] = []
  let normalized : Array[Json] = []
  let mut depreciation_period_count : Int64 = 0
  let mut disposal_count : Int64 = 0
  for index in 0..<assets.length() {
    let path = "assets[" + index.to_string() + "]"
    let asset = object(assets[index], path)
    let source_table = required_string(asset, "source_table", path)
    let source_id = required_string(asset, "source_id", path)
    let asset_id = required_string(asset, "asset_id", path)
    let principal_id = required_string(asset, "principal_id", path)
    let project_scope = required_string(asset, "project_scope", path)
    let description = required_string(asset, "description", path)
    let currency = required_string(asset, "currency", path)
    let acquisition = required_int(asset, "acquisition_cost_minor", path)
    let residual = required_int(asset, "residual_value_minor", path)
    let useful_life = required_int(asset, "useful_life_months", path)
    let expected_state = required_string(asset, "expected_state", path)
    let impair_before_disposal = optional_bool(
      asset, "impair_before_disposal", false, path,
    )
    let periods = array(asset, "depreciation_periods", path)
    let proceeds = required_int(asset, "disposal_proceeds_minor", path)
    if acquisition < 1 ||
      residual < 0 ||
      useful_life < 1 ||
      residual > acquisition ||
      proceeds < 0 {
      raise fail(
        "asset amount or useful life is outside the allowed range at " + path,
      )
    }
    if expected_state != "active" &&
      expected_state != "impaired" &&
      expected_state != "disposed" {
      raise fail("invalid expected_state at " + path)
    }
    if expected_state == "impaired" && !impair_before_disposal {
      raise fail("impaired state requires impairment evidence at " + path)
    }
    if expected_state != "disposed" &&
      impair_before_disposal &&
      expected_state != "impaired" {
      raise fail("impair_before_disposal is inconsistent at " + path)
    }
    if expected_state != "disposed" && proceeds != 0 {
      raise fail("disposal proceeds require disposed state at " + path)
    }
    if seen.contains(asset_id) {
      raise fail("duplicate asset_id: " + asset_id)
    }
    seen.push(asset_id)
    let period_ids : Array[String] = []
    let normalized_periods : Array[Json] = []
    for period_index in 0..<periods.length() {
      let period_path = path +
        ".depreciation_periods[" +
        period_index.to_string() +
        "]"
      let period = object(periods[period_index], period_path)
      let period_id = required_string(period, "period_id", period_path)
      if period_ids.contains(period_id) {
        raise fail("duplicate depreciation period: " + period_id)
      }
      period_ids.push(period_id)
      normalized_periods.push(
        Json::object({ "period_id": Json::string(period_id) }),
      )
      depreciation_period_count += 1
    }
    let accounts = object(required(asset, "accounts", path), path + ".accounts")
    let account_names = [
      "depreciation_expense_account", "accumulated_depreciation_account", "cash_or_receivable_account",
      "asset_account", "gain_account", "loss_account",
    ]
    let account_values : Array[(String, Json)] = []
    for account_name in account_names {
      account_values.push(
        (
          account_name,
          Json::string(
            required_string(accounts, account_name, path + ".accounts"),
          ),
        ),
      )
    }
    if expected_state == "disposed" {
      disposal_count += 1
    }
    normalized.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "asset_id": Json::string(asset_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "description": Json::string(description),
        "currency": Json::string(currency),
        "acquisition_cost_minor": number(acquisition),
        "residual_value_minor": number(residual),
        "useful_life_months": number(useful_life),
        "expected_state": Json::string(expected_state),
        "impair_before_disposal": Json::boolean(impair_before_disposal),
        "depreciation_periods": Json::array(normalized_periods),
        "disposal_proceeds_minor": number(proceeds),
        "accounts": Json::object(Map::Map(account_values)),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.asset-lifecycle-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "assets": number(normalized.length().to_int64()),
      "depreciation_periods": number(depreciation_period_count),
      "disposals": number(disposal_count),
    }),
    "assets": Json::array(normalized),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise AssetLifecyclePlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "assets": number(normalized.length().to_int64()),
      "depreciation_periods": number(depreciation_period_count),
      "disposals": number(disposal_count),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: asset_lifecycle_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    AssetLifecyclePlanError::InvalidInput(message) => {
      println("asset lifecycle plan failed: " + message)
      @sys.exit(1)
    }
    AssetLifecyclePlanError::Io(_) => {
      println("asset lifecycle plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
