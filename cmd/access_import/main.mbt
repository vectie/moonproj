///|
pub(all) suberror AccessPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Access(@access.AccessError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise AccessPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AccessPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise AccessPromotionError {
  match value {
    Object(value) => value
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise AccessPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise AccessPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise AccessPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise AccessPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise AccessPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise AccessPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise AccessPromotionError::InvalidInput
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "access-import/" + capability + "/" + scope,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn permission_json(permission : @access.Permission) -> Json {
  Json::object({
    "capability": Json::string(permission.capability),
    "scope": Json::string(permission.scope),
    "max_amount_minor": Json::number(
      permission.max_amount_minor.to_double(),
      repr=permission.max_amount_minor.to_string(),
    ),
  })
}

///|
fn permissions_json(permissions : Array[@access.Permission]) -> Json {
  let values : Array[Json] = []
  for permission in permissions {
    values.push(permission_json(permission))
  }
  Json::array(values)
}

///|
fn roles_json(roles : Array[@access.Role]) -> Json {
  let values : Array[Json] = []
  for role in roles {
    values.push(
      Json::object({
        "role_id": Json::string(role.role_id),
        "name": Json::string(role.name),
        "permissions": permissions_json(role.permissions),
      }),
    )
  }
  Json::array(values)
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise AccessPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.company.access-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise AccessPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let source_table = required_string(root, "source_table")
  let source_id = required_string(root, "source_id")
  let principal_id = required_string(root, "principal_id")
  let scope = required_string(root, "scope")
  let mut directory = @access.AccessDirectory::empty()
  for role_value in required_array(root, "roles") {
    let role_obj = object(role_value)
    let role_id = required_string(role_obj, "role_id")
    let role_name = required_string(role_obj, "name")
    let mut role = @access.Role::new(role_id~, name=role_name) catch {
      error => raise AccessPromotionError::Access(error)
    }
    for permission_value in required_array(role_obj, "permissions") {
      let permission_obj = object(permission_value)
      let capability = required_string(permission_obj, "capability")
      let permission_scope = required_string(permission_obj, "scope")
      let max_amount_minor = required_int64(permission_obj, "max_amount_minor")
      let permission = @access.Permission::new(
        capability~,
        scope=permission_scope,
        max_amount_minor~,
      ) catch {
        error => raise AccessPromotionError::Access(error)
      }
      role = role.add_permission(
        permission,
        actor_id="migration",
        grant=grant(principal_id, "rbac:role:edit", "role:" + role_id, 0L),
      ) catch {
        error => raise AccessPromotionError::Access(error)
      }
    }
    directory = directory.add_role(
      role,
      actor_id="migration",
      grant=grant(principal_id, "rbac:role:create", "role:" + role_id, 0L),
    ) catch {
      error => raise AccessPromotionError::Access(error)
    }
  }
  for rule_value in required_array(root, "separation_rules") {
    let rule_obj = object(rule_value)
    let rule_scope = required_string(rule_obj, "scope")
    let rule : @access.SeparationRule = {
      rule_id: required_string(rule_obj, "rule_id"),
      first_capability: required_string(rule_obj, "first_capability"),
      second_capability: required_string(rule_obj, "second_capability"),
      scope: rule_scope,
    }
    directory = directory.add_separation_rule(
      rule,
      actor_id="migration",
      grant=grant(principal_id, "rbac:sod:rule:create", rule_scope, 0L),
    ) catch {
      error => raise AccessPromotionError::Access(error)
    }
  }
  for assignment_value in required_array(root, "assignments") {
    let assignment_obj = object(assignment_value)
    let assignment_scope = required_string(assignment_obj, "scope")
    let assignment_principal = required_string(assignment_obj, "principal_id")
    let assignment : @access.RoleAssignment = {
      assignment_id: required_string(assignment_obj, "assignment_id"),
      role_id: required_string(assignment_obj, "role_id"),
      principal_id: assignment_principal,
      actor_id: required_string(assignment_obj, "actor_id"),
      scope: assignment_scope,
      max_amount_minor: required_int64(assignment_obj, "max_amount_minor"),
      active: required_bool(assignment_obj, "active"),
    }
    directory = directory.assign_role(
      assignment,
      actor_id="migration",
      grant=grant(
        assignment_principal, "rbac:assignment:create", assignment_scope, 0L,
      ),
    ) catch {
      error => raise AccessPromotionError::Access(error)
    }
  }
  let candidate = Json::object({
    "principal_id": Json::string(principal_id),
    "scope": Json::string(scope),
    "roles": roles_json(directory.roles),
    "assignments": Json::array(required_array(root, "assignments")),
    "separation_rules": Json::array(required_array(root, "separation_rules")),
    "reviewed": Json::boolean(true),
    "authority_migrated": Json::boolean(true),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("access-rbac-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("access_directory"),
        "target_id": Json::string(principal_id),
        "target_candidate": candidate,
      }),
    ]),
    "authority_migrated": Json::boolean(true),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise AccessPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: access_import <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      AccessPromotionError::InvalidInput => {
        println("access import failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      AccessPromotionError::Io(_) => {
        println("access import failed: filesystem error")
        @sys.exit(1)
      }
      AccessPromotionError::Access(_) => {
        println("access import failed: authority or segregation validation")
        @sys.exit(1)
      }
    }
  }
}
