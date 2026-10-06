///|
// Uses the existing in-memory browser/HTTP fixture. All commands execute, but
// network responses are delivered explicitly and no real service is contacted.
extern "js" fn products_route_test_param(name : String) -> String =
  #| name => new URL(window.location.href).searchParams.get(name) || ""

///|
extern "js" fn products_route_test_pop(url : String) =
  #| url => {
  #|   window.location.href = url;
  #|   globalThis.__draftsNavigation.listeners.forEach(callback => callback({type: "popstate"}));
  #| }

///|
fn products_route_test_catalog(ids : Array[String]) -> String {
  let root = @json.parse(products_test_catalog()) catch { _ => Json::null() }
  let values = match products_field(root, "products") {
    Array(values) => values
    _ => []
  }
  let selected : Array[Json] = []
  for id in ids {
    for value in values {
      if products_text(value, "id") == id {
        selected.push(value)
      }
    }
  }
  (
    {
      "schema": "moonsuite.product-portfolio.v2",
      "scope": "active_product_definitions",
      "products": selected.to_json(),
    } : Json).stringify()
}

///|
fn products_route_test_load(model : Model, catalog : String) -> Model {
  page_test_step(
    model,
    ProductsAction(CatalogRead(model.products.request, 200, catalog)),
  )
}

///|
fn products_route_test_read_only() -> Unit raise {
  let requests = drafts_navigation_requests().split("|").to_array()
  assert_true(
    requests.all(request => request.is_empty() || request.has_prefix("GET ")),
  )
  assert_false(drafts_navigation_requests().contains("/dispatch"))
  assert_false(drafts_navigation_requests().contains("/continuations"))
}

