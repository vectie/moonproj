///|
/// Attachment OCR re-extraction candidate.
///
/// The source route invokes OCR and updates attachment metadata. Native
/// migration keeps the route source-compatible while making the provider and
/// metadata effects explicit: no binary is read, no OCR provider is called,
/// and no row is persisted.

///|
fn attachment_reextract_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = [
    "/api/company/attachments/re-extract/", "/api/company/source/attachments/re-extract/",
  ]
  for prefix in prefixes {
    if request_method is @http.Post && path.has_prefix(prefix) {
      let guid = path[prefix.length():].to_owned()
      if valid_identifier(guid) {
        return Some(guid)
      }
    }
  }
  None
}

///|
async fn attachment_reextract_response(
  attachment_guid : String,
) -> (Int, Json) raise CompanyServiceError {
  let rows = raw_source_rows("attachment", 500)
  let coverage = Json::object({
    "attachment": Json::number(rows.length().to_double()),
    "sys_user": Json::number(
      raw_source_rows("sys_user", 500).length().to_double(),
    ),
  })
  let selected = source_payload(rows, "att_guid", attachment_guid)
  match selected {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("附件不存在"),
          "source_kind": Json::string("attachment_re_extract_candidate"),
          "source_coverage": coverage,
          "persisted": Json::boolean(false),
          "provider_execution": Json::boolean(false),
          "authorizing": Json::boolean(false),
        }),
      )
    Some(payload) =>
      (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "attGuid": Json::string(attachment_guid),
            "fileName": Json::string(json_text(payload, "file_name", "")),
            "aiStatus": Json::string("pending"),
            "queued": Json::boolean(false),
            "wouldReExtract": Json::boolean(true),
            "providerExecution": Json::boolean(false),
            "persisted": Json::boolean(false),
            "authorizing": Json::boolean(false),
          }),
          "source_kind": Json::string("attachment_re_extract_candidate"),
          "dry_run": Json::boolean(true),
          "source_coverage": coverage,
          "persisted": Json::boolean(false),
          "provider_execution": Json::boolean(false),
          "authorizing": Json::boolean(false),
          "cash_effect": Json::boolean(false),
          "accounting_effect": Json::boolean(false),
          "tax_effect": Json::boolean(false),
        }),
      )
  }
}
