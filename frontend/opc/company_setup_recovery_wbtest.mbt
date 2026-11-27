///|
extern "js" fn setup_transport_expire() =
  #| () => {
  #|   const state = globalThis.__setupTransport;
  #|   const timers = [...state.timers.values()];
  #|   for (const timer of timers) {
  #|     if (timer.delay !== 30000) throw Error("unexpected timeout");
  #|     timer.callback();
  #|   }
  #| }

///|
extern "js" fn setup_transport_headers(index : Int32, status : Int32) =
  #| (index, status) => {
  #|   const request = globalThis.__setupTransport.requests[index];
  #|   request.resolve({status, text: () => ({then: resolve => {request.resolveBody = resolve;}})});
  #| }

///|
extern "js" fn setup_transport_body(index : Int32, body : String) =
  #| (index, body) => globalThis.__setupTransport.requests[index].resolveBody(body)

///|
extern "js" fn setup_transport_aborted(index : Int32) -> Bool =
  #| index => !!globalThis.__setupTransport.requests[index].options.signal.aborted

///|
test "genuinely unresolved company POST or response body times out once then reconciles same request" {
  for body_hangs in [false, true] {
    setup_transport_start(false)
    let saving = setup_test_company_saving()
    let request = saving.company_setup.company.request.unwrap()
    let messages : Array[Msg] = []
    let emit = fn(msg) {
      messages.push(msg)
      none
    }
    let (post, posting) = company_setup_update(
      emit,
      Persisted(
        saving.company_setup.actor,
        saving.company_setup.epoch,
        "company",
        request.key,
        true,
      ),
      saving,
    )
    drafts_test_execute(post)
    assert_eq(messages.length(), 0)
    if body_hangs {
      setup_transport_headers(0, 201)
    }
    assert_eq(messages.length(), 0)
    setup_transport_expire()
    assert_eq(messages.length(), 1)
    assert_true(setup_transport_aborted(0))
    let (verify, checking) = update(emit, messages[0], posting)
    assert_eq(checking.company_setup.company.phase, "checking")
    assert_eq(checking.company_setup.company.request, Some(request))
    assert_false(checking.company_saved)
    if !body_hangs {
      setup_transport_headers(0, 201)
    }
    setup_transport_body(
      0,
      setup_test_profile_body("Real OPC", "ORG-new", "command"),
    )
    assert_eq(messages.length(), 1)
    drafts_test_execute(verify)
    setup_transport_headers(1, 200)
    setup_transport_body(
      1,
      setup_test_profile_body("Real OPC", "ORG-new", "command"),
    )
    setup_transport_headers(2, 200)
    setup_transport_body(2, setup_test_unit_body("ORG-new", "command"))
    assert_eq(messages.length(), 3)
    let canonical = update(emit, messages[1], checking).1
    let confirmed = update(emit, messages[2], canonical).1
    assert_true(confirmed.company_saved)
    assert_eq(confirmed.company_setup.company.phase, "confirmed")
    setup_transport_expire()
    assert_eq(messages.length(), 3)
    setup_transport_stop()
  }
}

///|
test "genuinely unresolved project exact read releases checking and stale body cannot select" {
  setup_transport_start(false)
  let posting = setup_test_posting(setup_test_project_saving(), "project")
  let request = posting.company_setup.project.request.unwrap()
  let messages : Array[Msg] = []
  let emit = fn(msg) {
    messages.push(msg)
    none
  }
  let (verify, checking) = company_setup_update(
    emit,
    Posted(
      posting.company_setup.actor,
      posting.company_setup.epoch,
      "project",
      request.key,
      200,
      "{}",
    ),
    posting,
  )
  drafts_test_execute(verify)
  setup_transport_headers(0, 200)
  assert_eq(messages.length(), 0)
  setup_transport_expire()
  assert_eq(messages.length(), 1)
  let uncertain = update(emit, messages[0], checking).1
  assert_eq(uncertain.company_setup.project.phase, "uncertain")
  assert_eq(uncertain.company_setup.project.request, Some(request))
  assert_eq(uncertain.products.project_id, "")
  setup_transport_body(0, setup_test_exact_body(request))
  assert_eq(messages.length(), 1)
  let (again, recovery) = company_setup_update(
    emit,
    Recover("project"),
    uncertain,
  )
  drafts_test_execute(again)
  setup_transport_headers(1, 404)
  setup_transport_body(1, "{}")
  let retryable = update(emit, messages[1], recovery).1
  assert_eq(retryable.company_setup.project.phase, "retryable")
  assert_eq(retryable.company_setup.project.request, Some(request))
  let retry = setup_test_posting(
    setup_test_update(retryable, Save("project")),
    "project",
  )
  assert_eq(retry.company_setup.project.request, Some(request))
  setup_transport_stop()
}

