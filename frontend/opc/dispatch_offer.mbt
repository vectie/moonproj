///|
// Ordinary content and operation identity only. Authority is rebuilt at send.
#derive(Debug, Eq, ToJson, FromJson)
struct DispatchOfferDraft {
  task_id : String
  project_id : String
  value : Json
  base_revision : Int32
  state : String
  operation_key : String
  operation_offer : Json?
  operation_revision : Int32
  saved_revision : Int32
  note : String
}

///|
#derive(ToJson, FromJson)
struct DispatchOfferStore {
  version : Int32
  drafts : Array[DispatchOfferDraft]
}

///|
enum DispatchOfferMsg {
  Begin
  Edit(String, String)
  EditLocal(String, String)
  BeginLocal
  Save
  Recover
  Retry
  Rebase
  NewPlanning
  Export(Bool)
  ExportCanonical
  OfferStored(String, String, String, Bool)
  OfferRestored(String, String)
  Written(String, String, String, Int32, String)
  Read(String, String, String, Int32, String)
}

///|
fn dispatch_offer_empty() -> Json {
  {
    "schema": "moonproj.offer-draft.v1",
    "title": "",
    "state": "draft",
    "demand_state": "unproven",
    "deliverables": [],
    "acceptance_criteria": [],
  }
}

///|
fn dispatch_offer_revision(value : Json) -> Int32 {
  match dispatch_json_field(value, "revision") {
    Number(number, ..) if number > 0.0 &&
      number <= 2147483647.0 &&
      number.trunc() == number => number.to_int()
    _ => 0
  }
}

///|
// A reply-only update advances the task snapshot, not the saved proposal.
fn dispatch_offer_canonical_revision(model : Model) -> Int32 {
  if dispatch_json_text(model.dispatch_task_commitment, "task_id") !=
    model.dispatch_task_id {
    return 0
  }
  let canonical = @task_evidence.normalize_offer_draft(
    dispatch_json_field(model.dispatch_offer_task, "offer_draft"),
  ) catch {
    _ => return 0
  }
  let mut latest = 0
  for
    entry in dispatch_continuation_array(
      model.dispatch_task_commitment,
      "offer_history",
    ) {
    let revision = dispatch_offer_revision(entry)
    let value = @task_evidence.normalize_offer_draft(
      dispatch_json_field(entry, "offer_draft"),
    ) catch {
      _ => continue
    }
    if dispatch_json_text(entry, "audit_state") == "available" &&
      revision > latest &&
      revision <= dispatch_offer_revision(model.dispatch_offer_task) &&
      value == canonical {
      latest = revision
    }
  }
  latest
}

///|
fn dispatch_offer_eligible(model : Model) -> Bool {
  let task = model.dispatch_offer_task
  !model.dispatch_task_actor_id.is_empty() &&
  dispatch_json_text(task, "taskGuid") == model.dispatch_task_id &&
  dispatch_json_text(task, "created_by") == model.dispatch_task_actor_id &&
  dispatch_json_text(task, "sourceKind") == "command" &&
  dispatch_json_text(task, "taskType") == "task" &&
  dispatch_json_text(task, "status") == "pending" &&
  model.dispatch_task_stage == "pending" &&
  model.dispatch_run is None &&
  dispatch_json_field(task, "execution") is Null &&
  dispatch_continuation_array(task, "continuations").is_empty() &&
  dispatch_continuation_array(task, "human_revisions").is_empty() &&
  dispatch_json_field(task, "selected_delivery_source") is Null &&
  dispatch_json_field(task, "accepted_delivery_source") is Null &&
  dispatch_json_text(task, "accepted_report_id").is_empty() &&
  model.dispatch_task_report_id.is_empty() &&
  model.dispatch_continuation.report_records.is_empty() &&
  dispatch_offer_revision(task) > 0 &&
  model.dispatch_task_pending_action.is_empty()
}

///|
fn dispatch_offer_find(model : Model, task_id : String) -> DispatchOfferDraft? {
  model.dispatch_offer_drafts.filter(item => item.task_id == task_id).get(0)
}

///|
fn dispatch_offer_seed(model : Model) -> DispatchOfferDraft {
  let canonical = dispatch_json_field(model.dispatch_offer_task, "offer_draft")
  {
    task_id: model.dispatch_task_id,
    project_id: model.dispatch_task_project_id,
    value: if canonical is Null {
      dispatch_offer_empty()
    } else {
      canonical
    },
    base_revision: dispatch_offer_revision(model.dispatch_offer_task),
    state: "editing",
    operation_key: "",
    operation_offer: None,
    operation_revision: 0,
    saved_revision: 0,
    note: "本地未保存修改；正式任务尚未更改。",
  }
}

