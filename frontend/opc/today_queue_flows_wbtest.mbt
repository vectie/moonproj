///|
// Reducer replies are delivered explicitly. Executed effects use the existing
// non-networking navigation fixture, which records every method and exact URL.
fn today_flows_update(model : Model, action : TodayMsg) -> Model {
  let (_, next) = update(_ => none, TodayAction(action), model)
  next
}

///|
fn today_flows_initial(actor : String) -> Model {
  {
    ..initial_model(),
    page: Overview,
    dispatch_task_actor_id: actor,
    today: { ..today_initial(), actor, },
  }
}

///|
fn today_flows_projects_body() -> String {
  let body =
    #|{"items":[{"project_id":"project-a","project_name":"Project A","source_kind":"command"},{"project_id":"project-b","project_name":"Project B","source_kind":"import"},{"project_id":"project A/&?#","project_name":"Encoded project","source_kind":"command"}]}
  body
}

///|
fn today_flows_projects(model : Model) -> Model {
  let loading = today_flows_update(model, Refresh)
  today_flows_update(
    loading,
    ProjectListRead(
      loading.today.actor,
      loading.today.epoch,
      loading.today.project_request,
      200,
      today_flows_projects_body(),
    ),
  )
}

///|
fn today_flows_task_json(id : String, project : String) -> Json {
  Json::object({
    "taskGuid": Json::string(id),
    "projGuid": Json::string(project),
    "taskName": Json::string("Actual task " + id),
    "ownerGuid": Json::string("owner-one"),
    "ownerName": Json::string("Owner One"),
    "planEndDate": Json::string("2026-10-05"),
    "status": Json::string("pending"),
    "execution": Json::null(),
  })
}

///|
fn today_flows_tasks_body(id : String, project : String) -> String {
  Json::object({ "items": Json::array([today_flows_task_json(id, project)]) }).stringify()
}

///|
fn today_flows_read(model : Model, status : Int, body : String) -> Model {
  today_flows_update(
    model,
    TasksRead(
      model.today.actor,
      model.today.epoch,
      model.today.project_id,
      model.today.work_request,
      status,
      body,
      "2026-10-05T12:00:00.000Z",
    ),
  )
}

///|
fn today_flows_ready(actor : String, project : String, task : String) -> Model {
  let loading = today_flows_update(
    today_flows_projects(today_flows_initial(actor)),
    ChooseProject(project),
  )
  today_flows_read(loading, 200, today_flows_tasks_body(task, project))
}

///|
test "Today refresh reads projects but never implicitly chooses a project or reads unscoped tasks" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let (request, loading) = update(
    _ => none,
    TodayAction(Refresh),
    today_flows_initial("actor-a"),
  )
  drafts_test_execute(request)
  assert_eq(loading.today.project_state, "loading")
  assert_eq(loading.today.project_id, "")
  assert_eq(loading.today.tasks.length(), 0)
  assert_eq(drafts_navigation_requests(), "GET /api/company/projects")
  let (receipt, ready) = update(
    _ => none,
    TodayAction(
      ProjectListRead(
        "actor-a",
        loading.today.epoch,
        loading.today.project_request,
        200,
        today_flows_projects_body(),
      ),
    ),
    loading,
  )
  drafts_test_execute(receipt)
  assert_eq(ready.today.project_state, "ready")
  assert_eq(ready.today.projects.length(), 3)
  assert_eq(ready.today.project_id, "")
  assert_eq(ready.today.tasks.length(), 0)
  let (unscoped, unchanged) = update(
    _ => none,
    TodayAction(RefreshTasks),
    ready,
  )
  drafts_test_execute(unscoped)
  assert_eq(unchanged.today.project_id, "")
  assert_eq(drafts_navigation_requests(), "GET /api/company/projects")
  drafts_navigation_cleanup()
}

