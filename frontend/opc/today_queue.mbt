///|
// A browser observation of one explicitly selected company project. These
// counts are never a whole-company catalog, approvals, revenue or execution.
#derive(Debug, Eq)
struct TodayTask {
  id : String
  project_id : String
  title : String
  owner_id : String
  owner_name : String
  due : String
  status : String
  execution_state : String
  execution_error : String
}

///|
#derive(Debug, Eq)
struct TodayState {
  actor : String
  epoch : Int32
  projects : Array[ProductCompanyProject]
  project_state : String
  project_request : Int32
  project_note : String
  project_id : String
  tasks : Array[TodayTask]
  work_state : String
  work_request : Int32
  observed_at : String
  scope : String
  project_reads : Array[TodayProjectRead]
  filters : TodayFilters
  task_metadata : Map[String, Json]
}

///|
#derive(Debug, Eq)
enum TodayMsg {
  NewObjective
  DelegateObjective(String)
  ReviseObjective(String, String)
  AcceptObjective(String, String)
  ObjectiveAccepted(String, Int32, String, String, Int32, String)
  Refresh
  ChooseAll
  RetryFailed
  RetryProject(String)
  ChooseProject(String)
  RefreshTasks
  ProjectListRead(String, Int32, Int32, Int32, String)
  TasksRead(String, Int32, String, Int32, Int32, String, String)
  OpenTask(String)
  Filter(String, Int32, Int32, String, String)
}

///|
fn today_initial() -> TodayState {
  {
    actor: "",
    epoch: 0,
    projects: [],
    project_state: "idle",
    project_request: 0,
    project_note: "",
    project_id: "",
    tasks: [],
    work_state: "idle",
    work_request: 0,
    observed_at: "",
    scope: "project",
    project_reads: [],
    filters: today_filters_initial(),
    task_metadata: Map([]),
  }
}

///|
fn today_decode_tasks(body : String, project_id : String) -> Array[TodayTask]? {
  if project_id.is_empty() {
    return None
  }
  let root = @json.parse(body) catch { _ => return None }
  if products_field(root, "scope_required") is True ||
    products_field(root, "success") is False {
    return None
  }
  let items = match products_field(root, "items") {
    Array(items) => items
    _ => return None
  }
  let tasks : Array[TodayTask] = []
  for item in items {
    // Do not silently drop broken rows and then present a complete count.
    if !["taskGuid", "projGuid", "taskName", "status"].all(key => {
        products_field(item, key) is String(text) && !text.trim().is_empty()
      }) ||
      !["ownerGuid", "ownerName", "planEndDate"].all(key => {
        products_field(item, key) is String(_)
      }) {
      return None
    }
    let id = products_text(item, "taskGuid")
    if id.trim() != id ||
      products_text(item, "projGuid") != project_id ||
      tasks.any(task => task.id == id) {
      return None
    }
    let execution = products_field(item, "execution")
    if !(execution is Null) &&
      (
        !(execution is Object(_)) ||
        !["state", "error"].all(key => {
          products_optional_text(products_field(execution, key))
        })
      ) {
      return None
    }
    tasks.push({
      id,
      project_id,
      title: products_text(item, "taskName"),
      owner_id: products_text(item, "ownerGuid"),
      owner_name: products_text(item, "ownerName"),
      due: products_text(item, "planEndDate"),
      status: products_text(item, "status"),
      execution_state: products_text(execution, "state"),
      execution_error: products_text(execution, "error"),
    })
  }
  Some(tasks)
}

///|
// Date-only deadlines follow dispatch_today(): UTC calendar days, without an
// invented hour or conversion of ambiguous imported timestamps.
fn today_date_valid(value : String) -> Bool {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    return false
  }
  for index in [0, 1, 2, 3, 5, 6, 8, 9] {
    if value[index] < '0' || value[index] > '9' {
      return false
    }
  }
  let year = (value[0].to_int() - 48) * 1000 +
    (value[1].to_int() - 48) * 100 +
    (value[2].to_int() - 48) * 10 +
    value[3].to_int() -
    48
  let month = (value[5].to_int() - 48) * 10 + value[6].to_int() - 48
  let day = (value[8].to_int() - 48) * 10 + value[9].to_int() - 48
  if year == 0 || month < 1 || month > 12 || day < 1 {
    return false
  }
  let days = if month == 2 {
    if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
      29
    } else {
      28
    }
  } else if [4, 6, 9, 11].contains(month) {
    30
  } else {
    31
  }
  day <= days
}

///|
fn today_outstanding(task : TodayTask) -> Bool {
  // The native canonical terminal state is done; retain unfamiliar imported
  // states for inspection rather than guessing that their work is complete.
  !["done", "cancelled", "canceled", "closed"].contains(task.status)
}

///|
fn today_blocker(task : TodayTask) -> String {
  match task.execution_state {
    "failed" => "执行失败"
    "blocked" => "执行受阻"
    "runtime_unavailable" => "执行环境不可用"
    "interrupted" => "执行中断"
    "waiting_approval" => "执行正在等待审批（不代表可批准）"
    "cancelled" => "执行已取消"
    _ => ""
  }
}

///|
fn today_attention(task : TodayTask, day : String) -> String {
  let reasons : Array[String] = []
  let blocker = today_blocker(task)
  if !blocker.is_empty() {
    reasons.push(blocker)
  }
  if today_date_valid(task.due) && today_date_valid(day) {
    if task.due < day {
      reasons.push("已逾期")
    } else if task.due == day {
      reasons.push("今日到期")
    }
  }
  if task.status == "blocked" {
    reasons.push("正式任务状态为 blocked")
  }
  if task.status == "overdue" {
    reasons.push("正式任务状态为 overdue")
  }
  reasons.join(" · ")
}

///|
fn today_rank(task : TodayTask, day : String) -> Int32 {
  if !today_blocker(task).is_empty() || task.status == "blocked" {
    0
  } else if (
      today_date_valid(day) && today_date_valid(task.due) && task.due < day
    ) ||
    task.status == "overdue" {
    1
  } else if today_date_valid(day) &&
    today_date_valid(task.due) &&
    task.due == day {
    2
  } else {
    3
  }
}

///|
fn today_queue(state : TodayState, day : String) -> Array[TodayTask] {
  let tasks = state.tasks.filter(today_outstanding)
  tasks.sort_by((a, b) => {
    let rank_a = today_rank(a, day)
    let rank_b = today_rank(b, day)
    if rank_a != rank_b {
      rank_a - rank_b
    } else {
      let due_a = if today_date_valid(a.due) { a.due } else { "9999-99-99" }
      let due_b = if today_date_valid(b.due) { b.due } else { "9999-99-99" }
      let order = due_a.lexical_compare(due_b)
      if order != 0 {
        order
      } else {
        a.id.lexical_compare(b.id)
      }
    }
  })
  tasks
}
