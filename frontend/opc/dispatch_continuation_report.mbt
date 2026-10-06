///|
fn dispatch_effective_source(model : Model, source : Json) -> Json {
  if !(source is Null) {
    return source
  }
  match model.dispatch_run {
    Some(run) =>
      {
        "type": "original",
        "original_run_id": run.run_id,
        "command_id": run.command_id,
      }
    None => Json::null()
  }
}

///|
fn dispatch_report_matches_selection(model : Model) -> Bool {
  if !(model.dispatch_continuation.selected is Null) &&
    model.dispatch_continuation.report_source is Null {
    return false
  }
  dispatch_effective_source(model, model.dispatch_continuation.selected) ==
  dispatch_effective_source(model, model.dispatch_continuation.report_source)
}

///|
fn dispatch_accept_report_blocker(model : Model) -> String {
  if model.dispatch_task_pending_action != "" {
    return "已有任务操作等待持久化收据。请等待完成；结果未确认时刷新正式任务。"
  }
  if dispatch_task_inspection_only(model) {
    return "任务已接受，无需重复接受。"
  }
  if model.dispatch_task_stage != "submitted" {
    return "请先在任务工作区提交报告，再检查并接受结果。"
  }
  if model.dispatch_task_report_id == "" {
    return "尚未选择已提交报告。请提交当前来源的报告，或选择与当前来源一致的已保存报告。"
  }
  let state = model.dispatch_continuation
  if state.task_id == model.dispatch_task_id &&
    state.selection == model.dispatch_task_selection {
    if state.actor != model.dispatch_task_actor_id {
      return "当前登录身份已变化。请刷新正式任务，再检查报告和交付来源。"
    }
    if !state.source_verified {
      return "交付来源尚未核实。请刷新正式任务，确认当前来源和报告。"
    }
    if state.operation_pending {
      return "交付来源选择尚未确认。请先刷新后续执行记录，恢复该选择操作。"
    }
    if !dispatch_report_matches_selection(model) {
      return "当前报告与已选执行来源不同。请为已选来源提交报告，或明确切回原来源后选择对应报告。"
    }
  }
  ""
}

///|
fn dispatch_can_accept_report(model : Model) -> Bool {
  dispatch_accept_report_blocker(model).is_empty()
}

///|
fn dispatch_report_operation_key(model : Model) -> String {
  dispatch_selection_key(model) + ":report"
}

///|
fn dispatch_report_requires_capture(model : Model) -> Bool {
  model.dispatch_continuation.task_id == model.dispatch_task_id &&
  model.dispatch_continuation.selection == model.dispatch_task_selection &&
  !(model.dispatch_continuation.selected is Null)
}

///|
fn dispatch_record_acknowledged_report(
  model : Model,
  report_id : String,
) -> DispatchContinuationState {
  let state = model.dispatch_continuation
  let captured = state.report_operation
  let reports = state.report_records.copy()
  if dispatch_json_text(captured, "report_id") == report_id &&
    !reports.any(report => dispatch_json_text(report, "reportGuid") == report_id) {
    reports.push({
      "reportGuid": report_id,
      "summary": dispatch_json_field(captured, "summary"),
      "evidence_ids": dispatch_json_field(captured, "evidence_ids"),
      "delivery_source": dispatch_json_field(captured, "delivery_source"),
    })
  }
  { ..state, report_records: reports, report_operation_pending: false, }
}

