///|
fn dispatch_outcome_decode(
  source : Json,
  draft : Json,
  text : String,
) -> Result[Json, String] {
  let value = @json.parse(text) catch {
    _ => return Err("无法读取结果预览；草稿仍保留。")
  }
  if value is { "error": String(error), .. } {
    return Err(error)
  }
  guard value
    is {
      "contract_version": "moonproj.outcome-export.v1",
      "handoff": actual_source,
      "draft": actual_draft,
      "submission": Object(_),
      "evidence_bundle": Object(_),
      ..
    } &&
    actual_source == source &&
    actual_draft == draft else {
    return Err(
      "返回内容与此次捕获来源或草稿不一致；请重新准备来源后预览。",
    )
  }
  if !dispatch_outcome_submission_matches(value, source, draft) {
    return Err(
      "完整结果或证据文件没有保留此次观察、缺口判断和准确来源；请重试。",
    )
  }
  for
    (name, key) in [
      ("submission", "submission"),
      ("handoff", "handoff"),
      ("evidence", "evidence_bundle"),
    ] {
    let serialized = dispatch_json_text(value, name + "_json")
    let decoded = @json.parse(serialized) catch {
      _ => return Err("下载文件缺失或无法读取；请重试预览。")
    }
    let filename = dispatch_json_text(value, name + "_filename")
    if decoded != dispatch_json_field(value, key) ||
      !filename.has_suffix(".json") ||
      filename.contains("/") ||
      filename.contains("\\") ||
      filename.contains("..") {
      return Err("下载文件与预览不一致；尚未准备导出。")
    }
  }
  Ok(value)
}

///|
fn dispatch_outcome_submission_matches(
  value : Json,
  source : Json,
  draft : Json,
) -> Bool {
  let submission = dispatch_json_field(value, "submission")
  guard submission is Object(fields) &&
    dispatch_json_text(submission, "contract_version") ==
    "moonbook.bookkeeper.product_outcome_submission.v1" &&
    dispatch_json_text(submission, "source_product") == "moonproj" else {
    return false
  }
  let task_snapshot = @json.parse(dispatch_json_text(source, "task_snapshot")) catch {
    _ => return false
  }
  let report_snapshot = @json.parse(
    dispatch_json_text(source, "report_snapshot"),
  ) catch {
    _ => return false
  }
  let title = dispatch_json_text(task_snapshot, "title")
  let report_summary = dispatch_json_text(
    dispatch_json_field(report_snapshot, "report"),
    "summary",
  )
  if title.trim().is_empty() ||
    report_summary.trim().is_empty() ||
    dispatch_json_text(submission, "deliverable_title") != title ||
    dispatch_json_text(submission, "deliverable_summary") != report_summary {
    return false
  }
  for key in ["task", "report"] {
    let reference = dispatch_json_field(source, key)
    if !dispatch_outcome_digest_shape(
        dispatch_json_text(reference, "record_digest"),
      ) {
      return false
    }
  }
  let evidence = dispatch_json_field(value, "evidence_bundle")
  let basis_text = dispatch_json_text(evidence, "digest_basis")
  let basis = @json.parse(basis_text) catch { _ => return false }
  let expected_basis : Json = {
    "contract_version": "moonproj.outcome-authoring.v1",
    "handoff": source,
    "draft": draft,
  }
  if basis != expected_basis {
    return false
  }
  for
    key in [
      "outcome_summary", "observed_at", "recorded_at", "information_gap", "recognition_gap",
      "decisiveness_gap", "owner_route",
    ] {
    if dispatch_json_field(submission, key) != dispatch_json_field(draft, key) {
      return false
    }
  }
  let reference = dispatch_json_field(submission, "submission")
  let identity = dispatch_json_text(reference, "record_id")
  let digest = dispatch_json_text(reference, "record_digest")
  if !dispatch_outcome_digest_shape(digest) ||
    identity != "moonproj-outcome-" + digest[7:].to_owned() ||
    dispatch_json_text(reference, "record_version") != "1" ||
    dispatch_json_text(value, "submission_filename") != identity + ".json" ||
    dispatch_json_text(value, "handoff_filename") != identity + "-handoff.json" ||
    dispatch_json_text(value, "evidence_filename") !=
    identity + "-evidence.json" {
    return false
  }
  let task_id = dispatch_json_text(
    dispatch_json_field(source, "task"),
    "record_id",
  )
  if dispatch_json_text(submission, "decision_evidence_id") != task_id {
    return false
  }
  let expected_refs : Array[Json] = ["task", "report"].map(key => {
    let item = dispatch_json_field(source, key)
    {
      "reference_id": dispatch_json_field(item, "record_id"),
      "reference_version": dispatch_json_field(item, "record_version"),
      "digest": dispatch_json_field(item, "record_digest"),
      "provenance_ref": identity + "-handoff.json#/" + key + "_snapshot",
    }
  })
  if dispatch_json_field(submission, "evidence_refs") != Json::array(expected_refs) {
    return false
  }
  let capability = dispatch_json_field(draft, "capability")
  if capability is Null {
    if [
        "capability_id", "capability_version", "capability_summary", "capability_change_digest",
      ].any(key => fields.contains(key)) {
      return false
    }
  } else {
    for key in ["id", "version", "summary"] {
      if dispatch_json_field(submission, "capability_" + key) !=
        dispatch_json_field(capability, key) {
        return false
      }
    }
    if !dispatch_outcome_digest_shape(
        dispatch_json_text(submission, "capability_change_digest"),
      ) {
      return false
    }
  }
  dispatch_json_text(evidence, "contract_version") ==
  "moonproj.outcome-evidence.v1" &&
  dispatch_json_field(evidence, "handoff") == source &&
  dispatch_json_field(evidence, "draft") == draft &&
  dispatch_json_field(evidence, "submission") == reference &&
  dispatch_json_field(evidence, "authorizing") == Json::boolean(false) &&
  dispatch_json_text(evidence, "customer_acceptance") == "not_asserted" &&
  dispatch_json_text(evidence, "cash") == "not_asserted"
}

