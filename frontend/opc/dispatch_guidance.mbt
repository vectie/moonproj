///|
// An optional observation lives only in this tab. It is never part of a draft,
// navigation URL, browser storage, or the older accepted-report lesson flow.
struct DispatchGuidanceContext {
  actor : String
  task : String
  project : String
  product : String
  selection : Int32
  revision : Double
  page : String
} derive(Debug, Eq)

///|
struct DispatchGuidanceState {
  context : DispatchGuidanceContext?
  request : Int32
  phase : String
  handoff : Json?
  selected : Json?
  origin : String
  notice : String
  start_body : Json?
  cancel : (() -> Unit)?
  needs_refresh : Bool
}

///|
enum DispatchGuidanceMsg {
  Prepare
  Loaded(DispatchGuidanceContext, Int32, Result[String, String])
  Origin(String)
  OpenBook
  Connected(DispatchGuidanceContext, Int32, () -> Unit)
  Returned(DispatchGuidanceContext, Int32, String, String, (Bool) -> Unit)
  Ended(DispatchGuidanceContext, Int32, String)
  Clear
}

///|
fn empty_dispatch_guidance() -> DispatchGuidanceState {
  {
    context: None,
    request: 0,
    phase: "idle",
    handoff: None,
    selected: None,
    origin: "",
    notice: "",
    start_body: None,
    cancel: None,
    needs_refresh: false,
  }
}

///|
fn dispatch_guidance_context(model : Model) -> DispatchGuidanceContext {
  {
    actor: model.dispatch_task_actor_id,
    task: model.dispatch_task_id,
    project: model.dispatch_task_project_id,
    product: model.dispatch_task_product_id,
    selection: model.dispatch_task_selection,
    revision: model.dispatch_continuation.revision,
    page: dispatch_handoff_current_page(),
  }
}

///|
fn dispatch_guidance_identity(model : Model) -> Bool {
  match model.dispatch_guidance.context {
    Some(context) =>
      context.actor == model.dispatch_task_actor_id &&
      context.task == model.dispatch_task_id &&
      context.selection == model.dispatch_task_selection
    None => false
  }
}

///|
fn dispatch_guidance_current(model : Model) -> Bool {
  dispatch_work_page(model) &&
  model.dispatch_guidance.context == Some(dispatch_guidance_context(model))
}

///|
fn dispatch_guidance_editable(model : Model) -> Bool {
  dispatch_work_page(model) &&
  !model.dispatch_task_id.is_empty() &&
  !model.dispatch_task_actor_id.is_empty() &&
  !model.dispatch_task_project_id.is_empty() &&
  model.dispatch_run is None &&
  model.dispatch_task_pending_action.is_empty() &&
  ["pending", "in_progress"].contains(model.dispatch_task_stage) &&
  model.dispatch_continuation.task_id == model.dispatch_task_id &&
  model.dispatch_continuation.actor == model.dispatch_task_actor_id &&
  model.dispatch_continuation.selection == model.dispatch_task_selection &&
  model.dispatch_guidance.start_body is None
}

///|
fn dispatch_guidance_reset(
  state : DispatchGuidanceState,
) -> DispatchGuidanceState {
  { ..empty_dispatch_guidance(), request: state.request + 1, }
}

///|
// Every application update passes here, including actor/route restoration.
// An in-flight Start retains its exact body until the server proves no reserve.
fn dispatch_guidance_reconcile(model : Model) -> Model {
  let state = model.dispatch_guidance
  if state.context is None {
    return model
  }
  if !dispatch_guidance_identity(model) {
    { ..model, dispatch_guidance: dispatch_guidance_reset(state), }
  } else if !dispatch_guidance_current(model) && state.start_body is None {
    let current = dispatch_guidance_context(model)
    let same_page = dispatch_work_page(model) &&
      state.context
      .map(context => context.page == current.page)
      .unwrap_or(false)
    let requires_decision = same_page &&
      (state.selected is Some(_) || state.needs_refresh)
    {
      ..model,
      dispatch_guidance: {
        ..dispatch_guidance_reset(state),
        context: if requires_decision {
          Some(current)
        } else {
          None
        },
        needs_refresh: requires_decision,
        notice: if requires_decision {
          "当前任务版本或范围已变化。原经验选择已移除；请明确刷新或清除经验选择后再 Start。"
        } else {
          ""
        },
      },
    }
  } else {
    model
  }
}