///|
test "Today project selection is explicit exact and encoded with no product or unscoped read" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let ready = today_flows_projects(today_flows_initial("actor-a"))
  let project = "project A/&?#"
  let (request, loading) = update(
    _ => none,
    TodayAction(ChooseProject(project)),
    ready,
  )
  drafts_test_execute(request)
  assert_eq(loading.today.project_id, project)
  assert_eq(loading.today.work_state, "loading")
  assert_eq(loading.today.tasks.length(), 0)
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks?project_id=" + dispatch_url_encode(project),
  )
  let (invalid, rejected) = update(
    _ => none,
    TodayAction(ChooseProject("unknown-project")),
    loading,
  )
  drafts_test_execute(invalid)
  assert_eq(rejected.today.project_id, project)
  assert_eq(rejected.today.work_request, loading.today.work_request)
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks?project_id=" + dispatch_url_encode(project),
  )
  assert_false(drafts_navigation_requests().contains("product_id="))
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}

///|
test "Today project refresh ignores older requests and duplicate completed replies" {
  let first = today_flows_update(today_flows_initial("actor-a"), Refresh)
  let second = today_flows_update(first, Refresh)
  assert_true(second.today.project_request > first.today.project_request)
  let stale = today_flows_update(
    second,
    ProjectListRead(
      "actor-a",
      first.today.epoch,
      first.today.project_request,
      200,
      today_flows_projects_body(),
    ),
  )
  assert_eq(stale.today.project_state, "loading")
  assert_eq(stale.today.projects.length(), 0)
  let ready = today_flows_update(
    stale,
    ProjectListRead(
      "actor-a",
      second.today.epoch,
      second.today.project_request,
      200,
      today_flows_projects_body(),
    ),
  )
  let duplicate = today_flows_update(
    ready,
    ProjectListRead(
      "actor-a",
      second.today.epoch,
      second.today.project_request,
      401,
      "{}",
    ),
  )
  assert_eq(duplicate.today.project_state, "ready")
  assert_eq(duplicate.today.projects, ready.today.projects)
}

///|
test "Today task refresh cannot accept stale requests or duplicate terminal replies" {
  let ready = today_flows_ready("actor-a", "project-a", "old-task")
  let first = today_flows_update(ready, RefreshTasks)
  let second = today_flows_update(first, RefreshTasks)
  assert_true(second.today.work_request > first.today.work_request)
  let stale = today_flows_update(
    second,
    TasksRead(
      "actor-a",
      first.today.epoch,
      "project-a",
      first.today.work_request,
      200,
      today_flows_tasks_body("stale-task", "project-a"),
      "old timestamp",
    ),
  )
  assert_eq(stale.today.work_state, "loading")
  assert_false(stale.today.tasks.any(task => task.id == "stale-task"))
  assert_true(stale.today.observed_at != "old timestamp")
  let latest = today_flows_read(
    stale,
    200,
    today_flows_tasks_body("latest-task", "project-a"),
  )
  assert_eq(latest.today.work_state, "ready")
  assert_eq(latest.today.tasks[0].id, "latest-task")
  assert_eq(latest.today.observed_at, "2026-10-05T12:00:00.000Z")
  let duplicate = today_flows_update(
    latest,
    TasksRead(
      "actor-a",
      latest.today.epoch,
      "project-a",
      latest.today.work_request,
      403,
      "{}",
      "duplicate timestamp",
    ),
  )
  assert_eq(duplicate.today.work_state, "ready")
  assert_eq(duplicate.today.tasks, latest.today.tasks)
  assert_eq(duplicate.today.observed_at, latest.today.observed_at)
}

///|
test "Today project A to B to A rejects both previous project and previous same-project responses" {
  let projects = today_flows_projects(today_flows_initial("actor-a"))
  let first_a = today_flows_update(projects, ChooseProject("project-a"))
  let b = today_flows_update(first_a, ChooseProject("project-b"))
  let newest_a = today_flows_update(b, ChooseProject("project-a"))
  assert_true(b.today.work_request > first_a.today.work_request)
  assert_true(newest_a.today.work_request > b.today.work_request)
  let mut current = newest_a
  for previous in [first_a, b] {
    current = today_flows_update(
      current,
      TasksRead(
        "actor-a",
        previous.today.epoch,
        previous.today.project_id,
        previous.today.work_request,
        200,
        today_flows_tasks_body(
          "stale-" + previous.today.project_id,
          previous.today.project_id,
        ),
        "stale timestamp",
      ),
    )
    assert_eq(current.today.project_id, "project-a")
    assert_eq(current.today.work_state, "loading")
    assert_eq(current.today.tasks.length(), 0)
    assert_true(current.today.observed_at != "stale timestamp")
  }
  let loaded = today_flows_read(
    current,
    200,
    today_flows_tasks_body("current-a", "project-a"),
  )
  assert_eq(loaded.today.tasks[0].id, "current-a")
}

