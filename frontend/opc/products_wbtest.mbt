///|
struct ProductsTestScheduler {
  mut effects : Int
  mut messages : Int
}

///|
impl @cmd.Scheduler for ProductsTestScheduler with fn run_effect(self, _, _) {
  self.effects += 1
}

///|
impl @cmd.Scheduler for ProductsTestScheduler with fn queue_message(self, _, _) {
  self.messages += 1
}

///|
impl @cmd.Scheduler for ProductsTestScheduler with fn drain_message(_) {
  ()
}

///|
impl @cmd.Scheduler for ProductsTestScheduler with fn hooks(_) {
  { url_request: None, url_changed: None, }
}

///|
fn products_test_effect_count(command : Cmd) -> Int {
  let scheduler = { effects: 0, messages: 0, }
  @cmd.Scheduler::add(scheduler, command)
  scheduler.effects + scheduler.messages
}

///|
fn products_test_update(model : Model, action : ProductsMsg) -> Model {
  let (_, model) = update(_ => none, ProductsAction(action), model)
  model
}

///|
fn products_test_loaded() -> Model {
  products_test_update(
    initial_model(),
    CatalogRead(0, 200, products_test_catalog()),
  )
}

///|
fn products_test_selected(id : String) -> Model {
  products_test_update(products_test_loaded(), Select(id))
}

///|
fn products_test_project(model : Model) -> Model {
  let loading = products_test_update(model, LoadProjects)
  let loaded = products_test_update(
    loading,
    ProjectsRead(
      loading.products.selected_id,
      loading.products.selection,
      loading.products.project_request,
      200,
      // Match native project creation's legacy flag and default status.
      "{\"items\":[{\"project_id\":\"company-actual\",\"project_name\":\"Actual company project\",\"source_kind\":\"command\",\"if_end\":true,\"proj_status\":\"initiation\"}]}",
    ),
  )
  products_test_update(loaded, SelectProject("company-actual"))
}

///|
#warnings("-alert_unstable")
fn products_test_html(model : Model) -> String {
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => view(msg => emit(msg), model))
  @rabbita.render_to_string(page)
}

///|
test "Products is the default visible front door without Moon mode or fake topbar facts" {
  let model = products_test_loaded()
  assert_eq(model.page, Products)
  assert_false(model.moon_mode)
  let html = products_test_html(model)
  assert_true(html.contains("产品目录"))
  assert_true(html.contains("MoonBook"))
  assert_true(html.contains("20 个已配置的活跃产品定义"))
  assert_false(html.contains("待决 5"))
  assert_false(html.contains("Agent 在线 11/12"))
  assert_false(html.contains("治理正常"))
}

///|
test "Complete catalog uses twenty exact stable identities and explicit enrollment subset" {
  let rows = products_decode(products_test_catalog()).unwrap()
  let expected = [
    "moonproj", "moonbook", "moonclaw", "moontown", "moondesk", "moongate", "moonrobo",
    "moonmoon", "moonfish", "mooncast", "moonchat", "moonfind", "moonflow", "moonfort",
    "moonlib", "moonmold", "moonpoly", "moonedit", "moonleaf", "moonvis",
  ]
  assert_eq(rows.length(), expected.length())
  for id in expected {
    assert_eq(rows.filter(row => row.id == id).length(), 1)
  }
  assert_eq(rows.filter(row => !row.engineering_target.is_empty()).length(), 9)
  assert_eq(
    products_find(rows, "moonfish").unwrap().repository_state,
    "missing",
  )
  assert_eq(
    products_find(rows, "moonpoly").unwrap().repository_state,
    "unknown",
  )
  for id in ["moonprop", "mooncake", "moonstat", "lunanexa"] {
    assert_eq(products_find(rows, id), None)
  }
}