///|
// Teardown runs before any next command. Clearing or switching cannot leave an
// old popup able to request the captured task payload later.
fn dispatch_guidance_transition(
  previous : Model,
  next : Model,
  command : Cmd,
) -> Cmd {
  let before = previous.dispatch_guidance
  let after = next.dispatch_guidance
  guard before.cancel is Some(cancel) else { return command }
  if before.context == after.context &&
    before.request == after.request &&
    (after.phase == "waiting" || after.phase == "selected") &&
    dispatch_guidance_current(next) {
    return command
  }
  @cmd.batch([@cmd.custom_cmd(kind=Immediately, _ => cancel()), command])
}

///|
fn dispatch_guidance_after_read(model : Model) -> Model {
  let state = model.dispatch_guidance
  if model.dispatch_run is Some(_) && dispatch_guidance_identity(model) {
    {
      ..model,
      dispatch_guidance: {
        ..state,
        request: state.request + 1,
        phase: "locked",
        handoff: None,
        selected: None,
        cancel: None,
        needs_refresh: false,
        notice: "正式执行已保留。以执行记录中的经验引用摘要为准，不能替换建议。",
      },
    }
  } else if model.dispatch_run is None &&
    dispatch_guidance_identity(model) &&
    state.start_body is Some(_) {
    dispatch_guidance_reconcile({
      ..model,
      dispatch_guidance: {
        ..state,
        start_body: None,
        phase: if state.selected is Some(_) {
          "selected"
        } else {
          "idle"
        },
        notice: "正式记录确认尚未保留原生执行；可清除或重新选择经验。",
      },
    })
  } else {
    dispatch_guidance_reconcile(model)
  }
}

///|
fn dispatch_guidance_capture_start(model : Model) -> Model {
  if dispatch_guidance_identity(model) &&
    model.dispatch_guidance.start_body is Some(_) {
    return model
  }
  let body = dispatch_start_body(model)
  let state = if dispatch_guidance_current(model) {
    model.dispatch_guidance
  } else {
    dispatch_guidance_reset(model.dispatch_guidance)
  }
  {
    ..model,
    dispatch_guidance: {
      ..state,
      context: Some(dispatch_guidance_context(model)),
      request: state.request + 1,
      phase: "locked",
      cancel: None,
      start_body: Some(body),
      notice: "本次 Start 输入已固定；重试保留相同请求。刷新正式记录后确认执行状态。",
    },
  }
}

///|
fn dispatch_guidance_start_blocker(model : Model) -> String {
  let state = model.dispatch_guidance
  if dispatch_guidance_identity(model) && state.start_body is Some(_) {
    return ""
  }
  if state.needs_refresh {
    return "当前任务版本或范围已变化；请明确刷新或清除经验选择后再 Start。"
  }
  guard state.selected is Some(value) else { return "" }
  if !dispatch_guidance_current(model) || model.dispatch_run is Some(_) {
    return "所选 Book 经验不再对应当前可启动任务；请刷新或清除经验选择后再 Start。"
  }
  guard state.handoff is Some(handoff) else {
    return "所选 Book 经验缺少当前查询交接；请刷新或清除经验选择后再 Start。"
  }
  match dispatch_guidance_decode(handoff, state.origin, value.stringify()) {
    Ok(_) => ""
    Err(_) =>
      "所选 Book 经验无法验证；请刷新或清除经验选择后再 Start。"
  }
}

