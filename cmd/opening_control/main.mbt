///|
pub(all) suberror ControlPromotionError {
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Control(@control.ControlError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ControlPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ControlPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ControlPromotionError {
  match value {
    Object(value) => value
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ControlPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise ControlPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ControlPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ControlPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise ControlPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ControlPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ControlPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ControlPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.opening-control-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise ControlPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let mut controls = @control.OpeningControlSet::new(source_snapshot_id~) catch {
    error => raise ControlPromotionError::Control(error)
  }
  let accepted : Array[Json] = []
  for control_value in required_array(root, "controls") {
    let control_obj = object(control_value)
    let metric_id = required_string(control_obj, "metric_id")
    let domain = required_string(control_obj, "domain")
    let dimension = required_string(control_obj, "dimension")
    let value = required_int64(control_obj, "value")
    let tolerance = required_int64(control_obj, "tolerance")
    let unit = required_string(control_obj, "unit")
    controls = controls.add({ metric_id, domain, dimension, value, tolerance }) catch {
      error => raise ControlPromotionError::Control(error)
    }
    accepted.push(
      Json::object({
        "source_table": Json::string("opening_control"),
        "source_id": Json::string(metric_id),
        "target_type": Json::string("opening_control_total"),
        "target_id": Json::string(metric_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "metric_id": Json::string(metric_id),
          "domain": Json::string(domain),
          "dimension": Json::string(dimension),
          "value": number(value),
          "tolerance": number(tolerance),
          "unit": Json::string(unit),
          "control_state": Json::string("reviewed"),
          "shadow_plan_compiled": Json::boolean(true),
          "accounting_posted": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  let shadow_plan = controls.to_shadow_plan(run_id~) catch {
    error => raise ControlPromotionError::Control(error)
  }
  if accepted.length() == 0 ||
    shadow_plan.expectations.length() != accepted.length() {
    raise ControlPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("opening-control-v1"),
    "accepted_items": Json::array(accepted),
    "control_count": number(shadow_plan.expectations.length().to_int64()),
    "shadow": Json::object({
      "run_id": Json::string(run_id),
      "state": Json::string("control_set_compiled"),
      "comparison_mode": Json::string("provided_control_totals"),
      "expectation_count": number(shadow_plan.expectations.length().to_int64()),
    }),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise ControlPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: opening_control <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ControlPromotionError::Quarantined(source) => {
        println("opening-control refused quarantined item: " + source)
        @sys.exit(1)
      }
      ControlPromotionError::InvalidInput => {
        println("opening-control failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      ControlPromotionError::Io(_) => {
        println("opening-control failed: filesystem error")
        @sys.exit(1)
      }
      ControlPromotionError::Control(_) => {
        println("opening-control failed: control invariant")
        @sys.exit(1)
      }
    }
  }
}
