///|
#warnings("-alert_unstable")
fn delivery_test_html(model : Model) -> String {
  let cell = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => delivery_work_view(msg => emit(msg), model))
  opc_render_cell(cell)
}

///|
test "imported materials can open before any agent execution" {
  let model = {
    ..objectives_test_model(),
    dispatch_task_source_context: {
      "reference": "http://127.0.0.1:4201/?activity=wiki&workspace=book-research&path=wiki/02-presentation/index.md",
      "problem": "材料已载入，尚未审阅；先核对开题讲稿。",
    },
    dispatch_offer_task: { "delivery_mode": "coordinated" },
    dispatch_run: None,
  }
  let html = delivery_test_html(model)
  assert_true(html.contains("工作材料"))
  assert_true(html.contains("打开工作材料"))
  assert_true(html.contains("book-research"))
  assert_true(html.contains("材料已载入，尚未审阅"))
  assert_true(html.contains("尚未分配专员"))
}

///|
test "coordinated delegation retains explicit mode and limits in the signed create body" {
  drafts_navigation_setup("https://example.test/?page=objectives", "delivery")
  defer drafts_navigation_cleanup()
  let (_, prepared) = update(
    _ => none,
    TodayAction(DelegateObjective("goal-1")),
    objectives_test_model(),
  )
  let draft = dispatch_active_draft(prepared).unwrap()
  assert_eq(draft.delivery_mode, Some("coordinated"))
  let (_, limited) = update(
    _ => none,
    DraftAction(Input("delivery_limits", "No external publishing")),
    prepared,
  )
  let body = dispatch_draft_create_body(
    dispatch_active_draft(limited).unwrap(),
    "founder",
  )
  assert_eq(dispatch_json_text(body, "delivery_mode"), "coordinated")
  assert_eq(
    dispatch_json_text(body, "delivery_limits"),
    "No external publishing",
  )
}

///|
test "coordinated work shows artifacts and real controls without Submit ceremony" {
  let model = {
    ..continuation_proj_model(),
    page: Objectives,
    dispatch_offer_task: {
      "delivery_mode": "coordinated",
      "execution": {
        "control_state": "stopping",
        "control_error": "Disconnected",
        "workers": [{ "worker_id": "review", "status": "running" }],
      },
    },
  }
  let html = delivery_test_html(model)
  assert_true(html.contains("停止待确认"))
  assert_true(html.contains("Disconnected"))
  assert_true(html.contains("谁在为交付做什么"))
  assert_false(html.contains("Submit ·"))
  assert_false(dispatch_can_start(model))
  assert_true(delivery_pollable(model))
  let stopped = {
    ..model,
    dispatch_offer_task: {
      "delivery_mode": "coordinated",
      "execution": { "control_state": "stopped" },
    },
  }
  assert_true(delivery_test_html(stopped).contains("继续交付"))
  assert_false(delivery_pollable(stopped))
  let unfinished = {
    ..stopped,
    dispatch_run: Some({ ..dispatch_test_run("running"), summary: "", }),
  }
  assert_true(
    delivery_test_html(unfinished).contains("尚无完整交付产物"),
  )
  assert_true(
    delivery_test_html(unfinished).contains("停止前的执行记录"),
  )
  assert_eq(
    dispatch_goal_copy({ ..unfinished, dispatch_task_stage: "in_progress", }),
    "交付已停止；已有结果保留。",
  )
  assert_true(
    dispatch_goal_copy({ ..model, dispatch_task_stage: "in_progress", }).contains(
      "停止待确认",
    ),
  )
  let reading = { ..stopped, dispatch_task_pending_action: "load", }
  assert_true(delivery_test_html(reading).contains("继续交付"))
  let busy = { ..model, dispatch_task_pending_action: "delivery", }
  assert_true(delivery_test_html(busy).contains("正在提交交付操作"))
  assert_false(delivery_test_html(busy).contains("停止这项交付"))
}

///|
test "revision feedback remains under the same delivery rather than adding another task" {
  let base = objectives_test_model()
  let model = {
    ..base,
    dispatch_task_id: "work-1",
    dispatch_offer_task: { "delivery_mode": "coordinated" },
    dispatch_run: Some(dispatch_test_run("completed")),
  }
  let (_, editing) = update(
    _ => none,
    TodayAction(ReviseObjective("goal-1", "work-1")),
    model,
  )
  assert_true(editing.delivery.editing)
  assert_eq(editing.dispatch_drafts, model.dispatch_drafts)
  assert_eq(objective_result_report(editing, "work-1"), "")
}
