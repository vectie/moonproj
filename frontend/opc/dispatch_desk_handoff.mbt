///|
struct DispatchDeskHandoff {
  task_id : String
  selection : Int
  request : Int
  pending : Bool
  error : String
  follow_up : Bool
  output : Json
}

///|
fn empty_dispatch_desk_handoff() -> DispatchDeskHandoff {
  {
    task_id: "",
    selection: -1,
    request: 0,
    pending: false,
    error: "",
    follow_up: false,
    output: Json::null(),
  }
}

///|
enum DispatchDeskHandoffMsg {
  Open
  Continue
  Output(String, String, String)
  Loaded(String, Int, Int, String, String, Result[String, String])
}

///|
fn dispatch_desk_handoff_url(
  response : String,
  task_id : String,
  return_to : String,
  follow_up? : Bool = false,
) -> Result[String, String] {
  let json = @json.parse(response) catch { _ => Json::null() }
  if dispatch_json_text(json, "schema") != "moonproj.desk-handoff.v1" {
    return Err("无法读取 MoonDesk 交接记录；请重试。")
  }
  let state = dispatch_json_text(json, "state")
  if state != "ready" {
    return Err(
      match state {
        "destination_unconfigured" =>
          "尚未配置 MoonDesk 地址；请配置后重试。"
        "destination_invalid" =>
          "MoonDesk 地址配置无效；请修正后重试。"
        "no_execution" => "此任务尚无已捕获的原生执行。"
        _ => "MoonDesk 交接暂不可用；请重试。"
      },
    )
  }
  let work = dispatch_json_field(json, "work")
  let accepted = dispatch_json_field(json, "task_accepted")
  if follow_up && accepted is True {
    return Err("此任务已接受，只能查看原始执行。")
  }
  let session = dispatch_json_text(work, "session_id")
  let command = dispatch_json_text(work, "original_command_id")
  let root = dispatch_json_text(work, "book_root")
  let run = dispatch_json_text(work, "run_id")
  if dispatch_json_text(work, "task_id") != task_id ||
    [task_id, run, session, command, root].contains("") ||
    dispatch_json_text(json, "mode") !=
    (if follow_up { "follow_up" } else { "inspect" }) {
    return Err(
      "原生执行身份不完整或已改变；请刷新任务后重试。",
    )
  }
  let url = dispatch_build_desk_url(
    dispatch_json_text(json, "desk_origin"),
    task_id,
    run,
    session,
    command,
    root,
    return_to,
  )
  if url.is_empty() {
    Err("MoonDesk 地址或返回地址无效；请检查配置。")
  } else {
    let url = match accepted {
      True => dispatch_desk_accepted_url(url, true)
      False => dispatch_desk_accepted_url(url, false)
      _ => url
    }
    Ok(if follow_up { dispatch_desk_follow_up_url(url) } else { url })
  }
}

///|
fn dispatch_desk_handoff_update(
  emit : @rabbita.Emit[Msg],
  action : DispatchDeskHandoffMsg,
  model : Model,
) -> (Cmd, Model) {
  match action {
    Open | Continue | Output(_, _, _) => {
      let follow_up = action is Continue
      let output = match action {
        Output(command, path, evidence) => {
          let value : Json = {
            "command_id": command,
            "path": path,
            "evidence_id": evidence,
          }
          if !dispatch_output_is_current(model, value) {
            return (none, model)
          }
          value
        }
        _ => Json::null()
      }
      if follow_up && dispatch_task_inspection_only(model) {
        return (none, model)
      }
      let state = model.dispatch_desk_handoff
      if model.page != Dispatch ||
        model.dispatch_task_id.is_empty() ||
        (
          state.pending &&
          state.task_id == model.dispatch_task_id &&
          state.selection == model.dispatch_task_selection
        ) {
        return (none, model)
      }
      let next = {
        task_id: model.dispatch_task_id,
        selection: model.dispatch_task_selection,
        request: state.request + 1,
        pending: true,
        error: "",
        follow_up,
        output,
      }
      (
        load_dispatch_desk_handoff(emit, next),
        { ..model, dispatch_desk_handoff: next, },
      )
    }
    Loaded(task, selection, request, expected_page, return_to, result) => {
      let state = model.dispatch_desk_handoff
      if model.page != Dispatch ||
        !dispatch_response_matches(model, task, selection) ||
        !state.pending ||
        state.request != request ||
        state.task_id != task ||
        state.selection != selection {
        return (none, model)
      }
      let resolved = match result {
        Ok(response) =>
          dispatch_desk_handoff_url(
            response,
            task,
            return_to,
            follow_up=state.follow_up,
          )
        Err(error) => Err("无法读取 MoonDesk 交接：" + error)
      }
      match resolved {
        Ok(url) => {
          let url = if state.output is Null {
            url
          } else {
            let payload = @json.parse(response_from_handoff_result(result)) catch {
              _ => Json::null()
            }
            let work = dispatch_json_field(payload, "work")
            guard model.dispatch_run is Some(run) else { return (none, model) }
            if dispatch_json_text(work, "run_id") != run.run_id ||
              dispatch_json_text(work, "session_id") != run.session_id ||
              dispatch_json_text(work, "original_command_id") != run.command_id ||
              dispatch_json_text(work, "book_root") != run.workspace {
              return (
                none,
                {
                  ..model,
                  dispatch_desk_handoff: {
                    ..state,
                    pending: false,
                    error: "执行身份已改变；请刷新任务后重试。",
                  },
                },
              )
            }
            dispatch_desk_output_url(url, state.output)
          }
          (
            @cmd.custom_cmd(_ => dispatch_navigate_desk(expected_page, url)),
            {
              ..model,
              dispatch_desk_handoff: { ..state, pending: false, error: "", },
            },
          )
        }
        Err(error) =>
          (
            none,
            {
              ..model,
              dispatch_desk_handoff: { ..state, pending: false, error, },
            },
          )
      }
    }
  }
}

