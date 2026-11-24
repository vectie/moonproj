///|
// Runs reducer commands only against the existing in-memory browser fixture.
// This proves URL/history/reducer effects, not browser rendering or mounting.
fn page_test_step(model : Model, message : Msg) -> Model {
  let messages : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = message => {
    messages.push(message)
    none
  }
  let (command, next) = update(emit, message, model)
  drafts_test_execute(command)
  let mut current = next
  for index = 0; index < messages.length(); index = index + 1 {
    let (command, next) = update(emit, messages[index], current)
    current = next
    drafts_test_execute(command)
  }
  current
}

///|
extern "js" fn page_test_url() -> String =
  #| () => globalThis.window.location.href

///|
test "task A Products Guide refresh stays Guide with separate read-only task context" {
  drafts_navigation_setup("https://example.test/console?keep=%23value", "uuid")
  let a = page_test_step(drafts_test_valid(), SelectDispatchTask("task-a"))
  let products = page_test_step(a, Navigate(Products))
  let guide = page_test_step(products, Navigate(Guide))
  assert_eq(guide.page, Guide)
  assert_eq(guide.dispatch_task_id, "task-a")
  assert_eq(saved_page_token(), "guide")
  assert_eq(drafts_navigation_metric("pushes"), 3)
  assert_eq(drafts_navigation_metric("length"), 4)
  assert_true(page_test_url().contains("/console?keep=%23value"))
  let before = drafts_navigation_requests()
  let refreshed = page_test_step(initial_model(), saved_page_route())
  assert_eq(refreshed.page, Guide)
  assert_eq(refreshed.dispatch_task_id, "task-a")
  assert_eq(refreshed.dispatch_task_pending_action, "load")
  assert_eq(drafts_navigation_metric("pushes"), 3)
  assert_eq(drafts_navigation_metric("replaces"), 1)
  assert_eq(
    drafts_navigation_requests(),
    before + "|GET /api/company/tasks/task-a",
  )
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    task_id: "task-a",
    run: None,
  }
  let loaded = page_test_step(
    refreshed,
    DispatchTaskLoaded("task-a", refreshed.dispatch_task_selection, snapshot),
  )
  assert_eq(loaded.page, Guide)
  assert_eq(loaded.dispatch_task_title, snapshot.title)
  assert_eq(loaded.dispatch_task_pending_action, "")
  let returned = page_test_step(loaded, Navigate(Dispatch))
  assert_eq(returned.page, Dispatch)
  assert_eq(returned.dispatch_task_id, "task-a")
  assert_eq(returned.dispatch_task_pending_action, "load")
  assert_true(
    drafts_navigation_requests().has_suffix("GET /api/company/tasks/task-a"),
  )
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("PUT"))
  assert_false(drafts_navigation_requests().contains("/dispatch"))
  drafts_navigation_cleanup()
}

///|
test "Back Forward visits Dispatch Products Guide once without duplicate task reads or pushes" {
  drafts_navigation_setup(
    "https://example.test/?task=task-a&page=dispatch", "uuid",
  )
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let a = page_test_step(drafts_test_valid(), saved_page_route())
  let draft = dispatch_active_draft(a).unwrap()
  let products = page_test_step(a, Navigate(Products))
  let guide = page_test_step(products, Navigate(Guide))
  let before = drafts_navigation_requests()
  let again = page_test_step(guide, Navigate(Guide))
  assert_eq(again.page, Guide)
  assert_eq(drafts_navigation_requests(), before)
  assert_eq(drafts_navigation_metric("pushes"), 2)
  assert_eq(drafts_navigation_metric("length"), 3)
  drafts_navigation_move(-1)
  assert_eq(emitted.length(), 1)
  let back_products = page_test_step(again, emitted[0])
  assert_eq(back_products.page, Products)
  assert_eq(back_products.dispatch_task_id, "task-a")
  drafts_navigation_move(-1)
  assert_eq(emitted.length(), 2)
  let back_a = page_test_step(back_products, emitted[1])
  assert_eq(back_a.page, Dispatch)
  assert_eq(back_a.dispatch_task_selection, a.dispatch_task_selection)
  assert_eq(back_a.dispatch_task_pending_action, "load")
  drafts_navigation_move(1)
  let forward_products = page_test_step(back_a, emitted[2])
  drafts_navigation_move(1)
  let forward_guide = page_test_step(forward_products, emitted[3])
  assert_eq(forward_guide.page, Guide)
  assert_eq(dispatch_draft_by_id(forward_guide, draft.id), Some(draft))
  assert_eq(drafts_navigation_metric("pushes"), 2)
  assert_eq(drafts_navigation_metric("length"), 3)
  assert_eq(
    drafts_navigation_requests()
    .split("GET /api/company/tasks/task-a")
    .to_array()
    .length(),
    2,
  )
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}

///|
test "explicit page overrides legacy breadcrumb and malformed pages fall back to Products" {
  for
    query in [
      "page=guide", "page=products", "page=dispatch", "page=unknown", "page=", "page=%E0%A4%A",
      "page=guide&page=dispatch", "page=Guide", "page=%2Fguide",
    ] {
    drafts_navigation_setup("https://example.test/?" + query, "uuid")
    drafts_navigation_legacy("stale-task")
    let restored = page_test_step(initial_model(), saved_page_route())
    let expected = match query {
      "page=guide" => Guide
      "page=dispatch" => Dispatch
      _ => Products
    }
    assert_eq(restored.page, expected)
    assert_eq(restored.dispatch_task_id, "")
    assert_eq(drafts_navigation_metric("pushes"), 0)
    assert_eq(saved_page_token(), page_route_token(expected))
    assert_false(drafts_navigation_requests().contains("/api/company/tasks/"))
    assert_false(drafts_navigation_requests().contains("POST"))
    drafts_navigation_cleanup()
  }
  drafts_navigation_setup(
    "https://example.test/?task=task-a&page=unknown", "uuid",
  )
  let restored = page_test_step(initial_model(), saved_page_route())
  assert_eq(restored.page, Products)
  assert_eq(restored.dispatch_task_id, "task-a")
  assert_eq(saved_page_token(), "products")
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/task-a|GET /api/moonsuite/products",
  )
  drafts_navigation_cleanup()
}

