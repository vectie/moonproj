///|
pub(all) suberror AuditPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> AuditPromotionPlanError {
  AuditPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AuditPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AuditPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AuditPromotionPlanError {
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
) -> Unit raise AuditPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let audit_map = match config.get("audit_by_id") {
    None => {}
    Some(value) => object(value, "audit_by_id")
  }
  let principal_map = match config.get("principal_by_bu") {
    None => {}
    Some(value) => object(value, "principal_by_bu")
  }
  let rows = match read_json(export_dir + "/tables/audit_log.json") {
    Array(values) => values
    _ => raise fail("audit export must be an array")
  }
  let items : Array[Json] = []
  for row in rows {
    let audit_id = text(field(row, "log_id"))
    let mapping = audit_map.get(audit_id).unwrap_or(Json::null())
    let reasons : Array[String] = []
    if audit_id.is_empty() || !truthy(field(row, "user_id")) {
      reasons.push("missing_audit_or_actor_identity")
    }
    let mapping_object = match mapping {
      Object(fields) => fields
      _ => {
        reasons.push("missing_audit_target_mapping")
        {}
      }
    }
    let bu_id = text(
      mapping_object.get("business_unit_id").unwrap_or(Json::null()),
    )
    let mapped_principal = mapping_object
      .get("principal_id")
      .unwrap_or(Json::null())
    let principal = if truthy(mapped_principal) {
      mapped_principal
    } else {
      principal_map.get(bu_id).unwrap_or(Json::null())
    }
    if !truthy(principal) {
      reasons.push("missing_principal_mapping")
    }
    let mapped_scope = mapping_object.get("scope").unwrap_or(Json::null())
    let scope = if truthy(mapped_scope) {
      mapped_scope
    } else if !bu_id.is_empty() {
      Json::string("organization:" + bu_id)
    } else {
      Json::string("")
    }
    let target_type = mapping_object.get("target_type").unwrap_or(Json::null())
    let target_id = mapping_object.get("target_id").unwrap_or(Json::null())
    let outcome = mapping_object.get("outcome").unwrap_or(Json::null())
    if !truthy(scope) ||
      !truthy(target_type) ||
      !truthy(target_id) ||
      !truthy(outcome) {
      reasons.push("incomplete_audit_target_mapping")
    }
    items.push(
      Json::object({
        "source_table": Json::string("audit_log"),
        "source_id": Json::string(audit_id),
        "target_type": Json::string("audit_record"),
        "target_id": Json::string(audit_id),
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
            "redacted network fields remain outside the target audit record",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          Json::object({
            "audit_id": Json::string(audit_id),
            "user_id": field(row, "user_id"),
            "action": field(row, "action"),
            "created_at": field(row, "created_at"),
            "principal_id": principal,
            "scope": scope,
            "target_type": target_type,
            "target_id": target_id,
            "outcome": outcome,
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
    None => Json::string("unversioned-audit-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.audit-promotion-plan.v1"),
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
    error => raise AuditPromotionPlanError::Io(error)
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
    println("usage: audit_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    AuditPromotionPlanError::InvalidInput(message) => {
      println("audit promotion plan failed: " + message)
      @sys.exit(1)
    }
    AuditPromotionPlanError::Io(_) => {
      println("audit promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
