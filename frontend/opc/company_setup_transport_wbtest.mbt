///|
// Actual compiled transport effects run only against this non-networking fixture.
extern "js" fn setup_transport_start(fail_storage : Bool) =
  #| failStorage => {
  #|   const previous = {window: globalThis.window, fetch: globalThis.fetch, setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout};
  #|   const data = new Map();
  #|   const state = {previous, data, events: [], requests: [], timers: new Map(), nextTimer: 0};
  #|   globalThis.__setupTransport = state;
  #|   globalThis.setTimeout = (callback, delay) => { const id = ++state.nextTimer; state.timers.set(id, {callback, delay}); return id; };
  #|   globalThis.clearTimeout = id => state.timers.delete(id);
  #|   globalThis.window = {localStorage: {
  #|     getItem: key => data.get(key) || null,
  #|     setItem: (key, value) => {state.events.push(failStorage ? "storage-failed" : "stored"); if (failStorage) throw Error("denied"); data.set(key, value);}
  #|   }};
  #|   globalThis.fetch = (url, options) => {
  #|     state.events.push(options.method + " " + url);
  #|     const request = {url, options};
  #|     state.requests.push(request);
  #|     return {then: resolve => {request.resolve = resolve; return {catch: reject => {request.reject = reject;}};}};
  #|   };
  #| }

///|
extern "js" fn setup_transport_stop() =
  #| () => {
  #|   const previous = globalThis.__setupTransport.previous;
  #|   if (previous.window === undefined) delete globalThis.window; else globalThis.window = previous.window;
  #|   if (previous.fetch === undefined) delete globalThis.fetch; else globalThis.fetch = previous.fetch;
  #|   globalThis.setTimeout = previous.setTimeout;
  #|   globalThis.clearTimeout = previous.clearTimeout;
  #|   delete globalThis.__setupTransport;
  #| }

///|
extern "js" fn setup_transport_events() -> String =
  #| () => globalThis.__setupTransport.events.join("|")

///|
extern "js" fn setup_transport_request(index : Int) -> String =
  #| index => JSON.stringify(globalThis.__setupTransport.requests[index] || null)

///|
test "compiled company transport persists actor scoped ordinary body before POST with stable header" {
  setup_transport_start(false)
  let model = setup_test_update(
    setup_test_empty(),
    Input("company_name", "Actual company"),
  )
  let messages : Array[Msg] = []
  let emit = fn(msg) {
    messages.push(msg)
    none
  }
  let (store, saving) = company_setup_update(emit, Save("company"), model)
  assert_eq(setup_transport_events(), "")
  drafts_test_execute(store)
  assert_eq(setup_transport_events(), "stored")
  assert_eq(messages.length(), 1)
  let frozen = saving.company_setup.company.request.unwrap()
  assert_true(
    company_setup_read(model.company_setup.actor).contains(frozen.key),
  )
  assert_eq(company_setup_read("other-actor"), "")
  let (post, posting) = update(emit, messages[0], saving)
  assert_eq(posting.company_setup.company.phase, "posting")
  drafts_test_execute(post)
  assert_eq(setup_transport_events(), "stored|POST /api/company/profile")
  let sent = @json.parse(setup_transport_request(0))
  let options = products_field(sent, "options")
  assert_eq(products_text(options, "credentials"), "same-origin")
  assert_eq(
    products_text(products_field(options, "headers"), "Idempotency-Key"),
    frozen.key,
  )
  assert_eq(products_text(options, "body"), company_setup_body(frozen))
  assert_false(setup_transport_request(0).contains("authority"))
  assert_false(setup_transport_request(0).contains("Authorization"))
  let (double, unchanged) = company_setup_update(emit, Save("company"), posting)
  drafts_test_execute(double)
  setup_test_unchanged(unchanged, posting)
  assert_eq(setup_transport_events(), "stored|POST /api/company/profile")
  let (verify, checking) = company_setup_update(
    emit,
    Posted(
      posting.company_setup.actor,
      posting.company_setup.epoch,
      "company",
      frozen.key,
      0,
      "",
    ),
    posting,
  )
  drafts_test_execute(verify)
  assert_eq(checking.company_setup.company.phase, "checking")
  assert_eq(
    setup_transport_events(),
    "stored|POST /api/company/profile|GET /api/company/profile|GET /api/company/business-units/tree",
  )
  setup_transport_stop()
}

///|
test "compiled storage failure aborts POST and actor key encoding is unambiguous" {
  setup_transport_start(true)
  let model = setup_test_update(
    setup_test_empty(),
    Input("company_name", "Actual company"),
  )
  let messages : Array[Msg] = []
  let emit = fn(msg) {
    messages.push(msg)
    none
  }
  let (store, saving) = company_setup_update(emit, Save("company"), model)
  drafts_test_execute(store)
  assert_eq(messages.length(), 1)
  let (after, failed) = update(emit, messages[0], saving)
  drafts_test_execute(after)
  assert_eq(setup_transport_events(), "storage-failed")
  assert_eq(failed.company_setup.company.phase, "failed")
  assert_eq(failed.company_setup.company.request, None)
  setup_transport_stop()
  setup_transport_start(false)
  assert_true(company_setup_write("actor/a", "ordinary"))
  assert_eq(company_setup_read("actor/a"), "ordinary")
  assert_eq(company_setup_read("actor%2Fa"), "")
  assert_false(company_setup_write("", "ordinary"))
  setup_transport_stop()
}

