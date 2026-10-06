///|
fn dispatch_reply_field(
  emit : @rabbita.Emit[DispatchReplyMsg],
  value : Json,
  field : String,
  title : String,
  hint : String,
  frozen : Bool,
) -> @html.Html {
  let id = "offer-reply-" + field
  div(class="field", style=["margin:12px 0"]) <| [
    label(for_=id, title),
    @html.textarea(
      id~,
      value=dispatch_json_text(value, field),
      rows=if field == "summary" { 5 } else { 2 },
      placeholder=hint,
      read_only=frozen,
      on_input=emit.map(text => Edit(field, text)),
      style=dispatch_outcome_control_style(),
      "",
    ),
  ]
}

///|
fn dispatch_reply_choice(
  emit : @rabbita.Emit[DispatchReplyMsg],
  value : Json,
  field : String,
  title : String,
  choices : Array[(String, String)],
  frozen : Bool,
) -> @html.Html {
  let id = "offer-reply-" + field
  div(class="field", style=["margin:12px 0"]) <| [
    label(for_=id, title),
    @html.select(
      id~,
      disabled=frozen,
      style=dispatch_outcome_control_style(),
      on_change=emit.map(text => Edit(field, text)),
    ) <| choices.map(pair => {
      let (key, title) = pair
      @html.option(
        value=key,
        selected=dispatch_json_text(value, field) == key,
        title,
      )
    }),
  ]
}

///|
fn dispatch_reply_editor(
  emit : @rabbita.Emit[Msg],
  model : Model,
  draft : DispatchReplyDraft,
) -> @html.Html {
  let send = emit.map(action => ReplyAction(action))
  let frozen = !dispatch_reply_eligible(model) || draft.state != "editing"
  let correction = !dispatch_json_text(draft.value, "supersedes_reply_id").is_empty()
  div <| [
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), draft.note),
    small(
      "任务保存基准版本 " +
      draft.base_revision.to_string() +
      " · " +
      model.dispatch_reply_storage,
    ),
    if draft.state != "saved" {
      div <| [
        label(
          for_="offer-reply-revision",
          "客户回复对应的已保存方案（必选）",
        ),
        @html.select(
          id="offer-reply-revision",
          disabled=frozen || correction,
          style=dispatch_outcome_control_style(),
          on_change=send.map(text => Edit("offer_revision", text)),
        ) <| [
          @html.option(
            value="",
            selected=dispatch_reply_number(draft.value, "offer_revision") == 0,
            "请选择具体方案版本",
          ),
          ..dispatch_reply_offers(model).map(entry => {
            let revision = dispatch_offer_revision(entry)
            @html.option(
              value=revision.to_string(),
              selected=dispatch_reply_number(draft.value, "offer_revision") ==
                revision,
              "方案版本 " +
              revision.to_string() +
              " · " +
              dispatch_json_text(
                dispatch_json_field(entry, "offer_draft"),
                "title",
              ),
            )
          }),
        ],
        p(
          "这与保存时检查的当前任务版本分别记录。请选择客户实际回应的那一版方案。",
        ),
        dispatch_reply_field(
          send,
          draft.value,
          "respondent",
          "回复者（可留空）",
          "不知道回复者时留空；不会自动当作当前记录者",
          frozen,
        ),
        dispatch_reply_field(
          send,
          draft.value,
          "received_at",
          "收到回复的时间（UTC，可留空）",
          "YYYY-MM-DDTHH:mm:ssZ；未知请留空",
          frozen,
        ),
        dispatch_reply_field(
          send,
          draft.value,
          "summary",
          "已经收到的回复摘要（必填）",
          "保留客户表达的要点、限制和不确定之处，可分多行",
          frozen,
        ),
        dispatch_reply_choice(
          send,
          draft.value,
          "kind",
          "回复类型（必选）",
          [
            ("", "请选择"),
            ("interested", "有兴趣"),
            ("changes_requested", "要求修改"),
            ("declined", "拒绝"),
            ("other", "其他"),
          ],
          frozen,
        ),
        dispatch_reply_choice(
          send,
          draft.value,
          "evidence_kind",
          "记录依据（请明确选择）",
          [
            ("", "请选择真实依据"),
            ("reference", "已有来源记录"),
            ("human_observation", "我的人工观察，没有来源记录"),
          ],
          frozen,
        ),
        if dispatch_json_text(draft.value, "evidence_kind") == "reference" {
          dispatch_reply_field(
            send,
            draft.value,
            "source_reference",
            "来源引用（必填）",
            "真实邮件、消息、记录标识或其他可核对引用",
            frozen,
          )
        } else if dispatch_json_text(draft.value, "evidence_kind") ==
          "human_observation" {
          p(
            "将明确标记为人工观察，不会自动生成或声称存在来源记录。",
          )
        } else {
          @html.nothing
        },
        if correction {
          div <| [
            p(
              "正在更正回复 " +
              dispatch_json_text(draft.value, "supersedes_reply_id") +
              "；原记录不会被覆盖或删除。",
            ),
            dispatch_reply_field(
              send,
              draft.value,
              "correction_reason",
              "更正原因（必填）",
              "说明原记录哪里不准确，以及这次为什么更正",
              frozen,
            ),
          ]
        } else {
          @html.nothing
        },
        if !frozen {
          primary_button(
            emit,
            ReplyAction(Save),
            if correction {
              "保存更正收据"
            } else {
              "保存回复收据"
            },
          )
        } else {
          @html.nothing
        },
        if !draft.operation_key.is_empty() &&
          ["uncertain", "conflict"].contains(draft.state) {
          secondary_button(
            emit,
            ReplyAction(Recover),
            "恢复此次回复保存记录",
          )
        } else {
          @html.nothing
        },
        if dispatch_reply_eligible(model) && draft.state == "uncertain" {
          secondary_button(emit, ReplyAction(Retry), "重试同一回复请求")
        } else {
          @html.nothing
        },
        if dispatch_reply_eligible(model) && draft.state == "conflict" {
          secondary_button(
            emit,
            ReplyAction(Rebase),
            "已核对历史，以当前任务版本继续",
          )
        } else {
          @html.nothing
        },
      ]
    } else {
      @html.nothing
    },
    if ["editing", "saved", "conflict"].contains(draft.state) {
      secondary_button(
        emit,
        ReplyAction(Discard),
        "清除此标签页的回复草稿",
      )
    } else {
      @html.nothing
    },
  ]
}

