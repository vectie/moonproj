///|
/// Source-compatible AI explanation candidates.
///
/// ERP calls an LLM for these two routes. The native boundary keeps the POST
/// contract useful during migration by producing a deterministic explanation
/// from the supplied/read-model values while making provider execution and
/// persistence explicit false.

///|
fn ai_explain_envelope(data : Json) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("analytics_candidate"),
    "dry_run": Json::boolean(true),
    "persisted": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn ai_explain_array(body : Json, key : String) -> Array[Json] {
  match json_field(body, key) {
    Some(Array(values)) => values
    _ => []
  }
}

///|
fn cashflow_ai_explain(body : Json) -> Json {
  let series = ai_explain_array(body, "series")
  let gap_weeks = ai_explain_array(body, "gapWeeks")
  let mut total_gap = 0.0
  for item in gap_weeks {
    total_gap += json_number(item, "gap", 0.0)
  }
  let explain = if series.is_empty() {
    "暂无现金流序列，无法形成趋势结论；请先加载预测读模型；外部模型调用保持关闭。"
  } else if gap_weeks.is_empty() {
    "当前预测序列未发现已标记的周缺口；继续关注累计净额和未来回款；外部模型调用保持关闭。"
  } else {
    "发现 " +
    gap_weeks.length().to_string() +
    " 个现金流缺口（合计约 " +
    round_places(total_gap, 2).to_string() +
    "）；优先核对对应付款计划与回款；外部模型调用保持关闭。"
  }
  ai_explain_envelope(
    Json::object({
      "explain": Json::string(explain),
      "provider": Json::string("native-deterministic"),
      "model": Json::string("moonbit-source-boundary"),
      "seriesCount": Json::number(series.length().to_double()),
      "gapWeekCount": Json::number(gap_weeks.length().to_double()),
      "totalGap": Json::number(round_places(total_gap, 2)),
      "providerExecution": Json::boolean(false),
      "persisted": Json::boolean(false),
    }),
  )
}

///|
async fn investment_ai_explain(
  project_id : String,
) -> Json raise CompanyServiceError {
  let version = investment_current_version_payload(project_id)
  match version {
    None =>
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(40010),
        "message": Json::string("尚无激活版本"),
        "source_kind": Json::string("analytics_candidate"),
        "dry_run": Json::boolean(true),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
        "provider_execution": Json::boolean(false),
      })
    Some(_) => {
      let summary = investment_profit_summary_response(project_id)
      let summary_data = json_field(summary, "data").unwrap_or(Json::object({}))
      let revenue = json_number(summary_data, "revenue", 0.0)
      let cost = json_number(summary_data, "cost", 0.0)
      let net = json_number(summary_data, "netProfit", 0.0)
      let irr = json_number(summary_data, "irr", 0.0)
      let explain = if revenue <= 0.0 {
        "当前版本缺少有效收入指标，暂不能判断整体可行性；先补齐测算数据；外部模型调用保持关闭。"
      } else if net < 0.0 {
        "当前版本净利润为负，主要风险是成本与收入倒挂；优先复核成本及税费变量；外部模型调用保持关闭。"
      } else {
        "当前版本具备正向净利润，整体可行性需结合 IRR 与成本敏感性复核；优先关注成本和税费；外部模型调用保持关闭。"
      }
      ai_explain_envelope(
        Json::object({
          "explain": Json::string(explain),
          "provider": Json::string("native-deterministic"),
          "model": Json::string("moonbit-source-boundary"),
          "versionGuid": json_field(summary_data, "versionGuid").unwrap_or(
            Json::string(""),
          ),
          "revenue": Json::number(revenue),
          "cost": Json::number(cost),
          "netProfit": Json::number(net),
          "irr": Json::number(irr),
          "providerExecution": Json::boolean(false),
          "persisted": Json::boolean(false),
        }),
      )
    }
  }
}

///|
async fn investment_ai_explain_status(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  (200, investment_ai_explain(project_id))
}

///|
fn ai_explain_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post &&
    (
      path == "/api/company/cashflow/ai-explain" ||
      path == "/api/company/source/cashflow/ai-explain"
    ) {
    return Some(("cashflow", None))
  }
  let prefixes = [
    "/api/company/investment/projects/", "/api/company/source/investment/projects/",
  ]
  for prefix in prefixes {
    if request_method is @http.Post &&
      path.has_prefix(prefix) &&
      path.has_suffix("/ai-explain") {
      let project_id = path[prefix.length():path.length() -
      "/ai-explain".length()].to_owned()
      if valid_identifier(project_id) {
        return Some(("investment", Some(project_id)))
      }
    }
  }
  None
}
