///|
fn products_inventory_fixture() -> @work_inventory.Inventory {
  {
    schema: "moonsuite.product-work-inventory.v1",
    product_id: "moonbook",
    as_of: "2026-10-04",
    origin: "packaged_prd_assessment",
    source_scope: "Recovered source; no installed parity",
    current_gap: "Host journey unverified",
    vision_scope: "Experienced-agent vision still needs decomposition",
    full_target_estimate: "Unknown beyond this bounded milestone",
    next_milestone: {
      title: "Qualify Book lifecycle",
      estimate_low_days: Some(2),
      estimate_high_days: Some(5),
      unit: "engineer-days",
      confidence: "low",
      scope: "One scoped fixture journey",
      linked_group_id: Some("book-lifecycle"),
    },
    prd_source: "MoonBook_PRD.docx",
    prd_sha256: "fixture",
    philosophy: ["Reviewed memory"],
    non_goals: ["Do not infer acceptance"],
    requirements: [
      {
        id: "MOONBOOK-B01",
        title: "Book lifecycle",
        track: "baseline",
        priority: "P0",
        statement: "Keep Book identity",
        acceptance: ["Reopen the same identity"],
        dependencies: ["Host"],
        historical_status: "Source documented",
        historical_evidence: ["PRD snapshot"],
        status: "partial",
        reason: "Only contract evidence",
        evidence: ["source/file.mbt"],
      },
    ],
    groups: [
      {
        id: "book-lifecycle",
        title: "Qualify Book lifecycle",
        requirement_ids: ["MOONBOOK-B01"],
        status: "partial",
        next_action: "Reopen a reviewed fixture",
        acceptance: ["Identity survives restart"],
        dependencies: ["Prepared host"],
        estimate_low_days: Some(2),
        estimate_high_days: Some(5),
        estimate_scope: "Only verification, not full product",
        confidence: "low",
        assumptions: ["One engineer with prepared host"],
        evidence: ["source/file.mbt"],
      },
    ],
  }
}

///|
fn products_inventory_test_body(
  inventory : @work_inventory.Inventory,
) -> String {
  let root = try! @json.parse(products_test_catalog())
  guard root is Object(fields) else { abort("fixture object") }
  guard fields["products"] is Array(rows) else { abort("fixture rows") }
  for row in rows {
    if row is Object(item) && item.get("id") == Some(Json::string("moonbook")) {
      item["work_inventory"] = inventory.to_json()
    }
  }
  fields["work_inventory_state"] = Json::string("ready")
  root.stringify()
}

///|
fn products_inventory_test_model() -> Model {
  products_test_update(
    products_test_update(
      initial_model(),
      CatalogRead(
        0,
        200,
        products_inventory_test_body(products_inventory_fixture()),
      ),
    ),
    Select("moonbook"),
  )
}

///|
// Test-only filesystem access. The browser product reads the authenticated API.
extern "js" fn products_inventory_test_packaged_json() -> String =
  #| () => require("node:fs").readFileSync("config/moonsuite-work-inventory.json", "utf8")

///|
test "all twenty packaged work inventories decode render and retain every requirement identity" {
  let root = @json.parse(products_test_catalog())
  guard root is Object(fields) else { fail("Catalog fixture") }
  guard fields["products"] is Array(rows) else { fail("Product rows") }
  let source = @json.parse(products_inventory_test_packaged_json())
  let inventories = @work_inventory.parse_portfolio(
    source,
    rows.map(row => products_text(row, "id")),
  )
  for row in rows {
    guard row is Object(item) else { fail("Product row") }
    let id = products_text(row, "id")
    item["work_inventory"] = inventories.filter(inventory => {
      inventory.product_id == id
    })[0].projection()
  }
  fields["work_inventory_state"] = "ready".to_json()
  let loaded = products_test_update(
    initial_model(),
    CatalogRead(0, 200, root.stringify()),
  )
  assert_eq(loaded.products.inventories.length(), 20)
  assert_eq(
    loaded.products.inventories.fold(init=0, (count, item) => {
      count + item.requirements.length()
    }),
    344,
  )
  for inventory in inventories {
    let selected = products_test_update(loaded, Select(inventory.product_id))
    let html = products_test_html(selected)
    assert_true(html.contains(inventory.full_target_estimate))
    assert_true(html.contains("建议下一交付"))
    assert_true(html.contains(inventory.next_milestone.title))
    for row in inventory.requirements {
      assert_true(html.contains(row.id))
    }
    assert_eq(selected.dispatch_drafts.length(), 0)
    assert_eq(selected.dispatch_task_id, loaded.dispatch_task_id)
  }
}

