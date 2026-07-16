///|
pub(all) suberror ParameterPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ParameterPromotionPlanError {
  ParameterPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ParameterPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ParameterPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ParameterPromotionPlanError {
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
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    String(value) => !value.is_empty()
    Number(value, ..) => value != 0.0
    _ => true
  }
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) if number == number.trunc() => number.to_int().to_int64()
    String(value) => {
      let source = value.trim()
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
        let c = source.get_char(index).unwrap()
        if c < '0' || c > '9' {
          return default
        }
        result = result * 10 + (c.to_int() - '0'.to_int()).to_int64()
        index += 1
      }
      result * sign
    }
    _ => default
  }
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
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise ParameterPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let mappings = match config.get("parameter_by_name") {
    Some(value) => object(value, "parameter_by_name")
    None => {}
  }
  let source_by_name = match config.get("parameter_source_by_name") {
    Some(value) => object(value, "parameter_source_by_name")
    None => {}
  }
  let allowed_sources : Map[String, Bool] = {
    "my_biz_param_option": true,
    "vys_proceeding": true,
  }
  let proceeding_names : Array[String] = []
  for name, table in source_by_name {
    let table_name = text(table)
    if allowed_sources.get(table_name) is None {
      raise fail("unsupported parameter source: " + table_name)
    }
    if table_name == "vys_proceeding" {
      proceeding_names.push(name)
    }
  }
  if proceeding_names.length() > 1 {
    raise fail("vys_proceeding can map to only one parameter dictionary")
  }
  let source_rows : Map[String, Array[Json]] = {}
  let defaults = match
    read_json(export_dir + "/tables/my_biz_param_option.json") {
    Array(values) => values
    _ => raise fail("parameter export must be an array")
  }
  for row in defaults {
    let name = text(field(row, "param_name"))
    let normalized = Json::object({
      "source_table": Json::string("my_biz_param_option"),
      "parameter_id": Json::string(text(field(row, "id"))),
      "parameter_name": Json::string(name),
      "parameter_code": Json::string(text(field(row, "param_code"))),
      "parameter_value": field(row, "param_value"),
      "display_order": Json::number(
        integer(field(row, "display_order"), 0L).to_double(),
        repr=integer(field(row, "display_order"), 0L).to_string(),
      ),
      "enabled": Json::boolean(truthy(field(row, "enabled"))),
    })
    let group = source_rows.get(name).unwrap_or([])
    group.push(normalized)
    source_rows.set(name, group)
  }
  if proceeding_names.length() == 1 {
    let name = proceeding_names[0]
    let proceeding = match
      read_json(export_dir + "/tables/vys_proceeding.json") {
      Array(values) => values
      _ => raise fail("proceeding export must be an array")
    }
    let group : Array[Json] = []
    let mut index = 0
    for row in proceeding {
      group.push(
        Json::object({
          "source_table": Json::string("vys_proceeding"),
          "parameter_id": Json::string(text(field(row, "proceeding_guid"))),
          "parameter_name": Json::string(name),
          "parameter_code": Json::string(text(field(row, "proceeding_code"))),
          "parameter_value": field(row, "proceeding_name"),
          "display_order": Json::number(
            index.to_double(),
            repr=index.to_string(),
          ),
          "enabled": Json::boolean(truthy(field(row, "enabled"))),
        }),
      )
      index += 1
    }
    source_rows.set(name, group)
  }
  let names : Array[String] = []
  for name, _ in source_rows {
    names.push(name)
  }
  names.sort_by(fn(left, right) { left.compare(right) })
  let items : Array[Json] = []
  for name in names {
    let group = source_rows.get(name).unwrap()
    let mapping = match mappings.get(name) {
      Some(value) => object(value, "parameter mapping")
      None => {}
    }
    let reasons : Array[String] = []
    if name.is_empty() {
      reasons.push("missing_parameter_name")
    }
    if group.is_empty() {
      reasons.push("empty_parameter_group")
    }
    if mappings.get(name) is None {
      reasons.push("missing_parameter_mapping")
    }
    let principal = field(Json::object(mapping), "principal_id")
    let scope = field(Json::object(mapping), "scope")
    if !truthy(principal) || !truthy(scope) {
      reasons.push("incomplete_parameter_mapping")
    }
    group.sort_by(fn(left, right) {
      let order = integer(field(left, "display_order"), 0L).compare(
        integer(field(right, "display_order"), 0L),
      )
      if order == 0 {
        text(field(left, "parameter_id")).compare(
          text(field(right, "parameter_id")),
        )
      } else {
        order
      }
    })
    let source_table = if group.is_empty() {
      "my_biz_param_option"
    } else {
      text(field(group[0], "source_table"))
    }
    let expected_source = source_by_name
      .get(name)
      .map(text)
      .unwrap_or("my_biz_param_option")
    if expected_source != source_table {
      reasons.push("source_table_mapping_mismatch")
    }
    let options : Array[Json] = []
    let seen_ids : Map[String, Bool] = {}
    let seen_codes : Map[String, Bool] = {}
    for row in group {
      let option_id = text(field(row, "parameter_id"))
      let code = text(field(row, "parameter_code"))
      if option_id.is_empty() || seen_ids.get(option_id) is Some(_) {
        reasons.push("duplicate_or_missing_option_id:" + option_id)
      }
      if code.is_empty() || seen_codes.get(code) is Some(_) {
        reasons.push("duplicate_or_missing_option_code:" + code)
      }
      match field(row, "parameter_value") {
        String(_) => ()
        _ => reasons.push("missing_parameter_value:" + option_id)
      }
      seen_ids.set(option_id, true)
      seen_codes.set(code, true)
      options.push(
        Json::object({
          "parameter_id": Json::string(option_id),
          "parameter_name": Json::string(name),
          "parameter_code": Json::string(code),
          "parameter_value": field(row, "parameter_value"),
          "display_order": Json::number(
            integer(field(row, "display_order"), 0L).to_double(),
            repr=integer(field(row, "display_order"), 0L).to_string(),
          ),
          "enabled": Json::boolean(truthy(field(row, "enabled"))),
        }),
      )
    }
    let candidate = Json::object({
      "parameter_name": Json::string(name),
      "principal_id": principal,
      "authority_scope": scope,
      "options": Json::array(options),
    })
    items.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(name),
        "target_type": Json::string("parameter_dictionary"),
        "target_id": Json::string(name),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array([
          Json::string(
            "parameter values remain opaque configuration; no CBS/accounting meaning is inferred",
          ),
          Json::string(
            "catalog metadata such as manager, department, and cost code remains source evidence",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          candidate
        } else {
          Json::null()
        },
      }),
    )
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  let mapping_version = config
    .get("mapping_version")
    .unwrap_or(Json::string("unversioned-parameter-map"))
  let report = Json::object({
    "format": Json::string("moonproj.erp.parameter-promotion-plan.v1"),
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
    error => raise ParameterPromotionPlanError::Io(error)
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
    println("usage: parameter_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    ParameterPromotionPlanError::InvalidInput(message) => {
      println("parameter promotion plan failed: " + message)
      @sys.exit(1)
    }
    ParameterPromotionPlanError::Io(_) => {
      println("parameter promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
