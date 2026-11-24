///|
// The stub records browser history and requests, and deliberately never delivers
// a fetch response. Canonical results are delivered explicitly to the reducer.
#cfg(target="js")
extern "js" fn drafts_navigation_setup(url : String, entropy : String) =
  #| (url, entropy) => {
  #|   const state = globalThis.__draftsNavigation = {
  #|     priorWindow: globalThis.window, priorFetch: globalThis.fetch,
  #|     priorNow: Date.now, priorRandom: Math.random,
  #|     priorCrypto: Object.getOwnPropertyDescriptor(globalThis, "crypto"),
  #|     entries: [url], index: 0, pushes: 0, replaces: 0,
  #|     entropyCalls: 0, requests: [], listeners: []
  #|   };
  #|   Date.now = () => 1790928000123;
  #|   Math.random = () => (++state.entropyCalls) / 100000;
  #|   Object.defineProperty(globalThis, "crypto", {
  #|     configurable: true, writable: true,
  #|     value: entropy === "uuid" ? {randomUUID: () => "test-uuid-" + (++state.entropyCalls)} : undefined
  #|   });
  #|   const stored = new Map();
  #|   globalThis.window = {
  #|     location: {href: url},
  #|     localStorage: {
  #|       getItem: key => stored.get(key) || null,
  #|       setItem: (key, value) => stored.set(key, value),
  #|       removeItem: key => stored.delete(key)
  #|     },
  #|     addEventListener: (kind, listener) => {if (kind === "popstate") state.listeners.push(listener);},
  #|     history: {
  #|       pushState: (_, __, next) => {
  #|         const href = String(next);
  #|         state.entries.splice(state.index + 1);
  #|         state.entries.push(href);
  #|         state.index++;
  #|         state.pushes++;
  #|         globalThis.window.location.href = href;
  #|       },
  #|       replaceState: (_, __, next) => {
  #|         const href = String(next);
  #|         state.entries[state.index] = href;
  #|         state.replaces++;
  #|         globalThis.window.location.href = href;
  #|       }
  #|     }
  #|   };
  #|   globalThis.fetch = (url, options) => {
  #|     state.requests.push((options && options.method || "GET") + " " + String(url));
  #|     return {then: () => ({catch: () => {}})};
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn drafts_navigation_cleanup() =
  #| () => {
  #|   const state = globalThis.__draftsNavigation;
  #|   Date.now = state.priorNow;
  #|   Math.random = state.priorRandom;
  #|   if (state.priorCrypto) Object.defineProperty(globalThis, "crypto", state.priorCrypto);
  #|   else delete globalThis.crypto;
  #|   if (state.priorWindow === undefined) delete globalThis.window;
  #|   else globalThis.window = state.priorWindow;
  #|   if (state.priorFetch === undefined) delete globalThis.fetch;
  #|   else globalThis.fetch = state.priorFetch;
  #|   delete globalThis.__draftsNavigation;
  #| }

///|
#cfg(target="js")
extern "js" fn drafts_navigation_move(delta : Int32) =
  #| delta => {
  #|   const state = globalThis.__draftsNavigation;
  #|   const next = state.index + delta;
  #|   if (next < 0 || next >= state.entries.length) return;
  #|   state.index = next;
  #|   globalThis.window.location.href = state.entries[next];
  #|   state.listeners.forEach(listener => listener({type: "popstate"}));
  #| }

///|
#cfg(target="js")
extern "js" fn drafts_navigation_metric(name : String) -> Int32 =
  #| name => name === "length" ? globalThis.__draftsNavigation.entries.length : globalThis.__draftsNavigation[name]

///|
#cfg(target="js")
extern "js" fn drafts_navigation_requests() -> String =
  #| () => globalThis.__draftsNavigation.requests.join("|")

///|
#cfg(target="js")
extern "js" fn drafts_navigation_legacy(value : String) =
  #| value => globalThis.window.localStorage.setItem("moonproj.dispatch.task", value)

///|
#cfg(target="js")
extern "js" fn drafts_navigation_legacy_value() -> String =
  #| () => globalThis.window.localStorage.getItem("moonproj.dispatch.task") || ""

