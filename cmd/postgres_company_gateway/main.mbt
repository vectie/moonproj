///|
/// Native MoonBit session gateway for the Rabbita company surface.
///
/// The gateway keeps the service bearer token private, establishes a bounded
/// HttpOnly session, signs the actor assertion sent to the native PostgreSQL
/// service, and forwards only the explicitly allow-listed company paths.
/// Shell is responsible only for selecting this binary and its environment.

///|
suberror GatewayError {
  InvalidInput(String)
  Upstream(String)
} derive(Debug)

///|
const SESSION_COOKIE = "moonproj_session"

///|
const TRUSTED_IDENTITY_HEADER = "X-Moonproj-Identity"

///|
const TRUSTED_IDENTITY_TIMESTAMP_HEADER = "X-Moonproj-Identity-Timestamp"

///|
const TRUSTED_IDENTITY_SIGNATURE_HEADER = "X-Moonproj-Identity-Signature"

///|
const MAX_BODY_BYTES : Int = 128 * 1024

///|
struct ProxyResult {
  status : Int
  content_type : String
  body : Bytes
  www_authenticate : String?
}

///|
fn fail(message : String) -> GatewayError {
  GatewayError::InvalidInput(message)
}

///|
fn gateway_error_text(error : GatewayError) -> String {
  match error {
    GatewayError::InvalidInput(message) => message
    GatewayError::Upstream(message) => message
  }
}

///|
fn header(request : @http.Request, key : String) -> String {
  request.headers
  .get(key.to_lower())
  .unwrap_or(request.headers.get(key).unwrap_or(""))
  .trim()
  .to_owned()
}

///|
fn valid_identifier(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for char in value.iter() {
    if !((char >= 'A' && char <= 'Z') ||
      (char >= 'a' && char <= 'z') ||
      (char >= '0' && char <= '9') ||
      char == '_' ||
      char == '.' ||
      char == ':' ||
      char == '-') {
      return false
    }
  }
  true
}

///|
fn parse_uint(value : String) -> UInt64? {
  if value.is_empty() {
    return None
  }
  let mut result = 0UL
  for char in value.iter() {
    if char < '0' || char > '9' {
      return None
    }
    result = result * 10UL + (char.to_int() - '0'.to_int()).to_uint64()
  }
  Some(result)
}

///|
fn hmac_hex(secret : String, message : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @encoding/utf8.encode(secret),
      @encoding/utf8.encode(message),
    ),
  )
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    let left_char = left.get_char(index).unwrap_or('\u0000')
    let right_char = right.get_char(index).unwrap_or('\u0000')
    difference = difference | (left_char.to_int() ^ right_char.to_int())
  }
  difference == 0
}

///|
fn verify_trusted_identity(
  user_code : String,
  timestamp : String,
  signature : String,
  secret : String,
) -> Bool {
  if !valid_identifier(user_code) || timestamp.length() > 20 {
    return false
  }
  let issued_at = match parse_uint(timestamp) {
    Some(value) => value
    None => return false
  }
  if signature.length() != 64 {
    return false
  }
  for char in signature.iter() {
    if !((char >= '0' && char <= '9') ||
      (char >= 'a' && char <= 'f') ||
      (char >= 'A' && char <= 'F')) {
      return false
    }
  }
  let now = @env.now() / 1000UL
  let skew = if now >= issued_at { now - issued_at } else { issued_at - now }
  if skew > 60UL {
    return false
  }
  constant_time_equal(
    signature.to_lower(),
    hmac_hex(secret, user_code + ":" + timestamp),
  )
}

///|
fn session_token(secret : String, actor : String, sequence : Int) -> String {
  let now = @env.now().to_string()
  hmac_hex(secret, actor + ":" + now + ":" + sequence.to_string())
}

///|
fn cookie_value(cookie_header : String, name : String) -> String? {
  let prefix = name + "="
  for piece in cookie_header.split(";") {
    let item = piece.trim()
    if item.has_prefix(prefix) {
      let value = item[prefix.length():].to_owned()
      if !value.is_empty() {
        return Some(value)
      }
    }
  }
  None
}

///|
fn query_value(path : String, key : String) -> String? {
  let query = match path.find("?") {
    Some(index) => path[index + 1:].to_owned()
    None => return None
  }
  for pair in query.split("&") {
    match pair.find("=") {
      Some(index) if pair[:index] == key =>
        return Some(pair[index + 1:].to_owned())
      None if pair == key => return Some("")
      _ => ()
    }
  }
  None
}

