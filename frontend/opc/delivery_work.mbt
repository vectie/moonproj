///|
struct DeliveryState {
  instruction : String
  editing : Bool
  pending : Json
  busy : Bool
}

///|
fn delivery_initial() -> DeliveryState {
  { instruction: "", editing: false, pending: Json::null(), busy: false, }
}

///|
enum DeliveryMsg {
  Input(String)
  CancelEdit
  Stop
  Revise
  Resume
  Retry
  Read(String, Int32, Result[String, String])
}

///|
fn delivery_coordinated(model : Model) -> Bool {
  dispatch_json_text(model.dispatch_offer_task, "delivery_mode") ==
  "coordinated"
}

///|
fn delivery_control(model : Model) -> String {
  dispatch_json_text(
    dispatch_json_field(model.dispatch_offer_task, "execution"),
    "control_state",
  )
}

///|
fn delivery_pollable(model : Model) -> Bool {
  if delivery_control(model) == "stopped" {
    return false
  }
  dispatch_run_pollable(model.dispatch_run) ||
  ["stopping", "revising", "resuming"].contains(delivery_control(model))
}

///|
fn delivery_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DeliveryMsg,
) -> (Cmd, Model) {
  match action {
    Input(instruction) =>
      (none, { ..model, delivery: { ..model.delivery, instruction, }, })
    CancelEdit =>
      (none, { ..model, delivery: { ..model.delivery, editing: false, }, })
    Read(task, selection, response) => {
      if !dispatch_response_matches(model, task, selection) {
        return (none, model)
      }
      match response {
        Ok(body) =>
          match dispatch_decode_snapshot(body, task) {
            Some(snapshot) => {
              let (read, loaded) = update_model(
                emit,
                DispatchTaskLoaded(task, selection, snapshot),
                { ..model, delivery: delivery_initial(), },
              )
              (read, loaded)
            }
            None =>
              (
                none,
                {
                  ..model,
                  delivery: { ..model.delivery, busy: false, },
                  dispatch_task_pending_action: "",
                  notice: "交付操作尚未确认。刷新或重试同一请求。" +
                  dispatch_response_error(body),
                },
              )
          }
        Err(_) =>
          (
            none,
            {
              ..model,
              delivery: { ..model.delivery, busy: false, },
              dispatch_task_pending_action: "",
              notice: "交付操作结果尚未确认。可以刷新或重试同一请求；不会另建运行。",
            },
          )
      }
    }
    Stop | Revise | Resume | Retry => {
      if !dispatch_work_page(model) ||
        model.dispatch_task_actor_id.is_empty() ||
        model.dispatch_run is None ||
        model.delivery.busy ||
        !["", "load"].contains(model.dispatch_task_pending_action) {
        return (none, model)
      }
      let (operation, instruction) = match action {
        Stop => ("stop", "")
        Revise =>
          ("revise-delivery", model.delivery.instruction.trim().to_owned())
        Resume => ("resume-delivery", "")
        _ =>
          (
            dispatch_json_text(model.delivery.pending, "operation"),
            dispatch_json_text(model.delivery.pending, "instruction"),
          )
      }
      if operation.is_empty() ||
        (operation == "revise-delivery" && instruction.is_empty()) {
        return (none, { ..model, notice: "请写明需要怎样修改。", })
      }
      let pending = if action is Retry {
        model.delivery.pending
      } else {
        {
          "operation": operation,
          "instruction": instruction,
          "idempotency_key": "delivery-" + dispatch_command_nonce(),
          "authority": dispatch_task_authority(model, "project:task:update"),
        }
      }
      let task = model.dispatch_task_id
      let selection = model.dispatch_task_selection
      (
        @http.post(
          "/api/company/plan/tasks/" +
          dispatch_url_encode(task) +
          "/" +
          operation,
        )
        .with_json(pending)
        .expect_text(r => {
          emit(
            DeliveryAction(Read(task, selection, r.map_err(_ => "unconfirmed"))),
          )
        }),
        {
          ..model,
          delivery: { ..model.delivery, pending, busy: true, },
          dispatch_task_pending_action: "delivery",
          notice: "",
        },
      )
    }
  }
}

