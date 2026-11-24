///|
fn objectives_test_model() -> Model {
  let task = today_test_task("goal-1", "2026-12-15", "pending")
  let child = {
    ..today_test_task("work-1", "2026-12-14", "done"),
    title: "Reviewed integrated output",
  }
  {
    ..initial_model(),
    page: Objectives,
    dispatch_task_actor_id: "founder",
    today: {
      ..today_initial(),
      actor: "founder",
      projects: [{ id: "project-a", name: "Our company", source: "command", }],
      project_id: "project-a",
      project_state: "ready",
      work_state: "ready",
      tasks: [task, child],
      task_metadata: {
        "goal-1": {
          "taskGuid": "goal-1",
          "taskType": "key_node",
          "remarks": "验收标准：Usable company result",
        },
        "work-1": {
          "taskGuid": "work-1",
          "taskType": "task",
          "parentTaskGuid": "goal-1",
          "accepted_report_id": "report-1",
        },
      },
    },
  }
}

///|
test "workspace is the default and objective routes remain reversible" {
  assert_eq(initial_model().page, Workspace)
  assert_eq(page_route_parse(page_route_token(Objectives)), Some(Objectives))
  let html = products_test_html(initial_model())
  assert_true(html.contains("工作如何汇成交付"))
  assert_false(html.contains("11/12 在线"))
}

///|
test "objective and child work share existing signed task transport and survive draft serialization" {
  drafts_navigation_setup("https://example.test/?page=objectives", "uuid")
  defer drafts_navigation_cleanup()
  let model = objectives_test_model()
  let (_, defined) = update(_ => none, TodayAction(NewObjective), model)
  let objective = dispatch_active_draft(defined).unwrap()
  assert_eq(objective.task_type, Some("key_node"))
  assert_eq(objective.owner_id, "founder")
  let body = dispatch_draft_create_body(objective, "founder")
  assert_eq(products_text(body, "task_type"), "key_node")
  assert_eq(products_text(body, "project_id"), "project-a")
  let store : DispatchDraftStore = @json.from_json(
    @json.parse(dispatch_draft_store(defined)),
  )
  assert_eq(store.drafts[0], objective)
  let (_, delegated) = update(
    _ => none,
    TodayAction(DelegateObjective("goal-1")),
    model,
  )
  let child = dispatch_active_draft(delegated).unwrap()
  assert_eq(child.task_type, Some("task"))
  assert_eq(child.parent_task_id, Some("goal-1"))
  assert_eq(child.observed_problem, Some("Existing goal-1"))
  assert_eq(
    products_text(
      dispatch_draft_create_body(child, "founder"),
      "parent_task_id",
    ),
    "goal-1",
  )
  assert_eq(child.workspace, "")
  assert_eq(delegated.page, Objectives)
  assert_eq(child.title, "Existing goal-1")
  assert_eq(child.acceptance, "Usable company result")
  assert_true(child.acceptance.contains("Usable company result"))
  let (_, edit) = update(
    _ => none,
    DraftAction(Input("project_id", "different")),
    delegated,
  )
  assert_eq(dispatch_active_draft(edit).unwrap().project_id, "project-a")
  assert_eq(drafts_navigation_requests(), "")
}

///|
test "objective view connects its accepted child output without inferring objective acceptance" {
  let model = objectives_test_model()
  let html = products_test_html(model)
  assert_true(html.contains("Usable company result"))
  assert_true(html.contains("Reviewed integrated output"))
  assert_true(html.contains("接受此交付结果"))
  assert_false(html.contains("我已核对结果，接受目标"))
  assert_false(html.contains("公司记录 · pending"))
  assert_false(html.contains("Architect-01"))
  assert_false(html.contains("11/12"))
  let (_, accepted) = update(
    _ => none,
    TodayAction(
      ObjectiveAccepted(
        "founder", 0, "project-a", "goal-1", 200, "{\"task\":{\"task_id\":\"goal-1\",\"state\":\"done\"}}",
      ),
    ),
    model,
  )
  assert_eq(accepted.today.work_state, "loading")
  assert_true(accepted.notice.contains("已记录"))
  let (_, failed) = update(
    _ => none,
    TodayAction(ObjectiveAccepted("founder", 0, "project-a", "goal-1", 0, "")),
    model,
  )
  assert_true(failed.notice.contains("尚未确认"))
  assert_eq(failed.today.tasks, model.today.tasks)
}

///|
test "objective workspace selects its delegated work without leaving the goal" {
  let model = objectives_test_model()
  let (_, opened) = update(_ => none, TodayAction(OpenTask("work-1")), model)
  assert_eq(opened.page, Objectives)
  assert_eq(opened.dispatch_task_id, "work-1")
  let html = products_test_html(opened)
  assert_true(html.contains("执行与结果"))
  assert_false(html.contains("准备只读 Book 经验查询"))
  let goals = model.today.tasks.filter(t => objective_is_node(model.today, t))
  assert_eq(objective_current_id(opened, goals), "goal-1")
  let (_, prepared) = update(
    _ => none,
    TodayAction(DelegateObjective("goal-1")),
    model,
  )
  let draft = dispatch_active_draft(prepared).unwrap()
  let (_, confirmed) = dispatch_confirm_draft(_ => none, prepared, draft)
  assert_eq(confirmed.page, Objectives)
  assert_eq(confirmed.dispatch_task_id, draft.task_id)
}

