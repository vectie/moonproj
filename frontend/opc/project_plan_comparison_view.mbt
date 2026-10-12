///|
fn plan_compare_selector(
  emit : @rabbita.Emit[Msg],
  state : PlanWorkbench,
  before : Bool,
) -> @html.Html {
  let selected = if before {
    state.comparison.before_key
  } else {
    state.comparison.after_key
  }
  let id = if before { "plan-compare-before" } else { "plan-compare-after" }
  div(class="field") <| [
    label(
      attrs=@html.Attrs::build().for_(id),
      if before {
        "Before · 对比前版本"
      } else {
        "After · 对比后版本"
      },
    ),
    @html.select(
      attrs=@html.Attrs::build().id(id),
      on_change=emit.map(key => PlanAction(Compare(Select(before, key)))),
    ) <| [
      @html.option(
        value="",
        selected=selected.is_empty(),
        "选择已保存版本",
      ),
      ..state.history.map(item => {
        let key = products_text(item, "key")
        @html.option(
          value=key,
          selected=selected == key,
          products_text(item, "recorded_at") + " · " + key,
        )
      }),
    ],
  ]
}

///|
fn plan_comparison_view(
  emit : @rabbita.Emit[Msg],
  state : PlanWorkbench,
) -> @html.Html {
  let s = state.comparison
  section(class="section-block plan-comparison") <| [
    h3("对比两个已保存计划 · 只读"),
    p(
      "对比保留当前草稿和准备结果。两个版本仍等待具名人工复核；不批准预算、付款、合同或执行。",
    ),
    if !s.visible {
      plan_button(
        emit,
        Compare(Show),
        "选择版本进行只读对比",
        disabled=state.history.is_empty(),
      )
    } else {
      div <| [
        plan_compare_selector(emit, state, true),
        plan_compare_selector(emit, state, false),
        plan_button(
          emit,
          Compare(Swap),
          "交换 Before / After",
          disabled=s.before_key.is_empty() || s.after_key.is_empty(),
        ),
        plan_button(
          emit,
          Compare(Load),
          "重新读取对比",
          disabled=s.before_key.is_empty() || s.after_key.is_empty(),
        ),
        plan_button(emit, Compare(Close), "关闭对比"),
        p(s.note),
        match s.result {
          None => @html.nothing
          Some(result) =>
            div <| [
              details(class="journey-details") <| [
                summary("版本、时间与来源（不计入内容变化）"),
                h3("Before"),
                @html.pre(result.before_header),
                h3("After"),
                @html.pre(result.after_header),
              ],
              if result.changes.is_empty() {
                p("没有实质内容变化 · No substantive changes")
              } else {
                p(
                  result.changes.length().to_string() +
                  " 项对比记录（变化或不可用）",
                )
              },
              div <| result.changes.map(change => {
                details(class="journey-details") <| [
                  summary(
                    change.kind +
                    " · " +
                    change.id +
                    " · " +
                    change.field +
                    " · " +
                    change.status,
                  ),
                  strong("Before"),
                  @html.pre(change.before),
                  strong("After"),
                  @html.pre(change.after),
                  if change.delta.is_empty() {
                    @html.nothing
                  } else {
                    p("Delta: " + change.delta)
                  },
                ]
              }),
              plan_button(emit, Compare(Export), "下载可读对比报告"),
            ]
        },
      ]
    },
  ]
}