///|
fn dispatch_guidance_query(
  response : String,
  context : DispatchGuidanceContext,
) -> Result[Json, String] {
  if response.length() > 131072 {
    return Err("经验查询交接过大。")
  }
  let value = @json.parse(response) catch {
    _ => return Err("无法读取经验查询交接。")
  }
  let expected_snapshot : Json = {
    "task_id": context.task,
    "project_id": context.project,
    "product_id": context.product,
    "revision": context.revision,
  }
  let conditions : Array[Json] = [
    { "key": "project_id", "value": context.project },
  ]
  if !context.product.is_empty() {
    conditions.push({ "key": "suite_product_id", "value": context.product })
  }
  let target = dispatch_json_field(value, "target_task")
  let snapshot = @json.parse(dispatch_json_text(value, "task_snapshot")) catch {
    _ => return Err("查询未包含准确任务快照。")
  }
  guard value is Object(fields) &&
    fields.length() == 6 &&
    target is Object(reference) &&
    reference.length() == 3 &&
    dispatch_json_text(value, "contract_version") ==
    "moonproj.book-guidance-query.v1" &&
    dispatch_json_text(value, "source_product") == "moonproj" &&
    dispatch_json_field(value, "authorizing") is False &&
    dispatch_json_text(target, "record_id") == context.task &&
    dispatch_json_text(target, "record_version") == context.revision.to_string() &&
    dispatch_json_text(target, "record_digest").has_prefix("sha256:") &&
    dispatch_json_text(target, "record_digest").length() == 71 &&
    snapshot == expected_snapshot &&
    dispatch_json_field(value, "conditions") == conditions.to_json() else {
    return Err(
      "查询不属于当前任务、产品、项目和版本；请刷新任务后重试。",
    )
  }
  Ok(value)
}

///|
fn dispatch_guidance_decode(
  handoff : Json,
  origin : String,
  text : String,
) -> Result[Json, String] {
  if text.length() > 131072 {
    return Err("返回的经验选择过大。")
  }
  let value = @json.parse(text) catch {
    _ => return Err("无法读取返回的经验选择。")
  }
  if dispatch_lesson_origin(origin).is_empty() ||
    dispatch_json_text(value, "book_origin") != origin {
    return Err("经验选择来自其他 Book。")
  }
  @task_evidence.validate_guidance_selection(value, handoff) catch {
    @task_evidence.InvalidSourceContext(message) => return Err(message)
  }
  Ok(value)
}

