///|
pub(all) suberror LifecyclePromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> LifecyclePromotionPlanError {
  LifecyclePromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise LifecyclePromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise LifecyclePromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise LifecyclePromotionPlanError {
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
fn field_or(value : Json, key : String, fallback : Json) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(fallback)
    _ => fallback
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(value, ..) => value.to_int().to_int64()
    String(value) => parse_integer(value, default)
    _ => default
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim().to_owned()
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
fn progress_bps(value : Json) -> Int64 raise LifecyclePromotionPlanError {
  let source = match value {
    Null => "0"
    Number(_, ..) => value.stringify()
    String(value) => value
    _ => raise fail("invalid lifecycle progress: " + value.stringify())
  }
  let source = source.trim().to_owned()
  if source.is_empty() {
    raise fail("invalid lifecycle progress: " + source)
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
  let mut numerator : Int64 = 0
  let mut denominator : Int64 = 1
  let mut after_decimal = false
  let mut digit_count = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char == '.' {
      if after_decimal {
        raise fail("invalid lifecycle progress: " + source)
      }
      after_decimal = true
    } else if char >= '0' && char <= '9' {
      numerator = numerator * 10 + (char.to_int() - '0'.to_int()).to_int64()
      digit_count += 1
      if after_decimal {
        denominator *= 10
      }
    } else {
      raise fail("invalid lifecycle progress: " + source)
    }
    index += 1
  }
  if digit_count == 0 {
    raise fail("invalid lifecycle progress: " + source)
  }
  let scaled = numerator * 100
  let quotient = scaled / denominator
  let remainder = scaled % denominator
  let rounded = if remainder * 2 > denominator ||
    (remainder * 2 == denominator && quotient % 2 == 1) {
    quotient + 1
  } else {
    quotient
  }
  let result = rounded * sign
  if result < 0 || result > 10000 {
    raise fail("lifecycle progress outside 0..10000 bps: " + result.to_string())
  }
  result
}

///|
fn sorted_reasons(values : Array[String]) -> Json {
  let unique : Array[String] = []
  for value in values {
    let mut found = false
    for existing in unique {
      if existing == value {
        found = true
      }
    }
    if !found {
      unique.push(value)
    }
  }
  unique.sort_by(fn(left, right) { left.compare(right) })
  Json::array(unique.map(fn(value) { Json::string(value) }))
}

///|
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    String(value) => !value.is_empty()
    Number(value, ..) => value != 0.0
    _ => true
  }
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise LifecyclePromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let stage_map = match config.get("lifecycle_stage_by_code") {
    None => {}
    Some(value) => object(value, "lifecycle_stage_by_code")
  }
  let projects = match read_json(export_dir + "/tables/ep_project.json") {
    Array(values) => values
    _ => raise fail("project export must be an array")
  }
  let instances = match
    read_json(export_dir + "/tables/proj_lifecycle_instance.json") {
    Array(values) => values
    _ => raise fail("lifecycle export must be an array")
  }
  let project_items : Array[Json] = []
  let lifecycle_items : Array[Json] = []
  for project in projects {
    let project_id = text(field(project, "proj_guid"))
    let bu_id = text(field(project, "bu_guid"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let project_reasons : Array[String] = []
    if !truthy(principal) {
      project_reasons.push("missing_principal_by_bu")
    }
    project_items.push(
      Json::object({
        "source_table": Json::string("ep_project"),
        "source_id": Json::string(project_id),
        "target_type": Json::string("project"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if project_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": Json::array(
          project_reasons.map(fn(value) { Json::string(value) }),
        ),
        "warnings": Json::array([]),
        "target_candidate": if project_reasons.is_empty() {
          Json::object({
            "project_id": Json::string(project_id),
            "principal_id": principal,
            "authority_scope": Json::string("project:" + project_id),
            "code": field(project, "proj_code"),
            "name": field(project, "proj_name"),
            "business_unit_id": Json::string(bu_id),
          })
        } else {
          Json::null()
        },
      }),
    )
    let rows : Array[Json] = []
    for instance in instances {
      if text(field(instance, "proj_guid")) == project_id {
        rows.push(instance)
      }
    }
    rows.sort_by(fn(left, right) {
      integer(field(left, "instance_id"), 0L).compare(
        integer(field(right, "instance_id"), 0L),
      )
    })
    let lifecycle_reasons : Array[String] = []
    if !truthy(principal) {
      lifecycle_reasons.push("missing_principal_by_bu")
    }
    let candidates : Array[Json] = []
    for row in rows {
      let source_code = text(field(row, "stage_code"))
      if stage_map.get(source_code) is None {
        lifecycle_reasons.push("missing_stage_mapping:" + source_code)
      }
      let instance_id = text(field(row, "instance_id"))
      candidates.push(
        Json::object({
          "instance_id": Json::string(instance_id),
          "proj_guid": Json::string(project_id),
          "stage_code": Json::string(source_code),
          "planned_start": field(row, "planned_start"),
          "planned_end": field(row, "planned_end"),
          "actual_start": field(row, "actual_start"),
          "actual_end": field(row, "actual_end"),
          "status": field(row, "status"),
          "progress_bps": Json::number(
            progress_bps(
              field_or(row, "progress_pct", Json::number(0.0, repr="0.0")),
            ).to_double(),
            repr=progress_bps(
              field_or(row, "progress_pct", Json::number(0.0, repr="0.0")),
            ).to_string(),
          ),
        }),
      )
    }
    if rows.is_empty() {
      lifecycle_reasons.push("missing_lifecycle_instances")
    }
    let stage_mappings : Array[Json] = []
    for source, target in stage_map {
      stage_mappings.push(
        Json::object({
          "source_code": Json::string(source),
          "target_stage": target,
        }),
      )
    }
    lifecycle_items.push(
      Json::object({
        "source_table": Json::string("proj_lifecycle_instance"),
        "source_id": Json::string(project_id),
        "target_type": Json::string("project_lifecycle"),
        "target_id": Json::string(project_id),
        "disposition": Json::string(
          if lifecycle_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(lifecycle_reasons),
        "warnings": Json::array([]),
        "target_candidate": if lifecycle_reasons.is_empty() {
          Json::object({
            "project_id": Json::string(project_id),
            "principal_id": principal,
            "authority_scope": Json::string("project:" + project_id),
            "rows": Json::array(candidates),
            "stage_mappings": Json::array(stage_mappings),
          })
        } else {
          Json::null()
        },
      }),
    )
  }
  let items : Array[Json] = []
  for item in project_items {
    items.push(item)
  }
  for item in lifecycle_items {
    items.push(item)
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  let mapping_version = match config.get("mapping_version") {
    Some(value) => value
    None => Json::string("unversioned-lifecycle-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.lifecycle-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha),
    "source_sha256": Json::string(source_sha),
    "mapping_version": mapping_version,
    "summary": Json::object({
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise LifecyclePromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: lifecycle_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    LifecyclePromotionPlanError::InvalidInput(message) => {
      println("lifecycle promotion plan failed: " + message)
      @sys.exit(1)
    }
    LifecyclePromotionPlanError::Io(_) => {
      println("lifecycle promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
