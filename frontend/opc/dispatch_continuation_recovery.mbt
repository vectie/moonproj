///|
fn dispatch_selection_target(body : Json) -> Json {
  let original = dispatch_json_field(body, "selected_delivery_source")
  if dispatch_json_text(original, "type") == "original" {
    original
  } else if dispatch_json_text(body, "human_revision_id") != "" {
    {
      "type": "human_revision",
      "original_run_id": dispatch_json_text(body, "original_run_id"),
      "revision_id": dispatch_json_text(body, "human_revision_id"),
    }
  } else {
    {
      "type": "continuation",
      "original_run_id": dispatch_json_text(body, "original_run_id"),
      "continuation_id": dispatch_json_text(body, "continuation_id"),
      "command_id": dispatch_json_text(body, "command_id"),
    }
  }
}

///|
fn dispatch_selection_matches(body : Json, selected : Json) -> Bool {
  !(body is Null) && dispatch_selection_target(body) == selected
}

///|
fn dispatch_selection_ack_state(
  model : Model,
  response : String,
) -> DispatchContinuationState? {
  let json = @json.parse(response) catch { _ => Json::null() }
  let task = dispatch_json_field(json, "task")
  let execution = dispatch_json_field(task, "execution")
  guard model.dispatch_run is Some(run) else { return None }
  if dispatch_json_text(json, "schema") != "moonproj.task-continuations.v1" ||
    dispatch_json_text(json, "task_id") != model.dispatch_task_id ||
    dispatch_json_text(task, "taskGuid") != model.dispatch_task_id ||
    dispatch_json_text(execution, "run_id") != run.run_id ||
    dispatch_json_text(execution, "command_id") != run.command_id ||
    dispatch_json_text(execution, "session_id") != run.session_id ||
    !(dispatch_json_field(json, "idempotent_replay") is True ||
    dispatch_json_field(json, "idempotent_replay") is False) {
    return None
  }
  let applied = dispatch_json_field(json, "operation_applied") is True &&
    dispatch_json_text(json, "operation_idempotency_key") ==
    dispatch_json_text(model.dispatch_continuation.operation, "idempotency_key") &&
    dispatch_json_field(json, "operation_source") ==
    dispatch_selection_target(model.dispatch_continuation.operation)
  if !applied &&
    !(dispatch_json_field(json, "inspection_only") is True &&
    dispatch_json_text(json, "acceptance") == "accepted") {
    return None
  }
  let envelope : Json = {
    "schema": "moonproj.task-continuations.v1",
    "task_id": model.dispatch_task_id,
    "original_run_id": run.run_id,
    "session_id": run.session_id,
    "original_command_id": run.command_id,
    "workspace": run.workspace,
    "revision": dispatch_json_field(json, "revision"),
    "acceptance": dispatch_json_field(json, "acceptance"),
    "continuations": dispatch_json_field(json, "continuations"),
    "human_revisions": dispatch_json_field(json, "human_revisions"),
    "selected_delivery_source": dispatch_json_field(
      json, "selected_delivery_source",
    ),
    "candidate": Json::null(),
  }
  match
    dispatch_continuation_decode(
      model,
      {
        ..model.dispatch_continuation,
        preview_command: "",
        preview_revision: "",
      },
      envelope.stringify(),
    ) {
    Ok(next) =>
      Some({
        ..next,
        operation_pending: false,
        preview_command: model.dispatch_continuation.preview_command,
        preview_revision: model.dispatch_continuation.preview_revision,
        candidate: model.dispatch_continuation.candidate,
        human_revision_candidate: model.dispatch_continuation.human_revision_candidate,
        human_revision_content: model.dispatch_continuation.human_revision_content,
      })
    Err(_) => None
  }
}

///|
fn dispatch_selection_same_target(left : Json, right : Json) -> Bool {
  dispatch_selection_target(left) == dispatch_selection_target(right)
}

///|
fn dispatch_selection_key(model : Model) -> String {
  "moonproj.result-selection.v1:" +
  ToJson::to_json([
    model.dispatch_task_actor_id,
    model.dispatch_task_id,
    model.dispatch_run.map(run => run.run_id).unwrap_or(""),
  ]).stringify()
}

