///|
struct DispatchLessonHandoff {
  task_id : String
  selection : Int32
  request : Int32
  pending : Bool
  payload : Json?
  origin : String
  notice : String
  receipt : Json?
  receipt_direct : Bool
  receipt_waiting : Bool
  receipt_target : Json?
  receipt_notice : String
}

///|
fn empty_dispatch_lesson_handoff() -> DispatchLessonHandoff {
  {
    task_id: "",
    selection: -1,
    request: 0,
    pending: false,
    payload: None,
    origin: "",
    notice: "",
    receipt: None,
    receipt_direct: false,
    receipt_waiting: false,
    receipt_target: None,
    receipt_notice: "",
  }
}

///|
enum DispatchLessonHandoffMsg {
  Prepare
  Loaded(String, Int32, Int32, Result[String, String])
  Export
  Origin(String)
  OpenBook
  Readback(String, Int32, Int32, String)
  ReopenLesson
  ImportReceipt
  ReceiptImported(String, Int32, Int32, String)
  ReceiptReturned(String, Int32, Int32, String, String, (Bool) -> Unit)
  ReceiptEnded(String, Int32, Int32, String)
}

///|
fn dispatch_lesson_payload(
  response : String,
  task : String,
  report : String,
) -> Result[Json, String] {
  let value = @json.parse(response) catch {
    _ => return Err("无法读取经验交接文件。")
  }
  guard value
    is {
      "contract_version": "moonproj.book-lesson-handoff.v1",
      "source_product": "moonproj",
      "task": {
        "record_id": String(actual),
        "record_version": String(version),
        "record_digest": String(digest),
        ..
      },
      "report": { "record_id": String(actual_report), .. },
      "task_snapshot": String(_),
      "report_snapshot": String(_),
      "authorizing": false,
      "customer_acceptance": "not_asserted",
      "cash": "not_asserted",
      ..
    } &&
    actual == task &&
    actual_report == report &&
    !version.is_empty() &&
    !digest.is_empty() else {
    return Err(
      "交接返回了其他任务或报告；请刷新当前任务后重试。",
    )
  }
  Ok(value)
}

///|
fn dispatch_lesson_current(model : Model) -> Bool {
  let state = model.dispatch_lesson_handoff
  let report_current = match state.payload {
    Some(payload) =>
      dispatch_json_text(dispatch_json_field(payload, "report"), "record_id") ==
      model.dispatch_task_report_id
    None => true
  }
  dispatch_work_page(model) &&
  state.task_id == model.dispatch_task_id &&
  state.selection == model.dispatch_task_selection &&
  model.dispatch_task_stage == "accepted" &&
  report_current
}

///|
fn dispatch_lesson_readback(payload : Json, response : String) -> String {
  let value = @json.parse(response) catch {
    _ => return "Book 尚未确认接收。可以重试或下载交接文件。"
  }
  if value is Object(fields) && fields.is_empty() {
    return "Book 未能建立直接连接。可以重试或下载交接文件。"
  }
  guard value
    is {
      "contract_version": "moonbook.task-lesson-readback.v1",
      "handoff": actual,
      "state": String(state),
      "activation_authorized": false,
      "external_side_effects_applied": false,
      ..
    } &&
    actual == payload &&
    [
      "reviewed_source_available", "choose_reviewed_source", "reviewed_source_missing",
    ].contains(state) else {
    return "Book 未读回相同的任务与报告绑定；尚未确认交接。"
  }
  if state == "reviewed_source_available" {
    "Book 已读回准确任务与报告，并找到了已审核的评估。请在 Book 中明确采用后编写经验。"
  } else if state == "choose_reviewed_source" {
    "Book 已读回准确绑定；请在 Book 中选择对应的已审核评估。"
  } else {
    "Book 已读回准确绑定，但尚无匹配的已审核结果评估。内部任务接受不会代替结果审核。"
  }
}