///|
test "Today actor A to B to A advances epoch and rejects both old actors and previous A replies" {
  let first_a = today_flows_update(
    today_flows_projects(today_flows_initial("actor-a")),
    ChooseProject("project-a"),
  )
  let (_, b) = update(_ => none, DispatchSessionLoaded("actor-b"), first_a)
  assert_eq(b.today.actor, "actor-b")
  assert_true(b.today.epoch > first_a.today.epoch)
  assert_eq(b.today.project_id, "")
  assert_eq(b.today.projects.length(), 0)
  assert_eq(b.today.tasks.length(), 0)
  let b = today_flows_update(
    today_flows_projects(b),
    ChooseProject("project-b"),
  )
  let (_, returned_a) = update(_ => none, DispatchSessionLoaded("actor-a"), b)
  assert_eq(returned_a.today.actor, "actor-a")
  assert_true(returned_a.today.epoch > b.today.epoch)
  assert_eq(returned_a.today.project_id, "")
  let latest = today_flows_update(
    today_flows_projects(returned_a),
    ChooseProject("project-a"),
  )
  let mut current = latest
  for previous in [first_a, b] {
    current = today_flows_update(
      current,
      ProjectListRead(
        previous.today.actor,
        previous.today.epoch,
        current.today.project_request,
        200,
        "{\"items\":[]}",
      ),
    )
    current = today_flows_update(
      current,
      TasksRead(
        previous.today.actor,
        previous.today.epoch,
        "project-a",
        current.today.work_request,
        200,
        today_flows_tasks_body("wrong-actor-task", "project-a"),
        "stale actor timestamp",
      ),
    )
    assert_eq(current.today.projects.length(), 3)
    assert_eq(current.today.project_id, "project-a")
    assert_eq(current.today.work_state, "loading")
    assert_eq(current.today.tasks.length(), 0)
  }
  let accepted = today_flows_read(
    current,
    200,
    today_flows_tasks_body("new-actor-a-task", "project-a"),
  )
  assert_eq(accepted.today.tasks[0].id, "new-actor-a-task")
}

///|
test "Today logout clears visible scope and cannot send reads or open a previous actor task" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let ready = today_flows_ready("actor-a", "project-a", "private-task")
  let (_, logged_out) = update(_ => none, DispatchSessionLoaded(""), ready)
  assert_eq(logged_out.today.actor, "")
  assert_eq(logged_out.today.project_id, "")
  assert_eq(logged_out.today.projects.length(), 0)
  assert_eq(logged_out.today.tasks.length(), 0)
  let actions : Array[TodayMsg] = [
    Refresh,
    RefreshTasks,
    ChooseProject("project-a"),
    OpenTask("private-task"),
  ]
  for action in actions {
    let (command, next) = update(_ => none, TodayAction(action), logged_out)
    drafts_test_execute(command)
    assert_eq(next.today.project_id, "")
    assert_eq(next.today.tasks.length(), 0)
    assert_eq(next.dispatch_task_id, logged_out.dispatch_task_id)
  }
  assert_eq(drafts_navigation_requests(), "")
  drafts_navigation_cleanup()
}

///|
test "Today malformed task envelopes and cross-project rows fail closed instead of claiming an empty queue" {
  let loading = today_flows_update(
    today_flows_projects(today_flows_initial("actor-a")),
    ChooseProject("project-a"),
  )
  let duplicate = today_flows_task_json("duplicate", "project-a")
  for
    body in [
      "broken json",
      "{}",
      "{\"items\":null}",
      "{\"items\":{}}",
      "{\"items\":[null]}",
      "{\"items\":[{\"taskGuid\":\"missing-project\"}]}",
      today_flows_tasks_body("wrong-project", "project-b"),
      Json::object({ "items": Json::array([duplicate, duplicate]) }).stringify(),
    ] {
    let invalid = today_flows_read(loading, 200, body)
    assert_eq(invalid.today.work_state, "invalid")
    assert_eq(invalid.today.tasks.length(), 0)
  }
  let empty = today_flows_read(loading, 200, "{\"items\":[]}")
  assert_eq(empty.today.work_state, "empty")
  assert_eq(empty.today.tasks.length(), 0)
}

