///|
pub(all) suberror UserPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> UserPromotionPlanError {
  UserPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise UserPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise UserPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise UserPromotionPlanError {
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
) -> Unit raise UserPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let rows = match read_json(export_dir + "/tables/sys_user.json") {
    Array(values) => values
    _ => raise fail("user export must be an array")
  }
  let items : Array[Json] = []
  for row in rows {
    let user_id = text(field(row, "user_id"))
    let bu_id = text(field(row, "bu_guid"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let reasons : Array[String] = []
    if user_id.is_empty() || !truthy(field(row, "user_code")) {
      reasons.push("missing_user_identity")
    }
    if bu_id.is_empty() {
      reasons.push("missing_business_unit")
    }
    if !truthy(principal) {
      reasons.push("missing_principal_by_bu")
    }
    let display_name = if truthy(field(row, "emp_name")) {
      field(row, "emp_name")
    } else {
      field(row, "user_name")
    }
    if !truthy(display_name) {
      reasons.push("missing_display_name")
    }
    let warnings : Array[Json] = [
      Json::string(
        "password_hash, login IP, and authentication timestamps are not imported",
      ),
    ]
    if truthy(field(row, "is_super_user")) {
      warnings.push(
        Json::string(
          "legacy super_user is evidence only; no target privilege is granted",
        ),
      )
    }
    items.push(
      Json::object({
        "source_table": Json::string("sys_user"),
        "source_id": Json::string(user_id),
        "target_type": Json::string("user_account"),
        "target_id": Json::string(user_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array(warnings),
        "target_candidate": if reasons.is_empty() {
          Json::object({
            "user_id": Json::string(user_id),
            "user_code": field(row, "user_code"),
            "display_name": display_name,
            "principal_id": principal,
            "business_unit_id": Json::string(bu_id),
            "department_id": field(row, "dept_guid"),
            "enabled": Json::boolean(truthy(field(row, "enabled"))),
            "source_super_user": Json::boolean(
              truthy(field(row, "is_super_user")),
            ),
            "authority_scope": Json::string("organization:" + bu_id),
          })
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
  let mapping_version = match config.get("mapping_version") {
    Some(value) => value
    None => Json::string("unversioned-user-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.user-promotion-plan.v1"),
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
    error => raise UserPromotionPlanError::Io(error)
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
    println("usage: user_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    UserPromotionPlanError::InvalidInput(message) => {
      println("user promotion plan failed: " + message)
      @sys.exit(1)
    }
    UserPromotionPlanError::Io(_) => {
      println("user promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
