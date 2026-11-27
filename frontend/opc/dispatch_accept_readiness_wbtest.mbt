///|
fn acceptance_readiness_model() -> Model {
  let model = continuation_proj_confirm(
    continuation_proj_model(),
    continuation_proj_source(),
  )
  {
    ..model,
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "report-C0",
    dispatch_continuation: {
      ..model.dispatch_continuation,
      report_records: [
        {
          "reportGuid": "report-C0",
          "summary": "Original report",
          "delivery_source": Json::null(),
        },
      ],
      report_source: Json::null(),
    },
  }
}

///|
#warnings("-alert_unstable")
fn acceptance_readiness_html(model : Model, goal~ : Bool) -> String {
  let cell = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => {
    if goal {
      dispatch_goal_flow(msg => emit(msg), model)
    } else {
      dispatch_task_action(msg => emit(msg), model)
    }
  })
  opc_render_cell(cell)
}

///|
test "newer selected continuation without a report never offers goal Accept" {
  let model = acceptance_readiness_model()
  assert_false(dispatch_can_accept_report(model))
  let goal = acceptance_readiness_html(model, goal=true)
  assert_false(goal.contains(">接受结果<"))
  assert_true(goal.contains("href=\"#dispatch-task-workspace\""))
  assert_true(goal.contains("当前报告与已选执行来源不同"))
  let report = acceptance_readiness_html(model, goal=false)
  assert_false(report.contains("Accept · 接受报告"))
  assert_true(report.contains("当前报告与已选执行来源不同"))
}

///|
test "rejected and repeated Accept clicks show guidance without accepting old report" {
  let model = acceptance_readiness_model()
  let (command, rejected) = update(_ => none, AcceptDispatchTask, model)
  drafts_test_execute(command)
  assert_true(rejected.notice.contains("本次未接受"))
  assert_true(
    rejected.notice.contains("当前报告与已选执行来源不同"),
  )
  assert_eq(rejected.dispatch_task_stage, "submitted")
  assert_eq(rejected.dispatch_task_pending_action, "")
  assert_eq(rejected.dispatch_task_report_id, "report-C0")
  assert_eq(rejected.dispatch_continuation.selected, continuation_proj_source())
  let (_, repeated) = update(_ => none, AcceptDispatchTask, rejected)
  assert_eq(repeated.notice, rejected.notice)
  assert_eq(repeated.dispatch_task_pending_action, "")
  assert_eq(repeated.dispatch_task_report_id, "report-C0")
  assert_eq(repeated.dispatch_continuation.selected, continuation_proj_source())
}

///|
fn acceptance_readiness_report(
  command~ : String = "C1",
  id~ : String = "K1",
) -> Json {
  {
    "reportGuid": "report-" + command,
    "summary": "Exact report " + command,
    "delivery_source": continuation_proj_source(command~, id~),
    "evidence_ids": ["evidence-" + command],
  }
}

///|
fn acceptance_readiness_ready() -> Model {
  let model = acceptance_readiness_model()
  let (_, chosen) = dispatch_continuation_update(
    _ => none,
    SelectReport("report-C1"),
    {
      ..model,
      dispatch_continuation: {
        ..model.dispatch_continuation,
        report_records: model.dispatch_continuation.report_records +
        [acceptance_readiness_report()],
      },
    },
  )
  chosen
}

///|
test "ready exact report enables both actions and repeated Accept waits for receipt" {
  let model = acceptance_readiness_ready()
  assert_true(dispatch_can_accept_report(model))
  assert_true(
    acceptance_readiness_html(model, goal=true).contains(">接受结果<"),
  )
  assert_true(
    acceptance_readiness_html(model, goal=false).contains(
      "Accept · 接受报告 report-C1",
    ),
  )
  let body = dispatch_accept_report_body(model, "accept-op")
  assert_eq(dispatch_json_text(body, "report_id"), "report-C1")
  assert_eq(
    dispatch_json_field(body, "delivery_source"),
    continuation_proj_source(),
  )
  let (_, waiting) = update(_ => none, AcceptDispatchTask, model)
  assert_eq(waiting.dispatch_task_pending_action, "accept")
  assert_eq(waiting.dispatch_task_stage, "submitted")
  let (command, repeated) = update(_ => none, AcceptDispatchTask, waiting)
  drafts_test_execute(command)
  assert_eq(repeated.dispatch_task_pending_action, "accept")
  assert_eq(repeated.dispatch_task_report_id, "report-C1")
  assert_true(repeated.notice.contains("等待持久化收据"))
  assert_false(
    acceptance_readiness_html(repeated, goal=true).contains(">接受结果<"),
  )
  let (_, stale) = update(
    _ => none,
    DispatchTaskAccepted("task-1", 2, "old-event", "old-audit"),
    repeated,
  )
  assert_eq(stale.dispatch_task_stage, "submitted")
  assert_eq(stale.dispatch_task_pending_action, "accept")
  let (_, accepted) = update(
    _ => none,
    DispatchTaskAccepted("task-1", 3, "event", "audit"),
    stale,
  )
  assert_eq(accepted.dispatch_task_stage, "accepted")
  assert_eq(accepted.dispatch_task_event_id, "event")
  assert_false(dispatch_can_accept_report(accepted))
}

