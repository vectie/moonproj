///|
fn workspace_status(stage : String) -> @html.Html {
  span(class="job-status", attrs=@html.Attrs::build().data_set("stage", stage)) <| [
    span(class="job-status-mark", attrs=@html.Attrs::build().aria_hidden("true"), ""),
    span(workspace_stage_label(stage)),
  ]
}

///|
fn workspace_job_card(emit : @rabbita.Emit[Msg], model : Model, job : TodayTask) -> @html.Html {
  let parent = workspace_parent(model, job)
  let stage = workspace_stage(workspace_record(model, job), job)
  button(
    type_="button", class="flow-job",
    attrs=@html.Attrs::build()
      .data_set("job-id", job.id)
      .data_set("parent", parent)
      .data_set("stage", stage)
      .data_set("receipt", workspace_receipt(model, job))
      .aria_label(job.title + " · " + workspace_stage_label(stage))
      .title(job.title),
    on_click=emit(WorkspaceAction(Focus(job.id))),
  ) <| [
    span(class="flow-job-icon", attrs=@html.Attrs::build().aria_hidden("true")) <| [span(class="opc-glyph glyph-tasks", "")],
    div(class="flow-job-copy") <| [
      h3(job.title),
      workspace_status(stage),
      if !job.execution_error.is_empty() && stage == "failed" { p(class="flow-job-error", job.execution_error) } else { @html.nothing },
    ],
    span(class="job-open-mark", attrs=@html.Attrs::build().aria_hidden("true"), "↗"),
  ]
}

///|
fn workspace_goal_group(emit : @rabbita.Emit[Msg], model : Model, goal : TodayTask, jobs : Array[TodayTask]) -> @html.Html {
  let record = objective_metadata(model.today, goal.id)
  let accepted = products_field(record, "objective_result") is Object(_) && goal.status == "done"
  section(class="flow-group", attrs=@html.Attrs::build().aria_label(goal.title)) <| [
    article(class="flow-goal", attrs=@html.Attrs::build().data_set("goal-id", goal.id)) <| [
      small("共同交付"),
      h2(goal.title),
      p(class="goal-state", if accepted { "已采纳交付" } else { "等待可验收的成果" }),
      details(class="flow-goal-details") <| [summary("交付要求"), p(products_text(record, "remarks"))],
      button(type_="button", class="button button-secondary button-small", on_click=emit(WorkspaceAction(ManageGoal(goal.id))), "管理目标"),
    ],
    div(class="flow-jobs", attrs=@html.Attrs::build().aria_label("为此目标工作的任务")) <| (if jobs.is_empty() {
      [p("尚未安排工作。"), primary_button(emit, TodayAction(DelegateObjective(goal.id)), "安排工作")]
    } else { jobs.map(job => workspace_job_card(emit, model, job)) }),
  ]
}

