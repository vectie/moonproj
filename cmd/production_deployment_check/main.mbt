///|
pub(all) suberror ProductionDeploymentError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ProductionDeploymentError {
  ProductionDeploymentError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ProductionDeploymentError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ProductionDeploymentError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read deployment manifest: " + path)
  }
}

///|
fn object(
  value : Json,
  name : String,
) -> Map[String, Json] raise ProductionDeploymentError {
  match value {
    Object(fields) => fields
    _ => raise fail(name + " must be an object")
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
) -> String raise ProductionDeploymentError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value.trim().to_owned()
    _ => raise fail("missing non-empty string: " + key)
  }
}

///|
fn field(
  fields : Map[String, Json],
  key : String,
  name : String,
) -> Map[String, Json] raise ProductionDeploymentError {
  object(fields.get(key).unwrap_or(Json::null()), name)
}

///|
fn bool_true(
  fields : Map[String, Json],
  key : String,
  message : String,
) -> Unit raise ProductionDeploymentError {
  if fields.get(key) != Some(Json::boolean(true)) {
    raise fail(message)
  }
}

///|
fn integer(
  fields : Map[String, Json],
  key : String,
  allow_zero : Bool,
) -> Int raise ProductionDeploymentError {
  let value = match fields.get(key) {
    Some(Number(number, ..)) if number == number.trunc() => number.to_int()
    _ => raise fail(key + " must be an integer")
  }
  if value < 0 || (!allow_zero && value == 0) {
    raise fail(key + " must be positive")
  }
  value
}

///|
fn env_name(value : String) -> Bool {
  if value.length() < 3 || value.length() > 128 {
    return false
  }
  let first = value.get_char(0).unwrap()
  if first < 'A' || first > 'Z' {
    return false
  }
  for char in value.iter() {
    if !((char >= 'A' && char <= 'Z') ||
      (char >= '0' && char <= '9') ||
      char == '_') {
      return false
    }
  }
  true
}

