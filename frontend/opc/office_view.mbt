///|
fn office_agent_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  agent : OfficeAgent,
  desk : Bool,
) -> @html.Html {
  let assignment = agent.assignments[0]
  button(
    type_="button",
    id="office-agent-" + dispatch_url_encode(agent.key),
    class=if desk { "office-desk" } else { "office-agent-row" },
    attrs=@html.Attrs::build()
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
      strong(agent.name),
      span(assignment.task.title),
      small(if agent.role.is_empty() { "本次执行" } else { agent.role }),
    ],
    status_badge(
      assignment.stage,
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
) -> @html.Html {
  div(
    id="office-inspector",
    class="office-inspector",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label("Agent 工作详情")
      .tabindex(-1),
  ) <| [
    div(class="office-inspector-head") <| [
      h2(agent.name),
      secondary_button(emit, OfficeAction(Close), "关闭详情"),
    ],
    p(
      if agent.parent.is_empty() {
        "执行身份 · " + agent.role
      } else {
        "本次运行专员；不代表长期公司成员。"
      },
    ),
    if !agent.assignments.any(a => a.task.id == model.office.pending_task) {
      secondary_button(emit, OfficeAction(Refresh), "刷新此 Agent")
    } else {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        "正在观察已有执行…",
      )
    },
    if model.office.error.is_empty() {
      @html.nothing
    } else {
      p(class="boundary-note", model.office.error)
    },
    div(class="office-assignments") <| agent.assignments.map(assignment => {
      let observation = office_record(model, assignment.task)
      section <| [
        h3(assignment.task.title),
        status_badge(assignment.stage, tone="info"),
        small(
          "任务阶段 · " +
          (if assignment.task.status == "done" {
            "已接受"
          } else {
            dispatch_task_stage_label(assignment.task.status)
          }),
        ),
        p(assignment.source),
        if products_field(observation, "observed_at") is Number(stamp) {
          small("本次读取 · " + office_observed_time(stamp))
        } else if model.today.observed_at.is_empty() {
          small("尚无可核实的观察时间")
        } else {
          small("公司记录读取 · " + model.today.observed_at)
        },
        if assignment.summary.is_empty() {
          p("尚无已记录的交付摘要。")
        } else {
          details(class="journey-details") <| [
            summary("结果摘要"),
            p(class="office-result", assignment.summary),
          ]
        },
        if assignment.artifacts.is_empty() {
          @html.nothing
        } else {
          div <| [
            h3("产物引用"),
            div <| assignment.artifacts.map(item => {
              p(class="office-file", products_text(item, "path"))
            }),
          ]
        },
        secondary_button(
          emit,
          TodayAction(OpenTask(assignment.task.id)),
          "打开任务",
        ),
        details(class="journey-details") <| [
          summary("执行来源"),
          p("任务 · " + assignment.task.id),
          p("命令 · " + assignment.command),
          p("会话 · " + agent.session),
          p("工作区 · " + agent.workspace),
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
    page_intro(Fleet, @html.nothing),
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
      secondary_button(emit, TodayAction(RefreshTasks), "刷新工作记录"),
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
        p("部分项目未读到；当前办公室不是完整公司名单。"),
        secondary_button(
          emit,
          TodayAction(RetryFailed),
          "重试未完成项目",
        ),
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
          "正在读取执行身份…"
        } else if state.project_id.is_empty() {
          "选择项目查看真实执行。"
        } else {
          "执行记录尚未读到。请刷新重试。"
        },
      )
    } else if agents.is_empty() {
      p(
        "尚无已记录的 Agent 执行。委派工作并启动后，实际执行身份会出现在这里。",
      )
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
            strong("我 · " + state.actor),
            small("目标与交付"),
          ],
          p(
            class="office-note",
            "仅显示已记录的运行身份；点击查看任务和状态来源，不推断在线或空闲。",
          ),
          if model.office.view == "office" {
            div <| agents
            .filter(a => a.parent.is_empty())
            .map(lead => {
              section(class="office-team") <| [
                h2(lead.assignments[0].task.title),
                div(class="office-lead") <| [
                  office_agent_button(emit, model, lead, true),
                ],
                div(class="office-workers") <| agents
                .filter(a => a.parent == lead.key)
                .map(worker => office_agent_button(emit, model, worker, true)),
              ]
            })
          } else {
            div(class="office-roster") <| agents.map(agent => {
              office_agent_button(emit, model, agent, false)
            })
          },
        ],
        match
          agents.filter(agent => agent.key == model.office.selected).get(0) {
          Some(agent) => office_inspector(emit, model, agent)
          None => @html.nothing
        },
      ]
    },
  ]
}
