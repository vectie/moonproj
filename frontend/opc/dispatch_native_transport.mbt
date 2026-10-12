///|
fn load_dispatch_session(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/session").expect_text(result => {
    let actor = match result {
      Ok(response) => {
        let json = @json.parse(response) catch { _ => Json::null() }
        if dispatch_json_field(json, "authenticated") is True {
          dispatch_json_text(json, "actor_id")
        } else {
          ""
        }
      }
      Err(_) => ""
    }
    emit(DispatchSessionLoaded(actor))
  })
}

///|
fn dispatch_decode_response(
  emit : @rabbita.Emit[Msg],
  task_id : String,
  selection : Int,
  action : String,
  response : String,
) -> Cmd {
  match dispatch_decode_snapshot(response, task_id) {
    Some(snapshot) => emit(DispatchTaskLoaded(task_id, selection, snapshot))
    None =>
      emit(
        DispatchTaskCommandFailed(
          task_id,
          selection,
          action,
          dispatch_response_error(response),
        ),
      )
  }
}

///|
fn load_dispatch_task(
  emit : @rabbita.Emit[Msg],
  task_id : String,
  selection : Int,
) -> Cmd {
  @http.get("/api/company/tasks/" + dispatch_url_encode(task_id)).expect_text(result => {
    match result {
      Ok(response) =>
        dispatch_decode_response(
          emit, task_id, selection, "读取任务", response,
        )
      Err(error) =>
        emit(
          DispatchTaskCommandFailed(
            task_id,
            selection,
            "读取任务",
            error.to_string(),
          ),
        )
    }
  })
}

///|
fn dispatch_start_body(model : Model) -> Json {
  if dispatch_guidance_identity(model) &&
    model.dispatch_guidance.start_body is Some(body) {
    return body
  }
  let fields = {
    "idempotency_key": Json::string(
      "opc-dispatch-start-" + model.dispatch_task_id,
    ),
    "authority": dispatch_task_authority(model, "project:task:update"),
  }
  if dispatch_guidance_current(model) &&
    model.dispatch_run is None &&
    model.dispatch_guidance.selected is Some(value) &&
    model.dispatch_guidance.handoff is Some(handoff) {
    let valid = match
      dispatch_guidance_decode(
        handoff,
        model.dispatch_guidance.origin,
        value.stringify(),
      ) {
      Ok(_) => true
      Err(_) => false
    }
    if valid {
      fields["book_guidance"] = value
    }
  }
  Json::object(fields)
}

///|
fn request_dispatch_task_start(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post(
    "/api/company/plan/tasks/" +
    dispatch_url_encode(model.dispatch_task_id) +
    "/dispatch",
  )
  .with_json(dispatch_start_body(model))
  .expect_text(result => {
    match result {
      Ok(response) =>
        dispatch_decode_response(
          emit,
          model.dispatch_task_id,
          model.dispatch_task_selection,
          "原生执行",
          response,
        )
      Err(error) =>
        emit(dispatch_failure(model, "原生执行", error.to_string()))
    }
  })
}

///|
fn open_dispatch_task(
  emit : @rabbita.Emit[Msg],
  model : Model,
  push? : Bool = true,
  page? : Page = Dispatch,
) -> (Cmd, Model) {
  let id = model.dispatch_task_open_id.trim().to_owned()
  if id.is_empty() {
    return (none, { ..model, notice: "填写要打开的正式任务 ID。", })
  }
  let selection = model.dispatch_task_selection + 1
  let next = dispatch_remember_recent(
    {
      ..model,
      page,
      products: products_clear_preparation(model.products),
      dispatch_task_selection: selection,
      dispatch_task_id: id,
      dispatch_task_open_id: id,
      dispatch_task_pending_action: "load",
      dispatch_run: None,
      dispatch_continuation: {
        ..empty_dispatch_continuation(),
        task_id: id,
        phase: "waiting",
      },
      dispatch_task_report_summary: "",
      dispatch_task_report_id: "",
      dispatch_task_evidence_id: "",
      dispatch_task_event_id: "",
      dispatch_task_audit_id: "",
      dispatch_task_stage: "loading",
      dispatch_task_title: id,
      dispatch_task_product_id: "",
      dispatch_report_product_id: "",
      dispatch_task_project_id: "",
      dispatch_task_workspace: "",
      dispatch_task_model: "",
      dispatch_task_acceptance: "",
      dispatch_task_source_context: Json::null(),
      dispatch_offer_task: Json::null(),
      dispatch_task_commitment: Json::null(),
      dispatch_journey_read_state: "loading",
      dispatch_task_form_open: false,
      dispatch_task_blocked: false,
      dispatch_task_note: "正在恢复正式任务和原生执行记录。",
    },
    id,
  )
  (
    @cmd.batch([
      remember_page_route(page, id, push~),
      dispatch_persist_drafts(emit, next, ""),
      load_dispatch_task(emit, id, selection),
    ]),
    next,
  )
}

///|
#cfg(target="js")
extern "js" fn dispatch_url_encode(value : String) -> String = "encodeURIComponent"

///|
#cfg(target="js")
extern "js" fn dispatch_saved_task() -> String =
  #| () => {
  #|   if (typeof window === "undefined") return "";
  #|   const url = new URL(window.location.href);
  #|   if (url.searchParams.has("task")) return url.searchParams.get("task") || "";
  #|   // An explicit displayed page never borrows a task from an old breadcrumb.
  #|   if (url.searchParams.has("page") || url.searchParams.has("product")) return "";
  #|   // Legacy ID is only a navigation hint. The exact authenticated GET is authoritative.
  #|   try { return window.localStorage.getItem("moonproj.dispatch.task") || ""; } catch (_) { return ""; }
  #| }

///|
fn dispatch_store_task(task_id : String, push : Bool) -> Unit {
  store_page_route(page_route_token(Dispatch), task_id, push)
}

///|
fn save_dispatch_execution_settings(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let body = Json::object({
    "idempotency_key": Json::string(
      "opc-dispatch-settings-" + dispatch_command_nonce(),
    ),
    "execution_workspace": Json::string(
      model.dispatch_task_workspace.trim().to_owned(),
    ),
    "execution_model": Json::string(model.dispatch_task_model.trim().to_owned()),
    "authority": dispatch_task_authority(model, "project:task:update"),
  })
  @http.put(
    "/api/company/plan/tasks/" + dispatch_url_encode(model.dispatch_task_id),
  )
  .with_json(body)
  .expect_text(result => {
    match result {
      Ok(response) =>
        if dispatch_result_text(response, "task", "task_id") ==
          model.dispatch_task_id {
          emit(
            DispatchExecutionSettingsSaved(
              model.dispatch_task_id,
              model.dispatch_task_selection,
            ),
          )
        } else {
          emit(
            dispatch_failure(
              model,
              "保存工作区",
              dispatch_response_error(response),
            ),
          )
        }
      Err(error) =>
        emit(dispatch_failure(model, "保存工作区", error.to_string()))
    }
  })
}
