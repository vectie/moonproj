///|
test "Today Overview replaces sample metrics with actual project scope" {
  let html = products_test_html({ ..initial_model(), page: Overview, })
  assert_false(html.contains("14.2 月"))
  assert_false(html.contains("批准 v0.8.0 灰度发布"))
  assert_true(html.contains("今日工作"))
  assert_true(html.contains("公司项目"))
}

///|
fn today_test_task(id : String, due : String, status : String) -> TodayTask {
  {
    id,
    project_id: "project-a",
    title: "Existing " + id,
    owner_id: "",
    owner_name: "",
    due,
    status,
    execution_state: "",
    execution_error: "",
  }
}

///|
test "Today due dates use real UTC calendar dates and never infer missing or timestamp deadlines" {
  for
    value in [
      "", "2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "0000-01-01", "2026-10-05T00:00:00Z",
      "2026-1-05", "not a date",
    ] {
    assert_false(today_date_valid(value), msg=value)
    assert_eq(
      today_attention(
        today_test_task("unknown", value, "pending"),
        "2026-10-05",
      ),
      "",
    )
  }
  assert_true(today_date_valid("2024-02-29"))
  assert_false(today_date_valid("1900-02-29"))
  assert_true(today_date_valid("2000-02-29"))
  assert_eq(
    today_attention(
      today_test_task("late", "2026-10-04", "pending"),
      "2026-10-05",
    ),
    "已逾期",
  )
  assert_eq(
    today_attention(
      today_test_task("today", "2026-10-05", "pending"),
      "2026-10-05",
    ),
    "今日到期",
  )
  assert_eq(
    today_attention(
      today_test_task("later", "2026-10-06", "pending"),
      "2026-10-05",
    ),
    "",
  )
  assert_eq(
    today_attention(
      today_test_task("unknown-clock", "2026-10-04", "pending"),
      "unknown",
    ),
    "",
  )
}

///|
test "Today attention is observed task deadline or blocker and never run-completion acceptance" {
  let task = today_test_task("run", "", "in_progress")
  assert_eq(
    today_attention({ ..task, execution_state: "completed", }, "2026-10-05"),
    "",
  )
  assert_eq(
    today_attention(
      {
        ..task,
        execution_state: "unknown",
        execution_error: "Old untyped text",
      },
      "2026-10-05",
    ),
    "",
  )
  assert_true(
    today_attention({ ..task, execution_state: "failed", }, "2026-10-05").contains(
      "执行失败",
    ),
  )
  assert_true(
    today_attention(
      { ..task, execution_state: "waiting_approval", },
      "2026-10-05",
    ).contains("不代表可批准"),
  )
  assert_true(
    today_attention({ ..task, status: "blocked", }, "2026-10-05").contains(
      "正式任务状态为 blocked",
    ),
  )
}

///|
test "Today orders blockers then overdue then today with deterministic due and id ties" {
  let base = today_initial()
  let state = {
    ..base,
    tasks: [
      today_test_task("z", "", "pending"),
      today_test_task("today-b", "2026-10-05", "pending"),
      today_test_task("today-a", "2026-10-05", "pending"),
      today_test_task("done", "2026-10-01", "done"),
      today_test_task("closed", "2026-10-01", "closed"),
      today_test_task("overdue", "2026-10-04", "pending"),
      {
        ..today_test_task("blocked", "", "in_progress"),
        execution_state: "failed",
      },
      today_test_task("future", "2026-10-06", "unknown-imported-state"),
    ],
  }
  assert_eq(today_queue(state, "2026-10-05").map(task => task.id), [
    "blocked", "overdue", "today-a", "today-b", "future", "z",
  ])
  assert_eq(state.tasks.length(), 8)
}

///|
test "Today view states scope freshness canonical status owner and unknown due without company sample facts" {
  let model = today_flows_ready("actor-a", "project-a", "canonical-task")
  let model = {
    ..model,
    page: Overview,
    today: {
      ..model.today,
      tasks: [
        today_test_task("unassigned", "", "pending"),
        {
          ..today_test_task("assigned", "2026-10-05", "submitted"),
          owner_id: "owner-id",
          owner_name: "Owner Name",
        },
        today_test_task("done", "2026-10-04", "done"),
      ],
    },
  }
  let html = products_test_html(model)
  for
    phrase in [
      "当前范围", "Project A", "project-a", "2026-10-05T12:00:00.000Z", "UTC",
      "未分配", "Owner Name", "owner-id", "到期日期", "未知", "submitted",
      "打开任务详情", "此浏览器的草稿", "未计入正式任务数量",
    ] {
    assert_true(html.contains(phrase), msg=phrase)
  }
  for
    phrase in [
      "14.2 月", "现金跑道", "证据齐全", "可裁决", "Existing done",
    ] {
    assert_false(html.contains(phrase), msg=phrase)
  }
  let failed = {
    ..model,
    today: { ..model.today, tasks: [], work_state: "unavailable", },
  }
  let html = products_test_html(failed)
  assert_true(html.contains("任务数量与队列当前未知"))
  assert_false(html.contains("本项目已读取"))
  assert_false(html.contains("此项目没有正式任务"))
}

///|
test "Today successful empty read is distinct from all completed work" {
  let model = today_flows_ready("actor-a", "project-a", "canonical-task")
  let empty = {
    ..model,
    page: Overview,
    today: { ..model.today, tasks: [], work_state: "empty", },
  }
  assert_true(products_test_html(empty).contains("此项目没有正式任务"))
  let completed = {
    ..model,
    page: Overview,
    today: {
      ..model.today,
      tasks: [today_test_task("completed", "2026-10-05", "done")],
    },
  }
  assert_true(
    products_test_html(completed).contains("本次读取没有未结束工作"),
  )
  assert_false(
    products_test_html(completed).contains("此项目没有正式任务"),
  )
}