///|
test "Search sorting and catalog reordering preserve selection by ID" {
  let selected = products_test_selected("moonbook")
  let filtered = products_test_update(selected, Search("MoonDesk"))
  assert_eq(filtered.products.selected_id, "moonbook")
  assert_eq(products_visible(filtered.products).map(row => row.id), ["moondesk"])
  let reordered = products_test_update(filtered, Reverse)
  assert_eq(reordered.engineering_project, "moonbook")
  assert_eq(products_selected(reordered.products).unwrap().name, "MoonBook")
  let json = @json.parse(products_test_catalog()) catch { _ => panic() }
  let values = match products_field(json, "products") {
    Array(v) => v
    _ => panic()
  }
  values.rev_in_place()
  let refreshed = products_test_update(
    reordered,
    CatalogRead(reordered.products.request, 200, json.stringify()),
  )
  assert_eq(refreshed.products.selected_id, "moonbook")
  assert_eq(refreshed.engineering_project, "moonbook")
}

///|
test "Catalog removal clears selection rather than drifting to another row" {
  let model = products_test_selected("moonbook")
  let empty = products_test_update(
    model,
    CatalogRead(
      0, 200, "{\"schema\":\"moonsuite.product-portfolio.v2\",\"scope\":\"active_product_definitions\",\"products\":[]}",
    ),
  )
  assert_eq(empty.products.selected_id, "")
  assert_eq(empty.engineering_project, "")
  assert_eq(empty.products.state, "empty")
}

///|
test "Invalid duplicate unsafe-document and wrong-schema catalogs fail closed" {
  assert_eq(products_decode("no JSON"), None)
  assert_eq(products_decode("{}"), None)
  let root = @json.parse(products_test_catalog()) catch { _ => panic() }
  let rows = match products_field(root, "products") {
    Array(v) => v
    _ => panic()
  }
  rows.push(rows[0])
  assert_eq(products_decode(root.stringify()), None)
  let unsafe_url = products_test_catalog().replace(
    old="/api/moonsuite/products/moonproj/documents/prd",
    new="javascript:alert(1)",
  )
  assert_eq(products_decode(unsafe_url), None)
  assert_eq(
    products_decode(
      products_test_catalog().replace(
        old="moonsuite.product-portfolio.v2",
        new="other.v1",
      ),
    ),
    None,
  )
}

///|
test "HTTP status distinguishes unauthorized missing invalid offline unavailable and empty" {
  for
    (status, body, expected) in [
      (401, "{}", "unauthorized"),
      (403, "{}", "unauthorized"),
      (503, "{\"code\":\"product_catalog_missing\"}", "missing"),
      (503, "{\"code\":\"product_catalog_invalid\"}", "invalid"),
      (0, "", "offline"),
      (503, "{}", "unavailable"),
      (200, "{}", "invalid"),
    ] {
    let failed = products_test_update(
      products_test_loaded(),
      CatalogRead(0, status, body),
    )
    assert_eq(failed.products.state, expected)
    assert_eq(failed.products.rows.length(), 0)
    assert_true(
      products_test_html(failed).contains(products_state_label(expected)),
    )
  }
}

///|
test "Late catalog responses cannot overwrite the latest refresh" {
  let loading = products_test_update(products_test_loaded(), Refresh)
  let late = products_test_update(loading, CatalogRead(0, 503, "{}"))
  assert_eq(late.products, loading.products)
}

///|
test "Product A to B to A rejects old detail success failure and audit callbacks" {
  let a = products_test_selected("moonbook")
  let b = products_test_update(a, Select("moondesk"))
  let again = products_test_update(b, Select("moonbook"))
  for model in [b, again] {
    let late = products_test_update(
      model,
      DetailRead(
        "engineering",
        "moonbook",
        a.products.selection,
        200,
        "{\"audit\":{\"project\":\"moonbook\",\"freshness\":\"fresh\",\"health\":{\"status\":\"OLD_A\"}}}",
      ),
    )
    assert_eq(late.engineering_health, "unknown")
    let failed = products_test_update(
      late,
      DetailRead("admission", "moonbook", a.products.selection, 401, "{}"),
    )
    assert_eq(failed.products.admission_state, "loading")
    let (_, audit) = update(
      _ => none,
      EngineeringAuditSubmitted(
        "moonbook",
        a.products.selection,
        "old",
        "old-task",
      ),
      failed,
    )
    assert_eq(audit.engineering_task_id, "")
    let (_, audit_failure) = update(
      _ => none,
      EngineeringAuditFailed("moonbook", a.products.selection),
      audit,
    )
    assert_eq(audit_failure.engineering_audit_state, "idle")
  }
}

