///|
// Presentation state only. Company tasks and native executions remain the
// canonical work records; an app in this dock is not another agent or job.
struct CompanyWorkspace {
  job : String
  pane : String
  tab : String
  selected_stage : String
  resource_title : String
  resource_url : String
  focused_agent : String
}

///|
enum WorkspaceMsg {
  Focus(String)
  FocusPane(String, String)
  OpenResource(String, String)
  InspectAgent(String)
  CloseSheet
  Flow
  Pane(String)
  Tab(String)
  SelectStage(String)
  ManageGoal(String)
  Refresh
  Tick(String, Int, String, Int)
}

///|
fn workspace_initial() -> CompanyWorkspace {
  {
    job: "",
    pane: "materials",
    tab: "focus",
    selected_stage: "",
    resource_title: "",
    resource_url: "",
    focused_agent: "",
  }
}

///|
fn workspace_has_open_app(ws : CompanyWorkspace) -> Bool {
  !ws.job.is_empty() || !ws.resource_url.is_empty()
}

///|
fn workspace_jobs(model : Model) -> Array[TodayTask] {
  let state = model.today
  if state.actor.is_empty() || state.actor != model.dispatch_task_actor_id ||
    state.scope != "project" ||
    (state.work_state != "ready" && (state.tasks.is_empty() || state.observed_at.is_empty())) {
    return []
  }
  let jobs = state.tasks.filter(t => t.project_id == state.project_id && !objective_is_node(state, t))
  jobs.sort_by((a, b) => {
    let order_a = workspace_order(objective_metadata(state, a.id))
    let order_b = workspace_order(objective_metadata(state, b.id))
    if order_a != order_b { order_a - order_b } else { a.title.compare(b.title) }
  })
  jobs
}

///|
fn workspace_order(task : Json) -> Int {
  match products_field(task, "sortOrder") {
    Number(n, ..) => n.to_int()
    _ => 0
  }
}

///|
fn workspace_record(model : Model, task : TodayTask) -> Json {
  let listed = objective_metadata(model.today, task.id)
  if model.dispatch_task_id == task.id &&
    model.dispatch_task_actor_id == model.today.actor &&
    model.dispatch_task_project_id == task.project_id &&
    model.dispatch_offer_task is Object(_) &&
    dispatch_offer_revision(model.dispatch_offer_task) >= dispatch_offer_revision(listed) {
    model.dispatch_offer_task
  } else {
    listed
  }
}

///|
fn workspace_stage(record : Json, task : TodayTask) -> String {
  let execution = products_field(record, "execution")
  let control = products_text(execution, "control_state")
  if control == "stopped" { return "stopped" }
  if control == "stopping" { return "stopping" }
  if ["resuming", "revising"].contains(control) { return control }
  if !products_text(record, "accepted_report_id").is_empty() { return "accepted" }
  // A selected continuation supersedes the original outcome.
  let selected = products_field(record, "selected_delivery_source")
  let run = if products_text(selected, "type") == "continuation" {
    dispatch_continuation_array(record, "continuations").filter(r => products_text(r, "command_id") == products_text(selected, "command_id")).get(0).unwrap_or(Json::null())
  } else { execution }
  let state = products_text(run, "state")
  if products_text(selected, "type") == "continuation" && state.is_empty() { return "unknown" }
  match state {
    "queued" | "running" | "waiting_approval" | "failed" | "unknown" | "runtime_unavailable" => state
    "completed" => "review"
    "cancelled" | "interrupted" => "stopped"
    _ => match task.status { "done" => "ended"; "pending" => "pending"; "cancelled" => "stopped"; _ => "unknown" }
  }
}

///|
fn workspace_stage_label(stage : String) -> String {
  match stage {
    "pending" => "未开始"
    "queued" => "排队中"
    "resuming" => "正在继续"
    "revising" => "正在修改"
    "running" => "执行中"
    "waiting_approval" => "需要你确认"
    "review" => "执行结束 · 待核对交付"
    "accepted" => "已验收"
    "ended" => "记录已结束"
    "stopping" => "停止待确认"
    "stopped" => "已停止"
    "failed" => "遇到问题"
    _ => "状态待核实"
  }
}

///|
fn workspace_parent(model : Model, task : TodayTask) -> String {
  products_text(objective_metadata(model.today, task.id), "parentTaskGuid")
}

///|
fn workspace_receipt(model : Model, task : TodayTask) -> String {
  let parent = objective_metadata(model.today, workspace_parent(model, task))
  let result = products_field(parent, "objective_result")
  if products_text(result, "task_id") == task.id {
    products_text(result, "report_id")
  } else { "" }
}

///|
fn workspace_job_name(title : String) -> String {
  title.split("：").next().unwrap_or(title[:]).to_owned()
}

///|
fn workspace_current_job(model : Model) -> TodayTask? {
  workspace_jobs(model).filter(t => t.id == model.workspace.job).get(0)
}

///|
fn workspace_source(model : Model, task : TodayTask) -> String {
  products_text(products_field(workspace_record(model, task), "source_context"), "reference")
}

