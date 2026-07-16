///|
pub(all) suberror InvestmentPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> InvestmentPromotionPlanError {
  InvestmentPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise InvestmentPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise InvestmentPromotionPlanError {
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
) -> Unit raise InvestmentPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let versions = match read_json(export_dir + "/tables/tzsy_version.json") {
    Array(values) => values
    _ => raise fail("investment versions must be an array")
  }
  let indexes = match read_json(export_dir + "/tables/tzsy_plan_index.json") {
    Array(values) => values
    _ => raise fail("investment indexes must be an array")
  }
  let version_ids : Map[String, Bool] = {}
  for version in versions {
    version_ids.set(text(field(version, "version_guid")), true)
  }
  let items : Array[Json] = []
  for version in versions {
    let version_id = text(field(version, "version_guid"))
    let project_id = text(field(version, "proj_guid"))
    let bu_id = text(field(version, "bu_guid"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let reasons : Array[String] = []
    if !truthy(principal) {
      reasons.push("missing_principal_by_bu")
    }
    if version_id.is_empty() || project_id.is_empty() {
      reasons.push("missing_version_or_project_id")
    }
    let version_indexes : Array[Json] = []
    for row in indexes {
      if text(field(row, "version_guid")) == version_id {
        version_indexes.push(row)
      }
    }
    version_indexes.sort_by(fn(left, right) {
      let order = integer(field(left, "sort_order"), 0L).compare(
        integer(field(right, "sort_order"), 0L),
      )
      if order == 0 {
        text(field(left, "index_guid")).compare(
          text(field(right, "index_guid")),
        )
      } else {
        order
      }
    })
    if version_indexes.is_empty() {
      reasons.push("missing_indexes")
    }
    let seen_codes : Map[String, Bool] = {}
    let candidates : Array[Json] = []
    for row in version_indexes {
      let index_id = text(field(row, "index_guid"))
      let full_code = text(field(row, "full_code"))
      if index_id.is_empty() || full_code.is_empty() {
        reasons.push("missing_index_identity")
      }
      if seen_codes.get(full_code) is Some(_) {
        reasons.push("duplicate_index_code:" + full_code)
      }
      seen_codes.set(full_code, true)
      let raw_value = field(row, "index_value")
      let value_repr = match raw_value {
        Null => Json::null()
        True => Json::string("true")
        False => Json::string("false")
        Number(number, ..) if number == number.trunc() =>
          Json::string(number.to_int().to_string())
        Number(number, ..) => Json::string(number.to_string())
        String(value) => Json::string(value)
        _ => Json::string(text(raw_value))
      }
      candidates.push(
        Json::object({
          "index_guid": Json::string(index_id),
          "version_guid": Json::string(version_id),
          "proj_guid": Json::string(project_id),
          "dimension": field(row, "dimension"),
          "full_code": Json::string(full_code),
          "index_name": field(row, "index_name"),
          "parent_code": field(row, "parent_code"),
          "unit": field(row, "unit"),
          "value_repr": value_repr,
          "remark": field(row, "remark"),
          "sort_order": Json::number(
            integer(field(row, "sort_order"), 0L).to_double(),
            repr=integer(field(row, "sort_order"), 0L).to_string(),
          ),
        }),
      )
    }
    let candidate = Json::object({
      "version": Json::object({
        "version_guid": Json::string(version_id),
        "proj_guid": Json::string(project_id),
        "bu_guid": Json::string(bu_id),
        "version_name": field(version, "version_name"),
        "version_no": Json::number(
          integer(field(version, "version_no"), 0L).to_double(),
          repr=integer(field(version, "version_no"), 0L).to_string(),
        ),
        "current": Json::boolean(truthy(field(version, "is_current"))),
        "created_by": field(version, "created_by"),
        "created_at": field(version, "created_at"),
        "remark": field(version, "remark"),
      }),
      "indexes": Json::array(candidates),
      "principal_id": principal,
      "authority_scope": Json::string("project:" + project_id),
    })
    items.push(
      Json::object({
        "source_table": Json::string("tzsy_version"),
        "source_id": Json::string(version_id),
        "target_type": Json::string("investment_model"),
        "target_id": Json::string(version_id),
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
            "index values remain source representations; formula and accounting semantics require later approval",
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
  for row in indexes {
    let version_id = text(field(row, "version_guid"))
    if version_ids.get(version_id) is None {
      let index_id = text(field(row, "index_guid"))
      items.push(
        Json::object({
          "source_table": Json::string("tzsy_plan_index"),
          "source_id": Json::string(index_id),
          "target_type": Json::string("investment_model"),
          "target_id": Json::string(version_id),
          "disposition": Json::string("quarantined"),
          "reasons": Json::array([Json::string("stray_index_without_version")]),
          "warnings": Json::array([]),
          "target_candidate": Json::null(),
        }),
      )
    }
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
    None => Json::string("unversioned-investment-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.investment-promotion-plan.v1"),
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
    error => raise InvestmentPromotionPlanError::Io(error)
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
    println("usage: investment_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    InvestmentPromotionPlanError::InvalidInput(message) => {
      println("investment promotion plan failed: " + message)
      @sys.exit(1)
    }
    InvestmentPromotionPlanError::Io(_) => {
      println("investment promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