///|
test "unresolved session and unit reads settle instead of leaving setup loading forever" {
  setup_transport_start(false)
  let messages : Array[Msg] = []
  let emit = fn(msg) {
    messages.push(msg)
    none
  }
  let (read, loading) = company_setup_update(emit, Refresh, initial_model())
  drafts_test_execute(read)
  setup_transport_expire()
  assert_eq(messages.length(), 1)
  let offline = update(emit, messages[0], loading).1
  assert_eq(offline.company_setup.session_state, "offline")
  assert_false(offline.company_saved)
  setup_transport_headers(0, 200)
  setup_transport_body(
    0, "{\"authenticated\":true,\"actor_id\":\"late-actor\"}",
  )
  assert_eq(messages.length(), 1)
  setup_transport_stop()
}

///|
test "known rejected first project conflict is editable but retry conflict stays recoverable" {
  let first = setup_test_posting(setup_test_project_saving(), "project")
  let rejected = setup_test_posted(first, "project", 409)
  assert_eq(rejected.company_setup.project.request, None)
  assert_eq(rejected.company_setup.project.phase, "failed")
  assert_eq(
    setup_test_update(rejected, Input("project_name", "Corrected")).company_setup.project_name,
    "Corrected",
  )
  let uncertain = setup_test_posted(first, "project", 0)
  let missing = setup_test_exact(uncertain, 404, "{}")
  let retry = setup_test_posting(
    setup_test_update(missing, Save("project")),
    "project",
  )
  let conflict = setup_test_posted(retry, "project", 409)
  assert_eq(conflict.company_setup.project.phase, "checking")
  assert_eq(
    conflict.company_setup.project.request,
    first.company_setup.project.request,
  )
}

///|
test "changed historical project hint may be dismissed without recreating or blocking new work" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let request = checking.company_setup.project.request.unwrap()
  let verified = setup_test_exact(checking, 200, setup_test_exact_body(request))
  let fresh = setup_test_empty()
  let restored = setup_test_update(
    fresh,
    Restored(
      fresh.company_setup.actor,
      fresh.company_setup.epoch,
      company_setup_store(verified.company_setup),
    ),
  )
  let recovery = setup_test_update(restored, Recover("project"))
  let changed = setup_test_exact(
    recovery,
    200,
    setup_test_exact_body({ ..request, name: "Renamed on server", }),
  )
  assert_eq(changed.products.project_id, "")
  assert_true(changed.company_setup.project.recover_only)
  let dismissed = setup_test_update(changed, DismissRecent)
  assert_eq(dismissed.company_setup.project.request, None)
  assert_eq(dismissed.company_setup.recent_project, None)
  assert_true(company_setup_editable(dismissed.company_setup.project))
  assert_eq(dismissed.dispatch_drafts, [])
  setup_test_unchanged(setup_test_update(checking, DismissRecent), checking)
}

///|
test "late created project never overwrites a newer company project choice or list refresh" {
  for action in ["select", "reselect", "refresh"] {
    let saving = setup_test_project_saving()
    let request = saving.company_setup.project.request.unwrap()
    let available = {
      ..saving,
      products: {
        ..saving.products,
        projects: [
          {
            id: "existing-project",
            name: "Existing project",
            source: "imported",
          },
        ],
        project_state: "ready",
      },
    }
    let newer = if action == "refresh" {
      let loading = products_test_update(available, LoadProjects)
      products_test_update(
        loading,
        ProjectsRead(
          loading.products.selected_id,
          loading.products.selection,
          loading.products.project_request,
          200,
          "{\"items\":[{\"project_id\":\"existing-project\",\"project_name\":\"Existing project\",\"source_kind\":\"imported\"}]}",
        ),
      )
    } else {
      let selected = products_test_update(
        available,
        SelectProject("existing-project"),
      )
      if action == "reselect" {
        products_test_update(selected, SelectProject("existing-project"))
      } else {
        selected
      }
    }
    let checking = setup_test_posted(
      setup_test_posting(newer, "project"),
      "project",
      200,
    )
    let late = setup_test_exact(checking, 200, setup_test_exact_body(request))
    assert_eq(late.products.project_id, newer.products.project_id)
    assert_eq(late.products.project_choice, newer.products.project_choice)
    assert_true(late.company_setup.exact_project is Some(_))
    let chosen = setup_test_update(late, UseProject)
    assert_eq(chosen.products.project_id, request.project_id)
    assert_eq(chosen.dispatch_drafts, [])
  }
}

