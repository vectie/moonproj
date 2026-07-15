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
