///|
fn workspace_status(stage : String) -> @html.Html {
  span(class="job-status", attrs=@html.Attrs::build().data_set("stage", stage)) <| [
    span(
      class="job-status-mark",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    span(workspace_stage_label(stage)),
  ]
}

///|
fn workspace_job_card(
  emit : @rabbita.Emit[Msg],
  model : Model,
  job : TodayTask,
  spotlight~ : Bool = false,
) -> @html.Html {
  let parent = workspace_parent(model, job)
  let stage = workspace_stage(workspace_record(model, job), job)
  let pinned = charter_is_critical_task(model.charter, job.id)
  let card = button(
    type_="button",
    class="flow-job",
    attrs=@html.Attrs::build()
      .data_set("job-id", job.id)
      .data_set("parent", parent)
      .data_set("stage", stage)
      .data_set("receipt", workspace_receipt(model, job))
      .data_set("pinned", if pinned { "true" } else { "false" })
      .data_set("stage-spotlight", if spotlight { "true" } else { "false" })
      .aria_label(job.title + " · " + workspace_stage_label(stage))
      .title(job.title),
    on_click=emit(WorkspaceAction(Focus(job.id))),
  ) <| [
    span(class="flow-job-icon", attrs=@html.Attrs::build().aria_hidden("true")) <| [
      span(class="opc-glyph glyph-tasks", ""),
    ],
    div(class="flow-job-copy") <| [
      h3(job.title),
      workspace_status(stage),
      if !job.execution_error.is_empty() && stage == "failed" {
        p(class="flow-job-error", job.execution_error)
      } else {
        @html.nothing
      },
    ],
    span(
      class="job-open-mark",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "↗",
    ),
  ]
  if !model.charter.persisted {
    return card
  }
  div(
    class="flow-job-row",
    attrs=@html.Attrs::build().data_set(
      "pinned",
      if pinned {
        "true"
      } else {
        "false"
      },
    ),
  ) <| [
    card,
    button(
      type_="button",
      class="workspace-quiet-button flow-job-priority-toggle",
      disabled=model.charter.saving,
      attrs=@html.Attrs::build()
        .aria_pressed(if pinned { "true" } else { "false" })
        .aria_label(
          if pinned {
            "移出 20% 关键聚焦：" + job.title
          } else {
            "标为 20% 关键决策：" + job.title
          },
        )
        .title(
          if pinned {
            "移出 20% 关键聚焦"
          } else {
            "固定到 20% 关键聚焦"
          },
        ),
      on_click=emit(CharterAction(ToggleCriticalTask(job.id))),
      if pinned {
        "已入 20%"
      } else {
        "标为 20%"
      },
    ),
  ]
}

///|
fn workspace_goal_group(
  emit : @rabbita.Emit[Msg],
  model : Model,
  goal : TodayTask,
  jobs : Array[TodayTask],
  spotlight_task_id~ : String = "",
) -> @html.Html {
  let record = objective_metadata(model.today, goal.id)
  let accepted = products_field(record, "objective_result") is Object(_) &&
    goal.status == "done"
  section(class="flow-group", attrs=@html.Attrs::build().aria_label(goal.title)) <| [
    article(
      class="flow-goal",
      attrs=@html.Attrs::build().data_set("goal-id", goal.id),
    ) <| [
      small("共同交付"),
      h2(goal.title),
      p(
        class="goal-state",
        if accepted {
          "已采纳交付"
        } else {
          "等待可验收的成果"
        },
      ),
      details(class="flow-goal-details") <| [
        summary("交付要求"),
        p(products_text(record, "remarks")),
      ],
      button(
        type_="button",
        class="button button-secondary button-small",
        on_click=emit(WorkspaceAction(ManageGoal(goal.id))),
        "管理目标",
      ),
    ],
    div(
      class="flow-jobs",
      attrs=@html.Attrs::build().aria_label("为此目标工作的任务"),
    ) <| (if jobs.is_empty() {
      [
        p("尚未安排工作。"),
        primary_button(
          emit,
          TodayAction(DelegateObjective(goal.id)),
          "安排工作",
        ),
      ]
    } else {
      jobs.map(job => {
        workspace_job_card(
          emit,
          model,
          job,
          spotlight=!spotlight_task_id.is_empty() && job.id == spotlight_task_id,
        )
      })
    }),
  ]
}

///|
fn workspace_agent_short_name(name : String) -> String {
  name.split("（").next().unwrap_or(name[:]).to_owned()
}

///|
fn workspace_standing_agents(model : Model) -> Array[CharterRole] {
  match model.charter.charter {
    Some(charter) => charter.roles.filter(r => r.kind == "agent")
    None => []
  }
}

///|
fn workspace_agent_sheet_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.workspace.focused_agent.is_empty() {
    return @html.nothing
  }
  match model.charter.charter {
    None => @html.nothing
    Some(charter) =>
      match
        charter.roles.filter(r => r.id == model.workspace.focused_agent).get(0) {
        None => @html.nothing
        Some(role) =>
          div(
            class="desktop-sheet-backdrop",
            attrs=@html.Attrs::build().data_set("desktop-sheet", "agent"),
          ) <| [
            button(
              type_="button",
              class="desktop-sheet-scrim",
              attrs=@html.Attrs::build().aria_label("关闭智能体详情"),
              on_click=emit(WorkspaceAction(CloseSheet)),
              "",
            ),
            section(
              class="desktop-sheet desktop-sheet-compact",
              attrs=@html.Attrs::build().role("dialog").aria_label(role.name),
            ) <| [
              header(class="desktop-sheet-bar") <| [
                div(class="desktop-sheet-bar-title") <| [
                  small(charter_tier_title(role.tier)),
                  h2(role.name),
                ],
                div(class="desktop-sheet-bar-actions") <| [
                  button(
                    type_="button",
                    class="workspace-quiet-button",
                    on_click=emit(WorkspaceAction(Tab("org"))),
                    "查看完整组织",
                  ),
                  button(
                    type_="button",
                    class="workspace-quiet-button desktop-sheet-close",
                    on_click=emit(WorkspaceAction(CloseSheet)),
                    "× 返回桌面",
                  ),
                ],
              ],
              div(class="desktop-sheet-body") <| [
                charter_role_card(charter, role),
              ],
            ],
          ]
      }
  }
}

