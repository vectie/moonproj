///|
/// Deterministic candidate for the ERP project-plan AI suggestion route.
///
/// The source asks an external LLM for seven milestone suggestions. The native
/// boundary keeps the response useful for migration while making provider
/// execution, persistence, and authority effects explicit false.

///|
fn plan_ai_suggest_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/plan/ai-suggest-plan" ||
    path == "/api/company/source/plan/ai-suggest-plan"
  )
}

///|
fn plan_ai_suggest_response(body : Json) -> Json raise CompanyServiceError {
  let project_type = json_text(body, "projType", "住宅")
  let scale = json_text(body, "scale", "中型")
  let region = json_text(body, "region", "")
  let begin_date = json_text(body, "beginDate", "2026-01-01")
  let names : Array[String] = [
    "立项", "获取", "规划设计", "开工", "主体封顶", "竣工验收",
    "交付",
  ]
  let roles : Array[String] = [
    "项目经理", "投资经理", "设计经理", "工程经理", "工程经理",
    "项目经理", "运营经理",
  ]
  let offsets : Array[Int] = [0, 30, 90, 180, 270, 330, 365]
  let nodes : Array[Json] = []
  for index in 0..<names.length() {
    nodes.push(
      Json::object({
        "name": Json::string(names[index]),
        "offsetDays": Json::number(offsets[index].to_double()),
        "ownerRole": Json::string(roles[index]),
        "planEndDate": Json::string(plan_shift_date(begin_date, offsets[index])),
      }),
    )
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "nodes": Json::array(nodes),
      "projectType": Json::string(project_type),
      "scale": Json::string(scale),
      "region": Json::string(region),
      "beginDate": Json::string(begin_date),
      "provider": Json::string("native-deterministic"),
      "model": Json::string("moonbit-source-boundary"),
      "raw": Json::string(""),
      "providerExecution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
    "source_kind": Json::string("plan_ai_suggestion_candidate"),
    "dry_run": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "persisted": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}
