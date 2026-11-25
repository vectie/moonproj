///|
struct DispatchAcceptedHumanExport {
  request : Int32
  pending : Bool
  expected : Json
  page : String
  notice : String
}

///|
enum DispatchAcceptedHumanExportMsg {
  Download
  Loaded(Int32, Json, String, Result[String, String])
}

///|
fn empty_dispatch_accepted_human_export() -> DispatchAcceptedHumanExport {
  { request: 0, pending: false, expected: Json::null(), page: "", notice: "", }
}

///|
fn dispatch_accepted_human_record(model : Model) -> Json? {
  let state = model.dispatch_continuation
  guard dispatch_work_page(model) &&
    dispatch_task_inspection_only(model) &&
    model.dispatch_task_pending_action.is_empty() &&
    dispatch_accepted_human_task_id_valid(model.dispatch_task_id) &&
    state.task_id == model.dispatch_task_id &&
    state.selection == model.dispatch_task_selection &&
    state.actor == model.dispatch_task_actor_id &&
    state.source_verified &&
    !state.accepted_report_id.is_empty() &&
    dispatch_json_text(state.accepted_delivery_source, "type") ==
    "human_revision" &&
    dispatch_delivery_source_valid(
      model,
      state.accepted_delivery_source,
      state.records,
      state.human_revisions,
    ) else {
    return None
  }
  state.human_revisions
  .filter(record => {
    dispatch_human_revision_valid(model, record) &&
    dispatch_json_text(record, "revision_id") ==
    dispatch_json_text(state.accepted_delivery_source, "revision_id")
  })
  .get(0)
}

///|
// This in-memory binding is never exported. Changing task, selected report,
// navigation, identity or source refresh invalidates the pending download.
fn dispatch_accepted_human_binding(model : Model) -> Json {
  guard dispatch_accepted_human_record(model) is Some(record) else {
    return Json::null()
  }
  let state = model.dispatch_continuation
  {
    "task": model.dispatch_task_id,
    "selection": model.dispatch_task_selection,
    "actor": model.dispatch_task_actor_id,
    "selected_report": model.dispatch_task_report_id,
    "report_summary": model.dispatch_task_report_summary,
    "report_source": state.report_source,
    "report_records": Json::array(state.report_records),
    "accepted_report": state.accepted_report_id,
    "accepted_source": state.accepted_delivery_source,
    "selected_source": state.selected,
    "source_request": state.request,
    "source_revision": state.revision,
    "commitment": model.dispatch_task_commitment,
    "revision": record,
  }
}

///|
fn dispatch_accepted_human_export_reconcile(model : Model) -> Model {
  let state = model.dispatch_accepted_human_export
  if !(state.expected is Null) &&
    (
      state.expected != dispatch_accepted_human_binding(model) ||
      !dispatch_continuation_page_matches(state.page)
    ) {
    {
      ..model,
      dispatch_accepted_human_export: {
        ..empty_dispatch_accepted_human_export(),
        request: state.request + 1,
      },
    }
  } else {
    model
  }
}

///|
fn dispatch_accepted_human_keys(value : Json, keys : Array[String]) -> Bool {
  guard value is Object(fields) && fields.length() == keys.length() else {
    return false
  }
  keys.all(key => fields.contains(key))
}

///|
extern "js" fn dispatch_accepted_human_task_id_valid(value : String) -> Bool =
  #| value => /^[A-Za-z0-9_.:-]{1,128}$/.test(value) && value!=='.' && value!=='..'