///|
fn dispatch_lesson_handoff_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchLessonHandoffMsg,
) -> (Cmd, Model) {
  let state = model.dispatch_lesson_handoff
  match action {
    Origin(value) =>
      if state.pending {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            dispatch_lesson_handoff: {
              ..state,
              origin: value,
              request: state.request + 1,
              receipt_waiting: false,
              receipt_direct: false,
              notice: "",
            },
          },
        )
      }
    Prepare => {
      if !dispatch_work_page(model) ||
        model.dispatch_task_stage != "accepted" ||
        !model.dispatch_task_pending_action.is_empty() ||
        (dispatch_lesson_current(model) && state.pending) {
        return (none, model)
      }
      let next = {
        ..state,
        task_id: model.dispatch_task_id,
        selection: model.dispatch_task_selection,
        request: state.request + 1,
        pending: true,
        payload: None,
        receipt: None,
        receipt_direct: false,
        receipt_waiting: false,
        receipt_target: None,
        receipt_notice: "",
        notice: "正在读取准确任务、接受报告和审计记录…",
      }
      let cmd = @http.get(
        "/api/company/tasks/" +
        dispatch_url_encode(next.task_id) +
        "/lesson-handoff",
      ).expect_text(result => {
        emit(
          LessonHandoffAction(
            Loaded(
              next.task_id,
              next.selection,
              next.request,
              match result {
                Ok(text) => Ok(text)
                Err(error) => Err(error.to_string())
              },
            ),
          ),
        )
      })
      (
        cmd,
        {
          ..dispatch_outcome_refreshing_source(model),
          dispatch_lesson_handoff: next,
        },
      )
    }
    Loaded(task, selection, request, result) => {
      if !dispatch_lesson_current(model) ||
        !state.pending ||
        state.task_id != task ||
        state.selection != selection ||
        state.request != request {
        return (none, model)
      }
      let result = match result {
        Ok(text) =>
          dispatch_lesson_payload(text, task, model.dispatch_task_report_id)
        Err(error) => Err(error)
      }
      (
        none,
        {
          ..model,
          dispatch_lesson_handoff: {
            ..state,
            pending: false,
            payload: match result {
              Ok(value) => Some(value)
              Err(_) => None
            },
            notice: match result {
              Ok(_) =>
                "准确任务与报告已准备。填写你要使用的 Book 地址并打开，或下载文件后在 Book 的经验工作区导入。"
              Err(error) => "无法准备交接：" + error
            },
          },
        },
      )
    }
    Export => {
      guard dispatch_lesson_current(model) &&
        !state.pending &&
        state.payload is Some(payload) else {
        return (none, model)
      }
      (
        @cmd.custom_cmd(_ => {
          dispatch_lesson_download(payload.stringify(indent=2))
        }),
        model,
      )
    }
    OpenBook | ReopenLesson => {
      guard dispatch_lesson_current(model) &&
        !state.pending &&
        state.payload is Some(payload) else {
        return (none, model)
      }
      let request = state.request + 1
      let reopening = action is ReopenLesson
      if reopening && state.receipt is None {
        return (none, model)
      }
      let origin = if reopening {
        dispatch_json_text(state.receipt.unwrap(), "book_origin")
      } else {
        state.origin
      }
      let selected = if reopening {
        Some(
          dispatch_json_field(
            dispatch_json_field(state.receipt.unwrap(), "receipt"),
            "lesson",
          ),
        )
      } else {
        None
      }
      (
        @cmd.custom_cmd(_ => {
          dispatch_lesson_connect_book_on(
            lesson_handoff_browser(),
            origin,
            payload.stringify(),
            selected.unwrap_or(Json::null()).stringify(),
            true,
            result => {
              ignore(
                emit(
                  LessonHandoffAction(
                    Readback(state.task_id, state.selection, request, result),
                  ),
                ),
              )
            },
            (result, acknowledge) => {
              ignore(
                emit(
                  LessonHandoffAction(
                    ReceiptReturned(
                      state.task_id,
                      state.selection,
                      request,
                      dispatch_lesson_origin(origin),
                      result,
                      acknowledge,
                    ),
                  ),
                ),
              )
            },
            reason => {
              ignore(
                emit(
                  LessonHandoffAction(
                    ReceiptEnded(
                      state.task_id,
                      state.selection,
                      request,
                      reason,
                    ),
                  ),
                ),
              )
            },
          )
        }),
        {
          ..model,
          dispatch_lesson_handoff: {
            ..state,
            request,
            pending: true,
            receipt_waiting: true,
            receipt_direct: false,
            receipt_target: selected,
            receipt_notice: "请在 Book 中明确选择保存的经验并返回状态。直接连接有时限；也可重新连接或导入收据文件。",
            notice: "在打开的 Book 中点击 Receive task from Proj。接收后会在这里确认准确绑定；不会保存或接受经验。",
          },
        },
      )
    }
    Readback(task, selection, request, response) => {
      if !dispatch_lesson_current(model) ||
        !state.pending ||
        state.task_id != task ||
        state.selection != selection ||
        state.request != request {
        return (none, model)
      }
      let notice = match state.payload {
        Some(payload) => dispatch_lesson_readback(payload, response)
        None => "请重新准备交接。"
      }
      (
        none,
        {
          ..model,
          dispatch_lesson_handoff: { ..state, pending: false, notice, },
        },
      )
    }
    ImportReceipt
    | ReceiptImported(_, _, _, _)
    | ReceiptReturned(_, _, _, _, _, _)
    | ReceiptEnded(_, _, _, _) =>
      dispatch_lesson_receipt_update(emit, model, action)
  }
}