///|
test "selection change makes old rendered Accept harmless until matching report is chosen" {
  let ready = acceptance_readiness_ready()
  let changed = continuation_proj_confirm(
    ready,
    continuation_proj_source(command="C2", id="K2"),
  )
  let (command, rejected) = update(_ => none, AcceptDispatchTask, changed)
  drafts_test_execute(command)
  assert_eq(rejected.dispatch_task_report_id, "report-C1")
  assert_eq(rejected.dispatch_task_pending_action, "")
  assert_true(
    rejected.notice.contains("当前报告与已选执行来源不同"),
  )
  assert_false(
    acceptance_readiness_html(rejected, goal=true).contains(">接受结果<"),
  )
  let (_, wrong_report) = dispatch_continuation_update(
    _ => none,
    SelectReport("report-C0"),
    rejected,
  )
  assert_false(dispatch_can_accept_report(wrong_report))
  let (_, matching) = dispatch_continuation_update(
    _ => none,
    SelectReport("report-C2"),
    {
      ..wrong_report,
      dispatch_continuation: {
        ..wrong_report.dispatch_continuation,
        report_records: wrong_report.dispatch_continuation.report_records +
        [acceptance_readiness_report(command="C2", id="K2")],
      },
    },
  )
  assert_true(dispatch_can_accept_report(matching))
  let goal = acceptance_readiness_html(matching, goal=true)
  assert_true(goal.contains(">接受结果<"))
  assert_false(goal.contains("当前报告与已选执行来源不同"))
  assert_eq(
    dispatch_json_field(
      dispatch_accept_report_body(matching, "exact-C2"),
      "delivery_source",
    ),
    continuation_proj_source(command="C2", id="K2"),
  )
}

///|
test "report submission readback and reload recompute exact acceptance readiness" {
  let model = acceptance_readiness_model()
  let old = model.dispatch_continuation.report_records[0]
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    revision: 4.0,
    report_id: "report-C0",
    report_records: [old],
    continuation_records: model.dispatch_continuation.records,
    delivery_source: continuation_proj_source(),
  }
  let reloaded = apply_dispatch_snapshot(
    { ..continuation_proj_model(), dispatch_task_report_id: "", },
    snapshot,
  )
  assert_false(dispatch_can_accept_report(reloaded))
  assert_true(
    acceptance_readiness_html(reloaded, goal=true).contains(
      "当前报告与已选执行来源不同",
    ),
  )
  let captured = dispatch_new_report_body(reloaded)
  let id = dispatch_json_text(captured, "report_id")
  let pending = {
    ..reloaded,
    dispatch_task_pending_action: "submit",
    dispatch_continuation: {
      ..reloaded.dispatch_continuation,
      report_operation: captured,
      report_operation_pending: true,
    },
  }
  let (_, acknowledged) = update(
    _ => none,
    DispatchTaskSubmitted("task-1", 3, id, "report-event", "report-audit"),
    pending,
  )
  assert_eq(acknowledged.dispatch_task_pending_action, "load")
  assert_false(dispatch_can_accept_report(acknowledged))
  let final_snapshot = {
    ..snapshot,
    revision: 5.0,
    report_id: id,
    report_records: acknowledged.dispatch_continuation.report_records,
  }
  let readback = apply_dispatch_snapshot(acknowledged, final_snapshot)
  assert_eq(readback.dispatch_task_report_id, id)
  assert_true(dispatch_can_accept_report(readback))
  let (_, stale) = update(
    _ => none,
    DispatchTaskLoaded("task-1", 3, snapshot),
    readback,
  )
  assert_eq(stale.dispatch_task_report_id, id)
  assert_true(dispatch_can_accept_report(stale))
  let after_reload = apply_dispatch_snapshot(
    continuation_proj_model(),
    final_snapshot,
  )
  assert_eq(after_reload.dispatch_task_report_id, id)
  assert_true(dispatch_can_accept_report(after_reload))
  let accepted = apply_dispatch_snapshot(after_reload, {
    ..final_snapshot,
    revision: 6.0,
    state: "done",
    accepted_report_id: id,
    accepted_delivery_source: continuation_proj_source(),
  })
  let (command, repeated) = update(_ => none, AcceptDispatchTask, accepted)
  drafts_test_execute(command)
  assert_eq(repeated.dispatch_task_stage, "accepted")
  assert_eq(repeated.dispatch_task_pending_action, "")
  assert_eq(repeated.dispatch_continuation.accepted_report_id, id)
  assert_true(repeated.notice.contains("任务已接受，无需重复接受"))
}

