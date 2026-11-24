///|
struct DispatchArtifact {
  path : String
  evidence_id : String
} derive(Debug, Eq)

///|
// Only the public per-run summary is decoded here, never saved PRD text.
struct DispatchProductPrd {
  document_id : String?
  source_sha256 : String?
  source_size_bytes : Double?
  version : String?
  coverage : String?
  text_sha256 : String?
  text_size_bytes : Double?
  extraction_version : String?
  limitations : Array[String]?
} derive(Debug, Eq, FromJson)

///|
struct DispatchProductContext {
  schema : String
  product_id : String
  product_name : String
  coverage : String
  issues : Array[String]
  context_path : String
  sha256 : String
  size_bytes : Double
  prd : DispatchProductPrd?
  artifact_state : String
  artifact_error : String
} derive(Debug, Eq, FromJson)

///|
enum DispatchProductContextReadback {
  Unbound
  Unsupported(String)
  Malformed
  Captured(DispatchProductContext)
} derive(Debug, Eq)

///|
struct DispatchRun {
  run_id : String
  task_id : String
  session_id : String
  command_id : String
  workspace : String
  state : String
  summary : String
  error : String
  evidence_ids : Array[String]
  output_urls : Array[String]
  artifacts : Array[DispatchArtifact]
  product_context : DispatchProductContextReadback
  book_guidance : Json
} derive(Debug, Eq)

///|
struct DispatchSnapshot {
  offer_task : Json
  source_context : Json
  commitment : Json
  product_id : String
  report_product_id : String
  task_id : String
  project_id : String
  title : String
  acceptance : String
  owner_id : String
  begin_date : String
  end_date : String
  workspace : String
  model : String
  state : String
  report_id : String
  report_summary : String
  evidence_ids : Array[String]
  run : DispatchRun?
  continuation_records : Array[Json]
  human_revision_records : Array[Json]
  delivery_source : Json
  report_records : Array[Json]
  revision : Double
  accepted_report_id : String
  accepted_delivery_source : Json
} derive(Debug, Eq)

///|
fn dispatch_json_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn dispatch_json_text(value : Json, name : String) -> String {
  match dispatch_json_field(value, name) {
    String(text) => text
    _ => ""
  }
}

///|
fn dispatch_json_strings(value : Json, name : String) -> Array[String] {
  let result : Array[String] = []
  match dispatch_json_field(value, name) {
    Array(items) =>
      for item in items {
        if item is String(text) && !text.is_empty() {
          result.push(text)
        }
      }
    _ => ()
  }
  result
}

///|
fn dispatch_product_context_bytes_valid(value : Double) -> Bool {
  value >= 0.0 && value <= 9007199254740991.0 && value.trunc() == value
}

///|
// Derived optional fields use absence, while the service also sends explicit
// null for an unavailable PRD. Normalize only the public summary and PRD fields.
fn dispatch_product_context_without_nulls(value : Json) -> Json {
  guard value is Object(fields) else { return value }
  let normalized : Map[String, Json] = Map([])
  for name, field in fields {
    if !(field is Null) {
      normalized[name] = field
    }
  }
  Json::object(normalized)
}

///|
fn dispatch_decode_product_context(
  value : Json,
) -> DispatchProductContextReadback {
  if value is Null {
    return Unbound
  }
  let schema = dispatch_json_text(value, "schema")
  if schema.is_empty() {
    return Malformed
  }
  if schema != "moonproj.product-context.v1" {
    return Unsupported(schema)
  }
  let normalized = dispatch_product_context_without_nulls(value)
  if normalized is Object(fields) && fields.get("prd") is Some(prd) {
    fields["prd"] = dispatch_product_context_without_nulls(prd)
  }
  let context : DispatchProductContext = @json.from_json(normalized) catch {
    _ => return Malformed
  }
  if !["complete", "partial", "unavailable", "untagged"].contains(
      context.coverage,
    ) ||
    !["pending", "available", "missing", "conflict", "unavailable"].contains(
      context.artifact_state,
    ) ||
    !dispatch_product_context_bytes_valid(context.size_bytes) {
    return Malformed
  }
  if context.prd is Some(prd) {
    for size in [prd.source_size_bytes, prd.text_size_bytes] {
      if size is Some(bytes) && !dispatch_product_context_bytes_valid(bytes) {
        return Malformed
      }
    }
  }
  Captured(context)
}

