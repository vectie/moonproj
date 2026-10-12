///|
fn work_packet_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.work_packet
  let project = dispatch_active_draft(model)
    .map(d => d.project_id)
    .unwrap_or("")
  details(class="journey-details") <| [
    summary("可重用工作简报 · JSON 导入与导出"),
    p(
      "保存任务名称、验收标准、来源、观察到的问题和计划日期，以便在其他草稿中重用。",
    ),
    p(
      class="boundary-note",
      "简报不含项目、负责人、登录身份、执行设置、任务收据、提案或附加研究。需要完整可读上下文时，使用上方 Markdown 工作包导出。请勿在自由文本中填写秘密。",
    ),
    secondary_button(
      emit,
      WorkPacketAction(Export),
      "下载可重用简报 (.json)",
    ),
    secondary_button(emit, WorkPacketAction(Choose), "选择工作简报 JSON"),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("work-packet-source"),
        "或粘贴工作简报 JSON",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("work-packet-source"),
        value=state.text,
        on_input=emit.map(value => WorkPacketAction(Source(value))),
        "",
      ),
    ],
    button(
      type_="button",
      class="button button-secondary",
      disabled=state.loading || state.text.is_empty(),
      on_click=emit(WorkPacketAction(Preview)),
      "预览工作简报",
    ),
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      state.notice,
    ),
    match state.packet {
      Some(packet) if !state.loading =>
        div <| [
          @html.h4("简报预览"),
          div <| [
            ("任务名称", packet.title),
            ("验收标准", packet.acceptance),
            ("来源引用", packet.source_reference),
            ("观察到的问题", packet.observed_problem),
            ("计划开始（原文）", packet.begin_date),
            ("计划完成（原文）", packet.end_date),
          ].map(pair => {
            div <| [
              strong(pair.0),
              @html.pre(
                style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
                if pair.1.is_empty() {
                  "（空白，待补充）"
                } else {
                  pair.1
                },
              ),
            ]
          }),
          p(
            "目标项目：" +
            (if project.is_empty() {
              "未填写，导入后补充"
            } else {
              project
            }),
          ),
          p(
            "将另建普通本地草稿；原草稿和正式任务保留。负责人、产品绑定与执行设置不复制。",
          ),
          secondary_button(
            emit,
            WorkPacketAction(Apply),
            "另建可编辑草稿",
          ),
        ]
      _ => @html.nothing
    },
    if state.open {
      secondary_button(emit, WorkPacketAction(Close), "取消简报预览")
    } else {
      @html.nothing
    },
  ]
}