///|
fn dispatch_guidance_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchGuidanceMsg,
) -> (Cmd, Model) {
  let state = model.dispatch_guidance
  match action {
    Prepare => {
      guard dispatch_guidance_editable(model) else { return (none, model) }
      let context = dispatch_guidance_context(model)
      let request = state.request + 1
      (
        @http.get(
          "/api/company/tasks/" +
          dispatch_url_encode(context.task) +
          "/guidance-query",
        ).expect_text(result => {
          emit(
            GuidanceAction(
              Loaded(
                context,
                request,
                match result {
                  Ok(text) => Ok(text)
                  Err(error) => Err(error.to_string())
                },
              ),
            ),
          )
        }),
        {
          ..model,
          dispatch_guidance: {
            ..empty_dispatch_guidance(),
            context: Some(context),
            request,
            phase: "loading",
            origin: state.origin,
            notice: "正在读取当前正式任务的只读经验查询交接…",
          },
        },
      )
    }
    Loaded(context, request, result) => {
      guard dispatch_guidance_editable(model) &&
        dispatch_guidance_current(model) &&
        state.context == Some(context) &&
        state.request == request &&
        state.phase == "loading" else {
        return (none, model)
      }
      let result = match result {
        Ok(text) => dispatch_guidance_query(text, context)
        Err(error) => Err(error)
      }
      (
        none,
        {
          ..model,
          dispatch_guidance: {
            ..state,
            phase: "ready",
            handoff: match result {
              Ok(value) => Some(value)
              Err(_) => None
            },
            notice: match result {
              Ok(_) =>
                "查询已准备。明确填写 Book 地址，再打开只读经验查询。"
              Err(error) =>
                "未准备经验查询：" +
                error +
                " 普通 Start 仍可使用。"
            },
          },
        },
      )
    }
    Origin(value) => {
      guard dispatch_guidance_editable(model) else { return (none, model) }
      (
        none,
        {
          ..model,
          dispatch_guidance: {
            ..state,
            context: Some(dispatch_guidance_context(model)),
            request: state.request + 1,
            phase: "ready",
            origin: value,
            selected: None,
            cancel: None,
            notice: "",
          },
        },
      )
    }
    OpenBook => {
      guard dispatch_guidance_editable(model) &&
        dispatch_guidance_current(model) &&
        state.handoff is Some(handoff) &&
        state.context is Some(context) else {
        return (none, model)
      }
      let origin = dispatch_lesson_origin(state.origin)
      if origin.is_empty() {
        return (
          none,
          {
            ..model,
            dispatch_guidance: {
              ..state,
              notice: "请填写明确的 Book HTTP(S) 主机地址，不含路径、参数或登录信息。",
            },
          },
        )
      }
      let request = state.request + 1
      (
        @cmd.custom_cmd(kind=Immediately, scheduler => {
          let cancel = dispatch_guidance_connect_book_on(
            lesson_handoff_browser(),
            origin,
            handoff.stringify(),
            (text, acknowledge) => {
              scheduler.add(
                emit(
                  GuidanceAction(
                    Returned(context, request, origin, text, acknowledge),
                  ),
                ),
              )
            },
            reason => {
              scheduler.add(
                emit(GuidanceAction(Ended(context, request, reason))),
              )
            },
          )
          scheduler.add(
            emit(GuidanceAction(Connected(context, request, cancel))),
          )
        }),
        {
          ..model,
          dispatch_guidance: {
            ..state,
            request,
            origin,
            selected: None,
            cancel: None,
            phase: "waiting",
            notice: "在所选 Book 中接收任务查询，检查适用范围并明确返回一条经验。等待不会阻止普通 Start。",
          },
        },
      )
    }
    Connected(context, request, cancel) =>
      if dispatch_guidance_current(model) &&
        state.context == Some(context) &&
        state.request == request &&
        state.phase == "waiting" {
        (
          none,
          { ..model, dispatch_guidance: { ..state, cancel: Some(cancel), }, },
        )
      } else {
        (@cmd.custom_cmd(kind=Immediately, _ => cancel()), model)
      }
    Returned(context, request, origin, text, acknowledge) => {
      guard dispatch_guidance_editable(model) &&
        dispatch_guidance_current(model) &&
        state.context == Some(context) &&
        state.request == request &&
        state.phase == "waiting" &&
        state.origin == origin &&
        state.handoff is Some(handoff) else {
        return (none, model)
      }
      match dispatch_guidance_decode(handoff, origin, text) {
        Err(error) =>
          (
            none,
            {
              ..model,
              dispatch_guidance: {
                ..state,
                notice: "未采用返回的经验：" + error,
              },
            },
          )
        Ok(value) =>
          (
            @cmd.custom_cmd(kind=Immediately, _ => acknowledge(true)),
            {
              ..model,
              dispatch_guidance: {
                ..state,
                phase: "selected",
                selected: Some(value),
                cancel: None,
                notice: "已收到明确选择的经验。请确认下方适用范围；下次 Start 将捕获这份只读建议。",
              },
            },
          )
      }
    }
    Ended(context, request, reason) => {
      guard dispatch_guidance_current(model) &&
        state.context == Some(context) &&
        state.request == request &&
        state.start_body is None else {
        return (none, model)
      }
      (
        none,
        {
          ..model,
          dispatch_guidance: {
            ..state,
            phase: if state.selected is Some(_) {
              "selected"
            } else {
              "ready"
            },
            cancel: None,
            notice: if reason == "received" {
              state.notice
            } else {
              "Book 连接已关闭、超时或不可用。可以重新打开；普通 Start 仍可使用。"
            },
          },
        },
      )
    }
    Clear => {
      guard dispatch_guidance_editable(model) else { return (none, model) }
      (none, { ..model, dispatch_guidance: dispatch_guidance_reset(state), })
    }
  }
}
