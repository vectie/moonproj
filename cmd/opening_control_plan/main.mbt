///|
/// Compile a reviewed opening-control map into explicit shadow expectations.
/// Controls are evidence, not inferred balances or posting instructions.
pub(all) suberror OpeningControlPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> OpeningControlPlanError {
  OpeningControlPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise OpeningControlPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise OpeningControlPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise OpeningControlPlanError {
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
) -> Json raise OpeningControlPlanError {
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
) -> String raise OpeningControlPlanError {
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
) -> Bool raise OpeningControlPlanError {
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
) -> Int64 raise OpeningControlPlanError {
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
) -> Array[Json] raise OpeningControlPlanError {
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
) -> Unit raise OpeningControlPlanError {
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
) -> Unit raise OpeningControlPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.opening-control-map.v1" {
    raise fail("unexpected opening-control map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("opening-control map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let controls = required_array(root, "controls", "mapping")
  let seen : Array[String] = []
  let normalized : Array[Json] = []
  for index in 0..<controls.length() {
    let path = "controls[" + index.to_string() + "]"
    let control = object(controls[index], path)
    let metric_id = required_string(control, "metric_id", path)
    let domain = required_string(control, "domain", path)
    let dimension = required_string(control, "dimension", path)
    let value = required_int(control, "value", path)
    let tolerance = required_int(control, "tolerance", path)
    let unit = required_string(control, "unit", path)
    if value < 0 || tolerance < 0 {
      raise fail("value and tolerance must be non-negative at " + path)
    }
    if seen.contains(metric_id) {
      raise fail("duplicate metric_id: " + metric_id)
    }
    seen.push(metric_id)
    normalized.push(
      Json::object({
        "metric_id": Json::string(metric_id),
        "domain": Json::string(domain),
        "dimension": Json::string(dimension),
        "value": number(value),
        "tolerance": number(tolerance),
        "unit": Json::string(unit),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.opening-control-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "controls": number(normalized.length().to_int64()),
    }),
    "controls": Json::array(normalized),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise OpeningControlPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "controls": number(normalized.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: opening_control_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    OpeningControlPlanError::InvalidInput(message) => {
      println("opening-control plan failed: " + message)
      @sys.exit(1)
    }
    OpeningControlPlanError::Io(_) => {
      println("opening-control plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
