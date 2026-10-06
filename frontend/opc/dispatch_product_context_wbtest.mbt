///|
fn dispatch_context_test_json(
  coverage? : String = "complete",
  artifact_state? : String = "available",
) -> Json {
  Json::object({
    "schema": "moonproj.product-context.v1".to_json(),
    "product_id": "product-a".to_json(),
    "product_name": "Captured product A".to_json(),
    "coverage": coverage.to_json(),
    "issues": ["Declared extraction scope"].to_json(),
    "context_path": ".moonproj/input/run-1/product-context.json".to_json(),
    "sha256": "captured-context-hash".to_json(),
    "size_bytes": (4096).to_json(),
    "prd": Json::object({
      "document_id": "prd-a".to_json(),
      "source_sha256": "captured-source-hash".to_json(),
      "source_size_bytes": (8192).to_json(),
      "version": "v-before-retag".to_json(),
      "coverage": coverage.to_json(),
      "text_sha256": "captured-text-hash".to_json(),
      "text_size_bytes": (1024).to_json(),
      "extraction_version": "visible-body-v1".to_json(),
      "limitations": ["Tables retain text only"].to_json(),
      "text": "PRIVATE_PRD_TEXT_MUST_NOT_RENDER".to_json(),
    }),
    "artifact_state": artifact_state.to_json(),
    "artifact_error": "".to_json(),
  })
}

///|
fn dispatch_context_test_replace(
  value : Json,
  key : String,
  field : Json,
) -> Json {
  guard value is Object(fields) else { return value }
  fields[key] = field
  value
}

///|
fn dispatch_context_test_response(context? : Json) -> String {
  let execution : Map[String, Json] = {
    "run_id": "run-1".to_json(),
    "task_id": "task-1".to_json(),
    "session_id": "session-1".to_json(),
    "command_id": "command-1".to_json(),
    "workspace": "/workspace/captured".to_json(),
    "state": "completed".to_json(),
    "summary": "Exact native answer".to_json(),
    "output_urls": ["https://example.test/actual-output"].to_json(),
  }
  if context is Some(value) {
    execution["product_context"] = value
  }
  Json::object({
    "data": Json::object({
      "task": Json::object({
        "taskGuid": "task-1".to_json(),
        "product_id": "product-b".to_json(),
        "status": "in_progress".to_json(),
        "execution": Json::object(execution),
      }),
      "reports": Json::array([]),
    }),
  }).stringify()
}

///|
#warnings("-alert_unstable")
fn dispatch_context_test_render(model : Model) -> String {
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    _,
    model,
  ) => dispatch_native_result(model))
  @rabbita.render_to_string(page)
}

///|
test "run context decodes public snapshot provenance without changing native identity" {
  let response = dispatch_context_test_response(
    context=dispatch_context_test_json(),
  )
  let snapshot = dispatch_decode_snapshot(response, "task-1").unwrap()
  let run = snapshot.run.unwrap()
  guard run.product_context is Captured(context) else {
    fail("missing captured context")
  }
  assert_eq(context.product_id, "product-a")
  assert_eq(context.product_name, "Captured product A")
  assert_eq(context.coverage, "complete")
  assert_eq(context.artifact_state, "available")
  assert_eq(context.size_bytes, 4096.0)
  assert_eq(context.prd.unwrap().document_id, Some("prd-a"))
  assert_eq(context.prd.unwrap().text_size_bytes, Some(1024.0))
  assert_eq(run.run_id, "run-1")
  assert_eq(run.task_id, "task-1")
  assert_eq(run.session_id, "session-1")
  assert_eq(run.command_id, "command-1")
  assert_eq(run.summary, "Exact native answer")
  assert_eq(snapshot.product_id, "product-b")
  let model = apply_dispatch_snapshot(initial_model(), snapshot)
  assert_eq(model.dispatch_task_stage, "in_progress")
  assert_eq(model.dispatch_task_report_id, "")
  assert_true(dispatch_can_submit(model))
}

///|
test "legacy and untagged execution context stays unbound even on a tagged current task" {
  for
    response in [
      dispatch_context_test_response(),
      dispatch_context_test_response(context=Json::null()),
    ] {
    let snapshot = dispatch_decode_snapshot(response, "task-1").unwrap()
    assert_eq(snapshot.product_id, "product-b")
    assert_eq(snapshot.run.unwrap().product_context, Unbound)
    let html = dispatch_context_test_render(
      apply_dispatch_snapshot(initial_model(), snapshot),
    )
    assert_true(html.contains("未绑定（未记录运行快照）"))
    assert_true(html.contains("Exact native answer"))
    assert_false(html.contains("本次执行捕获产品"))
  }
}