///|
test "older list response cannot replace newer exact create or explicit UseProject selection" {
  let loading = products_test_update(setup_test_project_ready(), LoadProjects)
  let saving = setup_test_update(loading, Save("project"))
  let request = saving.company_setup.project.request.unwrap()
  let verified = setup_test_exact(
    setup_test_posted(setup_test_posting(saving, "project"), "project", 200),
    200,
    setup_test_exact_body(request),
  )
  assert_eq(verified.products.project_id, request.project_id)
  let old_response = ProjectsRead(
    loading.products.selected_id,
    loading.products.selection,
    loading.products.project_request,
    200,
    "{\"items\":[]}",
  )
  let late = products_test_update(verified, old_response)
  setup_test_unchanged(late, verified)
  assert_true(late.products.project_request > loading.products.project_request)
  let second_loading = products_test_update(verified, LoadProjects)
  let chosen = setup_test_update(second_loading, UseProject)
  let second_old_response = ProjectsRead(
    second_loading.products.selected_id,
    second_loading.products.selection,
    second_loading.products.project_request,
    200,
    "{\"items\":[]}",
  )
  setup_test_unchanged(
    products_test_update(chosen, second_old_response),
    chosen,
  )
  assert_true(
    chosen.products.project_request > second_loading.products.project_request,
  )
  assert_eq(chosen.dispatch_drafts, [])
}

///|
test "explicit company project choice invalidates duplicate completed list callbacks" {
  let loading = products_test_update(setup_test_empty(), LoadProjects)
  let loaded = products_test_update(
    loading,
    ProjectsRead(
      loading.products.selected_id,
      loading.products.selection,
      loading.products.project_request,
      200,
      "{\"items\":[{\"project_id\":\"existing-project\",\"project_name\":\"Existing\",\"source_kind\":\"imported\"}]}",
    ),
  )
  let selected = products_test_update(loaded, SelectProject("existing-project"))
  let duplicate = products_test_update(
    selected,
    ProjectsRead(
      loading.products.selected_id,
      loading.products.selection,
      loading.products.project_request,
      200,
      "{\"items\":[]}",
    ),
  )
  setup_test_unchanged(duplicate, selected)
  assert_true(
    selected.products.project_request > loading.products.project_request,
  )
}

///|
test "explicit newer project list refresh still replaces current selection while retaining exact recovery" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let request = checking.company_setup.project.request.unwrap()
  let verified = setup_test_exact(checking, 200, setup_test_exact_body(request))
  let fresh = products_test_update(verified, LoadProjects)
  assert_eq(fresh.products.project_id, "")
  let response = ProjectsRead(
    fresh.products.selected_id,
    fresh.products.selection,
    fresh.products.project_request,
    200,
    "{\"items\":[]}",
  )
  let refreshed = products_test_update(fresh, response)
  assert_eq(refreshed.products.project_state, "empty")
  assert_eq(refreshed.products.projects, [])
  assert_eq(refreshed.products.project_id, "")
  assert_eq(
    refreshed.company_setup.exact_project,
    verified.company_setup.exact_project,
  )
  let chosen = setup_test_update(refreshed, UseProject)
  assert_eq(chosen.products.project_id, request.project_id)
  assert_eq(chosen.dispatch_drafts, [])
}

///|
test "partial project list diagnostics are visible without blocking valid choices" {
  for has_valid in [false, true] {
    let loading = products_test_update(setup_test_empty(), LoadProjects)
    let body = Json::object({
      "items": Json::array(
        if has_valid {
          [
            Json::object({
              "project_id": Json::string("valid-project"),
              "project_name": Json::string("Valid project"),
              "source_kind": Json::string("imported"),
            }),
          ]
        } else {
          []
        },
      ),
      "diagnostics": Json::array([
        Json::object({
          "code": Json::string("ambiguous_project_identity"),
          "projectId": Json::string("conflicted"),
          "message": Json::string("ambiguous"),
        }),
      ]),
    }).stringify()
    let loaded = products_test_update(
      loading,
      ProjectsRead(
        loading.products.selected_id,
        loading.products.selection,
        loading.products.project_request,
        200,
        body,
      ),
    )
    assert_true(loaded.products.project_note.contains("省略"))
    assert_true(
      products_test_html(loaded).contains(
        "相关项目已从可选列表中省略",
      ),
    )
    if has_valid {
      let chosen = products_test_update(loaded, SelectProject("valid-project"))
      assert_true(products_project_exists(chosen.products))
      assert_true(products_test_update(chosen, Prepare).dispatch_task_form_open)
    } else {
      assert_eq(loaded.products.project_state, "empty")
      assert_true(products_test_html(loaded).contains("没有可选择项目"))
    }
    let switched = products_test_update(loaded, Select("moondesk"))
    assert_eq(switched.products.project_note, "")
  }
}