///|
fn dispatch_accepted_human_payload(model : Model, text : String) -> Bool {
  // Bound before parsing. The API emits a single JSON object; keep its exact
  // response text for the file instead of serializing the parsed copy.
  if text.length() > 524288 || dispatch_human_revision_utf8_size(text) > 524288 {
    return false
  }
  let value = @json.parse(text) catch { _ => return false }
  guard dispatch_accepted_human_record(model) is Some(record) else {
    return false
  }
  let state = model.dispatch_continuation
  if !dispatch_accepted_human_keys(value, [
      "contract_version", "source_product", "provenance_scope", "authenticity", "authorizing",
      "task", "report", "revision", "content",
    ]) ||
    dispatch_json_text(value, "contract_version") !=
    "moonproj.accepted-human-result.v1" ||
    dispatch_json_text(value, "source_product") != "moonproj" ||
    dispatch_json_text(value, "provenance_scope") !=
    "captured_accepted_human_revision" ||
    dispatch_json_text(value, "authenticity") != "unsigned_source_observation" ||
    !(dispatch_json_field(value, "authorizing") is False) {
    return false
  }
  for
    (key, id) in [
      ("task", model.dispatch_task_id),
      ("report", state.accepted_report_id),
    ] {
    let reference = dispatch_json_field(value, key)
    let version = dispatch_json_text(reference, "record_version")
    if !dispatch_accepted_human_keys(reference, [
        "record_id", "record_version", "record_digest",
      ]) ||
      dispatch_json_text(reference, "record_id") != id ||
      !dispatch_accepted_human_version_valid(version) ||
      !dispatch_outcome_digest_shape(
        dispatch_json_text(reference, "record_digest"),
      ) {
      return false
    }
  }
  // Hydrated accepted tasks carry the source task revision and report receipt.
  // Older in-memory states can lack these optional captures; when present,
  // never silently export a different version of the same record identity.
  if state.revision > 0.0 &&
    (
      state.revision > 2147483647.0 ||
      state.revision.trunc() != state.revision ||
      dispatch_json_text(dispatch_json_field(value, "task"), "record_version") !=
      state.revision.to_int().to_string()
    ) {
    return false
  }
  let receipts = dispatch_continuation_array(
    model.dispatch_task_commitment,
    "receipts",
  ).filter(receipt => {
    dispatch_json_text(receipt, "action") == "report" &&
    dispatch_json_text(receipt, "report_id") == state.accepted_report_id
  })
  if receipts.length() > 1 {
    return false
  }
  if receipts.get(0) is Some(receipt) {
    let version = dispatch_json_field(receipt, "revision").stringify()
    if dispatch_json_text(model.dispatch_task_commitment, "task_id") !=
      model.dispatch_task_id ||
      !dispatch_accepted_human_version_valid(version) ||
      dispatch_json_text(dispatch_json_field(value, "report"), "record_version") !=
      version {
      return false
    }
  }
  let revision = dispatch_json_field(value, "revision")
  if !dispatch_accepted_human_keys(revision, [
      "revision_id", "original_run_id", "session_id", "original_command_id", "output_command_id",
      "output_evidence_id", "revision_snapshot_digest",
    ]) {
    return false
  }
  for
    key in [
      "revision_id", "original_run_id", "session_id", "original_command_id",
    ] {
    if dispatch_json_field(revision, key) != dispatch_json_field(record, key) {
      return false
    }
  }
  let output = dispatch_json_field(record, "output")
  if dispatch_json_field(revision, "output_command_id") !=
    dispatch_json_field(output, "command_id") ||
    dispatch_json_field(revision, "output_evidence_id") !=
    dispatch_json_field(output, "evidence_id") ||
    !dispatch_outcome_digest_shape(
      dispatch_json_text(revision, "revision_snapshot_digest"),
    ) {
    return false
  }
  let content = dispatch_json_field(value, "content")
  let captured_content = dispatch_json_field(record, "content")
  guard dispatch_accepted_human_keys(content, [
      "encoding", "media_type", "size_bytes", "sha256", "data",
    ]) &&
    dispatch_json_text(content, "encoding") == "base64" &&
    dispatch_json_text(content, "media_type") == "text/plain;charset=utf-8" &&
    dispatch_json_text(content, "sha256") ==
    "sha256:" + dispatch_json_text(captured_content, "sha256") &&
    dispatch_json_field(content, "size_bytes") ==
    dispatch_json_field(captured_content, "size_bytes") &&
    dispatch_json_field(content, "size_bytes") is Number(size, ..) &&
    dispatch_json_field(content, "data") is String(data) else {
    return false
  }
  dispatch_accepted_human_base64_valid(data, size)
}

///|
extern "js" fn dispatch_accepted_human_base64_valid(
  data : String,
  size : Double,
) -> Bool =
  #| (data,size) => Number.isInteger(size) && size>=0 && size<=262144 && data.length===4*Math.ceil(size/3) && (()=>{try{const bytes=atob(data);return bytes.length===size && btoa(bytes)===data;}catch(_){return false;}})()