///|
fn dispatch_offer_put(model : Model, draft : DispatchOfferDraft) -> Model {
  let drafts = model.dispatch_offer_drafts.filter(item => {
    item.task_id != draft.task_id
  })
  drafts.push(draft)
  let next = { ..model, dispatch_offer_drafts: drafts, }
  if draft.task_id == model.dispatch_task_id &&
    !["saving", "sending", "recovering"].contains(draft.state) {
    dispatch_offer_unlock(next, draft.task_id)
  } else {
    next
  }
}

///|
fn dispatch_offer_changed(
  emit : @rabbita.Emit[Msg],
  model : Model,
  draft : DispatchOfferDraft,
) -> (Cmd, Model) {
  let next = dispatch_offer_put(model, draft)
  (dispatch_offer_persist(emit, next, "", ""), next)
}

///|
fn dispatch_offer_editable(draft : DispatchOfferDraft) -> Bool {
  ["editing", "saved"].contains(draft.state)
}

///|
fn dispatch_offer_edit(value : Json, field : String, text : String) -> Json {
  let fields : Map[String, Json] = Map([])
  if value is Object(old) {
    for key, item in old {
      fields[key] = item
    }
  }
  if ["deliverables", "acceptance_criteria"].contains(field) {
    fields[field] = Json::array(
      text.split("\n").map(line => Json::string(line.to_owned())).collect(),
    )
  } else if [
      "title", "buyer", "buyer_reference", "problem", "problem_observed_on", "scope",
      "exclusions", "price_amount", "price_currency", "price_basis", "timing", "dependencies",
      "proof_sought", "closure_reason",
    ].contains(field) {
    fields[field] = Json::string(text)
  } else if field == "state" && ["draft", "closed"].contains(text) {
    fields[field] = Json::string(text)
  }
  Json::object(fields)
}

///|
fn dispatch_offer_value_text(value : Json, field : String) -> String {
  if ["deliverables", "acceptance_criteria"].contains(field) {
    dispatch_continuation_array(value, field)
    .map(item => {
      match item {
        String(text) => text
        _ => ""
      }
    })
    .join("\n")
  } else {
    dispatch_json_text(value, field)
  }
}

