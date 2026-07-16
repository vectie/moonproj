///|
pub(all) suberror AccessPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct PermissionCandidate {
  capability : String
  scope : String
  max_amount_minor : Int
}

///|
struct PermissionResult {
  candidate : PermissionCandidate?
  reason : String
}

///|
fn fail(message : String) -> AccessPlanError {
  AccessPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AccessPlanError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise AccessPlanError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AccessPlanError {
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
) -> Json raise AccessPlanError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|

///|
fn strict_string(value : Json) -> String? {
  match value {
    String(value) => Some(value)
    _ => None
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value.trim().to_owned()
    Number(number, repr~) =>
      match repr {
        Some(value) => value
        None => number.to_string()
      }
    True => "True"
    False => "False"
    Null => ""
    _ => value.stringify()
  }
}

///|
fn row_text(row : Map[String, Json], key : String) -> String {
  text(row.get(key).unwrap_or(Json::null()))
}

///|
fn bool_value(row : Map[String, Json], key : String) -> Bool {
  match row.get(key) {
    Some(True) => true
    Some(False) => false
    Some(Number(value, ..)) => value != 0.0
    Some(String(value)) => {
      let lowered = value.trim().to_lower()
      lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "y"
    }
    _ => false
  }
}

///|
fn reject_secrets(value : Json, path : String) -> Unit raise AccessPlanError {
  match value {
    Object(fields) =>
      for key, child in fields {
        let lowered = key.to_lower()
        if lowered.contains("password") ||
          lowered.contains("secret") ||
          lowered.contains("token") ||
          lowered.contains("private") ||
          lowered.has_suffix("ip") {
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
fn read_rows(
  export_dir : String,
  table : String,
) -> (Array[Map[String, Json]], Bool) raise AccessPlanError {
  let path = export_dir + "/tables/" + table + ".json"
  let content = @fs.read_file_to_string(path) catch { _ => return ([], false) }
  let parsed = @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
  let values = match parsed {
    Array(values) => values
    _ => raise fail("source table is not an object array: " + table)
  }
  let rows : Array[Map[String, Json]] = []
  for index in 0..<values.length() {
    rows.push(object(values[index], table + "[" + index.to_string() + "]"))
  }
  (rows, true)
}

///|
fn split_permission_text(raw : String) -> Array[String] {
  let result : Array[String] = []
  let mut current = ""
  for char in raw {
    if char == ',' || char == ';' || char.is_ascii_whitespace() {
      if !current.is_empty() {
        result.push(current)
        current = ""
      }
    } else {
      current = current + char.to_string()
    }
  }
  if !current.is_empty() {
    result.push(current)
  }
  result
}

///|
fn permission_names(value : Json) -> Array[String] raise AccessPlanError {
  match value {
    Null => []
    Array(values) => {
      let result : Array[String] = []
      for child in values {
        match child {
          String(name) => {
            let cleaned = name.trim()
            if !cleaned.is_empty() {
              result.push(cleaned.to_owned())
            }
          }
          Object(fields) => {
            let mut found : String? = None
            for key in ["code", "permission", "name", "capability"] {
              match fields.get(key) {
                Some(String(name)) if !name.trim().is_empty() => {
                  found = Some(name.trim().to_owned())
                  break
                }
                _ => ()
              }
            }
            match found {
              Some(name) => result.push(name)
              None => ()
            }
          }
          _ => ()
        }
      }
      result
    }
    Object(fields) => {
      let result : Array[String] = []
      for key, _ in fields {
        let cleaned = key.trim()
        if !cleaned.is_empty() {
          result.push(cleaned.to_owned())
        }
      }
      result
    }
    String(raw) => {
      let cleaned = raw.trim()
      if cleaned.is_empty() {
        []
      } else {
        let parsed = @json.parse(cleaned) catch {
          _ => return split_permission_text(cleaned.to_owned())
        }
        permission_names(parsed)
      }
    }
    _ => []
  }
}

///|
fn map_object(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json] raise AccessPlanError {
  match fields.get(key) {
    Some(Object(value)) => value
    _ => raise fail("access mapping dictionary is invalid: " + key)
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  key : String,
  default : Bool,
) -> Bool {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}

///|
fn permission_candidate(
  source_name : String,
  permission_map : Map[String, Json],
  role_scope : String,
) -> PermissionResult {
  let mapped = match permission_map.get(source_name) {
    Some(Object(value)) => value
    _ =>
      return {
        candidate: None,
        reason: "missing_permission_mapping:" + source_name,
      }
  }
  let capability = match
    strict_string(mapped.get("capability").unwrap_or(Json::null())) {
    Some(value) => value.trim().to_owned()
    None => ""
  }
  if capability.is_empty() {
    return {
      candidate: None,
      reason: "missing_permission_capability:" + source_name,
    }
  }
  let mut scope = match
    strict_string(mapped.get("scope").unwrap_or(Json::null())) {
    Some(value) => value.trim().to_owned()
    None => ""
  }
  if scope == "$role_scope" {
    scope = role_scope
  }
  if scope.is_empty() {
    return {
      candidate: None,
      reason: "missing_permission_scope:" + source_name,
    }
  }
  let amount_value = mapped.get("max_amount_minor").unwrap_or(Json::null())
  let amount = match amount_value {
    Number(value, ..) if value == value.trunc() && value >= 0.0 =>
      value.to_int()
    _ =>
      return {
        candidate: None,
        reason: "invalid_permission_cap:" + source_name,
      }
  }
  {
    candidate: Some(PermissionCandidate::{
      capability,
      scope,
      max_amount_minor: amount,
    }),
    reason: "",
  }
}

///|
fn candidate_json(candidate : PermissionCandidate) -> Json {
  Json::object({
    "capability": Json::string(candidate.capability),
    "scope": Json::string(candidate.scope),
    "max_amount_minor": Json::number(
      candidate.max_amount_minor.to_double(),
      repr=candidate.max_amount_minor.to_string(),
    ),
  })
}

///|
fn strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn json_number(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Json raise AccessPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  if text(required(config, "format", "mapping")) !=
    "moonproj.erp.access-mapping.v1" {
    raise fail("unsupported access mapping format")
  }
  let source_hash = match
    strict_string(required(manifest, "source_sha256", "manifest")) {
    Some(value) if !value.is_empty() => value
    _ => raise fail("source manifest has no source hash")
  }
  let role_rows_tuple = read_rows(export_dir, "sys_role")
  let assignment_rows_tuple = read_rows(export_dir, "sys_user_role")
  let role_rows = role_rows_tuple.0
  let roles_present = role_rows_tuple.1
  let assignment_rows = assignment_rows_tuple.0
  let assignments_present = assignment_rows_tuple.1
  let permission_map = map_object(config, "permission_map")
  let scope_by_role = map_object(config, "scope_by_role")
  let principal_by_user = map_object(config, "principal_by_user")
  let actor_by_user = map_object(config, "actor_by_user")
  let assignment_cap_by_role = map_object(config, "assignment_cap_by_role")
  let roles : Array[Json] = []
  let role_reasons : Map[String, Array[String]] = {}
  let role_scopes : Map[String, String] = {}
  for row in role_rows {
    let row_json = Json::object(row)
    reject_secrets(row_json, "sys_role")
    let role_code = row_text(row, "role_code")
    let role_name = row_text(row, "role_name")
    let reasons : Array[String] = []
    if role_code.is_empty() || role_name.is_empty() {
      reasons.push("missing_role_identity")
    }
    let mut role_scope = match
      strict_string(scope_by_role.get(role_code).unwrap_or(Json::null())) {
      Some(value) if !value.trim().is_empty() => value.trim().to_owned()
      _ => ""
    }
    if role_scope.is_empty() {
      reasons.push("missing_role_scope")
      role_scope = ""
    }
    role_scopes.set(role_code, role_scope)
    if bool_value(row, "is_system") &&
      !optional_bool(config, "allow_system_roles", false) {
      reasons.push("system_role_requires_explicit_review")
    }
    let permissions : Array[Json] = []
    for
      source_name in permission_names(
        row.get("permissions").unwrap_or(Json::null()),
      ) {
      let result = permission_candidate(source_name, permission_map, role_scope)
      if !result.reason.is_empty() {
        reasons.push(result.reason)
      } else {
        match result.candidate {
          Some(candidate) => permissions.push(candidate_json(candidate))
          None => ()
        }
      }
    }
    if permissions.is_empty() {
      reasons.push("role_has_no_reviewed_permissions")
    }
    role_reasons.set(role_code, reasons)
    roles.push(
      Json::object({
        "role_id": Json::string(role_code),
        "name": Json::string(role_name),
        "permissions": Json::array(permissions),
      }),
    )
  }
  let assignments : Array[Json] = []
  let assignment_reasons : Array[String] = []
  for row in assignment_rows {
    let row_json = Json::object(row)
    reject_secrets(row_json, "sys_user_role")
    let user_id = row_text(row, "user_id")
    let role_code = row_text(row, "role_code")
    let reasons : Array[String] = []
    let mut principal_id = match
      strict_string(principal_by_user.get(user_id).unwrap_or(Json::null())) {
      Some(value) if !value.trim().is_empty() => value.trim().to_owned()
      _ => ""
    }
    let mut actor_id = match
      strict_string(actor_by_user.get(user_id).unwrap_or(Json::null())) {
      Some(value) if !value.trim().is_empty() => value.trim().to_owned()
      _ => ""
    }
    let mut assignment_scope = match role_scopes.get(role_code) {
      Some(value) => value
      None =>
        match
          strict_string(scope_by_role.get(role_code).unwrap_or(Json::null())) {
          Some(value) if !value.trim().is_empty() => value.trim().to_owned()
          _ => ""
        }
    }
    let cap_value = assignment_cap_by_role
      .get(role_code)
      .unwrap_or(Json::null())
    let mut cap = 0
    if principal_id.is_empty() {
      reasons.push("missing_principal_mapping")
      principal_id = ""
    }
    if actor_id.is_empty() {
      reasons.push("missing_actor_mapping")
      actor_id = ""
    }
    if assignment_scope.is_empty() {
      reasons.push("missing_assignment_scope")
      assignment_scope = ""
    }
    match cap_value {
      Number(value, ..) if value == value.trunc() && value >= 0.0 =>
        cap = value.to_int()
      _ => reasons.push("missing_assignment_cap")
    }
    for
      reason in role_reasons.get(role_code).unwrap_or(["unknown_role_mapping"]) {
      reasons.push(reason)
    }
    let unique_reasons = reasons
    unique_reasons.sort_by(fn(left, right) { left.lexical_compare(right) })
    let deduped : Array[String] = []
    for reason in unique_reasons {
      if !deduped.contains(reason) {
        deduped.push(reason)
      }
    }
    for reason in deduped {
      assignment_reasons.push(user_id + ":" + role_code + ":" + reason)
    }
    assignments.push(
      Json::object({
        "assignment_id": Json::string(user_id + ":" + role_code),
        "role_id": Json::string(role_code),
        "principal_id": Json::string(principal_id),
        "actor_id": Json::string(actor_id),
        "scope": Json::string(assignment_scope),
        "max_amount_minor": json_number(cap),
        "active": Json::boolean(true),
      }),
    )
  }
  let reasons : Array[String] = assignment_reasons
  for _, role_values in role_reasons {
    for reason in role_values {
      reasons.push(reason)
    }
  }
  reasons.sort_by(fn(left, right) { left.lexical_compare(right) })
  let unique : Array[String] = []
  for reason in reasons {
    if !unique.contains(reason) {
      unique.push(reason)
    }
  }
  let source_rows_available = !role_rows.is_empty() ||
    !assignment_rows.is_empty()
  let source_tables_present = roles_present || assignments_present
  let reviewed = optional_bool(config, "reviewed", false) &&
    unique.is_empty() &&
    source_rows_available
  let state = if !source_rows_available {
    "scope_only"
  } else if reviewed {
    "ready_for_native_import"
  } else {
    "review_required"
  }
  let root_scope = match strict_string(required(config, "scope", "mapping")) {
    Some(value) if !value.trim().is_empty() => value.trim().to_owned()
    _ => ""
  }
  let root_principal = match
    strict_string(required(config, "principal_id", "mapping")) {
    Some(value) if !value.trim().is_empty() => value.trim().to_owned()
    _ => ""
  }
  if root_scope.is_empty() || root_principal.is_empty() {
    raise fail("mapping requires principal_id and scope")
  }
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(source_hash)),
  )
  let plan = Json::object({
    "format": Json::string("moonproj.company.access-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_hash),
    "mapping_version": config
    .get("mapping_version")
    .unwrap_or(Json::string("unversioned-access-map")),
    "source_table": Json::string("sys_role"),
    "source_id": Json::string("access-bundle:" + digest[:16].to_owned()),
    "principal_id": Json::string(root_principal),
    "scope": Json::string(root_scope),
    "reviewed": Json::boolean(reviewed),
    "roles": Json::array(roles),
    "separation_rules": config
    .get("separation_rules")
    .unwrap_or(Json::array([])),
    "assignments": Json::array(assignments),
    "summary": Json::object({
      "state": Json::string(state),
      "roles": json_number(roles.length()),
      "assignments": json_number(assignments.length()),
      "quarantine_reasons": strings(unique),
      "source_rows_available": Json::boolean(source_rows_available),
      "source_tables_present": Json::boolean(source_tables_present),
      "promotion_authorized": Json::boolean(false),
    }),
  })
  @fs.write_string_to_file(output_path, plan.stringify(indent=2) + "\n") catch {
    error => raise AccessPlanError::Io(error)
  }
  plan
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() != 4 {
    println("usage: access_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  let plan = run(args[1], args[2], args[3]) catch {
    error => {
      println("access promotion plan failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  match plan {
    Object(fields) =>
      println(
        Json::object({
          "output": Json::string(args[3]),
          "state": fields.get("summary").unwrap_or(Json::null()),
        }).stringify(),
      )
    _ => ()
  }
}
