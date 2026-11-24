///|
fn office_member_label(
  agent : OfficeAgent,
  agents : Array[OfficeAgent],
) -> String {
  if agent.parent.is_empty() {
    return "负责人"
  }
  for index, member in agents.filter(a => a.parent == agent.parent) {
    if member.key == agent.key {
      return "专员 " + (index + 1).to_string()
    }
  }
  "专员"
}

///|
fn office_status_label(stage : String) -> String {
  match stage {
    "执行中" => "工作中"
    "执行完成" => "已完成"
    "执行失败" => "遇到问题"
    "待验收" => "待我验收"
    "已接受" => "已验收"
    _ => stage
  }
}

///|
fn office_next_step(assignment : OfficeAssignment) -> String {
  if ["done", "accepted"].contains(assignment.task.status) {
    return "整个任务已验收。"
  }
  if assignment.task.status == "submitted" {
    return "整个任务等待你验收。"
  }
  match assignment.stage {
    "执行完成" => "这部分工作已完成，整个任务还未验收。"
    "已停止" | "已暂停" => "如需继续，请打开任务。"
    "执行失败" | "执行环境不可用" =>
      "打开任务查看问题并处理。"
    "状态未确认"
    | "结果未确认"
    | "停止待确认"
    | "恢复待确认" => "状态尚未确认，请更新状态。"
    "等待输入或审批" => "打开任务处理待办。"
    _ => ""
  }
}

///|
fn office_agent_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  agent : OfficeAgent,
  agents : Array[OfficeAgent],
  desk : Bool,
) -> @html.Html {
  let assignment = agent.assignments[0]
  let name = office_member_label(agent, agents)
  let stage = office_status_label(assignment.stage)
  button(
    type_="button",
    id="office-agent-" + dispatch_url_encode(agent.key),
    class=if desk { "office-desk" } else { "office-agent-row" },
    attrs=@html.Attrs::build()
      .aria_label(name + " · " + assignment.task.title + " · " + stage)
      .aria_pressed(
        if model.office.selected == agent.key {
          "true"
        } else {
          "false"
        },
      )
      .aria_controls("office-inspector"),
    on_click=emit(OfficeAction(Select(agent.key))),
  ) <| [
    span(
      class="office-avatar",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    span(class="office-agent-copy") <| [
      strong(name),
      if desk {
        @html.nothing
      } else {
        span(assignment.task.title)
      },
    ],
    status_badge(
      stage,
      tone=if [
          "执行失败", "状态未确认", "执行环境不可用", "停止待确认",
        ].contains(assignment.stage) {
        "warning"
      } else {
        "info"
      },
    ),
  ]
}

///|
fn office_inspector(
  emit : @rabbita.Emit[Msg],
  model : Model,
  agent : OfficeAgent,
  agents : Array[OfficeAgent],
) -> @html.Html {
  div(
    id="office-inspector",
    class="office-inspector",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label("成员工作详情")
      .tabindex(-1),
  ) <| [
    div(class="office-inspector-head") <| [
      h2(office_member_label(agent, agents)),
      secondary_button(emit, OfficeAction(Close), "关闭"),
    ],
    if agent.assignments.any(a => a.task.id == model.office.pending_task) {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        "正在更新状态…",
      )
    } else {
      @html.nothing
    },
    if model.office.error.is_empty() {
      @html.nothing
    } else {
      div(class="boundary-note") <| [
        p("状态更新失败，正在显示已保存的记录。"),
        secondary_button(emit, OfficeAction(Refresh), "重试"),
      ]
    },
    div(class="office-assignments") <| agent.assignments.map(assignment => {
      let observation = office_record(model, assignment.task)
      section <| [
        h3(assignment.task.title),
        status_badge(office_status_label(assignment.stage), tone="info"),
        if office_next_step(assignment).is_empty() {
          @html.nothing
        } else {
          p(class="office-next-step", office_next_step(assignment))
        },
        if !assignment.summary.is_empty() {
          details(class="journey-details") <| [
            summary("工作摘要"),
            p(class="office-result", assignment.summary),
          ]
        } else if assignment.artifacts.is_empty() {
          p("暂无工作成果。")
        } else {
          @html.nothing
        },
        if assignment.artifacts.is_empty() {
          @html.nothing
        } else {
          div <| [
            h3("工作成果"),
            div <| assignment.artifacts.map(item => {
              p(class="office-file", products_text(item, "path"))
            }),
          ]
        },
        primary_button(
          emit,
          TodayAction(OpenTask(assignment.task.id)),
          "查看任务",
        ),
        details(class="journey-details") <| [
          summary("详细记录"),
          p("原始名称 · " + agent.name),
          if agent.role.is_empty() {
            @html.nothing
          } else {
            p("执行角色 / 模型 · " + agent.role)
          },
          p(
            "任务状态 · " +
            dispatch_task_stage_label(assignment.task.status),
          ),
          p(assignment.source),
          if products_field(observation, "observed_at") is Number(stamp) {
            small("更新时间 · " + office_observed_time(stamp))
          } else if model.today.observed_at.is_empty() {
            @html.nothing
          } else {
            small("记录读取时间 · " + model.today.observed_at)
          },
          p("任务 · " + assignment.task.id),
          p("命令 · " + assignment.command),
          p("会话 · " + agent.session),
          p("工作区 · " + agent.workspace),
          secondary_button(emit, OfficeAction(Refresh), "更新状态"),
        ],
      ]
    }),
  ]
}