///|
test "malformed optional context never rejects otherwise valid task and execution readback" {
  for
    context in [
      "wrong shape".to_json(),
      Json::array([]),
      Json::object({}),
      dispatch_context_test_replace(
        dispatch_context_test_json(),
        "coverage",
        (3).to_json(),
      ),
      dispatch_context_test_replace(
        dispatch_context_test_json(),
        "issues",
        "not an array".to_json(),
      ),
      dispatch_context_test_replace(
        dispatch_context_test_json(),
        "prd",
        true.to_json(),
      ),
    ] {
    let snapshot = dispatch_decode_snapshot(
      dispatch_context_test_response(context~),
      "task-1",
    ).unwrap()
    let run = snapshot.run.unwrap()
    assert_eq(run.product_context, Malformed)
    assert_eq(run.command_id, "command-1")
    assert_eq(run.state, "completed")
    let model = apply_dispatch_snapshot(initial_model(), snapshot)
    assert_true(dispatch_can_submit(model))
    let html = dispatch_context_test_render(model)
    assert_true(html.contains("元数据无法读取"))
    assert_true(html.contains("Exact native answer"))
    assert_true(html.contains("href=\"https://example.test/actual-output\""))
  }
}

///|
test "future context schema is explicit and nonfatal while unknown v1 fields are ignored" {
  let future = dispatch_context_test_replace(
    dispatch_context_test_json(),
    "schema",
    "moonproj.product-context.v2".to_json(),
  )
  let snapshot = dispatch_decode_snapshot(
    dispatch_context_test_response(context=future),
    "task-1",
  ).unwrap()
  assert_eq(
    snapshot.run.unwrap().product_context,
    Unsupported("moonproj.product-context.v2"),
  )
  let html = dispatch_context_test_render(
    apply_dispatch_snapshot(initial_model(), snapshot),
  )
  assert_true(html.contains("暂不支持此版本"))
  assert_true(html.contains("Exact native answer"))
  let extended = dispatch_context_test_replace(
    dispatch_context_test_json(),
    "future_optional",
    Json::object({}),
  )
  assert_true(dispatch_decode_product_context(extended) is Captured(_))
}

///|
test "invalid context byte counts and unknown states cannot claim valid completeness" {
  for value in [-1.0, 0.5, 9007199254740992.0] {
    let context = dispatch_context_test_replace(
      dispatch_context_test_json(),
      "size_bytes",
      value.to_json(),
    )
    assert_eq(dispatch_decode_product_context(context), Malformed)
    let prd = Json::object({ "text_size_bytes": value.to_json() })
    assert_eq(
      dispatch_decode_product_context(
        dispatch_context_test_replace(dispatch_context_test_json(), "prd", prd),
      ),
      Malformed,
    )
  }
  for key in ["coverage", "artifact_state"] {
    assert_eq(
      dispatch_decode_product_context(
        dispatch_context_test_replace(
          dispatch_context_test_json(),
          key,
          "future-value".to_json(),
        ),
      ),
      Malformed,
    )
  }
}

///|
test "missing and sparse PRD provenance remain optional" {
  for
    prd in [
      Json::null(),
      Json::object({ "document_id": "sparse-prd".to_json() }),
      Json::object({
        "document_id": Json::null(),
        "text_size_bytes": Json::null(),
        "limitations": Json::null(),
      }),
    ] {
    let context = dispatch_context_test_replace(
      dispatch_context_test_json(coverage="unavailable"),
      "prd",
      prd,
    )
    assert_true(dispatch_decode_product_context(context) is Captured(_))
  }
}

///|
test "captured product is separate from current association and live catalog edits" {
  let snapshot = dispatch_decode_snapshot(
    dispatch_context_test_response(context=dispatch_context_test_json()),
    "task-1",
  ).unwrap()
  let model = apply_dispatch_snapshot(initial_model(), snapshot)
  let html = dispatch_context_test_render(model)
  assert_true(
    html.contains("本次执行捕获产品 · Captured product A (product-a)"),
  )
  assert_true(html.contains("当前任务关联产品 · product-b"))
  assert_true(html.contains("v-before-retag"))
  assert_false(html.contains("本次执行捕获产品 · product-b"))
  let retagged = { ..model, dispatch_task_product_id: "product-c", }
  let updated = dispatch_context_test_render(retagged)
  assert_true(updated.contains("当前任务关联产品 · product-c"))
  assert_true(updated.contains("Captured product A (product-a)"))
  assert_eq(retagged.dispatch_run, model.dispatch_run)
}

