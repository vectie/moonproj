///|
fn dispatch_offer_field(
  emit : @rabbita.Emit[DispatchOfferMsg],
  value : Json,
  field : String,
  title : String,
  hint : String,
  local_draft : Bool,
  frozen : Bool,
) -> @html.Html {
  let id = (if local_draft { "local-offer-" } else { "task-offer-" }) + field
  div(class="field", style=["margin:12px 0"]) <| [
    label(for_=id, title),
    @html.textarea(
      id~,
      value=dispatch_offer_value_text(value, field),
      rows=2,
      placeholder=hint,
      read_only=frozen,
      on_input=emit.map(text => {
        if local_draft {
          EditLocal(field, text)
        } else {
          Edit(field, text)
        }
      }),
      style=dispatch_outcome_control_style(),
      "",
    ),
  ]
}

///|
fn dispatch_offer_editor(
  emit : @rabbita.Emit[Msg],
  value : Json,
  local_draft : Bool,
  frozen : Bool,
) -> @html.Html {
  let send = emit.map(action => OfferAction(action))
  let unresolved = @task_evidence.offer_draft_unresolved(value) catch {
    @task_evidence.InvalidOfferDraft(error) => [error]
  }
  let fields = [
    ("title", "方案标题", "用一句话说明这份方案"),
    ("buyer", "潜在买方", "未知可留空，不代表已确认需求"),
    (
      "buyer_reference", "买方线索来源", "真实联系记录或公开来源，可留空",
    ),
    ("problem", "要解决的问题", "记录已知问题；未知可留空"),
    (
      "problem_observed_on", "问题观察日期", "YYYY-MM-DD；未知可留空",
    ),
    ("scope", "拟议范围", "这次准备做什么"),
    ("deliverables", "交付物", "每行一项"),
    (
      "acceptance_criteria", "方案验收条件", "每行一项；与任务内部验收标准独立",
    ),
    ("exclusions", "不包含的工作", "范围以外的内容"),
    ("price_amount", "拟议金额", "未知留空；明确为零时填写 0"),
    ("price_currency", "币种", "如 CNY、USD；未知留空"),
    (
      "price_basis", "价格依据", "一次性、按小时或其他真实依据",
    ),
    (
      "timing", "拟议时间安排", "交付节奏、期限或尚待确认的时间",
    ),
    (
      "dependencies", "依赖与前提", "客户需提供什么，还有哪些条件",
    ),
    (
      "proof_sought", "下一步需要验证的证据", "用什么真实结果判断需求是否成立",
    ),
  ]
  div <| [
    p(
      class="boundary-note",
      "需求尚未证实。这是可继续填写的方案草稿；保存或导出不会发送给客户、签订合同或产生付款。未知金额请留空。",
    ),
    div(class="form-grid") <| fields.map(item => {
      let (field, title, hint) = item
      dispatch_offer_field(send, value, field, title, hint, local_draft, frozen)
    }),
    div(class="form-actions") <| [
      button(
        type_="button",
        class="button button-secondary",
        disabled=frozen,
        on_click=send(
          if local_draft {
            EditLocal(
              "state",
              if dispatch_json_text(value, "state") == "closed" {
                "draft"
              } else {
                "closed"
              },
            )
          } else {
            Edit(
              "state",
              if dispatch_json_text(value, "state") == "closed" {
                "draft"
              } else {
                "closed"
              },
            )
          },
        ),
        if dispatch_json_text(value, "state") == "closed" {
          "重新打开方案草稿"
        } else {
          "关闭此方案草稿"
        },
      ),
    ],
    if dispatch_json_text(value, "state") == "closed" {
      dispatch_offer_field(
        send, value, "closure_reason", "关闭原因（必填）", "为什么不继续这份方案？",
        local_draft, frozen,
      )
    } else {
      @html.nothing
    },
    p(
      "方案状态 · " +
      (if dispatch_json_text(value, "state") == "closed" {
        "已关闭"
      } else {
        "草稿"
      }),
    ),
    match unresolved {
      [] => small("草稿信息已填写；需求仍需真实证据验证。")
      fields => small("待补充或核对 · " + fields.join("、"))
    },
    secondary_button(
      emit,
      OfferAction(Export(local_draft)),
      "导出 Markdown 草稿",
    ),
  ]
}

///|
fn dispatch_offer_local_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  frozen : Bool,
) -> @html.Html {
  guard dispatch_active_draft(model) is Some(draft) else {
    return @html.nothing
  }
  details(class="journey-details", open=draft.offer_draft is Some(_)) <| [
    summary("报价方案草稿（可选）"),
    match draft.offer_draft {
      Some(value) => dispatch_offer_editor(emit, value, true, frozen)
      None =>
        div <| [
          p(
            "可以先写方案，再明确创建普通待执行任务。打开此处不会创建或执行任务。",
          ),
          button(
            type_="button",
            class="button button-secondary",
            disabled=frozen,
            on_click=emit(OfferAction(BeginLocal)),
            "开始写报价方案草稿",
          ),
        ]
    },
  ]
}