///|
#cfg(target="js")
extern "js" fn drafts_navigation_fresh_url(url : String) =
  #| url => {
  #|   globalThis.window.location.href = url;
  #|   globalThis.__draftsNavigation.entries = [url];
  #|   globalThis.__draftsNavigation.index = 0;
  #| }

///|
fn drafts_navigation_distinct(drafts : Array[DispatchDraft]) -> Bool {
  let draft_ids : Array[String] = []
  let task_ids : Array[String] = []
  let keys : Array[String] = []
  for draft in drafts {
    if draft_ids.contains(draft.id) ||
      task_ids.contains(draft.task_id) ||
      keys.contains(draft.idempotency_key) {
      return false
    }
    if !draft.id.has_prefix("draft-1790928000123-") ||
      !draft.task_id.has_prefix("OPC-TASK-1790928000123-") ||
      !draft.idempotency_key.has_prefix("opc-dispatch-create-1790928000123-") {
      return false
    }
    draft_ids.push(draft.id)
    task_ids.push(draft.task_id)
    keys.push(draft.idempotency_key)
  }
  true
}

///|
test "frozen Date now still creates distinct New identities through UUID and fallback entropy" {
  for entropy in ["uuid", "fallback"] {
    drafts_navigation_setup("https://example.test/", entropy)
    let first = drafts_test_valid()
    let original = dispatch_active_draft(first).unwrap()
    let mut model = first
    for _ in 0..<8 {
      model = drafts_test_update(model, New)
    }
    assert_eq(model.dispatch_drafts.length(), 9)
    assert_true(drafts_navigation_distinct(model.dispatch_drafts))
    assert_eq(drafts_navigation_metric("entropyCalls"), 9)
    assert_eq(dispatch_draft_by_id(model, original.id), Some(original))
    assert_true(
      model.dispatch_drafts.all(draft => draft.product_id == original.product_id),
    )
    assert_true(
      model.dispatch_drafts.all(draft => draft.project_id == original.project_id),
    )
    assert_eq(drafts_navigation_requests(), "")
    drafts_navigation_cleanup()
  }
}

///|
test "repeated Revise in one frozen millisecond preserves rejected request and allocates distinct identities" {
  for entropy in ["uuid", "fallback"] {
    drafts_navigation_setup("https://example.test/", entropy)
    let creating = drafts_test_creating()
    let original = dispatch_active_draft(creating).unwrap()
    let rejected = drafts_test_update(
      creating,
      CreateRead(
        "actor-drafts",
        original.id,
        422,
        "{\"error\":\"revise acceptance\"}",
      ),
    )
    let retained = dispatch_active_draft(rejected).unwrap()
    let mut model = rejected
    for _ in 0..<6 {
      model = drafts_test_update(model, Revise(original.id))
    }
    assert_eq(model.dispatch_drafts.length(), 7)
    assert_true(drafts_navigation_distinct(model.dispatch_drafts))
    assert_eq(drafts_navigation_metric("entropyCalls"), 7)
    assert_eq(dispatch_draft_by_id(model, original.id), Some(retained))
    for draft in model.dispatch_drafts {
      assert_eq(draft.title, original.title)
      assert_eq(draft.acceptance, original.acceptance)
      assert_eq(draft.product_snapshot, original.product_snapshot)
      assert_eq(draft.workspace, original.workspace)
      if draft.id != original.id {
        assert_eq(draft.state, "editing")
        assert_false(draft.attempted)
      }
    }
    assert_true(model.dispatch_recent_tasks.contains(original.task_id))
    assert_eq(drafts_navigation_requests(), "")
    drafts_navigation_cleanup()
  }
}

///|
test "frozen clock reload and exact 404 retry never allocate a replacement identity" {
  drafts_navigation_setup("https://example.test/", "uuid")
  let creating = drafts_test_creating()
  let original = dispatch_active_draft(creating).unwrap()
  assert_true(
    dispatch_write_drafts("actor-drafts", dispatch_draft_store(creating)),
  )
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", dispatch_read_drafts("actor-drafts")),
  )
  let resumed = drafts_test_update(restored, Resume(original.id))
  let recovering = drafts_test_update(resumed, Create)
  let retryable = drafts_test_update(
    recovering,
    RecoveryRead("actor-drafts", original.id, 404, "{}"),
  )
  let saving = drafts_test_update(retryable, Create)
  let retry = drafts_test_update(
    saving,
    Stored("actor-drafts", original.id, true),
  )
  let retained = dispatch_active_draft(retry).unwrap()
  assert_eq(retained.id, original.id)
  assert_eq(retained.task_id, original.task_id)
  assert_eq(retained.idempotency_key, original.idempotency_key)
  assert_eq(
    dispatch_draft_create_body(retained, "actor-drafts"),
    dispatch_draft_create_body(original, "actor-drafts"),
  )
  assert_eq(drafts_navigation_metric("entropyCalls"), 1)
  assert_eq(retry.dispatch_drafts.length(), 1)
  drafts_navigation_cleanup()
}

