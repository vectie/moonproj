///|
/// Compile a reviewed tax-filing map into the explicit domain promotion plan.
///
/// This is deliberately a narrow, deterministic boundary: it validates source
/// identity, rates, filing authority and final state, but never pays tax,
/// posts accounting, releases cash, or calls an external authority.
pub(all) suberror TaxFilingPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> TaxFilingPlanError {
  TaxFilingPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TaxFilingPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaxFilingPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TaxFilingPlanError {
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
) -> Json raise TaxFilingPlanError {
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
) -> String raise TaxFilingPlanError {
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
) -> Bool raise TaxFilingPlanError {
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
) -> Int64 raise TaxFilingPlanError {
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
) -> Array[Json] raise TaxFilingPlanError {
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
) -> Unit raise TaxFilingPlanError {
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
) -> Unit raise TaxFilingPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.tax-filing-map.v1" {
    raise fail("unexpected tax-filing map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("tax-filing map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let filings = required_array(root, "filings", "mapping")
  let seen_filing_ids : Array[String] = []
  let seen_source_ids : Array[String] = []
  let normalized : Array[Json] = []
  for index in 0..<filings.length() {
    let path = "filings[" + index.to_string() + "]"
    let filing = object(filings[index], path)
    let source_table = required_string(filing, "source_table", path)
    let source_id = required_string(filing, "source_id", path)
    let tax_id = required_string(filing, "tax_id", path)
    let filing_id = required_string(filing, "filing_id", path)
    let principal_id = required_string(filing, "principal_id", path)
    let project_scope = required_string(filing, "project_scope", path)
    let source_reference = required_string(filing, "source_reference", path)
    let jurisdiction = required_string(filing, "jurisdiction", path)
    let category = required_string(filing, "category", path)
    let currency = required_string(filing, "currency", path)
    let base_amount_minor = required_int(filing, "base_amount_minor", path)
    let tax_rate_bps = required_int(filing, "tax_rate_bps", path)
    let withholding_rate_bps = required_int(
      filing, "withholding_rate_bps", path,
    )
    let filing_period = required_string(filing, "filing_period", path)
    let authority_reference = required_string(
      filing, "authority_reference", path,
    )
    let final_state = required_string(filing, "final_state", path)
    if base_amount_minor < 1 ||
      tax_rate_bps < 0 ||
      tax_rate_bps > 10000 ||
      withholding_rate_bps < 0 ||
      withholding_rate_bps > 10000 {
      raise fail("invalid amount or rate at " + path)
    }
    if final_state != "submitted" &&
      final_state != "accepted" &&
      final_state != "rejected" {
      raise fail("invalid final_state at " + path)
    }
    if seen_filing_ids.contains(filing_id) {
      raise fail("duplicate filing_id: " + filing_id)
    }
    if seen_source_ids.contains(source_id) {
      raise fail("duplicate source_id: " + source_id)
    }
    seen_filing_ids.push(filing_id)
    seen_source_ids.push(source_id)
    normalized.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "tax_id": Json::string(tax_id),
        "filing_id": Json::string(filing_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "source_reference": Json::string(source_reference),
        "jurisdiction": Json::string(jurisdiction),
        "category": Json::string(category),
        "currency": Json::string(currency),
        "base_amount_minor": number(base_amount_minor),
        "tax_rate_bps": number(tax_rate_bps),
        "withholding_rate_bps": number(withholding_rate_bps),
        "filing_period": Json::string(filing_period),
        "authority_reference": Json::string(authority_reference),
        "final_state": Json::string(final_state),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.tax-filing-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "filings": number(normalized.length().to_int64()),
    }),
    "filings": Json::array(normalized),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise TaxFilingPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "filings": number(normalized.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: tax_filing_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    TaxFilingPlanError::InvalidInput(message) => {
      println("tax-filing plan failed: " + message)
      @sys.exit(1)
    }
    TaxFilingPlanError::Io(_) => {
      println("tax-filing plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
