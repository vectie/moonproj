///|
fn setup_test_update(model : Model, action : CompanySetupMsg) -> Model {
  company_setup_update(_ => none, action, model).1
}

///|
fn setup_test_unchanged(actual : Model, expected : Model) -> Unit raise {
  assert_eq(actual.company_setup, expected.company_setup)
  assert_eq(actual.company_name, expected.company_name)
  assert_eq(actual.company_saved, expected.company_saved)
  assert_eq(actual.products, expected.products)
  assert_eq(actual.dispatch_drafts, expected.dispatch_drafts)
  assert_eq(actual.dispatch_task_id, expected.dispatch_task_id)
}

///|
fn setup_test_session(model : Model, actor : String) -> Model {
  let refreshed = setup_test_update(model, Refresh)
  let result = setup_test_update(
    refreshed,
    SessionRead(
      refreshed.company_setup.session_request,
      200,
      Json::object({
        "authenticated": Json::boolean(true),
        "actor_id": Json::string(actor),
      }).stringify(),
    ),
  )
  setup_test_update(result, Restored(actor, result.company_setup.epoch, ""))
}

///|
fn setup_test_profile(model : Model, status : Int, body : String) -> Model {
  let state = model.company_setup
  setup_test_update(
    model,
    ProfileRead(state.actor, state.epoch, state.read_request, status, body),
  )
}

///|
fn setup_test_units(model : Model, status : Int, body : String) -> Model {
  let state = model.company_setup
  setup_test_update(
    model,
    UnitsRead(state.actor, state.epoch, state.read_request, status, body),
  )
}

///|
fn setup_test_unit_body(id : String, source : String) -> String {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array([
      Json::object({
        "buGuid": Json::string(id),
        "buName": Json::string("Actual unit"),
        "sourceKind": Json::string(source),
        "children": Json::array([]),
      }),
    ]),
  }).stringify()
}

///|
fn setup_test_profile_body(
  name : String,
  unit : String,
  source : String,
) -> String {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "persisted": Json::boolean(true),
    "profile": Json::object({
      "company_id": Json::string("current"),
      "company_name": Json::string(name),
      "bu_guid": Json::string(unit),
      "bu_name": Json::string("Actual unit"),
      "unit_source_kind": Json::string(source),
      "source_kind": Json::string("command"),
      "revision": Json::number(1),
    }),
  }).stringify()
}

///|
fn setup_test_empty() -> Model {
  setup_test_units(
    setup_test_profile(
      setup_test_session(
        products_test_selected("moonbook"),
        "signed-actor-no-erp-user",
      ),
      200,
      "{\"success\":true,\"code\":0,\"persisted\":false,\"profile\":null}",
    ),
    200,
    "{\"success\":true,\"code\":0,\"data\":[]}",
  )
}

///|
fn setup_test_company_saving() -> Model {
  setup_test_update(
    setup_test_update(setup_test_empty(), Input("company_name", "Real OPC")),
    Save("company"),
  )
}

///|
fn setup_test_project_ready() -> Model {
  let unit = setup_test_units(
    setup_test_empty(),
    200,
    setup_test_unit_body("imported-unit", "imported"),
  )
  setup_test_update(
    setup_test_update(
      setup_test_update(unit, Input("project_unit", "imported-unit")),
      Input("project_name", "Actual work"),
    ),
    Input("project_code", "WORK-001"),
  )
}

///|
fn setup_test_project_saving() -> Model {
  setup_test_update(setup_test_project_ready(), Save("project"))
}

///|
fn setup_test_posting(model : Model, kind : String) -> Model {
  let state = model.company_setup
  let request = company_setup_op(state, kind).request.unwrap()
  setup_test_update(
    model,
    Persisted(state.actor, state.epoch, kind, request.key, true),
  )
}

///|
fn setup_test_posted(model : Model, kind : String, status : Int) -> Model {
  let state = model.company_setup
  let request = company_setup_op(state, kind).request.unwrap()
  setup_test_update(
    model,
    Posted(state.actor, state.epoch, kind, request.key, status, "{}"),
  )
}

///|
fn setup_test_exact_body(request : CompanySetupRequest) -> String {
  Json::object({
    "project_id": Json::string(request.project_id),
    "project_name": Json::string(request.name),
    "project_code": Json::string(request.project_code),
    "bu_guid": Json::string(request.unit_id),
    "source_kind": Json::string("command"),
    "if_end": Json::boolean(true),
    "proj_status": Json::string("initiation"),
  }).stringify()
}