///|
test "Today task decoder rejects malformed field types without silently dropping bad rows" {
  for
    field in [
      "taskGuid", "projGuid", "taskName", "ownerGuid", "ownerName", "planEndDate",
      "status", "execution",
    ] {
    let fields = match today_flows_task_json("task-a", "project-a") {
      Object(fields) => fields
      _ => fail("expected fixture task object")
    }
    fields[field] = Json::number(42)
    let body = Json::object({ "items": Json::array([Json::object(fields)]) }).stringify()
    assert_true(today_decode_tasks(body, "project-a") is None)
  }
  for field in ["state", "error"] {
    let fields = match today_flows_task_json("task-a", "project-a") {
      Object(fields) => fields
      _ => fail("expected fixture task object")
    }
    let execution : Map[String, Json] = Map([])
    execution[field] = Json::boolean(true)
    fields["execution"] = Json::object(execution)
    let body = Json::object({ "items": Json::array([Json::object(fields)]) }).stringify()
    assert_true(today_decode_tasks(body, "project-a") is None)
  }
}

///|
test "Today offline unauthorized and invalid projects remain distinct from an empty successful list" {
  let loading = today_flows_update(today_flows_initial("actor-a"), Refresh)
  for
    (status, body, expected) in [
      (0, "", "offline"),
      (401, "{}", "unauthorized"),
      (403, "{}", "unauthorized"),
      (200, "broken json", "invalid"),
      (200, "{\"items\":[]}", "empty"),
    ] {
    let read = today_flows_update(
      loading,
      ProjectListRead(
        "actor-a",
        loading.today.epoch,
        loading.today.project_request,
        status,
        body,
      ),
    )
    assert_eq(read.today.project_state, expected)
    assert_eq(read.today.projects.length(), 0)
    assert_eq(read.today.project_id, "")
  }
}

///|
test "Today failed task refresh removes stale rows and remains distinct from a verified empty queue" {
  let ready = today_flows_ready("actor-a", "project-a", "formerly-visible")
  for
    (status, body, expected) in [
      (0, "", "offline"),
      (401, "{}", "unauthorized"),
      (403, "{}", "unauthorized"),
      (200, "broken json", "invalid"),
      (200, "{\"items\":[]}", "empty"),
    ] {
    let loading = today_flows_update(ready, RefreshTasks)
    let read = today_flows_read(loading, status, body)
    assert_eq(read.today.work_state, expected)
    assert_eq(read.today.tasks.length(), 0)
    assert_eq(read.today.project_id, "project-a")
  }
}

///|
test "Today OpenTask opens the exact listed canonical task with GET and preserves a typed draft" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let typed = drafts_test_valid()
  let original = dispatch_active_draft(typed).unwrap()
  let task = "task A/&?#"
  let scoped = today_flows_ready("actor-drafts", "project-a", task)
  let model = { ..typed, page: Overview, today: scoped.today, }
  let (request, opening) = update(_ => none, TodayAction(OpenTask(task)), model)
  drafts_test_execute(request)
  assert_eq(opening.page, Dispatch)
  assert_eq(opening.dispatch_task_id, task)
  assert_eq(opening.dispatch_task_stage, "loading")
  assert_eq(opening.dispatch_task_pending_action, "load")
  assert_eq(opening.dispatch_run, None)
  assert_eq(dispatch_draft_by_id(opening, original.id), Some(original))
  assert_false(opening.dispatch_task_form_open)
  assert_eq(dispatch_saved_task(), task)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/" + dispatch_url_encode(task),
  )
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("/dispatch"))
  assert_false(drafts_navigation_requests().contains("/accept"))
  let (_, loaded) = update(
    _ => none,
    DispatchTaskLoaded(task, opening.dispatch_task_selection, {
      ..dispatch_test_snapshot("completed"),
      task_id: task,
      project_id: "project-a",
    }),
    opening,
  )
  let resumed = drafts_test_update(loaded, Resume(original.id))
  assert_eq(dispatch_active_draft(resumed), Some(original))
  assert_eq(resumed.dispatch_task_id, task)
  assert_eq(
    dispatch_draft_form_model(resumed).dispatch_task_title,
    original.title,
  )
  assert_eq(
    dispatch_draft_form_model(resumed).dispatch_task_acceptance,
    original.acceptance,
  )
  drafts_navigation_cleanup()
}

