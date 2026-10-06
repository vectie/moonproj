///|
extern "js" fn today_observed_at() -> String =
  #| () => new Date().toISOString()

///|
fn today_tasks_url(project : String) -> String {
  "/api/company/tasks?project_id=" + dispatch_url_encode(project)
}

///|
fn today_load_tasks(emit : @rabbita.Emit[Msg], state : TodayState) -> Cmd {
  company_setup_get(today_tasks_url(state.project_id), (status, body) => {
    emit(
      TodayAction(
        TasksRead(
          state.actor,
          state.epoch,
          state.project_id,
          state.work_request,
          status,
          body,
          today_observed_at(),
        ),
      ),
    )
  })
}

///|
fn today_reconcile(
  emit : @rabbita.Emit[Msg],
  command : Cmd,
  model : Model,
) -> (Cmd, Model) {
  if model.today.actor == model.dispatch_task_actor_id {
    return (command, model)
  }
  let next = {
    ..model,
    today: {
      ..today_initial(),
      actor: model.dispatch_task_actor_id,
      epoch: model.today.epoch + 1,
      project_state: if model.dispatch_task_actor_id.is_empty() {
        "unauthorized"
      } else {
        "idle"
      },
    },
  }
  if next.page == Overview && !next.today.actor.is_empty() {
    let (read, refreshed) = today_update(emit, Refresh, next)
    (@cmd.batch([command, read]), refreshed)
  } else {
    (command, next)
  }
}

///|
fn today_update(
  emit : @rabbita.Emit[Msg],
  action : TodayMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.today
  match action {
    Refresh => {
      if state.actor.is_empty() || state.actor != model.dispatch_task_actor_id {
        return (
          emit(CompanySetupAction(Refresh)),
          {
            ..model,
            today: {
              ..state,
              project_state: "unauthorized",
              tasks: [],
              projects: [],
              project_id: "",
              work_state: "idle",
              observed_at: "",
              project_request: state.project_request + 1,
              work_request: state.work_request + 1,
            },
          },
        )
      }
      let next = {
        ..state,
        project_state: "loading",
        project_note: "",
        projects: [],
        project_request: state.project_request + 1,
        work_request: state.work_request + 1,
        tasks: [],
        work_state: "idle",
        observed_at: "",
      }
      (
        company_setup_get("/api/company/projects", (status, body) => {
          emit(
            TodayAction(
              ProjectListRead(
                next.actor,
                next.epoch,
                next.project_request,
                status,
                body,
              ),
            ),
          )
        }),
        { ..model, today: next, },
      )
    }
    ProjectListRead(actor, epoch, request, status, body) => {
      if actor != state.actor ||
        actor != model.dispatch_task_actor_id ||
        epoch != state.epoch ||
        request != state.project_request ||
        state.project_state != "loading" {
        return (none, model)
      }
      let read_state = products_read_state(status, body)
      let root = @json.parse(body) catch { _ => Json::null() }
      let projects = if read_state == "ready" &&
        !(products_field(root, "success") is False) {
        products_decode_projects(body)
      } else {
        None
      }
      match projects {
        None =>
          (
            none,
            {
              ..model,
              today: {
                ..state,
                projects: [],
                tasks: [],
                project_id: "",
                observed_at: "",
                work_state: "idle",
                project_state: if read_state == "ready" {
                  "invalid"
                } else {
                  read_state
                },
              },
            },
          )
        Some(projects) => {
          let next = {
            ..state,
            projects,
            project_state: if projects.is_empty() {
              "empty"
            } else {
              "ready"
            },
            project_note: products_project_note(body),
            project_id: if projects.any(project => {
                project.id == state.project_id
              }) {
              state.project_id
            } else {
              ""
            },
          }
          let loaded = { ..model, today: next, }
          if next.project_id.is_empty() {
            (none, loaded)
          } else {
            today_update(emit, RefreshTasks, loaded)
          }
        }
      }
    }
    ChooseProject(id) => {
      if state.project_state != "ready" ||
        !state.projects.any(project => project.id == id) {
        return (none, model)
      }
      today_update(emit, RefreshTasks, {
        ..model,
        today: { ..state, project_id: id, observed_at: "", },
      })
    }
    RefreshTasks => {
      if state.actor.is_empty() ||
        state.actor != model.dispatch_task_actor_id ||
        state.project_state != "ready" ||
        !state.projects.any(project => project.id == state.project_id) {
        return (none, model)
      }
      let next = {
        ..state,
        tasks: [],
        work_state: "loading",
        work_request: state.work_request + 1,
      }
      (today_load_tasks(emit, next), { ..model, today: next, })
    }
    TasksRead(actor, epoch, project, request, status, body, observed_at) => {
      if actor != state.actor ||
        actor != model.dispatch_task_actor_id ||
        epoch != state.epoch ||
        project != state.project_id ||
        request != state.work_request ||
        state.project_state != "ready" ||
        state.work_state != "loading" {
        return (none, model)
      }
      let read_state = products_read_state(status, body)
      let tasks = if read_state == "ready" {
        today_decode_tasks(body, project)
      } else {
        None
      }
      match tasks {
        None =>
          (
            none,
            {
              ..model,
              today: {
                ..state,
                tasks: [],
                work_state: if read_state == "ready" {
                  "invalid"
                } else {
                  read_state
                },
              },
            },
          )
        Some(tasks) =>
          (
            none,
            {
              ..model,
              today: {
                ..state,
                tasks,
                work_state: if tasks.is_empty() {
                  "empty"
                } else {
                  "ready"
                },
                observed_at,
              },
            },
          )
      }
    }
    OpenTask(id) => {
      if state.work_state != "ready" ||
        state.actor != model.dispatch_task_actor_id ||
        !state.tasks.any(task => {
          task.id == id && task.project_id == state.project_id
        }) {
        return (none, model)
      }
      open_dispatch_task(emit, { ..model, dispatch_task_open_id: id, })
    }
  }
}
