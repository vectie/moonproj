///|
pub(all) suberror TypedEvidencePromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct TableSpec {
  table : String
  primary_key : String
  default_class : String
}

///|
fn fail(message : String) -> TypedEvidencePromotionPlanError {
  TypedEvidencePromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise TypedEvidencePromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TypedEvidencePromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise TypedEvidencePromotionPlanError {
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
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise TypedEvidencePromotionPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        let lowered = key.to_lower()
        if lowered.contains("password") ||
          lowered.contains("secret") ||
          lowered.contains("token") ||
          lowered.contains("private") ||
          lowered.has_suffix("ip") {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secrets(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn number_tokens(source : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut index = 0
  let mut in_string = false
  let mut escaped = false
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if in_string {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        in_string = false
      }
      index += 1
    } else if char == '"' {
      in_string = true
      index += 1
    } else if char == '-' || (char >= '0' && char <= '9') {
      let start = index
      index += 1
      while index < source.length() {
        let next = source.get_char(index).unwrap()
        if next == ',' ||
          next == ']' ||
          next == '}' ||
          next == ' ' ||
          next == '\n' ||
          next == '\r' ||
          next == '\t' {
          break
        }
        index += 1
      }
      tokens.push(source[start:index].to_owned())
    } else {
      index += 1
    }
  }
  tokens
}

///|
fn restore_numbers(
  value : Json,
  tokens : Array[String],
  index : Int,
) -> (Json, Int) {
  match value {
    Number(number, ..) =>
      if index < tokens.length() {
        (Json::number(number, repr=tokens[index]), index + 1)
      } else {
        (value, index)
      }
    Array(values) => {
      let restored : Array[Json] = []
      let mut next = index
      for child in values {
        let result = restore_numbers(child, tokens, next)
        restored.push(result.0)
        next = result.1
      }
      (Json::array(restored), next)
    }
    Object(fields) => {
      let restored : Map[String, Json] = {}
      let mut next = index
      for key in fields.keys() {
        let child = fields.get(key).unwrap()
        let result = restore_numbers(child, tokens, next)
        restored.set(key, result.0)
        next = result.1
      }
      (Json::object(restored), next)
    }
    _ => (value, index)
  }
}

///|
fn read_preserving_numbers(
  path : String,
) -> Json raise TypedEvidencePromotionPlanError {
  let source = @fs.read_file_to_string(path) catch {
    error => raise TypedEvidencePromotionPlanError::Io(error)
  }
  let parsed = @json.parse(source) catch {
    _ => raise fail("cannot read " + path)
  }
  restore_numbers(parsed, number_tokens(source), 0).0
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise TypedEvidencePromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let classes = match config.get("typed_evidence_class_by_table") {
    None => {}
    Some(value) => object(value, "typed_evidence_class_by_table")
  }
  let specs = [
    TableSpec::{
      table: "jd_task",
      primary_key: "task_guid",
      default_class: "task_record_snapshot",
    },
    TableSpec::{
      table: "jd_task_report",
      primary_key: "report_guid",
      default_class: "task_progress_report",
    },
    TableSpec::{
      table: "wf_step_assignee",
      primary_key: "assignee_guid",
      default_class: "workflow_assignment",
    },
    TableSpec::{
      table: "proj_lifecycle_instance",
      primary_key: "instance_id",
      default_class: "lifecycle_instance_history",
    },
    TableSpec::{
      table: "proj_lifecycle_stage",
      primary_key: "stage_code",
      default_class: "lifecycle_stage_catalog",
    },
    TableSpec::{
      table: "vys_proceeding",
      primary_key: "proceeding_guid",
      default_class: "expense_proceeding_catalog",
    },
  ]
  let items : Array[Json] = []
  for spec in specs {
    let rows = match
      read_preserving_numbers(export_dir + "/tables/" + spec.table + ".json") {
      Array(values) => values
      _ => raise fail("evidence export is not an array: " + spec.table)
    }
    let evidence_class = classes.get(spec.table).unwrap_or(Json::null())
    let class_valid = match evidence_class {
      String(value) => value == spec.default_class
      _ => false
    }
    let base_reasons : Array[String] = []
    if !class_valid {
      base_reasons.push("missing_or_invalid_evidence_class:" + spec.table)
    }
    let seen : Map[String, Bool] = {}
    for row in rows {
      let source_id = text(field(row, spec.primary_key))
      let reasons = base_reasons.copy()
      if source_id.is_empty() || seen.get(source_id) is Some(_) {
        reasons.push("missing_or_duplicate_source_id")
      }
      seen.set(source_id, true)
      reject_secrets(row, spec.table + ":" + source_id) catch {
        TypedEvidencePromotionPlanError::InvalidInput(message) =>
          reasons.push(message)
        TypedEvidencePromotionPlanError::Io(_) => ()
      }
      let target_id = spec.table + ":" + source_id
      items.push(
        Json::object({
          "source_table": Json::string(spec.table),
          "source_id": Json::string(source_id),
          "target_type": Json::string("typed_evidence"),
          "target_id": Json::string(target_id),
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
              "evidence is queryable preservation only; no target workflow, authority, or economic state is inferred",
            ),
          ]),
          "target_candidate": if reasons.is_empty() {
            Json::object({
              "evidence_id": Json::string(target_id),
              "evidence_class": evidence_class,
              "source_table": Json::string(spec.table),
              "source_id": Json::string(source_id),
              "evidence_payload": row,
              "evidence_policy": Json::string("typed-preservation-only"),
            })
          } else {
            Json::null()
          },
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
    None => Json::string("unversioned-typed-evidence-map")
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.typed-evidence-promotion-plan.v1"),
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
    error => raise TypedEvidencePromotionPlanError::Io(error)
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
    println("usage: typed_evidence_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    TypedEvidencePromotionPlanError::InvalidInput(message) => {
      println("typed-evidence promotion plan failed: " + message)
      @sys.exit(1)
    }
    TypedEvidencePromotionPlanError::Io(_) => {
      println("typed-evidence promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