///|
fn workspace_flow_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.page != Workspace { return @html.nothing }
  let state = model.today
  let jobs = workspace_jobs(model)
  let goals = state.tasks.filter(t => objective_is_node(state, t))
  div(class="company-flow", hidden=!model.workspace.job.is_empty()) <| [
    div(class="flow-heading") <| [
      div <| [small("公司工作空间"), h1("工作如何汇成交付")],
      button(type_="button", class="button button-secondary", disabled=model.today.project_state != "ready" || model.today.project_id.is_empty(), on_click=emit(TodayAction(NewObjective)), "定义目标"),
    ],
    if ["idle", "loading"].contains(state.project_state) || (state.work_state == "loading" && jobs.is_empty()) {
      p(class="workspace-message", attrs=@html.Attrs::build().role("status"), "正在读取工作关系…")
    } else if !["ready", "empty"].contains(state.project_state) {
      div(class="workspace-message") <| [p("公司项目尚未载入。"), secondary_button(emit, TodayAction(Refresh), "重试读取项目"), secondary_button(emit, OpenCompanyForm, "设置公司")]
    } else if state.project_id.is_empty() {
      p(class="workspace-message", "选择一个项目，查看它的工作与交付。")
    } else if !["ready", "empty"].contains(state.work_state) && jobs.is_empty() {
      div(class="workspace-message", attrs=@html.Attrs::build().role("alert")) <| [p("工作关系未能读回，不能推断工作已经结束。"), secondary_button(emit, TodayAction(RefreshTasks), "重试读取工作")]
    } else if goals.is_empty() && jobs.is_empty() {
      p(class="workspace-message", "这里还没有工作。先定义一个要交付的结果。")
    } else {
      div <| [
      if state.work_state != "ready" && state.work_state != "empty" {
        p(class="workspace-refresh-status", attrs=@html.Attrs::build().role("status"), if state.work_state == "loading" { "正在刷新状态…" } else { "状态未能刷新；下方保留上次读回的记录。" })
      } else { @html.nothing },
      div(class="flow-board") <| [
        div(class="flow-wires", attrs=@html.Attrs::build().aria_hidden("true"), ""),
        ..goals.map(goal => workspace_goal_group(emit, model, goal, jobs.filter(t => workspace_parent(model, t) == goal.id))),
        if jobs.any(t => !goals.any(g => g.id == workspace_parent(model, t))) {
          section(class="flow-independent") <| [
            h2("其他工作"),
            ..jobs.filter(t => !goals.any(g => g.id == workspace_parent(model, t))).map(job => workspace_job_card(emit, model, job)),
          ]
        } else { @html.nothing },
      ],
      ]
    },
    if !goals.is_empty() && !jobs.is_empty() {
      div(class="flow-key") <| [span("连线：工作贡献给哪个目标"), span("任务顺序不代表执行依赖"), span("只有确认交付进入目标时，连线上才会传递光点。")]
    } else { @html.nothing },
  ]
}

///|
fn workspace_dock_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.page != Workspace { return @html.nothing }
  nav(class="job-dock", attrs=@html.Attrs::build().aria_label("工作应用 Dock")) <| [
    button(type_="button", class="dock-job dock-home", attrs=@html.Attrs::build().aria_pressed(if model.workspace.job.is_empty() { "true" } else { "false" }).aria_label("工作全景"), on_click=emit(WorkspaceAction(Flow))) <| [
      span(class="dock-job-icon", attrs=@html.Attrs::build().aria_hidden("true")) <| [span(class="opc-glyph glyph-overview", "")],
      span(class="dock-job-name", "全景"),
    ],
    ..workspace_jobs(model).map(job => {
      let stage = workspace_stage(workspace_record(model, job), job)
      button(type_="button", class="dock-job", attrs=@html.Attrs::build()
        .data_set("dock-job", job.id).data_set("stage", stage)
        .aria_pressed(if model.workspace.job == job.id { "true" } else { "false" })
        .aria_label(job.title + " · " + workspace_stage_label(stage))
        .title(job.title + " · " + workspace_stage_label(stage)),
        on_click=emit(WorkspaceAction(Focus(job.id))),
      ) <| [
        span(class="dock-job-icon", attrs=@html.Attrs::build().aria_hidden("true")) <| [span(class="opc-glyph glyph-tasks", ""), span(class="dock-status-dot", "")],
        span(class="dock-job-name", workspace_job_name(job.title)),
      ]
    }),
  ]
}

///|
fn workspace_header_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  header(class="workspace-bar") <| [
    div(class="workspace-brand") <| [@html.img(src="./moonproj.svg", alt="", width=24, height=24), strong("MoonProj")],
    if model.today.projects.length() > 1 {
      @html.select(attrs=@html.Attrs::build().aria_label("公司项目"), on_change=emit.map(id => TodayAction(ChooseProject(id)))) <| model.today.projects.map(project => {
        @html.option(value=project.id, selected=model.today.project_id == project.id, project.name)
      })
    } else {
      span(class="workspace-project", model.today.projects.get(0).map(p => p.name).unwrap_or("工作空间"))
    },
    div(class="workspace-bar-actions") <| [
      button(type_="button", class="workspace-quiet-button", disabled=model.today.project_state == "loading" || model.today.work_state == "loading", attrs=@html.Attrs::build().aria_label("刷新工作状态"), on_click=emit(WorkspaceAction(Refresh)), "刷新"),
      button(type_="button", class="workspace-quiet-button workspace-motion-toggle", attrs=@html.Attrs::build().aria_label("暂停动态效果").aria_pressed("false").data_set("workspace-motion-toggle", ""), "动画"),
      details(class="workspace-tools") <| [
        summary("工具"),
        div <| [secondary_button(emit, Navigate(Overview), "今日待办"), secondary_button(emit, Navigate(Objectives), "目标与任务"), secondary_button(emit, Navigate(Fleet), "Agent 编队"), secondary_button(emit, Navigate(Company), "公司"), secondary_button(emit, Navigate(Guide), "使用指南")],
      ],
    ],
  ]
}