///|
fn workspace_update(emit : @rabbita.Emit[Msg], model : Model, action : WorkspaceMsg) -> (Cmd, Model) {
  match action {
    Tick(actor, epoch, project, request) => {
      if model.page != Workspace || model.today.actor != actor || model.dispatch_task_actor_id != actor ||
        model.today.epoch != epoch || model.today.project_id != project || model.today.work_request != request || model.today.work_state != "ready" {
        return (none, model)
      }
      workspace_update(emit, model, Refresh)
    }
    Refresh => {
      let (charter_cmd, refreshed) = if model.charter.status != "loading" {
        charter_update(emit, Load, model)
      } else {
        (none, model)
      }
      let state = refreshed.today
      if state.actor.is_empty() || state.actor != refreshed.dispatch_task_actor_id || state.project_state != "ready" || state.project_id.is_empty() {
        let (today_cmd, next_model) = today_update(emit, TodayMsg::Refresh, refreshed)
        return (@cmd.batch([today_cmd, charter_cmd]), next_model)
      }
      if state.work_state == "loading" { return (charter_cmd, refreshed) }
      let state = { ..state, work_request: state.work_request + 1, work_state: "loading", }
      // Active selected runs already have the native task reader's polling
      // chain. Refresh a dormant selection too, without forking that chain.
      let selected = if !refreshed.dispatch_task_id.is_empty() && !delivery_pollable(refreshed) {
        emit(RefreshDispatchTask(refreshed.dispatch_task_id, refreshed.dispatch_task_selection))
      } else { none }
      (@cmd.batch([today_load_tasks(emit, state), selected, charter_cmd]), { ..refreshed, today: state, })
    }
    Focus(id) => {
      if !workspace_jobs(model).any(t => t.id == id) { return (none, model) }
      let next = {
        ..model,
        workspace: {
          ..model.workspace,
          job: id,
          pane: "materials",
          resource_title: "",
          resource_url: "",
          focused_agent: "",
        },
      }
      if model.dispatch_task_id == id && model.dispatch_task_stage != "loading" {
        return (remember_page_route(Workspace, id, push=true), { ..next, page: Workspace, })
      }
      open_dispatch_task(emit, { ..next, dispatch_task_open_id: id, }, page=Workspace)
    }
    FocusPane(id, pane) => {
      if !workspace_jobs(model).any(t => t.id == id) { return (none, model) }
      let target_pane = if pane == "progress" { "progress" } else { "materials" }
      let next = {
        ..model,
        workspace: {
          ..model.workspace,
          job: id,
          pane: target_pane,
          resource_title: "",
          resource_url: "",
          focused_agent: "",
        },
      }
      if model.dispatch_task_id == id && model.dispatch_task_stage != "loading" {
        return (remember_page_route(Workspace, id, push=true), { ..next, page: Workspace, })
      }
      open_dispatch_task(emit, { ..next, dispatch_task_open_id: id, }, page=Workspace)
    }
    OpenResource(title, url) => {
      let clean_url = url.trim().to_string()
      if clean_url.is_empty() { return (none, model) }
      (
        none,
        {
          ..model,
          page: Workspace,
          workspace: {
            ..model.workspace,
            job: "",
            pane: "materials",
            resource_title: if title.is_empty() { "MoonDesk 资源" } else { title },
            resource_url: clean_url,
            focused_agent: "",
          },
        },
      )
    }
    InspectAgent(role_id) => {
      let next_agent = if model.workspace.focused_agent == role_id { "" } else { role_id }
      (
        none,
        {
          ..model,
          page: Workspace,
          workspace: {
            ..model.workspace,
            job: "",
            tab: "focus",
            resource_title: "",
            resource_url: "",
            focused_agent: next_agent,
          },
        },
      )
    }
    CloseSheet => (
      none,
      {
        ..model,
        workspace: { ..model.workspace, tab: "focus", focused_agent: "", },
      },
    )
    Flow => (
      remember_page_route(Workspace, "", push=true),
      {
        ..model,
        page: Workspace,
        workspace: {
          ..model.workspace,
          job: "",
          tab: "focus",
          resource_title: "",
          resource_url: "",
          focused_agent: "",
        },
      },
    )
    Pane(pane) => if ["materials", "progress"].contains(pane) {
      (none, { ..model, workspace: { ..model.workspace, pane, }, })
    } else { (none, model) }
    Tab(tab) => if ["focus", "org", "resources"].contains(tab) {
      let next = {
        ..model,
        workspace: {
          ..model.workspace,
          tab,
          job: "",
          resource_title: "",
          resource_url: "",
          focused_agent: "",
        },
      }
      if next.charter.status == "idle" {
        charter_update(emit, Load, next)
      } else {
        (none, next)
      }
    } else { (none, model) }
    SelectStage(stage_id) => {
      let next_stage = if model.workspace.selected_stage == stage_id { "" } else { stage_id }
      (none, { ..model, workspace: { ..model.workspace, selected_stage: next_stage, }, })
    }
    ManageGoal(id) => {
      if !model.today.tasks.any(t => t.id == id && objective_is_node(model.today, t)) { return (none, model) }
      open_dispatch_task(emit, { ..model, dispatch_task_open_id: id, }, page=Objectives)
    }
  }
}

///|
fn workspace_observe(emit : @rabbita.Emit[Msg], previous : Model, model : Model, msg : Msg, command : Cmd) -> Cmd {
  if model.page != Workspace { return command }
  let observed = match msg {
    TodayAction(TasksRead(_, _, _, _, _, _, _)) => previous.today.work_state == "loading" && model.today.work_state == "ready"
    DispatchTaskLoaded(_, _, _) => previous.dispatch_run != model.dispatch_run
    _ => false
  }
  if !observed || !workspace_jobs(model).any(job => {
    ["queued", "running", "waiting_approval", "resuming", "revising", "unknown", "runtime_unavailable"].contains(workspace_stage(workspace_record(model, job), job))
  }) { return command }
  @cmd.batch([command, @cmd.delay(emit(WorkspaceAction(Tick(model.today.actor, model.today.epoch, model.today.project_id, model.today.work_request))), 5000)])
}
