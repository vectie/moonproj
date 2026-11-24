///|
fn office_test_model() -> Model {
  let task = {
    ..today_test_task("work-1", "2026-11-24", "in_progress"),
    execution_state: "running",
  }
  let raw : Json = {
    "taskGuid": task.id,
    "projGuid": task.project_id,
    "taskName": task.title,
    "delivery_mode": "coordinated",
    "execution": {
      "session_id": "lead-session",
      "command_id": "C0",
      "workspace": "/book",
      "state": "running",
      "model": "configured-model",
      "control_state": "stopped",
      "workers": [
        {
          "worker_id": "buyer-brief",
          "child_session_id": "worker-1",
          "child_command_id": "W1",
          "status": "done",
          "terminal": true,
        },
        {
          "worker_id": "handoff",
          "child_session_id": "worker-2",
          "child_command_id": "W2",
          "status": "running",
          "terminal": false,
        },
      ],
    },
  }
  {
    ..objectives_test_model(),
    page: Fleet,
    today: {
      ..objectives_test_model().today,
      tasks: [task],
      task_metadata: { "work-1": raw },
      observed_at: "2026-11-24T10:00:00Z",
    },
  }
}

///|
fn office_test_observation(model : Model) -> String {
  let task = office_tasks(model)[0]
  (
    {
      "schema": "moonproj.office-observation.v1",
      "task": objective_metadata(model.today, task.id),
      "state": "observed",
      "observed_at": 1795516200000.0,
      "workers": [
        {
          "worker_id": "buyer-brief",
          "child_session_id": "worker-1",
          "child_command_id": "W1",
          "child_book_root": "/worker-book",
          "status": "done",
          "terminal": true,
          "summary": "Actual buyer brief",
          "artifact_references": [{ "path": "contribution.md" }],
        },
        {
          "worker_id": "handoff",
          "child_session_id": "worker-2",
          "child_command_id": "W2",
          "child_book_root": "/worker-two",
          "status": "done",
          "terminal": true,
        },
      ],
    } : Json).stringify()
}

///|
test "office renders only real recorded execution identities and stopped state takes precedence" {
  let model = office_test_model()
  let agents = office_agents(model)
  assert_eq(agents.length(), 3)
  assert_eq(agents[0].assignments[0].stage, "已停止")
  assert_eq(agents[1].assignments[0].stage, "执行完成")
  assert_eq(agents[2].assignments[0].stage, "已停止")
  let html = products_test_html(model)
  assert_true(html.contains("迷你办公室地图"))
  assert_true(html.contains("buyer-brief"))
  assert_false(html.contains("Architect-01"))
  assert_false(html.contains("在线" + "率"))
  assert_eq(
    office_agents({ ..model, dispatch_task_actor_id: "other", }).length(),
    0,
  )
  assert_eq(
    office_agents({ ..model, today: { ..model.today, work_state: "loading", }, }).length(),
    0,
  )
}

///|
test "office does not invent a desk for a planned worker confirmed never created" {
  let model = office_test_model()
  let raw = objective_metadata(model.today, "work-1")
  if products_field(raw, "execution") is Object(fields) {
    fields["control_receipt"] = {
      "sessions": [{ "session_id": "worker-2", "state": "missing" }],
    }
  }
  assert_eq(office_agents(model).length(), 2)
  assert_false(office_agents(model).any(agent => agent.name == "handoff"))
}

///|
test "office uses the freshly read canonical task stage instead of the older task list" {
  let model = office_test_model()
  let raw = objective_metadata(model.today, "work-1")
  if raw is Object(fields) {
    fields["status"] = Json::string("submitted")
    fields["taskName"] = Json::string("Updated deliverable")
  }
  let task = office_agents(model)[0].assignments[0].task
  assert_eq(task.status, "submitted")
  assert_eq(task.title, "Updated deliverable")
}

///|
test "office and fleet toggle preserve selected agent and inspection shows real tasks and output" {
  let model = office_test_model()
  let key = office_agents(model)[1].key
  let (_, selected) = office_update(_ => none, model, Select(key))
  assert_eq(selected.office.pending_task, "work-1")
  let (_, observed) = office_update(
    _ => none,
    selected,
    Read(
      selected.today.actor,
      selected.today.epoch,
      selected.today.work_request,
      selected.office.request,
      "work-1",
      200,
      office_test_observation(selected),
    ),
  )
  assert_eq(office_agents(observed)[1].key, key)
  let (_, listed) = office_update(_ => none, observed, View("fleet"))
  assert_eq(listed.office.selected, key)
  let html = products_test_html(listed)
  for
    text in [
      "Agent 编队列表", "Agent 工作详情", "Actual buyer brief", "contribution.md",
      "打开任务", "MoonClaw 专员观察",
    ] {
    assert_true(html.contains(text), msg=text)
  }
  let (_, back) = office_update(_ => none, listed, View("office"))
  assert_eq(back.office.selected, key)
  let (_, closed) = office_update(_ => none, back, Close)
  assert_eq(closed.office.selected, "")
}