///|
test "bound imported unit rename preserves stable identity and immutable profile capture" {
  let captured = setup_test_profile_body(
    "Immutable company", "imported-unit", "imported",
  )
  let ready = setup_test_units(
    setup_test_profile(setup_test_empty(), 200, captured),
    200,
    setup_test_unit_body("imported-unit", "imported"),
  )
  assert_true(ready.company_saved)
  let loading = setup_test_update(ready, Refresh)
  let refresh = setup_test_update(
    loading,
    SessionRead(
      loading.company_setup.session_request,
      200,
      "{\"authenticated\":true,\"actor_id\":\"signed-actor-no-erp-user\"}",
    ),
  )
  let renamed = setup_test_units(
    setup_test_profile(refresh, 200, captured),
    200,
    setup_test_unit_body("imported-unit", "imported").replace_all(
      old="Actual unit",
      new="Current unit name",
    ),
  )
  assert_true(renamed.company_saved)
  assert_eq(renamed.company_name, "Immutable company")
  assert_eq(renamed.company_setup.profile.unwrap().unit_name, "Actual unit")
  assert_eq(
    company_setup_profile_unit(renamed.company_setup).unwrap().name,
    "Current unit name",
  )
  let html = products_test_html({ ..renamed, page: Company, })
  assert_true(html.contains("Current unit name"))
  assert_true(html.contains("建档时记录的单位名称：Actual unit"))
  assert_false(
    setup_test_units(
      renamed,
      200,
      setup_test_unit_body("different-unit", "imported"),
    ).company_saved,
  )
  assert_false(
    setup_test_units(
      renamed,
      200,
      setup_test_unit_body("imported-unit", "command"),
    ).company_saved,
  )
  let stale = setup_test_update(
    renamed,
    UnitsRead(
      ready.company_setup.actor,
      ready.company_setup.epoch,
      ready.company_setup.read_request,
      200,
      setup_test_unit_body("wrong", "imported"),
    ),
  )
  setup_test_unchanged(stale, renamed)
}

///|
test "unrelated duplicate cycle diagnostic blank name and malformed branches preserve usable units and new roots" {
  let duplicate = Json::object({
    "buGuid": Json::string("ambiguous"),
    "buName": Json::string("Duplicate"),
    "sourceKind": Json::string("imported"),
    "children": Json::array([]),
  })
  let valid = Json::object({
    "buGuid": Json::string("valid-unit"),
    "buName": Json::string("Actual unit"),
    "sourceKind": Json::string("command"),
    "children": Json::array([]),
  })
  let unnamed = Json::object({
    "buGuid": Json::string("unnamed-unit"),
    "buName": Json::string(""),
    "sourceKind": Json::string("imported"),
    "children": Json::array([]),
  })
  let body = Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array([
      duplicate,
      valid,
      unnamed,
      duplicate,
      Json::object({ "buGuid": Json::string("invalid") }),
    ]),
    "diagnostics": Json::array([
      Json::object({
        "code": Json::string("unit_cycle"),
        "buGuid": Json::string("other-cycle"),
        "message": Json::string("cycle safely flattened"),
      }),
    ]),
  }).stringify()
  let units = setup_test_units(setup_test_empty(), 200, body)
  assert_eq(units.company_setup.units.length(), 2)
  assert_true(units.company_setup.units_note.contains("组织数据"))
  assert_eq(
    setup_test_update(units, Input("project_unit", "ambiguous")).company_setup.project_unit_id,
    "",
  )
  let selected = setup_test_update(units, Input("project_unit", "valid-unit"))
  assert_eq(selected.company_setup.project_unit_id, "valid-unit")
  let profile = setup_test_profile(
    units,
    200,
    setup_test_profile_body("Actual OPC", "valid-unit", "command"),
  )
  assert_true(profile.company_saved)
  let new_root = setup_test_update(
    setup_test_update(units, Input("company_name", "New root")),
    Save("company"),
  )
  assert_eq(new_root.company_setup.company.phase, "saving")
  assert_eq(new_root.company_setup.company.request.unwrap().unit_id, "")
  assert_true(
    products_test_html(units).contains("unnamed-unit（名称未提供）"),
  )
  let existing = products_test_project(units)
  assert_true(products_test_update(existing, Prepare).dispatch_task_form_open)
}
