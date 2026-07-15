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

///|
fn attachment_upload_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/attachments/upload" ||
    path == "/api/company/source/attachments/upload"
  )
}

///|
fn attachment_upload_gate() -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43002),
      "message": Json::string(
        "附件上传需要对象存储与负责人确认；当前 native 服务不接受 multipart。",
      ),
      "data": Json::object({
        "multipartAccepted": Json::boolean(false),
        "binaryStorage": Json::string("not_imported"),
      }),
      "source_kind": Json::string("attachment_upload_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}

///|
fn attachment_delete_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = [
    "/api/company/attachments/", "/api/company/source/attachments/",
  ]
  for prefix in prefixes {
    if request_method is @http.Delete && path.has_prefix(prefix) {
      let guid = path[prefix.length():].to_owned()
      if valid_identifier(guid) &&
        guid != "upload" &&
        guid != "all" &&
        guid != "list" &&
        guid != "stats" {
        return Some(guid)
      }
    }
  }
  None
}

///|
fn attachment_delete_gate(attachment_guid : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43003),
      "message": Json::string(
        "附件删除需要对象存储所有权与负责人确认；当前 native 服务不执行删除。",
      ),
      "data": Json::object({
        "attGuid": Json::string(attachment_guid),
        "deleted": Json::boolean(false),
        "binaryStorage": Json::string("not_imported"),
      }),
      "source_kind": Json::string("attachment_delete_candidate"),
      "dry_run": Json::boolean(true),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}