///|
test "explicit Select task pushes A then B while repeated selection replaces without new history entry" {
  drafts_navigation_setup("https://example.test/?view=products", "uuid")
  let ready = drafts_test_valid()
  let draft = dispatch_active_draft(ready).unwrap()
  let task_a = "task A/&?#"
  let (open_a, a) = update(_ => none, SelectDispatchTask(task_a), ready)
  drafts_test_execute(open_a)
  assert_eq(dispatch_saved_task(), task_a)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(drafts_navigation_metric("replaces"), 0)
  assert_eq(drafts_navigation_metric("length"), 2)
  assert_eq(a.dispatch_task_id, task_a)
  assert_eq(a.dispatch_task_stage, "loading")
  let (open_b, b) = update(_ => none, SelectDispatchTask("task-b"), a)
  drafts_test_execute(open_b)
  assert_eq(dispatch_saved_task(), "task-b")
  assert_eq(drafts_navigation_metric("pushes"), 2)
  assert_eq(drafts_navigation_metric("length"), 3)
  assert_eq(b.dispatch_task_selection, a.dispatch_task_selection + 1)
  let (repeat_b, repeated) = update(_ => none, SelectDispatchTask("task-b"), b)
  drafts_test_execute(repeat_b)
  assert_eq(drafts_navigation_metric("pushes"), 2)
  assert_eq(drafts_navigation_metric("replaces"), 1)
  assert_eq(drafts_navigation_metric("length"), 3)
  assert_eq(repeated.dispatch_task_id, "task-b")
  assert_eq(dispatch_draft_by_id(repeated, draft.id), Some(draft))
  assert_false(repeated.dispatch_task_form_open)
  assert_eq(repeated.dispatch_run, None)
  assert_eq(repeated.dispatch_task_pending_action, "load")
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/" +
    dispatch_url_encode(task_a) +
    "|GET /api/company/tasks/task-b|GET /api/company/tasks/task-b",
  )
  drafts_navigation_cleanup()
}

///|
test "boot Back and Forward restore exact task through replaceState and never POST or Start" {
  let task_a = "task A/&?#"
  drafts_navigation_setup(
    "https://example.test/?task=" + dispatch_url_encode(task_a),
    "uuid",
  )
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let ready = drafts_test_valid()
  let draft = dispatch_active_draft(ready).unwrap()
  let (boot, a) = update(
    _ => none,
    RestoreDispatchTask(dispatch_saved_task()),
    ready,
  )
  drafts_test_execute(boot)
  assert_eq(a.dispatch_task_id, task_a)
  assert_eq(drafts_navigation_metric("pushes"), 0)
  assert_eq(drafts_navigation_metric("replaces"), 1)
  assert_eq(drafts_navigation_metric("length"), 1)
  let (select_b, b) = update(_ => none, SelectDispatchTask("task-b"), a)
  drafts_test_execute(select_b)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(drafts_navigation_metric("length"), 2)
  drafts_navigation_move(-1)
  assert_eq(emitted.length(), 1)
  assert_true(emitted[0] is RestorePageRoute(Dispatch, id) && id == task_a)
  let (back, back_a) = update(_ => none, emitted[0], b)
  drafts_test_execute(back)
  assert_eq(back_a.dispatch_task_id, task_a)
  assert_eq(dispatch_saved_task(), task_a)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(drafts_navigation_metric("replaces"), 2)
  assert_eq(back_a.dispatch_task_selection, b.dispatch_task_selection + 1)
  let old_snapshot = {
    ..dispatch_test_snapshot("completed"),
    task_id: task_a,
    run: Some({ ..dispatch_test_run("completed"), task_id: task_a, }),
  }
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded(task_a, a.dispatch_task_selection, old_snapshot),
    back_a,
  )
  assert_eq(stale.dispatch_task_pending_action, "load")
  assert_eq(stale.dispatch_run, None)
  drafts_navigation_move(1)
  assert_eq(emitted.length(), 2)
  assert_true(emitted[1] is RestorePageRoute(Dispatch, "task-b"))
  let (forward, forward_b) = update(_ => none, emitted[1], stale)
  drafts_test_execute(forward)
  assert_eq(forward_b.dispatch_task_id, "task-b")
  assert_eq(dispatch_saved_task(), "task-b")
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(drafts_navigation_metric("replaces"), 3)
  assert_eq(drafts_navigation_metric("length"), 2)
  assert_eq(forward_b.dispatch_task_stage, "loading")
  assert_eq(forward_b.dispatch_task_pending_action, "load")
  assert_eq(forward_b.dispatch_run, None)
  assert_eq(dispatch_draft_by_id(forward_b, draft.id), Some(draft))
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/" +
    dispatch_url_encode(task_a) +
    "|GET /api/company/tasks/task-b|GET /api/company/tasks/" +
    dispatch_url_encode(task_a) +
    "|GET /api/company/tasks/task-b",
  )
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("/dispatch"))
  drafts_navigation_cleanup()
}

