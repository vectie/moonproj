///|
/// Explicit gate for AI Hub mutations that would create drafts, execute
/// queries, or promote AI output into business/workflow state.

///|
fn ai_hub_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let prefix = "/api/company/ai-hub/"
    let source_prefix = "/api/company/source/ai-hub/"
    let names : Array[String] = [
      "intake", "confirm", "discard", "query", "rule-from-nl", "approval-draft",
      "global-ask", "query-session", "command",
    ]
    for name in names {
      if path == prefix + name || path == source_prefix + name {
        return Some(name)
      }
    }
  }
  None
}

///|
fn ai_hub_command_gate(command : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(47001),
      "message": Json::string(
        "AI Hub 命令需要 AI 负责人确认；当前 native 服务仅开放观察与解释候选。",
      ),
      "data": Json::object({
        "command": Json::string(command),
        "provider": Json::string("not_connected"),
        "queryExecution": Json::boolean(false),
      }),
      "source_kind": Json::string("ai_hub_command_candidate"),
      "dry_run": Json::boolean(true),
      "provider_execution": Json::boolean(false),
      "query_execution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}