///|
extern "js" fn dispatch_accepted_human_version_valid(value : String) -> Bool =
  #| value => /^[1-9][0-9]{0,9}$/.test(value) && Number(value)<=2147483647

///|
fn dispatch_accepted_human_filename(task : String, revision : String) -> String {
  "moonproj-accepted-human-" +
  dispatch_accepted_human_filename_part(task) +
  "-" +
  dispatch_accepted_human_filename_part(revision) +
  ".json"
}

///|
extern "js" fn dispatch_accepted_human_filename_part(value : String) -> String =
  #| value => value.replace(/[^A-Za-z0-9_-]/g,'_').slice(0,64)||'unknown'

///|
fn dispatch_accepted_human_export_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchAcceptedHumanExportMsg,
) -> (Cmd, Model) {
  let state = model.dispatch_accepted_human_export
  let expected = dispatch_accepted_human_binding(model)
  if expected is Null {
    return (none, model)
  }
  match action {
    Download => {
      if state.pending &&
        state.expected == expected &&
        dispatch_continuation_page_matches(state.page) {
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
          AcceptedHumanExportAction(
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
              AcceptedHumanExportAction(
                Loaded(
                  request,
                  expected,
                  page,
                  Err("accepted-human-export-timeout"),
                ),
              ),
            ),
          )
        }),
        30000,
      )
      (
        @cmd.batch([command, timeout]),
        {
          ..model,
          dispatch_accepted_human_export: {
            request,
            expected,
            page,
            pending: true,
            notice: "正在读取已接受人工修订的来源观察文件…",
          },
        },
      )
    }
    Loaded(request, captured, page, result) => {
      if !state.pending ||
        state.request != request ||
        state.expected != captured ||
        captured != expected ||
        state.page != page ||
        !dispatch_continuation_page_matches(page) {
        return (none, model)
      }
      let valid = match result {
        Ok(text) => dispatch_accepted_human_payload(model, text)
        Err(_) => false
      }
      let command = if valid && result is Ok(text) {
        let filename = dispatch_accepted_human_filename(
          model.dispatch_task_id,
          dispatch_json_text(
            model.dispatch_continuation.accepted_delivery_source,
            "revision_id",
          ),
        )
        @cmd.custom_cmd(_ => dispatch_outcome_download(text, filename))
      } else {
        none
      }
      (
        command,
        {
          ..model,
          dispatch_accepted_human_export: {
            ..state,
            pending: false,
            notice: if valid {
              "已下载捕获的已接受人工修订。此文件是未签名的来源观察，不授予权限，也不表示 Book 接受。"
            } else if result is Err("accepted-human-export-timeout") {
              "读取超时（30 秒），尚未下载。可以重试；迟到响应会被忽略。"
            } else {
              "未下载：读取失败或返回的任务、报告、修订及内容与当前接受记录不匹配。请刷新正式任务后重试。"
            },
          },
        },
      )
    }
  }
}

///|
fn dispatch_accepted_human_export_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let source = model.dispatch_continuation.accepted_delivery_source
  if !dispatch_task_inspection_only(model) ||
    dispatch_json_text(source, "type") != "human_revision" {
    return @html.nothing
  }
  let state = model.dispatch_accepted_human_export
  div(class="journey-section accepted-human-export") <| [
    strong("导出已接受人工修订 · 只读文件"),
    p(
      "捕获的来源观察 / 未签名 / 不授予权限；下载不会改变任务或 Book 的接受状态。",
    ),
    if dispatch_accepted_human_record(model) is Some(_) {
      if state.pending &&
        state.expected == dispatch_accepted_human_binding(model) {
        p("正在读取，请稍候…")
      } else {
        secondary_button(
          emit,
          AcceptedHumanExportAction(Download),
          "下载已接受人工修订 JSON",
        )
      }
    } else {
      p(
        "请刷新正式任务，核实已接受报告和准确人工修订后下载。",
      )
    },
    if !state.notice.is_empty() {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        state.notice,
      )
    } else {
      @html.nothing
    },
  ]
}