///|
fn setup_test_exact(model : Model, status : Int, body : String) -> Model {
  let state = model.company_setup
  setup_test_update(
    model,
    ExactRead(
      state.actor,
      state.epoch,
      state.project.request.unwrap().key,
      status,
      body,
    ),
  )
}

///|
test "fresh empty schema is a successful empty read and session identity never requires ERP user" {
  let model = setup_test_empty()
  assert_eq(model.company_setup.actor, "signed-actor-no-erp-user")
  assert_eq(model.dispatch_task_actor_id, model.company_setup.actor)
  assert_eq(model.company_setup.profile_state, "empty")
  assert_eq(model.company_setup.units_state, "empty")
  assert_false(model.company_saved)
  assert_eq(model.products.selected_id, "moonbook")
  let html = products_test_html(model)
  assert_true(html.contains("读取成功，当前没有组织单位"))
  assert_true(html.contains("建立公司工作区"))
}

///|
test "first company save only becomes persisted after canonical profile and root both verify" {
  let saving = setup_test_company_saving()
  assert_false(saving.company_saved)
  assert_eq(saving.company_setup.company.phase, "saving")
  let request = saving.company_setup.company.request.unwrap()
  assert_eq(company_setup_body(request), "{\"companyName\":\"Real OPC\"}")
  let posting = setup_test_posting(saving, "company")
  assert_false(posting.company_saved)
  let checking = setup_test_posted(posting, "company", 201)
  assert_eq(checking.company_setup.company.phase, "checking")
  assert_false(checking.company_saved)
  let profile = setup_test_profile(
    checking,
    200,
    setup_test_profile_body("Real OPC", "ORG-real", "command"),
  )
  assert_false(profile.company_saved)
  let verified = setup_test_units(
    profile,
    200,
    setup_test_unit_body("ORG-real", "command"),
  )
  assert_true(verified.company_saved)
  assert_eq(verified.company_setup.company.phase, "confirmed")
  assert_eq(verified.company_setup.company.request, None)
  assert_false(verified.constitution_ready)
  assert_false(verified.authority_ready)
  assert_false(verified.ledger_ready)
  assert_false(verified.budget_ready)
  assert_eq(verified.products.project_id, "")
  assert_eq(verified.dispatch_task_id, "")
  let changed = setup_test_update(
    verified,
    Input("company_name", "unapproved rename"),
  )
  assert_eq(changed.company_name, "Real OPC")
  setup_test_unchanged(setup_test_update(changed, Save("company")), changed)
}

///|
test "saved profile renders read only without fake company financial or legal facts" {
  let ready = setup_test_units(
    setup_test_profile(
      setup_test_empty(),
      200,
      setup_test_profile_body("Real OPC", "ORG-real", "command"),
    ),
    200,
    setup_test_unit_body("ORG-real", "command"),
  )
  let html = products_test_html({
    ..ready,
    page: Company,
    company_form_open: true,
  })
  assert_true(html.contains("Real OPC"))
  assert_true(html.contains("首次创建后此处只读"))
  assert_true(html.contains("不代表法律注册"))
  assert_false(html.contains("id=\"company-name\""))
  assert_false(html.contains("保存公司工作区"))
  for
    fake in [
      "85.2", "14.2", "12.6", "07-15", "07-31", "本月 2 项", "编辑公司档案",
    ] {
    assert_false(html.contains(fake))
  }
}

///|
test "known saved company remains read only while refreshing" {
  let ready = setup_test_units(
    setup_test_profile(
      setup_test_empty(),
      200,
      setup_test_profile_body("Real OPC", "ORG-real", "command"),
    ),
    200,
    setup_test_unit_body("ORG-real", "command"),
  )
  let loading = setup_test_update(ready, Refresh)
  let refresh = setup_test_update(
    loading,
    SessionRead(
      loading.company_setup.session_request,
      200,
      "{\"authenticated\":true,\"actor_id\":\"signed-actor-no-erp-user\"}",
    ),
  )
  assert_false(company_setup_company_editable(refresh))
  assert_eq(
    setup_test_update(refresh, Input("company_name", "rename during refresh")).company_name,
    "Real OPC",
  )
}

///|
test "company failures remain unknown never empty and cannot submit" {
  for status in [0, 401, 403, 503] {
    let model = setup_test_profile(setup_test_empty(), status, "{}")
    assert_false(model.company_saved)
    assert_true(model.company_setup.profile_state != "empty")
    let saved = setup_test_update(
      { ..model, company_name: "OPC", },
      Save("company"),
    )
    assert_eq(saved.company_setup.company.request, None)
  }
  let invalid = setup_test_profile(
    setup_test_empty(),
    200,
    "{\"success\":true,\"code\":0,\"persisted\":false}",
  )
  assert_eq(invalid.company_setup.profile_state, "invalid")
  assert_false(invalid.company_saved)
}

