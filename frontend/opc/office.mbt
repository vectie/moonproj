///|
struct OfficeState {
  view : String
  task_id : String
  task_actor : String
  task_epoch : Int32
  selected : String
  actor : String
  source_request : Int32
  epoch : Int32
  request : Int32
  pending_task : String
  records : Map[String, Json]
  error : String
}

///|
struct OfficeAssignment {
  task : TodayTask
  command : String
  stage : String
  summary : String
  artifacts : Array[Json]
  source : String
}

///|
struct OfficeAgent {
  key : String
  name : String
  role : String
  parent : String
  session : String
  workspace : String
  assignments : Array[OfficeAssignment]
}

///|
enum OfficeMsg {
  View(String)
  Task(String)
  Select(String)
  Close
  Refresh
  Read(String, Int32, Int32, Int32, String, Int32, String)
}

///|
fn office_initial() -> OfficeState {
  {
    view: "office",
    task_id: "",
    task_actor: "",
    task_epoch: -1,
    selected: "",
    actor: "",
    source_request: -1,
    epoch: -1,
    request: 0,
    pending_task: "",
    records: Map([]),
    error: "",
  }
}

///|
fn office_tasks(model : Model) -> Array[TodayTask] {
  let s = model.today
  if s.actor.is_empty() ||
    s.actor != model.dispatch_task_actor_id ||
    s.project_state != "ready" {
    return []
  }
  let tasks = (if s.scope == "all" {
    today_portfolio_tasks(s)
  } else if ["ready", "empty"].contains(s.work_state) {
    s.tasks.filter(t => t.project_id == s.project_id)
  } else {
    []
  }).filter(task => !objective_is_node(s, task))
  // Creation time comes from the first saved revision, not last activity.
  tasks.sort_by((a, b) => {
    let order = products_text(objective_metadata(s, b.id), "createdAt").compare(
      products_text(objective_metadata(s, a.id), "createdAt"),
    )
    if order == 0 {
      b.id.compare(a.id)
    } else {
      order
    }
  })
  tasks
}

///|
fn office_current_task(model : Model) -> TodayTask? {
  let tasks = office_tasks(model)
  if model.office.task_actor == model.today.actor &&
    model.office.task_epoch == model.today.epoch {
    if tasks.filter(t => t.id == model.office.task_id).get(0) is Some(task) {
      return Some(task)
    }
  }
  tasks.get(0)
}

///|
fn office_record(model : Model, task : TodayTask) -> Json {
  if model.office.actor == model.today.actor &&
    model.office.epoch == model.today.epoch &&
    model.office.source_request == model.today.work_request {
    if model.office.records.get(task.id) is Some(record) {
      return record
    }
  }
  Json::null()
}

///|
fn office_stage(state : String, control : String, terminal : Bool) -> String {
  if terminal {
    return match state {
      "done" | "completed" => "执行完成"
      "failed" => "执行失败"
      "cancelled" => "已取消"
      _ => "结果未确认"
    }
  }
  match control {
    "stopped" => "已停止"
    "stopping" => "停止待确认"
    "revising" => "修改中"
    "resuming" => "恢复待确认"
    _ =>
      match state {
        "running" => "执行中"
        "pending" | "queued" => "排队中"
        "waiting" | "waiting_approval" => "等待输入或审批"
        "paused" | "interrupted" => "已暂停"
        "done" | "completed" => "执行完成"
        "failed" => "执行失败"
        "cancelled" => "已取消"
        "runtime_unavailable" => "执行环境不可用"
        _ => "状态未确认"
      }
  }
}

///|
fn office_agent_key(session : String, workspace : String) -> String {
  session + "|" + workspace
}