///|
extern "js" fn office_observed_time(stamp : Double) -> String =
  #| stamp => new Date(stamp).toLocaleString()

///|
fn office_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.today
  let agents = office_agents(model)
  let ready = state.project_state == "ready" &&
    (if state.scope == "all" {
      !today_portfolio_busy(state)
    } else {
      ["ready", "empty"].contains(state.work_state)
    })
  section(class="page office-page") <| [
    header(class="page-intro") <| [
      div(class="page-intro-copy") <| [
        h1("我的办公室"),
        p(class="page-question", "点击成员，查看工作和结果。"),
      ],
    ],
    div(class="office-toolbar") <| [
      div(
        class="office-switch",
        attrs=@html.Attrs::build()
          .role("group")
          .aria_label("Agent 查看方式"),
      ) <| [
        button(
          type_="button",
          class="button button-secondary",
          attrs=@html.Attrs::build().aria_pressed(
            if model.office.view == "office" {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(OfficeAction(View("office"))),
          "迷你办公室",
        ),
        button(
          type_="button",
          class="button button-secondary",
          attrs=@html.Attrs::build().aria_pressed(
            if model.office.view == "fleet" {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(OfficeAction(View("fleet"))),
          "Agent 编队",
        ),
      ],
      secondary_button(emit, TodayAction(RefreshTasks), "刷新"),
    ],
    objective_project_picker(emit, model),
    if state.project_state == "ready" && state.projects.length() > 1 {
      button(
        type_="button",
        class="button button-secondary",
        attrs=@html.Attrs::build()
          .aria_pressed(if state.scope == "all" { "true" } else { "false" })
          .disabled(state.scope == "all" && today_portfolio_busy(state)),
        on_click=emit(TodayAction(ChooseAll)),
        "所有公司项目",
      )
    } else {
      @html.nothing
    },
    if state.scope == "all" &&
      state.project_reads.any(row => {
        !today_portfolio_success(row) &&
        !["loading", "queued"].contains(row.state)
      }) {
      div(class="boundary-note") <| [
        p("部分项目未加载，成员显示不完整。"),
        secondary_button(emit, TodayAction(RetryFailed), "重试"),
      ]
    } else {
      @html.nothing
    },
    if state.project_state != "ready" {
      @html.nothing
    } else if !ready && agents.is_empty() {
      p(
        attrs=@html.Attrs::build().role("status"),
        if state.scope == "all" || state.work_state == "loading" {
          "正在加载成员…"
        } else if state.project_id.is_empty() {
          "请选择项目。"
        } else {
          "未能加载成员，请刷新重试。"
        },
      )
    } else if agents.is_empty() {
      div <| [
        p("还没有成员开始工作。"),
        secondary_button(emit, Navigate(Objectives), "安排工作"),
      ]
    } else {
      div(class="office-layout") <| [
        div(
          class="office-floor",
          attrs=@html.Attrs::build().aria_label(
            if model.office.view == "office" {
              "迷你办公室地图"
            } else {
              "Agent 编队列表"
            },
          ),
        ) <| [
          div(class="office-owner") <| [
            strong("我"),
          ],
          if model.office.view == "office" {
            div <| agents
            .filter(a => a.parent.is_empty())
            .map(lead => {
              section(class="office-team") <| [
                h2(lead.assignments[0].task.title),
                div(class="office-lead") <| [
                  office_agent_button(emit, model, lead, agents, true),
                ],
                div(class="office-workers") <| agents
                .filter(a => a.parent == lead.key)
                .map(worker => {
                  office_agent_button(emit, model, worker, agents, true)
                }),
              ]
            })
          } else {
            div(class="office-roster") <| agents.map(agent => {
              office_agent_button(emit, model, agent, agents, false)
            })
          },
        ],
        match
          agents.filter(agent => agent.key == model.office.selected).get(0) {
          Some(agent) => office_inspector(emit, model, agent, agents)
          None => @html.nothing
        },
      ]
    },
  ]
}