///|
test "compiled project create uses existing endpoint then exact GET and never invokes task or model" {
  setup_transport_start(false)
  let saving = setup_test_project_saving()
  let frozen = saving.company_setup.project.request.unwrap()
  let messages : Array[Msg] = []
  let emit = fn(msg) {
    messages.push(msg)
    none
  }
  drafts_test_execute(
    company_setup_persist(emit, saving.company_setup, "project", frozen.key),
  )
  let (post, posting) = update(emit, messages[0], saving)
  drafts_test_execute(post)
  let sent = @json.parse(setup_transport_request(0))
  assert_eq(products_text(sent, "url"), "/api/company/source/mdm/projects")
  let options = products_field(sent, "options")
  assert_eq(
    products_text(products_field(options, "headers"), "Idempotency-Key"),
    frozen.key,
  )
  assert_eq(products_text(options, "body"), company_setup_body(frozen))
  let body = @json.parse(products_text(options, "body"))
  assert_eq(products_text(body, "projGuid"), frozen.project_id)
  assert_eq(products_text(body, "buGuid"), "imported-unit")
  assert_eq(products_text(body, "projName"), "Actual work")
  assert_false(products_has(body, "product_id"))
  let (verify, checking) = company_setup_update(
    emit,
    Posted(
      posting.company_setup.actor,
      posting.company_setup.epoch,
      "project",
      frozen.key,
      200,
      "{\"success\":true}",
    ),
    posting,
  )
  drafts_test_execute(verify)
  assert_eq(
    setup_transport_events(),
    "stored|POST /api/company/source/mdm/projects|GET /api/company/projects/" +
    frozen.project_id,
  )
  assert_eq(checking.products.project_id, "")
  assert_false(setup_transport_events().contains("/tasks"))
  assert_false(setup_transport_events().contains("/dispatch"))
  assert_false(setup_transport_events().contains("/models"))
  setup_transport_stop()
}

///|
test "compiled refreshed identity reads session without transmitting actor in body or fabricating ERP users" {
  setup_transport_start(false)
  let (read, loading) = company_setup_update(
    _ => none,
    Refresh,
    initial_model(),
  )
  drafts_test_execute(read)
  assert_eq(setup_transport_events(), "GET /api/session")
  assert_eq(loading.company_setup.session_state, "loading")
  let (next, session) = company_setup_update(
    _ => none,
    SessionRead(
      loading.company_setup.session_request,
      200,
      "{\"authenticated\":true,\"actor_id\":\"no-erp-record\"}",
    ),
    loading,
  )
  drafts_test_execute(next)
  assert_eq(session.company_setup.actor, "no-erp-record")
  assert_eq(session.dispatch_task_actor_id, "no-erp-record")
  assert_eq(
    setup_transport_events(),
    "GET /api/session|GET /api/company/profile|GET /api/company/business-units/tree",
  )
  assert_false(setup_transport_events().contains("POST"))
  setup_transport_stop()
}

///|
test "retry storage failure and rejection cannot erase prior uncertain create identity" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    0,
  )
  let request = checking.company_setup.project.request.unwrap()
  let retryable = setup_test_exact(checking, 404, "{}")
  let saving = setup_test_update(retryable, Save("project"))
  let failed = setup_test_update(
    saving,
    Persisted(
      saving.company_setup.actor,
      saving.company_setup.epoch,
      "project",
      request.key,
      false,
    ),
  )
  assert_eq(failed.company_setup.project.request, Some(request))
  assert_eq(failed.company_setup.project.phase, "retryable")
  assert_eq(
    setup_test_update(failed, Input("project_name", "different")).company_setup.project_name,
    "Actual work",
  )
  let posting = setup_test_posting(saving, "project")
  let rejected = setup_test_posted(posting, "project", 401)
  assert_eq(rejected.company_setup.project.request, Some(request))
  assert_eq(rejected.company_setup.project.phase, "checking")
}

///|
test "session error and malformed unit responses never masquerade as empty data" {
  for status in [0, 401, 403, 503] {
    let loading = setup_test_update(initial_model(), Refresh)
    let failed = setup_test_update(
      loading,
      SessionRead(loading.company_setup.session_request, status, "{}"),
    )
    assert_true(failed.company_setup.profile_state != "empty")
    assert_eq(failed.company_setup.actor, "")
    assert_false(failed.company_saved)
  }
  for
    body in [
      "{}", "{\"data\":[]}", "{\"success\":true,\"code\":0,\"data\":false}",
    ] {
    let failed = setup_test_units(setup_test_empty(), 200, body)
    assert_eq(failed.company_setup.units_state, "invalid")
    assert_eq(failed.company_setup.units, [])
  }
}
