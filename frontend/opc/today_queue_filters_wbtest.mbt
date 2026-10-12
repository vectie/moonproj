///|
fn today_filter_fixture() -> Model {
  let all = today_flows_update(
    { ..portfolio_fixture(3), page: Overview, },
    ChooseAll,
  )
  let task = today_test_task("a", "2026-10-05", "pending")
  {
    ..all,
    today: {
      ..all.today,
      project_reads: [
        {
          ..all.today.project_reads[0],
          state: "ready",
          observed_at: "2026-10-06T00:01:00Z",
          tasks: [
            {
              ..task,
              project_id: "p0",
              owner_id: "one",
              owner_name: "Same",
              title: "Review ALPHA",
              execution_state: "blocked",
            },
            {
              ..task,
              id: "b",
              project_id: "p0",
              owner_id: "two",
              owner_name: "Same",
              title: "Review beta",
            },
            {
              ..task,
              id: "c",
              project_id: "p0",
              due: "bad-date",
              title: "Review unassigned",
            },
            { ..task, id: "done", project_id: "p0", status: "done", },
          ],
        },
        {
          ..all.today.project_reads[1],
          state: "ready",
          observed_at: "2026-10-05T23:59:00Z",
          tasks: [
            {
              ..task,
              id: "d",
              project_id: "p1",
              owner_id: "unassigned",
              owner_name: "Same",
              title: "Review ALPHA",
            },
            {
              ..task,
              id: "e",
              project_id: "p1",
              due: "2026-10-07",
              title: "Later",
            },
            { ..task, id: "f", project_id: "p1", due: "", status: "overdue", },
          ],
        },
        { ..all.today.project_reads[2], state: "unavailable", tasks: [], },
      ],
    },
  }
}

///|
fn today_set_filter(model : Model, field : String, value : String) -> Model {
  today_flows_update(
    model,
    Filter(
      model.today.actor,
      model.today.epoch,
      model.today.work_request,
      field,
      value,
    ),
  )
}

///|
fn today_match_ids(model : Model) -> Array[String] {
  today_filtered_queue(model.today).map(task => task.id)
}

///|
test "Today filters observed exact owner IDs including duplicate names and sentinel-like IDs" {
  let model = today_filter_fixture()
  assert_eq(today_observed_owners(model.today), [
    ("id:one", "Same · one"),
    ("id:two", "Same · two"),
    ("id:unassigned", "Same · unassigned"),
  ])
  assert_eq(today_match_ids(today_set_filter(model, "owner", "id:one")), ["a"])
  assert_eq(today_match_ids(today_set_filter(model, "owner", "id:two")), ["b"])
  assert_eq(
    today_match_ids(today_set_filter(model, "owner", "id:unassigned")),
    ["d"],
  )
  assert_eq(today_match_ids(today_set_filter(model, "owner", "unassigned")), [
    "f", "e", "c",
  ])
  assert_eq(today_set_filter(model, "owner", "not-observed").today, model.today)
}

///|
test "Today filters reuse each project observed UTC date and canonical attention and blockers" {
  let model = today_filter_fixture()
  assert_eq(today_match_ids(today_set_filter(model, "due", "overdue")), [
    "a", "b", "f",
  ])
  assert_eq(today_match_ids(today_set_filter(model, "due", "today")), ["d"])
  assert_eq(today_match_ids(today_set_filter(model, "due", "future")), ["e"])
  assert_eq(today_match_ids(today_set_filter(model, "due", "unknown")), [
    "f", "c",
  ])
  assert_eq(today_match_ids(today_set_filter(model, "due", "attention")), [
    "a", "b", "f", "d",
  ])
  assert_eq(today_match_ids(today_set_filter(model, "blocker", "blocked")), [
    "a",
  ])
  assert_eq(
    today_match_ids(today_set_filter(model, "blocker", "unblocked")).length(),
    5,
  )
  let unknown = {
    ..model.today,
    project_reads: model.today.project_reads.map(row => {
      ..row,
      observed_at: "unknown",
    }),
  }
  assert_eq(
    today_filtered_queue({
      ..unknown,
      filters: { ..today_filters_initial(), due: "today", },
    }).length(),
    0,
  )
  assert_eq(
    today_filtered_queue({
      ..unknown,
      filters: { ..today_filters_initial(), due: "unknown", },
    }).length(),
    6,
  )
}