///|
test "readiness guidance preserves all existing acceptance requirements and legacy fallback" {
  let baseline = acceptance_readiness_ready()
  for stage in ["submitted", "in_progress", "accepted", ""] {
    for mask in 0..<256 {
      let same_task = mask % 2 == 1
      let same_selection = mask / 2 % 2 == 1
      let same_actor = mask / 4 % 2 == 1
      let verified = mask / 8 % 2 == 1
      let selecting = mask / 16 % 2 == 1
      let matching_report = mask / 32 % 2 == 1
      let pending = mask / 64 % 2 == 1
      let has_report = mask / 128 % 2 == 1
      let model = {
        ..baseline,
        dispatch_task_stage: stage,
        dispatch_task_pending_action: if pending {
          "accept"
        } else {
          ""
        },
        dispatch_task_report_id: if has_report {
          "report-C1"
        } else {
          ""
        },
        dispatch_continuation: {
          ..baseline.dispatch_continuation,
          task_id: if same_task {
            "task-1"
          } else {
            "other-task"
          },
          selection: if same_selection {
            3
          } else {
            2
          },
          actor: if same_actor {
            "actor-a"
          } else {
            "actor-b"
          },
          source_verified: verified,
          operation_pending: selecting,
          report_source: if matching_report {
            continuation_proj_source()
          } else {
            Json::null()
          },
        },
      }
      let expected = stage == "submitted" &&
        !pending &&
        has_report &&
        (
          !(same_task && same_selection) ||
          (same_actor && verified && !selecting && matching_report)
        )
      assert_eq(
        dispatch_can_accept_report(model),
        expected,
        msg="stage=\{stage}, mask=\{mask}",
      )
      assert_eq(dispatch_accept_report_blocker(model).is_empty(), expected)
    }
  }
  let legacy = {
    ..continuation_proj_model(),
    dispatch_task_stage: "submitted",
    dispatch_task_report_id: "legacy-report",
  }
  assert_true(dispatch_can_accept_report(legacy))
  assert_true(
    acceptance_readiness_html(legacy, goal=true).contains(">接受结果<"),
  )
  assert_true(
    dispatch_json_field(
      dispatch_accept_report_body(legacy, "legacy"),
      "report_id",
    )
    is Null,
  )
}

///|
test "each existing blocker provides actionable same-source guidance in both submitted views" {
  let baseline = acceptance_readiness_ready()
  for
    (model, explanation) in [
      (
        { ..baseline, dispatch_task_report_id: "", },
        "尚未选择已提交报告",
      ),
      (
        {
          ..baseline,
          dispatch_continuation: {
            ..baseline.dispatch_continuation,
            actor: "other-actor",
          },
        },
        "当前登录身份已变化",
      ),
      (
        {
          ..baseline,
          dispatch_continuation: {
            ..baseline.dispatch_continuation,
            source_verified: false,
          },
        },
        "交付来源尚未核实",
      ),
      (
        {
          ..baseline,
          dispatch_continuation: {
            ..baseline.dispatch_continuation,
            operation_pending: true,
          },
        },
        "交付来源选择尚未确认",
      ),
    ] {
    assert_false(dispatch_can_accept_report(model))
    for goal in [true, false] {
      let html = acceptance_readiness_html(model, goal~)
      assert_true(html.contains(explanation), msg=explanation)
      assert_false(html.contains(">接受结果<"))
      assert_false(html.contains("Accept · 接受报告"))
    }
    let (command, rejected) = update(_ => none, AcceptDispatchTask, model)
    drafts_test_execute(command)
    assert_true(rejected.notice.contains(explanation))
    assert_eq(rejected.dispatch_task_pending_action, "")
  }
}
