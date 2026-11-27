///|
// Presentation checks: all mutation and transport semantics remain in existing reducers.
extern "js" fn guided_index(html : String, text : String) -> Int32 =
  #| (html, text) => html.indexOf(text)

///|
extern "js" fn guided_count(html : String, text : String) -> Int32 =
  #| (html, text) => html.split(text).length - 1

///|
extern "js" fn guided_disclosure_open(html : String, text : String) -> Bool =
  #| (html, text) => {
  #|   const index = html.indexOf(text);
  #|   const start = html.lastIndexOf('<details', index);
  #|   if (index < 0 || start < 0) return false;
  #|   return /\sopen(?:[=\s>])/.test(html.slice(start, html.indexOf('>', start) + 1));
  #| }

///|
extern "js" fn guided_disclosure_visible(html : String, text : String) -> Bool =
  #| (html, text) => {
  #|   const index = html.indexOf(text);
  #|   if (index < 0) return false;
  #|   const stack = [];
  #|   for (const match of html.slice(0, index).matchAll(/<\/?details\b[^>]*>/g)) {
  #|     if (match[0].startsWith('</')) stack.pop();
  #|     else stack.push(/\sopen(?:[=\s>])/.test(match[0]));
  #|   }
  #|   return stack.every(Boolean);
  #| }

///|
extern "js" fn guided_preview_enabled() -> Bool =
  #| () => globalThis.process?.env?.MOONPROJ_UI_PREVIEW === '1'

///|
#warnings("-alert_unstable")
fn guided_page(model : Model) -> String {
  opc_render_cell(@rabbita.static_cell(view(_ => none, model)))
}

///|
#warnings("-alert_unstable")
fn guided_task(model : Model) -> String {
  opc_render_cell(@rabbita.static_cell(dispatch_view(_ => none, model)))
}

///|
fn guided_work_model() -> Model {
  let model = output_proj_model()
  {
    ..model,
    products: products_test_loaded().products,
    dispatch_task_title: "为产品准备一份清晰的上手说明",
    dispatch_task_acceptance: "新用户可以按说明完成第一件工作，并能找到输出。",
    dispatch_task_product_id: "moonbook",
    dispatch_task_workspace: "/workspace/book",
    dispatch_task_note: "执行已完成，请检查输出。",
    dispatch_run: Some({
      ..model.dispatch_run.unwrap(),
      summary: "上手说明已完成。请检查 results/report 书.md 中的步骤。",
    }),
    dispatch_continuation: {
      ..model.dispatch_continuation,
      candidate: Json::null(),
      records: [],
    },
  }
}

///|
test "guided navigation keeps primary destinations and expands active secondary route" {
  let home = guided_page({ ..initial_model(), page: Overview, })
  assert_false(guided_disclosure_open(home, "更多工具"))
  assert_true(guided_disclosure_visible(home, "今日："))
  assert_true(guided_disclosure_visible(home, "目标："))
  assert_true(guided_disclosure_visible(home, "公司域："))
  assert_false(
    guided_disclosure_visible(home, "交付演练（会话内）："),
  )
  let secondary = guided_page({ ..initial_model(), page: Quality, })
  assert_true(guided_disclosure_open(secondary, "更多工具"))
  assert_true(guided_disclosure_visible(secondary, "出厂质检："))
}

///|
test "guided product preparation precedes inspectable reference detail" {
  let model = products_test_project(products_test_selected("moonbook"))
  let html = guided_page(model)
  assert_true(
    guided_index(html, "下一步 · 准备一个目标") <
    guided_index(html, "产品意图与定义来源"),
  )
  assert_true(guided_disclosure_visible(html, ">准备任务<"))
  assert_false(guided_disclosure_open(html, "产品意图与定义来源"))
  assert_false(guided_disclosure_open(html, "源码与登记"))
  assert_true(html.contains("产品任务历史"))
  assert_true(html.contains("下载 PRD 快照"))
}

///|
test "guided product read errors and new project recovery remain visible" {
  let selected = products_test_selected("moonbook")
  let html = guided_page({
    ..selected,
    products: {
      ..selected.products,
      project_state: "empty",
      project_note: "项目读取没有结果",
      admission_state: "offline",
    },
  })
  assert_true(guided_disclosure_visible(html, "项目读取没有结果"))
  assert_true(
    guided_disclosure_open(html, "需要新项目？创建公司项目"),
  )
  assert_true(guided_disclosure_open(html, "已观察的能力与证据"))
  assert_false(html.contains(">准备任务<"))
}