///|
fn dispatch_offer_canonical_view(model : Model) -> @html.Html {
  let value = dispatch_json_field(model.dispatch_offer_task, "offer_draft")
  if value is Null {
    return p("此正式任务尚未保存报价方案。")
  }
  let saved_revision = dispatch_offer_canonical_revision(model)
  let markdown = @task_evidence.offer_draft_markdown(
    value,
    task_id=model.dispatch_task_id,
    project_id=model.dispatch_task_project_id,
    revision=if saved_revision > 0 {
      saved_revision
    } else {
      dispatch_offer_revision(model.dispatch_offer_task)
    },
  ) catch {
    @task_evidence.InvalidOfferDraft(error) => error
  }
  details(class="journey-details") <| [
    summary(
      if saved_revision > 0 {
        "当前正式方案 · 方案版本 " +
        saved_revision.to_string() +
        " · 当前任务版本 " +
        dispatch_offer_revision(model.dispatch_offer_task).to_string()
      } else {
        "当前正式方案 · 版本 " +
        dispatch_offer_revision(model.dispatch_offer_task).to_string() +
        "（任务快照；方案保存版本待核对）"
      },
    ),
    p(
      if saved_revision > 0 {
        "回复属于其明确引用的方案版本；后续任务记录不会自动生成新方案。"
      } else {
        "下方 Task revision 仅表示本次任务快照，未确认这是方案保存时的版本。"
      },
    ),
    if saved_revision > 0 {
      p(
        if dispatch_reply_history(model).any(entry => {
            dispatch_reply_number(
              dispatch_json_field(entry, "offer_reply"),
              "offer_revision",
            ) ==
            saved_revision
          }) {
          "当前方案版本已有回复记录，请在客户回复历史中核对。"
        } else {
          "当前方案版本尚无已保存回复。历史回复仍按原方案版本保留。"
        },
      )
    } else {
      @html.nothing
    },
    @html.pre(
      style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
      markdown,
    ),
  ]
}

///|
fn dispatch_offer_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let eligible = dispatch_offer_eligible(model)
  section(class="journey-section") <| [
    h3("报价方案草稿"),
    dispatch_offer_canonical_view(model),
    dispatch_reply_view(emit, model),
    if !(dispatch_json_field(model.dispatch_offer_task, "offer_draft") is Null) {
      secondary_button(
        emit,
        OfferAction(ExportCanonical),
        "导出当前正式方案 Markdown",
      )
    } else {
      @html.nothing
    },
    match dispatch_offer_find(model, model.dispatch_task_id) {
      None =>
        if eligible {
          secondary_button(
            emit,
            OfferAction(Begin),
            "起草或编辑报价方案",
          )
        } else {
          @html.nothing
        }
      Some(draft) =>
        div <| [
          p(
            attrs=@html.Attrs::build().role("status").aria_live("polite"),
            draft.note,
          ),
          small(
            "本地编辑基于任务版本 " +
            draft.base_revision.to_string() +
            " · " +
            model.dispatch_offer_storage,
          ),
          dispatch_offer_editor(
            emit,
            draft.value,
            false,
            !eligible || !dispatch_offer_editable(draft),
          ),
          if eligible && dispatch_offer_editable(draft) {
            primary_button(
              emit,
              OfferAction(Save),
              "保存方案到正式任务",
            )
          } else {
            @html.nothing
          },
          if !draft.operation_key.is_empty() &&
            (draft.state == "uncertain" || draft.state == "conflict") {
            secondary_button(
              emit,
              OfferAction(Recover),
              "恢复此次保存记录",
            )
          } else {
            @html.nothing
          },
          if eligible && draft.state == "uncertain" {
            secondary_button(
              emit,
              OfferAction(Retry),
              "重试同一保存请求",
            )
          } else {
            @html.nothing
          },
          if eligible && ["conflict", "historical"].contains(draft.state) {
            secondary_button(
              emit,
              OfferAction(Rebase),
              "已核对正式版本，保留本地内容继续编辑",
            )
          } else {
            @html.nothing
          },
        ]
    },
    if !eligible && model.dispatch_task_pending_action.is_empty() {
      div <| [
        p(
          "此处仅查看方案。新方案请准备独立的普通规划任务。",
        ),
        secondary_button(
          emit,
          OfferAction(NewPlanning),
          "另建方案规划草稿",
        ),
      ]
    } else {
      @html.nothing
    },
    details(class="journey-details") <| [
      summary("方案保存历史与审计状态"),
      div <| dispatch_continuation_array(
        model.dispatch_task_commitment,
        "offer_history",
      ).map(entry => {
        let markdown = @task_evidence.offer_draft_markdown(
          dispatch_json_field(entry, "offer_draft"),
          task_id=model.dispatch_task_id,
          project_id=model.dispatch_task_project_id,
          revision=dispatch_offer_revision(entry),
        ) catch {
          @task_evidence.InvalidOfferDraft(error) =>
            "历史内容无法核对：" + error
        }
        details(class="journey-details") <| [
          summary(
            "历史方案 · 版本 " +
            dispatch_offer_revision(entry).to_string() +
            " · 审计 " +
            dispatch_json_text(entry, "audit_state") +
            " · " +
            dispatch_json_text(entry, "recorded_at"),
          ),
          @html.pre(
            style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
            markdown,
          ),
          p(
            if dispatch_reply_history(model).any(reply => {
                dispatch_reply_number(
                  dispatch_json_field(reply, "offer_reply"),
                  "offer_revision",
                ) ==
                dispatch_offer_revision(entry)
              }) {
              "此方案版本已有回复记录，请在客户回复历史中核对。"
            } else {
              "此方案版本尚无已保存回复；其他方案版本的回复不会自动沿用。"
            },
          ),
        ]
      }),
    ],
  ]
}