///|
fn response_from_handoff_result(result : Result[String, String]) -> String {
  match result {
    Ok(value) => value
    Err(_) => ""
  }
}

///|
fn dispatch_output_valid_path(path : String) -> Bool {
  !path.is_empty() &&
  path.length() <= 4096 &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains("\u0000") &&
  !path.split("/").any(part => part == "" || part == "." || part == "..")
}

///|
fn dispatch_output_is_current(model : Model, output : Json) -> Bool {
  let command = dispatch_json_text(output, "command_id")
  let path = dispatch_json_text(output, "path")
  let evidence = dispatch_json_text(output, "evidence_id")
  if command.is_empty() ||
    evidence.is_empty() ||
    !dispatch_output_valid_path(path) {
    return false
  }
  guard model.dispatch_run is Some(run) else { return false }
  if run.task_id != model.dispatch_task_id {
    return false
  }
  if command == run.command_id {
    return run.artifacts.any(item => {
      item.path == path && item.evidence_id == evidence
    })
  }
  let state = model.dispatch_continuation
  state.task_id == model.dispatch_task_id &&
  state.selection == model.dispatch_task_selection &&
  state.actor == model.dispatch_task_actor_id &&
  state.phase == "ready" &&
  dispatch_json_text(state.candidate, "original_run_id") == run.run_id &&
  dispatch_json_text(state.candidate, "task_id") == model.dispatch_task_id &&
  dispatch_json_text(state.candidate, "session_id") == run.session_id &&
  dispatch_json_text(state.candidate, "workspace") == run.workspace &&
  dispatch_json_text(state.candidate, "command_id") == command &&
  dispatch_continuation_array(state.candidate, "artifact_refs").any(item => {
    dispatch_json_text(item, "command_id") == command &&
    dispatch_json_text(item, "path") == path &&
    dispatch_json_text(item, "evidence_id") == evidence
  })
}

///|
fn dispatch_output_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command : String,
  path : String,
  evidence : String,
) -> @html.Html {
  if dispatch_output_is_current(model, {
      "command_id": command,
      "path": path,
      "evidence_id": evidence,
    }) {
    secondary_button(
      emit,
      DeskHandoffAction(Output(command, path, evidence)),
      "在 MoonDesk 打开此输出 · 当前文件",
    )
  } else {
    @html.nothing
  }
}

///|
fn dispatch_desk_handoff_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.dispatch_run is None {
    return @html.nothing
  }
  let state = model.dispatch_desk_handoff
  let current = state.task_id == model.dispatch_task_id &&
    state.selection == model.dispatch_task_selection
  div(class="inline-form") <| [
    secondary_button(
      emit,
      DeskHandoffAction(Open),
      if current && state.pending {
        "正在读取准确执行…"
      } else {
        "在 MoonDesk 打开准确执行"
      },
    ),
    small(
      "只读查看已捕获的会话、命令和文件；不会发起后续执行。",
    ),
    if !dispatch_task_inspection_only(model) {
      secondary_button(
        emit,
        DeskHandoffAction(Continue),
        "在 MoonDesk 继续此工作 · 新的人工指令",
      )
    } else {
      @html.nothing
    },
    if current && !state.error.is_empty() {
      p(state.error)
    } else {
      @html.nothing
    },
  ]
}