///|
test "Today cannot open unknown tasks or rows invalidated by a project switch" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let ready = today_flows_ready("actor-a", "project-a", "task-a")
  let switched = today_flows_update(ready, ChooseProject("project-b"))
  for (model, task) in [(ready, "unknown-task"), (switched, "task-a")] {
    let (command, unchanged) = update(
      _ => none,
      TodayAction(OpenTask(task)),
      model,
    )
    drafts_test_execute(command)
    assert_eq(unchanged.dispatch_task_id, model.dispatch_task_id)
    assert_eq(unchanged.dispatch_task_selection, model.dispatch_task_selection)
    assert_eq(unchanged.page, model.page)
  }
  assert_eq(drafts_navigation_requests(), "")
  drafts_navigation_cleanup()
}

///|
test "Today project choices reads and failures never overwrite or create a local task draft" {
  let typed = drafts_test_valid()
  let original = dispatch_active_draft(typed).unwrap()
  let initial = {
    ..typed,
    today: { ..today_initial(), actor: "actor-drafts", },
  }
  let projects = today_flows_projects(initial)
  let a = today_flows_update(projects, ChooseProject("project-a"))
  let loaded = today_flows_read(
    a,
    200,
    today_flows_tasks_body("canonical-a", "project-a"),
  )
  let b = today_flows_update(loaded, ChooseProject("project-b"))
  let failed = today_flows_read(b, 0, "")
  for model in [projects, a, loaded, b, failed] {
    assert_eq(model.dispatch_drafts, typed.dispatch_drafts)
    assert_eq(dispatch_active_draft(model), Some(original))
    assert_eq(model.dispatch_task_form_open, typed.dispatch_task_form_open)
    assert_eq(model.dispatch_task_id, typed.dispatch_task_id)
    assert_eq(model.dispatch_task_selection, typed.dispatch_task_selection)
    assert_eq(
      model.products.prepared_product_id,
      typed.products.prepared_product_id,
    )
    assert_eq(
      model.products.prepared_project_id,
      typed.products.prepared_project_id,
    )
  }
}

///|
test "Today date-only attention validates leap years and never infers a day from timestamps or malformed dates" {
  let task = today_decode_tasks(
      today_flows_tasks_body("task-a", "project-a"),
      "project-a",
    ).unwrap()[0]
  for
    valid in [
      "2024-02-29", "2000-02-29", "2026-04-30", "2026-12-31", "2026-01-01",
    ] {
    assert_true(today_date_valid(valid))
  }
  for
    unknown in [
      "", "unknown", "2026-02-29", "1900-02-29", "2026-04-31", "2026-00-10", "2026-13-01",
      "2026-01-00", "0000-01-01", "2026-1-01", "2026-01-1", "2026/10/05", " 2026-10-05",
      "2026-10-05 ", "2026-10-05T00:00:00Z", "2026-10-04T23:30:00-08:00", "2026-10-06T01:30:00+14:00",
    ] {
    assert_false(today_date_valid(unknown))
    assert_eq(today_attention({ ..task, due: unknown, }, "2026-10-05"), "")
  }
  assert_eq(
    today_attention({ ..task, due: "2026-10-04", }, "2026-10-05"),
    "已逾期",
  )
  assert_eq(
    today_attention({ ..task, due: "2026-10-05", }, "2026-10-05"),
    "今日到期",
  )
  assert_eq(today_attention({ ..task, due: "2026-10-06", }, "2026-10-05"), "")
  assert_eq(
    today_attention({ ..task, due: "2026-10-05", }, "malformed-day"),
    "",
  )
}

