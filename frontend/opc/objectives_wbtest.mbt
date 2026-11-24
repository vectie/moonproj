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
        },
      },
    },
  }
}

///|
test "Today is the default and objective routes remain reversible" {
  assert_eq(initial_model().page, Overview)
  assert_eq(page_route_parse(page_route_token(Objectives)), Some(Objectives))
  let html = products_test_html(initial_model())
  assert_true(html.contains("定义或查看目标"))
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
  assert_true(html.contains("我已核对结果，接受目标"))
  assert_true(html.contains("公司记录 · pending"))
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