///|
fn dispatch_outcome_digest_shape(value : String) -> Bool {
  if !value.has_prefix("sha256:") || value.length() != 71 {
    return false
  }
  for character in value[7:] {
    if !(character is ('0'..='9' | 'a'..='f')) {
      return false
    }
  }
  true
}

///|
fn dispatch_outcome_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  source : Json,
  action : DispatchOutcomeMsg,
) -> (Cmd, Model) {
  guard dispatch_lesson_current(model) &&
    model.dispatch_lesson_handoff.payload == Some(source) else {
    return (none, model)
  }
  let draft = dispatch_outcome_draft(model, source)
  match action {
    Edit(field, value) => {
      let previous = match field {
        "summary" => draft.outcome_summary
        "observed_at" => draft.observed_at
        "capability_id" => draft.capability_id
        "capability_version" => draft.capability_version
        "capability_summary" => draft.capability_summary
        "change_text" => draft.change_text
        _ => return (none, model)
      }
      if previous == value {
        return (none, model)
      }
      let next = match field {
        "summary" => { ..draft, outcome_summary: value, }
        "observed_at" => { ..draft, observed_at: value, }
        "capability_id" => { ..draft, capability_id: value, }
        "capability_version" => { ..draft, capability_version: value, }
        "capability_summary" => { ..draft, capability_summary: value, }
        _ => { ..draft, change_text: value, }
      }
      (none, dispatch_outcome_changed(model, next))
    }
    GapEdit(index, field, value) => {
      guard draft.gaps.get(index) is Some(gap) else { return (none, model) }
      let next = match field {
        "choice" if ["", "absent", "present"].contains(value) =>
          { ..gap, choice: value, }
        "summary" => { ..gap, summary: value, }
        "severity" => { ..gap, severity: value, }
        _ => return (none, model)
      }
      if next == gap {
        return (none, model)
      }
      let gaps = draft.gaps.copy()
      gaps[index] = next
      (none, dispatch_outcome_changed(model, { ..draft, gaps, }))
    }
    Evidence(index, id) => {
      guard draft.gaps.get(index) is Some(gap) &&
        dispatch_outcome_evidence(source).contains(id) else {
        return (none, model)
      }
      let evidence_refs = if gap.evidence_refs.contains(id) {
        gap.evidence_refs.filter(item => item != id)
      } else {
        // Stable source order, independent of the order boxes were clicked.
        dispatch_outcome_evidence(source).filter(item => {
          item == id || gap.evidence_refs.contains(item)
        })
      }
      let gaps = draft.gaps.copy()
      gaps[index] = { ..gap, evidence_refs, }
      (none, dispatch_outcome_changed(model, { ..draft, gaps, }))
    }
    Preview => {
      if draft.pending &&
        draft.pending_selection == model.dispatch_task_selection {
        return (none, model)
      }
      let problem = dispatch_outcome_validation(draft)
      if !problem.is_empty() {
        return (
          none,
          dispatch_outcome_store(model, { ..draft, notice: problem, }),
        )
      }
      let request = model.dispatch_outcome_sequence + 1
      let frozen = {
        ..draft,
        recorded_at: if draft.recorded_at == 0 {
          dispatch_outcome_now()
        } else {
          draft.recorded_at
        },
        request,
        pending_selection: model.dispatch_task_selection,
        pending: true,
        prepared: None,
        notice: "正在重新核对正式任务与报告，并准备完整结果文件…",
      }
      let draft_json = dispatch_outcome_draft_json(frozen)
      let task = model.dispatch_task_id
      let selection = model.dispatch_task_selection
      let command = @http.post(
          "/api/company/tasks/" + dispatch_url_encode(task) + "/outcome-export",
        )
        .with_json({ "handoff": source, "draft": draft_json })
        .expect_text(result => {
          emit(
            OutcomeAction(
              source,
              Loaded(
                task,
                selection,
                request,
                draft_json,
                match result {
                  Ok(text) => Ok(text)
                  Err(error) => Err(error.to_string())
                },
              ),
            ),
          )
        })
      (
        command,
        dispatch_outcome_store(
          { ..model, dispatch_outcome_sequence: request, },
          frozen,
        ),
      )
    }
    Loaded(task, selection, request, expected, result) => {
      if task != model.dispatch_task_id ||
        selection != model.dispatch_task_selection ||
        !draft.pending ||
        draft.pending_selection != selection ||
        draft.request != request ||
        dispatch_outcome_draft_json(draft) != expected {
        return (none, model)
      }
      let checked = match result {
        Ok(text) => dispatch_outcome_decode(source, expected, text)
        Err(error) => Err(error)
      }
      (
        none,
        dispatch_outcome_store(model, {
          ..draft,
          pending: false,
          prepared: match checked {
            Ok(value) => Some(value)
            Err(_) => None
          },
          notice: match checked {
            Ok(_) =>
              "完整结果已准备。请下载结果、来源交接和证据三个文件，一同保留；之后在 Book 导入结果并按其审核流程继续。"
            Err(error) =>
              "预览未完成：" +
              error +
              " 草稿仍保留；若来源已变化，请重新准备来源。"
          },
        }),
      )
    }
    Download(kind) => {
      guard !draft.pending &&
        ["submission", "handoff", "evidence"].contains(kind) &&
        draft.prepared is Some(prepared) else {
        return (none, model)
      }
      let bytes = dispatch_json_text(prepared, kind + "_json")
      let filename = dispatch_json_text(prepared, kind + "_filename")
      (@cmd.custom_cmd(_ => dispatch_outcome_download(bytes, filename)), model)
    }
  }
}

///|
extern "js" fn dispatch_outcome_download(text : String, filename : String) =
  #| (text,filename) => { const blob=new Blob([text],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000); }