///|
test "Today combined filters clear without changing read coverage or observed totals" {
  let model = today_filter_fixture()
  let combined = today_set_filter(
    today_set_filter(
      today_set_filter(
        today_set_filter(model, "title", "  alpha  "),
        "owner",
        "id:one",
      ),
      "due",
      "overdue",
    ),
    "blocker",
    "blocked",
  )
  assert_eq(today_match_ids(combined), ["a"])
  assert_eq(combined.today.project_reads, model.today.project_reads)
  let empty = today_set_filter(combined, "title", "nothing")
  assert_true(today_match_ids(empty).is_empty())
  let html = products_test_html(empty)
  assert_true(html.contains("已读取 2 / 3"))
  assert_true(html.contains("匹配 0 / 6"))
  assert_true(html.contains("不代表公司没有工作"))
  assert_true(html.contains("部分项目读取失败"))
  assert_eq(
    today_match_ids(today_set_filter(empty, "clear", "")),
    today_match_ids(model),
  )
}

///|
test "Today filter events cannot cross actor read or scope boundaries and never write" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let model = today_filter_fixture()
  let event = Filter(
    model.today.actor,
    model.today.epoch,
    model.today.work_request,
    "title",
    "ALPHA",
  )
  let (cmd, filtered) = update(_ => none, TodayAction(event), model)
  drafts_test_execute(cmd)
  assert_eq(drafts_navigation_requests(), "")
  assert_eq(today_match_ids(filtered), ["a", "d"])
  let refreshed = today_flows_update(filtered, RefreshTasks)
  assert_eq(today_flows_update(refreshed, event).today, refreshed.today)
  let (_, switched) = update(
    _ => none,
    DispatchSessionLoaded("actor-b"),
    filtered,
  )
  assert_eq(switched.today.filters, today_filters_initial())
  assert_eq(today_flows_update(switched, event).today, switched.today)
  let single = today_flows_update(filtered, ChooseProject("p0"))
  assert_eq(single.today.filters, today_filters_initial())
  assert_eq(today_flows_update(single, event).today, single.today)
  let (_, left) = today_reconcile(_ => none, none, {
    ..filtered,
    page: Products,
  })
  assert_eq(left.today.filters, today_filters_initial())
  drafts_navigation_cleanup()
}

///|
test "Today filtered exact navigation preserves an unrelated local draft" {
  drafts_navigation_setup("https://example.test/?view=today", "uuid")
  let fixture = today_filter_fixture()
  let draft = drafts_test_valid()
  let model = {
    ..draft,
    page: Overview,
    dispatch_task_actor_id: fixture.dispatch_task_actor_id,
    today: fixture.today,
  }
  let filtered = today_set_filter(model, "owner", "id:two")
  let original = dispatch_active_draft(filtered).unwrap()
  let (cmd, opened) = update(_ => none, TodayAction(OpenTask("b")), filtered)
  drafts_test_execute(cmd)
  assert_eq(opened.dispatch_task_open_id, "b")
  assert_eq(dispatch_active_draft(opened).unwrap(), original)
  assert_true(drafts_navigation_requests().contains("GET /api/company/tasks/b"))
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}

///|
test "Today filters retain narrowed identity across refresh and reject late read changes" {
  let filtered = today_set_filter(today_filter_fixture(), "owner", "id:one")
  let refreshed = today_flows_update(filtered, RefreshTasks)
  let old = TasksRead(
    filtered.today.actor,
    filtered.today.epoch,
    "p0",
    filtered.today.work_request,
    200,
    today_flows_tasks_body("late", "p0"),
    "2026-10-08T00:00:00Z",
  )
  assert_eq(today_flows_update(refreshed, old).today, refreshed.today)
  let ready = portfolio_reply(
    refreshed,
    "p0",
    200,
    today_flows_tasks_body("new", "p0"),
  )
  assert_eq(ready.today.filters.owner, "id:one")
  assert_true(today_match_ids(ready).is_empty())
  assert_true(
    products_test_html(ready).contains("当前未观察到的负责人"),
  )
  assert_eq(today_match_ids(today_set_filter(ready, "clear", "")), ["new"])
}
