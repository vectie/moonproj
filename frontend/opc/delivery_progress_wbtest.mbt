///|
test "coordinated task route has one progress explanation and a distinct loading state" {
  let model = delivery_progress_test_model()
  let html = products_test_html(model)
  assert_false(html.contains("后端收据是唯一状态真相"))
  assert_false(html.contains("交付一个可验收的正式任务"))
  let loading = products_test_html({
    ..model,
    dispatch_task_stage: "loading",
    dispatch_offer_task: Json::null(),
  })
  assert_true(loading.contains("正在读取这项工作的交付与进展"))
  assert_false(loading.contains("谁在为交付做什么"))
}

///|
test "latest delivery revision is not mistaken for the original command outcome" {
  let base = delivery_progress_test_model()
  let task = match base.dispatch_offer_task {
    Object(f) => f.copy()
    _ => Map([])
  }
  task["execution"] = {
    "revision_request": { "snapshot": { "command_id": "C-new" } },
  }
  task["continuations"] = [
    {
      "command_id": "C-new",
      "state": "failed",
      "error": "Revision actually failed",
    },
  ]
  let model = {
    ..base,
    dispatch_run: Some(dispatch_test_run("completed")),
    dispatch_offer_task: Json::object(task),
  }
  assert_eq(delivery_now(model), "Revision actually failed")
  assert_eq(delivery_stage_label(model), "遇到问题")
  task["continuations"] = []
  assert_eq(delivery_run_state(model), "unknown")
}

///|
fn delivery_progress_test_model() -> Model {
  {
    ..continuation_proj_model(),
    dispatch_task_title: "Review my dissertation",
    dispatch_task_acceptance: "Integrated review, chapter comments and revision plan",
    dispatch_run: Some(dispatch_test_run("running")),
    dispatch_offer_task: {
      "delivery_mode": "coordinated",
      "delivery_progress": {
        "schema": "moonproj.delivery-progress.v1",
        "task_id": "task-1",
        "command_id": "command-1",
        "deliverable": "A chapter-linked dissertation review and revision plan",
        "now": "Checking evidence for the central argument",
        "next": "Integrate the methods findings",
        "needs_user": "Confirm which dissertation version to review",
        "output_path": "review.md",
        "contributions": [
          {
            "worker_id": "methods",
            "responsibility": "Review research methods",
            "contributes_to": "Methods chapter comments and prioritized revisions",
          },
        ],
      },
      "execution": {
        "command_id": "command-1",
        "workers": [
          {
            "worker_id": "methods",
            "child_session_id": "W",
            "child_command_id": "WC",
            "status": "done",
            "terminal": true,
            "summary": "The sampling rationale needs clarification",
            "artifact_references": [{ "path": "methods.md" }],
          },
        ],
      },
    },
  }
}

///|
test "delivery explains the outcome current work and contribution before technical records" {
  let model = delivery_progress_test_model()
  let html = delivery_test_html(model)
  for
    text in [
      "你将收到", "现在", "接下来", "需要你", "A chapter-linked dissertation review",
      "Checking evidence", "Integrate the methods", "Confirm which dissertation",
      "Review research methods", "Methods chapter comments", "The sampling rationale",
      "当前整合稿", "尚无可查看的整合稿",
    ] {
    assert_true(html.contains(text))
  }
  assert_true(
    html.find("你将收到").unwrap() < html.find("执行记录").unwrap(),
  )
  assert_true(html.contains("不表示已整合、复核或验收"))
  assert_false(html.contains("100%"))
}

///|
test "missing or stale explanations never invent assignments or progress" {
  let base = delivery_progress_test_model()
  for
    note in [
      Json::null(),
      {
        "schema": "moonproj.delivery-progress.v1",
        "task_id": "other",
        "command_id": "command-1",
        "now": "WRONG TASK",
      },
      {
        "schema": "moonproj.delivery-progress.v1",
        "task_id": "task-1",
        "command_id": "old-command",
        "now": "STALE COMMAND",
      },
    ] {
    let model = {
      ..base,
      dispatch_offer_task: {
        "delivery_mode": "coordinated",
        "delivery_progress": note,
      },
    }
    assert_true(delivery_progress(model) is Null)
    let html = delivery_test_html(model)
    assert_false(html.contains("WRONG TASK"))
    assert_false(html.contains("STALE COMMAND"))
    assert_true(html.contains("尚未提供具体工作说明"))
  }
}

///|
test "stopped failed and accepted facts override an optimistic progress note" {
  let base = delivery_progress_test_model()
  let fields = match base.dispatch_offer_task {
    Object(f) => f.copy()
    _ => Map([])
  }
  fields["execution"] = { "control_state": "stopped" }
  let stopped = { ..base, dispatch_offer_task: Json::object(fields), }
  assert_true(delivery_now(stopped).contains("已停止"))
  assert_false(delivery_test_html(stopped).contains("Checking evidence"))
  assert_true(
    delivery_now({
      ..base,
      dispatch_run: Some({
        ..dispatch_test_run("failed"),
        error: "Actual failure",
      }),
    }) ==
    "Actual failure",
  )
  let accepted = { ..base, dispatch_task_stage: "accepted", }
  assert_true(delivery_now(accepted).contains("已验收"))
  let html = delivery_test_html(accepted)
  assert_true(html.contains("当前工作区文件不代表验收时的内容"))
}

///|
test "integrated draft requires both the marked path and exact command artifact" {
  let base = delivery_progress_test_model()
  let run = {
    ..dispatch_test_run("completed"),
    artifacts: [{ path: "review.md", evidence_id: "E", }],
  }
  let model = { ..base, dispatch_run: Some(run), }
  let html = delivery_test_html(model)
  assert_true(html.contains("在 MoonDesk 编辑"))
  assert_false(html.contains("尚无可查看的整合稿"))
  let other = {
    ..model,
    dispatch_run: Some({ ..run, command_id: "old-command", }),
  }
  assert_true(delivery_test_html(other).contains("尚无可查看的整合稿"))
}

///|
test "planned missing workers do not become contribution rows" {
  assert_eq(
    delivery_workers({ "workers": [{ "worker_id": "planned" }] }).length(),
    0,
  )
  assert_eq(
    delivery_workers({
      "workers": [{ "child_session_id": "missing" }],
      "control_receipt": {
        "sessions": [{ "session_id": "missing", "state": "missing" }],
      },
    }).length(),
    0,
  )
}

///|
test "MoonDesk task title hint preserves exact output and return identity" {
  let url = dispatch_desk_title_url(
    "https://desk.example/?work_task=T&command=C&return_to=https%3A%2F%2Fproj.example%2F%3Ftask%3DT",
    "Review dissertation & <notes>",
  )
  assert_true(url.contains("work_title=Review+dissertation+%26+%3Cnotes%3E"))
  assert_true(url.contains("work_task=T&command=C"))
  assert_true(url.contains("return_to=https%3A%2F%2Fproj.example"))
}
