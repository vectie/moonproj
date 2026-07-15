///|
/// Compile a reviewed financing-facility map. This names explicit facility
/// operations but grants no lender, cash, or accounting authority.
pub(all) suberror FinancingFacilityPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> FinancingFacilityPlanError {
  FinancingFacilityPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise FinancingFacilityPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise FinancingFacilityPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise FinancingFacilityPlanError {
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
) -> Json raise FinancingFacilityPlanError {
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
) -> String raise FinancingFacilityPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise FinancingFacilityPlanError {
  match required(fields, key, path) {
    True => true
    False => false
    _ => raise fail("expected boolean at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise FinancingFacilityPlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise FinancingFacilityPlanError {
  match required(fields, key, path) {
    Array(values) if !values.is_empty() => values
    _ => raise fail("expected non-empty array at " + path + "." + key)
  }
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
) -> Unit raise FinancingFacilityPlanError {
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
) -> Unit raise FinancingFacilityPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.financing-facility-map.v1" {
    raise fail("unexpected financing map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("financing map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let facilities = required_array(root, "facilities", "mapping")
  let seen_facility_ids : Array[String] = []
  let normalized : Array[Json] = []
  for index in 0..<facilities.length() {
    let path = "facilities[" + index.to_string() + "]"
    let facility = object(facilities[index], path)
    let source_table = required_string(facility, "source_table", path)
    let source_id = required_string(facility, "source_id", path)
    let facility_id = required_string(facility, "facility_id", path)
    let principal_id = required_string(facility, "principal_id", path)
    let project_scope = required_string(facility, "project_scope", path)
    let lender_id = required_string(facility, "lender_id", path)
    let currency = required_string(facility, "currency", path)
    let limit_minor = required_int(facility, "limit_amount_minor", path)
    let annual_rate_bps = required_int(facility, "annual_rate_bps", path)
    let draw_minor = required_int(facility, "draw_amount_minor", path)
    let repay_minor = required_int(facility, "repay_amount_minor", path)
    let interest_days = required_int(facility, "interest_days", path)
    let expected_state = required_string(facility, "expected_state", path)
    if limit_minor < 1 ||
      annual_rate_bps < 0 ||
      annual_rate_bps > 10000 ||
      draw_minor < 0 ||
      repay_minor < 0 ||
      interest_days < 0 {
      raise fail(
        "facility amount/rate/day is outside the allowed range at " + path,
      )
    }
    if draw_minor > limit_minor {
      raise fail("draw_amount_minor exceeds facility limit at " + path)
    }
    if repay_minor > draw_minor {
      raise fail("repay_amount_minor exceeds draw amount at " + path)
    }
    if expected_state != "active" &&
      expected_state != "partially_repaid" &&
      expected_state != "closed" &&
      expected_state != "defaulted" {
      raise fail("invalid expected_state at " + path)
    }
    if seen_facility_ids.contains(facility_id) {
      raise fail("duplicate facility_id: " + facility_id)
    }
    seen_facility_ids.push(facility_id)
    normalized.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "facility_id": Json::string(facility_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "lender_id": Json::string(lender_id),
        "currency": Json::string(currency),
        "limit_amount_minor": number(limit_minor),
        "annual_rate_bps": number(annual_rate_bps),
        "draw_amount_minor": number(draw_minor),
        "repay_amount_minor": number(repay_minor),
        "interest_days": number(interest_days),
        "expected_state": Json::string(expected_state),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.financing-facility-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "facilities": number(normalized.length().to_int64()),
    }),
    "facilities": Json::array(normalized),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise FinancingFacilityPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "facilities": number(normalized.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: financing_facility_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    FinancingFacilityPlanError::InvalidInput(message) => {
      println("financing plan failed: " + message)
      @sys.exit(1)
    }
    FinancingFacilityPlanError::Io(_) => {
      println("financing plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
