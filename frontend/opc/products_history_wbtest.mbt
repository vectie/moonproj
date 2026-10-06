///|
fn products_history_test_loaded(model : Model) -> Model {
  let loading = products_test_update(model, LoadWork)
  products_test_update(
    loading,
    WorkRead(
      loading.products.selected_id,
      loading.products.selection,
      "",
      loading.products.work_request,
      200,
      "{\"items\":[{\"taskGuid\":\"history-task\",\"product_id\":\"" +
      loading.products.selected_id +
      "\",\"projGuid\":\"company-shared\",\"taskName\":\"Product delivery\",\"status\":\"completed\"}]}",
    ),
  )
}

///|
test "Product history requests exact product without any project selection" {
  let selected = products_test_selected("moonbook")
  assert_eq(selected.products.project_id, "")
  assert_eq(selected.products.project_state, "idle")
  let loading = products_test_update(selected, LoadWork)
  assert_eq(loading.products.work_state, "loading")
  assert_eq(loading.products.work_request, selected.products.work_request + 1)
  assert_eq(
    products_work_url("moonbook"),
    "/api/company/tasks?product_id=moonbook",
  )
  let loaded = products_history_test_loaded(selected)
  assert_eq(loaded.products.work_state, "ready")
  assert_eq(loaded.products.tasks[0].product_id, "moonbook")
  assert_eq(loaded.products.project_id, "")
  let html = products_test_html(loaded)
  assert_true(html.contains("读取产品任务"))
  assert_true(html.contains("href=\"?task=history-task\""))
  assert_true(html.contains("Product delivery"))
  assert_false(html.contains("读取项目任务"))
}

///|
test "Product history spans projects but excludes legacy untagged company work" {
  let rows = products_decode_tasks(
    "{\"items\":[{\"taskGuid\":\"a\",\"product_id\":\"moonbook\",\"projGuid\":\"company-one\"},{\"taskGuid\":\"b\",\"product_id\":\"moonbook\",\"projGuid\":\"company-two\"},{\"taskGuid\":\"legacy-null\",\"product_id\":null,\"projGuid\":\"company-one\"},{\"taskGuid\":\"legacy-missing\",\"projGuid\":\"company-one\"}]}",
    "moonbook",
  ).unwrap()
  assert_eq(rows.map(task => task.id), ["a", "b"])
  assert_eq(rows.map(task => task.project_id), ["company-one", "company-two"])
  assert_true(rows.all(task => task.product_id == "moonbook"))
  let legacy = products_decode_tasks(
    "{\"items\":[{\"taskGuid\":\"legacy\",\"product_id\":null,\"projGuid\":\"company-shared\"}]}",
    "moonbook",
  ).unwrap()
  assert_true(legacy.is_empty())
}

///|
test "Product history rejects cross-product rows in the same company project" {
  let body = "{\"items\":[{\"taskGuid\":\"book-task\",\"product_id\":\"moonbook\",\"projGuid\":\"company-shared\"}]}"
  assert_eq(products_decode_tasks(body, "moondesk"), None)
  assert_eq(products_decode_tasks(body, ""), None)
  for malformed in ["{}", "{\"items\":[42]}", "{\"items\":[{}]}"] {
    assert_eq(products_decode_tasks(malformed, "moonbook"), None)
  }
  for replacement in ["null", "false", "42", "{}", "[]"] {
    let malformed = body.replace(old="\"moonbook\"", new=replacement)
    if replacement == "null" {
      assert_eq(products_decode_tasks(malformed, "moonbook"), Some([]))
    } else {
      assert_eq(products_decode_tasks(malformed, "moonbook"), None)
    }
  }
  assert_eq(
    products_decode_tasks(
      body.replace(old="company-shared", new=""),
      "moonbook",
    ),
    None,
  )
  let a = products_history_test_loaded(products_test_selected("moonbook"))
  let b = products_history_test_loaded(
    products_test_update(a, Select("moondesk")),
  )
  assert_eq(b.products.tasks.map(task => task.product_id), ["moondesk"])
  assert_eq(b.products.tasks[0].project_id, "company-shared")
}