///|
fn dispatch_response_error(response : String) -> String {
  let json = @json.parse(response) catch { _ => Json::null() }
  let error = dispatch_json_text(json, "error")
  if error.is_empty() {
    "服务器没有返回匹配任务的正式记录；请刷新任务状态。"
  } else {
    error
  }
}

///|
fn dispatch_failure(model : Model, action : String, detail : String) -> Msg {
  DispatchTaskCommandFailed(
    model.dispatch_task_id,
    model.dispatch_task_selection,
    action,
    detail,
  )
}

///|
fn dispatch_decode_snapshot(
  response : String,
  expected_task : String,
) -> DispatchSnapshot? {
  let root = @json.parse(response) catch { _ => Json::null() }
  let data = dispatch_json_field(root, "data")
  let task = dispatch_json_field(data, "task")
  let task_id = dispatch_json_text(task, "taskGuid")
  if task_id.is_empty() || task_id != expected_task {
    return None
  }
  let execution = dispatch_json_field(task, "execution")
  let run = if execution is Object(_) {
    let run_id = dispatch_json_text(execution, "run_id")
    let run_task = dispatch_json_text(execution, "task_id")
    let session_id = dispatch_json_text(execution, "session_id")
    let command_id = dispatch_json_text(execution, "command_id")
    if run_task != task_id ||
      run_id.is_empty() ||
      session_id.is_empty() ||
      command_id.is_empty() {
      return None
    }
    let artifacts : Array[DispatchArtifact] = []
    match dispatch_json_field(execution, "artifact_refs") {
      Array(items) =>
        for item in items {
          let path = dispatch_json_text(item, "path")
          if !path.is_empty() &&
            dispatch_json_text(item, "command_id") == command_id {
            artifacts.push({
              path,
              evidence_id: dispatch_json_text(item, "evidence_id"),
            })
          }
        }
      _ => ()
    }
    Some({
      run_id,
      task_id: run_task,
      session_id,
      command_id,
      workspace: dispatch_json_text(execution, "workspace"),
      state: dispatch_json_text(execution, "state"),
      summary: dispatch_json_text(execution, "summary"),
      error: dispatch_json_text(execution, "error"),
      evidence_ids: dispatch_json_strings(execution, "evidence_ids"),
      output_urls: dispatch_json_strings(execution, "output_urls"),
      artifacts,
      product_context: dispatch_decode_product_context(
        dispatch_json_field(execution, "product_context"),
      ),
      book_guidance: dispatch_json_field(execution, "book_guidance"),
    })
  } else {
    None
  }
  let mut report_id = ""
  let mut report_summary = ""
  let mut report_product_id = ""
  let evidence_ids : Array[String] = []
  match dispatch_json_field(data, "reports") {
    Array(reports) =>
      for report in reports {
        let id = dispatch_json_text(report, "reportGuid")
        if !id.is_empty() && report_id.is_empty() {
          report_id = id
          report_product_id = dispatch_json_text(report, "product_id")
          report_summary = dispatch_json_text(report, "summary")
          for reference in dispatch_json_strings(report, "evidence_ids") {
            if !evidence_ids.contains(reference) {
              evidence_ids.push(reference)
            }
          }
        }
      }
    _ => ()
  }
  Some({
    source_context: dispatch_json_field(task, "source_context"),
    offer_task: task,
    commitment: dispatch_json_field(data, "commitment"),
    product_id: dispatch_json_text(task, "product_id"),
    report_product_id,
    task_id,
    project_id: dispatch_json_text(task, "projGuid"),
    title: dispatch_json_text(task, "taskName"),
    acceptance: dispatch_json_text(task, "remarks")
    .strip_prefix("验收标准：")
    .map(StringView::to_owned)
    .unwrap_or(dispatch_json_text(task, "remarks")),
    owner_id: dispatch_json_text(task, "ownerGuid"),
    begin_date: dispatch_json_text(task, "planBeginDate"),
    end_date: dispatch_json_text(task, "planEndDate"),
    workspace: dispatch_json_text(task, "execution_workspace"),
    model: dispatch_json_text(task, "execution_model"),
    state: dispatch_json_text(task, "status"),
    report_id,
    report_summary,
    evidence_ids,
    run,
    continuation_records: dispatch_continuation_array(task, "continuations"),
    human_revision_records: dispatch_continuation_array(task, "human_revisions"),
    delivery_source: dispatch_json_field(task, "selected_delivery_source"),
    report_records: dispatch_continuation_array(data, "reports"),
    revision: dispatch_continuation_revision(task),
    accepted_report_id: dispatch_json_text(task, "accepted_report_id"),
    accepted_delivery_source: dispatch_json_field(
      task, "accepted_delivery_source",
    ),
  })
}

