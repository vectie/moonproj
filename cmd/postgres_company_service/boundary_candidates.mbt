///|
/// Explicit boundaries for source actions whose storage or destructive policy
/// is not yet accepted by the native PostgreSQL service.

///|
fn import_batch_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = ["/api/company/import/", "/api/company/source/import/"]
  for prefix in prefixes {
    if request_method is @http.Post && path.has_prefix(prefix) {
      let biz_type = path[prefix.length():].to_owned()
      if biz_type == "project" || biz_type == "contract" {
        return Some(biz_type)
      }
    }
  }
  None
}

///|
fn import_batch_gate(biz_type : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(46001),
      "message": Json::string(
        "批量导入需要逐行校验、事务提交和负责人确认；当前 native 服务仅提供模板读取。",
      ),
      "data": Json::object({
        "bizType": Json::string(biz_type),
        "rowsAccepted": Json::number(0),
        "mode": Json::string("gated"),
      }),
      "source_kind": Json::string("import_batch_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
fn sales_customer_delete_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = [
    "/api/company/sales/customers/", "/api/company/source/sales/customers/",
  ]
  for prefix in prefixes {
    if request_method is @http.Delete && path.has_prefix(prefix) {
      let customer_guid = path[prefix.length():].to_owned()
      if valid_identifier(customer_guid) {
        return Some(customer_guid)
      }
    }
  }
  None
}

///|
fn sales_customer_delete_gate(customer_guid : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(48001),
      "message": Json::string(
        "客户删除被策略门禁；当前 native 服务只允许后续归档，不执行破坏性删除。",
      ),
      "data": Json::object({
        "customerGuid": Json::string(customer_guid),
        "deleted": Json::boolean(false),
        "archiveAvailable": Json::boolean(false),
      }),
      "source_kind": Json::string("sales_customer_delete_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
fn cbs_mutation_boundary_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefix = "/api/company/cbs/"
  if !path.has_prefix(prefix) {
    return None
  }
  let rest = path[prefix.length():].to_owned()
  if request_method is @http.Post {
    if rest == "r0/resolve" ||
      rest == "demo/contracts" ||
      rest == "demo/legacy" ||
      rest == "changes" {
      return Some(rest)
    }
    let parts = rest.split("/").to_array()
    if parts.length() == 2 && valid_identifier(parts[1].to_owned()) {
      if parts[0].to_owned() == "contracts" {
        return Some("contracts/" + parts[1].to_owned())
      }
      if parts[0].to_owned() == "changes" {
        return Some("changes/" + parts[1].to_owned())
      }
    }
    if parts.length() == 3 &&
      valid_identifier(parts[1].to_owned()) &&
      parts[0].to_owned() == "contracts" {
      if parts[2].to_owned() == "submit-approval" ||
        parts[2].to_owned() == "approve" ||
        parts[2].to_owned() == "reject" ||
        parts[2].to_owned() == "mark-paid" {
        return Some(rest)
      }
    }
    if parts.length() == 3 &&
      valid_identifier(parts[1].to_owned()) &&
      parts[0].to_owned() == "changes" &&
      (
        parts[2].to_owned() == "submit-approval" ||
        parts[2].to_owned() == "approve"
      ) {
      return Some(rest)
    }
  }
  if request_method is @http.Put && rest.has_prefix("demo/contracts/") {
    let parts = rest.split("/").to_array()
    if parts.length() == 3 &&
      valid_identifier(parts[1].to_owned()) &&
      parts[2].to_owned() == "state" {
      return Some(rest)
    }
  }
  if request_method is @http.Delete && rest == "demo/clear" {
    return Some(rest)
  }
  None
}

///|
fn cbs_mutation_boundary_gate(action : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(45001),
      "message": Json::string(
        "CBS 合同/R0/变更写入需要完整源表、审批策略和财务负责人确认；当前 native 服务不执行该写入。",
      ),
      "data": Json::object({
        "action": Json::string(action),
        "mutated": Json::boolean(false),
      }),
      "source_kind": Json::string("cbs_mutation_boundary_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "cbs_effect": Json::boolean(false),
      "budget_consumption": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
fn auth_lifecycle_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post && path == "/api/company/auth/login" {
    return Some("login")
  }
  if request_method is @http.Post && path == "/api/company/auth/logout" {
    return Some("logout")
  }
  if request_method is @http.Post && path == "/api/company/auth/change-password" {
    return Some("change_password")
  }
  if request_method is @http.Put && path == "/api/company/auth/profile" {
    return Some("profile")
  }
  None
}

///|
fn auth_lifecycle_gate(action : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(41001),
      "message": Json::string(
        "认证生命周期需要生产身份、密码哈希/会话存储和负责人确认；当前 native 服务不执行该写入。",
      ),
      "data": Json::object({
        "action": Json::string(action),
        "sessionIssued": Json::boolean(false),
        "mutated": Json::boolean(false),
      }),
      "source_kind": Json::string("auth_lifecycle_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}