///|
test "Malformed or cross-product evidence cannot become missing success" {
  let a = products_test_selected("moonbook")
  for
    body in [
      "{}", "{\"audit\":{\"project\":\"moondesk\",\"freshness\":\"fresh\"}}",
    ] {
    let bad = products_test_update(
      a,
      DetailRead("engineering", "moonbook", a.products.selection, 200, body),
    )
    assert_eq(bad.products.engineering_state, "invalid")
    assert_eq(bad.engineering_health, "unknown")
  }
  let bad = products_test_update(
    a,
    DetailRead(
      "admission",
      "moonbook",
      a.products.selection,
      200,
      "{\"product_in_gate\":{\"product\":\"moondesk\",\"persisted\":true}}",
    ),
  )
  assert_eq(bad.products.admission_state, "invalid")
}

///|
test "Missing stale and unavailable evidence remain separate without erasing catalog" {
  let a = products_test_selected("moonbook")
  for freshness in ["missing", "stale"] {
    let loaded = products_test_update(
      a,
      DetailRead(
        "engineering",
        "moonbook",
        a.products.selection,
        200,
        "{\"audit\":{\"project\":\"moonbook\",\"freshness\":\"" +
        freshness +
        "\"}}",
      ),
    )
    assert_eq(loaded.engineering_freshness, freshness)
    assert_eq(loaded.products.state, "ready")
    let html = products_test_html(loaded)
    assert_true(
      html.contains(
        if freshness == "missing" {
          "没有工程证据"
        } else {
          "历史证据已过期"
        },
      ),
    )
  }
  let failed = products_test_update(
    a,
    DetailRead("engineering", "moonbook", a.products.selection, 503, "{}"),
  )
  assert_eq(failed.products.engineering_state, "unavailable")
  assert_eq(failed.products.rows.length(), 20)
}

///|
test "PRD links require a declared available exact route and retain snapshot meaning" {
  let model = products_test_selected("moonbook")
  let html = products_test_html(model)
  assert_true(
    html.contains("href=\"/api/moonsuite/products/moonbook/documents/prd\""),
  )
  assert_true(html.contains("作者快照"))
  assert_false(html.contains("href=\"libfile_"))
  let row = products_selected(model.products).unwrap()
  let doc = { ..row.documents[0], url: "", availability: "missing", }
  let missing = {
    ..model,
    products: { ..model.products, rows: [{ ..row, documents: [doc], }], },
  }
  let missing_html = products_test_html(missing)
  assert_true(missing_html.contains("当前文件不可用"))
  assert_false(
    missing_html.contains(
      "href=\"/api/moonsuite/products/moonbook/documents/prd\"",
    ),
  )
}

///|
test "Quality keeps exact selected product identity with Moon mode off" {
  let model = products_test_update(
    products_test_selected("moonbook"),
    OpenEngineering(Quality),
  )
  assert_eq(model.page, Quality)
  assert_false(model.moon_mode)
  let html = products_test_html(model)
  assert_true(html.contains("moonbook · 发布候选"))
  assert_false(html.contains("Investment Pack"))
  assert_false(html.contains("Core Service"))
}

///|
test "Inventory-only or missing repository products cannot launch engineering audit" {
  for id in ["moonfish", "moonpoly", "moonfort"] {
    let model = products_test_selected(id)
    let (command, after) = update(_ => none, RequestEngineeringAudit, model)
    assert_eq(products_test_effect_count(command), 0)
    assert_eq(after.engineering_audit_state, "idle")
  }
}

///|
test "Unlinked product preparation never substitutes product ID or fixture project" {
  let model = products_test_selected("moonbook")
  let (command, blocked) = update(_ => none, ProductsAction(Prepare), model)
  assert_eq(products_test_effect_count(command), 0)
  assert_eq(blocked.dispatch_task_project_id, "")
  assert_eq(blocked.dispatch_task_id, "")
  assert_false(blocked.dispatch_task_form_open)
}