///|
fn workspace_overlay_sheet_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.page != Workspace || workspace_has_open_app(model.workspace) {
    return @html.nothing
  }
  if model.workspace.tab == "org" {
    return div(
      class="desktop-sheet-backdrop",
      attrs=@html.Attrs::build().data_set("desktop-sheet", "org"),
    ) <| [
      button(
        type_="button",
        class="desktop-sheet-scrim",
        attrs=@html.Attrs::build().aria_label("关闭组织与权力面板"),
        on_click=emit(WorkspaceAction(CloseSheet)),
        "",
      ),
      section(
        class="desktop-sheet",
        attrs=@html.Attrs::build()
          .role("dialog")
          .aria_label("组织与权力结构"),
      ) <| [
        header(class="desktop-sheet-bar") <| [
          div(class="desktop-sheet-bar-title") <| [
            small("桌面浮层 · 不离开当前工作全景"),
            h2("组织与权力"),
          ],
          button(
            type_="button",
            class="workspace-quiet-button desktop-sheet-close",
            on_click=emit(WorkspaceAction(CloseSheet)),
            "× 返回桌面",
          ),
        ],
        div(class="desktop-sheet-body") <| [
          workspace_org_view(emit, model),
        ],
      ],
    ]
  }
  if model.workspace.tab == "resources" {
    return div(
      class="desktop-sheet-backdrop",
      attrs=@html.Attrs::build().data_set("desktop-sheet", "resources"),
    ) <| [
      button(
        type_="button",
        class="desktop-sheet-scrim",
        attrs=@html.Attrs::build().aria_label("关闭资源清单面板"),
        on_click=emit(WorkspaceAction(CloseSheet)),
        "",
      ),
      section(
        class="desktop-sheet",
        attrs=@html.Attrs::build()
          .role("dialog")
          .aria_label("公司资源清单"),
      ) <| [
        header(class="desktop-sheet-bar") <| [
          div(class="desktop-sheet-bar-title") <| [
            small("桌面浮层 · 不离开当前工作全景"),
            h2("资源清单"),
          ],
          button(
            type_="button",
            class="workspace-quiet-button desktop-sheet-close",
            on_click=emit(WorkspaceAction(CloseSheet)),
            "× 返回桌面",
          ),
        ],
        div(class="desktop-sheet-body") <| [
          workspace_resources_view(emit, model),
        ],
      ],
    ]
  }
  workspace_agent_sheet_view(emit, model)
}

