///|
fn dispatch_source_context_form(
  emit : @rabbita.Emit[Msg],
  model : Model,
  frozen : Bool,
) -> @html.Html {
  let draft = dispatch_active_draft(model)
  details(class="journey-details") <| [
    summary("来源与问题（可选）"),
    p(
      "保留这项工作来自哪里、要解决什么问题。不要填写密码或访问令牌。",
    ),
    dispatch_task_input(
      "dispatch-source-reference",
      "来源引用",
      draft.map(value => value.source_reference.unwrap_or("")).unwrap_or(""),
      "原始请求、文档或访谈记录的位置",
      emit.map(value => DraftAction(Input("source_reference", value))),
      read_only=frozen,
    ),
    dispatch_task_input(
      "dispatch-observed-problem",
      "观察到的问题",
      draft.map(value => value.observed_problem.unwrap_or("")).unwrap_or(""),
      "为什么需要这项工作？",
      emit.map(value => DraftAction(Input("observed_problem", value))),
      read_only=frozen,
    ),
  ]
}

///|
fn dispatch_source_context_view(source : Json) -> @html.Html {
  let reference = dispatch_json_text(source, "reference")
  let problem = dispatch_json_text(source, "problem")
  if reference.is_empty() && problem.is_empty() {
    @html.nothing
  } else {
    div <| [
      if reference.is_empty() {
        @html.nothing
      } else {
        p <| [
          span("来源 · "),
          dispatch_result_reference(reference),
        ]
      },
      if problem.is_empty() {
        @html.nothing
      } else {
        p("问题 · " + problem)
      },
    ]
  }
}

///|
fn dispatch_receipt_action_label(action : String) -> String {
  match action {
    "create" => "创建正式任务"
    "update" => "更新任务"
    "offer_reply" => "记录客户回复"
    "report" => "提交结果报告"
    "internal_acceptance" => "内部验收"
    "continuation_observe" => "关联后续执行"
    "delete" => "删除任务"
    _ => action
  }
}

///|
fn dispatch_commitment_receipts_view(history : Json) -> @html.Html {
  if !(history is Object(_)) {
    return @html.nothing
  }
  let brief = dispatch_json_field(history, "original_brief")
  let receipts = dispatch_continuation_array(history, "receipts")
  div <| [
    strong("持久化任务记录"),
    if brief is Null {
      small("原始任务请求尚未读回")
    } else {
      details <| [
        summary("创建时的任务与验收标准"),
        p(dispatch_json_text(brief, "task_name")),
        p(dispatch_json_text(brief, "remarks")),
        dispatch_source_context_view(
          dispatch_json_field(brief, "source_context"),
        ),
      ]
    },
    if receipts.is_empty() {
      small("尚未读回命令收据")
    } else {
      div <| receipts.map(receipt => {
        div <| [
          strong(
            dispatch_receipt_action_label(dispatch_json_text(receipt, "action")),
          ),
          small("操作人 · " + dispatch_json_text(receipt, "actor_id")),
          small("记录时间 · " + dispatch_json_text(receipt, "recorded_at")),
          small("事件 · " + dispatch_json_text(receipt, "event_id")),
          small("审计 · " + dispatch_json_text(receipt, "audit_id")),
          if dispatch_json_text(receipt, "audit_state") == "available" {
            @html.nothing
          } else {
            small(
              "审计记录待核对 · " +
              dispatch_json_text(receipt, "audit_state"),
            )
          },
          if dispatch_json_text(receipt, "report_id").is_empty() {
            @html.nothing
          } else {
            small("对应报告 · " + dispatch_json_text(receipt, "report_id"))
          },
        ]
      })
    },
    small(
      "内部验收、客户接受和实际收款是不同事实；此处仅展示任务命令记录。",
    ),
  ]
}
