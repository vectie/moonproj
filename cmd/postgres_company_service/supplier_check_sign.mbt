///|
/// Source-compatible supplier signature-check preview.
///
/// Imported suppliers remain behind the procurement-owner gate.  A
/// command-owned supplier receives only a deterministic local risk preview;
/// this endpoint never authorizes a signature, persists risk state, or calls a
/// provider.

///|
fn supplier_check_sign_coverage(
  providers : Array[SourceRow],
  categories : Array[SourceRow],
  links : Array[SourceRow],
  contracts : Array[SourceRow],
  units : Array[SourceRow],
) -> Json {
  Json::object({
    "cb_contract": Json::number(contracts.length().to_double()),
    "mu_business_unit": Json::number(units.length().to_double()),
    "srm_category": Json::number(categories.length().to_double()),
    "srm_provider": Json::number(providers.length().to_double()),
    "srm_provider_bu": Json::number(links.length().to_double()),
  })
}

///|
fn supplier_check_sign_risk(
  state : String,
  evaluation : String,
) -> (Int, String, Array[String], Bool, Bool, String) {
  let score = if state == "voided" ||
    state == "blacklisted" ||
    evaluation == "unqualified" ||
    evaluation == "不合格" {
    0
  } else if state == "active" &&
    (evaluation == "strategic" || evaluation == "战略") {
    95
  } else if state == "active" &&
    (evaluation == "qualified" || evaluation == "合格") {
    85
  } else if state == "pending_review" {
    60
  } else if state == "suspended" {
    35
  } else {
    50
  }
  let rating = if score >= 95 {
    "A"
  } else if score >= 85 {
    "B"
  } else if score == 0 {
    "E"
  } else if score == 35 {
    "D"
  } else {
    "C"
  }
  let tags : Array[String] = []
  if state == "pending_review" {
    tags.push("pending_review")
  }
  if state == "suspended" {
    tags.push("suspended")
  }
  if state == "blacklisted" {
    tags.push("blacklist")
  }
  if evaluation == "unqualified" || evaluation == "不合格" {
    tags.push("unqualified")
  }
  let allow = state != "blacklisted" && rating != "E"
  let require_extra_approve = rating == "D"
  let reason = if state == "blacklisted" {
    "黑名单供应商,禁止签约"
  } else if rating == "E" {
    "风险评级 E,禁止签约"
  } else if rating == "D" {
    "风险评级 D,需要风控加签"
  } else {
    ""
  }
  (score, rating, tags, allow, require_extra_approve, reason)
}

///|
async fn supplier_check_sign_response(
  provider_guid : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(provider_guid) {
    raise fail("invalid provider_guid")
  }
  let providers = raw_source_rows("srm_provider", 500)
  let categories = raw_source_rows("srm_category", 500)
  let links = raw_source_rows("srm_provider_bu", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage = supplier_check_sign_coverage(
    providers, categories, links, contracts, units,
  )
  let metadata = supplier_source_metadata(coverage)
  let imported = source_payload(providers, "provider_guid", provider_guid)
  if imported is Some(_) {
    match metadata {
      Object(fields) => {
        fields.set("success", Json::boolean(false))
        fields.set("code", Json::number(43003))
        fields.set(
          "message",
          Json::string("供应商签约校验仍需采购负责人审批"),
        )
        fields.set(
          "data",
          Json::object({
            "providerGuid": Json::string(provider_guid),
            "allow": Json::null(),
            "requireExtraApprove": Json::null(),
            "reason": Json::string(
              "采购负责人审批后才能执行签约校验",
            ),
            "risk": Json::null(),
          }),
        )
        fields.set("decision", Json::string("gated"))
        (409, Json::object(fields))
      }
      _ => raise fail("invalid supplier check-sign metadata")
    }
  } else {
    let command_items = supplier_command_items()
    let mut selected : Json? = None
    for item in command_items {
      if json_text(item, "providerGuid", "") == provider_guid {
        selected = Some(item)
        break
      }
    }
    match selected {
      Some(item) if json_text(item, "auditState", "draft") != "voided" => {
        let state = json_text(item, "auditState", "draft")
        let evaluation = json_text(item, "evalResult", "未定级")
        let (score, rating, tags, allow, require_extra_approve, reason) = supplier_check_sign_risk(
          state, evaluation,
        )
        match metadata {
          Object(fields) => {
            fields.set("success", Json::boolean(true))
            fields.set("code", Json::number(0))
            fields.set(
              "data",
              Json::object({
                "providerGuid": Json::string(provider_guid),
                "allow": Json::boolean(allow),
                "requireExtraApprove": Json::boolean(require_extra_approve),
                "reason": Json::string(reason),
                "risk": Json::object({
                  "score": Json::number(score.to_double()),
                  "rating": Json::string(rating),
                  "tags": Json::array(tags.map(fn(tag) { Json::string(tag) })),
                  "contractCount": Json::number(0),
                  "contractTotal": Json::number(0),
                  "overdueCount": Json::number(0),
                  "overdueAmount": Json::number(0),
                }),
                "sourceKind": Json::string("command"),
              }),
            )
            fields.set("decision", Json::string("derived_command_preview"))
            fields.set("derived_replacement", Json::boolean(true))
            fields.set(
              "procurement_owner_approval_required",
              Json::boolean(true),
            )
            fields.set("source_kind", Json::string("command"))
            fields.set("command_projection", Json::boolean(true))
            (200, Json::object(fields))
          }
          _ => raise fail("invalid supplier check-sign metadata")
        }
      }
      _ =>
        match metadata {
          Object(fields) => {
            fields.set("success", Json::boolean(false))
            fields.set("code", Json::number(43001))
            fields.set("message", Json::string("供应商不存在"))
            fields.set("data", Json::null())
            (404, Json::object(fields))
          }
          _ => raise fail("invalid supplier check-sign metadata")
        }
    }
  }
}