///|
fn workspace_flow_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.page != Workspace {
    return @html.nothing
  }
  let has_app = workspace_has_open_app(model.workspace)
  let sheet_open = model.workspace.tab == "org" ||
    model.workspace.tab == "resources" ||
    !model.workspace.focused_agent.is_empty()
  let state = model.today
  let all_jobs = workspace_jobs(model)
  let all_goals = state.tasks.filter(t => objective_is_node(state, t))
  let selected_stage = match model.charter.charter {
    Some(charter) => charter_find_stage(charter, model.workspace.selected_stage)
    None => None
  }
  let spotlight_task_id = match selected_stage {
    Some(stage) => stage.milestone_task_id
    None => ""
  }
  let (goals, jobs, stage_filter_note) = match selected_stage {
    Some(stage) if !stage.milestone_task_id.is_empty() => {
      let matched_jobs = all_jobs.filter(j => {
        j.id == stage.milestone_task_id ||
        workspace_parent(model, j) == stage.milestone_task_id
      })
      // Keep the parent goal connected so SVG contribution wires stay intact
      // when a stage points to a regular task rather than directly to a goal.
      let matched_goals = all_goals.filter(g => {
        g.id == stage.milestone_task_id ||
        matched_jobs.any(j => workspace_parent(model, j) == g.id)
      })
      if !matched_goals.is_empty() || !matched_jobs.is_empty() {
        (matched_goals, matched_jobs, "")
      } else {
        (
          all_goals,
          all_jobs,
          "阶段“" +
          stage.title +
          "”尚未关联具体目标，下方显示全部工作。",
        )
      }
    }
    Some(stage) =>
      (
        all_goals,
        all_jobs,
        "阶段“" +
        stage.title +
        "”尚未绑定单一目标，下方显示全部工作。",
      )
    None => (all_goals, all_jobs, "")
  }
  let has_charter_hero = model.charter.charter is Some(_)
  div(
    class=if sheet_open { "company-flow is-dimmed" } else { "company-flow" },
    hidden=has_app,
    attrs=@html.Attrs::build().data_set("workspace-surface", "focus"),
  ) <| [
    workspace_mission_spine_view(emit, model),
    workspace_founder_focus_view(emit, model),
    div(class="flow-heading") <| [
      div <| [
        if has_charter_hero {
          h2("工作如何汇成交付")
        } else {
          div <| [
            small("公司工作空间"),
            h1("工作如何汇成交付"),
          ]
        },
      ],
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=model.today.project_state != "ready" ||
          model.today.project_id.is_empty(),
        on_click=emit(TodayAction(NewObjective)),
        "定义目标",
      ),
    ],
    if !stage_filter_note.is_empty() {
      p(class="workspace-refresh-status", stage_filter_note)
    } else {
      @html.nothing
    },
    if ["idle", "loading"].contains(state.project_state) ||
      (state.work_state == "loading" && jobs.is_empty()) {
      p(
        class="workspace-message",
        attrs=@html.Attrs::build().role("status"),
        "正在读取工作关系…",
      )
    } else if !["ready", "empty"].contains(state.project_state) {
      div(class="workspace-message") <| [
        p("公司项目尚未载入。"),
        secondary_button(emit, TodayAction(Refresh), "重试读取项目"),
        secondary_button(emit, OpenCompanyForm, "设置公司"),
      ]
    } else if state.project_id.is_empty() {
      p(
        class="workspace-message",
        "选择一个项目，查看它的工作与交付。",
      )
    } else if !["ready", "empty"].contains(state.work_state) && jobs.is_empty() {
      div(class="workspace-message", attrs=@html.Attrs::build().role("alert")) <| [
        p("工作关系未能读回，不能推断工作已经结束。"),
        secondary_button(emit, TodayAction(RefreshTasks), "重试读取工作"),
      ]
    } else if goals.is_empty() && jobs.is_empty() {
      p(
        class="workspace-message",
        "这里还没有工作。先定义一个要交付的结果。",
      )
    } else {
      div <| [
        if state.work_state != "ready" && state.work_state != "empty" {
          p(
            class="workspace-refresh-status",
            attrs=@html.Attrs::build().role("status"),
            if state.work_state == "loading" {
              "正在刷新状态…"
            } else {
              "状态未能刷新；下方保留上次读回的记录。"
            },
          )
        } else {
          @html.nothing
        },
        div(class="flow-board") <| [
          div(
            class="flow-wires",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
          ..goals.map(goal => {
            workspace_goal_group(
              emit,
              model,
              goal,
              jobs.filter(t => workspace_parent(model, t) == goal.id),
              spotlight_task_id~,
            )
          }),
          if jobs.any(t => !goals.any(g => g.id == workspace_parent(model, t))) {
            section(class="flow-independent") <| [
              h2("其他工作"),
              ..jobs
              .filter(t => !goals.any(g => g.id == workspace_parent(model, t)))
              .map(job => workspace_job_card(emit, model, job)),
            ]
          } else {
            @html.nothing
          },
        ],
      ]
    },
    if !goals.is_empty() && !jobs.is_empty() {
      div(class="flow-key") <| [
        span(
          "连线表示贡献归属 · 任务顺序不代表执行依赖 · 确认交付时触发光点传递",
        ),
      ]
    } else {
      @html.nothing
    },
  ]
}