///|
test "guided draft foregrounds goal acceptance workspace and keeps optional settings inspectable" {
  let html = guided_task(drafts_test_valid())
  assert_true(
    guided_index(html, "dispatch-task-acceptance") <
    guided_index(html, "可选设置"),
  )
  assert_true(
    guided_disclosure_visible(html, "执行工作区（执行前填写）"),
  )
  assert_false(
    guided_disclosure_open(html, "可选设置 · 模型与负责人"),
  )
  assert_false(guided_disclosure_visible(html, "负责人 ID（可选）"))
  assert_eq(guided_count(html, "id=\"dispatch-task-workspace\""), 1)
  assert_true(html.contains("id=\"dispatch-task-workspace-input\""))
}

///|
test "guided generic draft exposes missing project and identity requirements" {
  let (_, draft) = update(_ => none, OpenDispatchTaskForm, {
    ..initial_model(),
    page: Dispatch,
  })
  let html = guided_task(draft)
  assert_true(guided_disclosure_open(html, "公司项目与登录身份"))
  assert_true(guided_disclosure_visible(html, "尚未登录"))
  assert_true(guided_disclosure_visible(html, "真实公司项目 ID"))
}

///|
test "guided recovery is not buried when storage or a draft is uncertain" {
  let source = drafts_test_valid()
  let draft = dispatch_active_draft(source).unwrap()
  let model = dispatch_replace_draft(source, {
    ..draft,
    state: "uncertain",
    recovery_required: true,
    note: "创建结果尚未确认",
  })
  let html = guided_task({
    ..model,
    dispatch_task_form_open: false,
    dispatch_draft_storage: "草稿未保存到此浏览器；保留当前页面并检查存储权限",
  })
  assert_true(
    guided_disclosure_open(
      html, "其他任务 · 草稿、恢复与手动打开",
    ),
  )
  assert_true(
    guided_disclosure_visible(html, "保留当前页面并检查存储权限"),
  )
  assert_true(guided_disclosure_visible(html, "恢复草稿"))
}

///|
test "guided task is full width and output precedes human revision and submission" {
  let html = guided_task(guided_work_model())
  assert_true(html.contains("focused-workspace"))
  assert_false(html.contains("class=\"work-board\""))
  assert_false(html.contains("没有任务"))
  assert_true(
    guided_index(html, "results/report 书.md") <
    guided_index(html, "需要调整？加入人工指令"),
  )
  assert_true(
    guided_index(html, "需要调整？加入人工指令") <
    guided_index(html, "Submit · 提交验收"),
  )
  assert_eq(guided_count(html, "Submit · 提交验收"), 1)
  assert_true(guided_disclosure_visible(html, "在 MoonDesk 编辑"))
  assert_false(guided_disclosure_visible(html, "会话 · session-1"))
}

///|
test "guided rail links to one real Start and Accept action without changing readiness" {
  let pending = {
    ..guided_work_model(),
    dispatch_task_stage: "pending",
    dispatch_run: None,
  }
  let start = guided_task(pending)
  assert_eq(guided_count(start, "Start · MoonClaw 执行"), 1)
  assert_true(start.contains("href=\"#dispatch-task-workspace\""))
  let ready = acceptance_readiness_ready()
  let accept = guided_task(ready)
  assert_eq(guided_count(accept, "Accept · 接受报告 report-C1"), 1)
  assert_true(dispatch_can_accept_report(ready))
  let blocked = acceptance_readiness_model()
  let mismatch = guided_task(blocked)
  assert_false(mismatch.contains("Accept · 接受报告"))
  assert_true(
    guided_disclosure_visible(
      mismatch, "当前报告与已选执行来源不同",
    ),
  )
  assert_true(
    guided_disclosure_open(mismatch, "已保存报告与接受记录"),
  )
}