///|
test "every supported page has one bounded reversible token" {
  let pages = [
    Overview,
    Objectives,
    Fleet,
    Dispatch,
    Projects,
    Products,
    MoonSuite,
    Quality,
    Observe,
    Operate,
    Company,
    PolicyRadar,
    Evidence,
    Guide,
    Market,
    Delivery,
    Commerce,
    Finance,
    Assurance,
    Extensions,
  ]
  let tokens : Array[String] = []
  for page in pages {
    let token = page_route_token(page)
    assert_false(tokens.contains(token))
    assert_eq(page_route_parse(token), Some(page))
    tokens.push(token)
  }
  assert_eq(page_route_parse("https://other.example/"), None)
  assert_eq(page_route_parse("../guide"), None)
}

///|
test "blank task cannot override the explicit displayed page or trigger canonical GET" {
  for page in [Products, Dispatch, Guide] {
    drafts_navigation_setup(
      "https://example.test/?page=" + page_route_token(page) + "&task=%20%20",
      "uuid",
    )
    let restored = page_test_step(initial_model(), saved_page_route())
    assert_eq(restored.page, page)
    assert_eq(restored.dispatch_task_id, "")
    assert_eq(dispatch_saved_task(), "")
    assert_false(drafts_navigation_requests().contains("/api/company/tasks/"))
    assert_eq(drafts_navigation_metric("pushes"), 0)
    drafts_navigation_cleanup()
  }
}

///|
test "same page real query history invalidates pending URL callbacks and permits read-only recovery" {
  let page = "https://proj.example/?page=dispatch&task=task-1"
  assert_true(
    anchor_test_browser(page, () => {
      let messages : Array[Msg] = []
      let emit : @rabbita.Emit[Msg] = message => {
        messages.push(message)
        none
      }
      drafts_test_execute(dispatch_history_listener(emit))
      let (store, saving) = dispatch_continuation_update(
        emit,
        Select,
        continuation_proj_model(),
      )
      drafts_test_execute(store)
      let (post, attaching) = update(emit, messages[0], saving)
      drafts_test_execute(post)
      anchor_test_pop(page + "&keep=changed")
      if messages.length() != 2 {
        return false
      }
      let (recover, restored) = update(emit, messages[1], attaching)
      drafts_test_execute(recover)
      if restored.dispatch_continuation.phase != "idle" ||
        !restored.dispatch_continuation.operation_pending ||
        restored.dispatch_continuation.operation !=
        attaching.dispatch_continuation.operation ||
        restored.dispatch_continuation.request <=
        attaching.dispatch_continuation.request {
        return false
      }
      anchor_test_respond(anchor_test_ack(attaching))
      let (_, stale) = update(emit, messages[messages.length() - 1], restored)
      if stale.dispatch_continuation.phase != "idle" ||
        !stale.dispatch_continuation.operation_pending {
        return false
      }
      let (read, loading) = update(emit, ContinuationAction(Refresh), stale)
      drafts_test_execute(read)
      loading.dispatch_continuation.phase == "loading" &&
      loading.dispatch_continuation.operation ==
      attaching.dispatch_continuation.operation &&
      anchor_test_requests() ==
      "POST /api/company/plan/tasks/task-1/continuations|GET /api/company/tasks/task-1/continuations"
    }),
  )
}

///|
test "local draft input persists across page history refresh and explicit resume" {
  drafts_navigation_setup("https://example.test/?page=products", "uuid")
  let prepared = page_test_step(
    products_test_project(products_test_selected("moondesk")),
    ProductsAction(Prepare),
  )
  assert_eq(prepared.page, Dispatch)
  assert_eq(saved_page_token(), "dispatch")
  assert_eq(drafts_navigation_metric("pushes"), 1)
  let actor = { ..prepared, dispatch_task_actor_id: "actor-drafts", }
  let typed = page_test_step(
    actor,
    DraftAction(Input("title", "Keep unsaved text")),
  )
  let typed = page_test_step(
    typed,
    DraftAction(Input("acceptance", "Keep local acceptance")),
  )
  let draft = dispatch_active_draft(typed).unwrap()
  let products = page_test_step(typed, Navigate(Products))
  let guide = page_test_step(products, Navigate(Guide))
  assert_eq(dispatch_active_draft(guide), Some(draft))
  let refreshed = page_test_step(initial_model(), saved_page_route())
  let restored = page_test_step(
    { ..refreshed, dispatch_task_actor_id: "actor-drafts", },
    DraftAction(Restored("actor-drafts", dispatch_read_drafts("actor-drafts"))),
  )
  assert_eq(restored.page, Guide)
  assert_eq(dispatch_draft_by_id(restored, draft.id), Some(draft))
  let resumed = page_test_step(restored, DraftAction(Resume(draft.id)))
  assert_eq(resumed.page, Dispatch)
  assert_eq(saved_page_token(), "dispatch")
  assert_eq(dispatch_active_draft(resumed), Some(draft))
  assert_true(resumed.dispatch_task_form_open)
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}