///|
fn workspace_dock_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.page != Workspace {
    return @html.nothing
  }
  let agents = workspace_standing_agents(model)
  let home_active = !workspace_has_open_app(model.workspace) &&
    model.workspace.tab == "focus" &&
    model.workspace.focused_agent.is_empty()
  nav(
    class="job-dock",
    attrs=@html.Attrs::build().aria_label("工作应用 Dock"),
  ) <| [
    button(
      type_="button",
      class="dock-job dock-home",
      attrs=@html.Attrs::build()
        .aria_pressed(if home_active { "true" } else { "false" })
        .aria_label("工作全景")
        .title("返回公司桌面与项目流"),
      on_click=emit(WorkspaceAction(Flow)),
    ) <| [
      span(
        class="dock-job-icon",
        attrs=@html.Attrs::build().aria_hidden("true"),
      ) <| [
        span(class="opc-glyph glyph-overview", ""),
      ],
      span(class="dock-job-name", "桌面"),
    ],
    ..workspace_jobs(model).map(job => {
      let stage = workspace_stage(workspace_record(model, job), job)
      button(
        type_="button",
        class="dock-job",
        attrs=@html.Attrs::build()
          .data_set("dock-job", job.id)
          .data_set("stage", stage)
          .aria_pressed(
            if model.workspace.job == job.id {
              "true"
            } else {
              "false"
            },
          )
          .aria_label(job.title + " · " + workspace_stage_label(stage))
          .title(job.title + " · " + workspace_stage_label(stage)),
        on_click=emit(WorkspaceAction(Focus(job.id))),
      ) <| [
        span(
          class="dock-job-icon",
          attrs=@html.Attrs::build().aria_hidden("true"),
        ) <| [
          span(class="opc-glyph glyph-tasks", ""),
          span(class="dock-status-dot", ""),
        ],
        span(class="dock-job-name", workspace_job_name(job.title)),
      ]
    }),
    if !agents.is_empty() {
      span(
        class="dock-divider",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      )
    } else {
      @html.nothing
    },
    ..agents.map(role => {
      let short_name = workspace_agent_short_name(role.name)
      let active = model.workspace.focused_agent == role.id
      button(
        type_="button",
        class="dock-job dock-agent",
        attrs=@html.Attrs::build()
          .data_set("dock-agent", role.id)
          .data_set("tier", role.tier.to_string())
          .data_set("status", role.status)
          .aria_pressed(if active { "true" } else { "false" })
          .aria_label("AI 角色：" + role.name)
          .title(role.name + " · " + charter_role_status_label(role.status)),
        on_click=emit(WorkspaceAction(InspectAgent(role.id))),
      ) <| [
        span(
          class="dock-job-icon dock-agent-icon",
          attrs=@html.Attrs::build().aria_hidden("true"),
        ) <| [
          span(class="opc-glyph glyph-agents", ""),
          span(class="dock-tier-badge", "T" + role.tier.to_string()),
          span(class="dock-status-dot dock-agent-dot", ""),
        ],
        span(class="dock-job-name", short_name),
      ]
    }),
  ]
}

