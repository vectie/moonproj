///|
pub(all) suberror MarketingCohortPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> MarketingCohortPlanError {
  MarketingCohortPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise MarketingCohortPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise MarketingCohortPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise MarketingCohortPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn required_string(
  value : Json,
  key : String,
) -> String raise MarketingCohortPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_bool(
  value : Json,
  key : String,
) -> Bool raise MarketingCohortPlanError {
  match value {
    True => true
    False => false
    _ => raise fail(key + " must be boolean")
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim()
  if source.is_empty() {
    return default
  }
  let mut index = 0
  let mut sign : Int64 = 1
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut result : Int64 = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return default
    }
    result = result * 10 + (char.to_int() - '0'.to_int()).to_int64()
    index += 1
  }
  result * sign
}

///|
fn integer(
  value : Json,
  key : String,
  minimum : Int64,
) -> Int64 raise MarketingCohortPlanError {
  let result = match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), 0L)
    _ => raise fail(key + " must be an integer >= " + minimum.to_string())
  }
  if result < minimum {
    raise fail(key + " must be an integer >= " + minimum.to_string())
  }
  result
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
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise MarketingCohortPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secrets(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn source_fields(
  value : Map[String, Json],
  path : String,
) -> (String, String) raise MarketingCohortPlanError {
  (
    required_string(
      value.get("source_table").unwrap_or(Json::null()),
      path + ".source_table",
    ),
    required_string(
      value.get("source_id").unwrap_or(Json::null()),
      path + ".source_id",
    ),
  )
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise MarketingCohortPlanError {
  let config_value = read_json(mapping_path)
  reject_secrets(config_value, "mapping")
  let config = object(config_value, "mapping")
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.marketing-cohort-map.v1" ||
    !required_bool(field(Json::object(config), "reviewed"), "reviewed") {
    raise fail("marketing map is not reviewed")
  }
  let snapshot = required_string(
    field(Json::object(config), "source_snapshot_id"),
    "source_snapshot_id",
  )
  let mapping_version = required_string(
    field(Json::object(config), "mapping_version"),
    "mapping_version",
  )
  let run_id = required_string(field(Json::object(config), "run_id"), "run_id")
  let campaign = object(field(Json::object(config), "campaign"), "campaign")
  let placement = object(field(Json::object(config), "placement"), "placement")
  let channel = object(field(Json::object(config), "channel"), "channel")
  let material = object(field(Json::object(config), "material"), "material")
  if required_string(
      field(Json::object(campaign), "expected_state"),
      "campaign.expected_state",
    ) !=
    "completed" {
    raise fail("campaign.expected_state must be completed")
  }
  if required_string(
      field(Json::object(placement), "expected_state"),
      "placement.expected_state",
    ) !=
    "placed" {
    raise fail("placement.expected_state must be placed")
  }
  if required_string(
      field(Json::object(channel), "evidence_state"),
      "channel.evidence_state",
    ) !=
    "catalog_evidence_only" ||
    required_string(
      field(Json::object(material), "evidence_state"),
      "material.evidence_state",
    ) !=
    "catalog_evidence_only" {
    raise fail("channel and material must remain catalog_evidence_only")
  }
  let campaign_id = required_string(
    field(Json::object(campaign), "campaign_id"),
    "campaign.campaign_id",
  )
  let placement_campaign = match placement.get("campaign_id") {
    Some(value) => required_string(value, "placement.campaign_id")
    None => campaign_id
  }
  if placement_campaign != campaign_id {
    raise fail("placement.campaign_id differs from campaign")
  }
  let budget = integer(
    field(Json::object(campaign), "budget_amount_minor"),
    "campaign.budget_amount_minor",
    1L,
  )
  let spend = integer(
    field(Json::object(campaign), "spend_amount_minor"),
    "campaign.spend_amount_minor",
    1L,
  )
  let placement_amount = integer(
    field(Json::object(placement), "amount_minor"),
    "placement.amount_minor",
    1L,
  )
  if spend > budget || placement_amount > budget || placement_amount != spend {
    raise fail(
      "marketing spend/placement amount exceeds or differs from budget map",
    )
  }
  let currency = required_string(
    field(Json::object(campaign), "currency"),
    "campaign.currency",
  )
  let placement_currency = match placement.get("currency") {
    Some(value) => required_string(value, "placement.currency")
    None => currency
  }
  if placement_currency != currency {
    raise fail("placement currency differs from campaign")
  }
  let campaign_source = source_fields(campaign, "campaign")
  let placement_source = source_fields(placement, "placement")
  let channel_source = source_fields(channel, "channel")
  let material_source = source_fields(material, "material")
  let report = Json::object({
    "format": Json::string("moonproj.erp.marketing-cohort-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(snapshot),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "campaign": Json::object({
      "source_table": Json::string(campaign_source.0),
      "source_id": Json::string(campaign_source.1),
      "campaign_id": Json::string(campaign_id),
      "principal_id": Json::string(
        required_string(
          field(Json::object(campaign), "principal_id"),
          "campaign.principal_id",
        ),
      ),
      "project_scope": Json::string(
        required_string(
          field(Json::object(campaign), "project_scope"),
          "campaign.project_scope",
        ),
      ),
      "name": Json::string(
        required_string(field(Json::object(campaign), "name"), "campaign.name"),
      ),
      "budget_amount_minor": Json::number(
        budget.to_double(),
        repr=budget.to_string(),
      ),
      "spend_amount_minor": Json::number(
        spend.to_double(),
        repr=spend.to_string(),
      ),
      "currency": Json::string(currency),
    }),
    "placement": Json::object({
      "source_table": Json::string(placement_source.0),
      "source_id": Json::string(placement_source.1),
      "placement_id": Json::string(
        required_string(
          field(Json::object(placement), "placement_id"),
          "placement.placement_id",
        ),
      ),
      "campaign_id": Json::string(campaign_id),
      "channel": Json::string(
        required_string(
          field(Json::object(placement), "channel"),
          "placement.channel",
        ),
      ),
      "amount_minor": Json::number(
        placement_amount.to_double(),
        repr=placement_amount.to_string(),
      ),
      "currency": Json::string(currency),
      "leads": Json::number(
        integer(field(Json::object(placement), "leads"), "placement.leads", 0L).to_double(),
        repr=integer(
          field(Json::object(placement), "leads"),
          "placement.leads",
          0L,
        ).to_string(),
      ),
    }),
    "channel": Json::object({
      "source_table": Json::string(channel_source.0),
      "source_id": Json::string(channel_source.1),
      "channel_id": Json::string(
        required_string(
          field(Json::object(channel), "channel_id"),
          "channel.channel_id",
        ),
      ),
      "channel_code": Json::string(
        required_string(
          field(Json::object(channel), "channel_code"),
          "channel.channel_code",
        ),
      ),
      "name": Json::string(
        required_string(field(Json::object(channel), "name"), "channel.name"),
      ),
      "evidence_state": Json::string("catalog_evidence_only"),
    }),
    "material": Json::object({
      "source_table": Json::string(material_source.0),
      "source_id": Json::string(material_source.1),
      "material_id": Json::string(
        required_string(
          field(Json::object(material), "material_id"),
          "material.material_id",
        ),
      ),
      "material_code": Json::string(
        required_string(
          field(Json::object(material), "material_code"),
          "material.material_code",
        ),
      ),
      "name": Json::string(
        required_string(field(Json::object(material), "name"), "material.name"),
      ),
      "evidence_state": Json::string("catalog_evidence_only"),
    }),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise MarketingCohortPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(4.0, repr="4"),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: marketing_cohort_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    MarketingCohortPlanError::InvalidInput(message) => {
      println("marketing cohort plan failed: " + message)
      @sys.exit(1)
    }
    MarketingCohortPlanError::Io(_) => {
      println("marketing cohort plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
