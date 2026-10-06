///|
// Relevant fields from a source-derived native-created project list projection,
// not an HTTP capture.
// project_source_create_request defaults if_end=true and proj_status=initiation;
// project_source_command persists state=active. project_plan_project_item keeps
// those legacy flags in the API list but does not publish the projection state.
fn products_test_native_project_list() -> String {
  let body =
    #| {"items":[{"project_id":"native-created-project","project_code":"NATIVE-001","project_name":"Native created project","if_end":true,"proj_status":"initiation","source_kind":"command"}]}
  body
}

///|
fn products_test_project_list(model : Model, body : String) -> Model {
  let loading = products_test_update(model, LoadProjects)
  products_test_update(
    loading,
    ProjectsRead(
      loading.products.selected_id,
      loading.products.selection,
      loading.products.project_request,
      200,
      body,
    ),
  )
}

///|
fn products_test_native_project() -> Model {
  products_test_update(
    products_test_project_list(
      products_test_selected("moonbook"),
      products_test_native_project_list(),
    ),
    SelectProject("native-created-project"),
  )
}

///|
test "Native-created project with if_end true is selectable and prepares its exact identity" {
  let selected = products_test_native_project()
  assert_eq(selected.products.project_state, "ready")
  assert_true(products_project_exists(selected.products))
  let html = products_test_html(selected)
  assert_true(html.contains("Native created project · native-created-project"))
  assert_true(html.contains("准备任务"))
  assert_false(html.contains("已结束"))
  assert_false(html.contains("不能准备"))
  let (command, prepared) = update(_ => none, ProductsAction(Prepare), selected)
  assert_eq(products_test_effect_count(command), 2)
  assert_true(prepared.dispatch_task_form_open)
  let draft = dispatch_active_draft(prepared).unwrap()
  assert_eq(draft.product_id, "moonbook")
  assert_eq(draft.project_id, "native-created-project")
  assert_eq(draft.product_snapshot, products_selected(selected.products))
  assert_eq(draft.workspace, "")
  assert_eq(prepared.dispatch_task_id, "")
}

///|
test "Listed project eligibility ignores proj_status and if_end without adding admission gates" {
  for
    status in [
      "initiation", "active", "inactive", "completed", "custom-status", "",
    ] {
    for legacy_end in ["true", "false", "null", "\"legacy\""] {
      let body = products_test_native_project_list()
        .replace(
          old="\"proj_status\":\"initiation\"",
          new="\"proj_status\":\"" + status + "\"",
        )
        .replace(old="\"if_end\":true", new="\"if_end\":" + legacy_end)
      let listed = products_test_project_list(
        products_test_selected("moonfort"),
        body,
      )
      let selected = products_test_update(
        listed,
        SelectProject("native-created-project"),
      )
      assert_eq(selected.products.engineering_state, "not_enrolled")
      assert_eq(selected.products.admission_state, "loading")
      assert_true(products_project_exists(selected.products))
      let prepared = products_test_update(selected, Prepare)
      assert_eq(
        dispatch_active_draft(prepared).unwrap().project_id,
        "native-created-project",
      )
      assert_eq(dispatch_active_draft(prepared).unwrap().product_id, "moonfort")
    }
  }
  let minimal = products_test_project_list(
    products_test_selected("moonbook"),
    "{\"items\":[{\"project_id\":\"minimal\",\"project_name\":\"Minimal\"}]}",
  )
  let prepared = products_test_update(
    products_test_update(minimal, SelectProject("minimal")),
    Prepare,
  )
  assert_eq(dispatch_active_draft(prepared).unwrap().project_id, "minimal")
}

///|
test "Project preparation still requires successful current list membership" {
  let selected = products_test_native_project()
  for
    state in [
      "idle", "loading", "empty", "invalid", "unauthorized", "offline", "unavailable",
    ] {
    let unavailable = {
      ..selected,
      products: { ..selected.products, project_state: state, },
    }
    let (command, blocked) = update(
      _ => none,
      ProductsAction(Prepare),
      unavailable,
    )
    assert_eq(products_test_effect_count(command), 0)
    assert_false(blocked.dispatch_task_form_open)
    assert_true(blocked.dispatch_drafts.is_empty())
    assert_false(products_project_exists(unavailable.products))
  }
  let absent = { ..selected, products: { ..selected.products, projects: [], }, }
  let (command, blocked) = update(_ => none, ProductsAction(Prepare), absent)
  assert_eq(products_test_effect_count(command), 0)
  assert_true(blocked.dispatch_drafts.is_empty())
  assert_false(products_project_exists(absent.products))
  for
    body in [
      "{}", "{\"items\":[{}]}", "{\"items\":[{\"project_id\":\"id\",\"project_name\":\"\"}]}",
      "{\"items\":[{\"project_id\":\"id\",\"project_name\":\"One\"},{\"project_id\":\"id\",\"project_name\":\"Two\"}]}",
    ] {
    assert_eq(products_decode_projects(body), None)
  }
}