///|
test "a sole project is derived but multiple company projects remain an explicit choice" {
  let model = objectives_test_model()
  let loading = {
    ..model,
    today: { ..model.today, project_id: "", project_state: "loading", },
  }
  let (_, selected) = update(
    _ => none,
    TodayAction(
      ProjectListRead(
        "founder", 0, 0, 200, "{\"items\":[{\"project_id\":\"project-a\",\"project_name\":\"Our company\"}]}",
      ),
    ),
    loading,
  )
  assert_eq(selected.today.project_id, "project-a")
  assert_eq(selected.today.work_state, "loading")
  let (_, choice) = update(
    _ => none,
    TodayAction(
      ProjectListRead(
        "founder", 0, 0, 200, "{\"items\":[{\"project_id\":\"project-a\",\"project_name\":\"A\"},{\"project_id\":\"project-b\",\"project_name\":\"B\"}]}",
      ),
    ),
    loading,
  )
  assert_eq(choice.today.project_id, "")
}

///|
test "objective acceptance needs a specific saved report not merely closed work" {
  let model = objectives_test_model()
  for work in ["", "missing", "goal-1"] {
    let (_, next) = update(
      _ => none,
      TodayAction(AcceptObjective("goal-1", work)),
      model,
    )
    assert_eq(next.notice, model.notice)
  }
  let (_, accepted) = update(
    _ => none,
    TodayAction(AcceptObjective("goal-1", "work-1")),
    model,
  )
  assert_true(accepted.notice.contains("正在保存"))
  assert_eq(accepted.today.tasks[0].status, "pending")
  let metadata = model.today.task_metadata.copy()
  metadata["work-1"] = { "parentTaskGuid": "goal-1" }
  let closed_only = {
    ..model,
    today: { ..model.today, task_metadata: metadata, },
  }
  assert_false(
    products_test_html(closed_only).contains("接受此交付结果"),
  )
  let (_, unchanged) = update(
    _ => none,
    TodayAction(AcceptObjective("goal-1", "work-1")),
    closed_only,
  )
  assert_eq(unchanged.notice, model.notice)
  let submitted = {
    ..closed_only,
    dispatch_task_id: "work-1",
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "report-new",
  }
  assert_eq(objective_result_report(submitted, "work-1"), "report-new")
  let (_, decided) = update(
    _ => none,
    TodayAction(AcceptObjective("goal-1", "work-1")),
    submitted,
  )
  assert_true(decided.notice.contains("正在保存"))
  drafts_navigation_setup(
    "https://example.test/?page=objectives", "objective-rework",
  )
  defer drafts_navigation_cleanup()
  let (_, revision) = update(
    _ => none,
    TodayAction(ReviseObjective("goal-1", "work-1")),
    submitted,
  )
  let draft = dispatch_active_draft(revision).unwrap()
  assert_eq(revision.page, Objectives)
  assert_eq(draft.parent_task_id, Some("goal-1"))
  assert_eq(draft.source_reference, Some("moonproj:report:report-new"))
  assert_eq(revision.today.tasks, model.today.tasks)
}

///|
test "execution guidance and refresh work inside the objective home" {
  let model = { ..guidance_test_model(), page: Objectives, }
  assert_true(dispatch_guidance_editable(model))
  assert_true(products_test_html({ ..model, page: Dispatch, }).length() > 0)
  let (_, refreshed) = update(
    _ => none,
    RefreshDispatchTask(model.dispatch_task_id, model.dispatch_task_selection),
    model,
  )
  assert_eq(refreshed.dispatch_task_pending_action, "load")
  assert_eq(refreshed.page, Objectives)
  let active = { ..continuation_proj_model(), page: Objectives, }
  let (_, preview) = update(_ => none, ContinuationAction(Refresh), active)
  assert_eq(preview.dispatch_continuation.phase, "loading")
}

///|
test "objectives do not delegate closed missing cross-project or unavailable work" {
  let model = objectives_test_model()
  for
    candidate in [
      { ..model, today: { ..model.today, tasks: [], }, },
      { ..model, today: { ..model.today, work_state: "offline", }, },
      { ..model, today: { ..model.today, actor: "another", }, },
      {
        ..model,
        today: {
          ..model.today,
          tasks: [{ ..model.today.tasks[0], status: "done", }],
        },
      },
    ] {
    let (_, next) = update(
      _ => none,
      TodayAction(DelegateObjective("goal-1")),
      candidate,
    )
    assert_true(next.dispatch_drafts.is_empty())
  }
}

///|
test "key nodes cannot accidentally launch agent execution" {
  assert_false(
    dispatch_can_start({
      ..initial_model(),
      dispatch_task_id: "goal-1",
      dispatch_task_stage: "pending",
      dispatch_offer_task: { "taskType": "key_node" },
    }),
  )
}

///|
test "Fleet and Dispatch contain no demonstration workforce or sample task board" {
  for page in [Fleet, Dispatch] {
    let html = products_test_html({ ..initial_model(), page, })
    assert_false(html.contains("Architect-01"))
    assert_false(html.contains("今日留痕 26"))
    assert_false(html.contains("编排参考投影"))
    assert_false(html.contains("T-241"))
  }
}