///|
test "product selection reload resolves the exact ID after catalog load and preserves query context" {
  drafts_navigation_setup(
    "https://example.test/mount?keep=%23value&tag=a&tag=b#main-content", "uuid",
  )
  let selected = page_test_step(
    products_test_loaded(),
    ProductsAction(Select("moonbook")),
  )
  assert_eq(selected.products.selected_id, "moonbook")
  assert_eq(products_route_test_param("product"), "moonbook")
  assert_eq(products_route_test_param("page"), "products")
  assert_true(page_test_url().contains("/mount?keep=%23value&tag=a&tag=b"))
  assert_false(page_test_url().contains("#main-content"))
  let loading = page_test_step(initial_model(), ProductsAction(Refresh))
  let restored = page_test_step(loading, saved_page_route())
  assert_eq(restored.products.selected_id, "")
  assert_true(
    products_test_html(restored).contains(
      "正在读取目录，以恢复产品「moonbook」",
    ),
  )
  let loaded = products_route_test_load(
    restored,
    products_route_test_catalog(["moondesk", "moonbook"]),
  )
  assert_eq(loaded.products.selected_id, "moonbook")
  assert_eq(loaded.engineering_project, "moonbook")
  assert_eq(loaded.page, Products)
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_false(loaded.dispatch_task_form_open)
  assert_eq(loaded.dispatch_task_id, "")
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "product A B Back Forward returns exact selections and missing selection returns to chooser" {
  drafts_navigation_setup("https://example.test/?page=products", "uuid")
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let a = page_test_step(
    products_test_loaded(),
    ProductsAction(Select("moonbook")),
  )
  let b = page_test_step(a, ProductsAction(Select("moondesk")))
  let b = page_test_step(b, ProductsAction(Select("moondesk")))
  assert_eq(drafts_navigation_metric("pushes"), 2)
  drafts_navigation_move(-1)
  assert_eq(emitted.length(), 1)
  let back_a = page_test_step(b, emitted[0])
  assert_eq(back_a.products.selected_id, "moonbook")
  drafts_navigation_move(-1)
  let chooser = page_test_step(back_a, emitted[1])
  assert_eq(chooser.products.selected_id, "")
  assert_eq(chooser.engineering_project, "")
  assert_true(products_test_html(chooser).contains("选择一个产品"))
  drafts_navigation_move(1)
  let forward_a = page_test_step(chooser, emitted[2])
  assert_eq(forward_a.products.selected_id, "moonbook")
  drafts_navigation_move(1)
  let forward_b = page_test_step(forward_a, emitted[3])
  assert_eq(forward_b.products.selected_id, "moondesk")
  assert_eq(drafts_navigation_metric("pushes"), 2)
  assert_eq(drafts_navigation_metric("length"), 3)
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "unknown removed empty and failed catalogs retain the requested identity without substitution" {
  for
    body in [
      products_route_test_catalog(["moondesk"]),
      products_route_test_catalog([]),
    ] {
    drafts_navigation_setup(
      "https://example.test/?page=products&product=moonbook", "uuid",
    )
    let loading = page_test_step(initial_model(), ProductsAction(Refresh))
    let restored = page_test_step(loading, saved_page_route())
    let missing = products_route_test_load(restored, body)
    assert_eq(missing.products.selected_id, "")
    assert_true(
      products_test_html(missing).contains(
        "当前目录中没有产品「moonbook」",
      ),
    )
    assert_eq(products_route_test_param("product"), "moonbook")
    let failed = page_test_step(
      missing,
      ProductsAction(CatalogRead(missing.products.request, 0, "")),
    )
    assert_true(
      products_test_html(failed).contains(
        "尚未恢复产品「moonbook」：目录读取未成功",
      ),
    )
    let retry = page_test_step(failed, ProductsAction(Refresh))
    let found = products_route_test_load(retry, products_test_catalog())
    assert_eq(found.products.selected_id, "moonbook")
    let removed = products_route_test_load(found, body)
    assert_eq(removed.products.selected_id, "")
    assert_eq(removed.engineering_project, "")
    assert_eq(drafts_navigation_metric("pushes"), 0)
    products_route_test_read_only()
    drafts_navigation_cleanup()
  }
}

///|
test "invalid duplicate and malformed product links remain explicit and never choose a product" {
  for
    query in [
      "product=", "product=MoonBook", "product=moonbook&product=moondesk", "product=%2Fmoonbook",
      "product=%E0%A4%A", "product=moonbook%20",
    ] {
    drafts_navigation_setup(
      "https://example.test/?page=products&" + query,
      "uuid",
    )
    let restored = page_test_step(products_test_loaded(), saved_page_route())
    assert_eq(restored.products.selected_id, "")
    assert_true(
      products_test_html(restored).contains(
        "链接中的产品 ID 无效或重复",
      ),
    )
    assert_eq(drafts_navigation_requests(), "")
    let selected = page_test_step(restored, ProductsAction(Select("moondesk")))
    assert_eq(selected.products.selected_id, "moondesk")
    assert_eq(products_route_test_param("product"), "moondesk")
    assert_eq(drafts_navigation_metric("pushes"), 1)
    products_route_test_read_only()
    drafts_navigation_cleanup()
  }
}

///|
test "product-only links ignore legacy task breadcrumbs and explicit task context stays separate" {
  drafts_navigation_setup(
    "https://example.test/?product=moonbook#main-content", "uuid",
  )
  drafts_navigation_legacy("stale-task")
  let restored = page_test_step(products_test_loaded(), saved_page_route())
  assert_eq(restored.page, Products)
  assert_eq(restored.products.selected_id, "moonbook")
  assert_eq(restored.dispatch_task_id, "")
  assert_false(drafts_navigation_requests().contains("/api/company/tasks/"))
  assert_true(page_test_url().has_suffix("#main-content"))
  drafts_navigation_cleanup()

  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook&task=task-a&keep=ok", "uuid",
  )
  let restored = page_test_step(products_test_loaded(), saved_page_route())
  assert_eq(restored.page, Products)
  assert_eq(restored.dispatch_task_id, "task-a")
  let restored = products_route_test_load(restored, products_test_catalog())
  let b = page_test_step(restored, ProductsAction(Select("moondesk")))
  assert_eq(b.dispatch_task_id, "task-a")
  assert_eq(b.dispatch_task_selection, restored.dispatch_task_selection)
  assert_eq(products_route_test_param("task"), "task-a")
  assert_eq(products_route_test_param("keep"), "ok")
  assert_false(b.dispatch_task_form_open)
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "late catalog resolves newest history identity and cannot steal another page" {
  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook", "uuid",
  )
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let loading = page_test_step(initial_model(), ProductsAction(Refresh))
  let a = page_test_step(loading, saved_page_route())
  products_route_test_pop(
    "https://example.test/?page=products&product=moondesk",
  )
  let b = page_test_step(a, emitted[0])
  let guide = page_test_step(b, Navigate(Guide))
  let loaded = products_route_test_load(guide, products_test_catalog())
  assert_eq(loaded.page, Guide)
  assert_eq(loaded.products.selected_id, "moondesk")
  assert_eq(products_route_test_param("page"), "guide")
  assert_eq(products_route_test_param("product"), "moondesk")
  let fresh = page_test_step(initial_model(), ProductsAction(Refresh))
  let fresh = page_test_step(fresh, saved_page_route())
  let fresh = products_route_test_load(fresh, products_test_catalog())
  assert_eq(fresh.page, Guide)
  assert_eq(fresh.products.selected_id, "moondesk")
  products_route_test_pop("https://example.test/?page=guide")
  let no_product = page_test_step(fresh, emitted[1])
  let no_product = products_route_test_load(no_product, products_test_catalog())
  assert_eq(no_product.page, Guide)
  assert_eq(no_product.products.selected_id, "")
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "product history invalidates stale detail project and task reads without touching prepared draft" {
  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook", "uuid",
  )
  let a = products_test_project(products_test_selected("moonbook"))
  let (_, prepared) = update(_ => none, ProductsAction(Prepare), a)
  let draft = dispatch_active_draft(prepared).unwrap()
  let browsing = { ..prepared, page: Products, }
  drafts_navigation_fresh_url(
    "https://example.test/?page=products&product=moondesk",
  )
  let b = page_test_step(browsing, saved_page_route())
  let b = products_route_test_load(b, products_test_catalog())
  assert_eq(b.products.selected_id, "moondesk")
  let before = b.products
  let stale = products_test_update(
    b,
    DetailRead("admission", "moonbook", a.products.selection, 200, "{}"),
  )
  let stale = products_test_update(
    stale,
    ProjectsRead(
      "moonbook",
      a.products.selection,
      a.products.project_request,
      200,
      "{\"items\":[]}",
    ),
  )
  let stale = products_test_update(
    stale,
    WorkRead(
      "moonbook",
      a.products.selection,
      "",
      a.products.work_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(stale.products, before)
  assert_eq(dispatch_draft_by_id(stale, draft.id), Some(draft))
  assert_eq(stale.dispatch_task_id, browsing.dispatch_task_id)
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "fragment-only movement after product writes does not restore routes or reset selection" {
  drafts_navigation_setup(
    "https://example.test/?page=products&keep=%23value", "uuid",
  )
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let selected = page_test_step(
    products_test_loaded(),
    ProductsAction(Select("moonbook")),
  )
  let url = page_test_url()
  products_route_test_pop(url + "#main-content")
  products_route_test_pop(url + "#another")
  assert_eq(emitted.length(), 0)
  assert_eq(selected.products.selected_id, "moonbook")
  assert_eq(drafts_navigation_metric("pushes"), 1)
  products_route_test_pop(url + "&keep=changed#main-content")
  assert_eq(emitted.length(), 1)
  let restored = page_test_step(selected, emitted[0])
  assert_eq(restored.products.selected_id, "moonbook")
  assert_true(page_test_url().has_suffix("#main-content"))
  products_route_test_read_only()
  drafts_navigation_cleanup()
}

///|
test "product engineering navigation records the displayed page with the same product context" {
  drafts_navigation_setup("https://example.test/?page=products", "uuid")
  let emitted : Array[Msg] = []
  drafts_test_execute(
    dispatch_history_listener(msg => {
      emitted.push(msg)
      none
    }),
  )
  let selected = page_test_step(
    products_test_loaded(),
    ProductsAction(Select("moonbook")),
  )
  let quality = page_test_step(
    selected,
    ProductsAction(OpenEngineering(Quality)),
  )
  assert_eq(quality.page, Quality)
  assert_eq(products_route_test_param("page"), "quality")
  assert_eq(products_route_test_param("product"), "moonbook")
  let fresh = page_test_step(initial_model(), ProductsAction(Refresh))
  let fresh = page_test_step(fresh, saved_page_route())
  let fresh = products_route_test_load(fresh, products_test_catalog())
  assert_eq(fresh.page, Quality)
  assert_eq(fresh.products.selected_id, "moonbook")
  drafts_navigation_move(-1)
  let back = page_test_step(quality, emitted[0])
  let back = products_route_test_load(back, products_test_catalog())
  assert_eq(back.page, Products)
  assert_eq(back.products.selected_id, "moonbook")
  drafts_navigation_move(1)
  let forward = page_test_step(back, emitted[1])
  assert_eq(forward.page, Quality)
  assert_eq(forward.products.selected_id, "moonbook")
  assert_eq(drafts_navigation_metric("pushes"), 2)
  products_route_test_read_only()
  drafts_navigation_cleanup()
}