///|
test "Prepare repeat cancel and back only save local drafts without fabricated workspace" {
  let model = products_test_project(products_test_selected("moonbook"))
  let (command, prepared) = update(_ => none, ProductsAction(Prepare), model)
  // One local draft write plus one deliberate displayed-page history write.
  assert_eq(products_test_effect_count(command), 2)
  assert_eq(
    dispatch_active_draft(prepared).unwrap().project_id,
    "company-actual",
  )
  assert_eq(dispatch_active_draft(prepared).unwrap().workspace, "")
  assert_eq(prepared.dispatch_task_id, "")
  assert_true(prepared.dispatch_task_form_open)
  assert_true(
    products_test_html(prepared).contains("产品上下文：MoonBook"),
  )
  let (again_command, repeated) = update(
    _ => none,
    ProductsAction(Prepare),
    prepared,
  )
  assert_eq(products_test_effect_count(again_command), 1)
  assert_eq(repeated.dispatch_task_id, "")
  assert_eq(repeated.dispatch_drafts, prepared.dispatch_drafts)
  let (cancel_command, cancelled) = update(
    _ => none,
    ProductsAction(CancelPreparation),
    repeated,
  )
  assert_eq(products_test_effect_count(cancel_command), 1)
  assert_eq(cancelled.page, Products)
  assert_eq(cancelled.dispatch_task_id, "")
  assert_eq(cancelled.dispatch_task_project_id, "")
  assert_false(cancelled.dispatch_task_form_open)
  assert_eq(cancelled.dispatch_drafts, prepared.dispatch_drafts)
}

///|
test "Product preparation requires explicit actual workspace before creating" {
  let prepared = products_test_update(
    products_test_project(products_test_selected("moonbook")),
    Prepare,
  )
  let valid = dispatch_replace_draft(
    { ..prepared, dispatch_task_actor_id: "fixture-owner", },
    {
      ..dispatch_active_draft(prepared).unwrap(),
      acceptance: "Check actual artifact",
      begin_date: "2026-10-02",
      end_date: "2026-10-03",
    },
  )
  let (_, blocked) = update(_ => none, CreateDispatchTask, valid)
  assert_eq(blocked.dispatch_task_pending_action, "")
  assert_eq(dispatch_active_draft(blocked).unwrap().state, "editing")
  assert_true(
    dispatch_active_draft(blocked).unwrap().note.contains(
      "实际执行工作区",
    ),
  )
}