///|
fn dispatch_reply_known(value : Json, field : String) -> String {
  let text = dispatch_json_text(value, field)
  if text.is_empty() {
    "未知"
  } else {
    text
  }
}

///|
fn dispatch_reply_history_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let history = dispatch_reply_history(model)
  let can_begin = dispatch_reply_find(model) is None ||
    (dispatch_reply_find(model) is Some(draft) && draft.state == "saved")
  details(class="journey-details", open=true) <| [
    summary("客户回复历史与更正记录"),
    if history.is_empty() {
      p("尚无已保存的客户回复。")
    } else {
      @html.nothing
    },
    div <| history.map(entry => {
      let value = dispatch_json_field(entry, "offer_reply")
      let id = dispatch_json_text(entry, "reply_id")
      let superseded = dispatch_reply_superseded(history, id)
      details(class="journey-details") <| [
        summary(
          "方案版本 " +
          dispatch_reply_number(value, "offer_revision").to_string() +
          " · " +
          dispatch_reply_kind_label(dispatch_json_text(value, "kind")) +
          (if superseded { " · 已有更正，原记录保留" } else { "" }),
        ),
        p(
          "回复者 · " +
          dispatch_reply_known(value, "respondent") +
          " ｜ 收到时间 · " +
          dispatch_reply_known(value, "received_at"),
        ),
        @html.pre(
          style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
          dispatch_json_text(value, "summary"),
        ),
        p(
          "依据 · " +
          (if dispatch_json_text(value, "evidence_kind") == "human_observation" {
            "人工观察（没有来源引用）"
          } else {
            "来源记录：" + dispatch_reply_known(value, "source_reference")
          }),
        ),
        p(
          "记录者 · " +
          dispatch_reply_known(entry, "recorded_by") +
          " ｜ 记录时间 · " +
          dispatch_reply_known(entry, "recorded_at"),
        ),
        p(
          "回复收据 " +
          id +
          " · 任务记录版本 " +
          dispatch_reply_number(entry, "record_revision").to_string() +
          " · 审计 " +
          dispatch_reply_known(entry, "audit_state"),
        ),
        if !dispatch_json_text(value, "supersedes_reply_id").is_empty() {
          p(
            "更正原回复 " +
            dispatch_json_text(value, "supersedes_reply_id") +
            " · 原因：" +
            dispatch_json_text(value, "correction_reason"),
          )
        } else {
          @html.nothing
        },
        if can_begin &&
          dispatch_reply_eligible(model) &&
          !superseded &&
          !id.is_empty() &&
          dispatch_json_text(entry, "audit_state") == "available" {
          secondary_button(emit, ReplyAction(Correct(id)), "追加更正记录")
        } else {
          @html.nothing
        },
      ]
    }),
  ]
}

///|
fn dispatch_reply_kind_label(kind : String) -> String {
  match kind {
    "interested" => "有兴趣"
    "changes_requested" => "要求修改"
    "declined" => "拒绝"
    _ => "其他"
  }
}

///|
fn dispatch_reply_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let can_begin = dispatch_reply_find(model) is None ||
    (dispatch_reply_find(model) is Some(draft) && draft.state == "saved")
  div(class="journey-section") <| [
    h3("客户对方案的回复"),
    p(
      "这里只记录已经收到的回复，不会向客户发送消息。回复不代表需求已验证、客户验收、合同承诺或收入。",
    ),
    p(
      "未保存内容只保留在当前标签页，切换任务或刷新当前标签页可恢复；关闭标签页后不保证恢复。切换账号时会尝试清除本地草稿；正式保存并核对成功后也会尝试清除标签页中的回复副本，保存状态会提示浏览器失败。",
    ),
    if model.dispatch_reply_storage.contains("失败") ||
      model.dispatch_reply_storage.contains("未确认") ||
      model.dispatch_reply_storage.contains("无法读取") {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        model.dispatch_reply_storage,
      )
    } else {
      @html.nothing
    },
    if dispatch_reply_eligible(model) && can_begin {
      secondary_button(emit, ReplyAction(Begin), "记录客户回复")
    } else {
      @html.nothing
    },
    match dispatch_reply_find(model) {
      Some(draft) => dispatch_reply_editor(emit, model, draft)
      None => @html.nothing
    },
    dispatch_reply_history_view(emit, model),
    if dispatch_offer_eligible(model) {
      secondary_button(emit, OfferAction(Begin), "修改或关闭报价方案")
    } else {
      @html.nothing
    },
  ]
}