///|
fn dispatch_response_matches(
  model : Model,
  task_id : String,
  selection : Int32,
) -> Bool {
  model.dispatch_task_id == task_id &&
  model.dispatch_task_selection == selection
}

///|
fn dispatch_work_page(model : Model) -> Bool {
  [Dispatch, Objectives].contains(model.page)
}

///|
fn dispatch_run_pollable(run : DispatchRun?) -> Bool {
  match run {
    Some(run) =>
      [
        "queued", "running", "waiting_approval", "unknown", "runtime_unavailable",
        "interrupted",
      ].contains(run.state)
    None => false
  }
}

///|
fn dispatch_can_start(model : Model) -> Bool {
  !model.dispatch_task_id.is_empty() &&
  dispatch_json_text(model.dispatch_offer_task, "taskType") != "key_node" &&
  model.dispatch_task_pending_action.is_empty() &&
  (
    model.dispatch_task_stage == "pending" ||
    model.dispatch_task_stage == "in_progress"
  ) &&
  (match model.dispatch_run {
    None => true
    Some(run) =>
      ["runtime_unavailable", "unknown", "interrupted"].contains(run.state)
  })
}

///|
fn dispatch_can_submit(model : Model) -> Bool {
  if model.dispatch_continuation.task_id == model.dispatch_task_id &&
    model.dispatch_task_id != "" {
    return ["in_progress", "submitted"].contains(model.dispatch_task_stage) &&
      model.dispatch_task_pending_action.is_empty() &&
      dispatch_continuation_reportable(model) &&
      (
        model.dispatch_task_stage != "submitted" ||
        !dispatch_report_matches_selection(model)
      )
  }
  model.dispatch_task_stage == "in_progress" &&
  model.dispatch_task_pending_action.is_empty() &&
  (match model.dispatch_run {
    Some(run) => run.state == "completed"
    None => false
  })
}

///|
fn dispatch_report_evidence(model : Model) -> Array[String] {
  if dispatch_json_text(model.dispatch_continuation.selected, "type") ==
    "human_revision" {
    return match dispatch_human_revision_selected(model) {
      Some(record) =>
        [dispatch_json_text(dispatch_json_field(record, "content"), "path")]
      None => []
    }
  }
  if dispatch_continuation_selected(model) is Some(record) {
    return dispatch_json_strings(record, "evidence_ids")
  }
  if dispatch_json_text(model.dispatch_continuation.selected, "type") ==
    "original" &&
    model.dispatch_continuation.source_verified {
    return model.dispatch_run.map(run => run.evidence_ids).unwrap_or([])
  }
  let refs : Array[String] = []
  for text in model.dispatch_task_evidence_id.split("\n") {
    let value = text.trim().to_owned()
    if !value.is_empty() && !refs.contains(value) {
      refs.push(value)
    }
  }
  match model.dispatch_run {
    Some(run) =>
      for reference in run.evidence_ids {
        if !refs.contains(reference) {
          refs.push(reference)
        }
      }
    None => ()
  }
  refs
}

