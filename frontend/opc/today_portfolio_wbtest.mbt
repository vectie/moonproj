///|
test "Today across projects offers an explicit scope choice" {
  let model = {
    ..today_flows_projects(today_flows_initial("actor-a")),
    page: Overview,
  }
  assert_true(products_test_html(model).contains("跨项目查看"))
}

///|
fn portfolio_fixture(count : Int) -> Model {
  let loading = today_flows_update(today_flows_initial("actor-a"), Refresh)
  let projects : Array[Json] = []
  for n in 0..<count {
    projects.push({
      "project_id": "p" + n.to_string(),
      "project_name": "Project " + n.to_string(),
      "source_kind": "command",
    })
  }
  today_flows_update(
    loading,
    ProjectListRead(
      "actor-a",
      loading.today.epoch,
      loading.today.project_request,
      200,
      ({ "items": projects } : Json).stringify(),
    ),
  )
}

///|
fn portfolio_reply(
  model : Model,
  project : String,
  status : Int,
  body : String,
) -> Model {
  let request = model.today.project_reads
    .filter(row => row.project.id == project)
    .get(0)
    .map(row => row.request)
    .unwrap_or(-1)
  today_flows_update(
    model,
    TasksRead(
      model.today.actor,
      model.today.epoch,
      project,
      request,
      status,
      body,
      "2026-10-06T12:00:00.000Z",
    ),
  )
}

///|
test "Today across projects bounds fanout and starts one waiting read on each terminal reply" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let (cmd, started) = update(
    _ => none,
    TodayAction(ChooseAll),
    portfolio_fixture(5),
  )
  drafts_test_execute(cmd)
  assert_eq(started.today.project_reads.map(row => row.state), [
    "loading", "loading", "loading", "queued", "queued",
  ])
  let requests = drafts_navigation_requests()
  assert_true(requests.contains("project_id=p0"))
  assert_true(requests.contains("project_id=p2"))
  assert_false(requests.contains("project_id=p3"))
  assert_false(requests.contains("POST"))
  let (cmd, next) = update(
    _ => none,
    TodayAction(
      TasksRead(
        "actor-a",
        started.today.epoch,
        "p1",
        started.today.work_request,
        200,
        "{\"items\":[]}",
        "2026-10-06T12:00:00.000Z",
      ),
    ),
    started,
  )
  drafts_test_execute(cmd)
  assert_eq(next.today.project_reads.map(row => row.state), [
    "loading", "empty", "loading", "loading", "queued",
  ])
  assert_true(drafts_navigation_requests().contains("project_id=p3"))
  assert_false(drafts_navigation_requests().contains("project_id=p4"))
  for action in [ChooseAll, RefreshTasks, RetryFailed] {
    let (cmd, repeated) = update(_ => none, TodayAction(action), next)
    drafts_test_execute(cmd)
    assert_eq(repeated.today, next.today)
  }
  assert_false(drafts_navigation_requests().contains("project_id=p4"))
  drafts_navigation_cleanup()
}

///|
test "Today across projects keeps successful scopes visible while failed scopes remain unknown" {
  let started = today_flows_update(portfolio_fixture(3), ChooseAll)
  let one = portfolio_reply(
    started,
    "p0",
    200,
    today_flows_tasks_body("task-a", "p0"),
  )
  let partial = portfolio_reply(one, "p1", 503, "{}")
  let done = portfolio_reply(partial, "p2", 200, "{\"items\":[]}")
  assert_eq(today_portfolio_tasks(done.today).map(task => task.id), ["task-a"])
  assert_eq(done.today.project_reads.map(row => row.state), [
    "ready", "unavailable", "empty",
  ])
  let html = products_test_html({ ..done, page: Overview, })
  assert_true(html.contains("已读取 2 / 3"))
  assert_true(html.contains("部分项目读取失败"))
  assert_true(html.contains("重试失败项目"))
  assert_true(html.contains("Actual task task-a"))
  assert_false(html.contains("本次已列范围读取完成"))
  let retry = today_flows_update(done, RetryFailed)
  assert_eq(retry.today.project_reads.map(row => row.state), [
    "ready", "loading", "empty",
  ])
  assert_eq(today_portfolio_tasks(retry.today).length(), 1)
  assert_eq(
    retry.today.project_reads[0].observed_at,
    done.today.project_reads[0].observed_at,
  )
  let fixed = portfolio_reply(
    retry,
    "p1",
    200,
    today_flows_tasks_body("task-b", "p1"),
  )
  assert_eq(today_portfolio_tasks(fixed.today).length(), 2)
  assert_true(
    products_test_html({ ..fixed, page: Overview, }).contains(
      "本次已列范围读取完成",
    ),
  )
}

