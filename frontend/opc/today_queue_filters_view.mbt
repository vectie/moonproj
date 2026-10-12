///|
fn today_filter_select(
  emit : @rabbita.Emit[Msg],
  state : TodayState,
  field : String,
  title : String,
  selected : String,
  choices : Array[(String, String)],
) -> @html.Html {
  let id = "today-filter-" + field
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(id), title),
    @html.select(
      attrs=@html.Attrs::build().id(id),
      on_change=emit.map(value => {
        TodayAction(
          Filter(state.actor, state.epoch, state.work_request, field, value),
        )
      }),
    ) <| choices.map(choice => {
      @html.option(value=choice.0, selected=selected == choice.0, choice.1)
    }),
  ]
}

///|
fn today_filters_view(
  emit : @rabbita.Emit[Msg],
  state : TodayState,
) -> @html.Html {
  let owners = today_observed_owners(state)
  let selected = state.filters.owner
  // Keep an explicitly selected identity visible if refresh no longer observes
  // it. Never silently broaden a restricted queue to all owners.
  if selected != "" &&
    selected != "unassigned" &&
    !owners.any(owner => owner.0 == selected) {
    owners.push((selected, "当前未观察到的负责人 · " + selected))
  }
  div(class="today-filters") <| [
    h3("筛选已观察队列"),
    p(
      "仅当前 Today 页面；负责人来自已观察任务，不是公司成员目录。标题按包含文本匹配，忽略 ASCII 大小写。",
    ),
    today_filter_select(
      emit,
      state,
      "owner",
      "负责人（精确 ID）",
      selected,
      [("", "全部已观察负责人"), ("unassigned", "未分配"), ..owners],
    ),
    today_filter_select(
      emit,
      state,
      "due",
      "到期 / 留意",
      state.filters.due,
      [
        ("", "全部到期状态"),
        ("attention", "需要留意"),
        ("overdue", "已逾期（日期或正式状态）"),
        ("today", "今日到期"),
        ("future", "未来到期"),
        ("unknown", "到期判断未知"),
      ],
    ),
    today_filter_select(
      emit,
      state,
      "blocker",
      "阻塞",
      state.filters.blocker,
      [
        ("", "全部阻塞状态"),
        ("blocked", "已观察到阻塞"),
        ("unblocked", "未观察到阻塞"),
      ],
    ),
    label(attrs=@html.Attrs::build().for_("today-filter-title"), "标题包含"),
    input(
      attrs=@html.Attrs::build().id("today-filter-title"),
      value=state.filters.title,
      on_input=emit.map(value => {
        TodayAction(
          Filter(state.actor, state.epoch, state.work_request, "title", value),
        )
      }),
    ),
    secondary_button(
      emit,
      TodayAction(
        Filter(state.actor, state.epoch, state.work_request, "clear", ""),
      ),
      "清除筛选",
    ),
  ]
}
