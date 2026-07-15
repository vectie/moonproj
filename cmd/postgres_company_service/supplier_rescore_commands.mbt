///|
/// Supplier risk rescore candidate.
///
/// The source route mutates every supplier rating. The native migration
/// boundary reports the current supplier population and a deterministic
/// would-update count without changing imported or command-owned rows.

///|
fn supplier_rescore_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/srm/providers/rescore-all" ||
    path == "/api/company/source/srm/providers/rescore-all"
  )
}

///|
async fn supplier_rescore_response() -> Json raise CompanyServiceError {
  let list = supplier_source_list_response()
  let total = match json_field(list, "data") {
    Some(Array(items)) => items.length()
    _ => 0
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "total": Json::number(total.to_double()),
      "updated": Json::number(0),
      "wouldUpdate": Json::number(total.to_double()),
      "dryRun": Json::boolean(true),
      "providerExecution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
    "source_kind": Json::string("supplier_rescore_candidate"),
    "dry_run": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "persisted": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}