///|
fn dispatch_offer_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchOfferMsg,
) -> (Cmd, Model) {
  match action {
    BeginLocal | EditLocal(_, _) => {
      guard dispatch_active_draft(model) is Some(draft) &&
        draft.state == "editing" else {
        return (none, model)
      }
      let value = draft.offer_draft.unwrap_or(dispatch_offer_empty())
      let value = match action {
        EditLocal(field, text) => dispatch_offer_edit(value, field, text)
        _ => value
      }
      dispatch_save_draft(emit, model, { ..draft, offer_draft: Some(value), })
    }
    Begin => {
      if !dispatch_offer_eligible(model) {
        return (none, model)
      }
      if dispatch_offer_find(model, model.dispatch_task_id) is Some(_) {
        return (none, model)
      }
      dispatch_offer_changed(emit, model, dispatch_offer_seed(model))
    }
    Edit(field, text) => {
      guard dispatch_offer_find(model, model.dispatch_task_id) is Some(draft) else {
        return (none, model)
      }
      if !dispatch_offer_eligible(model) || !dispatch_offer_editable(draft) {
        return (none, model)
      }
      dispatch_offer_changed(emit, model, {
        ..draft,
        value: dispatch_offer_edit(draft.value, field, text),
        state: "editing",
        operation_key: "",
        operation_offer: None,
        operation_revision: 0,
        note: "本地未保存修改；正式任务尚未更改。",
      })
    }
    Save => {
      guard dispatch_offer_find(model, model.dispatch_task_id) is Some(draft) else {
        return (none, model)
      }
      if !dispatch_offer_eligible(model) || !dispatch_offer_editable(draft) {
        return (none, model)
      }
      if draft.base_revision !=
        dispatch_offer_revision(model.dispatch_offer_task) {
        return dispatch_offer_changed(emit, model, {
          ..draft,
          state: "conflict",
          note: "正式任务版本已改变。本地内容保留，请核对正式方案后明确使用新版本。",
        })
      }
      let value = @task_evidence.normalize_offer_draft(draft.value) catch {
        @task_evidence.InvalidOfferDraft(error) =>
          return dispatch_offer_changed(emit, model, { ..draft, note: error, })
      }
      let frozen = {
        ..draft,
        state: "saving",
        operation_key: "opc-offer-" + dispatch_command_nonce(),
        operation_offer: Some(value),
        operation_revision: draft.base_revision,
        note: "先保留此次方案与版本，再保存到正式任务。",
      }
      let next = dispatch_offer_put(
        { ..model, dispatch_task_pending_action: "offer", },
        frozen,
      )
      (
        dispatch_offer_persist(emit, next, frozen.task_id, frozen.operation_key),
        next,
      )
    }
    OfferStored(actor, task, key, ok) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let next = {
        ..model,
        dispatch_offer_storage: if ok {
          "已保存到此浏览器"
        } else {
          "浏览器保存失败；请保留当前页面"
        },
      }
      if key.is_empty() {
        return (none, next)
      }
      guard dispatch_offer_find(next, task) is Some(draft) &&
        draft.operation_key == key &&
        draft.state == "saving" else {
        return (none, next)
      }
      if !ok {
        return (
          none,
          dispatch_offer_put(dispatch_offer_unlock(next, task), {
            ..draft,
            state: "uncertain",
            note: "本地保存失败，本次没有发送；保留同一请求，可恢复或重试。",
          }),
        )
      }
      (
        dispatch_offer_write(emit, actor, draft),
        dispatch_offer_put(next, {
          ..draft,
          state: "sending",
          note: "正在保存；等待正式记录与审计收据。",
        }),
      )
    }
    Written(actor, task, key, _, _) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      guard dispatch_offer_find(model, task) is Some(draft) &&
        draft.operation_key == key &&
        draft.state == "sending" else {
        return (none, model)
      }
      let next = dispatch_offer_put(model, {
        ..draft,
        state: "recovering",
        note: "正在读回正式任务，核对此次保存。",
      })
      (dispatch_offer_read(emit, actor, draft), next)
    }
    Recover | Retry => {
      guard dispatch_offer_find(model, model.dispatch_task_id) is Some(draft) &&
        !draft.operation_key.is_empty() &&
        draft.operation_offer is Some(_) else {
        return (none, model)
      }
      if !["uncertain", "conflict"].contains(draft.state) {
        return (none, model)
      }
      if action is Retry {
        if draft.state == "conflict" || !dispatch_offer_eligible(model) {
          return (none, model)
        }
        let next = dispatch_offer_put(
          { ..model, dispatch_task_pending_action: "offer", },
          {
            ..draft,
            state: "saving",
            note: "仅重试已保留的相同方案、版本和请求身份。",
          },
        )
        (
          dispatch_offer_persist(emit, next, draft.task_id, draft.operation_key),
          next,
        )
      } else {
        (
          dispatch_offer_read(emit, model.dispatch_task_actor_id, draft),
          dispatch_offer_put(model, {
            ..draft,
            state: "recovering",
            note: "正在恢复此次保存的正式记录。",
          }),
        )
      }
    }
    Read(actor, task, key, status, body) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      guard dispatch_offer_find(model, task) is Some(draft) &&
        draft.operation_key == key &&
        draft.state == "recovering" else {
        return (none, model)
      }
      guard status == 200 &&
        dispatch_decode_snapshot(body, task) is Some(snapshot) &&
        snapshot.project_id == draft.project_id &&
        dispatch_offer_revision(snapshot.offer_task) > 0 else {
        return dispatch_offer_changed(
          emit,
          dispatch_offer_unlock(model, task),
          {
            ..draft,
            state: "uncertain",
            note: "保存结果尚未确认。保留原请求，请恢复记录或明确重试同一请求。",
          },
        )
      }
      let revision = dispatch_offer_revision(snapshot.offer_task)
      let matched = dispatch_offer_receipt_revision(snapshot.commitment, draft)
      let next = if model.dispatch_task_id == task &&
        ["", "offer", "load"].contains(model.dispatch_task_pending_action) {
        apply_dispatch_snapshot(model, snapshot)
      } else {
        model
      }
      let latest = if next.dispatch_task_id == task {
        Int32::max(revision, dispatch_offer_revision(next.dispatch_offer_task))
      } else {
        revision
      }
      if matched > 0 && matched <= revision {
        dispatch_offer_changed(emit, next, {
          ..draft,
          state: if matched == latest {
            "saved"
          } else {
            "historical"
          },
          value: draft.operation_offer.unwrap(),
          base_revision: latest,
          saved_revision: matched,
          note: if matched == latest {
            "已保存到正式任务，审计收据已核对。"
          } else {
            "此次方案已保存为历史版本；正式任务已有更新版本。请核对后再编辑。"
          },
        })
      } else if revision != draft.operation_revision {
        dispatch_offer_changed(emit, next, {
          ..draft,
          state: "conflict",
          note: "未找到可确认此次保存的审计收据，正式任务版本已改变。本地方案仍保留。",
        })
      } else {
        dispatch_offer_changed(emit, next, {
          ..draft,
          state: "uncertain",
          note: "尚无此次保存的可核对收据；可以恢复记录，或明确重试完全相同的请求。",
        })
      }
    }
    Rebase => {
      guard dispatch_offer_find(model, model.dispatch_task_id) is Some(draft) else {
        return (none, model)
      }
      if !dispatch_offer_eligible(model) ||
        !["conflict", "saved", "historical", "editing"].contains(draft.state) {
        return (none, model)
      }
      dispatch_offer_changed(emit, model, {
        ..draft,
        state: "editing",
        base_revision: dispatch_offer_revision(model.dispatch_offer_task),
        operation_key: "",
        operation_offer: None,
        operation_revision: 0,
        note: "已明确以当前正式版本为基础；本地内容保留，仍需点击保存。",
      })
    }
    OfferRestored(actor, text) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let store : DispatchOfferStore = @json.from_json(@json.parse(text)) catch {
        _ =>
          return (
            none,
            {
              ..model,
              dispatch_offer_storage: if text.is_empty() {
                "已读取此浏览器草稿"
              } else {
                "方案草稿无法读取，未覆盖当前编辑"
              },
            },
          )
      }
      if store.version != 1 {
        return (none, model)
      }
      let mut next = model
      for draft in store.drafts {
        if !draft.task_id.is_empty() &&
          !draft.project_id.is_empty() &&
          dispatch_offer_find(next, draft.task_id) is None {
          let restored = if ["saving", "sending", "recovering"].contains(
              draft.state,
            ) {
            {
              ..draft,
              state: "uncertain",
              note: "页面曾中断；先恢复同一任务的正式保存记录。",
            }
          } else {
            draft
          }
          next = dispatch_offer_put(next, restored)
        }
      }
      (none, { ..next, dispatch_offer_storage: "已读取此浏览器草稿", })
    }
    NewPlanning => {
      let (_, next) = dispatch_prepare_draft(
        emit,
        model,
        "",
        model.dispatch_task_project_id,
        None,
        true,
      )
      let draft = dispatch_active_draft(next).unwrap()
      let reference = "MoonProj task " +
        model.dispatch_task_id +
        (if model.dispatch_task_product_id.is_empty() {
          ""
        } else {
          " · product " + model.dispatch_task_product_id
        })
      dispatch_save_draft(emit, next, {
        ..draft,
        offer_draft: Some(dispatch_offer_empty()),
        source_reference: Some(reference),
      })
    }
    Export(is_local) => dispatch_offer_export(emit, model, is_local)
    ExportCanonical => {
      let (command, exported) = dispatch_offer_export(
        emit,
        { ..model, dispatch_offer_drafts: [], },
        false,
      )
      (command, { ..model, notice: exported.notice, })
    }
  }
}