///|
test "office stale account scope and superseded replies cannot replace current observation" {
  let model = office_test_model()
  let (_, pending) = office_update(
    _ => none,
    model,
    Select(office_agents(model)[1].key),
  )
  let body = office_test_observation(pending)
  let actions : Array[OfficeMsg] = [
    Read(
      "other",
      pending.today.epoch,
      pending.today.work_request,
      pending.office.request,
      "work-1",
      200,
      body,
    ),
    Read(
      pending.today.actor,
      pending.today.epoch + 1,
      pending.today.work_request,
      pending.office.request,
      "work-1",
      200,
      body,
    ),
    Read(
      pending.today.actor,
      pending.today.epoch,
      pending.today.work_request + 1,
      pending.office.request,
      "work-1",
      200,
      body,
    ),
    Read(
      pending.today.actor,
      pending.today.epoch,
      pending.today.work_request,
      pending.office.request - 1,
      "work-1",
      200,
      body,
    ),
  ]
  for action in actions {
    let (_, unchanged) = office_update(_ => none, pending, action)
    assert_true(unchanged.office.records.is_empty())
    assert_eq(unchanged.office.pending_task, "work-1")
  }
  let (_, failed) = office_update(
    _ => none,
    pending,
    Read(
      pending.today.actor,
      pending.today.epoch,
      pending.today.work_request,
      pending.office.request,
      "work-1",
      503,
      "{}",
    ),
  )
  assert_eq(office_agents(failed).length(), 3)
  assert_false(failed.office.error.is_empty())
}

///|
test "selecting office desk executes only a read and never starts or resumes an agent" {
  setup_transport_start(false)
  defer setup_transport_stop()
  let model = office_test_model()
  let (read, _) = office_update(
    _ => none,
    model,
    Select(office_agents(model)[1].key),
  )
  drafts_test_execute(read)
  assert_eq(setup_transport_events(), "GET /api/company/tasks/work-1/office")
}

///|
test "selecting a cached office task clears another task error and invalidates its pending read" {
  let base = office_test_model()
  let cached = @json.parse(office_test_observation(base))
  let model = {
    ..base,
    office: {
      ..base.office,
      actor: base.today.actor,
      epoch: base.today.epoch,
      source_request: base.today.work_request,
      request: 7,
      pending_task: "other-task",
      error: "Other task is unavailable",
      records: { "work-1": cached },
    },
  }
  let (_, selected) = office_update(
    _ => none,
    model,
    Select(office_agents(model)[1].key),
  )
  assert_eq(selected.office.error, "")
  assert_eq(selected.office.pending_task, "")
  assert_eq(selected.office.request, 8)
  let (_, unchanged) = office_update(
    _ => none,
    selected,
    Read(
      base.today.actor,
      base.today.epoch,
      base.today.work_request,
      7,
      "other-task",
      503,
      "{}",
    ),
  )
  assert_eq(unchanged.office.error, "")
  assert_eq(office_agents(unchanged).length(), 3)
}

///|
test "office company scope keeps exact execution metadata from each successful project" {
  let started = today_flows_update(portfolio_fixture(2), ChooseAll)
  let raw = today_flows_task_json("a", "p0")
  if raw is Object(fields) {
    fields["execution"] = {
      "session_id": "session-a",
      "state": "running",
      "workspace": "/a",
    }
  }
  let first = portfolio_reply(
    started,
    "p0",
    200,
    ({ "items": [raw] } : Json).stringify(),
  )
  let raw2 = today_flows_task_json("b", "p1")
  if raw2 is Object(fields) {
    fields["execution"] = {
      "session_id": "session-b",
      "state": "completed",
      "workspace": "/b",
    }
  }
  let second = portfolio_reply(
    first,
    "p1",
    200,
    ({ "items": [raw2] } : Json).stringify(),
  )
  assert_eq(office_agents({ ..second, page: Fleet, }).length(), 2)
}
