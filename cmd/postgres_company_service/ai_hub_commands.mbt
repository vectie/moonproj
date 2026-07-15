///|
/// AI Hub explanation candidate.
///
/// The source route calls an LLM over a caller-supplied table. Native MoonBit
/// returns a deterministic summary with the same response envelope while
/// keeping provider execution and prompt persistence disabled.

///|
fn ai_hub_explain_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> Bool {
  request_method is @http.Post &&
  (
    path == "/api/company/ai-hub/explain" ||
    path == "/api/company/source/ai-hub/explain"
  )
}

///|
fn ai_hub_explain_response(body : Json) -> Json {
  let title = json_text(body, "title", "数据")
  let focus = json_text(body, "focus", "")
  let table = ai_explain_array(body, "table")
  let explain = if table.is_empty() {
    "当前数据表为空，暂无法判断趋势；请先加载读模型；外部模型调用保持关闭。"
  } else if focus.is_empty() {
    title +
    " 共收到 " +
    table.length().to_string() +
    " 行数据；建议先核对异常值与时间范围，再结合业务口径复核；外部模型调用保持关闭。"
  } else {
    title +
    " 共收到 " +
    table.length().to_string() +
    " 行数据；当前重点关注：" +
    focus +
    "；建议结合原始记录复核；外部模型调用保持关闭。"
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "explain": Json::string(explain),
      "provider": Json::string("native-deterministic"),
      "model": Json::string("moonbit-source-boundary"),
      "title": Json::string(title),
      "rowCount": Json::number(table.length().to_double()),
      "providerExecution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
    "source_kind": Json::string("ai_hub_explain_candidate"),
    "dry_run": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "persisted": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}
