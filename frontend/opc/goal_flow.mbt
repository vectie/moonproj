///|
fn page_glyph(page : Page) -> String {
  match page {
    Overview => "overview"
    Fleet => "agents"
    Dispatch => "tasks"
    Projects => "projects"
    Quality => "quality"
    Observe => "observe"
    Operate => "operate"
    Company => "company"
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
fn dispatch_goal_stage(model : Model) -> Int {
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
  number : Int,
  label : String,
  glyph : String,
  current : Int,
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
  } else {
    match model.dispatch_task_stage {
      "pending" => primary_button(emit, StartDispatchTask, "开始执行")
      "in_progress" =>
        a(
          class="button button-primary",
          href="#dispatch-task-workspace",
          attrs=@html.Attrs::build().aria_label("添加交付证据"),
          "添加证据",
        )
      "submitted" => primary_button(emit, AcceptDispatchTask, "接受结果")
      "accepted" =>
        secondary_button(emit, OpenDispatchTaskForm, "创建下一任务")
      _ => primary_button(emit, OpenDispatchTaskForm, "创建正式任务")
    }
  }
}

///|
fn dispatch_goal_copy(model : Model) -> String {
  if model.dispatch_task_blocked {
    "命令没有推进状态。按阻断原因修复身份、权限或网关，再重试当前步骤。"
  } else {
    match model.dispatch_task_stage {
      "pending" =>
        "任务与验收标准已持久化；下一步明确开始执行。"
      "in_progress" =>
        "提交真实制品或证据引用，系统不会把界面样例当成交付。"
      "submitted" => "证据已提交；只有具名验收才会关闭任务。"
      "accepted" =>
        "事件与审计收据已闭环；新目标必须创建新的任务身份。"
      _ =>
        "先写清交付结果与验收标准，再产生任何编排状态。"
    }
  }
}

///|
fn dispatch_goal_flow(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let stage = dispatch_goal_stage(model)
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
        small(if blocked { "安全恢复" } else { "下一安全动作" }),
        dispatch_goal_action(emit, model),
      ],
    ],
    div(class="goal-rail") <| [
      dispatch_goal_step(1, "定义", "edit", stage, blocked),
      dispatch_goal_step(2, "开始", "start", stage, blocked),
      dispatch_goal_step(3, "提交", "evidence", stage, blocked),
      dispatch_goal_step(4, "验收", "quality", stage, blocked),
    ],
    div(
      class=if blocked { "goal-result is-denied" } else { "goal-result" },
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
    ) <| [
      strong(if blocked { "命令已安全阻断" } else { "当前结果" }),
      span(
        if model.dispatch_task_note.is_empty() {
          dispatch_task_stage_label(model.dispatch_task_stage)
        } else {
          model.dispatch_task_note
        },
      ),
      small("后端收据是唯一状态真相；界面不会自行放行"),
    ],
  ]
}
