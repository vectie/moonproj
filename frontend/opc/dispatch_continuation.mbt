///|
struct DispatchContinuationState {
  task_id : String
  selection : Int32
  request : Int32
  phase : String
  preview_command : String
  preview_revision : String
  candidate : Json
  records : Array[Json]
  human_revision_candidate : Json
  human_revision_content : String
  human_revisions : Array[Json]
  selected : Json
  error : String
  accepted : Bool
  source_verified : Bool
  operation : Json
  operation_pending : Bool
  actor : String
  report_records : Array[Json]
  report_source : Json
  revision : Double
  accepted_report_id : String
  accepted_delivery_source : Json
  report_operation : Json
  report_operation_pending : Bool
}

///|
enum DispatchContinuationMsg {
  Refresh
  Preview(String)
  PreviewHumanRevision(String)
  Loaded(String, Int32, Int32, String, String, Result[String, String])
  Select
  SelectHumanRevision
  SelectOriginal
  SelectReport(String)
  Attached(String, Int32, Int32, String, Result[String, String])
  SelectionStored(String, Int32, Int32, String, Bool)
}

///|
fn empty_dispatch_continuation() -> DispatchContinuationState {
  {
    task_id: "",
    selection: -1,
    request: 0,
    phase: "idle",
    preview_command: "",
    preview_revision: "",
    candidate: Json::null(),
    records: [],
    human_revision_candidate: Json::null(),
    human_revision_content: "",
    human_revisions: [],
    selected: Json::null(),
    error: "",
    accepted: false,
    source_verified: false,
    operation: Json::null(),
    operation_pending: false,
    actor: "",
    report_records: [],
    report_source: Json::null(),
    revision: 0.0,
    accepted_report_id: "",
    accepted_delivery_source: Json::null(),
    report_operation: Json::null(),
    report_operation_pending: false,
  }
}

///|
fn dispatch_continuation_valid(model : Model, record : Json) -> Bool {
  guard model.dispatch_run is Some(run) else { return false }
  dispatch_json_text(record, "task_id") == model.dispatch_task_id &&
  dispatch_json_text(record, "original_run_id") == run.run_id &&
  dispatch_json_text(record, "session_id") == run.session_id &&
  dispatch_json_text(record, "original_command_id") == run.command_id &&
  dispatch_json_text(record, "workspace") == run.workspace &&
  dispatch_json_text(record, "continuation_id") != "" &&
  dispatch_json_text(record, "command_id") != "" &&
  dispatch_json_text(record, "command_id") != run.command_id
}

