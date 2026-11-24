///|
struct TodayProjectRead {
  project : ProductCompanyProject
  state : String
  tasks : Array[TodayTask]
  observed_at : String
  note : String
  request : Int32
} derive(Debug, Eq)

///|
fn today_portfolio_success(row : TodayProjectRead) -> Bool {
  row.state == "ready" || row.state == "empty"
}

///|
fn today_portfolio_busy(state : TodayState) -> Bool {
  state.project_reads.any(row => row.state == "queued" || row.state == "loading")
}

///|
fn today_portfolio_tasks(state : TodayState) -> Array[TodayTask] {
  let tasks : Array[TodayTask] = []
  for row in state.project_reads {
    if today_portfolio_success(row) {
      for task in row.tasks {
        tasks.push(task)
      }
    }
  }
  tasks
}

///|
fn today_portfolio_day(state : TodayState, project : String) -> String {
  match state.project_reads.filter(row => row.project.id == project).get(0) {
    Some(row) if today_portfolio_success(row) && row.observed_at.length() >= 10 =>
      row.observed_at[:10].to_owned()
    _ => ""
  }
}

///|
fn today_portfolio_queue(state : TodayState) -> Array[TodayTask] {
  let tasks = today_portfolio_tasks(state).filter(today_outstanding)
  tasks.sort_by((a, b) => {
    let rank = today_rank(a, today_portfolio_day(state, a.project_id)) -
      today_rank(b, today_portfolio_day(state, b.project_id))
    if rank != 0 {
      rank
    } else {
      let due_a = if today_date_valid(a.due) { a.due } else { "9999-99-99" }
      let due_b = if today_date_valid(b.due) { b.due } else { "9999-99-99" }
      let due = due_a.lexical_compare(due_b)
      if due != 0 {
        due
      } else {
        a.id.lexical_compare(b.id)
      }
    }
  })
  tasks
}

///|
// Start at most three existing project-scoped reads in this current batch.
// Older invalidated transports may finish; their identities cannot settle it.
fn today_portfolio_pump(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> (Cmd, Model) {
  let state = model.today
  let mut slots = 3 -
    state.project_reads.filter(row => row.state == "loading").length()
  let commands : Array[Cmd] = []
  let rows = state.project_reads.map(row => {
    if row.state == "queued" && slots > 0 {
      slots -= 1
      let project = row.project.id
      commands.push(
        company_setup_get(today_tasks_url(project), (status, body) => {
          emit(
            TodayAction(
              TasksRead(
                state.actor,
                state.epoch,
                project,
                row.request,
                status,
                body,
                today_observed_at(),
              ),
            ),
          )
        }),
      )
      { ..row, state: "loading", }
    } else {
      row
    }
  })
  (@cmd.batch(commands), { ..model, today: { ..state, project_reads: rows, }, })
}

///|
fn today_portfolio_start(
  emit : @rabbita.Emit[Msg],
  model : Model,
  retry : Bool,
) -> (Cmd, Model) {
  let state = model.today
  if state.actor.is_empty() ||
    state.actor != model.dispatch_task_actor_id ||
    !["ready", "empty"].contains(state.project_state) ||
    (retry && (state.scope != "all" || today_portfolio_busy(state))) {
    return (none, model)
  }
  if state.scope == "all" && today_portfolio_busy(state) {
    return (none, model)
  }
  let rows = state.projects.map(project => {
    let previous = state.project_reads
      .filter(row => row.project.id == project.id)
      .get(0)
    match previous {
      Some(row) if retry && today_portfolio_success(row) => row
      _ =>
        {
          project,
          state: "queued",
          tasks: [],
          observed_at: "",
          note: "",
          request: state.work_request + 1,
        }
    }
  })
  today_portfolio_pump(emit, {
    ..model,
    today: {
      ..state,
      scope: "all",
      project_id: "",
      tasks: [],
      observed_at: "",
      work_state: "idle",
      work_request: state.work_request + 1,
      project_reads: rows,
      task_metadata: if retry {
        state.task_metadata
      } else {
        Map([])
      },
    },
  })
}

///|
fn today_portfolio_retry(
  emit : @rabbita.Emit[Msg],
  model : Model,
  project : String,
) -> (Cmd, Model) {
  let state = model.today
  if state.scope != "all" ||
    state.actor.is_empty() ||
    state.actor != model.dispatch_task_actor_id ||
    state.project_state != "ready" ||
    !state.project_reads.any(row => {
      row.project.id == project &&
      !today_portfolio_success(row) &&
      row.state != "queued" &&
      row.state != "loading"
    }) {
    return (none, model)
  }
  let rows = state.project_reads.map(row => {
    if row.project.id == project {
      {
        ..row,
        state: "queued",
        tasks: [],
        observed_at: "",
        note: "",
        request: state.work_request + 1,
      }
    } else {
      row
    }
  })
  today_portfolio_pump(emit, {
    ..model,
    today: {
      ..state,
      project_reads: rows,
      work_request: state.work_request + 1,
    },
  })
}

///|
fn today_portfolio_read(
  emit : @rabbita.Emit[Msg],
  model : Model,
  actor : String,
  epoch : Int32,
  project : String,
  request : Int32,
  status : Int32,
  body : String,
  observed_at : String,
) -> (Cmd, Model) {
  let state = model.today
  if actor != state.actor ||
    actor != model.dispatch_task_actor_id ||
    epoch != state.epoch ||
    state.project_state != "ready" ||
    !state.project_reads.any(row => {
      row.project.id == project &&
      row.state == "loading" &&
      row.request == request
    }) {
    return (none, model)
  }
  let read_state = products_read_state(status, body)
  let decoded = if read_state == "ready" {
    today_decode_tasks(body, project)
  } else {
    None
  }
  let rows = state.project_reads.map(row => {
    if row.project.id != project {
      row
    } else {
      match decoded {
        Some(tasks) =>
          {
            ..row,
            tasks,
            state: if tasks.is_empty() {
              "empty"
            } else {
              "ready"
            },
            observed_at,
            note: "",
          }
        None =>
          {
            ..row,
            tasks: [],
            state: if read_state == "ready" {
              "invalid"
            } else {
              read_state
            },
            note: "",
          }
      }
    }
  })
  // Duplicate canonical IDs across projects are ambiguous, not two countable tasks.
  let counts : Map[String, Int32] = Map([])
  for row in rows {
    for task in row.tasks {
      counts[task.id] = counts.get(task.id).unwrap_or(0) + 1
    }
  }
  let checked = rows.map(row => {
    if today_portfolio_success(row) &&
      row.tasks.any(task => counts.get(task.id).unwrap_or(0) > 1) {
      {
        ..row,
        state: "invalid",
        note: "多个项目返回了相同任务 ID；这些项目需要重新读取后再检查。",
      }
    } else {
      row
    }
  })
  today_portfolio_pump(emit, {
    ..model,
    today: {
      ..state,
      project_reads: checked,
      task_metadata: {
        let metadata = state.task_metadata.copy()
        if decoded is Some(_) {
          for key, value in objective_read_metadata(body) {
            metadata[key] = value
          }
        }
        metadata
      },
    },
  })
}