///|
fn apply_dispatch_snapshot(model : Model, snapshot : DispatchSnapshot) -> Model {
  if model.dispatch_continuation.task_id == snapshot.task_id &&
    model.dispatch_continuation.actor == model.dispatch_task_actor_id &&
    model.dispatch_continuation.selection == model.dispatch_task_selection &&
    snapshot.revision < model.dispatch_continuation.revision {
    return model
  }
  let reports = snapshot.report_records.copy()
  if model.dispatch_continuation.task_id == snapshot.task_id &&
    model.dispatch_continuation.actor == model.dispatch_task_actor_id &&
    model.dispatch_continuation.selection == model.dispatch_task_selection {
    for report in model.dispatch_continuation.report_records {
      if !reports.any(existing => {
          dispatch_json_text(existing, "reportGuid") ==
          dispatch_json_text(report, "reportGuid")
        }) {
        reports.push(report)
      }
    }
  }
  let snapshot = { ..snapshot, report_records: reports, }
  let selected_report_id = if snapshot.state == "done" &&
    snapshot.accepted_report_id != "" {
    snapshot.accepted_report_id
  } else {
    model.dispatch_task_report_id
  }
  let selected_report = if model.dispatch_task_id == snapshot.task_id {
    snapshot.report_records
    .filter(report => {
      dispatch_json_text(report, "reportGuid") == selected_report_id
    })
    .get(0)
  } else {
    None
  }
  let state = if snapshot.state == "done" {
    "accepted"
  } else if !snapshot.report_id.is_empty() || !reports.is_empty() {
    "submitted"
  } else {
    snapshot.state
  }
  let refs = snapshot.evidence_ids.copy()
  match snapshot.run {
    Some(run) =>
      for reference in run.evidence_ids {
        if !refs.contains(reference) {
          refs.push(reference)
        }
      }
    None => ()
  }
  let next = {
    ..model,
    dispatch_task_id: snapshot.task_id,
    dispatch_offer_task: snapshot.offer_task,
    dispatch_task_product_id: snapshot.product_id,
    dispatch_report_product_id: snapshot.report_product_id,
    dispatch_task_open_id: snapshot.task_id,
    dispatch_task_title: snapshot.title,
    dispatch_task_acceptance: snapshot.acceptance,
    dispatch_task_source_context: snapshot.source_context,
    dispatch_task_commitment: snapshot.commitment,
    dispatch_journey_read_state: "loaded",
    dispatch_task_project_id: snapshot.project_id,
    dispatch_task_owner_id: snapshot.owner_id,
    dispatch_task_begin_date: snapshot.begin_date,
    dispatch_task_end_date: snapshot.end_date,
    dispatch_task_workspace: snapshot.workspace,
    dispatch_task_model: snapshot.model,
    dispatch_task_report_summary: selected_report
    .map(report => dispatch_json_text(report, "summary"))
    .unwrap_or(snapshot.report_summary),
    dispatch_task_report_id: selected_report
    .map(report => dispatch_json_text(report, "reportGuid"))
    .unwrap_or(snapshot.report_id),
    dispatch_task_evidence_id: refs.join("\n"),
    dispatch_task_stage: state,
    dispatch_run: snapshot.run,
    dispatch_task_pending_action: "",
    dispatch_task_blocked: false,
    dispatch_task_note: if state == "accepted" {
      "任务已明确接受。执行记录与报告仍可查看。"
    } else if state == "submitted" {
      "正式报告已提交；等待你检查结果并接受。"
    } else {
      dispatch_native_label(snapshot.run)
    },
  }
  dispatch_reply_after_snapshot(
    dispatch_offer_after_snapshot(
      dispatch_continuation_snapshot(next, snapshot),
    ),
  )
}

///|
fn dispatch_report_summary(model : Model) -> String {
  if dispatch_human_revision_selected(model) is Some(record) {
    return "人工修订 " +
      dispatch_json_text(record, "revision_id") +
      "：" +
      dispatch_json_text(dispatch_json_field(record, "output"), "path") +
      "。人工保存的不可变内容快照，交付结果见证据引用。"
  }
  if dispatch_continuation_selected(model) is Some(record) {
    return "人工后续执行 " +
      dispatch_json_text(record, "command_id") +
      "：" +
      dispatch_json_text(record, "summary")
  }
  match model.dispatch_run {
    Some(run) =>
      "原生执行 " +
      run.run_id +
      "：" +
      (if run.summary.is_empty() {
        "已完成，交付结果见证据引用。"
      } else {
        run.summary
      })
    None => "提交验收：" + model.dispatch_task_title
  }
}