///|
fn dispatch_lesson_handoff_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.dispatch_lesson_handoff
  let current = dispatch_lesson_current(model)
  div(class="journey-section") <| [
    primary_button(
      emit,
      LessonHandoffAction(Prepare),
      if current && state.pending {
        "正在准备 / 等待 Book…"
      } else {
        "Prepare lesson · 准备经验交接"
      },
    ),
    p(
      "从当前已接受报告带入准确身份。Book 将查找已有结果和具名审核评估；不会根据内部接受生成客户结果。",
    ),
    if current && state.payload is Some(payload) {
      div <| [
        dispatch_outcome_composer_view(emit, model, payload),
        p(
          "任务 · " +
          dispatch_json_text(dispatch_json_field(payload, "task"), "record_id") +
          " / 报告 · " +
          dispatch_json_text(
            dispatch_json_field(payload, "report"),
            "record_id",
          ),
        ),
        dispatch_task_input(
          "lesson-book-origin",
          "Book 地址（明确填写，默认空）",
          state.origin,
          "例如你自己的 Book HTTP(S) 地址",
          emit.map(value => LessonHandoffAction(Origin(value))),
          read_only=state.pending,
        ),
        secondary_button(
          emit,
          LessonHandoffAction(OpenBook),
          if state.receipt_waiting {
            "重新连接此 Book（新的返回连接）"
          } else {
            "在此 Book 打开经验交接"
          },
        ),
        secondary_button(
          emit,
          LessonHandoffAction(Export),
          "下载经验交接文件",
        ),
        secondary_button(
          emit,
          LessonHandoffAction(ImportReceipt),
          "Import Book lesson receipt · 导入经验收据",
        ),
        dispatch_lesson_receipt_view(emit, state),
        small(
          "文件包含任务来源、报告和收据，请只导入你明确选择的 Book。地址未配置时使用文件导入；内容不会放入网址。",
        ),
      ]
    } else {
      @html.nothing
    },
    if !model.dispatch_outcome_drafts.is_empty() &&
      (!current || state.payload is None) {
      small(
        "此标签页的结果草稿仍保留。重新准备相同的准确来源后可继续；来源变化不会自动迁移笔记。",
      )
    } else {
      @html.nothing
    },
    dispatch_outcome_retained_view(model),
    if current {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        state.notice,
      )
    } else {
      @html.nothing
    },
  ]
}

///|
extern "js" fn dispatch_lesson_download(text : String) =
  #| text => { const blob = new Blob([text], {type:'application/json'}); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href=url; a.download='moonproj-lesson-handoff.json'; a.click(); setTimeout(()=>URL.revokeObjectURL(url), 1000); }

///|
#external
type LessonHandoffBrowser

///|
extern "js" fn lesson_handoff_browser() -> LessonHandoffBrowser =
  #| () => globalThis

///|
fn dispatch_lesson_open_book_on(
  browser : LessonHandoffBrowser,
  origin : String,
  payload : String,
  done : (String) -> Unit,
) -> Unit {
  dispatch_lesson_connect_book_on(
    browser,
    origin,
    payload,
    "null",
    false,
    done,
    (_, _) => (),
    _ => (),
  )
}