///|
// A late ordinary task refresh must not reopen actions during an offer save.
fn dispatch_offer_after_snapshot(model : Model) -> Model {
  match dispatch_offer_find(model, model.dispatch_task_id) {
    Some(draft) if ["saving", "sending", "recovering"].contains(draft.state) =>
      { ..model, dispatch_task_pending_action: "offer", }
    _ => model
  }
}

///|
fn dispatch_offer_receipt_revision(
  commitment : Json,
  draft : DispatchOfferDraft,
) -> Int32 {
  if dispatch_json_text(commitment, "task_id") != draft.task_id {
    return 0
  }
  guard draft.operation_offer is Some(expected) else { return 0 }
  for entry in dispatch_continuation_array(commitment, "offer_history") {
    let revision = dispatch_offer_revision(entry)
    let value = @task_evidence.normalize_offer_draft(
      dispatch_json_field(entry, "offer_draft"),
    ) catch {
      _ => continue
    }
    if dispatch_json_text(entry, "idempotency_key") == draft.operation_key &&
      dispatch_json_text(entry, "audit_state") == "available" &&
      !dispatch_json_text(entry, "event_id").is_empty() &&
      !dispatch_json_text(entry, "audit_id").is_empty() &&
      revision == draft.operation_revision + 1 &&
      value == expected {
      return revision
    }
  }
  0
}

///|
fn dispatch_offer_unlock(model : Model, task : String) -> Model {
  if model.dispatch_task_id == task &&
    model.dispatch_task_pending_action == "offer" {
    { ..model, dispatch_task_pending_action: "", }
  } else {
    model
  }
}