///|
fn path_only(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
fn json_text(value : Json, key : String) -> String? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool(value : Json, key : String) -> Bool {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
}

///|
fn moonclaw_task_id(value : Json) -> String? {
  match value {
    Object(fields) =>
      match fields.get("task") {
        Some(Object(task)) =>
          match task.get("id") {
            Some(String(id)) => Some(id)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn moonclaw_task_status(value : Json) -> String? {
  match value {
    Object(fields) =>
      match fields.get("task") {
        Some(Object(task)) =>
          match task.get("status") {
            Some(String(status)) => Some(status)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn moonsuite_project_path(workspace_root : String, project : String) -> String? {
  match project {
    "moonproj" => Some(workspace_root + "/moonproj")
    "moonclaw" => Some(workspace_root + "/moonclaw")
    "moonbook" => Some(workspace_root + "/moonbook")
    "moontown" => Some(workspace_root + "/moontown")
    "moondesk" => Some(workspace_root + "/moondesk")
    "moongate" => Some(workspace_root + "/moongate")
    "moonrobo" => Some(workspace_root + "/moonrobo")
    "moonmoon" => Some(workspace_root + "/moonmoon")
    "moonfish" => Some(workspace_root + "/moonfish")
    _ => None
  }
}

///|
fn path_with_identifier(prefix : String, path : String) -> Bool {
  path.has_prefix(prefix) && valid_identifier(path[prefix.length():].to_owned())
}

///|
fn path_with_identifier_suffix(
  prefix : String,
  suffix : String,
  path : String,
) -> Bool {
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return false
  }
  let end = path.length() - suffix.length()
  valid_identifier(path[prefix.length():end].to_owned())
}

///|
fn investment_project_version_path(path : String, suffix : String) -> Bool {
  let prefix = "/api/company/investment/projects/"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return false
  }
  let end = path.length() - suffix.length()
  let parts = path[prefix.length():end].to_owned().split("/").to_array()
  parts.length() == 3 &&
  valid_identifier(parts[0].to_owned()) &&
  parts[1] == "versions" &&
  valid_identifier(parts[2].to_owned())
}

///|
fn ai_hub_command_path(path : String) -> Bool {
  let names = [
    "intake", "confirm", "discard", "query", "rule-from-nl", "approval-draft", "global-ask",
    "query-session", "command",
  ]
  for prefix in ["/api/company/ai-hub/", "/api/company/source/ai-hub/"] {
    for name in names {
      if path == prefix + name {
        return true
      }
    }
  }
  false
}

///|
fn marketing_effect_path(path : String) -> Bool {
  let prefix = "/api/company/marketing/"
  let suffix = "/effect"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return false
  }
  let middle = path[prefix.length():path.length() - suffix.length()].to_owned()
  let parts = middle.split("/").to_array()
  if parts.length() != 2 {
    return false
  }
  let category = parts[0].to_owned()
  (
    category == "campaigns" ||
    category == "placements" ||
    category == "channels" ||
    category == "materials"
  ) &&
  valid_identifier(parts[1].to_owned())
}

///|
fn command_path_allowed(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  match request_method {
    @http.Post =>
      path_with_identifier_suffix(
        "/api/company/engineering/projects/", "/remediations", path,
      ) ||
      path == "/api/company/expenses" ||
      path.has_prefix("/api/company/expenses/") ||
      path == "/api/company/budget-check" ||
      path == "/api/company/contracts" ||
      path.has_prefix("/api/company/contracts/") ||
      path == "/api/company/payment-applies" ||
      path.has_prefix("/api/company/payment-applies/") ||
      path == "/api/company/tenders" ||
      path.has_prefix("/api/company/tenders/") ||
      path == "/api/company/source/tender/tenders" ||
      path.has_prefix("/api/company/source/tender/tenders/") ||
      path == "/api/company/source/tender/awards" ||
      path == "/api/company/source/srm/providers" ||
      path == "/api/company/srm/providers/rescore-all" ||
      path == "/api/company/source/srm/providers/rescore-all" ||
      path == "/api/company/rbac/users" ||
      path == "/api/company/auth/logout" ||
      path == "/api/company/auth/change-password" ||
      path == "/api/company/rbac/roles" ||
      path_with_identifier_suffix("/api/company/rbac/users/", "/roles", path) ||
      path_with_identifier_suffix("/api/company/rbac/users/", "/toggle", path) ||
      path_with_identifier_suffix(
        "/api/company/rbac/users/", "/reset-password", path,
      ) ||
      path == "/api/company/suppliers" ||
      path.has_prefix("/api/company/suppliers/") ||
      path == "/api/company/tender-splits" ||
      path.has_prefix("/api/company/tender-splits/") ||
      path == "/api/company/source/tender/splits" ||
      path == "/api/company/sales" ||
      path.has_prefix("/api/company/sales/") ||
      path == "/api/company/receivables" ||
      path.has_prefix("/api/company/receivables/") ||
      path == "/api/company/delivery" ||
      path.has_prefix("/api/company/delivery/") ||
      path == "/api/company/loans" ||
      path.has_prefix("/api/company/loans/") ||
      path == "/api/company/fund/plans" ||
      path.has_prefix("/api/company/fund/plans/") ||
      path == "/api/company/fund/dispatches" ||
      path.has_prefix("/api/company/fund/dispatches/") ||
      path == "/api/company/plan/tasks" ||
      path.has_prefix("/api/company/plan/tasks/") ||
      path == "/api/company/marketing" ||
      path.has_prefix("/api/company/marketing/") ||
      path == "/api/company/reports/templates" ||
      path == "/api/company/reports/templates/run" ||
      path == "/api/company/export/excel" ||
      path == "/api/company/ai-hub/explain" ||
      path == "/api/company/source/ai-hub/explain" ||
      ai_hub_command_path(path) ||
      path == "/api/company/cashflow/ai-explain" ||
      path == "/api/company/source/cashflow/ai-explain" ||
      path_with_identifier_suffix(
        "/api/company/investment/projects/", "/ai-explain", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/investment/projects/", "/ai-explain", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/investment/projects/", "/excel-imports", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/investment/projects/", "/excel-imports", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/investment/excel-imports/", "/index-upsert", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/investment/excel-imports/", "/index-upsert", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/investment/excel-imports/", "/plan-lines/import", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/investment/excel-imports/", "/plan-lines/import", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/investment/projects/", "/versions", path,
      ) ||
      investment_project_version_path(path, "/activate") ||
      path_with_identifier_suffix(
        "/api/company/investment/versions/", "/indices", path,
      ) ||
      path == "/api/company/plan/ai-suggest-plan" ||
      path == "/api/company/source/plan/ai-suggest-plan" ||
      path == "/api/company/admin/dict/options" ||
      path == "/api/company/source/admin/dict/options" ||
      path == "/api/company/admin/sys-param" ||
      path == "/api/company/source/admin/sys-param" ||
      path == "/api/company/admin/ocr/test" ||
      path == "/api/company/source/admin/ocr/test" ||
      path == "/api/company/admin/llm/test" ||
      path == "/api/company/source/admin/llm/test" ||
      path == "/api/company/notify/llm-test" ||
      path == "/api/company/source/notify/llm-test" ||
      path_with_identifier_suffix("/api/company/warning/", "/resolve", path) ||
      path_with_identifier_suffix("/api/company/warning/", "/ignore", path) ||
      path_with_identifier_suffix("/api/company/warning/", "/to-ticket", path) ||
      path_with_identifier_suffix(
        "/api/company/source/warning/", "/to-ticket", path,
      ) ||
      path == "/api/company/warning/scan" ||
      path == "/api/company/source/warning/scan" ||
      path == "/api/company/warning/custom-rules" ||
      path == "/api/company/source/warning/custom-rules" ||
      path == "/api/company/warning/custom-rules/preview" ||
      path == "/api/company/source/warning/custom-rules/preview" ||
      path == "/api/company/attachments/upload" ||
      path == "/api/company/source/attachments/upload" ||
      path == "/api/company/workflow/instances" ||
      path == "/api/company/source/workflow/instances" ||
      path_with_identifier_suffix(
        "/api/company/workflow/instances/", "/approve", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/workflow/instances/", "/approve", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/workflow/instances/", "/reject", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/workflow/instances/", "/reject", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/workflow/instances/", "/cosigners", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/workflow/instances/", "/cosigners", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/workflow/instances/", "/transfer", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/workflow/instances/", "/transfer", path,
      ) ||
      path_with_identifier("/api/company/attachments/re-extract/", path) ||
      path_with_identifier("/api/company/source/attachments/re-extract/", path) ||
      path_with_identifier("/api/company/webhook/test/", path) ||
      path_with_identifier("/api/company/source/webhook/test/", path) ||
      path == "/api/company/webhook/scan-overdue" ||
      path == "/api/company/source/webhook/scan-overdue" ||
      path == "/api/company/webhook/scan-overdue/preview" ||
      path == "/api/company/source/webhook/scan-overdue/preview" ||
      path == "/api/company/source/invoice/in" ||
      path == "/api/company/source/invoice/out" ||
      path == "/api/company/source/cost/payment-applies" ||
      path == "/api/company/source/cost/contracts" ||
      path == "/api/company/source/cost/milestones" ||
      path_with_identifier_suffix(
        "/api/company/source/cost/contracts/", "/milestones", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/cost/milestones/", "/trigger-event", path,
      ) ||
      path == "/api/company/cost/dynamic-cost" ||
      path == "/api/company/source/mdm/projects" ||
      path == "/api/company/import/project" ||
      path == "/api/company/source/import/project" ||
      path == "/api/company/import/contract" ||
      path == "/api/company/source/import/contract" ||
      path == "/api/company/source/auth/prefs" ||
      path == "/api/company/notify/subscriptions" ||
      path == "/api/company/source/notify/subscriptions" ||
      path == "/api/company/notify/messages/read-all" ||
      path == "/api/company/source/notify/messages/read-all" ||
      path == "/api/company/notify/digest/dispatch" ||
      path == "/api/company/source/notify/digest/dispatch" ||
      path == "/api/company/notify/email-outbox/test" ||
      path == "/api/company/source/notify/email-outbox/test" ||
      path_with_identifier_suffix(
        "/api/company/notify/email-outbox/", "/redeliver", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/notify/email-outbox/", "/redeliver", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/notify/messages/", "/read", path,
      )
    @http.Put =>
      path == "/api/company/auth/profile" ||
      path_with_identifier("/api/company/expenses/", path) ||
      path_with_identifier("/api/company/rbac/users/", path) ||
      path_with_identifier("/api/company/loans/", path) ||
      path_with_identifier("/api/company/webhook/config/", path) ||
      path_with_identifier("/api/company/source/webhook/config/", path) ||
      marketing_effect_path(path) ||
      path_with_identifier("/api/company/source/invoice/in/", path) ||
      path_with_identifier("/api/company/source/invoice/out/", path) ||
      path_with_identifier("/api/company/sales/customers/", path) ||
      path_with_identifier("/api/company/source/sales/customers/", path) ||
      path_with_identifier("/api/company/sales/revenues/", path) ||
      path_with_identifier("/api/company/fund/plans/", path) ||
      path_with_identifier("/api/company/plan/tasks/", path) ||
      path_with_identifier("/api/company/delivery/progress/", path) ||
      path_with_identifier("/api/company/source/cost/payment-applies/", path) ||
      path_with_identifier("/api/company/source/cost/contracts/", path) ||
      path_with_identifier("/api/company/source/cost/milestones/", path) ||
      path_with_identifier("/api/company/source/cost/dynamic-cost/", path) ||
      path_with_identifier("/api/company/source/mdm/projects/", path) ||
      path_with_identifier("/api/company/source/auth/prefs/", path) ||
      path_with_identifier_suffix(
        "/api/company/source/tender/tenders/", "/state", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/investment/projects/", "/subject-mappings", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/investment/projects/", "/subject-mappings", path,
      ) ||
      path_with_identifier("/api/company/investment/plan-lines/", path) ||
      path_with_identifier("/api/company/source/investment/plan-lines/", path) ||
      path_with_identifier("/api/company/investment/indices/", path)
    @http.Patch =>
      path_with_identifier("/api/company/source/srm/providers/", path) ||
      path_with_identifier("/api/company/source/notify/subscriptions/", path) ||
      path_with_identifier("/api/company/admin/dict/options/", path) ||
      path_with_identifier("/api/company/source/admin/dict/options/", path) ||
      path_with_identifier_suffix(
        "/api/company/warning/tickets/", "/status", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/warning/tickets/", "/status", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/warning/tickets/", "/reassign", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/warning/tickets/", "/reassign", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/warning/tickets/", "/extend", path,
      ) ||
      path_with_identifier_suffix(
        "/api/company/source/warning/tickets/", "/extend", path,
      )
    @http.Delete =>
      path_with_identifier("/api/company/expenses/", path) ||
      path_with_identifier("/api/company/loans/", path) ||
      path_with_identifier("/api/company/plan/tasks/", path) ||
      path_with_identifier("/api/company/tenders/", path) ||
      path_with_identifier("/api/company/source/tender/tenders/", path) ||
      path_with_identifier("/api/company/reports/templates/", path) ||
      path_with_identifier("/api/company/source/cost/payment-applies/", path) ||
      path_with_identifier("/api/company/source/cost/contracts/", path) ||
      path_with_identifier("/api/company/source/cost/milestones/", path) ||
      path_with_identifier("/api/company/source/cost/dynamic-cost/", path) ||
      path_with_identifier("/api/company/source/mdm/projects/", path) ||
      path_with_identifier("/api/company/source/auth/prefs/", path) ||
      path_with_identifier("/api/company/rbac/roles/", path) ||
      investment_project_version_path(path, "") ||
      path_with_identifier("/api/company/investment/indices/", path) ||
      path_with_identifier("/api/company/warning/custom-rules/", path) ||
      path_with_identifier("/api/company/source/warning/custom-rules/", path) ||
      path_with_identifier("/api/company/source/invoice/in/", path) ||
      path_with_identifier("/api/company/source/invoice/out/", path) ||
      path_with_identifier("/api/company/sales/customers/", path) ||
      path_with_identifier("/api/company/source/sales/customers/", path) ||
      path_with_identifier("/api/company/sales/revenues/", path) ||
      path_with_identifier("/api/company/delivery/progress/", path) ||
      path_with_identifier("/api/company/source/srm/providers/", path) ||
      path_with_identifier("/api/company/source/notify/subscriptions/", path) ||
      path_with_identifier("/api/company/marketing/campaigns/", path) ||
      path_with_identifier("/api/company/marketing/channels/", path) ||
      path_with_identifier("/api/company/marketing/materials/", path) ||
      path_with_identifier("/api/company/attachments/", path) ||
      path_with_identifier("/api/company/source/attachments/", path)
    _ => false
  }
}

///|
async fn read_body(
  body : &@io.Reader,
  request : @http.Request,
) -> Bytes raise GatewayError {
  let declared = header(request, "Content-Length")
  match parse_uint(declared) {
    Some(length) if length > MAX_BODY_BYTES.to_uint64() =>
      raise fail("request body is too large")
    _ => ()
  }
  let data = body.read_all() catch {
    _ => raise fail("unable to read request body")
  }
  let data = data.binary()
  if data.length() > MAX_BODY_BYTES {
    raise fail("request body is too large")
  }
  data
}

///|
fn normalized_command_body(
  body : Bytes,
  request : @http.Request,
  require_key : Bool,
) -> (Bytes, String?) raise GatewayError {
  if body.length() == 0 {
    if require_key {
      let key = header(request, "Idempotency-Key")
      let key = if key.is_empty() {
        query_value(request.path, "idempotency_key").unwrap_or("")
      } else {
        key
      }
      if key.is_empty() {
        raise fail("idempotency_key or Idempotency-Key is required")
      }
      return (body, Some(key))
    }
    return (body, None)
  }
  let value = @json.parse(@encoding/utf8.decode(body)) catch {
    _ => raise fail("request body must be valid JSON")
  }
  match value {
    Object(fields) => {
      let body_key = match fields.get("idempotency_key") {
        Some(String(key)) if !key.trim().is_empty() =>
          Some(key.trim().to_owned())
        _ => None
      }
      fields.remove("idempotency_key")
      let header_key = header(request, "Idempotency-Key")
      let query_key = query_value(request.path, "idempotency_key").unwrap_or("")
      let key = match body_key {
        Some(value) => Some(value)
        None if !header_key.is_empty() => Some(header_key)
        None if !query_key.is_empty() => Some(query_key)
        None => None
      }
      if require_key && key is None {
        raise fail("idempotency_key or Idempotency-Key is required")
      }
      (@encoding/utf8.encode(Json::object(fields).stringify()), key)
    }
    _ => raise fail("request body must be a JSON object")
  }
}

///|
async fn proxy_request(
  service_uri : String,
  service_token : String,
  actor_signing_secret : String,
  request_method : @http.RequestMethod,
  path : String,
  request : @http.Request,
  body : Bytes,
  idempotency_key : String?,
) -> ProxyResult raise GatewayError {
  try {
    let client = @http.Client(service_uri)
    let extra_headers : Map[String, String] = {
      "Authorization": "Bearer " + service_token,
      "X-Forwarded-Proto": "https",
      "X-Moonproj-Actor": header(request, "X-Moonproj-Actor"),
    }
    let actor = extra_headers["X-Moonproj-Actor"]
    extra_headers["X-Moonproj-Actor-Signature"] = hmac_hex(
      actor_signing_secret, actor,
    )
    if !body.is_empty() {
      let content_type = header(request, "Content-Type")
      extra_headers["Content-Type"] = if content_type.is_empty() {
        "application/json"
      } else {
        content_type
      }
    }
    match idempotency_key {
      Some(key) => extra_headers["Idempotency-Key"] = key
      None => ()
    }
    client.request(request_method, path, extra_headers~)
    if !body.is_empty() {
      client.write(body)
    }
    let response = client.end_request()
    let response_body = client.read_all().binary()
    let content_type = match response.headers.get("content-type") {
      Some(value) => value
      None =>
        match response.headers.get("Content-Type") {
          Some(value) => value
          None => "application/json; charset=utf-8"
        }
    }
    let www_authenticate = match response.headers.get("www-authenticate") {
      Some(value) => Some(value)
      None => response.headers.get("WWW-Authenticate")
    }
    client.close()
    {
      status: response.code,
      content_type,
      body: response_body,
      www_authenticate,
    }
  } catch {
    _ => raise GatewayError::Upstream("company service forwarding failed")
  }
}

///|
fn valid_release_candidate_identifier(value : String) -> Bool {
  !value.trim().is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(fn(char) {
    char.is_ascii_digit() ||
    (char >= 'a' && char <= 'z') ||
    (char >= 'A' && char <= 'Z') ||
    char == '.' ||
    char == '/' ||
    char == '_' ||
    char == '-'
  })
}

///|
async fn submit_moonsuite_audit(
  moonclaw_uri : String,
  workspace_root : String,
  project : String,
  branch : String,
  version : String,
  tag : String,
  audit_sequence : Int,
) -> ProxyResult raise GatewayError {
  for value in [branch, version, tag] {
    if !valid_release_candidate_identifier(value) {
      raise fail("release candidate identifiers are invalid")
    }
  }
  let target = match moonsuite_project_path(workspace_root, project) {
    Some(value) => value
    None => raise fail("project is not registered for engineering audit")
  }
  let target_exists = @fs.exists(target) catch { _ => false }
  if !target_exists {
    raise fail("registered project repository does not exist")
  }
  let control_workspace = workspace_root + "/moonproj"
  let control_workspace_exists = @fs.exists(
    control_workspace + "/moonclaw.jobs.json",
  ) catch {
    _ => false
  }
  if !control_workspace_exists {
    raise fail("MoonProj control workspace does not contain moonclaw.jobs.json")
  }
  let reviewer_workspace = control_workspace + "/.moonsuite/reviewer-workspace"
  let reviewer_workspace_exists = @fs.exists(
    reviewer_workspace + "/.moonsuite/suite-status.json",
  ) catch {
    _ => false
  }
  if !reviewer_workspace_exists {
    raise fail(
      "MoonClaw reviewer workspace is not prepared; run scripts/prepare_moonclaw_engineering_runtime.sh",
    )
  }
  let audit_id = "audit-" +
    project +
    "-" +
    @env.now().to_string() +
    "-" +
    audit_sequence.to_string()
  let draft_relative_path = "engineering/evidence/inbox/" +
    audit_id +
    ".producer.json"
  let evidence_relative_path = "engineering/evidence/inbox/" +
    audit_id +
    ".json"
  let draft_path = control_workspace + "/" + draft_relative_path
  let evidence_path = control_workspace + "/" + evidence_relative_path
  let release_handover = workspace_root +
    "/moongate/docs/LEPUSA_APP_RELEASE_HANDOVER.md"
  let common_constraints = "Use pure MoonBit plus shell tooling only: never invoke python or python3. " +
    "Never use an unbounded file-search tool. Bound every command output and receipt to 64 KiB; " +
    "prefer counts, selected paths, exit codes, timestamps, and digests. " +
    "The canonical Gate meanings are fixed: G1 intent/candidate identity; G2 functional completeness; " +
    "G3 UI/accessibility/responsive/guidance; G4 build/test/engineering quality; " +
    "G5 integration/persistence/data consistency; G6 security/compliance/secrets; " +
    "G7 artifacts/compatibility/packaging; G8 install/runtime/rollback/recovery/cleanup; " +
    "G9 repository/branch/commit/tag/checksum/release control. Do not remap them. "
  let producer_prompt = "moonsuite unified engineering evidence producer. Audit the registered Moon Suite project '" +
    project +
    "' at " +
    target +
    " for requested branch='" +
    branch +
    "', version='" +
    version +
    "', tag='" +
    tag +
    "'. Resolve and record the exact current full commit and remote. " +
    "Use $moonsuite-production-gate to produce one candidate-bound draft with R1-R3 and G1-G9. " +
    "Apply the Lepusa release procedure at " +
    release_handover +
    " when it is relevant to this candidate. Do not invent scores and do not review your own work. " +
    "Return unknown when evidence is missing and include every command receipt. " +
    common_constraints +
    "Your only durable output is the producer draft " +
    draft_relative_path +
    " inside the MoonProj control workspace. " +
    "Write it atomically with shell and jq. It must use schema='moonsuite.engineering-evidence-draft.v1', " +
    "contain exact candidate identity, producer_agent='" +
    audit_id +
    ":producer', and R1-R3 plus G1-G9 once each. " +
    "Do not modify the audited repository or any other MoonProj file. Do not tag, push, publish, sign, or notarize."
  try {
    let producer_task_id = start_moonclaw_audit_task(
      moonclaw_uri,
      control_workspace,
      "MoonProj evidence producer: " + project + " " + tag,
      producer_prompt,
    )
    let reviewer_prompt = "moonsuite independent engineering evidence reviewer. You are a separate MoonClaw task from producer task '" +
      producer_task_id +
      "'. Wait up to 15 minutes for " +
      draft_path +
      ", then use $moonsuite-evidence-review to verify that draft against project '" +
      project +
      "' at " +
      target +
      " and requested branch='" +
      branch +
      "', version='" +
      version +
      "', tag='" +
      tag +
      "'. Rerun a bounded risk-weighted sample in a separate ephemeral tree. " +
      common_constraints +
      "Your only durable output is " +
      evidence_path +
      ". Write it atomically with shell and jq only after review. It must exactly follow " +
      "schema='moonsuite.engineering-evidence.v2', preserve R1-R3 and G1-G9 once each, and have " +
      "exactly these sorted top-level keys: branch,commit,findings,gates,observed_at,project," +
      "redlines,repository,review,schema,tag,version. Remove the draft-only top-level producer_agent; " +
      "each redline/Gate must have exactly id,missing,receipts,status,summary and review must have " +
      "exactly missing_evidence,producer_agent,rejected_claims,reviewer_agent,verified_receipts,verdict. " +
      "Mechanically assert all exact key sets with jq before the atomic move. Then " +
      "set review.producer_agent='" +
      audit_id +
      ":producer' and review.reviewer_agent='" +
      audit_id +
      ":reviewer', and cite producer_task_id='" +
      producer_task_id +
      "' in verified_receipts. Reject unsupported claims. Do not modify the audited repository, " +
      "draft, or other MoonProj files. Do not tag, push, publish, sign, or notarize."
    let reviewer_task_id = start_moonclaw_audit_task(
      moonclaw_uri,
      reviewer_workspace,
      "MoonProj evidence reviewer: " + project + " " + tag,
      reviewer_prompt,
    )
    {
      status: 202,
      content_type: "application/json; charset=utf-8",
      body: @encoding/utf8.encode(
        Json::object({
          "accepted": Json::boolean(true),
          "project": Json::string(project),
          "audit_id": Json::string(audit_id),
          "task_id": Json::string(reviewer_task_id),
          "producer_task_id": Json::string(producer_task_id),
          "result_state": Json::string("unknown_until_independent_review"),
        }).stringify(),
      ),
      www_authenticate: None,
    }
  } catch {
    _ => raise GatewayError::Upstream("MoonClaw audit submission failed")
  }
}

///|
async fn start_moonclaw_audit_task(
  moonclaw_uri : String,
  cwd : String,
  name : String,
  prompt : String,
) -> String raise GatewayError {
  let payload = Json::object({
    "name": Json::string(name),
    "cwd": Json::string(cwd),
    "message": Json::object({
      "role": Json::string("user"),
      "content": Json::string(prompt),
    }),
    "web_search": Json::boolean(false),
  }).stringify()
  try {
    let client = @http.Client(moonclaw_uri)
    client.request(@http.Post, "/v1/task", extra_headers={
      "Content-Type": "application/json; charset=utf-8",
    })
    client.write(@encoding/utf8.encode(payload))
    let response = client.end_request()
    let response_body = client.read_all().binary()
    let status = response.code
    client.close()
    if status != 201 && status != 409 {
      raise GatewayError::Upstream(
        "MoonClaw rejected an engineering audit task with status " +
        status.to_string(),
      )
    }
    let upstream = @json.parse(@encoding/utf8.decode(response_body)) catch {
      _ => Json::null()
    }
    match moonclaw_task_id(upstream) {
      Some(task_id) if !task_id.is_empty() => task_id
      _ =>
        raise GatewayError::Upstream(
          "MoonClaw response did not contain a task id",
        )
    }
  } catch {
    GatewayError::Upstream(message) => raise GatewayError::Upstream(message)
    _ => raise GatewayError::Upstream("MoonClaw audit task request failed")
  }
}

///|
async fn poll_moonsuite_audit(
  moonclaw_uri : String,
  workspace_root : String,
  service_uri : String,
  service_token : String,
  actor_signing_secret : String,
  request : @http.Request,
  actor : String,
  audit_id : String,
  project : String,
  task_id : String,
) -> ProxyResult raise GatewayError {
  if !valid_identifier(audit_id) ||
    !valid_identifier(project) ||
    !valid_identifier(task_id) ||
    moonsuite_project_path(workspace_root, project) is None {
    raise fail("invalid engineering audit polling identifiers")
  }
  let task_payload = try {
    let client = @http.Client(moonclaw_uri)
    client.request(@http.Get, "/v1/task/" + task_id)
    let response = client.end_request()
    let bytes = client.read_all().binary()
    let status = response.code
    client.close()
    if status != 200 {
      raise GatewayError::Upstream("MoonClaw task status request failed")
    }
    @json.parse(@encoding/utf8.decode(bytes)) catch {
      _ => raise GatewayError::Upstream("MoonClaw task status was not JSON")
    }
  } catch {
    _ => raise GatewayError::Upstream("MoonClaw task status request failed")
  }
  let task_status = moonclaw_task_status(task_payload).unwrap_or("unknown")
  if task_status != "idle" {
    return {
      status: 200,
      content_type: "application/json; charset=utf-8",
      body: @encoding/utf8.encode(
        Json::object({
          "audit_id": audit_id,
          "project": project,
          "task_id": task_id,
          "state": if task_status == "running" || task_status == "generating" {
            "running"
          } else {
            "task_" + task_status
          },
        }).stringify(),
      ),
      www_authenticate: None,
    }
  }
  let evidence_path = workspace_root +
    "/moonproj/engineering/evidence/inbox/" +
    audit_id +
    ".json"
  if !(@fs.exists(evidence_path) catch { _ => false }) {
    return {
      status: 200,
      content_type: "application/json; charset=utf-8",
      body: @encoding/utf8.encode(
        Json::object({
          "audit_id": audit_id,
          "project": project,
          "task_id": task_id,
          "state": "awaiting_artifact",
        }).stringify(),
      ),
      www_authenticate: None,
    }
  }
  let evidence = @fs.read_file(evidence_path) catch {
    _ =>
      raise GatewayError::Upstream("unable to read MoonClaw evidence artifact")
  }
  if evidence.binary().length() > MAX_BODY_BYTES {
    raise fail("MoonClaw evidence artifact is too large")
  }
  let envelope = @json.parse(@encoding/utf8.decode(evidence.binary())) catch {
    _ => raise fail("MoonClaw evidence artifact is not valid JSON")
  }
  let ingest_body = Json::object({
    "audit_id": audit_id,
    "project": project,
    "task_id": task_id,
    "envelope": envelope,
  }).stringify()
  let service_request : @http.Request = {
    meth: @http.Post,
    path: "/api/company/engineering/audits",
    headers: request.headers,
  }
  service_request.headers["X-Moonproj-Actor"] = actor
  let result = proxy_request(
    service_uri,
    service_token,
    actor_signing_secret,
    @http.Post,
    service_request.path,
    service_request,
    @encoding/utf8.encode(ingest_body),
    Some(audit_id),
  )
  if result.status == 200 || result.status == 201 {
    let payload = @json.parse(@encoding/utf8.decode(result.body)) catch {
      _ => Json::null()
    }
    return {
      status: 200,
      content_type: "application/json; charset=utf-8",
      body: @encoding/utf8.encode(
        Json::object({
          "audit_id": audit_id,
          "project": project,
          "task_id": task_id,
          "state": "ingested",
          "result": payload,
        }).stringify(),
      ),
      www_authenticate: None,
    }
  }
  result
}

///|
async fn verify_trusted_profile(
  service_uri : String,
  service_token : String,
  actor_signing_secret : String,
  user_code : String,
) -> Bool raise GatewayError {
  let request : @http.Request = {
    meth: @http.Get,
    path: "/api/company/auth/me?userCode=" + user_code,
    headers: { "X-Moonproj-Actor": user_code },
  }
  let result = proxy_request(
    service_uri,
    service_token,
    actor_signing_secret,
    @http.Get,
    request.path,
    request,
    b"",
    None,
  )
  if result.status != 200 {
    return false
  }
  let payload = @json.parse(@encoding/utf8.decode(result.body)) catch {
    _ => return false
  }
  match payload {
    Object(fields) =>
      match fields.get("data") {
        Some(data) => json_bool(data, "enabled")
        None => false
      }
    _ => false
  }
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  request_method : @http.RequestMethod,
  status : Int,
  payload : Json,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  let headers : Map[String, String] = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  }
  for key, value in extra_headers {
    headers[key] = value
  }
  conn.send_response(status, status_reason(status), extra_headers=headers)
  if status != 204 && !(request_method is @http.Head) {
    conn.write(payload.stringify())
  }
  conn.end_response()
}

///|
async fn send_bytes(
  conn : @http.ServerConnection,
  request_method : @http.RequestMethod,
  result : ProxyResult,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  let headers : Map[String, String] = {
    "Content-Type": result.content_type,
    "Cache-Control": "no-store",
  }
  match result.www_authenticate {
    Some(value) => headers["WWW-Authenticate"] = value
    None => ()
  }
  for key, value in extra_headers {
    headers[key] = value
  }
  conn.send_response(
    result.status,
    status_reason(result.status),
    extra_headers=headers,
  )
  if !(request_method is @http.Head) {
    conn.write(result.body)
  }
  conn.end_response()
}

///|
fn status_reason(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    204 => "No Content"
    400 => "Bad Request"
    401 => "Unauthorized"
    404 => "Not Found"
    405 => "Method Not Allowed"
    500 => "Internal Server Error"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "Error"
  }
}

///|
fn static_content_type(path : String) -> String {
  if path.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if path.has_suffix(".js") || path.has_suffix(".mjs") {
    "text/javascript; charset=utf-8"
  } else if path.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if path.has_suffix(".json") {
    "application/json; charset=utf-8"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else if path.has_suffix(".png") {
    "image/png"
  } else if path.has_suffix(".jpg") || path.has_suffix(".jpeg") {
    "image/jpeg"
  } else if path.has_suffix(".woff2") {
    "font/woff2"
  } else {
    "application/octet-stream"
  }
}

///|
fn static_relative_path(path : String) -> String? {
  let clean = path_only(path)
  if clean.contains("..") || clean.contains("\\") || clean.contains("\u0000") {
    return None
  }
  let relative = clean.trim_start(chars="/")
  if relative.is_empty() || !relative.contains(".") {
    Some("index.html")
  } else {
    Some(relative.to_owned())
  }
}

///|
async fn serve_static(
  public_dir : String?,
  path : String,
  request_method : @http.RequestMethod,
  conn : @http.ServerConnection,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  let file_path : String? = match public_dir {
    None => None
    Some(directory) =>
      match static_relative_path(path) {
        Some(relative) => Some(directory + "/" + relative)
        None => None
      }
  }
  match file_path {
    None =>
      send_json(
        conn,
        request_method,
        404,
        Json::object({
          "error": Json::string("static public directory is not configured"),
        }),
      )
    Some(file_path) => {
      if !@fs.exists(file_path) {
        send_json(
          conn,
          request_method,
          404,
          Json::object({ "error": Json::string("static file not found") }),
        )
        return
      }
      let body = @fs.read_file(file_path) catch {
        _ => {
          send_json(
            conn,
            request_method,
            404,
            Json::object({ "error": Json::string("static file not found") }),
          )
          return
        }
      }
      let body = body.binary()
      let content_type = static_content_type(file_path)
      let result : ProxyResult = {
        status: 200,
        content_type,
        body,
        www_authenticate: None,
      }
      send_bytes(conn, request_method, result, extra_headers~)
    }
  }
}

///|
async fn handle(
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  service_uri : String,
  moonclaw_uri : String,
  moonsuite_workspace_root : String,
  service_token : String,
  actor_signing_secret : String,
  session_secret : String,
  dev_user : String,
  dev_password : String,
  actor_id : String,
  trusted_identity_secret : String?,
  desktop_actor : String?,
  public_dir : String?,
  sessions : Map[String, String],
  sequence : Ref[Int],
) -> Unit {
  let path = path_only(request.path)
  if request.meth is @http.Options {
    send_json(conn, request.meth, 204, Json::null(), extra_headers={
      "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, Idempotency-Key, " +
      TRUSTED_IDENTITY_HEADER +
      ", " +
      TRUSTED_IDENTITY_TIMESTAMP_HEADER +
      ", " +
      TRUSTED_IDENTITY_SIGNATURE_HEADER,
    })
    return
  }
  if path == "/health" &&
    (request.meth is @http.Get || request.meth is @http.Head) {
    let health_request : @http.Request = {
      meth: request.meth,
      path: "/api/health",
      headers: request.headers,
    }
    let result = proxy_request(
      service_uri,
      service_token,
      actor_signing_secret,
      request.meth,
      health_request.path,
      health_request,
      b"",
      None,
    ) catch {
      _ =>
        {
          status: 503,
          content_type: "application/json; charset=utf-8",
          body: b"{\"ok\":false,\"error\":\"company service unavailable\"}",
          www_authenticate: None,
        }
    }
    send_bytes(conn, request.meth, result)
    return
  }
  if path == "/api/session" && request.meth is @http.Get {
    match cookie_value(header(request, "Cookie"), SESSION_COOKIE) {
      Some(cookie) =>
        match sessions.get(cookie) {
          Some(actor) =>
            send_json(
              conn,
              request.meth,
              200,
              Json::object({
                "authenticated": Json::boolean(true),
                "actor_id": Json::string(actor),
              }),
            )
          None =>
            send_json(
              conn,
              request.meth,
              401,
              Json::object({
                "authenticated": Json::boolean(false),
                "error": Json::string("session required"),
              }),
            )
        }
      None =>
        send_json(
          conn,
          request.meth,
          401,
          Json::object({
            "authenticated": Json::boolean(false),
            "error": Json::string("session required"),
          }),
        )
    }
    return
  }
  if path == "/api/session/login" && request.meth is @http.Post {
    match trusted_identity_secret {
      Some(secret) => {
        let user_code = header(request, TRUSTED_IDENTITY_HEADER)
        let timestamp = header(request, TRUSTED_IDENTITY_TIMESTAMP_HEADER)
        let signature = header(request, TRUSTED_IDENTITY_SIGNATURE_HEADER)
        if !verify_trusted_identity(user_code, timestamp, signature, secret) {
          send_json(
            conn,
            request.meth,
            401,
            Json::object({
              "authenticated": Json::boolean(false),
              "error": Json::string("trusted identity assertion rejected"),
            }),
          )
          return
        }
        let enabled = verify_trusted_profile(
          service_uri, service_token, actor_signing_secret, user_code,
        ) catch {
          _ => false
        }
        if !enabled {
          send_json(
            conn,
            request.meth,
            401,
            Json::object({
              "authenticated": Json::boolean(false),
              "error": Json::string("trusted identity profile rejected"),
            }),
          )
          return
        }
        let token = session_token(session_secret, user_code, sequence.val)
        sequence.val += 1
        sessions[token] = user_code
        send_json(
          conn,
          request.meth,
          200,
          Json::object({
            "authenticated": Json::boolean(true),
            "actor_id": Json::string(user_code),
            "identity_source": Json::string("trusted_upstream"),
          }),
          extra_headers={
            "Set-Cookie": SESSION_COOKIE +
            "=" +
            token +
            "; HttpOnly; Path=/; SameSite=Strict; Secure; Max-Age=900",
          },
        )
      }
      None => {
        let body = read_body(body_reader, request) catch {
          error => {
            send_json(
              conn,
              request.meth,
              400,
              Json::object({
                "authenticated": Json::boolean(false),
                "error": Json::string(gateway_error_text(error)),
              }),
            )
            return
          }
        }
        let payload = @json.parse(@encoding/utf8.decode(body)) catch {
          _ => {
            send_json(
              conn,
              request.meth,
              400,
              Json::object({
                "authenticated": Json::boolean(false),
                "error": Json::string("request body must be valid JSON"),
              }),
            )
            return
          }
        }
        let supplied_user = json_text(payload, "user_code").unwrap_or("")
        let supplied_password = json_text(payload, "password").unwrap_or("")
        if supplied_user.is_empty() || supplied_password.is_empty() {
          send_json(
            conn,
            request.meth,
            400,
            Json::object({
              "authenticated": Json::boolean(false),
              "error": Json::string("user_code and password are required"),
            }),
          )
          return
        }
        let native_request : @http.Request = {
          meth: @http.Post,
          path: "/api/company/auth/login",
          headers: request.headers,
        }
        let native_result = proxy_request(
          service_uri,
          service_token,
          actor_signing_secret,
          @http.Post,
          native_request.path,
          native_request,
          body,
          None,
        ) catch {
          _ =>
            {
              status: 0,
              content_type: "application/json",
              body: b"",
              www_authenticate: None,
            }
        }
        let native_payload = @json.parse(
          @encoding/utf8.decode(native_result.body),
        ) catch {
          _ => Json::null()
        }
        if native_result.status == 200 &&
          json_bool(native_payload, "authenticated") {
          let native_actor = json_text(native_payload, "actor_id").unwrap_or(
            supplied_user,
          )
          let token = session_token(session_secret, native_actor, sequence.val)
          sequence.val += 1
          sessions[token] = native_actor
          send_json(
            conn,
            request.meth,
            200,
            Json::object({
              "authenticated": Json::boolean(true),
              "actor_id": Json::string(native_actor),
              "identity_source": Json::string("postgresql_credential"),
            }),
            extra_headers={
              "Set-Cookie": SESSION_COOKIE +
              "=" +
              token +
              "; HttpOnly; Path=/; SameSite=Strict",
            },
          )
          return
        }
        if !constant_time_equal(supplied_user, dev_user) ||
          !constant_time_equal(supplied_password, dev_password) {
          send_json(
            conn,
            request.meth,
            401,
            Json::object({
              "authenticated": Json::boolean(false),
              "error": Json::string("invalid credentials"),
            }),
          )
          return
        }
        let token = session_token(session_secret, actor_id, sequence.val)
        sequence.val += 1
        sessions[token] = actor_id
        send_json(
          conn,
          request.meth,
          200,
          Json::object({
            "authenticated": Json::boolean(true),
            "actor_id": Json::string(actor_id),
            "identity_source": Json::string("development_fixture"),
          }),
          extra_headers={
            "Set-Cookie": SESSION_COOKIE +
            "=" +
            token +
            "; HttpOnly; Path=/; SameSite=Strict",
          },
        )
      }
    }
    return
  }
  if path == "/api/session/logout" && request.meth is @http.Post {
    match cookie_value(header(request, "Cookie"), SESSION_COOKIE) {
      Some(cookie) => sessions.remove(cookie)
      None => ()
    }
    send_json(
      conn,
      request.meth,
      200,
      Json::object({ "authenticated": Json::boolean(false) }),
      extra_headers={
        "Set-Cookie": SESSION_COOKIE +
        "=; Max-Age=0; HttpOnly; Path=/; SameSite=Strict",
      },
    )
    return
  }
  if path.has_prefix("/api/") {
    let actor = match cookie_value(header(request, "Cookie"), SESSION_COOKIE) {
      Some(cookie) => sessions.get(cookie)
      None => None
    }
    match actor {
      None => {
        send_json(
          conn,
          request.meth,
          401,
          Json::object({
            "authenticated": Json::boolean(false),
            "error": Json::string("session required"),
          }),
        )
        return
      }
      Some(actor) => {
        let engineering_audit_prefix = "/api/moonsuite/engineering/audits/"
        if path.has_prefix(engineering_audit_prefix) &&
          request.meth is @http.Get {
          let audit_id = path[engineering_audit_prefix.length():].to_owned()
          let project = query_value(request.path, "project").unwrap_or("")
          let task_id = query_value(request.path, "task_id").unwrap_or("")
          let result = poll_moonsuite_audit(
            moonclaw_uri, moonsuite_workspace_root, service_uri, service_token, actor_signing_secret,
            request, actor, audit_id, project, task_id,
          ) catch {
            error => {
              let status = match error {
                GatewayError::InvalidInput(_) => 400
                GatewayError::Upstream(_) => 503
              }
              send_json(
                conn,
                request.meth,
                status,
                Json::object({
                  "error": Json::string(gateway_error_text(error)),
                }),
              )
              return
            }
          }
          send_bytes(conn, request.meth, result)
          return
        }
        if path == "/api/moonsuite/engineering/audits" &&
          request.meth is @http.Post {
          let body = read_body(body_reader, request) catch {
            error => {
              send_json(
                conn,
                request.meth,
                400,
                Json::object({
                  "error": Json::string(gateway_error_text(error)),
                }),
              )
              return
            }
          }
          let payload = @json.parse(@encoding/utf8.decode(body)) catch {
            _ => Json::null()
          }
          let project = json_text(payload, "project").unwrap_or("")
          let branch = json_text(payload, "branch").unwrap_or("")
          let version = json_text(payload, "version").unwrap_or("")
          let tag = json_text(payload, "tag").unwrap_or("")
          let audit_sequence = sequence.val
          sequence.val += 1
          let result = submit_moonsuite_audit(
            moonclaw_uri, moonsuite_workspace_root, project, branch, version, tag,
            audit_sequence,
          ) catch {
            error => {
              let status = match error {
                GatewayError::InvalidInput(_) => 400
                GatewayError::Upstream(_) => 503
              }
              send_json(
                conn,
                request.meth,
                status,
                Json::object({
                  "error": Json::string(gateway_error_text(error)),
                }),
              )
              return
            }
          }
          send_bytes(conn, request.meth, result)
          return
        }
        if !(request.meth is @http.Get) &&
          !(request.meth is @http.Head) &&
          !command_path_allowed(request.meth, path) {
          send_json(
            conn,
            request.meth,
            404,
            Json::object({
              "error": Json::string(
                "development gateway command is not allow-listed",
              ),
            }),
          )
          return
        }
        let body = if request.meth is @http.Get || request.meth is @http.Head {
          b""
        } else {
          read_body(body_reader, request) catch {
            error => {
              send_json(
                conn,
                request.meth,
                400,
                Json::object({
                  "error": Json::string(gateway_error_text(error)),
                }),
              )
              return
            }
          }
        }
        let require_key = if request.meth is @http.Delete &&
          (
            path_with_identifier("/api/company/attachments/", path) ||
            path_with_identifier("/api/company/source/attachments/", path)
          ) {
          false
        } else {
          !(request.meth is @http.Post) ||
          (
            path != "/api/company/budget-check" &&
            path != "/api/company/export/excel" &&
            path != "/api/company/ai-hub/explain" &&
            path != "/api/company/source/ai-hub/explain" &&
            path != "/api/company/cashflow/ai-explain" &&
            path != "/api/company/source/cashflow/ai-explain" &&
            !path_with_identifier_suffix(
              "/api/company/investment/projects/", "/ai-explain", path,
            ) &&
            !path_with_identifier_suffix(
              "/api/company/source/investment/projects/", "/ai-explain", path,
            ) &&
            path != "/api/company/plan/ai-suggest-plan" &&
            path != "/api/company/source/plan/ai-suggest-plan" &&
            !path_with_identifier("/api/company/attachments/re-extract/", path) &&
            !path_with_identifier(
              "/api/company/source/attachments/re-extract/", path,
            )
          )
        }
        let (body, key) = if request.meth is @http.Get ||
          request.meth is @http.Head {
          (body, None)
        } else {
          normalized_command_body(body, request, require_key) catch {
            error => {
              send_json(
                conn,
                request.meth,
                400,
                Json::object({
                  "error": Json::string(gateway_error_text(error)),
                }),
              )
              return
            }
          }
        }
        let request_for_proxy : @http.Request = {
          meth: request.meth,
          path: request.path,
          headers: request.headers,
        }
        request_for_proxy.headers["X-Moonproj-Actor"] = actor
        let result = proxy_request(
          service_uri,
          service_token,
          actor_signing_secret,
          request.meth,
          request.path,
          request_for_proxy,
          body,
          key,
        ) catch {
          error => {
            send_json(
              conn,
              request.meth,
              503,
              Json::object({ "error": Json::string(gateway_error_text(error)) }),
            )
            return
          }
        }
        send_bytes(conn, request.meth, result)
      }
    }
    return
  }
  if request.meth is @http.Get || request.meth is @http.Head {
    let static_headers : Map[String, String] = {}
    match desktop_actor {
      Some(actor) if path == "/" || path == "/index.html" => {
        let authenticated = match
          cookie_value(header(request, "Cookie"), SESSION_COOKIE) {
          Some(cookie) => sessions.get(cookie) is Some(_)
          None => false
        }
        if !authenticated {
          let token = session_token(session_secret, actor, sequence.val)
          sequence.val += 1
          sessions[token] = actor
          static_headers["Set-Cookie"] = SESSION_COOKIE +
            "=" +
            token +
            "; HttpOnly; Path=/; SameSite=Strict; Max-Age=28800"
        }
      }
      _ => ()
    }
    serve_static(
      public_dir,
      request.path,
      request.meth,
      conn,
      extra_headers=static_headers,
    )
  } else {
    send_json(
      conn,
      request.meth,
      405,
      Json::object({ "error": Json::string("method not allowed") }),
    )
  }
}

///|
fn option(args : Array[String], name : String) -> String? {
  for index in 1..<args.length() {
    if args[index] == name {
      match args.get(index + 1) {
        Some(value) => return Some(value)
        None => return None
      }
    }
  }
  None
}

///|
fn required_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
async fn main {
  let args = @env.args()
  let service_token_env = option(args, "--service-token-env").unwrap_or(
    "MOONPROJ_SERVICE_TOKEN",
  )
  let actor_secret_env = option(args, "--actor-signing-secret-env").unwrap_or(
    "MOONPROJ_ACTOR_SIGNING_SECRET",
  )
  let session_secret_env = option(args, "--session-secret-env").unwrap_or(
    "MOONPROJ_SESSION_SECRET",
  )
  let dev_user_env = option(args, "--dev-user-env").unwrap_or(
    "MOONPROJ_DEV_USER",
  )
  let dev_password_env = option(args, "--dev-password-env").unwrap_or(
    "MOONPROJ_DEV_PASSWORD",
  )
  let actor_id = option(args, "--actor-id").unwrap_or(
    @env.get_env_var("MOONPROJ_DEV_ACTOR_ID").unwrap_or("rabbita-user"),
  )
  let service_token = required_env(service_token_env)
  let actor_signing_secret = required_env(actor_secret_env)
  let session_secret = required_env(session_secret_env)
  if service_token.is_empty() ||
    actor_signing_secret.is_empty() ||
    session_secret.is_empty() {
    println(
      "service, actor-signing, and session secret environment variables are required",
    )
    @sys.exit(2)
  }
  if !valid_identifier(actor_id) {
    println("gateway actor id contains unsupported characters")
    @sys.exit(2)
  }
  let trusted_identity_secret = match
    option(args, "--trusted-identity-secret-env") {
    Some(name) => {
      let value = required_env(name)
      if value.is_empty() {
        println("trusted identity secret environment variable is not set")
        @sys.exit(2)
      }
      Some(value)
    }
    None => None
  }
  let dev_user = required_env(dev_user_env)
  let dev_password = required_env(dev_password_env)
  if trusted_identity_secret is None &&
    (dev_user.is_empty() || dev_password.is_empty()) {
    println("development session credentials are not set")
    @sys.exit(2)
  }
  let host = option(args, "--host").unwrap_or(
    @env.get_env_var("COMPANY_GATEWAY_HOST").unwrap_or("127.0.0.1"),
  )
  if host == "0.0.0.0" || host == "::" || host == "[::]" {
    println("gateway must bind privately")
    @sys.exit(2)
  }
  let port = option(args, "--port").unwrap_or(
    @env.get_env_var("COMPANY_GATEWAY_PORT").unwrap_or("4173"),
  )
  let service_host = option(args, "--service-host").unwrap_or(
    @env.get_env_var("COMPANY_SERVICE_HOST").unwrap_or("127.0.0.1"),
  )
  let service_port = option(args, "--service-port").unwrap_or(
    @env.get_env_var("COMPANY_SERVICE_PORT").unwrap_or("4174"),
  )
  let public_dir = match option(args, "--public-dir") {
    Some(value) => Some(value)
    None => @env.get_env_var("COMPANY_GATEWAY_PUBLIC_DIR")
  }
  let moonclaw_uri = option(args, "--moonclaw-uri").unwrap_or(
    @env.get_env_var("MOONCLAW_DAEMON_URI").unwrap_or("http://localhost:18123"),
  )
  let moonsuite_workspace_root = option(args, "--moonsuite-workspace-root").unwrap_or(
    @env.get_env_var("MOONSUITE_WORKSPACE_ROOT").unwrap_or(
      @fs.realpath("..") catch {
        _ => ".."
      },
    ),
  )
  let desktop_actor = match @env.get_env_var("MOONPROJ_DESKTOP_ACTOR") {
    Some(value) if !value.is_empty() => {
      if !valid_identifier(value) {
        println("desktop actor contains unsupported characters")
        @sys.exit(2)
      }
      if host != "127.0.0.1" && host != "localhost" && host != "::1" {
        println("desktop session bootstrap requires a loopback gateway")
        @sys.exit(2)
      }
      Some(value)
    }
    _ => None
  }
  let address = @socket.Addr::parse(host + ":" + port) catch {
    _ => {
      println("invalid gateway listen address")
      @sys.exit(2)
      @socket.Addr::parse("127.0.0.1:4173")
    }
  }
  let server = @http.Server(address, reuse_addr=true) catch {
    _ => {
      println("cannot start native company gateway")
      @sys.exit(1)
      @http.Server(@socket.Addr::parse("127.0.0.1:4173"), reuse_addr=true) catch {
        _ => panic()
      }
    }
  }
  let sessions : Map[String, String] = {}
  let sequence = Ref(0)
  let service_uri = "http://" + service_host + ":" + service_port
  println("company MoonBit gateway listening on http://" + host + ":" + port)
  server.run_forever(
    (request, body, conn) => {
      handle(
        request, body, conn, service_uri, moonclaw_uri, moonsuite_workspace_root,
        service_token, actor_signing_secret, session_secret, dev_user, dev_password,
        actor_id, trusted_identity_secret, desktop_actor, public_dir, sessions, sequence,
      )
    },
    allow_failure=true,
  )
}