///|
test "Product project and work response generations reject late or cross-product rows" {
  let a = products_test_selected("moonbook")
  let loading = products_test_update(a, LoadProjects)
  let b = products_test_update(loading, Select("moondesk"))
  let stale = products_test_update(
    b,
    ProjectsRead(
      "moonbook",
      loading.products.selection,
      loading.products.project_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(stale.products.project_state, "idle")
  assert_eq(
    products_decode_tasks(
      "{\"items\":[{\"taskGuid\":\"t\",\"product_id\":\"moondesk\",\"projGuid\":\"company-actual\"}]}",
      "moonbook",
    ),
    None,
  )
  let work = products_test_update(products_test_project(a), LoadWork)
  let failed = products_test_update(
    work,
    WorkRead(
      "moonbook",
      work.products.selection - 1,
      "",
      work.products.work_request,
      503,
      "{}",
    ),
  )
  assert_eq(failed.products.work_state, "loading")
}

///|
test "Opening actual selected work keeps existing native recovery selection guards" {
  let model = products_test_project(products_test_selected("moonbook"))
  let work = products_test_update(model, LoadWork)
  let loaded = products_test_update(
    work,
    WorkRead(
      "moonbook",
      work.products.selection,
      "company-actual",
      work.products.work_request,
      200,
      "{\"items\":[{\"taskGuid\":\"task-1\",\"product_id\":\"moonbook\",\"projGuid\":\"company-actual\",\"taskName\":\"Actual task\",\"status\":\"in_progress\"}]}",
    ),
  )
  let opened = products_test_update(loaded, OpenTask("task-1"))
  assert_eq(opened.page, Dispatch)
  assert_eq(opened.dispatch_task_id, "task-1")
  assert_eq(opened.dispatch_task_pending_action, "load")
  assert_eq(opened.dispatch_task_selection, model.dispatch_task_selection + 1)
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded(
      "task-1",
      opened.dispatch_task_selection - 1,
      dispatch_test_snapshot("completed"),
    ),
    opened,
  )
  assert_eq(stale.dispatch_task_stage, "loading")
  assert_eq(stale.dispatch_run, None)
}

///|
test "Policy and generic task preparation replace product-only guards and context" {
  let prepared = products_test_update(
    products_test_project(products_test_selected("moonbook")),
    Prepare,
  )
  let policy = {
    ..prepared,
    policy_radar_projection: Some(
      policy_test_projection("verified", "confirmed"),
    ),
  }
  let (_, replaced) = update(
    _ => none,
    PreparePolicyValidationTask("edge-validation"),
    policy,
  )
  assert_eq(replaced.products.prepared_product_id, "")
  assert_eq(
    dispatch_active_draft(replaced).unwrap().project_id,
    "policy-intelligence",
  )
  let (_, generic) = update(_ => none, OpenDispatchTaskForm, prepared)
  assert_eq(generic.products.prepared_product_id, "")
  let (_, reopened) = update(_ => none, OpenDispatchTask, {
    ..prepared,
    dispatch_task_open_id: "task-1",
  })
  assert_eq(reopened.products.prepared_product_id, "")
}

///|
test "Unfinished formal task and pending read remain intact when preparing product work" {
  let selected = products_test_project(products_test_selected("moonbook"))
  let original = {
    ..apply_dispatch_snapshot(selected, dispatch_test_snapshot("running")),
    dispatch_task_title: "Do not replace this actual task",
    dispatch_task_project_id: "original-company-project",
    dispatch_task_workspace: "/original/workspace",
    dispatch_task_form_open: false,
  }
  for model in [original, { ..original, dispatch_task_pending_action: "load", }] {
    let (command, blocked) = update(_ => none, ProductsAction(Prepare), model)
    assert_eq(products_test_effect_count(command), 2)
    assert_eq(blocked.dispatch_task_id, model.dispatch_task_id)
    assert_eq(blocked.dispatch_task_title, model.dispatch_task_title)
    assert_eq(blocked.dispatch_task_project_id, model.dispatch_task_project_id)
    assert_eq(blocked.dispatch_task_workspace, model.dispatch_task_workspace)
    assert_eq(blocked.dispatch_run, model.dispatch_run)
    assert_eq(blocked.dispatch_task_selection, model.dispatch_task_selection)
    assert_eq(
      blocked.dispatch_task_pending_action,
      model.dispatch_task_pending_action,
    )
    assert_true(blocked.dispatch_task_form_open)
    assert_eq(dispatch_active_draft(blocked).unwrap().product_id, "moonbook")
  }
}

///|
test "Founder purpose paragraphs remain visible and separated from acceptance" {
  let rows = products_decode(products_test_catalog()).unwrap()
  for id in ["moonproj", "moondesk", "moontown", "moonbook"] {
    let row = products_find(rows, id).unwrap()
    assert_eq(row.philosophy_kind, "founder_intent")
    let html = products_test_html(products_test_selected(id))
    for paragraph in row.philosophy_paragraphs {
      assert_true(html.contains(paragraph))
    }
    assert_true(html.contains("不代表已经实现"))
  }
  let proj = products_find(rows, "moonproj").unwrap()
  assert_true(proj.philosophy_paragraphs.join(" ").contains("autonomously"))
}

///|
test "Unknown project cannot be selected while listed project work and history remain available" {
  let model = products_test_project(products_test_selected("moonbook"))
  let unchanged = products_test_update(model, SelectProject("moonbook"))
  assert_eq(unchanged.products.project_id, "company-actual")
  let listed = {
    ..model,
    products: {
      ..model.products,
      project_id: "",
      projects: [{ id: "company-listed", name: "Listed", source: "command", }],
    },
  }
  let selected = products_test_update(listed, SelectProject("company-listed"))
  assert_eq(selected.products.project_id, "company-listed")
  let history = products_test_update(selected, LoadWork)
  assert_eq(history.products.work_state, "loading")
  let (command, prepared) = update(_ => none, ProductsAction(Prepare), selected)
  assert_eq(products_test_effect_count(command), 2)
  assert_true(prepared.dispatch_task_form_open)
  assert_eq(
    dispatch_active_draft(prepared).unwrap().project_id,
    "company-listed",
  )
  assert_false(products_project_exists(listed.products))
  assert_true(products_project_exists(selected.products))
  let row = products_selected(model.products).unwrap()
  let mapped = {
    ..model,
    products: {
      ..model.products,
      rows: [{ ..row, company_project_id: "not-present", }],
    },
  }
  let read = products_test_project(mapped)
  assert_eq(read.products.project_id, "company-actual")
}

///|
test "Inventory-only products load admission and can prepare ordinary work without audit enrollment" {
  let inventory = products_test_selected("moonfort")
  assert_eq(inventory.products.engineering_state, "not_enrolled")
  assert_eq(inventory.products.admission_state, "loading")
  let prepared = products_test_update(products_test_project(inventory), Prepare)
  assert_true(prepared.dispatch_task_form_open)
  assert_eq(
    dispatch_active_draft(prepared).unwrap().project_id,
    "company-actual",
  )
  assert_eq(prepared.products.prepared_product_id, "moonfort")
  assert_eq(dispatch_active_draft(prepared).unwrap().workspace, "")
}

///|
test "Global Quality navigation does not read undeclared engineering targets" {
  let inventory = products_test_selected("moonfort")
  let (command, quality) = update(_ => none, Navigate(Quality), inventory)
  // The only effect records the visible page; it does not read engineering.
  assert_eq(products_test_effect_count(command), 1)
  assert_eq(quality.products.engineering_state, "not_enrolled")
  assert_eq(quality.engineering_project, "moonfort")
}

///|
test "Prepared product context and verified company project survive browsing refresh and return" {
  let prepared = products_test_update(
    products_test_project(products_test_selected("moonbook")),
    Prepare,
  )
  let draft = dispatch_replace_draft(
    { ..prepared, dispatch_task_actor_id: "fixture-owner", },
    {
      ..dispatch_active_draft(prepared).unwrap(),
      title: "Actual result to build",
      acceptance: "Check the named artifact",
      workspace: "/explicit/authorized/workspace",
      begin_date: "2026-10-02",
      end_date: "2026-10-03",
    },
  )
  let (_, browsing) = update(_ => none, Navigate(Products), draft)
  let refreshed = products_test_update(
    browsing,
    CatalogRead(browsing.products.request, 200, products_test_catalog()),
  )
  let other = products_test_update(refreshed, Select("moondesk"))
  let returned = { ..other, page: Dispatch, }
  assert_eq(returned.products.prepared_project_id, "company-actual")
  assert_eq(returned.products.prepared_product_snapshot.unwrap().id, "moonbook")
  assert_eq(returned.products.selected_id, "moondesk")
  assert_eq(returned.products.project_id, "")
  assert_eq(returned.dispatch_task_title, draft.dispatch_task_title)
  assert_eq(returned.dispatch_task_workspace, draft.dispatch_task_workspace)
  let html = products_test_html(returned)
  assert_true(html.contains("产品上下文：MoonBook"))
  assert_true(html.contains("公司项目：company-actual"))
  let (command, creating) = update(_ => none, CreateDispatchTask, returned)
  assert_eq(products_test_effect_count(command), 1)
  assert_eq(dispatch_active_draft(creating).unwrap().state, "saving")
  assert_eq(
    dispatch_active_draft(creating).unwrap().project_id,
    "company-actual",
  )
}
