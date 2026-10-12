///|
fn research_import_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.research_import
  section(class="journey-section") <| [
    h3("从 MoonFind 研究准备工作"),
    p(
      "选择导出的 decision JSON，核对来源后另建本地草稿。请勿选择含密码或访问令牌的文件。",
    ),
    secondary_button(
      emit,
      ResearchImportAction(Choose),
      if state.loading {
        "重新选择文件"
      } else {
        "选择 MoonFind 决策 JSON"
      },
    ),
    if state.open {
      div <| [
        p(
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          state.notice,
        ),
        if state.loading {
          p("正在等待文件；可以取消预览。")
        } else {
          @html.nothing
        },
        match state.brief {
          Some(brief) =>
            div <| [
              p("决策问题 · " + brief.worksheet.question),
              p(
                "选择 · " +
                brief
                .chosen()
                .map(option => option.name)
                .unwrap_or("尚未选择"),
              ),
              p("理由 · " + brief.worksheet.reasoning),
              p("下一步 · " + brief.worksheet.next_action),
              p(
                class="boundary-note",
                "来源状态仅为导出时记录，当前新鲜度未核实。研究不是已验证需求，也不是正式公司决定。",
              ),
              p("导出时状态 · " + brief.evidence_status),
              details(class="journey-details") <| [
                summary("核对保留的来源、反证与未知项"),
                @html.pre(
                  style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
                  brief.markdown(),
                ),
              ],
              if !brief.preparation_blocker().is_empty() {
                p(brief.preparation_blocker())
              } else {
                @html.nothing
              },
              button(
                type_="button",
                class="button button-primary",
                disabled=state.loading ||
                  !brief.preparation_blocker().is_empty(),
                on_click=emit(ResearchImportAction(Prepare)),
                "准备可编辑草稿",
              ),
            ]
          None => @html.nothing
        },
        secondary_button(
          emit,
          ResearchImportAction(Close),
          "取消 / 关闭研究预览",
        ),
      ]
    } else {
      @html.nothing
    },
  ]
}

///|
fn research_draft_context(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  guard dispatch_active_draft(model) is Some(draft) else {
    return @html.nothing
  }
  div <| [
    if draft.research_brief is Some(brief) {
      details(class="journey-details") <| [
        summary("保留的研究决策与来源（原始参考）"),
        p(
          "任务名称与验收标准可以继续编辑。这里保留导入时的研究，不会把后续任务编辑改写为研究结论。",
        ),
        @html.pre(
          style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
          brief.markdown(),
        ),
      ]
    } else {
      @html.nothing
    },
    secondary_button(
      emit,
      ResearchImportAction(ExportDraft(draft.id)),
      "导出本地工作包 Markdown",
    ),
  ]
}
