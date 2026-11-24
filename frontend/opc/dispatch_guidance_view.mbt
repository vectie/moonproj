///|
fn dispatch_guidance_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.dispatch_guidance
  let current = dispatch_guidance_current(model)
  let locked = dispatch_guidance_identity(model) && state.start_body is Some(_)
  if model.dispatch_task_id.is_empty() ||
    !dispatch_work_page(model) ||
    (model.dispatch_run is Some(_) && !(locked && state.selected is Some(_))) {
    return @html.nothing
  }
  let editable = dispatch_guidance_editable(model)
  details(
    class="journey-details",
    open=state.selected is Some(_) || state.phase == "waiting",
  ) <| [
    summary("可选：复用 Book 已审核经验"),
    p(
      "在第一次 Start 前，按当前任务的项目和产品查找经验。未选择经验或 Book 不可用时，仍可照常 Start。",
    ),
    if editable {
      secondary_button(
        emit,
        GuidanceAction(Prepare),
        "准备只读 Book 经验查询",
      )
    } else {
      small(
        if locked || model.dispatch_run is Some(_) {
          "原生 Start 输入已固定，不能替换所选建议。"
        } else {
          "请先读取当前正式任务，再选择可选经验。"
        },
      )
    },
    if current && state.handoff is Some(_) && editable {
      div <| [
        dispatch_task_input(
          "guidance-book-origin",
          "Book 地址（明确填写，默认空）",
          state.origin,
          "例如你自己的 Book HTTP(S) 主机地址",
          emit.map(value => GuidanceAction(Origin(value))),
        ),
        secondary_button(
          emit,
          GuidanceAction(OpenBook),
          "在此 Book 查找已审核经验",
        ),
      ]
    } else {
      @html.nothing
    },
    if (current || locked) && state.selected is Some(value) {
      let lesson = dispatch_json_field(value, "lesson")
      let review = dispatch_json_field(value, "review")
      div <| [
        strong("所选经验 · " + dispatch_json_text(lesson, "title")),
        p(dispatch_json_text(lesson, "guidance")),
        p("具名审核人 · " + dispatch_json_text(review, "reviewer_id")),
        p("适用范围"),
        div <| dispatch_continuation_array(lesson, "applicability").map(item => {
          p(
            dispatch_json_text(item, "key") +
            " · " +
            dispatch_json_text(item, "value"),
          )
        }),
        p("失效条件"),
        if dispatch_continuation_array(lesson, "invalidation").is_empty() {
          small(
            "没有额外记录的失效条件；仍需确认本次适用性。",
          )
        } else {
          div <| dispatch_continuation_array(lesson, "invalidation").map(item => {
            p(
              dispatch_json_text(item, "key") +
              " · " +
              dispatch_json_text(item, "value"),
            )
          })
        },
        p("此 Book · " + dispatch_json_text(value, "book_origin")),
        p("观察时状态 · " + dispatch_json_text(value, "currentness")),
        details <| [
          summary("经验版本与来源引用"),
          p(dispatch_json_field(lesson, "reference").stringify()),
          p(
            "审核收据 · " +
            dispatch_json_field(review, "receipt").stringify(),
          ),
          p("来源 · " + dispatch_json_field(value, "source").stringify()),
          p(
            "观察时间 · " +
            dispatch_lesson_observed_label(
              dispatch_json_field(value, "observed_at").stringify(),
            ),
          ),
        ],
      ]
    } else {
      @html.nothing
    },
    if editable &&
      current &&
      (
        state.selected is Some(_) ||
        state.phase == "waiting" ||
        state.needs_refresh
      ) {
      secondary_button(
        emit,
        GuidanceAction(Clear),
        "清除经验选择，照常 Start",
      )
    } else {
      @html.nothing
    },
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      state.notice,
    ),
  ]
}

///|
fn dispatch_guidance_capture_view(value : Json) -> @html.Html {
  if value is Null {
    return @html.nothing
  }
  if dispatch_json_text(value, "schema") != "moonproj.book-guidance-capture.v1" ||
    dispatch_json_text(value, "state") != "captured_input" {
    return small(
      "本次经验输入摘要无法读取；仍可查看执行结果。",
    )
  }
  details(class="journey-details") <| [
    summary("本次执行捕获的 Book 经验引用"),
    p(
      "此处仅显示已保留输入的引用摘要；不代表建议当前仍适用或已被执行。",
    ),
    p(
      "目标任务 · " + dispatch_json_field(value, "target_task").stringify(),
    ),
    p("经验版本 · " + dispatch_json_field(value, "lesson").stringify()),
    p("审核收据 · " + dispatch_json_field(value, "review").stringify()),
    p(
      "版本选择审核 · " +
      dispatch_json_field(value, "selection_review").stringify(),
    ),
    p("此 Book · " + dispatch_json_text(value, "book_origin")),
    p("捕获摘要 SHA-256 · " + dispatch_json_text(value, "sha256")),
    p(
      "观察时间 · " +
      dispatch_lesson_observed_label(
        dispatch_json_field(value, "observed_at").stringify(),
      ),
    ),
  ]
}