///|
test "company root mismatch and incomplete canonical profile never assert persisted" {
  let profile = setup_test_profile(
    setup_test_empty(),
    200,
    setup_test_profile_body("OPC", "missing-unit", "command"),
  )
  let wrong = setup_test_units(
    profile,
    200,
    setup_test_unit_body("another-unit", "command"),
  )
  assert_false(wrong.company_saved)
  let source = setup_test_units(
    profile,
    200,
    setup_test_unit_body("missing-unit", "imported"),
  )
  assert_false(source.company_saved)
  assert_eq(
    company_setup_profile(
      "{\"success\":true,\"code\":0,\"persisted\":true,\"profile\":{\"company_name\":\"OPC\"}}",
    ),
    None,
  )
}

///|
test "double click freezes company body key and waits for durable local save" {
  let saving = setup_test_company_saving()
  let frozen = saving.company_setup.company.request.unwrap()
  let double = setup_test_update(saving, Save("company"))
  setup_test_unchanged(double, saving)
  let typed = setup_test_update(double, Input("company_name", "changed"))
  assert_eq(typed.company_name, "Real OPC")
  let posting = setup_test_posting(typed, "company")
  assert_eq(posting.company_setup.company.request, Some(frozen))
  setup_test_unchanged(setup_test_update(posting, Save("company")), posting)
}

///|
test "storage failure before first POST keeps editable inputs and no persisted claim" {
  let saving = setup_test_company_saving()
  let state = saving.company_setup
  let failed = setup_test_update(
    saving,
    Persisted(
      state.actor,
      state.epoch,
      "company",
      state.company.request.unwrap().key,
      false,
    ),
  )
  assert_eq(failed.company_setup.company.phase, "failed")
  assert_eq(failed.company_setup.company.request, None)
  assert_false(failed.company_saved)
  assert_true(failed.company_setup.company.note.contains("没有提交"))
  assert_eq(
    setup_test_update(failed, Input("company_name", "Revised")).company_name,
    "Revised",
  )
}

///|
test "lost company response reload and empty exact recovery retain same body and key" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_company_saving(), "company"),
    "company",
    0,
  )
  let original = checking.company_setup.company.request.unwrap()
  let local = company_setup_store(checking.company_setup)
  let fresh = setup_test_session(initial_model(), checking.company_setup.actor)
  let restored = setup_test_update(
    fresh,
    Restored(fresh.company_setup.actor, fresh.company_setup.epoch, local),
  )
  assert_false(restored.company_saved)
  assert_eq(restored.company_setup.company.phase, "uncertain")
  let recovering = setup_test_update(restored, Recover("company"))
  let empty = setup_test_units(
    setup_test_profile(
      recovering, 200, "{\"success\":true,\"code\":0,\"persisted\":false,\"profile\":null}",
    ),
    200,
    "{\"success\":true,\"code\":0,\"data\":[]}",
  )
  assert_eq(empty.company_setup.company.phase, "retryable")
  let retry = setup_test_posting(
    setup_test_update(empty, Save("company")),
    "company",
  )
  assert_eq(retry.company_setup.company.request, Some(original))
  assert_eq(
    company_setup_body(retry.company_setup.company.request.unwrap()),
    company_setup_body(original),
  )
  assert_true(retry.company_setup.company.retrying)
}

///|
test "definitive first command rejection makes both company and project editable" {
  for kind in ["company", "project"] {
    let initial = if kind == "company" {
      setup_test_company_saving()
    } else {
      setup_test_project_saving()
    }
    let rejected = setup_test_posted(
      setup_test_posting(initial, kind),
      kind,
      422,
    )
    assert_eq(company_setup_op(rejected.company_setup, kind).request, None)
    assert_eq(company_setup_op(rejected.company_setup, kind).phase, "failed")
    let edited = setup_test_update(
      rejected,
      Input(
        if kind == "company" {
          "company_name"
        } else {
          "project_name"
        },
        "Revised",
      ),
    )
    assert_eq(
      if kind == "company" {
        edited.company_name
      } else {
        edited.company_setup.project_name
      },
      "Revised",
    )
    assert_false(edited.company_saved)
  }
}

