///|
// Page-local preparation only. Customer-facing notes never enter task storage.
struct DispatchClientDelivery {
  request : Int32
  pending : Bool
  expected : Json
  page : String
  source : String
  body : String
  note : @client_delivery.Note
  include_source : Bool
  notice : String
}

///|
enum DispatchClientDeliveryMsg {
  Prepare
  Loaded(Int32, Json, String, Result[String, String])
  Edit(String, String)
  ToggleSource
  Download
  Close
}

///|
fn empty_dispatch_client_delivery() -> DispatchClientDelivery {
  {
    request: 0,
    pending: false,
    expected: Json::null(),
    page: "",
    source: "",
    body: "",
    note: {
      title: "交付结果",
      summary: "本次交付包含一个文本结果，详见随附文件。",
      review_request: "请按约定验收标准审阅，并回复接受或需要调整的内容。",
      filename: "delivered-result.txt",
    },
    include_source: false,
    notice: "",
  }
}

///|
fn dispatch_client_delivery_reconcile(model : Model) -> Model {
  let state = model.dispatch_client_delivery
  if !(state.expected is Null) &&
    (
      state.expected != dispatch_accepted_human_binding(model) ||
      !dispatch_continuation_page_matches(state.page)
    ) {
    {
      ..model,
      dispatch_client_delivery: {
        ..empty_dispatch_client_delivery(),
        request: state.request + 1,
      },
    }
  } else {
    model
  }
}

///|
fn dispatch_client_delivery_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchClientDeliveryMsg,
) -> (Cmd, Model) {
  let state = model.dispatch_client_delivery
  let expected = dispatch_accepted_human_binding(model)
  if action is Close {
    return (
      none,
      {
        ..model,
        dispatch_client_delivery: {
          ..empty_dispatch_client_delivery(),
          request: state.request + 1,
        },
      },
    )
  }
  if expected is Null {
    return (none, model)
  }
  match action {
    Prepare => {
      if state.pending ||
        (!state.source.is_empty() && state.expected == expected) {
        return (none, model)
      }
      let request = state.request + 1
      let page = dispatch_handoff_current_page()
      let command = @http.get(
        "/api/company/tasks/" +
        model.dispatch_task_id +
        "/accepted-human-result",
      ).expect_text(result => {
        emit(
          ClientDeliveryAction(
            Loaded(
              request,
              expected,
              page,
              match result {
                Ok(text) => Ok(text)
                Err(error) => Err(error.to_string())
              },
            ),
          ),
        )
      })
      let timeout = @cmd.delay(
        @cmd.custom_cmd(scheduler => {
          scheduler.add(
            emit(
              ClientDeliveryAction(
                Loaded(request, expected, page, Err("timeout")),
              ),
            ),
          )
        }),
        30000,
      )
      let filename = dispatch_accepted_human_record(model)
        .map(record => {
          @client_delivery.default_filename(
            dispatch_json_text(dispatch_json_field(record, "output"), "path"),
          )
        })
        .unwrap_or("delivered-result.txt")
      let note = if state.expected == expected {
        state.note
      } else {
        { ..empty_dispatch_client_delivery().note, filename, }
      }
      (
        @cmd.batch([command, timeout]),
        {
          ..model,
          dispatch_client_delivery: {
            request,
            expected,
            page,
            source: "",
            body: "",
            note,
            include_source: state.expected == expected && state.include_source,
            pending: true,
            notice: "正在准备已接受的准确文本…",
          },
        },
      )
    }
    Loaded(request, captured, page, result) => {
      if !state.pending ||
        request != state.request ||
        captured != state.expected ||
        captured != expected ||
        page != state.page ||
        !dispatch_continuation_page_matches(page) {
        return (none, model)
      }
      let prepared = match result {
        Ok(source) if dispatch_accepted_human_payload(model, source) =>
          try @client_delivery.body_text(source) catch {
            @client_delivery.Invalid(error) => Err(error)
          } noraise {
            body => Ok((source, body))
          }
        Err("timeout") => Err("读取超时，可以重试。")
        _ => Err("读取失败或来源已变化，请刷新任务后重试。")
      }
      let next = match prepared {
        Ok((source, body)) =>
          { ..state, source, body, pending: false, notice: "", }
        Err(error) => { ..state, pending: false, notice: error, }
      }
      (none, { ..model, dispatch_client_delivery: next, })
    }
    Edit(field, value) => {
      if state.source.is_empty() || state.expected != expected {
        return (none, model)
      }
      let note = match field {
        "title" => { ..state.note, title: value, }
        "summary" => { ..state.note, summary: value, }
        "review_request" => { ..state.note, review_request: value, }
        "filename" => { ..state.note, filename: value, }
        _ => return (none, model)
      }
      (
        none,
        { ..model, dispatch_client_delivery: { ..state, note, notice: "", }, },
      )
    }
    ToggleSource => {
      if state.source.is_empty() || state.expected != expected {
        return (none, model)
      }
      (
        none,
        {
          ..model,
          dispatch_client_delivery: {
            ..state,
            include_source: !state.include_source,
            notice: "",
          },
        },
      )
    }
    Download => {
      if state.source.is_empty() ||
        state.pending ||
        state.expected != expected ||
        !dispatch_continuation_page_matches(state.page) ||
        !dispatch_accepted_human_payload(model, state.source) {
        return (none, model)
      }
      let archive = @client_delivery.archive(
        state.source,
        state.note,
        include_source=state.include_source,
      ) catch {
        @client_delivery.Invalid(error) =>
          return (
            none,
            { ..model, dispatch_client_delivery: { ..state, notice: error, }, },
          )
      }
      let data = @base64.encode(archive)
      let filename = state.note.filename + ".zip"
      let command = @cmd.custom_cmd(_ => {
        dispatch_client_delivery_download(data, filename)
      })
      (
        command,
        {
          ..model,
          dispatch_client_delivery: {
            ..state,
            notice: "已准备 ZIP 下载，未向客户发送。",
          },
        },
      )
    }
    Close => (none, model)
  }
}

///|
extern "js" fn dispatch_client_delivery_download(
  data : String,
  filename : String,
) =
  #| (data,filename) => {const bytes=Uint8Array.from(atob(data),c=>c.charCodeAt(0));const blob=new Blob([bytes],{type:'application/zip'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
