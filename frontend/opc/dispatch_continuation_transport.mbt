///|
fn dispatch_load_continuations(
  emit : @rabbita.Emit[Msg],
  state : DispatchContinuationState,
  page : String,
) -> Cmd {
  let url = "/api/company/tasks/" +
    dispatch_url_encode(state.task_id) +
    "/continuations" +
    (if state.preview_revision != "" {
      "?human_revision_id=" + dispatch_url_encode(state.preview_revision)
    } else if state.preview_command == "" {
      ""
    } else {
      "?command_id=" + dispatch_url_encode(state.preview_command)
    })
  @http.get(url).expect_text(result => {
    emit(
      ContinuationAction(
        Loaded(
          state.task_id,
          state.selection,
          state.request,
          page,
          state.preview_command,
          match result {
            Ok(value) => Ok(value)
            Err(error) => Err(error.to_string())
          },
        ),
      ),
    )
  })
}

///|
fn dispatch_continuation_attach_body(
  model : Model,
  original : Bool,
  idempotency_key : String,
  human_revision~ : Bool = false,
) -> Json {
  let run = model.dispatch_run.unwrap()
  let candidate = model.dispatch_continuation.candidate
  let fields : Map[String, Json] = {
    "idempotency_key": Json::string(idempotency_key),
    "original_run_id": Json::string(run.run_id),
    "select_for_delivery": Json::boolean(true),
    "authority": dispatch_task_authority(model, "project:task:update"),
  }
  if original {
    fields["selected_delivery_source"] = {
      "type": "original",
      "original_run_id": run.run_id,
      "command_id": run.command_id,
    }
  } else if human_revision {
    fields["human_revision_id"] = dispatch_json_field(
      model.dispatch_continuation.human_revision_candidate,
      "revision_id",
    )
  } else {
    fields["continuation_id"] = dispatch_json_field(
      candidate, "continuation_id",
    )
    fields["command_id"] = dispatch_json_field(candidate, "command_id")
  }
  Json::object(fields)
}

///|
fn dispatch_attach_continuation(
  emit : @rabbita.Emit[Msg],
  model : Model,
  request : Int32,
  body : Json,
) -> Cmd {
  let page = dispatch_handoff_current_page()
  @http.post(
    "/api/company/plan/tasks/" +
    dispatch_url_encode(model.dispatch_task_id) +
    "/continuations",
  )
  .with_json(body)
  .expect_text(result => {
    emit(
      ContinuationAction(
        Attached(
          model.dispatch_task_id,
          model.dispatch_task_selection,
          request,
          page,
          match result {
            Ok(value) => Ok(value)
            Err(error) => Err(error.to_string())
          },
        ),
      ),
    )
  })
}

///|
#cfg(target="js")
extern "js" fn dispatch_continuation_return_hint(
  page : String,
  task : String,
  run : String,
) -> String =
  #| (page, task, run) => { try { const url = new URL(page); return url.searchParams.get('task') === task && url.searchParams.get('source_run') === run && url.searchParams.get('continuation_id') ? url.searchParams.get('continuation_command') || '' : ''; } catch (_) { return ''; } }

///|
#cfg(target="js")
extern "js" fn dispatch_continuation_page_matches(page : String) -> Bool =
  #| page => !globalThis.location || globalThis.location.href.split('#', 1)[0] === page.split('#', 1)[0]