///|
test "explicit imported unit binding uses actual identity while existing project path needs no profile" {
  let imported = setup_test_units(
    setup_test_empty(),
    200,
    setup_test_unit_body("imported-unit", "imported"),
  )
  let bound = setup_test_update(
    setup_test_update(
      setup_test_update(imported, Input("company_name", "OPC")),
      Input("company_unit", "imported-unit"),
    ),
    Save("company"),
  )
  assert_true(
    company_setup_body(bound.company_setup.company.request.unwrap()).contains(
      "\"existingBuGuid\":\"imported-unit\"",
    ),
  )
  let existing = products_test_project(imported)
  assert_false(existing.company_saved)
  let prepared = products_test_update(existing, Prepare)
  assert_true(prepared.dispatch_task_form_open)
  assert_eq(
    dispatch_active_draft(prepared).unwrap().project_id,
    "company-actual",
  )
}

///|
test "native project create validates canonical identity unit source before selection and never creates task" {
  let saving = setup_test_project_saving()
  let request = saving.company_setup.project.request.unwrap()
  assert_true(request.project_id.has_prefix("PRJ-"))
  assert_eq(request.unit_id, "imported-unit")
  let checking = setup_test_posted(
    setup_test_posting(saving, "project"),
    "project",
    200,
  )
  assert_eq(checking.company_setup.exact_project, None)
  assert_eq(checking.products.project_id, "")
  let verified = setup_test_exact(checking, 200, setup_test_exact_body(request))
  assert_eq(verified.products.project_id, request.project_id)
  assert_true(products_project_exists(verified.products))
  assert_eq(verified.company_setup.project.phase, "confirmed")
  assert_false(verified.company_saved)
  assert_eq(verified.dispatch_task_id, "")
  assert_eq(verified.dispatch_drafts, [])
  assert_eq(verified.products.prepared_product_id, "")
  assert_eq(verified.page, Products)
  let prepared = products_test_update(verified, Prepare)
  assert_eq(
    dispatch_active_draft(prepared).unwrap().project_id,
    request.project_id,
  )
  assert_eq(prepared.dispatch_task_id, "")
}

///|
test "project 404 allows identical retry while incomplete mismatched and unavailable readbacks never select" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    0,
  )
  let original = checking.company_setup.project.request.unwrap()
  let not_found = setup_test_exact(checking, 404, "{}")
  assert_eq(not_found.company_setup.project.phase, "retryable")
  assert_eq(not_found.products.project_id, "")
  let retry = setup_test_posting(
    setup_test_update(not_found, Save("project")),
    "project",
  )
  assert_eq(retry.company_setup.project.request, Some(original))
  for
    body in [
      "{}",
      setup_test_exact_body({ ..original, unit_id: "other-unit", }),
      setup_test_exact_body({ ..original, project_id: "wrong-id", }),
      setup_test_exact_body(original).replace_all(
        old="\"command\"",
        new="\"imported\"",
      ),
    ] {
    let invalid = setup_test_exact(checking, 200, body)
    assert_eq(invalid.company_setup.project.phase, "uncertain")
    assert_eq(invalid.company_setup.exact_project, None)
    assert_eq(invalid.products.project_id, "")
  }
  for status in [0, 401, 503] {
    let failed = setup_test_exact(checking, status, "{}")
    assert_eq(failed.company_setup.project.phase, "uncertain")
    assert_eq(failed.company_setup.project.request, Some(original))
    assert_eq(failed.products.project_id, "")
  }
}

///|
test "project A to B navigation rejects selection from late canonical A callback" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let request = checking.company_setup.project.request.unwrap()
  let b = products_test_update(checking, Select("moondesk"))
  let late = setup_test_exact(b, 200, setup_test_exact_body(request))
  assert_eq(late.products.selected_id, "moondesk")
  assert_eq(late.products.project_id, "")
  assert_eq(late.products.projects, [])
  assert_true(late.company_setup.exact_project is Some(_))
  let chosen = setup_test_update(late, UseProject)
  assert_eq(chosen.products.project_id, request.project_id)
  assert_eq(chosen.dispatch_drafts, [])
}