///|
test "Product A to B to A rejects old history success failure and repeated refresh" {
  let a = products_test_update(products_test_selected("moonbook"), LoadWork)
  let b = products_test_update(
    products_test_update(a, Select("moondesk")),
    LoadWork,
  )
  let again = products_test_update(
    products_test_update(b, Select("moonbook")),
    LoadWork,
  )
  for current in [b, again] {
    for (status, body) in [(200, "{\"items\":[]}"), (401, "{}"), (0, "")] {
      let stale = products_test_update(
        current,
        WorkRead(
          "moonbook",
          a.products.selection,
          "",
          a.products.work_request,
          status,
          body,
        ),
      )
      assert_eq(stale.products, current.products)
    }
  }
  let refreshed = products_test_update(again, LoadWork)
  let stale = products_test_update(
    refreshed,
    WorkRead(
      "moonbook",
      again.products.selection,
      "",
      again.products.work_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(stale.products, refreshed.products)
  let current = products_test_update(
    stale,
    WorkRead(
      "moonbook",
      refreshed.products.selection,
      "",
      refreshed.products.work_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(current.products.work_state, "empty")
}

///|
test "Company project picker changes and reloads preserve product history" {
  let history = products_history_test_loaded(products_test_selected("moonbook"))
  let selectable = {
    ..history,
    products: {
      ..history.products,
      project_state: "ready",
      projects: [
        { id: "company-one", name: "One", source: "command", },
        { id: "company-two", name: "Two", source: "command", },
      ],
    },
  }
  for action in [SelectProject("company-two"), LoadProjects] {
    let changed = products_test_update(selectable, action)
    assert_eq(changed.products.tasks, history.products.tasks)
    assert_eq(changed.products.work_state, "ready")
    assert_eq(changed.products.work_request, history.products.work_request)
  }
  let loading = products_test_update(selectable, LoadWork)
  let changed = products_test_update(loading, SelectProject("company-two"))
  let loaded = products_test_update(
    changed,
    WorkRead(
      "moonbook",
      loading.products.selection,
      "",
      loading.products.work_request,
      200,
      "{\"items\":[]}",
    ),
  )
  assert_eq(loaded.products.work_state, "empty")
  assert_eq(loaded.products.project_id, "company-two")
}

///|
test "Opening product history verifies exact list identity without consulting the project picker" {
  let history = products_history_test_loaded(products_test_selected("moonbook"))
  let opened = products_test_update(history, OpenTask("history-task"))
  assert_eq(opened.page, Dispatch)
  assert_eq(opened.dispatch_task_id, "history-task")
  assert_eq(opened.dispatch_task_pending_action, "load")
  let absent = products_test_update(history, OpenTask("other-task"))
  assert_eq(absent.dispatch_task_id, history.dispatch_task_id)
  let cross_product = {
    ..history,
    products: {
      ..history.products,
      tasks: [{ ..history.products.tasks[0], product_id: "moondesk", }],
    },
  }
  let blocked = products_test_update(cross_product, OpenTask("history-task"))
  assert_eq(blocked.dispatch_task_id, cross_product.dispatch_task_id)
  assert_eq(blocked.page, Products)
  assert_false(products_test_html(cross_product).contains("?task=history-task"))
}

///|
test "Product task permalink retains the exact encoded task identity" {
  let history = products_history_test_loaded(products_test_selected("moonbook"))
  let encoded = {
    ..history,
    products: {
      ..history.products,
      tasks: [{ ..history.products.tasks[0], id: "task A/&?#", }],
    },
  }
  assert_true(
    products_test_html(encoded).contains("href=\"?task=task%20A%2F%26%3F%23\""),
  )
}