///|
test "guided execution uncertainty failure and interrupted recovery remain visible" {
  for
    state in [
      "running", "waiting_approval", "failed", "cancelled", "interrupted", "runtime_unavailable",
      "unknown",
    ] {
    let base = guided_work_model()
    let model = {
      ..base,
      dispatch_run: Some({
        ..base.dispatch_run.unwrap(),
        state,
        error: "需要检查的执行说明",
      }),
    }
    let html = guided_task(model)
    assert_true(guided_disclosure_visible(html, "需要检查的执行说明"))
    assert_false(html.contains("Submit · 提交验收"))
    if ["interrupted", "runtime_unavailable", "unknown"].contains(state) {
      assert_true(html.contains(dispatch_resume_label(model)))
    }
  }
}

///|
test "guided input capture warning stays outside collapsed provenance" {
  let snapshot = dispatch_decode_snapshot(
    dispatch_context_test_response(
      context=dispatch_context_test_json(
        coverage="partial",
        artifact_state="missing",
      ),
    ),
    "task-1",
  ).unwrap()
  let model = {
    ..apply_dispatch_snapshot(initial_model(), snapshot),
    page: Dispatch,
  }
  let html = guided_task(model)
  assert_true(guided_disclosure_visible(html, "输入上下文说明"))
  assert_true(guided_disclosure_visible(html, "文件缺失"))
  assert_true(guided_disclosure_visible(html, "Declared extraction scope"))
  assert_false(guided_disclosure_visible(html, "captured-context-hash"))
}

///|
test "guided continuation pending and unverified sources stay prominent" {
  let base = guided_work_model()
  let model = {
    ..base,
    dispatch_continuation: {
      ..base.dispatch_continuation,
      operation_pending: true,
      source_verified: false,
      error: "来源读取失败",
    },
  }
  let html = guided_task(model)
  assert_true(guided_disclosure_visible(html, "来源读取失败"))
  assert_true(guided_disclosure_visible(html, "结果选择尚未确认"))
  assert_true(guided_disclosure_visible(html, "交付来源尚未核实"))
  assert_true(
    guided_disclosure_open(html, "其他执行结果 · 查看并明确选择"),
  )
}

///|
test "guided accepted task offers honest optional learning and no new continuation" {
  let html = guided_task({
    ..guided_work_model(),
    dispatch_task_stage: "accepted",
  })
  assert_true(
    guided_disclosure_visible(html, "下一步 · 保存有用的经验"),
  )
  assert_true(html.contains("Review this Book’s learning"))
  assert_true(html.contains("Teach this book"))
  assert_true(html.contains("编辑 Teach this book 已打开的草稿"))
  assert_true(
    html.contains("关闭 Learning Review，再点击 Exit inspection"),
  )
  assert_false(html.contains("Review，在 Document tools 中选择 Learning"))
  assert_true(html.contains("Publish → Experienced Book package"))
  assert_true(html.contains("保持同一个 Book"))
  assert_true(html.contains("若出现 Save to book 或 Retry book save"))
  assert_true(html.contains("MoonProj 尚未读取学习保存收据"))
  assert_true(html.contains("不会自动在 Town 中复用"))
  assert_false(html.contains("新的人工指令"))
  assert_false(html.contains("Submit ·"))
  assert_false(html.contains("Accept · 接受报告"))
}

///|
test "accepted task without native run explicitly selects the same Book before ordinary learning controls" {
  let html = guided_task({
    ..guided_work_model(),
    dispatch_task_stage: "accepted",
    dispatch_run: None,
  })
  assert_true(html.contains("此任务未记录原生执行"))
  assert_true(html.contains("明确选中同一个 Book"))
  assert_true(html.contains("Review，在 Document tools 中选择 Learning"))
  assert_false(html.contains("Review this Book’s learning"))
  assert_false(html.contains("打开本次工作所在的 MoonDesk"))
  assert_true(html.contains("不会自动打包或传输到 Town"))
  assert_true(html.contains("关闭 Document tools"))
  assert_false(html.contains("再点击 Exit inspection"))
}

///|
test "guided guide begins with actionable everyday journey" {
  let html = guided_page({ ..initial_model(), page: Guide, })
  assert_true(
    guided_index(html, "按顺序完成一件工作") <
    guided_index(html, "发布与工程证据参考"),
  )
  assert_true(guided_disclosure_visible(html, "从产品开始"))
  assert_false(guided_disclosure_open(html, "发布与工程证据参考"))
}