///|
fn dispatch_continuation_array(json : Json, key : String) -> Array[Json] {
  match dispatch_json_field(json, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn dispatch_continuation_decode(
  model : Model,
  state : DispatchContinuationState,
  response : String,
) -> Result[DispatchContinuationState, String] {
  let json = @json.parse(response) catch { _ => Json::null() }
  guard model.dispatch_run is Some(run) else {
    return Err("原始执行不可用，请刷新任务。")
  }
  if dispatch_json_text(json, "schema") != "moonproj.task-continuations.v1" ||
    dispatch_json_text(json, "task_id") != model.dispatch_task_id ||
    dispatch_json_text(json, "original_run_id") != run.run_id ||
    dispatch_json_text(json, "session_id") != run.session_id ||
    dispatch_json_text(json, "original_command_id") != run.command_id ||
    dispatch_json_text(json, "workspace") != run.workspace {
    return Err("后续执行记录与此任务的原始执行不匹配。")
  }
  let revision = dispatch_continuation_revision(json)
  let older = state.source_verified && revision < state.revision
  let records = if older {
    state.records.copy()
  } else {
    dispatch_continuation_array(json, "continuations").filter(record => {
      dispatch_continuation_valid(model, record)
    })
  }
  for record in dispatch_continuation_array(json, "candidates") {
    if dispatch_continuation_valid(model, record) &&
      !records.any(existing => {
        dispatch_json_text(existing, "command_id") ==
        dispatch_json_text(record, "command_id")
      }) {
      records.push(record)
    }
  }
  let candidate = dispatch_json_field(json, "candidate")
  let candidate = if state.preview_command != "" &&
    dispatch_continuation_valid(model, candidate) &&
    dispatch_json_text(candidate, "command_id") == state.preview_command {
    candidate
  } else {
    Json::null()
  }
  if !(candidate is Null) &&
    !records.any(record => {
      dispatch_json_text(record, "command_id") == state.preview_command
    }) {
    records.push(candidate)
  }
  let human_revisions = if older {
    state.human_revisions.copy()
  } else {
    dispatch_continuation_array(json, "human_revisions").filter(record => {
      dispatch_human_revision_valid(model, record)
    })
  }
  let human_revision_candidate = dispatch_json_field(
    json, "human_revision_candidate",
  )
  let human_revision_candidate = if state.preview_revision != "" &&
    dispatch_human_revision_valid(model, human_revision_candidate) &&
    dispatch_human_revision_content_valid(
      human_revision_candidate,
      dispatch_json_field(json, "human_revision_content"),
    ) &&
    dispatch_json_text(human_revision_candidate, "revision_id") ==
    state.preview_revision {
    human_revision_candidate
  } else {
    Json::null()
  }
  let selected = if older {
    state.selected
  } else {
    dispatch_json_field(json, "selected_delivery_source")
  }
  let selected_valid = dispatch_delivery_source_valid(
    model, selected, records, human_revisions,
  )
  if !selected_valid {
    return Err("已选交付来源无法验证；报告提交已暂停。")
  }
  Ok({
    ..state,
    phase: "ready",
    records,
    candidate,
    human_revisions,
    human_revision_candidate,
    human_revision_content: if human_revision_candidate is Null {
      ""
    } else {
      dispatch_json_text(json, "human_revision_content")
    },
    selected,
    source_verified: true,
    revision: if older {
      state.revision
    } else {
      revision
    },
    operation_pending: state.operation_pending &&
    !dispatch_selection_matches(state.operation, selected),
    accepted: state.accepted ||
    dispatch_json_field(json, "acceptance") is True ||
    dispatch_json_text(json, "acceptance") == "accepted" ||
    dispatch_json_field(json, "task_accepted") is True ||
    dispatch_task_inspection_only(model),
    error: if state.operation_pending &&
      !dispatch_selection_matches(state.operation, selected) &&
      state.error != "" {
      state.error
    } else if state.preview_revision != "" && human_revision_candidate is Null {
      let detail = dispatch_json_text(json, "error")
      if detail != "" {
        detail
      } else {
        "此准确人工修订尚不可用；刷新可重试，不会替换为其他修订。"
      }
    } else if state.preview_command != "" && candidate is Null {
      let detail = dispatch_json_text(json, "error")
      if detail != "" {
        detail
      } else {
        "此准确命令尚不可用；刷新可重试，不会替换为最新命令。"
      }
    } else {
      ""
    },
  })
}

///|
fn dispatch_continuation_selected(model : Model) -> Json? {
  let state = model.dispatch_continuation
  if state.actor != model.dispatch_task_actor_id {
    return None
  }
  if state.task_id != model.dispatch_task_id ||
    state.selection != model.dispatch_task_selection ||
    !state.source_verified ||
    dispatch_json_text(state.selected, "type") != "continuation" {
    return None
  }
  state.records
  .filter(record => {
    dispatch_continuation_valid(model, record) &&
    dispatch_json_text(record, "command_id") ==
    dispatch_json_text(state.selected, "command_id") &&
    dispatch_json_text(record, "continuation_id") ==
    dispatch_json_text(state.selected, "continuation_id")
  })
  .get(0)
}

///|
fn dispatch_continuation_reportable(model : Model) -> Bool {
  let state = model.dispatch_continuation
  if state.actor != model.dispatch_task_actor_id {
    return false
  }
  if !state.source_verified ||
    state.operation_pending ||
    state.selection != model.dispatch_task_selection ||
    state.accepted ||
    dispatch_task_inspection_only(model) {
    return false
  }
  if dispatch_json_text(state.selected, "type") == "human_revision" {
    dispatch_human_revision_selected(model) is Some(_)
  } else if dispatch_json_text(state.selected, "type") == "continuation" {
    match dispatch_continuation_selected(model) {
      Some(record) => dispatch_json_text(record, "state") == "completed"
      None => false
    }
  } else {
    match model.dispatch_run {
      Some(run) => run.state == "completed"
      None => false
    }
  }
}

///|
fn dispatch_report_with_source(body : Json, model : Model) -> Json {
  if body is Object(fields) &&
    !(model.dispatch_continuation.selected is Null) &&
    model.dispatch_continuation.task_id == model.dispatch_task_id &&
    model.dispatch_continuation.selection == model.dispatch_task_selection {
    fields["delivery_source"] = model.dispatch_continuation.selected
  } else if body is Object(fields) && model.dispatch_run is Some(_) {
    fields["delivery_source"] = dispatch_effective_source(model, Json::null())
  }
  body
}

///|
fn dispatch_continuation_update(
  emit : @rabbita.Emit[Msg],
  action : DispatchContinuationMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.dispatch_continuation
  match action {
    SelectReport(id) => {
      let report = state.report_records
        .filter(report => dispatch_json_text(report, "reportGuid") == id)
        .get(0)
      match report {
        Some(report) if state.actor == model.dispatch_task_actor_id &&
          state.task_id == model.dispatch_task_id &&
          state.selection == model.dispatch_task_selection &&
          model.dispatch_task_pending_action == "" =>
          (
            none,
            {
              ..model,
              dispatch_task_report_id: id,
              dispatch_task_report_summary: dispatch_json_text(
                report, "summary",
              ),
              dispatch_report_product_id: dispatch_json_text(
                report, "product_id",
              ),
              dispatch_continuation: {
                ..state,
                report_source: dispatch_json_field(report, "delivery_source"),
              },
            },
          )
        _ => (none, model)
      }
    }
    Refresh | Preview(_) | PreviewHumanRevision(_) => {
      if !dispatch_work_page(model) ||
        model.dispatch_run is None ||
        model.dispatch_task_id == "" ||
        state.phase == "attaching" {
        return (none, model)
      }
      let page = dispatch_handoff_current_page()
      let revision = match action {
        PreviewHumanRevision(id) => id
        Preview(_) => ""
        _ =>
          if state.task_id == model.dispatch_task_id &&
            state.selection == model.dispatch_task_selection &&
            state.preview_revision != "" {
            state.preview_revision
          } else {
            dispatch_human_revision_return_hint(page, model.dispatch_task_id)
          }
      }
      let command = if revision != "" {
        ""
      } else {
        match action {
          Preview(command) => command
          PreviewHumanRevision(_) => ""
          _ =>
            if state.task_id == model.dispatch_task_id &&
              state.selection == model.dispatch_task_selection &&
              state.preview_command != "" {
              state.preview_command
            } else {
              dispatch_continuation_return_hint(
                page,
                model.dispatch_task_id,
                model.dispatch_run.unwrap().run_id,
              )
            }
        }
      }
      let saved = dispatch_selection_restore(model)
      let restore = state.operation is Null && !(saved is Null)
      let next = {
        ..state,
        actor: model.dispatch_task_actor_id,
        task_id: model.dispatch_task_id,
        selection: model.dispatch_task_selection,
        request: state.request + 1,
        phase: "loading",
        preview_command: command,
        preview_revision: revision,
        candidate: Json::null(),
        human_revision_candidate: Json::null(),
        human_revision_content: "",
        error: if state.operation_pending {
          state.error
        } else {
          ""
        },
        operation: if restore {
          dispatch_json_field(saved, "body")
        } else {
          state.operation
        },
        operation_pending: if restore {
          dispatch_json_field(saved, "pending") is True
        } else {
          state.operation_pending
        },
      }
      (
        dispatch_load_continuations(emit, next, page),
        { ..model, dispatch_continuation: next, },
      )
    }
    Loaded(task, selection, request, page, command, result) => {
      if !dispatch_work_page(model) ||
        state.actor != model.dispatch_task_actor_id ||
        !dispatch_response_matches(model, task, selection) ||
        state.request != request ||
        state.phase != "loading" ||
        state.preview_command != command ||
        !dispatch_continuation_page_matches(page) {
        return (none, model)
      }
      let decoded = match result {
        Ok(response) => dispatch_continuation_decode(model, state, response)
        Err(error) => Err(error)
      }
      match decoded {
        Ok(next) =>
          (
            if state.operation_pending && !next.operation_pending {
              @cmd.custom_cmd(_ => {
                ignore(
                  dispatch_selection_store(
                    dispatch_selection_key(model),
                    next.operation.stringify(),
                    false,
                  ),
                )
              })
            } else {
              none
            },
            { ..model, dispatch_continuation: next, },
          )
        Err(error) =>
          (
            none,
            {
              ..model,
              dispatch_continuation: { ..state, phase: "unavailable", error, },
            },
          )
      }
    }
    Select | SelectOriginal | SelectHumanRevision => {
      if state.actor != model.dispatch_task_actor_id ||
        !dispatch_work_page(model) ||
        state.phase != "ready" ||
        dispatch_task_inspection_only(model) ||
        state.accepted ||
        state.task_id != model.dispatch_task_id ||
        state.selection != model.dispatch_task_selection {
        return (none, model)
      }
      let original = action is SelectOriginal
      let human_revision = action is SelectHumanRevision
      if original {
        if !(model.dispatch_run is Some(run) && run.state == "completed") {
          return (none, model)
        }
      } else if human_revision {
        if !dispatch_human_revision_valid(model, state.human_revision_candidate) ||
          !dispatch_human_revision_content_valid(
            state.human_revision_candidate,
            Json::string(state.human_revision_content),
          ) ||
          state.preview_revision == "" ||
          dispatch_json_text(state.human_revision_candidate, "revision_id") !=
          state.preview_revision {
          return (none, model)
        }
      } else if !dispatch_continuation_valid(model, state.candidate) ||
        dispatch_json_text(state.candidate, "state") != "completed" {
        return (none, model)
      }
      let request = state.request + 1
      let desired = dispatch_continuation_attach_body(
        model,
        original,
        "",
        human_revision~,
      )
      if state.operation_pending &&
        !dispatch_selection_same_target(state.operation, desired) {
        return (
          none,
          {
            ..model,
            dispatch_continuation: {
              ..state,
              error: "先恢复尚未确认的准确来源选择，再选择另一个结果。",
            },
          },
        )
      }
      let body = if state.operation_pending {
        state.operation
      } else {
        dispatch_continuation_attach_body(
          model,
          original,
          "opc-select-" + dispatch_command_nonce(),
          human_revision~,
        )
      }
      let page = dispatch_handoff_current_page()
      (
        @cmd.custom_cmd(scheduler => {
          scheduler.add(
            emit(
              ContinuationAction(
                SelectionStored(
                  model.dispatch_task_id,
                  model.dispatch_task_selection,
                  request,
                  page,
                  dispatch_selection_store(
                    dispatch_selection_key(model),
                    body.stringify(),
                    true,
                  ),
                ),
              ),
            ),
          )
        }),
        {
          ..model,
          dispatch_continuation: {
            ..state,
            operation: body,
            operation_pending: true,
            phase: "saving",
            request,
            error: "",
          },
        },
      )
    }
    SelectionStored(task, selection, request, page, stored) => {
      if !dispatch_work_page(model) ||
        state.actor != model.dispatch_task_actor_id ||
        !dispatch_response_matches(model, task, selection) ||
        state.request != request ||
        state.phase != "saving" ||
        !dispatch_continuation_page_matches(page) {
        return (none, model)
      }
      if !stored {
        (
          none,
          {
            ..model,
            dispatch_continuation: {
              ..state,
              phase: "ready",
              error: "无法持久保存选择操作，尚未发送。请启用浏览器本地存储后重试。",
            },
          },
        )
      } else {
        (
          dispatch_attach_continuation(emit, model, request, state.operation),
          { ..model, dispatch_continuation: { ..state, phase: "attaching", }, },
        )
      }
    }
    Attached(task, selection, request, page, result) => {
      if !dispatch_work_page(model) ||
        state.actor != model.dispatch_task_actor_id ||
        !dispatch_response_matches(model, task, selection) ||
        state.request != request ||
        state.phase != "attaching" ||
        !dispatch_continuation_page_matches(page) {
        return (none, model)
      }
      let acknowledged = match result {
        Ok(response) => dispatch_selection_ack_state(model, response)
        Err(_) => None
      }
      match acknowledged {
        Some(next) =>
          (
            @cmd.batch([
              @cmd.custom_cmd(_ => {
                ignore(
                  dispatch_selection_store(
                    dispatch_selection_key(model),
                    next.operation.stringify(),
                    false,
                  ),
                )
              }),
              emit(ContinuationAction(Refresh)),
            ]),
            {
              ..model,
              dispatch_continuation: { ..next, phase: "recovering", },
            },
          )
        None => {
          let error = match result {
            Ok(response) => {
              let json = @json.parse(response) catch { _ => Json::null() }
              let detail = dispatch_json_text(json, "error")
              let detail = if detail != "" {
                detail
              } else {
                dispatch_json_text(json, "message")
              }
              "选择尚未确认：" +
              (if detail != "" { detail } else { "响应无法验证" }) +
              "。正在读取服务端选择；重试使用同一操作身份。"
            }
            Err(error) =>
              "结果选择响应未确认：" +
              error +
              "。正在读取服务端选择；重试使用同一操作身份。"
          }
          (
            emit(ContinuationAction(Refresh)),
            {
              ..model,
              dispatch_continuation: { ..state, phase: "recovering", error, },
            },
          )
        }
      }
    }
  }
}
