///|
fn dispatch_outcome_textarea(
  id : String,
  title : String,
  value : String,
  placeholder : String,
  emit : @rabbita.Emit[String],
) -> @html.Html {
  div(class="field", style=["margin:12px 0"]) <| [
    label(for_=id, title),
    @html.textarea(
      id~,
      value~,
      rows=3,
      placeholder~,
      on_input=emit,
      style=dispatch_outcome_control_style(),
      "",
    ),
  ]
}

///|
fn dispatch_outcome_gap_view(
  emit : @rabbita.Emit[DispatchOutcomeMsg],
  source : Json,
  index : Int32,
  gap : DispatchOutcomeGap,
) -> @html.Html {
  let id = "outcome-gap-" + index.to_string()
  @html.fieldset(class="inline-form") <| [
    @html.legend(dispatch_outcome_gap_label(index)),
    p(
      match index {
        0 => "是否缺少完成工作所需的信息？"
        1 => "是否已有信息，却未能正确识别或理解？"
        _ => "是否已理解情况，却未能作出或执行必要决定？"
      },
    ),
    label(for_=id + "-choice", "你的明确判断"),
    @html.select(
      id=id + "-choice",
      style=dispatch_outcome_control_style(),
      on_change=emit.map(value => GapEdit(index, "choice", value)),
    ) <| [
      ("", "尚未选择"),
      ("absent", "未发现此类缺口"),
      ("present", "发现此类缺口"),
    ].map(pair => {
      let (value, text) = pair
      @html.option(value~, selected=gap.choice == value, text)
    }),
    dispatch_outcome_textarea(
      id + "-summary",
      "判断依据",
      gap.summary,
      "说明你观察到了什么，以及为什么作出这一判断",
      emit.map(value => GapEdit(index, "summary", value)),
    ),
    if gap.choice == "present" {
      div(class="field") <| [
        label(for_=id + "-severity", "严重程度（1 轻微，5 严重）"),
        @html.select(
          id=id + "-severity",
          style=dispatch_outcome_control_style(),
          on_change=emit.map(value => GapEdit(index, "severity", value)),
        ) <| ["", "1", "2", "3", "4", "5"].map(value => {
          @html.option(
            value~,
            selected=gap.severity == value,
            if value.is_empty() {
              "请选择严重程度"
            } else {
              value
            },
          )
        }),
      ]
    } else {
      @html.nothing
    },
    p("依据此次捕获的哪些记录？至少选择一项"),
    div <| dispatch_outcome_evidence(source).mapi((source_index, reference) => {
      let checkbox_id = id + "-evidence-" + source_index.to_string()
      label(
        for_=checkbox_id,
        style=[
          "display:flex", "gap:8px", "align-items:center", "min-height:40px",
        ],
      ) <| [
        input(
          id=checkbox_id,
          input_type=Checkbox,
          checked=gap.evidence_refs.contains(reference),
          on_change=emit.map(_ => Evidence(index, reference)),
        ),
        span(
          (if source_index == 0 {
            "任务记录 · "
          } else {
            "接受报告 · "
          }) +
          reference,
        ),
      ]
    }),
  ]
}

///|
fn dispatch_outcome_source_view(source : Json) -> @html.Html {
  let task = @json.parse(dispatch_json_text(source, "task_snapshot")) catch {
    _ => Json::null()
  }
  let report = @json.parse(dispatch_json_text(source, "report_snapshot")) catch {
    _ => Json::null()
  }
  details(class="journey-details") <| [
    summary("查看此次捕获的任务、报告与来源摘要"),
    p("任务 · " + dispatch_json_text(task, "title")),
    p(
      "报告 · " +
      dispatch_json_text(dispatch_json_field(report, "report"), "summary"),
    ),
    div <| ["task", "report"].map(kind => {
      let reference = dispatch_json_field(source, kind)
      div <| [
        small(kind + " · " + dispatch_json_text(reference, "record_id")),
        small("版本 · " + dispatch_json_text(reference, "record_version")),
        small("摘要 · " + dispatch_json_text(reference, "record_digest")),
      ]
    }),
    details <| [
      summary("查看完整捕获内容（只读）"),
      @html.pre(
        style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
        dispatch_json_text(source, "task_snapshot"),
      ),
      @html.pre(
        style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
        dispatch_json_text(source, "report_snapshot"),
      ),
    ],
  ]
}