///|
fn dispatch_selection_restore(model : Model) -> Json {
  let saved = @json.parse(
    dispatch_selection_read(dispatch_selection_key(model)),
  ) catch {
    _ => Json::null()
  }
  let body = dispatch_json_field(saved, "body")
  guard model.dispatch_run is Some(run) else { return Json::null() }
  if dispatch_json_text(body, "original_run_id") != run.run_id ||
    dispatch_json_text(body, "idempotency_key") == "" ||
    dispatch_json_text(dispatch_json_field(body, "authority"), "actor_id") !=
    model.dispatch_task_actor_id {
    return Json::null()
  }
  // Only bounded selection fields are restored; never arbitrary stored headers,
  // service credentials, native requests or report content.
  let fields : Map[String, Json] = Map([])
  for
    key in [
      "idempotency_key", "original_run_id", "continuation_id", "command_id", "selected_delivery_source",
      "select_for_delivery", "human_revision_id",
    ] {
    let value = dispatch_json_field(body, key)
    if !(value is Null) {
      fields[key] = value
    }
  }
  fields["authority"] = dispatch_task_authority(model, "project:task:update")
  {
    "body": Json::object(fields),
    "pending": dispatch_json_field(saved, "pending"),
  }
}

///|
fn dispatch_continuation_snapshot(
  model : Model,
  snapshot : DispatchSnapshot,
) -> Model {
  let state = model.dispatch_continuation
  let chosen = snapshot.report_records
    .filter(report => {
      dispatch_json_text(report, "reportGuid") == model.dispatch_task_report_id
    })
    .get(0)
  let report_source = chosen
    .map(report => dispatch_json_field(report, "delivery_source"))
    .unwrap_or(Json::null())
  if state.source_verified &&
    state.task_id == model.dispatch_task_id &&
    state.selection == model.dispatch_task_selection &&
    state.actor == model.dispatch_task_actor_id &&
    snapshot.revision < state.revision {
    return model
  }
  let records = snapshot.continuation_records.filter(record => {
    dispatch_continuation_valid(model, record)
  })
  let human_revisions = snapshot.human_revision_records.filter(record => {
    dispatch_human_revision_valid(model, record)
  })
  let selected = snapshot.delivery_source
  let valid = dispatch_delivery_source_valid(
    model, selected, records, human_revisions,
  )
  {
    ..model,
    dispatch_continuation: {
      ..state,
      task_id: model.dispatch_task_id,
      selection: model.dispatch_task_selection,
      actor: model.dispatch_task_actor_id,
      records,
      human_revisions,
      human_revision_candidate: Json::null(),
      human_revision_content: "",
      selected,
      report_records: snapshot.report_records,
      report_source,
      revision: snapshot.revision,
      accepted_report_id: snapshot.accepted_report_id,
      accepted_delivery_source: snapshot.accepted_delivery_source,
      source_verified: valid,
      accepted: dispatch_task_inspection_only(model),
      phase: if ["saving", "attaching", "recovering"].contains(state.phase) {
        state.phase
      } else {
        "idle"
      },
      error: if valid {
        ""
      } else {
        "正式任务的交付来源无法验证，请刷新记录。"
      },
    },
  }
}

///|
fn dispatch_continuation_revision(json : Json) -> Double {
  match dispatch_json_field(json, "revision") {
    Number(value, ..) if value >= 0.0 && value.trunc() == value => value
    _ => 0.0
  }
}

///|
#cfg(target="js")
extern "js" fn dispatch_selection_read(key : String) -> String =
  #| key => { try { return globalThis.localStorage?.getItem(key) || 'null'; } catch (_) { return 'null'; } }

///|
#cfg(target="js")
extern "js" fn dispatch_selection_store(
  key : String,
  body : String,
  pending : Bool,
) -> Bool =
  #| (key, body, pending) => { try { if (!globalThis.localStorage) return false; const value = JSON.stringify({schema:'moonproj.result-selection.v1',body:JSON.parse(body),pending}); globalThis.localStorage.setItem(key,value); return globalThis.localStorage.getItem(key) === value; } catch (_) { return false; } }