///|
fn office_agents(model : Model) -> Array[OfficeAgent] {
  let agents : Map[String, OfficeAgent] = Map([])
  let tasks = match office_current_task(model) {
    Some(task) => [task]
    None => []
  }
  for task in tasks {
    let saved = objective_metadata(model.today, task.id)
    let record = office_record(model, task)
    let detail = products_field(record, "task")
    let raw = if products_text(detail, "taskGuid") == task.id {
      detail
    } else {
      saved
    }
    let task = {
      ..task,
      title: if products_text(raw, "taskName").is_empty() {
        task.title
      } else {
        products_text(raw, "taskName")
      },
      status: if products_text(raw, "status").is_empty() {
        task.status
      } else {
        products_text(raw, "status")
      },
    }
    let execution = products_field(raw, "execution")
    let session = products_text(execution, "session_id")
    if session.is_empty() {
      continue
    }
    let workspace = products_text(execution, "workspace")
    let root_key = task.id + "|" + office_agent_key(session, workspace)
    let control = products_text(execution, "control_state")
    let assignment : OfficeAssignment = {
      task,
      command: products_text(execution, "command_id"),
      stage: if control.is_empty() && task.status == "done" {
        "已接受"
      } else if control.is_empty() && task.status == "submitted" {
        "待验收"
      } else {
        office_stage(products_text(execution, "state"), control, false)
      },
      summary: products_text(execution, "summary"),
      artifacts: dispatch_continuation_array(execution, "artifact_refs"),
      source: "公司执行记录",
    }
    if agents.get(root_key) is Some(agent) {
      agent.assignments.push(assignment)
    } else {
      agents[root_key] = {
        key: root_key,
        name: if products_text(raw, "delivery_mode") == "coordinated" {
          "交付负责人"
        } else {
          "执行 Agent"
        },
        role: products_text(execution, "model"),
        parent: "",
        session,
        workspace,
        assignments: [assignment],
      }
    }
    let workers = if products_text(record, "state") == "observed" {
      dispatch_continuation_array(record, "workers")
    } else {
      dispatch_continuation_array(execution, "workers")
    }
    for worker in workers {
      let child = products_text(worker, "child_session_id")
      if child.is_empty() {
        continue
      }
      if dispatch_continuation_array(
          products_field(execution, "control_receipt"),
          "sessions",
        ).any(node => {
          products_text(node, "session_id") == child &&
          products_text(node, "state") == "missing"
        }) {
        continue
      }
      let book = if !products_text(worker, "child_book_root").is_empty() {
        products_text(worker, "child_book_root")
      } else if !products_text(
          products_field(worker, "terminal_evidence"),
          "book_root",
        ).is_empty() {
        products_text(products_field(worker, "terminal_evidence"), "book_root")
      } else {
        dispatch_continuation_array(
          products_field(execution, "control_receipt"),
          "sessions",
        )
        .filter(node => products_text(node, "session_id") == child)
        .get(0)
        .map(node => products_text(node, "book_root"))
        .unwrap_or("")
      }
      let key = task.id + "|" + office_agent_key(child, workspace)
      let assignment : OfficeAssignment = {
        task,
        command: products_text(worker, "child_command_id"),
        stage: office_stage(
          products_text(worker, "status"),
          control,
          products_field(worker, "terminal") is True,
        ),
        summary: products_text(worker, "summary"),
        artifacts: dispatch_continuation_array(worker, "artifact_references"),
        source: if products_text(record, "state") == "observed" {
          "MoonClaw 专员观察"
        } else {
          "公司专员记录"
        },
      }
      if agents.get(key) is Some(agent) {
        agent.assignments.push(assignment)
      } else {
        agents[key] = {
          key,
          name: products_text(worker, "worker_id"),
          role: "本次运行专员",
          parent: root_key,
          session: child,
          workspace: book,
          assignments: [assignment],
        }
      }
    }
  }
  agents.values().to_array()
}