///|
test "Today across projects handles empty scope and project-list failures without task reads" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let (cmd, empty) = update(
    _ => none,
    TodayAction(ChooseAll),
    portfolio_fixture(0),
  )
  drafts_test_execute(cmd)
  assert_eq(empty.today.scope, "all")
  assert_eq(empty.today.project_reads.length(), 0)
  assert_eq(drafts_navigation_requests(), "")
  assert_true(
    products_test_html({ ..empty, page: Overview, }).contains(
      "尚未读取任务",
    ),
  )
  let refresh = today_flows_update(empty, Refresh)
  let failed = today_flows_update(
    refresh,
    ProjectListRead(
      "actor-a",
      refresh.today.epoch,
      refresh.today.project_request,
      401,
      "{}",
    ),
  )
  let (cmd, blocked) = update(_ => none, TodayAction(ChooseAll), failed)
  drafts_test_execute(cmd)
  assert_eq(blocked.today.project_reads.length(), 0)
  assert_true(
    products_test_html({ ..blocked, page: Overview, }).contains(
      "项目范围当前未知",
    ),
  )
  assert_eq(drafts_navigation_requests(), "")
  drafts_navigation_cleanup()
}

///|
test "Today across projects rejects stale replies after scope switch refresh and actor change" {
  let all = today_flows_update(portfolio_fixture(3), ChooseAll)
  let stale : TodayMsg = TasksRead(
    "actor-a",
    all.today.epoch,
    "p0",
    all.today.work_request,
    200,
    today_flows_tasks_body("stale", "p0"),
    "old",
  )
  let single = today_flows_update(all, ChooseProject("p0"))
  let ignored = today_flows_update(single, stale)
  assert_eq(ignored.today, single.today)
  let all_again = today_flows_update(single, ChooseAll)
  assert_eq(today_flows_update(all_again, stale).today, all_again.today)
  let refreshed = today_flows_update(all_again, Refresh)
  assert_eq(today_flows_update(refreshed, stale).today, refreshed.today)
  let (_, actor_b) = update(_ => none, DispatchSessionLoaded("actor-b"), all)
  assert_eq(today_flows_update(actor_b, stale).today, actor_b.today)
  let (_, logged_out) = update(_ => none, DispatchSessionLoaded(""), all)
  assert_eq(logged_out.today.project_reads.length(), 0)
  assert_eq(
    today_flows_update(logged_out, ChooseAll).today.project_reads.length(),
    0,
  )
}

///|
test "Today across projects project refresh drops removed projects and fences old callbacks" {
  let all = today_flows_update(portfolio_fixture(3), ChooseAll)
  let first = portfolio_reply(
    all,
    "p0",
    200,
    today_flows_tasks_body("removed-task", "p0"),
  )
  let refresh = today_flows_update(first, Refresh)
  let body = "{\"items\":[{\"project_id\":\"p2\",\"project_name\":\"Remaining\"}],\"diagnostics\":[{\"error\":\"omitted\"}]}"
  let next = today_flows_update(
    refresh,
    ProjectListRead(
      "actor-a",
      refresh.today.epoch,
      refresh.today.project_request,
      200,
      body,
    ),
  )
  assert_eq(next.today.project_reads.map(row => row.project.id), ["p2"])
  assert_eq(next.today.project_reads[0].state, "loading")
  assert_false(next.today.project_note.is_empty())
  let stale = today_flows_update(
    next,
    TasksRead(
      "actor-a",
      all.today.epoch,
      "p1",
      all.today.work_request,
      200,
      today_flows_tasks_body("old", "p1"),
      "old",
    ),
  )
  assert_eq(stale.today, next.today)
}

///|
test "Today across projects treats duplicate canonical IDs as conflicts across every affected scope" {
  let all = today_flows_update(portfolio_fixture(3), ChooseAll)
  let one = portfolio_reply(
    all,
    "p0",
    200,
    today_flows_tasks_body("same", "p0"),
  )
  let two = portfolio_reply(
    one,
    "p1",
    200,
    today_flows_tasks_body("same", "p1"),
  )
  assert_eq(two.today.project_reads.map(row => row.state), [
    "invalid", "invalid", "loading",
  ])
  let three = portfolio_reply(
    two,
    "p2",
    200,
    today_flows_tasks_body("same", "p2"),
  )
  assert_eq(three.today.project_reads.map(row => row.state), [
    "invalid", "invalid", "invalid",
  ])
  assert_eq(today_portfolio_tasks(three.today).length(), 0)
  assert_eq(
    today_flows_update(three, OpenTask("same")).dispatch_task_id,
    three.dispatch_task_id,
  )
  let retry = today_flows_update(three, RetryFailed)
  assert_eq(retry.today.project_reads.map(row => row.state), [
    "loading", "loading", "loading",
  ])
  assert_true(retry.today.project_reads.all(row => row.tasks.is_empty()))
}