///|
fn dispatch_begin_report(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> (Cmd, Model) {
  match dispatch_report_operation_body(model, dispatch_new_report_body(model)) {
    Err(error) => (none, { ..model, dispatch_task_note: error, })
    Ok(body) => {
      let next = {
        ..model,
        dispatch_continuation: {
          ..model.dispatch_continuation,
          report_operation: body,
          report_operation_pending: true,
        },
        dispatch_task_pending_action: "submit",
        dispatch_task_blocked: false,
        dispatch_task_note: "正在提交准确来源的不可变报告；本页重试保留同一操作。重载后请先刷新任务确认已保存报告。",
      }
      (request_dispatch_task_submit(emit, next), next)
    }
  }
}

///|
fn dispatch_report_in_memory_body(model : Model) -> Json {
  let state = model.dispatch_continuation
  if state.report_operation_pending && !(state.report_operation is Null) {
    state.report_operation
  } else {
    dispatch_new_report_body(model)
  }
}

///|
fn dispatch_accept_report_body(model : Model, idempotency_key : String) -> Json {
  let fields : Map[String, Json] = {
    "idempotency_key": Json::string(idempotency_key),
    "status": Json::string("done"),
    "progress_pct": Json::number(100),
    "authority": dispatch_task_authority(model, "project:task:update"),
  }
  if !(model.dispatch_continuation.selected is Null) ||
    !(model.dispatch_continuation.report_source is Null) {
    fields["report_id"] = Json::string(model.dispatch_task_report_id)
    fields["delivery_source"] = dispatch_effective_source(
      model,
      model.dispatch_continuation.report_source,
    )
  }
  Json::object(fields)
}

///|
fn dispatch_report_operation_body(
  model : Model,
  fresh : Json,
) -> Result[Json, String] {
  let saved : Json = if model.dispatch_continuation.report_operation_pending {
    { "body": model.dispatch_continuation.report_operation, "pending": true }
  } else {
    @json.parse(dispatch_selection_read(dispatch_report_operation_key(model))) catch {
      _ => Json::null()
    }
  }
  let body = dispatch_json_field(saved, "body")
  let recorded = model.dispatch_continuation.report_records.any(report => {
    dispatch_json_text(report, "reportGuid") ==
    dispatch_json_text(body, "report_id") &&
    dispatch_effective_source(
      model,
      dispatch_json_field(report, "delivery_source"),
    ) ==
    dispatch_effective_source(
      model,
      dispatch_json_field(body, "delivery_source"),
    )
  })
  if dispatch_json_field(saved, "pending") is True &&
    !recorded &&
    dispatch_json_text(body, "task_id") == model.dispatch_task_id &&
    dispatch_json_text(body, "idempotency_key") != "" {
    if dispatch_effective_source(
        model,
        dispatch_json_field(body, "delivery_source"),
      ) !=
      dispatch_effective_source(model, model.dispatch_continuation.selected) {
      return Err(
        "另一准确来源的报告提交尚未确认。请先刷新任务恢复其报告，再切换来源提交。",
      )
    }
    let fields : Map[String, Json] = Map([])
    for
      key in [
        "idempotency_key", "report_id", "task_id", "project_id", "progress_pct",
        "report_date", "summary", "evidence_ids", "delivery_source",
      ] {
      let value = dispatch_json_field(body, key)
      if !(value is Null) {
        fields[key] = value
      }
    }
    Ok(Json::object(fields))
  } else {
    Ok(fresh)
  }
}

///|
fn dispatch_report_selection_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.dispatch_continuation
  div <| [
    strong("已保存报告 · 选择准确报告后接受"),
    dispatch_accepted_human_export_view(emit, model),
    if state.accepted_report_id != "" {
      strong(
        "正式接受的报告 · " +
        state.accepted_report_id +
        " / 来源 · " +
        dispatch_delivery_source_label(state.accepted_delivery_source),
      )
    } else {
      @html.nothing
    },
    div <| state.report_records.map(report => {
      div <| [
        p(
          dispatch_json_text(report, "reportGuid") +
          " · 来源 " +
          dispatch_delivery_source_label(
            dispatch_effective_source(
              model,
              dispatch_json_field(report, "delivery_source"),
            ),
          ),
        ),
        p(dispatch_json_text(report, "summary")),
        secondary_button(
          emit,
          ContinuationAction(
            SelectReport(dispatch_json_text(report, "reportGuid")),
          ),
          if state.accepted || dispatch_task_inspection_only(model) {
            "查看此报告"
          } else if model.dispatch_task_report_id ==
            dispatch_json_text(report, "reportGuid") {
            "已选此报告"
          } else {
            "选择此报告进行接受"
          },
        ),
      ]
    }),
    if model.dispatch_task_report_id != "" {
      small(
        "当前报告 · " +
        model.dispatch_task_report_id +
        " / 来源 · " +
        dispatch_delivery_source_label(
          dispatch_effective_source(model, state.report_source),
        ),
      )
    } else {
      @html.nothing
    },
    if !dispatch_report_matches_selection(model) {
      small(
        "当前报告与已选执行来源不同。该报告不会被当作新来源的报告接受。",
      )
    } else {
      @html.nothing
    },
  ]
}