///|
test "beyond capped project list exact result remains usable without inferred product mapping" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let request = checking.company_setup.project.request.unwrap()
  let verified = setup_test_exact(checking, 200, setup_test_exact_body(request))
  let loading = products_test_update(verified, LoadProjects)
  let capped = products_test_update(
    loading,
    ProjectsRead(
      loading.products.selected_id,
      loading.products.selection,
      loading.products.project_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(capped.products.project_state, "empty")
  assert_true(capped.company_setup.exact_project is Some(_))
  let chosen = setup_test_update(capped, UseProject)
  assert_true(products_project_exists(chosen.products))
  assert_eq(products_selected(chosen.products).unwrap().company_project_id, "")
  assert_true(products_test_html(chosen).contains("有数量上限"))
}

///|
test "confirmed project reload treats stored identity as hint and exact 404 never recreates deleted project" {
  let checking = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let request = checking.company_setup.project.request.unwrap()
  let verified = setup_test_exact(checking, 200, setup_test_exact_body(request))
  let fresh = setup_test_session(
    products_test_selected("moonbook"),
    verified.company_setup.actor,
  )
  let restored = setup_test_update(
    fresh,
    Restored(
      fresh.company_setup.actor,
      fresh.company_setup.epoch,
      company_setup_store(verified.company_setup),
    ),
  )
  assert_eq(restored.company_setup.exact_project, None)
  assert_eq(restored.products.project_id, "")
  assert_true(restored.company_setup.project.recover_only)
  let recovery = setup_test_update(restored, Recover("project"))
  let missing = setup_test_exact(recovery, 404, "{}")
  assert_eq(missing.company_setup.project.phase, "missing")
  assert_eq(missing.company_setup.project.request, None)
  assert_eq(missing.company_setup.recent_project, None)
  assert_eq(missing.company_setup.exact_project, None)
  let confirmed = setup_test_exact(
    recovery,
    200,
    setup_test_exact_body(request),
  )
  assert_true(confirmed.company_setup.exact_project is Some(_))
  assert_eq(confirmed.products.project_id, "")
}

///|
test "actor switch and stale callbacks cannot expose profile recovery or select project" {
  let old = setup_test_posted(
    setup_test_posting(setup_test_project_saving(), "project"),
    "project",
    200,
  )
  let state = old.company_setup
  let request = state.project.request.unwrap()
  let (_, changed) = update(
    _ => none,
    DispatchSessionLoaded("another-actor"),
    old,
  )
  assert_eq(changed.company_setup.actor, "another-actor")
  assert_false(changed.company_saved)
  assert_eq(changed.company_setup.project.request, None)
  for
    msg in [
      ExactRead(
        state.actor,
        state.epoch,
        request.key,
        200,
        setup_test_exact_body(request),
      ),
      Restored(state.actor, state.epoch, company_setup_store(state)),
      UnitsRead(
        state.actor,
        state.epoch,
        state.read_request,
        200,
        setup_test_unit_body("imported-unit", "imported"),
      ),
      ProfileRead(
        state.actor,
        state.epoch,
        state.read_request,
        200,
        setup_test_profile_body(
          "wrong-actor company", "imported-unit", "imported",
        ),
      ),
      Persisted(state.actor, state.epoch, "project", request.key, true),
      Posted(state.actor, state.epoch, "project", request.key, 200, "{}"),
    ] {
    setup_test_unchanged(setup_test_update(changed, msg), changed)
  }
}

///|
test "same actor old load request and previous epoch after sign out cannot override fresh data" {
  let old = setup_test_empty()
  let refreshed = setup_test_update(old, Refresh)
  let stale = setup_test_update(
    refreshed,
    SessionRead(
      old.company_setup.session_request,
      200,
      "{\"authenticated\":true,\"actor_id\":\"wrong\"}",
    ),
  )
  setup_test_unchanged(stale, refreshed)
  let (_, out) = update(_ => none, DispatchSessionLoaded(""), old)
  let back = setup_test_session(out, old.company_setup.actor)
  assert_true(back.company_setup.epoch > old.company_setup.epoch)
  let stale_units = setup_test_update(
    back,
    UnitsRead(
      old.company_setup.actor,
      old.company_setup.epoch,
      old.company_setup.read_request,
      200,
      setup_test_unit_body("old-unit", "imported"),
    ),
  )
  setup_test_unchanged(stale_units, back)
}

///|
test "recovery serialization stores ordinary request only never authority credentials or persisted proof" {
  let state = setup_test_project_saving().company_setup
  let text = company_setup_store(state)
  for
    forbidden in [
      "authority", "principal", "password", "signature", "authenticated", "persisted",
      "Cookie", "Authorization",
    ] {
    assert_false(text.contains(forbidden))
  }
  let fresh = setup_test_session(initial_model(), state.actor)
  let bad = setup_test_update(
    fresh,
    Restored(
      state.actor,
      fresh.company_setup.epoch,
      "{\"version\":1,\"company\":null,\"project\":{\"kind\":\"project\"}}",
    ),
  )
  assert_eq(bad.company_setup.project.request, None)
  assert_true(bad.company_setup.storage.contains("不可用"))
}