///|
test "Back to product route parks draft without creating or starting and Forward restores selected task" {
  drafts_navigation_setup("https://example.test/?view=products", "uuid")
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let ready = drafts_test_valid()
  let draft = dispatch_active_draft(ready).unwrap()
  let (boot, product_route) = update(
    _ => none,
    RestoreDispatchTask(dispatch_saved_task()),
    ready,
  )
  drafts_test_execute(boot)
  assert_eq(product_route.page, Workspace)
  assert_eq(drafts_navigation_requests(), "")
  let (select, a) = update(
    _ => none,
    SelectDispatchTask("task-a"),
    product_route,
  )
  drafts_test_execute(select)
  drafts_navigation_move(-1)
  assert_true(emitted[0] is RestoreDispatchTask(""))
  let (back, products) = update(_ => none, emitted[0], a)
  drafts_test_execute(back)
  assert_eq(products.page, Workspace)
  assert_eq(products.dispatch_task_id, "")
  assert_eq(products.dispatch_task_pending_action, "")
  assert_eq(products.dispatch_run, None)
  assert_false(products.dispatch_task_form_open)
  assert_eq(dispatch_draft_by_id(products, draft.id), Some(draft))
  assert_eq(drafts_navigation_requests(), "GET /api/company/tasks/task-a")
  drafts_navigation_move(1)
  assert_true(emitted[1] is RestorePageRoute(Dispatch, "task-a"))
  let (forward, restored) = update(_ => none, emitted[1], products)
  drafts_test_execute(forward)
  assert_eq(restored.page, Dispatch)
  assert_eq(restored.dispatch_task_id, "task-a")
  assert_eq(restored.dispatch_task_stage, "loading")
  assert_eq(dispatch_draft_by_id(restored, draft.id), Some(draft))
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(drafts_navigation_metric("replaces"), 1)
  assert_eq(drafts_navigation_metric("length"), 2)
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/task-a|GET /api/company/tasks/task-a",
  )
  drafts_navigation_cleanup()
}