///|
test "inventory renders scoped work before full requirement detail without claiming database import" {
  let model = products_inventory_test_model()
  assert_eq(model.products.inventories.length(), 1)
  let html = products_test_html(model)
  for
    expected in [
      "未写入公司数据库", "工程人日", "MOONBOOK-B01", "Experienced-agent",
      "准备此工作", "LunaNexa",
    ] {
    assert_true(html.contains(expected))
  }
  assert_false(html.contains("100%"))
  let filtered = products_test_update(model, FilterWork("verified"))
  assert_eq(
    products_inventory_visible(
      filtered.products,
      filtered.products.inventories[0],
    ).length(),
    0,
  )
  let searched = products_test_update(model, SearchWork("MOONBOOK-B01"))
  assert_eq(
    products_inventory_visible(
      searched.products,
      searched.products.inventories[0],
    ).length(),
    1,
  )
  assert_eq(searched.products.selected_id, "moonbook")
  let selected = products_test_update(searched, Select("moonproj"))
  assert_eq(selected.products.inventory_query, "")
  assert_eq(selected.products.inventory_filter, "all")
}

///|
test "inventory preparation requires a real project and preserves canonical task state" {
  let model = products_inventory_test_model()
  let blocked = products_test_update(
    model,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  assert_eq(blocked.dispatch_drafts.length(), 0)
  assert_true(blocked.notice.contains("读取公司项目"))
  let selected = products_test_project(model)
  let ready = products_test_update(
    selected,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  let draft = dispatch_active_draft(ready).unwrap()
  assert_eq(draft.product_id, "moonbook")
  assert_eq(draft.project_id, "company-actual")
  assert_true(draft.title.contains("book-lifecycle"))
  assert_true(draft.acceptance.contains("MOONBOOK-B01"))
  assert_false(draft.attempted)
  assert_eq(draft.workspace, "")
  assert_eq(ready.dispatch_task_id, selected.dispatch_task_id)
  assert_eq(ready.dispatch_task_title, selected.dispatch_task_title)
  assert_false(
    draft.product_snapshot.to_json().stringify().contains("work_inventory"),
  )
  let again = products_test_update(
    ready,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  assert_eq(again.dispatch_drafts.length(), 1)
  assert_eq(dispatch_active_draft(again), Some(draft))
}

///|
test "inventory preparation cannot overwrite edited or uncertain drafts or cross product identity" {
  let model = products_test_project(products_inventory_test_model())
  let ready = products_test_update(
    model,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  let (_, edited) = dispatch_draft_update(
    _ => none,
    Input("acceptance", "My exact acceptance"),
    ready,
  )
  let preserved = products_test_update(
    edited,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  assert_eq(
    dispatch_active_draft(preserved).unwrap().acceptance,
    "My exact acceptance",
  )
  assert_true(preserved.notice.contains("保留你的修改"))
  let old = dispatch_active_draft(preserved).unwrap()
  let uncertain = dispatch_replace_draft(preserved, {
    ..old,
    state: "uncertain",
    attempted: true,
    recovery_required: true,
  })
  let same = products_test_update(
    uncertain,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  assert_eq(same.dispatch_drafts, uncertain.dispatch_drafts)
  assert_eq(
    products_test_update(same, PrepareWork("moonproj", "book-lifecycle")).dispatch_drafts,
    same.dispatch_drafts,
  )
  assert_eq(
    products_test_update(same, PrepareWork("moonbook", "unknown")).dispatch_drafts,
    same.dispatch_drafts,
  )
}

///|
test "missing and malformed inventories do not become zero remaining work or stale assessments" {
  let old = products_test_loaded()
  assert_true(old.products.inventories.is_empty())
  let html = products_test_html(products_test_update(old, Select("moonbook")))
  assert_true(html.contains("没有将缺失清单解释为零剩余工作"))
  let loaded = products_inventory_test_model()
  let failed = products_test_update(loaded, CatalogRead(0, 503, "{}"))
  assert_true(failed.products.inventories.is_empty())
  let bad = { ..products_inventory_fixture(), product_id: "moonproj", }
  let invalid = products_test_update(
    loaded,
    CatalogRead(0, 200, products_inventory_test_body(bad)),
  )
  assert_eq(invalid.products.state, "ready")
  assert_eq(invalid.products.inventory_state, "invalid")
  assert_eq(invalid.products.rows.length(), 20)
  assert_true(invalid.products.inventories.is_empty())
}

///|
test "preparing inventory work participates in page history without task creation" {
  drafts_navigation_setup(
    "https://example.test/console?page=products&product=moonbook", "inventory-nonce",
  )
  let initial = products_test_project(products_inventory_test_model())
  let prepared = page_test_step(
    initial,
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  assert_eq(prepared.page, Dispatch)
  assert_eq(saved_page_token(), "dispatch")
  assert_eq(products_route_test_param("product"), "moonbook")
  assert_eq(drafts_navigation_metric("pushes"), 1)
  let draft = dispatch_active_draft(prepared).unwrap()
  let again = page_test_step(
    prepared,
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  assert_eq(drafts_navigation_metric("pushes"), 1)
  assert_eq(dispatch_active_draft(again), Some(draft))
  drafts_navigation_move(-1)
  let back = page_test_step(again, saved_page_route())
  assert_eq(back.page, Products)
  assert_eq(back.dispatch_drafts, prepared.dispatch_drafts)
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("PUT"))
  drafts_navigation_cleanup()
}