///|
test "guided synthetic previews use exact view components without runtime effects" {
  let completed = guided_work_model()
  let ready = {
    ..acceptance_readiness_ready(),
    dispatch_task_title: completed.dispatch_task_title,
    dispatch_task_acceptance: completed.dispatch_task_acceptance,
    dispatch_task_product_id: "moonbook",
  }
  for
    (name, model) in [
      ("products", products_test_project(products_test_selected("moonbook"))),
      ("draft", drafts_test_valid()),
      ("completed", completed),
      (
        "mismatch",
        {
          ..acceptance_readiness_model(),
          dispatch_task_title: completed.dispatch_task_title,
          dispatch_task_acceptance: completed.dispatch_task_acceptance,
        },
      ),
      ("ready", ready),
      ("accepted", { ..completed, dispatch_task_stage: "accepted", }),
      ("guide", { ..initial_model(), page: Guide, }),
    ] {
    let html = guided_page(model)
    assert_true(html.contains("opc-app"))
    if guided_preview_enabled() {
      println(
        "MOONPROJ_UI_PREVIEW " +
        Json::object({
          "name": ToJson::to_json(name),
          "html": ToJson::to_json(html),
        }).stringify(),
      )
    }
  }
}

///|
test "guided required dates remain visible and agree with actual draft validation" {
  let model = drafts_test_update(
    drafts_test_update(drafts_test_valid(), Input("begin_date", "")),
    Input("end_date", ""),
  )
  let draft = dispatch_active_draft(model).unwrap()
  assert_eq(
    dispatch_draft_validation(draft, model.dispatch_task_actor_id),
    "计划开始和完成日期不能为空。",
  )
  let html = guided_task(model)
  assert_true(guided_disclosure_visible(html, "计划开始（必填）"))
  assert_true(guided_disclosure_visible(html, "计划完成（必填）"))
  assert_true(
    guided_index(html, "dispatch-task-end") < guided_index(html, "可选设置"),
  )
  let guide = guided_page({ ..initial_model(), page: Guide, })
  assert_true(guide.contains("必填的计划日期"))
  assert_false(guide.contains("日期可以稍后"))
}

///|
test "guided corrupt restored storage with no drafts exposes error and exact task recovery" {
  let source = {
    ..initial_model(),
    page: Dispatch,
    dispatch_task_actor_id: "actor-recovery",
  }
  let model = drafts_test_update(
    source,
    Restored("actor-recovery", "not valid JSON"),
  )
  assert_true(model.dispatch_drafts.is_empty())
  assert_eq(
    model.dispatch_draft_storage,
    "草稿记录无法读取；当前页面仍可使用正式任务链接",
  )
  let html = guided_task(model)
  assert_true(
    guided_disclosure_open(
      html, "其他任务 · 草稿、恢复与手动打开",
    ),
  )
  assert_true(guided_disclosure_visible(html, "草稿记录无法读取"))
  assert_true(guided_disclosure_visible(html, "恢复 / 打开正式任务"))
  let clean = drafts_test_update(source, Restored("actor-recovery", ""))
  assert_false(
    guided_disclosure_open(
      guided_task(clean),
      "其他任务 · 草稿、恢复与手动打开",
    ),
  )
}

///|
test "guided project setup failure without a request remains visible" {
  let selected = products_test_project(products_test_selected("moonbook"))
  let model = {
    ..selected,
    company_setup: {
      ..selected.company_setup,
      project: {
        ..selected.company_setup.project,
        request: None,
        phase: "failed",
        note: "本地存储失败，没有提交创建；输入仍可修改。",
      },
      storage: "本地恢复不可用；请修复存储后再创建。",
    },
  }
  let html = guided_page(model)
  assert_true(
    guided_disclosure_open(html, "需要新项目？创建公司项目"),
  )
  assert_true(
    guided_disclosure_visible(html, "本地存储失败，没有提交创建"),
  )
  assert_true(guided_disclosure_visible(html, "本地恢复不可用"))
  let unavailable = {
    ..selected,
    company_setup: { ..selected.company_setup, units_state: "unauthorized", },
  }
  assert_true(
    guided_disclosure_open(
      guided_page(unavailable),
      "需要新项目？创建公司项目",
    ),
  )
}