///|
test "Prepare during actual canonical loading survives failed read and exact successful result" {
  let ready = products_test_project(products_test_selected("moondesk"))
  let (_, loading) = update(_ => none, SelectDispatchTask("task-1"), ready)
  assert_eq(loading.dispatch_task_stage, "loading")
  assert_eq(loading.dispatch_task_pending_action, "load")
  assert_eq(loading.dispatch_run, None)
  let prepared = products_test_update(loading, Prepare)
  let typed = drafts_test_update(
    drafts_test_update(prepared, Input("title", "B while A is loading")),
    Input("acceptance", "Keep this local acceptance"),
  )
  let draft = dispatch_active_draft(typed).unwrap()
  assert_eq(typed.dispatch_task_id, "task-1")
  assert_eq(typed.dispatch_task_stage, "loading")
  assert_eq(typed.dispatch_task_selection, loading.dispatch_task_selection)
  assert_true(typed.dispatch_task_form_open)
  let (_, failed) = update(
    _ => none,
    DispatchTaskCommandFailed(
      "task-1",
      loading.dispatch_task_selection,
      "读取任务",
      "offline",
    ),
    typed,
  )
  assert_true(failed.dispatch_task_blocked)
  assert_eq(dispatch_active_draft(failed), Some(draft))
  assert_eq(failed.dispatch_task_stage, "loading")
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    product_id: "moonbook",
    title: "Canonical A result",
  }
  let (_, loaded) = update(
    _ => none,
    DispatchTaskLoaded("task-1", loading.dispatch_task_selection, snapshot),
    failed,
  )
  assert_eq(loaded.dispatch_task_title, "Canonical A result")
  assert_eq(loaded.dispatch_task_product_id, "moonbook")
  assert_eq(loaded.dispatch_task_stage, "in_progress")
  assert_eq(loaded.dispatch_task_pending_action, "")
  assert_false(loaded.dispatch_task_blocked)
  assert_eq(loaded.dispatch_run, snapshot.run)
  assert_eq(dispatch_active_draft(loaded), Some(draft))
  assert_true(loaded.dispatch_task_form_open)
  assert_eq(loaded.products.prepared_product_id, "moondesk")
  assert_eq(
    dispatch_draft_form_model(loaded).dispatch_task_title,
    "B while A is loading",
  )
  let html = products_test_html(loaded)
  assert_true(html.contains("Canonical A result"))
  assert_true(html.contains("B while A is loading"))
  assert_true(html.contains("Keep this local acceptance"))
}

///|
test "fresh root restores latest legacy breadcrumb after A to B without inferring account or product" {
  drafts_navigation_setup("https://example.test/?task=url-first", "uuid")
  drafts_navigation_legacy("stale-original-task")
  assert_eq(dispatch_saved_task(), "url-first")
  let ready = drafts_test_valid()
  let draft = dispatch_active_draft(ready).unwrap()
  let (select_a, a) = update(_ => none, SelectDispatchTask("task-a"), ready)
  drafts_test_execute(select_a)
  assert_eq(drafts_navigation_legacy_value(), "task-a")
  let (select_b, b) = update(_ => none, SelectDispatchTask("task-b"), a)
  drafts_test_execute(select_b)
  assert_eq(drafts_navigation_legacy_value(), "task-b")
  assert_eq(dispatch_saved_task(), "task-b")
  let scoped_text = dispatch_read_drafts("actor-drafts")
  let scoped : DispatchDraftStore = @json.from_json(@json.parse(scoped_text))
  assert_eq(scoped.recent_tasks, ["task-b", "task-a"])
  assert_eq(scoped.drafts, [draft])
  assert_eq(b.dispatch_recent_tasks, scoped.recent_tasks)
  drafts_navigation_fresh_url("https://example.test/")
  assert_eq(dispatch_saved_task(), "task-b")
  let (restore, fresh) = update(
    _ => none,
    RestoreDispatchTask(dispatch_saved_task()),
    initial_model(),
  )
  drafts_test_execute(restore)
  assert_eq(fresh.dispatch_task_id, "task-b")
  assert_eq(fresh.dispatch_task_stage, "loading")
  assert_eq(fresh.dispatch_task_actor_id, "")
  assert_eq(fresh.dispatch_task_product_id, "")
  assert_eq(fresh.dispatch_task_project_id, "")
  assert_eq(fresh.dispatch_report_product_id, "")
  assert_eq(fresh.dispatch_drafts, [])
  assert_eq(fresh.products.prepared_product_id, "")
  assert_eq(dispatch_read_drafts("actor-drafts"), scoped_text)
  assert_eq(
    drafts_navigation_requests(),
    "GET /api/company/tasks/task-a|GET /api/company/tasks/task-b|GET /api/company/tasks/task-b",
  )
  drafts_navigation_fresh_url("https://example.test/?task=")
  assert_eq(dispatch_saved_task(), "")
  assert_eq(drafts_navigation_legacy_value(), "task-b")
  dispatch_store_task("", false)
  assert_eq(drafts_navigation_legacy_value(), "")
  assert_eq(dispatch_saved_task(), "")
  assert_eq(dispatch_read_drafts("actor-drafts"), scoped_text)
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("/dispatch"))
  drafts_navigation_cleanup()
}