///|
test "captured coverage and input availability render independently without action gates" {
  for coverage in ["complete", "partial", "unavailable", "untagged"] {
    for
      artifact_state in [
        "pending", "available", "missing", "conflict", "unavailable",
      ] {
      let context = dispatch_context_test_json(coverage~, artifact_state~)
      let snapshot = dispatch_decode_snapshot(
        dispatch_context_test_response(context~),
        "task-1",
      ).unwrap()
      let model = apply_dispatch_snapshot(initial_model(), snapshot)
      let html = dispatch_context_test_render(model)
      assert_true(
        html.contains(
          "捕获时完整性 · " + dispatch_context_coverage_label(coverage),
        ),
      )
      assert_true(
        html.contains(
          "输入文件状态 · " +
          dispatch_context_artifact_label(artifact_state),
        ),
      )
      assert_eq(model.dispatch_task_stage, "in_progress")
      assert_true(dispatch_can_submit(model))
      assert_false(dispatch_can_start(model))
      assert_false(html.contains("<button"))
    }
  }
}

///|
test "context input path is literal and distinct from output with Review-only staging disclosure" {
  let snapshot = dispatch_decode_snapshot(
    dispatch_context_test_response(context=dispatch_context_test_json()),
    "task-1",
  ).unwrap()
  let html = dispatch_context_test_render(
    apply_dispatch_snapshot(initial_model(), snapshot),
  )
  assert_true(html.contains("产品上下文输入（相对执行工作区）"))
  assert_true(html.contains(".moonproj/input/run-1/product-context.json"))
  assert_true(html.contains("执行工作区 · /workspace/captured"))
  assert_false(
    html.contains("href=\".moonproj/input/run-1/product-context.json\""),
  )
  assert_true(html.contains("Review-only"))
  assert_true(
    html.contains("不代表页面还原、Agent 已阅读或任务已验收"),
  )
  assert_false(html.contains("PRIVATE_PRD_TEXT_MUST_NOT_RENDER"))
  assert_true(html.contains("captured-source-hash"))
  assert_true(html.contains("captured-text-hash"))
  assert_true(html.contains("Tables retain text only"))
}

///|
test "input diagnostics escape markup and never become links or execution failures" {
  let context = dispatch_context_test_replace(
    dispatch_context_test_json(artifact_state="conflict"),
    "artifact_error",
    "<script>conflict</script>".to_json(),
  )
  let snapshot = dispatch_decode_snapshot(
    dispatch_context_test_response(context~),
    "task-1",
  ).unwrap()
  let html = dispatch_context_test_render(
    apply_dispatch_snapshot(initial_model(), snapshot),
  )
  assert_true(html.contains("文件内容冲突"))
  assert_true(html.contains("&lt;script&gt;conflict&lt;/script&gt;"))
  assert_false(html.contains("<script>conflict</script>"))
  assert_eq(snapshot.run.unwrap().error, "")
  assert_eq(snapshot.run.unwrap().state, "completed")
}

///|
test "refresh updates artifact availability without rewriting captured metadata or native result" {
  let before = dispatch_decode_snapshot(
    dispatch_context_test_response(
      context=dispatch_context_test_json(artifact_state="available"),
    ),
    "task-1",
  ).unwrap()
  let after = dispatch_decode_snapshot(
    dispatch_context_test_response(
      context=dispatch_context_test_json(artifact_state="missing"),
    ),
    "task-1",
  ).unwrap()
  let model = apply_dispatch_snapshot(initial_model(), before)
  let (_, refreshed) = update(
    _ => none,
    DispatchTaskLoaded("task-1", model.dispatch_task_selection, after),
    model,
  )
  let run = refreshed.dispatch_run.unwrap()
  guard run.product_context is Captured(context) else {
    fail("missing context after refresh")
  }
  assert_eq(context.artifact_state, "missing")
  assert_eq(context.product_id, "product-a")
  assert_eq(context.coverage, "complete")
  assert_eq(context.sha256, "captured-context-hash")
  assert_eq(run.command_id, "command-1")
  assert_eq(run.summary, "Exact native answer")
  assert_eq(refreshed.dispatch_task_stage, "in_progress")
  assert_eq(refreshed.dispatch_task_report_id, "")
}
