///|
fn workspace_test_model() -> Model {
  let base = objectives_test_model()
  let first = { ..today_test_task("work-1", "", "pending"), title: "1 · 研究计划：核对方法", }
  let second = { ..first, id: "work-2", title: "2 · 开题答辩：核对讲稿", }
  let third = { ..first, id: "work-3", title: "3 · 学位论文：核对证据", }
  {
    ..base, page: Workspace, workspace: workspace_initial(),
    today: {
      ..base.today,
      tasks: [base.today.tasks[0], third, first, second],
      task_metadata: {
        "goal-1": { "taskType": "key_node", "remarks": "可追溯的最终论文", },
        "work-1": { "taskType": "task", "parentTaskGuid": "goal-1", "sortOrder": 1, "source_context": { "reference": "http://127.0.0.1:4201/?workspace=book-research&activity=wiki&path=wiki/proposal.md" }, },
        "work-2": { "taskType": "task", "parentTaskGuid": "goal-1", "sortOrder": 2, },
        "work-3": { "taskType": "task", "parentTaskGuid": "goal-1", "sortOrder": 3, },
      },
    },
  }
}

///|
test "workspace is the default and all existing routes remain available" {
  assert_eq(initial_model().page, Workspace)
  assert_eq(page_route_parse("workspace"), Some(Workspace))
  assert_eq(page_route_parse(page_route_token(Objectives)), Some(Objectives))
  assert_eq(page_route_parse("dispatch"), Some(Dispatch))
}

///|
test "dock jobs are real regular tasks in explicit order, never goal-as-agent apps" {
  let model = workspace_test_model()
  assert_eq(workspace_jobs(model).map(t => t.id), ["work-1", "work-2", "work-3"])
  let html = products_test_html(model)
  assert_true(html.contains("工作应用 Dock"))
  assert_true(html.contains("工作如何汇成交付"))
  assert_true(html.contains("data-parent=\"goal-1\""))
  assert_true(html.contains("任务顺序不代表执行依赖"))
  assert_false(html.contains("data-dock-job=\"goal-1\""))
  assert_eq(workspace_job_name("2 · 开题答辩：核对讲稿"), "2 · 开题答辩")
  assert_true(workspace_jobs({ ..model, dispatch_task_actor_id: "other", }).is_empty())
}

///|
test "execution end and worker completion cannot become accepted delivery" {
  let task = workspace_jobs(workspace_test_model())[0]
  assert_eq(workspace_stage({ "execution": { "state": "completed" } }, task), "review")
  assert_eq(workspace_stage({ "execution": { "state": "running", "control_state": "stopped" } }, task), "stopped")
  assert_eq(workspace_stage({ "execution": { "state": "completed", "control_state": "revising" } }, task), "revising")
  assert_eq(workspace_stage({ "selected_delivery_source": { "type": "continuation", "command_id": "missing" } }, task), "unknown")
  assert_eq(workspace_stage({ "accepted_report_id": "R" }, task), "accepted")
  assert_eq(workspace_stage({}, { ..task, status: "in_progress", }), "unknown")
}

///|
test "a newer collection revision supersedes an older focused task snapshot" {
  let base = workspace_test_model()
  let task = workspace_jobs(base)[0]
  let metadata = base.today.task_metadata.copy()
  metadata[task.id] = { "revision": 4, "execution": { "state": "completed" } }
  let model = { ..base, dispatch_task_id: task.id, dispatch_task_project_id: task.project_id,
    dispatch_offer_task: { "revision": 3, "execution": { "state": "running" } },
    today: { ..base.today, task_metadata: metadata, }, }
  assert_eq(workspace_stage(workspace_record(model, task), task), "review")
}

///|
test "only a goal's exact selected report is a contribution receipt" {
  let base = workspace_test_model()
  let task = workspace_jobs(base)[0]
  assert_eq(workspace_receipt(base, task), "")
  let metadata = base.today.task_metadata.copy()
  metadata["goal-1"] = { "taskType": "key_node", "objective_result": { "task_id": "work-2", "report_id": "R2" } }
  let model = { ..base, today: { ..base.today, task_metadata: metadata, }, }
  assert_eq(workspace_receipt(model, task), "")
  assert_eq(workspace_receipt(model, workspace_jobs(model)[1]), "R2")
}

///|
test "opening and minimizing job apps only select and read, never start or stop work" {
  drafts_navigation_setup("https://example.test/?page=workspace", "dock")
  defer drafts_navigation_cleanup()
  let (command, opened) = update(_ => none, WorkspaceAction(Focus("work-1")), workspace_test_model())
  drafts_test_execute(command)
  assert_eq(opened.page, Workspace)
  assert_eq(opened.workspace.job, "work-1")
  assert_eq(opened.dispatch_task_pending_action, "load")
  assert_true(drafts_navigation_requests().contains("GET /api/company/tasks/work-1"))
  assert_false(drafts_navigation_requests().contains("POST"))
  let (command, flow) = update(_ => none, WorkspaceAction(Flow), opened)
  drafts_test_execute(command)
  assert_eq(flow.workspace.job, "")
  assert_eq(flow.dispatch_task_id, "work-1")
  assert_eq(flow.dispatch_task_selection, opened.dispatch_task_selection)
  assert_false(drafts_navigation_requests().contains("stop"))
  let (_, untouched) = update(_ => none, WorkspaceAction(Focus("missing")), flow)
  assert_eq(untouched.workspace.job, "")
}

///|
test "workspace deep links restore exactly one job, without moving into legacy Dispatch" {
  drafts_navigation_setup("https://example.test/?page=workspace&task=work-2", "dock")
  defer drafts_navigation_cleanup()
  let (_, model) = restore_page_route(_ => none, Workspace, "work-2", workspace_test_model())
  assert_eq(model.page, Workspace)
  assert_eq(model.workspace.job, "work-2")
  assert_eq(model.dispatch_task_id, "work-2")
  assert_true(dispatch_work_page(model))
  assert_eq(workspace_current_job({ ..model, workspace: { ..model.workspace, job: "missing", pane: "progress", }, }), None)
}

///|
test "quiet flow refresh retains jobs and stale callbacks cannot replace the current company" {
  let base = workspace_test_model()
  let base = { ..base, today: { ..base.today, observed_at: "2026-11-24T12:00:00Z", }, }
  let (_, loading) = workspace_update(_ => none, base, Refresh)
  assert_eq(loading.today.work_state, "loading")
  assert_eq(workspace_jobs(loading).length(), 3)
  let (_, failed) = today_update(_ => none, TasksRead("founder", loading.today.epoch, "project-a", loading.today.work_request, 503, "{}", ""), loading)
  assert_eq(workspace_jobs(failed).length(), 3)
  assert_true(products_test_html(failed).contains("保留上次读回的记录"))
  let (_, stale) = workspace_update(_ => none, loading, Tick("founder", base.today.epoch, "project-a", base.today.work_request))
  assert_eq(stale.today.work_request, loading.today.work_request)
  let (_, elsewhere) = workspace_update(_ => none, { ..base, page: Guide, }, Tick("founder", base.today.epoch, "project-a", base.today.work_request))
  assert_eq(elsewhere.today.work_state, "ready")
}

///|
test "legacy destinations retain the app host without duplicating the company flow or dock" {
  let html = products_test_html({ ..workspace_test_model(), page: Guide, })
  assert_true(html.contains("data-job-app-host"))
  assert_false(html.contains("data-dock-job="))
  assert_false(html.contains("class=\"flow-board\""))
}