///|
fn workspace_header_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  header(class="workspace-bar") <| [
    div(class="workspace-brand") <| [
      @html.img(src="./moonproj.svg", alt="", width=24, height=24),
      strong("MoonProj"),
    ],
    if model.today.projects.length() > 1 {
      @html.select(
        attrs=@html.Attrs::build().aria_label("公司项目"),
        on_change=emit.map(id => TodayAction(ChooseProject(id))),
      ) <| model.today.projects.map(project => {
        @html.option(
          value=project.id,
          selected=model.today.project_id == project.id,
          project.name,
        )
      })
    } else {
      span(
        class="workspace-project",
        model.today.projects.get(0).map(p => p.name).unwrap_or("工作空间"),
      )
    },
    nav(
      class="workspace-tabs",
      attrs=@html.Attrs::build()
        .aria_label("工作空间视图")
        .data_set("workspace-tabs", ""),
    ) <| [
      span(
        class="workspace-tabs-indicator",
        attrs=@html.Attrs::build()
          .aria_hidden("true")
          .data_set("workspace-tabs-indicator", ""),
        "",
      ),
      button(
        type_="button",
        class="workspace-quiet-button workspace-tab",
        attrs=@html.Attrs::build()
          .data_set("workspace-tab", "focus")
          .aria_pressed(
            if model.workspace.tab == "focus" {
              "true"
            } else {
              "false"
            },
          ),
        on_click=emit(WorkspaceAction(Tab("focus"))),
      ) <| [
        span(
          class="opc-glyph glyph-overview",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        span("使命与聚焦"),
      ],
      button(
        type_="button",
        class="workspace-quiet-button workspace-tab",
        attrs=@html.Attrs::build()
          .data_set("workspace-tab", "org")
          .aria_pressed(
            if model.workspace.tab == "org" {
              "true"
            } else {
              "false"
            },
          ),
        on_click=emit(WorkspaceAction(Tab("org"))),
      ) <| [
        span(
          class="opc-glyph glyph-agents",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        span("组织与权力"),
      ],
      button(
        type_="button",
        class="workspace-quiet-button workspace-tab",
        attrs=@html.Attrs::build()
          .data_set("workspace-tab", "resources")
          .aria_pressed(
            if model.workspace.tab == "resources" {
              "true"
            } else {
              "false"
            },
          ),
        on_click=emit(WorkspaceAction(Tab("resources"))),
      ) <| [
        span(
          class="opc-glyph glyph-projects",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        span("资源清单"),
      ],
    ],
    div(class="workspace-bar-actions") <| [
      button(
        type_="button",
        class="workspace-quiet-button",
        disabled=model.today.project_state == "loading" ||
          model.today.work_state == "loading",
        attrs=@html.Attrs::build().aria_label("刷新工作状态"),
        on_click=emit(WorkspaceAction(Refresh)),
        "刷新",
      ),
      button(
        type_="button",
        class="workspace-quiet-button workspace-motion-toggle",
        attrs=@html.Attrs::build()
          .aria_label("暂停动态效果")
          .aria_pressed("false")
          .data_set("workspace-motion-toggle", ""),
        "动画",
      ),
      details(class="workspace-tools") <| [
        summary("工具"),
        div <| [
          secondary_button(emit, Navigate(Overview), "今日待办"),
          secondary_button(emit, Navigate(Objectives), "目标与任务"),
          secondary_button(emit, Navigate(Fleet), "Agent 编队"),
          secondary_button(emit, Navigate(Company), "公司"),
          secondary_button(emit, Navigate(Guide), "使用指南"),
        ],
      ],
    ],
  ]
}

///|
fn workspace_app_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let job = workspace_current_job(model)
  let resource_mode = model.workspace.job.is_empty() &&
    !model.workspace.resource_url.is_empty()
  let has_app = workspace_has_open_app(model.workspace)
  let source = if resource_mode {
    model.workspace.resource_url
  } else {
    job.map(t => workspace_source(model, t)).unwrap_or("")
  }
  let app_id = if resource_mode {
    "resource:" + model.workspace.resource_url
  } else {
    model.workspace.job
  }
  let app_title = if resource_mode {
    model.workspace.resource_title
  } else {
    job.map(t => t.title).unwrap_or("正在打开工作…")
  }
  div(
    class="job-app-window",
    hidden=!has_app,
    attrs=@html.Attrs::build().data_set("active-job", app_id),
  ) <| [
    header(class="job-app-titlebar") <| [
      button(
        type_="button",
        class="workspace-quiet-button",
        attrs=@html.Attrs::build().title(
          "返回全景；不会停止工作或关闭编辑器",
        ),
        on_click=emit(WorkspaceAction(Flow)),
        if resource_mode {
          "返回资源清单"
        } else {
          "返回全景"
        },
      ),
      h1(app_title),
      if resource_mode {
        @html.nothing
      } else {
        job
        .map(t => {
          workspace_status(workspace_stage(workspace_record(model, t), t))
        })
        .unwrap_or(@html.nothing)
      },
    ],
    nav(
      class="job-app-panes",
      attrs=@html.Attrs::build().aria_label("当前工作的应用视图"),
    ) <| [
      button(
        type_="button",
        attrs=@html.Attrs::build().aria_pressed(
          if resource_mode || model.workspace.pane == "materials" {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(WorkspaceAction(Pane("materials"))),
        "MoonDesk · 工作材料",
      ),
      if resource_mode {
        @html.nothing
      } else {
        button(
          type_="button",
          attrs=@html.Attrs::build().aria_pressed(
            if model.workspace.pane == "progress" {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(WorkspaceAction(Pane("progress"))),
          "团队与交付",
        )
      },
      if !source.is_empty() {
        a(
          href=source,
          target=Blank,
          attrs=@html.Attrs::build()
            .rel("noopener noreferrer")
            .data_set("workspace-source-link", ""),
          "独立打开",
        )
      } else {
        @html.nothing
      },
    ],
    // This host remains in the root view even when changing routes. Its runtime
    // keeps each lazily opened app mounted, preserving unsaved edits.
    div(
      class="job-app-host",
      hidden=!resource_mode && model.workspace.pane != "materials",
      attrs=@html.Attrs::build()
        .data_set("job-app-host", "")
        .data_set("job", app_id)
        .data_set("source", source)
        .data_set("title", app_title)
        .data_set(
          "read-state",
          if resource_mode || job is Some(_) {
            "ready"
          } else if ["idle", "loading"].contains(model.today.project_state) ||
            ["idle", "loading"].contains(model.today.work_state) {
            "loading"
          } else {
            "unavailable"
          },
        )
        .data_set(
          "visible",
          if model.page == Workspace &&
            has_app &&
            (resource_mode || model.workspace.pane == "materials") {
            "true"
          } else {
            "false"
          },
        ),
      "",
    ),
    section(
      class="job-progress-pane",
      hidden=resource_mode || model.workspace.pane != "progress",
    ) <| [
      if model.dispatch_task_id == model.workspace.job {
        dispatch_durable_task_card(emit, model)
      } else {
        p("正在读取这项工作的真实进展…")
      },
    ],
  ]
}

///|
fn workspace_shell_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(
    class="company-workspace",
    hidden=model.page != Workspace,
    attrs=@html.Attrs::build()
      .data_set("company-workspace", "")
      .data_set("actor", model.dispatch_task_actor_id)
      .data_set("project", model.today.project_id)
      .data_set(
        "active",
        if model.page == Workspace {
          "true"
        } else {
          "false"
        },
      ),
  ) <| [
    workspace_header_view(emit, model),
    main_(
      class="workspace-main",
      attrs=@html.Attrs::build()
        .id(
          if model.page == Workspace {
            "main-content"
          } else {
            "workspace-main-content"
          },
        )
        .tabindex(-1),
    ) <| [
      notice_view(emit, model.notice),
      workspace_flow_view(emit, model),
      workspace_overlay_sheet_view(emit, model),
      workspace_app_view(emit, model),
    ],
    workspace_dock_view(emit, model),
  ]
}
