///|
test "chosen outcome survives the required project selection before preparing a packet" {
  let chosen = products_test_update(
    products_inventory_test_model(),
    PrepareWork("moonbook", "book-lifecycle"),
  )
  assert_eq(chosen.dispatch_drafts.length(), 0)
  let with_project = products_test_project(chosen)
  let prepared = products_test_update(with_project, Prepare)
  let draft = dispatch_active_draft(prepared).unwrap()
  assert_true(draft.title.contains("book-lifecycle"))
  assert_true(draft.acceptance.contains("MOONBOOK-B01"))
  assert_true(draft.acceptance.contains("Identity survives restart"))
  assert_eq(draft.workspace, "")
  assert_false(draft.attempted)
}

///|
fn outcome_test_read(model : Model, status : Int, body : String) -> Model {
  products_test_update(
    model,
    ProjectsRead(
      model.products.selected_id,
      model.products.selection,
      model.products.project_request,
      status,
      body,
    ),
  )
}

///|
fn outcome_test_projects() -> String {
  let body =
    #|{"items":[{"project_id":"company-actual","project_name":"Actual company project","source_kind":"command","if_end":true,"proj_status":"initiation"}]}
  body
}

///|
test "choosing an outcome reads projects once and foregrounds the retained scope without creating work" {
  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook", "uuid",
  )
  let chosen = page_test_step(
    products_inventory_test_model(),
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  assert_eq(chosen.products.project_state, "loading")
  assert_eq(chosen.products.pending_work_group_id, "book-lifecycle")
  assert_eq(drafts_navigation_requests(), "GET /api/company/projects")
  let repeated = page_test_step(
    chosen,
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  assert_eq(repeated.products.project_request, chosen.products.project_request)
  assert_eq(drafts_navigation_requests(), "GET /api/company/projects")
  assert_eq(repeated.dispatch_drafts.length(), 0)
  assert_eq(repeated.dispatch_task_id, "")
  assert_eq(drafts_navigation_metric("pushes"), 0)
  let html = products_test_html(repeated)
  assert_true(
    guided_disclosure_visible(html, "已选择：Qualify Book lifecycle"),
  )
  assert_false(guided_disclosure_open(html, "所选工作的验收与范围"))
  assert_eq(guided_count(html, "下一步 · 准备一个目标"), 1)
  assert_true(
    guided_index(html, "已选择：Qualify Book lifecycle") <
    guided_index(html, "剩余工作 · 从目标 PRD 到可验收结果"),
  )
  assert_false(html.contains(">准备所选工作<"))
  let loaded = outcome_test_read(repeated, 200, outcome_test_projects())
  assert_eq(loaded.products.project_id, "")
  assert_eq(loaded.dispatch_drafts.length(), 0)
  let selected = products_test_update(loaded, SelectProject("company-actual"))
  assert_true(products_test_html(selected).contains(">准备所选工作<"))
  assert_eq(selected.dispatch_drafts.length(), 0)
  drafts_navigation_cleanup()
}

///|
test "project errors and empty results retain the chosen outcome until an explicit successful retry" {
  for
    (status, body, expected) in [
      (0, "", "offline"),
      (401, "{}", "unauthorized"),
      (403, "{}", "unauthorized"),
      (503, "{}", "unavailable"),
      (200, "{}", "invalid"),
      (200, "{\"items\":[]}", "empty"),
    ] {
    let chosen = products_test_update(
      products_inventory_test_model(),
      PrepareWork("moonbook", "book-lifecycle"),
    )
    let failed = outcome_test_read(chosen, status, body)
    assert_eq(failed.products.project_state, expected)
    assert_eq(failed.products.pending_work_group_id, "book-lifecycle")
    let html = products_test_html(failed)
    assert_true(
      guided_disclosure_visible(html, "已选择：Qualify Book lifecycle"),
    )
    assert_true(guided_disclosure_visible(html, products_state_label(expected)))
    assert_false(html.contains(">准备所选工作<"))
    let still_blocked = products_test_update(failed, Prepare)
    assert_eq(still_blocked.products.project_state, expected)
    assert_eq(still_blocked.dispatch_drafts.length(), 0)
    let retry = products_test_update(still_blocked, LoadProjects)
    let loaded = outcome_test_read(retry, 200, outcome_test_projects())
    let selected = products_test_update(loaded, SelectProject("company-actual"))
    let prepared = products_test_update(selected, Prepare)
    assert_true(
      dispatch_active_draft(prepared).unwrap().acceptance.contains(
        "MOONBOOK-B01",
      ),
    )
    assert_eq(prepared.products.pending_work_group_id, "")
  }
}

///|
test "changing or cancelling an outcome never reuses a stale scope or creates a task" {
  let first = products_inventory_fixture()
  let second = {
    ..first.groups[0],
    id: "book-second",
    title: "Second outcome",
  }
  let model = products_inventory_test_model()
  let model = {
    ..model,
    products: {
      ..model.products,
      inventories: [{ ..first, groups: first.groups + [second], }],
    },
  }
  let chosen = products_test_update(
    model,
    PrepareWork("moonbook", "book-lifecycle"),
  )
  let changed = products_test_update(
    chosen,
    PrepareWork("moonbook", "book-second"),
  )
  assert_eq(changed.products.pending_work_group_id, "book-second")
  assert_eq(changed.products.project_request, chosen.products.project_request)
  assert_eq(
    products_test_update(changed, PrepareWork("moonbook", "missing")).products,
    changed.products,
  )
  assert_eq(
    products_test_update(changed, PrepareWork("moonproj", "book-second")).products,
    changed.products,
  )
  let cancelled = products_test_update(changed, CancelWorkChoice)
  assert_eq(cancelled.products.pending_work_group_id, "")
  let late = outcome_test_read(cancelled, 200, outcome_test_projects())
  assert_eq(late.dispatch_drafts.length(), 0)
  let generic = products_test_update(
    products_test_update(late, SelectProject("company-actual")),
    Prepare,
  )
  assert_eq(dispatch_active_draft(generic).unwrap().acceptance, "")
  let other = products_test_update(changed, Select("moonproj"))
  let (_, stale) = products_update(
    _ => none,
    ProjectsRead(
      "moonbook",
      chosen.products.selection,
      chosen.products.project_request,
      200,
      outcome_test_projects(),
    ),
    other,
  )
  assert_eq(stale.products, other.products)
  assert_eq(stale.products.pending_work_group_id, "")
  let (_, back) = products_restore_route(_ => none, "moonbook", stale)
  assert_eq(back.products.pending_work_group_id, "")
  assert_eq(back.dispatch_drafts.length(), 0)
  let refreshed = products_test_update(
    changed,
    CatalogRead(
      changed.products.request,
      200,
      products_inventory_test_body(first),
    ),
  )
  assert_eq(refreshed.products.pending_work_group_id, "")
  let failed_catalog = products_test_update(
    changed,
    CatalogRead(changed.products.request, 503, "{}"),
  )
  assert_eq(failed_catalog.products.pending_work_group_id, "")
}

///|
test "repeated preparation close and stored draft restoration retain the same packet identity" {
  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook", "uuid",
  )
  let chosen = page_test_step(
    {
      ..products_inventory_test_model(),
      dispatch_task_actor_id: "actor-outcome",
    },
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  let selected = products_test_project(chosen)
  let prepared = page_test_step(selected, ProductsAction(Prepare))
  let draft = dispatch_active_draft(prepared).unwrap()
  let repeated = page_test_step(prepared, ProductsAction(Prepare))
  assert_eq(repeated.dispatch_drafts.length(), 1)
  assert_eq(dispatch_active_draft(repeated), Some(draft))
  let closed = page_test_step(repeated, ProductsAction(CancelPreparation))
  assert_false(closed.dispatch_task_form_open)
  assert_eq(closed.page, Products)
  assert_eq(closed.dispatch_drafts, prepared.dispatch_drafts)
  let resumed = page_test_step(
    closed,
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  assert_eq(dispatch_active_draft(resumed), Some(draft))
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-outcome", },
    Restored("actor-outcome", dispatch_read_drafts("actor-outcome")),
  )
  assert_eq(dispatch_draft_by_id(restored, draft.id), Some(draft))
  assert_eq(restored.dispatch_task_id, "")
  assert_eq(restored.products.pending_work_group_id, "")
  assert_false(drafts_navigation_requests().contains("POST"))
  assert_false(drafts_navigation_requests().contains("PUT"))
  drafts_navigation_cleanup()
}

///|
test "selected scope survives draft validation creation bytes and the existing native start route" {
  drafts_test_transport(false)
  let chosen = products_test_update(
    {
      ..products_inventory_test_model(),
      dispatch_task_actor_id: "actor-outcome",
    },
    PrepareWork("moonbook", "book-lifecycle"),
  )
  let prepared = products_test_update(products_test_project(chosen), Prepare)
  let blocked = drafts_test_update(prepared, Create)
  assert_eq(dispatch_active_draft(blocked).unwrap().state, "editing")
  assert_eq(drafts_test_post_count(), 0)
  let mut ready = blocked
  for
    (field, value) in [
      ("workspace", "/workspace/authorized-outcome"),
      ("begin_date", "2026-10-05"),
      ("end_date", "2026-10-06"),
    ] {
    ready = drafts_test_update(ready, Input(field, value))
  }
  let saving = drafts_test_update(ready, Create)
  let draft = dispatch_active_draft(saving).unwrap()
  let (post, creating) = dispatch_draft_update(
    _ => none,
    Stored("actor-outcome", draft.id, true),
    saving,
  )
  drafts_test_execute(post)
  assert_eq(drafts_test_post_count(), 1)
  let body = @json.parse(drafts_test_post_body(0))
  assert_eq(products_text(body, "task_id"), draft.task_id)
  assert_eq(products_text(body, "product_id"), "moonbook")
  assert_eq(products_text(body, "project_id"), "company-actual")
  assert_eq(
    products_text(body, "execution_workspace"),
    "/workspace/authorized-outcome",
  )
  assert_true(products_text(body, "remarks").contains("MOONBOOK-B01"))
  assert_true(
    products_text(body, "remarks").contains("Identity survives restart"),
  )
  assert_false(dispatch_can_start(creating))
  // Existing canonical read contract: this is an injected fixture response,
  // not a claim that a live company or provider accepted the packet.
  let canonical = (
    {
      "data": {
        "task": {
          "taskGuid": draft.task_id,
          "taskName": draft.title,
          "product_id": "moonbook",
          "projGuid": "company-actual",
          "status": "pending",
          "remarks": products_text(body, "remarks"),
          "execution_workspace": "/workspace/authorized-outcome",
        },
        "reports": [],
      },
    } : Json).stringify()
  let recovered = apply_dispatch_snapshot(
    creating,
    dispatch_decode_snapshot(canonical, draft.task_id).unwrap(),
  )
  assert_true(dispatch_can_start(recovered))
  assert_eq(drafts_test_post_count(), 1)
  let (start, starting) = update(_ => none, StartDispatchTask, recovered)
  drafts_test_execute(start)
  assert_eq(drafts_test_post_count(), 2)
  assert_true(
    drafts_test_events().contains(
      "POST /api/company/plan/tasks/" + draft.task_id + "/dispatch",
    ),
  )
  assert_eq(starting.dispatch_task_pending_action, "start")
  assert_false(dispatch_can_start(starting))
  assert_eq(starting.dispatch_task_report_id, "")
  assert_eq(starting.dispatch_task_stage, "pending")
  drafts_test_transport_cleanup()
}

///|
test "product Back and Forward do not revive cancelled pending scope or accept stale project reads" {
  drafts_navigation_setup(
    "https://example.test/?page=products&product=moonbook", "uuid",
  )
  let chosen = page_test_step(
    products_inventory_test_model(),
    ProductsAction(PrepareWork("moonbook", "book-lifecycle")),
  )
  let other = page_test_step(chosen, ProductsAction(Select("moondesk")))
  assert_eq(other.products.pending_work_group_id, "")
  drafts_navigation_move(-1)
  let back = page_test_step(other, saved_page_route())
  assert_eq(back.products.selected_id, "moonbook")
  assert_eq(back.products.pending_work_group_id, "")
  let late = page_test_step(
    back,
    ProductsAction(
      ProjectsRead(
        "moonbook",
        chosen.products.selection,
        chosen.products.project_request,
        200,
        outcome_test_projects(),
      ),
    ),
  )
  assert_eq(late.products.project_state, "idle")
  assert_eq(late.products.projects.length(), 0)
  drafts_navigation_move(1)
  let forward = page_test_step(late, saved_page_route())
  assert_eq(forward.products.selected_id, "moondesk")
  assert_eq(forward.products.pending_work_group_id, "")
  assert_eq(forward.dispatch_drafts.length(), 0)
  assert_false(drafts_navigation_requests().contains("POST"))
  drafts_navigation_cleanup()
}

///|
test "outcome continuation preserves an edited or uncertain existing packet and running task" {
  for phase in ["editing", "uncertain"] {
    let source = products_test_update(
      products_test_project(products_inventory_test_model()),
      PrepareWork("moonbook", "book-lifecycle"),
    )
    let original = dispatch_active_draft(source).unwrap()
    let saved = {
      ..original,
      acceptance: "Owner's existing criterion",
      state: phase,
      attempted: phase == "uncertain",
      recovery_required: phase == "uncertain",
    }
    let original_task = apply_dispatch_snapshot(
      source,
      dispatch_test_snapshot("running"),
    )
    let model = dispatch_replace_draft(original_task, saved)
    let unloaded = products_test_update(model, LoadProjects)
    let chosen = products_test_update(
      unloaded,
      PrepareWork("moonbook", "book-lifecycle"),
    )
    let prepared = products_test_update(products_test_project(chosen), Prepare)
    assert_eq(dispatch_active_draft(prepared), Some(saved))
    assert_eq(prepared.dispatch_drafts.length(), 1)
    assert_eq(prepared.dispatch_run, model.dispatch_run)
    assert_eq(prepared.dispatch_task_id, model.dispatch_task_id)
    assert_eq(prepared.dispatch_task_stage, model.dispatch_task_stage)
    assert_true(prepared.notice.contains("保留你的修改"))
    assert_eq(prepared.products.pending_work_group_id, "")
  }
}
