///|
pub(all) suberror ProductionServiceError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ProductionServiceError {
  ProductionServiceError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ProductionServiceError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ProductionServiceError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  name : String,
) -> Map[String, Json] raise ProductionServiceError {
  match value {
    Object(fields) => fields
    _ => raise fail(name + " must be an object")
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
) -> String raise ProductionServiceError {
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
) -> Map[String, Json] raise ProductionServiceError {
  object(fields.get(key).unwrap_or(Json::null()), name)
}

///|
fn bool_true(
  fields : Map[String, Json],
  key : String,
  message : String,
) -> Unit raise ProductionServiceError {
  if fields.get(key) != Some(Json::boolean(true)) {
    raise fail(message)
  }
}

///|
fn positive_int(
  fields : Map[String, Json],
  key : String,
  maximum : Int,
) -> Int raise ProductionServiceError {
  let value = match fields.get(key) {
    Some(Number(number, ..)) if number == number.trunc() => number.to_int()
    _ => raise fail(key + " must be a positive integer")
  }
  if value <= 0 || value > maximum {
    raise fail(key + " exceeds " + maximum.to_string())
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
) -> Unit raise ProductionServiceError {
  match value {
    Object(fields) =>
      for key, child in fields {
        let lowered = key.to_lower()
        if key != "token_env" &&
          (
            lowered.contains("password") ||
            lowered.contains("secret") ||
            lowered.contains("token") ||
            lowered.contains("private") ||
            lowered.contains("credential")
          ) {
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
fn validate(
  service : Json,
  deployment_gate : Json,
) -> Json raise ProductionServiceError {
  let root = object(service, "service manifest")
  reject_secrets(service, "manifest")
  if required(root, "format") != "moonproj.company.production-service.v1" {
    raise fail("unsupported service manifest format")
  }
  if required(root, "environment") != "production" {
    raise fail("service environment must be production")
  }
  let database = field(root, "database", "database")
  if required(database, "engine") != "postgresql" {
    raise fail("service database engine must be postgresql")
  }
  ignore(required(database, "deployment_gate_artifact"))
  let pool = field(database, "pool", "database.pool")
  bool_true(
    pool, "reuse_connections", "database.pool.reuse_connections must be true",
  )
  let max_in_flight = positive_int(pool, "max_in_flight", 256)
  let acquire_timeout = positive_int(pool, "acquire_timeout_seconds", 300)
  bool_true(
    pool, "fail_closed_on_exhaustion", "pool exhaustion must fail closed",
  )
  let health = field(database, "health", "database.health")
  ignore(required(health, "readiness_query_name"))
  ignore(required(health, "migration_schema_version"))
  bool_true(
    health, "readiness_requires_schema_match", "readiness must require schema-version match",
  )
  let http = field(root, "http", "http")
  let bind = required(http, "bind_host")
  if bind == "0.0.0.0" || bind == "::" || bind == "[::]" {
    raise fail("service must bind privately behind its gateway")
  }
  ignore(required(http, "tls_terminated_by"))
  bool_true(http, "forwarded_tls_required", "forwarded TLS must be required")
  ignore(positive_int(http, "request_timeout_seconds", 300))
  ignore(positive_int(http, "max_response_rows", 10000))
  let auth = field(http, "auth", "http.auth")
  bool_true(auth, "required", "HTTP authentication must be required")
  let token_env = required(auth, "token_env")
  if !env_name(token_env) {
    raise fail("auth.token_env must be an uppercase environment name")
  }
  ignore(required(auth, "issuer"))
  ignore(required(auth, "audience"))
  let origins = match http.get("cors_origins") {
    Some(Array(values)) => values
    _ => raise fail("cors_origins must contain only explicit HTTPS origins")
  }
  if origins.is_empty() {
    raise fail("cors_origins must contain only explicit HTTPS origins")
  }
  for origin in origins {
    match origin {
      String(value) if value.has_prefix("https://") && value != "*" => ()
      _ => raise fail("cors_origins must contain only explicit HTTPS origins")
    }
  }
  let endpoints = field(root, "endpoints", "endpoints")
  let expected_endpoints = [
    "/api/company/projections", "/api/company/receipts", "/api/company/summary",
    "/api/health",
  ]
  let read_endpoints = match endpoints.get("read") {
    Some(Array(values)) => values
    _ => raise fail("read endpoints must match the fixed read-model allow-list")
  }
  let read_set : Map[String, Bool] = {}
  for endpoint in read_endpoints {
    match endpoint {
      String(value) => read_set.set(value, true)
      _ =>
        raise fail("read endpoints must match the fixed read-model allow-list")
    }
  }
  if read_set.keys().length() != expected_endpoints.length() {
    raise fail("read endpoints must match the fixed read-model allow-list")
  }
  for endpoint in expected_endpoints {
    if !read_set.contains(endpoint) {
      raise fail("read endpoints must match the fixed read-model allow-list")
    }
  }
  match endpoints.get("mutation") {
    None => ()
    Some(Array(values)) if values.is_empty() => ()
    _ => raise fail("mutation endpoints require a separate command gateway")
  }
  bool_false(endpoints, "arbitrary_sql", "arbitrary SQL must be disabled")
  let observability = field(root, "observability", "observability")
  for key in ["metrics", "audit_log", "alerts", "request_trace"] {
    ignore(required(observability, key))
  }
  let deployment = object(deployment_gate, "deployment gate")
  if required(deployment, "format") !=
    "moonproj.company.production-deployment-gate.v1" {
    raise fail("unexpected deployment gate format")
  }
  let deployment_authorized = deployment.get("deployment_authorized") ==
    Some(Json::boolean(true))
  Json::object({
    "format": Json::string("moonproj.company.production-service-gate.v1"),
    "environment": Json::string("production"),
    "database_engine": Json::string("postgresql"),
    "pool": Json::object({
      "max_in_flight": Json::number(
        max_in_flight.to_double(),
        repr=max_in_flight.to_string(),
      ),
      "acquire_timeout_seconds": Json::number(
        acquire_timeout.to_double(),
        repr=acquire_timeout.to_string(),
      ),
      "fail_closed_on_exhaustion": Json::boolean(true),
    }),
    "auth_token_env": Json::string(token_env),
    "read_endpoints": strings(expected_endpoints),
    "mutation_endpoints": Json::array([]),
    "arbitrary_sql": Json::boolean(false),
    "deployment_authorized": Json::boolean(deployment_authorized),
    "service_authorized": Json::boolean(deployment_authorized),
    "state": Json::string(
      if deployment_authorized {
        "ready_for_production_service"
      } else {
        "ready_for_service_review"
      },
    ),
  })
}

///|
fn bool_false(
  fields : Map[String, Json],
  key : String,
  message : String,
) -> Unit raise ProductionServiceError {
  if fields.get(key) != Some(Json::boolean(false)) {
    raise fail(message)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: production_service_check <service_manifest> <deployment_gate> <output>",
    )
    @sys.exit(2)
  } else {
    let result = validate(read_json(args[1]), read_json(args[2])) catch {
      ProductionServiceError::InvalidInput(message) => {
        println("production service check failed: " + message)
        @sys.exit(1)
        Json::null()
      }
      ProductionServiceError::Io(_) => {
        println("production service check failed: filesystem error")
        @sys.exit(1)
        Json::null()
      }
    }
    @fs.write_string_to_file(args[3], result.stringify(indent=2) + "\n") catch {
      _ => {
        println("production service check failed: filesystem error")
        @sys.exit(1)
      }
    }
    println(result.stringify())
  }
}