///|
fn workspace_app_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let job = workspace_current_job(model)
  let source = job.map(t => workspace_source(model, t)).unwrap_or("")
  div(class="job-app-window", hidden=model.workspace.job.is_empty(), attrs=@html.Attrs::build().data_set("active-job", model.workspace.job)) <| [
    header(class="job-app-titlebar") <| [
      button(type_="button", class="workspace-quiet-button", attrs=@html.Attrs::build().title("返回全景；不会停止工作或关闭编辑器"), on_click=emit(WorkspaceAction(Flow)), "返回全景"),
      h1(job.map(t => t.title).unwrap_or("正在打开工作…")),
      job.map(t => workspace_status(workspace_stage(workspace_record(model, t), t))).unwrap_or(@html.nothing),
    ],
    nav(class="job-app-panes", attrs=@html.Attrs::build().aria_label("当前工作的应用视图")) <| [
      button(type_="button", attrs=@html.Attrs::build().aria_pressed(if model.workspace.pane == "materials" { "true" } else { "false" }), on_click=emit(WorkspaceAction(Pane("materials"))), "MoonDesk · 工作材料"),
      button(type_="button", attrs=@html.Attrs::build().aria_pressed(if model.workspace.pane == "progress" { "true" } else { "false" }), on_click=emit(WorkspaceAction(Pane("progress"))), "团队与交付"),
      if !source.is_empty() { a(href=source, target=Blank, attrs=@html.Attrs::build().rel("noopener noreferrer").data_set("workspace-source-link", ""), "独立打开") } else { @html.nothing },
    ],
    // This host remains in the root view even when changing routes. Its runtime
    // keeps each lazily opened app mounted, preserving unsaved edits.
    div(class="job-app-host", hidden=model.workspace.pane != "materials", attrs=@html.Attrs::build()
      .data_set("job-app-host", "")
      .data_set("job", model.workspace.job)
      .data_set("source", source)
      .data_set("title", job.map(t => t.title).unwrap_or("工作材料"))
      .data_set("read-state", if job is Some(_) { "ready" } else if ["idle", "loading"].contains(model.today.project_state) || ["idle", "loading"].contains(model.today.work_state) { "loading" } else { "unavailable" })
      .data_set("visible", if model.page == Workspace && !model.workspace.job.is_empty() && model.workspace.pane == "materials" { "true" } else { "false" }),
      "",
    ),
    section(class="job-progress-pane", hidden=model.workspace.pane != "progress") <| [
      if model.dispatch_task_id == model.workspace.job {
        dispatch_durable_task_card(emit, model)
      } else { p("正在读取这项工作的真实进展…") },
    ],
  ]
}

///|
fn workspace_shell_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="company-workspace", hidden=model.page != Workspace, attrs=@html.Attrs::build()
    .data_set("company-workspace", "")
    .data_set("actor", model.dispatch_task_actor_id)
    .data_set("project", model.today.project_id)
    .data_set("active", if model.page == Workspace { "true" } else { "false" }),
  ) <| [
    workspace_header_view(emit, model),
    main_(class="workspace-main", attrs=@html.Attrs::build().id(if model.page == Workspace { "main-content" } else { "workspace-main-content" }).tabindex(-1)) <| [
      notice_view(emit, model.notice),
      workspace_flow_view(emit, model),
      workspace_app_view(emit, model),
    ],
    workspace_dock_view(emit, model),
  ]
}
