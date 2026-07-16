///|
pub(all) suberror ShadowPeriodError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ShadowPeriodError {
  ShadowPeriodError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ShadowPeriodError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ShadowPeriodError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON evidence: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ShadowPeriodError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object: " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ShadowPeriodError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing " + key + ": " + path)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ShadowPeriodError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("missing non-empty field: " + key)
  }
}

///|
fn array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ShadowPeriodError {
  match required(fields, key, path) {
    Array(values) => values
    _ => raise fail(key + " must be an array")
  }
}

///|
fn reject_secrets(value : Json, path : String) -> Unit raise ShadowPeriodError {
  match value {
    Object(fields) =>
      for key, child in fields {
        let lowered = key.to_lower()
        if lowered.contains("password") ||
          lowered.contains("secret") ||
          lowered.contains("token") ||
          lowered.contains("private") ||
          lowered.contains("credential") {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn positive_int(
  fields : Map[String, Json],
  key : String,
  maximum : Int,
  path : String,
) -> Int raise ShadowPeriodError {
  let value = match required(fields, key, path) {
    Number(number, ..) if number == number.trunc() => number.to_int()
    _ => raise fail(key + " must be a positive integer")
  }
  if value <= 0 || value > maximum {
    raise fail(key + " exceeds " + maximum.to_string())
  }
  value
}

///|
fn strings(values : Array[Json]) -> Array[String] raise ShadowPeriodError {
  if values.is_empty() {
    raise fail("comparison_dimensions must be a non-empty string array")
  }
  let result : Array[String] = []
  for value in values {
    match value {
      String(text) if !text.trim().is_empty() => result.push(text)
      _ => raise fail("comparison_dimensions must be a non-empty string array")
    }
  }
  result
}

///|
fn strings_json(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn validate(
  work_dir : String,
  manifest : Json,
  parity_paths : Array[String],
  reconciliation_paths : Array[String],
) -> Json raise ShadowPeriodError {
  let root = object(manifest, "manifest")
  reject_secrets(manifest, "manifest")
  if required_string(root, "format", "manifest") !=
    "moonproj.company.shadow-period.v1" {
    raise fail("unsupported shadow-period format")
  }
  let period_id = required_string(root, "period_id", "manifest")
  let owner_role = required_string(root, "owner_role", "manifest")
  let rollback_runbook = required_string(root, "rollback_runbook", "manifest")
  if root.get("legacy_authoritative") != Some(Json::boolean(true)) {
    raise fail("legacy_authoritative must remain true during shadow")
  }
  if root.get("target_mode") != Some(Json::string("read_only_shadow")) {
    raise fail("target_mode must be read_only_shadow")
  }
  if root.get("target_mutations_allowed") != Some(Json::boolean(false)) {
    raise fail("target mutations must be disabled during shadow")
  }
  let duration_days = positive_int(root, "duration_days", 90, "manifest")
  let comparison_interval_hours = positive_int(
    root, "comparison_interval_hours", 168, "manifest",
  )
  let dimensions = strings(array(root, "comparison_dimensions", "manifest"))
  if parity_paths.is_empty() {
    raise fail("all projection parity reports must be shadow_verified")
  }
  for path in parity_paths {
    let report = object(read_json(path), path)
    if report.get("state") != Some(Json::string("shadow_verified")) {
      raise fail("all projection parity reports must be shadow_verified")
    }
  }
  let row_coverage = object(
    read_json(work_dir + "/row-coverage.json"),
    "row coverage",
  )
  if row_coverage.get("state") != Some(Json::string("row_coverage_verified")) {
    raise fail("row coverage is not verified")
  }
  if reconciliation_paths.is_empty() {
    raise fail(
      "accounting reconciliation evidence is missing or has external effects",
    )
  }
  for path in reconciliation_paths {
    let report = object(read_json(path), path)
    if report.get("state") != Some(Json::string("reconciled")) ||
      report.get("cash_released") != Some(Json::boolean(false)) ||
      report.get("period_posted") != Some(Json::boolean(false)) {
      raise fail(
        "accounting reconciliation evidence is missing or has external effects",
      )
    }
  }
  let acceptance = object(
    read_json(work_dir + "/business-acceptance.json"),
    "business acceptance",
  )
  if acceptance.get("format") !=
    Some(Json::string("moonproj.erp.business-acceptance-result.v1")) {
    raise fail("business acceptance packet is missing or invalid")
  }
  let decisions = match acceptance.get("decisions") {
    Some(Array(values)) => values
    _ => []
  }
  let mut shadow_authorized = false
  for decision in decisions {
    let fields = match decision {
      Object(fields) => fields
      _ => continue
    }
    if fields.get("id") == Some(Json::string("shadow-period")) {
      shadow_authorized = fields.get("decision") ==
        Some(Json::string("accept_for_shadow"))
    }
  }
  Json::object({
    "format": Json::string("moonproj.company.shadow-period-result.v1"),
    "period_id": Json::string(period_id),
    "state": Json::string(
      if shadow_authorized {
        "shadow_ready"
      } else {
        "shadow_pending_owner"
      },
    ),
    "legacy_authoritative": Json::boolean(true),
    "target_mode": Json::string("read_only_shadow"),
    "target_mutations_allowed": Json::boolean(false),
    "duration_days": Json::number(
      duration_days.to_double(),
      repr=duration_days.to_string(),
    ),
    "comparison_interval_hours": Json::number(
      comparison_interval_hours.to_double(),
      repr=comparison_interval_hours.to_string(),
    ),
    "comparison_dimensions": strings_json(dimensions),
    "parity_report_count": Json::number(
      parity_paths.length().to_double(),
      repr=parity_paths.length().to_string(),
    ),
    "reconciliation_report_count": Json::number(
      reconciliation_paths.length().to_double(),
      repr=reconciliation_paths.length().to_string(),
    ),
    "source_rows": row_coverage.get("source_rows").unwrap_or(Json::null()),
    "covered_rows": row_coverage.get("covered_rows").unwrap_or(Json::null()),
    "owner_role": Json::string(owner_role),
    "rollback_runbook": Json::string(rollback_runbook),
    "shadow_authorized": Json::boolean(shadow_authorized),
    "cutover_authorized": Json::boolean(false),
  })
}

///|
fn result_field(result : Json, key : String) -> Json {
  match result {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 5 {
    println(
      "usage: shadow_period_check <work_dir> <manifest> <output> <parity...> --reconciliations <reconciliation...>",
    )
    @sys.exit(2)
  } else {
    let mut marker = -1
    for index in 4..<args.length() {
      if args[index] == "--reconciliations" {
        marker = index
      }
    }
    if marker < 0 {
      println("shadow-period check failed: missing reconciliation marker")
      @sys.exit(2)
    }
    let parity_paths : Array[String] = []
    for index in 4..<marker {
      parity_paths.push(args[index])
    }
    let reconciliation_paths : Array[String] = []
    for index in (marker + 1)..<args.length() {
      reconciliation_paths.push(args[index])
    }
    let result = validate(
      args[1],
      read_json(args[2]),
      parity_paths,
      reconciliation_paths,
    ) catch {
      ShadowPeriodError::InvalidInput(message) => {
        println("shadow-period check failed: " + message)
        @sys.exit(1)
        Json::null()
      }
      ShadowPeriodError::Io(_) => {
        println("shadow-period check failed: filesystem error")
        @sys.exit(1)
        Json::null()
      }
    }
    @fs.write_string_to_file(args[3], result.stringify(indent=2) + "\n") catch {
      _ => {
        println("shadow-period check failed: filesystem error")
        @sys.exit(1)
      }
    }
    println(
      Json::object({
        "output": Json::string(args[3]),
        "state": result_field(result, "state"),
        "shadow_authorized": result_field(result, "shadow_authorized"),
        "target_mutations_allowed": result_field(
          result, "target_mutations_allowed",
        ),
      }).stringify(),
    )
  }
}