///|
fn delivery_work_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let execution = dispatch_json_field(model.dispatch_offer_task, "execution")
  let control = delivery_control(model)
  let revision = dispatch_continuation_selected(model)
  let busy = model.delivery.busy ||
    !["", "load"].contains(model.dispatch_task_pending_action)
  article(class="work-card focused-work") <| [
    div(class="loop-head") <| [
      strong(model.dispatch_task_title),
      status_badge(
        match control {
          "stopping" => "停止待确认"
          "stopped" => "已停止"
          "revising" => "修改中"
          _ => dispatch_task_stage_label(model.dispatch_task_stage)
        },
        tone="info",
      ),
    ],
    if revision is Some(record) {
      div(class="delivery-output") <| [
        p(dispatch_json_text(record, "summary")),
        div <| dispatch_continuation_array(record, "artifact_refs").map(item => {
          div <| [
            strong(dispatch_json_text(item, "path")),
            dispatch_output_button(
              emit,
              model,
              dispatch_json_text(record, "command_id"),
              dispatch_json_text(item, "path"),
              dispatch_json_text(item, "evidence_id"),
            ),
          ]
        }),
      ]
    } else if control == "stopped" &&
      model.dispatch_run.map(r => r.state != "completed").unwrap_or(false) {
      div <| [
        p(
          model.dispatch_run
          .map(r => {
            if r.summary.is_empty() {
              "尚无完整交付产物。"
            } else {
              r.summary
            }
          })
          .unwrap_or("尚无完整交付产物。"),
        ),
        details(class="journey-details") <| [
          summary("停止前的执行记录"),
          dispatch_native_result(model, emit~),
        ],
      ]
    } else {
      dispatch_native_result(model, emit~)
    },
    if !dispatch_json_text(model.dispatch_offer_task, "delivery_report_error").is_empty() {
      p(
        class="boundary-note",
        "输出已保留，报告尚未确认。刷新可继续同步。",
      )
    } else if model.dispatch_run
      .map(r => r.state == "completed")
      .unwrap_or(false) &&
      model.dispatch_task_report_id.is_empty() {
      p("正在登记交付报告…")
    } else {
      @html.nothing
    },
    if busy {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        "正在提交交付操作…",
      )
    } else if control == "stopping" {
      div <| [
        p("尚未确认全部执行与专员会话停止。"),
        p(dispatch_json_text(execution, "control_error")),
        secondary_button(emit, DeliveryAction(Stop), "重试停止"),
      ]
    } else if control == "stopped" {
      div <| [
        p("交付已停止；已有结果保留。"),
        primary_button(emit, DeliveryAction(Resume), "继续交付"),
      ]
    } else if control == "revising" {
      div <| [
        p("正在继续同一交付，旧报告仍保留。"),
        p(dispatch_json_text(execution, "control_error")),
        secondary_button(
          emit,
          DeliveryAction(Resume),
          "恢复同一修改请求",
        ),
      ]
    } else {
      @html.nothing
    },
    if model.delivery.editing && !busy {
      div(class="inline-form") <| [
        dispatch_outcome_textarea(
          "delivery-revision",
          "需要怎样修改？",
          model.delivery.instruction,
          "保留什么、修改什么，以及如何验收",
          emit.map(v => DeliveryAction(Input(v))),
        ),
        primary_button(emit, DeliveryAction(Revise), "发送修改要求"),
        secondary_button(emit, DeliveryAction(CancelEdit), "取消修改"),
      ]
    } else {
      @html.nothing
    },
    div(class="form-actions") <| [
      if !busy && dispatch_can_start(model) {
        primary_button(
          emit,
          StartDispatchTask,
          if model.dispatch_run is None {
            "开始交付"
          } else {
            "恢复原执行"
          },
        )
      } else {
        @html.nothing
      },
      if !busy && model.dispatch_run is Some(_) && control != "stopped" {
        secondary_button(emit, DeliveryAction(Stop), "停止这项交付")
      } else {
        @html.nothing
      },
      secondary_button(
        emit,
        RefreshDispatchTask(
          model.dispatch_task_id,
          model.dispatch_task_selection,
        ),
        "刷新交付",
      ),
      if !(model.delivery.pending is Null) &&
        model.dispatch_task_pending_action.is_empty() {
        secondary_button(emit, DeliveryAction(Retry), "重试同一请求")
      } else {
        @html.nothing
      },
    ],
    details(class="journey-details", open=model.dispatch_run is None) <| [
      summary("交付条件"),
      p("验收标准 · " + model.dispatch_task_acceptance),
      p(dispatch_json_text(model.dispatch_offer_task, "delivery_limits")),
      dispatch_execution_settings(emit, model),
    ],
    if !dispatch_json_text(execution, "worker_error").is_empty() {
      p(
        class="boundary-note",
        "专员记录暂不可读；这不表示专员已完成。" +
        dispatch_json_text(execution, "worker_error"),
      )
    } else {
      @html.nothing
    },
    if !dispatch_continuation_array(execution, "workers").is_empty() {
      details(class="journey-details") <| [
        summary("实际专员与复核记录"),
        div <| dispatch_continuation_array(execution, "workers").map(w => {
          p(
            dispatch_json_text(w, "worker_id") +
            " · " +
            delivery_worker_label(dispatch_json_text(w, "status")),
          )
        }),
      ]
    } else {
      @html.nothing
    },
    small(
      "执行成本 · 尚无可核实的金额；不按完成任务数推算。",
    ),
    details(class="journey-details") <| [
      summary("执行记录与其他工具"),
      p(model.dispatch_task_id),
      dispatch_task_receipts(model),
      dispatch_continuation_view(emit, model),
      dispatch_desk_handoff_view(emit, model),
      secondary_button(emit, ExportFounderPacket, "下载交付工作包"),
    ],
  ]
}

///|
fn delivery_worker_label(state : String) -> String {
  match state {
    "done" => "已完成"
    "failed" => "失败"
    "cancelled" => "已取消"
    "waiting" => "等待中"
    "paused" | "interrupted" => "已暂停"
    "running" => "执行中"
    "pending" | "queued" => "排队中"
    _ => "状态未确认"
  }
}