///|
fn office_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : OfficeMsg,
) -> (Cmd, Model) {
  if model.page != Fleet {
    return (none, model)
  }
  match action {
    Task(id) => {
      if !office_tasks(model).any(t => t.id == id) {
        return (none, model)
      }
      (
        none,
        {
          ..model,
          office: {
            ..model.office,
            task_id: id,
            task_actor: model.today.actor,
            task_epoch: model.today.epoch,
            selected: "",
            request: model.office.request + 1,
            pending_task: "",
            error: "",
          },
        },
      )
    }
    View(view) =>
      if ["office", "fleet"].contains(view) {
        (none, { ..model, office: { ..model.office, view, }, })
      } else {
        (none, model)
      }
    Close =>
      (
        @cmd.custom_cmd(_ => {
          office_focus(
            "office-agent-" + dispatch_url_encode(model.office.selected),
          )
        }),
        { ..model, office: { ..model.office, selected: "", }, },
      )
    Select(key) => {
      if !office_agents(model).any(a => a.key == key) {
        return (none, model)
      }
      let next = {
        ..model,
        office: { ..model.office, selected: key, error: "", },
      }
      let agent = office_agents(next).filter(a => a.key == key)[0]
      let task = agent.assignments[0].task
      let focus = @cmd.custom_cmd(_ => office_focus("office-inspector"))
      if next.office.pending_task == task.id &&
        next.office.epoch == next.today.epoch &&
        next.office.source_request == next.today.work_request {
        return (focus, next)
      }
      let record = office_record(next, task)
      if !(record is Null) {
        return (
          focus,
          {
            ..next,
            office: {
              ..next.office,
              request: next.office.request + 1,
              pending_task: "",
              error: products_text(record, "error"),
            },
          },
        )
      }
      let (read, loaded) = office_update(emit, next, Refresh)
      (@cmd.batch([read, focus]), loaded)
    }
    Refresh => {
      let selected = office_agents(model)
        .filter(a => a.key == model.office.selected)
        .get(0)
      guard selected is Some(agent) else { return (none, model) }
      let task = agent.assignments[0].task.id
      let s = model.today
      let sequence = model.office.request + 1
      let records = if model.office.actor == s.actor &&
        model.office.epoch == s.epoch &&
        model.office.source_request == s.work_request {
        model.office.records
      } else {
        Map([])
      }
      (
        company_setup_get(
          "/api/company/tasks/" + dispatch_url_encode(task) + "/office",
          (status, body) => {
            emit(
              OfficeAction(
                Read(
                  s.actor,
                  s.epoch,
                  s.work_request,
                  sequence,
                  task,
                  status,
                  body,
                ),
              ),
            )
          },
        ),
        {
          ..model,
          office: {
            ..model.office,
            actor: s.actor,
            epoch: s.epoch,
            source_request: s.work_request,
            request: sequence,
            pending_task: task,
            records,
            error: "",
          },
        },
      )
    }
    Read(actor, epoch, source_request, sequence, task, status, body) => {
      if actor != model.today.actor ||
        actor != model.dispatch_task_actor_id ||
        epoch != model.today.epoch ||
        source_request != model.today.work_request ||
        sequence != model.office.request ||
        model.office.pending_task != task {
        return (none, model)
      }
      let result = @json.parse(body) catch { _ => Json::null() }
      let raw = products_field(result, "task")
      let saved = objective_metadata(model.today, task)
      if status == 200 &&
        products_text(result, "schema") == "moonproj.office-observation.v1" &&
        products_text(raw, "taskGuid") == task &&
        products_text(raw, "projGuid") == products_text(saved, "projGuid") &&
        products_text(products_field(raw, "execution"), "session_id") ==
        products_text(products_field(saved, "execution"), "session_id") &&
        products_text(products_field(raw, "execution"), "workspace") ==
        products_text(products_field(saved, "execution"), "workspace") {
        let records = model.office.records.copy()
        records[task] = result
        (
          none,
          {
            ..model,
            office: {
              ..model.office,
              records,
              pending_task: "",
              error: products_text(result, "error"),
            },
          },
        )
      } else {
        (
          none,
          {
            ..model,
            office: {
              ..model.office,
              pending_task: "",
              error: "观察未完成，保留公司记录。请重试。",
            },
          },
        )
      }
    }
  }
}

///|
extern "js" fn office_focus(id : String) =
  #| id => {
  #|   if (typeof document === 'undefined') return;
  #|   requestAnimationFrame(() => requestAnimationFrame(() => {
  #|     const target = document.getElementById(id);
  #|     if (target) { target.focus({preventScroll: true}); target.scrollIntoView({block: 'nearest'}); }
  #|   }));
  #| }