///|
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise ProductionDeploymentError {
  match value {
    Object(fields) =>
      for key, child in fields {
        let lowered = key.to_lower()
        if lowered.contains("password") ||
          lowered.contains("secret") ||
          lowered.contains("token") ||
          lowered.contains("private_key") ||
          lowered.contains("private-key") ||
          lowered.contains("credential") {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        reject_secrets(child, path + "." + key)
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    String(value) => {
      let lowered = value.to_lower()
      if lowered.contains("postgres://") ||
        lowered.contains("postgresql://") ||
        lowered.contains("mysql://") {
        raise fail("raw database DSN is not allowed at " + path)
      }
    }
    _ => ()
  }
}

///|
fn strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn required_roles() -> Array[String] {
  ["finance", "operations", "security"]
}

///|
fn validate(manifest : Json) -> Json raise ProductionDeploymentError {
  let root = object(manifest, "manifest")
  reject_secrets(manifest, "manifest")
  if required(root, "format") != "moonproj.company.production-deployment.v1" {
    raise fail("unsupported deployment manifest format")
  }
  if required(root, "environment") != "production" {
    raise fail("environment must be production")
  }
  let database = field(root, "database", "database")
  let engine = required(database, "engine").to_lower()
  if engine != "postgresql" {
    raise fail("Moonproj production engine must be postgresql")
  }
  let dsn_env = required(database, "dsn_env")
  if !env_name(dsn_env) {
    raise fail("dsn_env must be an uppercase environment-variable name")
  }
  let pool = field(database, "pool", "database.pool")
  let pool_min = integer(pool, "min", true)
  let pool_max = integer(pool, "max", false)
  if pool_max < pool_min {
    raise fail("database.pool.max must be >= database.pool.min")
  }
  let acquire_timeout = integer(pool, "acquire_timeout_seconds", false)
  if acquire_timeout > 300 {
    raise fail("database.pool.acquire_timeout_seconds exceeds 300")
  }
  let tls = field(database, "tls", "database.tls")
  bool_true(
    tls, "required", "database TLS must be required with certificate verification",
  )
  bool_true(
    tls, "verify_server_certificate", "database TLS must be required with certificate verification",
  )
  let encryption = field(
    database, "encryption_at_rest", "database.encryption_at_rest",
  )
  ignore(required(encryption, "provider"))
  ignore(required(encryption, "key_management"))
  let backup = field(root, "backup", "backup")
  ignore(required(backup, "schedule"))
  let backup_retention = integer(backup, "retention_days", false)
  ignore(required(backup, "destination"))
  ignore(required(backup, "encryption"))
  bool_true(backup, "cross_region", "backup.cross_region must be true")
  let restore = field(root, "restore", "restore")
  let restore_rpo = integer(restore, "rpo_minutes", true)
  let restore_rto = integer(restore, "rto_minutes", false)
  ignore(required(restore, "verification_command"))
  ignore(required(restore, "runbook"))
  let operations = field(root, "operations", "operations")
  ignore(required(operations, "migration_lock"))
  ignore(required(operations, "rollback_runbook"))
  let observability = field(
    operations, "observability", "operations.observability",
  )
  ignore(required(observability, "metrics"))
  ignore(required(observability, "audit_log"))
  ignore(required(observability, "alerts"))
  let approvals = field(root, "approvals", "approvals")
  let approved_role_values = match approvals.get("approved_roles") {
    Some(Array(values)) => values
    Some(_) =>
      raise fail("approvals.approved_roles must be an array of strings")
    None => []
  }
  let required_role_values = required_roles()
  let approved_roles : Array[String] = []
  for value in approved_role_values {
    match value {
      String(role) if required_role_values.contains(role) =>
        approved_roles.push(role)
      String(_) =>
        raise fail("approvals.approved_roles contains an unknown role")
      _ => raise fail("approvals.approved_roles must be an array of strings")
    }
  }
  let records = match approvals.get("records") {
    Some(Array(values)) => values
    Some(_) => raise fail("approvals.records must be an array")
    None => []
  }
  let record_roles : Map[String, Bool] = {}
  let approved_record_roles : Map[String, Bool] = {}
  for record_value in records {
    let record = object(record_value, "approval record")
    let role = required(record, "role")
    if !required_role_values.contains(role) {
      raise fail("approval record has unknown role: " + role)
    }
    if record_roles.contains(role) {
      raise fail("duplicate approval record: " + role)
    }
    record_roles.set(role, true)
    let decision = required(record, "decision")
    if decision == "approve" {
      for key in ["actor_id", "decided_at", "rationale"] {
        ignore(required(record, key))
      }
      let refs = match record.get("evidence_refs") {
        Some(Array(values)) => values
        _ => raise fail("approval record requires evidence_refs: " + role)
      }
      if refs.is_empty() {
        raise fail("approval record requires evidence_refs: " + role)
      }
      for reference in refs {
        match reference {
          String(value) if !value.trim().is_empty() => ()
          _ => raise fail("approval record requires evidence_refs: " + role)
        }
      }
      approved_record_roles.set(role, true)
    }
  }
  for role in approved_roles {
    if !record_roles.contains(role) {
      raise fail("approved_roles must be backed by approval records")
    }
  }
  let missing_roles : Array[String] = []
  for role in required_role_values {
    if !approved_record_roles.contains(role) {
      missing_roles.push(role)
    }
  }
  let approval_record_roles = record_roles.keys().to_array()
  approval_record_roles.sort_by(fn(left, right) { left.lexical_compare(right) })
  Json::object({
    "format": Json::string("moonproj.company.production-deployment-gate.v1"),
    "environment": Json::string("production"),
    "engine": Json::string(engine),
    "dsn_env": Json::string(dsn_env),
    "pool": Json::object({
      "min": Json::number(pool_min.to_double(), repr=pool_min.to_string()),
      "max": Json::number(pool_max.to_double(), repr=pool_max.to_string()),
      "acquire_timeout_seconds": Json::number(
        acquire_timeout.to_double(),
        repr=acquire_timeout.to_string(),
      ),
    }),
    "backup": Json::object({
      "retention_days": Json::number(
        backup_retention.to_double(),
        repr=backup_retention.to_string(),
      ),
      "cross_region": Json::boolean(true),
    }),
    "restore": Json::object({
      "rpo_minutes": Json::number(
        restore_rpo.to_double(),
        repr=restore_rpo.to_string(),
      ),
      "rto_minutes": Json::number(
        restore_rto.to_double(),
        repr=restore_rto.to_string(),
      ),
    }),
    "required_approval_roles": strings(required_roles()),
    "missing_approval_roles": strings(missing_roles),
    "approval_record_roles": strings(approval_record_roles),
    "deployment_authorized": Json::boolean(missing_roles.is_empty()),
    "state": Json::string(
      if missing_roles.is_empty() {
        "ready_for_managed_deployment"
      } else {
        "ready_for_owner_review"
      },
    ),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: production_deployment_check <manifest> <output>")
    @sys.exit(2)
  } else {
    let result = validate(read_json(args[1])) catch {
      ProductionDeploymentError::InvalidInput(message) => {
        println("production deployment check failed: " + message)
        @sys.exit(1)
        Json::null()
      }
      ProductionDeploymentError::Io(_) => {
        println("production deployment check failed: filesystem error")
        @sys.exit(1)
        Json::null()
      }
    }
    @fs.write_string_to_file(args[2], result.stringify(indent=2) + "\n") catch {
      _ => {
        println("production deployment check failed: filesystem error")
        @sys.exit(1)
      }
    }
    println(result.stringify())
  }
}