///|
fn dispatch_outcome_composer_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  source : Json,
) -> @html.Html {
  let draft = dispatch_outcome_draft(model, source)
  let send = emit.map(action => OutcomeAction(source, action))
  let pending = draft.pending &&
    draft.pending_selection == model.dispatch_task_selection
  let changed_source = model.dispatch_outcome_drafts.any(item => {
    item.handoff != source &&
    dispatch_json_text(dispatch_json_field(item.handoff, "task"), "record_id") ==
    dispatch_json_text(dispatch_json_field(source, "task"), "record_id")
  })
  div(class="inline-form", id="dispatch-outcome-composer") <| [
    h3("记录实际结果"),
    p(
      "写下工作之后实际发生的事，再明确判断三类缺口。这里准备结果文件；正式审核仍在 Book 中进行。",
    ),
    p(
      "内部任务接受只表示内部流程状态。客户接受与现金事实需要各自证据，此次导出均不作断言。",
    ),
    small(
      "草稿只保留在当前标签页，切换任务不会丢失；关闭、重载页面、退出登录或切换账号会清除。",
    ),
    if changed_source {
      p(
        "捕获来源已变化。旧来源的笔记仍保留在此标签页；此版本不会自动沿用旧笔记。",
      )
    } else {
      @html.nothing
    },
    dispatch_outcome_textarea(
      "outcome-observation",
      "实际观察到了什么？",
      draft.outcome_summary,
      "写下可核实的实际结果、影响和限制，不要把内部接受当作客户结果",
      send.map(value => Edit("summary", value)),
    ),
    div(class="field") <| [
      label(for_="outcome-observed-at", "何时观察到？（UTC）"),
      input(
        id="outcome-observed-at",
        input_type=DateTimeLocal,
        value=draft.observed_at,
        step=1,
        on_input=send.map(value => Edit("observed_at", value)),
      ),
    ],
    dispatch_outcome_source_view(source),
    div <| draft.gaps.mapi((index, gap) => {
      dispatch_outcome_gap_view(send, source, index, gap)
    }),
    if dispatch_outcome_has_gap(draft) {
      div(class="inline-form") <| [
        h3("这个缺口涉及什么真实能力？"),
        p(
          "填写已有能力的准确身份及拟议改进。任务 ID 不等于能力 ID；导出不会启用能力或执行改进。",
        ),
        dispatch_task_input(
          "outcome-capability-id",
          "真实能力 ID",
          draft.capability_id,
          "来自你实际使用的能力记录",
          send.map(value => Edit("capability_id", value)),
        ),
        dispatch_task_input(
          "outcome-capability-version",
          "能力版本",
          draft.capability_version,
          "准确版本",
          send.map(value => Edit("capability_version", value)),
        ),
        dispatch_outcome_textarea(
          "outcome-capability-summary",
          "拟议改进摘要",
          draft.capability_summary,
          "概括这项能力需要怎样改进",
          send.map(value => Edit("capability_summary", value)),
        ),
        dispatch_outcome_textarea(
          "outcome-change-text",
          "拟议改进内容",
          draft.change_text,
          "描述与此缺口相关的实际改进建议",
          send.map(value => Edit("change_text", value)),
        ),
      ]
    } else {
      @html.nothing
    },
    button(
      class="button button-primary",
      type_="button",
      disabled=pending,
      on_click=send(Preview),
      if pending {
        "正在核对来源…"
      } else {
        "预览完整结果文件"
      },
    ),
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      draft.notice,
    ),
    match draft.prepared {
      Some(prepared) =>
        div(class="journey-section") <| [
          h3("准备导出的实际结果"),
          p(draft.outcome_summary),
          small("观察时间（UTC）· " + draft.observed_at),
          div <| draft.gaps.mapi((index, gap) => {
            p(
              dispatch_outcome_gap_label(index) +
              " · " +
              (if gap.choice == "present" {
                "发现，严重程度 " + gap.severity
              } else {
                "明确未发现"
              }) +
              " · " +
              gap.summary,
            )
          }),
          small(
            "请将三个文件一同保留；证据文件含捕获来源和你的原始观察。重复下载使用此次预览的相同字节。",
          ),
          button(
            class="button button-secondary",
            type_="button",
            on_click=send(Download("submission")),
            "下载完整结果",
          ),
          button(
            class="button button-secondary",
            type_="button",
            on_click=send(Download("handoff")),
            "下载来源交接",
          ),
          button(
            class="button button-secondary",
            type_="button",
            on_click=send(Download("evidence")),
            "下载证据文件",
          ),
          details(class="journey-details") <| [
            summary("导出身份与技术详情"),
            small("任务页面 · " + draft.owner_route),
            small(dispatch_json_text(prepared, "submission_filename")),
            small(dispatch_json_text(prepared, "handoff_filename")),
            small(dispatch_json_text(prepared, "evidence_filename")),
            @html.pre(
              style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
              dispatch_json_text(prepared, "submission_json"),
            ),
          ],
        ]
      None => @html.nothing
    },
  ]
}