///|
test "Today terminal statuses are excluded while unknown states and dates remain outstanding without invented attention" {
  let task = today_decode_tasks(
      today_flows_tasks_body("task-a", "project-a"),
      "project-a",
    ).unwrap()[0]
  let tasks : Array[TodayTask] = []
  for status in ["done", "cancelled", "canceled", "closed"] {
    let terminal = { ..task, id: status, status, }
    assert_false(today_outstanding(terminal))
    tasks.push(terminal)
  }
  for
    status in [
      "pending", "in_progress", "unknown", "completed", "custom-imported-state",
    ] {
    let outstanding = { ..task, id: status, status, due: "", }
    assert_true(today_outstanding(outstanding))
    assert_eq(today_attention(outstanding, "2026-10-05"), "")
    tasks.push(outstanding)
  }
  let queue = today_queue({ ..today_initial(), tasks, }, "2026-10-05")
  assert_eq(queue.length(), 5)
  assert_true(queue.all(today_outstanding))
  assert_true(queue.any(task => task.status == "custom-imported-state"))
}

///|
test "Today exact row decoding preserves owner due and canonical execution facts without promoting display status" {
  let body =
    #|{"items":[{"taskGuid":"known-task","projGuid":"project-a","taskName":"Canonical title","ownerGuid":"owner-a","ownerName":"Owner A","planEndDate":"2026-10-05","status":"in_progress","execution":{"state":"waiting_approval","error":"Approval required"}},{"taskGuid":"unknown-task","projGuid":"project-a","taskName":"Unknown owner and due","ownerGuid":"","ownerName":"","planEndDate":"2026-10-05T01:00:00+14:00","status":"custom-state","execution":null}]}
  let tasks = today_decode_tasks(body, "project-a").unwrap()
  assert_eq(tasks.length(), 2)
  assert_eq(tasks[0].id, "known-task")
  assert_eq(tasks[0].project_id, "project-a")
  assert_eq(tasks[0].title, "Canonical title")
  assert_eq(tasks[0].owner_id, "owner-a")
  assert_eq(tasks[0].owner_name, "Owner A")
  assert_eq(tasks[0].due, "2026-10-05")
  assert_eq(tasks[0].status, "in_progress")
  assert_eq(tasks[0].execution_state, "waiting_approval")
  assert_eq(tasks[0].execution_error, "Approval required")
  assert_true(today_attention(tasks[0], "2026-10-05").contains("等待审批"))
  assert_eq(tasks[1].owner_id, "")
  assert_eq(tasks[1].owner_name, "")
  assert_eq(tasks[1].due, "2026-10-05T01:00:00+14:00")
  assert_eq(tasks[1].status, "custom-state")
  assert_eq(tasks[1].execution_state, "")
  assert_eq(tasks[1].execution_error, "")
  assert_eq(today_attention(tasks[1], "2026-10-05"), "")
}

///|
test "Today reloading project membership invalidates task replies and clears a removed selected project" {
  let selected = today_flows_ready("actor-a", "project-a", "task-a")
  let tasks_loading = today_flows_update(selected, RefreshTasks)
  let projects_loading = today_flows_update(tasks_loading, Refresh)
  let stale = today_flows_update(
    projects_loading,
    TasksRead(
      "actor-a",
      tasks_loading.today.epoch,
      "project-a",
      tasks_loading.today.work_request,
      200,
      today_flows_tasks_body("late-task", "project-a"),
      "late timestamp",
    ),
  )
  assert_eq(stale.today.project_state, "loading")
  assert_eq(stale.today.tasks.length(), 0)
  let changed = today_flows_update(
    stale,
    ProjectListRead(
      "actor-a",
      stale.today.epoch,
      stale.today.project_request,
      200,
      "{\"items\":[{\"project_id\":\"project-b\",\"project_name\":\"Only B remains\",\"source_kind\":\"command\"}]}",
    ),
  )
  assert_eq(changed.today.project_id, "")
  assert_eq(changed.today.tasks.length(), 0)
  assert_eq(changed.today.observed_at, "")
  let (request, rejected) = update(
    _ => none,
    TodayAction(ChooseProject("project-a")),
    changed,
  )
  assert_eq(products_test_effect_count(request), 0)
  assert_eq(rejected.today.project_id, "")
}
