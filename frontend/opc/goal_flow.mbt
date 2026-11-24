///|
fn page_glyph(page : Page) -> String {
  match page {
    Objectives => "projects"
    Overview => "overview"
    Fleet => "agents"
    Dispatch => "tasks"
    Projects => "projects"
    Quality => "quality"
    Observe => "observe"
    Operate => "operate"
    Company => "company"
    PolicyRadar => "observe"
    Evidence => "evidence"
    Guide => "guide"
    MoonSuite => "suite"
    _ => "domain"
  }
}

///|
fn opc_glyph(name : String) -> @html.Html {
  span(
    class="opc-glyph glyph-\{name}",
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
fn dispatch_goal_stage(model : Model) -> Int32 {
  match model.dispatch_task_stage {
    "pending" => 2
    "in_progress" => 3
    "submitted" => 4
    "accepted" => 5
    _ => 1
  }
}

///|
fn dispatch_goal_step(
  number : Int32,
  label : String,
  glyph : String,
  current : Int32,
  blocked : Bool,
) -> @html.Html {
  let state = if number < current {
    "complete"
  } else if number == current && blocked {
    "blocked"
  } else if number == current {
    "current"
  } else {
    "next"
  }
  div(class="goal-step is-\{state}") <| [
    opc_glyph(glyph),
    div <| [
      strong(label),
      small(
        match state {
          "complete" => "完成"
          "blocked" => "已阻断"
          "current" => "当前"
          _ => "下一步"
        },
      ),
    ],
  ]
}

///|
fn dispatch_goal_action(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if !model.dispatch_task_pending_action.is_empty() {
    status_badge("等待持久化收据", tone="warning")
  } else if model.dispatch_task_form_open {
    a(
      class="button button-primary",
      href="#dispatch-draft",
      "继续填写目标",
    )
  } else {
    match model.dispatch_task_stage {
      "pending" | "in_progress" =>
        a(
          class="button button-primary",
          href="#dispatch-task-workspace",
          if dispatch_can_start(model) {
            "查看并开始执行"
          } else if dispatch_can_submit(model) {
            "查看结果 / 提交报告"
          } else {
            "查看执行状态"
          },
        )
      "submitted" =>
        a(
          class="button button-primary",
          href="#dispatch-task-workspace",
          if dispatch_can_accept_report(model) {
            "接受结果"
          } else {
            "查看报告 / 处理当前来源"
          },
        )
      "accepted" =>
        a(
          class="button button-primary",
          href="#dispatch-learning",
          "保存有用的经验",
        )
      _ =>
        primary_button(emit, Navigate(Products), "从产品创建正式任务")
    }
  }
}

///|
fn dispatch_goal_copy(model : Model) -> String {
  if model.dispatch_task_form_open {
    "正在准备新的任务草稿；已打开的正式任务仍独立保留在下方。"
  } else if model.dispatch_task_blocked {
    model.dispatch_task_note
  } else {
    match model.dispatch_task_stage {
      "pending" =>
        "任务与验收标准已持久化；下一步明确开始执行。"
      "in_progress" =>
        match delivery_control(model) {
          "stopped" => "交付已停止；已有结果保留。"
          "stopping" =>
            "停止待确认；尚未确认全部执行与专员会话停止。"
          "revising" => "正在继续同一交付，旧报告仍保留。"
          "resuming" => "恢复交付待确认；尚未确认执行已继续。"
          _ => dispatch_native_label(model.dispatch_run)
        }
      "submitted" =>
        if dispatch_can_accept_report(model) {
          "证据已提交；只有具名验收才会关闭任务。"
        } else {
          dispatch_accept_report_blocker(model)
        }
      "accepted" =>
        "任务已接受。你可以把有用的方法保存到这本 Book，再为下一目标准备新任务。"
      _ =>
        "先写清交付结果与验收标准，再产生任何编排状态。"
    }
  }
}

///|
fn dispatch_goal_flow(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let stage = if model.dispatch_task_form_open {
    1
  } else if model.dispatch_task_stage == "in_progress" &&
    !dispatch_can_submit(model) {
    2
  } else {
    dispatch_goal_stage(model)
  }
  let blocked = model.dispatch_task_blocked
  section(
    class=if blocked { "goal-flow is-blocked" } else { "goal-flow" },
    attrs=@html.Attrs::build().aria_label("正式任务闭环"),
  ) <| [
    div(class="goal-flow-head") <| [
      div <| [
        p(class="page-kicker", "你的结果"),
        h2("交付一个可验收的正式任务"),
        p(class="goal-flow-copy", dispatch_goal_copy(model)),
      ],
      div(class="goal-next") <| [
        small(if blocked { "恢复操作" } else { "下一步" }),
        dispatch_goal_action(emit, model),
      ],
    ],
    div(class="goal-rail") <| [
      dispatch_goal_step(1, "准备任务", "edit", stage, blocked),
      dispatch_goal_step(2, "执行", "start", stage, blocked),
      dispatch_goal_step(3, "查看与提交", "evidence", stage, blocked),
      dispatch_goal_step(4, "核对并接受", "quality", stage, blocked),
      dispatch_goal_step(5, "保存经验", "guide", stage, blocked),
    ],
    div(
      class=if blocked { "goal-result is-denied" } else { "goal-result" },
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
    ) <| [
      strong(if blocked { "操作未完成" } else { "当前结果" }),
      span(
        if model.dispatch_task_stage == "submitted" &&
          model.dispatch_task_pending_action.is_empty() &&
          !model.dispatch_task_blocked &&
          !dispatch_can_accept_report(model) {
          dispatch_accept_report_blocker(model)
        } else if model.dispatch_task_note.is_empty() {
          dispatch_task_stage_label(model.dispatch_task_stage)
        } else {
          model.dispatch_task_note
        },
      ),
      small("后端收据是唯一状态真相；界面不会自行放行"),
    ],
  ]
}

///|
fn dispatch_learning_next(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.dispatch_task_stage != "accepted" {
    return @html.nothing
  }
  section(id="dispatch-learning", class="journey-section learning-next") <| [
    h3("下一步 · 保存有用的经验"),
    dispatch_lesson_handoff_view(emit, model),
    p(
      "接受任务不会自动保存经验，也不会自动在 Town 中复用。",
    ),
    if model.dispatch_run is Some(_) {
      secondary_button(
        emit,
        DeskHandoffAction(Open),
        "打开本次工作所在的 MoonDesk",
      )
    } else {
      p(
        "此任务未记录原生执行，无法从这里定位 Book。请在 MoonDesk 中明确选择对应 Book。",
      )
    },
    @html.ol(class="journey-instructions") <| [
      li(
        if model.dispatch_run is Some(_) {
          "在 Captured work 页面点击 Review this Book’s learning；也可以在本次工作对应的回答旁点击 Teach this book。"
        } else {
          "明确选中同一个 Book 后，在 Book 工作区点击 Review，在 Document tools 中选择 Learning。"
        },
      ),
      li(
        "使用 Add learning 新建条目，或编辑 Teach this book 已打开的草稿；写下值得复用的方法，Save for review 后检查并 Accept learning。",
      ),
      li(
        "查看保存结果；若出现 Save to book 或 Retry book save，请完成该操作并确认 Saved to book。",
      ),
      li(
        if model.dispatch_run is Some(_) {
          "可选：确认 Saved to book 后关闭 Learning Review，再点击 Exit inspection。保持同一个 Book，进入 Publish → Experienced Book package，检查并决定是否打包复用。这里不会自动打包或传输到 Town。"
        } else {
          "可选：确认 Saved to book 后关闭 Document tools。保持同一个 Book，进入 Publish → Experienced Book package，检查并决定是否打包复用。这里不会自动打包或传输到 Town。"
        },
      ),
    ],
    p(
      "Book 交接回执只确认任务上下文已接收；MoonProj 尚未读取学习保存收据。上面的 Desk 步骤保留为原有学习路径。",
    ),
    if model.dispatch_desk_handoff.task_id == model.dispatch_task_id &&
      model.dispatch_desk_handoff.selection == model.dispatch_task_selection &&
      !model.dispatch_desk_handoff.error.is_empty() {
      p(class="boundary-note", model.dispatch_desk_handoff.error)
    } else {
      @html.nothing
    },
    secondary_button(emit, Navigate(Products), "选择下一个产品目标"),
  ]
}