///|
fn dispatch_outcome_control_style() -> Array[String] {
  [
    "width:100%", "min-height:44px", "padding:10px 12px", "color:var(--ink)", "background:var(--paper)",
    "border:1px solid var(--line-strong)", "border-radius:7px", "font:inherit", "box-sizing:border-box",
  ]
}

///|
fn dispatch_outcome_retained_view(model : Model) -> @html.Html {
  let current = if dispatch_lesson_current(model) {
    model.dispatch_lesson_handoff.payload
  } else {
    None
  }
  let retained = model.dispatch_outcome_drafts.filter(draft => {
    Some(draft.handoff) != current &&
    dispatch_json_text(dispatch_json_field(draft.handoff, "task"), "record_id") ==
    model.dispatch_task_id
  })
  if retained.is_empty() {
    return @html.nothing
  }
  details(class="journey-details") <| [
    summary("查看此前捕获来源的笔记（只读）"),
    p(
      "这些笔记仍属于此前捕获的准确来源。可在这里查看；不会自动复制到新来源或作为当前结果导出。",
    ),
    div <| retained.map(draft => {
      div(class="inline-form") <| [
        h3("此前的实际观察"),
        p(draft.outcome_summary),
        small("观察时间（UTC）· " + draft.observed_at),
        div <| ["task", "report"].map(key => {
          let reference = dispatch_json_field(draft.handoff, key)
          p(
            key +
            " · " +
            dispatch_json_text(reference, "record_id") +
            " / 版本 " +
            dispatch_json_text(reference, "record_version") +
            " / " +
            dispatch_json_text(reference, "record_digest"),
          )
        }),
        div <| draft.gaps.mapi((index, gap) => {
          p(
            dispatch_outcome_gap_label(index) +
            " · " +
            (if gap.choice == "present" {
              "发现，严重程度 " + gap.severity
            } else if gap.choice == "absent" {
              "明确未发现"
            } else {
              "尚未选择"
            }) +
            " · " +
            gap.summary +
            " / 证据 " +
            gap.evidence_refs.join("、"),
          )
        }),
        if ![
            draft.capability_id,
            draft.capability_version,
            draft.capability_summary,
            draft.change_text,
          ].all(value => value.is_empty()) {
          div <| [
            p(
              "能力 · " +
              draft.capability_id +
              " / 版本 " +
              draft.capability_version,
            ),
            p("拟议改进摘要 · " + draft.capability_summary),
            p("拟议改进内容 · " + draft.change_text),
          ]
        } else {
          @html.nothing
        },
      ]
    }),
  ]
}