///|
test "Today across projects invalid response cannot lower a successful count silently" {
  let all = today_flows_update(portfolio_fixture(2), ChooseAll)
  let one = portfolio_reply(
    all,
    "p0",
    200,
    today_flows_tasks_body("valid", "p0"),
  )
  let broken = portfolio_reply(
    one,
    "p1",
    200,
    today_flows_tasks_body("wrong-project", "p0"),
  )
  assert_eq(broken.today.project_reads[1].state, "invalid")
  assert_eq(today_portfolio_tasks(broken.today).length(), 1)
  let duplicate = portfolio_reply(broken, "p1", 200, "{\"items\":[]}")
  assert_eq(duplicate.today, broken.today)
}

///|
test "Today across projects opens exact task detail and preserves local draft" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let all = today_flows_update(portfolio_fixture(1), ChooseAll)
  let ready = portfolio_reply(
    all,
    "p0",
    200,
    today_flows_tasks_body("task A/&?#", "p0"),
  )
  let typed = drafts_test_valid()
  let model = {
    ..typed,
    dispatch_task_actor_id: "actor-a",
    today: ready.today,
  }
  let original = dispatch_active_draft(model).unwrap()
  let (cmd, opened) = update(
    _ => none,
    TodayAction(OpenTask("task A/&?#")),
    model,
  )
  drafts_test_execute(cmd)
  assert_eq(opened.dispatch_task_open_id, "task A/&?#")
  assert_eq(dispatch_active_draft(opened).unwrap().title, original.title)
  assert_true(
    drafts_navigation_requests().contains(
      "GET /api/company/tasks/" + dispatch_url_encode("task A/&?#"),
    ),
  )
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}

///|
test "Today across projects uses each successful observation date and hides stale rows on full refresh" {
  let all = today_flows_update(portfolio_fixture(2), ChooseAll)
  let one = today_flows_update(
    all,
    TasksRead(
      "actor-a",
      all.today.epoch,
      "p0",
      all.today.work_request,
      200,
      today_flows_tasks_body("earlier", "p0"),
      "2026-10-05T23:59:59.000Z",
    ),
  )
  let two = portfolio_reply(
    one,
    "p1",
    200,
    today_flows_tasks_body("later", "p1"),
  )
  assert_eq(today_portfolio_day(two.today, "p0"), "2026-10-05")
  assert_eq(today_portfolio_day(two.today, "p1"), "2026-10-06")
  assert_eq(today_portfolio_queue(two.today).map(task => task.id), [
    "later", "earlier",
  ])
  let refreshed = today_flows_update(two, RefreshTasks)
  assert_eq(today_portfolio_tasks(refreshed.today).length(), 0)
  assert_true(
    refreshed.today.project_reads.all(row => row.observed_at.is_empty()),
  )
}

///|
test "Today across projects retries one failure in place with distinct attempt and bounded scheduling" {
  let all = today_flows_update(portfolio_fixture(5), ChooseAll)
  let failed = portfolio_reply(all, "p0", 503, "{}")
  assert_eq(failed.today.project_reads.map(row => row.state), [
    "unavailable", "loading", "loading", "loading", "queued",
  ])
  let old_request = failed.today.project_reads[0].request
  let retried = today_flows_update(failed, RetryProject("p0"))
  assert_eq(retried.today.scope, "all")
  assert_eq(retried.today.project_reads.map(row => row.state), [
    "queued", "loading", "loading", "loading", "queued",
  ])
  assert_true(retried.today.project_reads[0].request > old_request)
  let one = portfolio_reply(
    retried,
    "p1",
    200,
    today_flows_tasks_body("good", "p1"),
  )
  assert_eq(one.today.project_reads.map(row => row.state), [
    "loading", "ready", "loading", "loading", "queued",
  ])
  assert_eq(today_portfolio_tasks(one.today).map(task => task.id), ["good"])
  let stale = today_flows_update(
    one,
    TasksRead(
      "actor-a",
      one.today.epoch,
      "p0",
      old_request,
      200,
      today_flows_tasks_body("stale", "p0"),
      "old",
    ),
  )
  assert_eq(stale.today, one.today)
  let duplicate = today_flows_update(one, RetryProject("p0"))
  assert_eq(duplicate.today, one.today)
  let success = portfolio_reply(
    one,
    "p0",
    200,
    today_flows_tasks_body("fixed", "p0"),
  )
  assert_eq(today_portfolio_tasks(success.today).length(), 2)
  assert_eq(success.today.project_reads[4].state, "loading")
}