///|
test "Catalog project mapping needs listed identity but no legacy status approval" {
  let initial = products_test_selected("moonbook")
  let row = products_selected(initial.products).unwrap()
  for
    (mapping, expected) in [
      ("native-created-project", "native-created-project"),
      ("missing-project", ""),
    ] {
    let mapped = {
      ..initial,
      products: {
        ..initial.products,
        rows: [{ ..row, company_project_id: mapping, }],
      },
    }
    let listed = products_test_project_list(
      mapped,
      products_test_native_project_list(),
    )
    assert_eq(listed.products.project_id, expected)
    assert_eq(products_project_exists(listed.products), !expected.is_empty())
    let prepared = products_test_update(listed, Prepare)
    assert_eq(prepared.dispatch_task_form_open, !expected.is_empty())
  }
}

///|
test "Project removal on refresh blocks new preparation without rewriting parked draft or accepting late list" {
  let prepared = products_test_update(products_test_native_project(), Prepare)
  let original = dispatch_active_draft(prepared).unwrap()
  let parked = products_test_update(prepared, CancelPreparation)
  let first = products_test_update(parked, LoadProjects)
  let second = products_test_update(first, LoadProjects)
  let missing = products_test_update(
    second,
    ProjectsRead(
      second.products.selected_id,
      second.products.selection,
      second.products.project_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(missing.products.project_state, "empty")
  assert_eq(missing.products.project_id, "")
  assert_eq(dispatch_draft_by_id(missing, original.id), Some(original))
  for
    (status, body) in [
      (200, products_test_native_project_list()),
      (401, "{}"),
      (0, ""),
    ] {
    let late = products_test_update(
      missing,
      ProjectsRead(
        first.products.selected_id,
        first.products.selection,
        first.products.project_request,
        status,
        body,
      ),
    )
    assert_eq(late.products, missing.products)
    assert_eq(late.dispatch_drafts, missing.dispatch_drafts)
  }
  let (command, blocked) = update(_ => none, ProductsAction(Prepare), missing)
  assert_eq(products_test_effect_count(command), 0)
  assert_false(blocked.dispatch_task_form_open)
  assert_eq(blocked.dispatch_drafts, parked.dispatch_drafts)
}

///|
test "Project deleted after listing preserves create-time service409 and immutable draft identities" {
  let selected = {
    ..products_test_native_project(),
    dispatch_task_actor_id: "actor-project-test",
  }
  let prepared = products_test_update(selected, Prepare)
  let original = dispatch_active_draft(prepared).unwrap()
  let valid = dispatch_replace_draft(prepared, {
    ..original,
    title: "Deliver native project work",
    acceptance: "Verify saved output",
    workspace: "/explicit/workspace",
    begin_date: "2026-10-02",
    end_date: "2026-10-03",
  })
  let saving = drafts_test_update(valid, Create)
  let creating = drafts_test_update(
    saving,
    Stored("actor-project-test", original.id, true),
  )
  assert_eq(dispatch_active_draft(creating).unwrap().state, "creating")
  // The project can disappear after this read. The server rechecks membership;
  // its exact pre-transaction rejection is not converted into a successful task.
  let rejected = drafts_test_update(
    creating,
    CreateRead(
      "actor-project-test",
      original.id,
      409,
      "{\"error\":\"project-plan task requires an active project identity\"}",
    ),
  )
  let draft = dispatch_active_draft(rejected).unwrap()
  assert_eq(draft.state, "rejected")
  assert_eq(draft.task_id, original.task_id)
  assert_eq(draft.idempotency_key, original.idempotency_key)
  assert_eq(draft.project_id, "native-created-project")
  assert_eq(draft.product_id, "moonbook")
  assert_eq(draft.product_snapshot, original.product_snapshot)
  assert_eq(rejected.dispatch_task_id, "")
  let ambiguous = drafts_test_update(
    creating,
    CreateRead(
      "actor-project-test",
      original.id,
      409,
      "{\"error\":\"idempotency conflict\"}",
    ),
  )
  assert_eq(dispatch_active_draft(ambiguous).unwrap().state, "uncertain")
  let revised = drafts_test_update(rejected, Revise(original.id))
  assert_eq(dispatch_draft_by_id(revised, original.id), Some(draft))
  assert_true(
    dispatch_active_draft(revised).unwrap().task_id != original.task_id,
  )
}
