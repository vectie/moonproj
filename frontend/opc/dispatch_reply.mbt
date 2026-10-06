///|
// Private working content stays in this tab, never in ordinary task projections.
struct DispatchReplyDraft {
  task_id : String
  project_id : String
  value : Json
  base_revision : Int
  state : String
  operation_key : String
  operation_reply : Json?
  operation_revision : Int
  saved_revision : Int
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct DispatchReplyStore {
  version : Int
  drafts : Array[DispatchReplyDraft]
} derive(ToJson, FromJson)

///|
enum DispatchReplyMsg {
  Scoped(Int, DispatchReplyMsg)
  StorageStatus(String, String)
  Begin
  Correct(String)
  Edit(String, String)
  Save
  Recover
  Retry
  Rebase
  Discard
  ReplyStored(String, String, String, Bool)
  ReplyRestored(String, String)
  Written(String, String, String, Int, String)
  Read(String, String, String, Int, String)
}

///|
fn dispatch_reply_number(value : Json, field : String) -> Int {
  dispatch_offer_revision({ "revision": dispatch_json_field(value, field) })
}

///|
fn dispatch_reply_empty() -> Json {
  {
    "schema": "moonproj.offer-reply.v1",
    "offer_revision": Json::null(),
    "respondent": Json::null(),
    "received_at": Json::null(),
    "summary": "",
    "kind": "",
    "evidence_kind": "",
    "source_reference": Json::null(),
    "supersedes_reply_id": Json::null(),
    "correction_reason": Json::null(),
  }
}

///|
fn dispatch_reply_offers(model : Model) -> Array[Json] {
  if dispatch_json_text(model.dispatch_task_commitment, "task_id") !=
    model.dispatch_task_id {
    return []
  }
  dispatch_continuation_array(model.dispatch_task_commitment, "offer_history").filter(entry => {
      let revision = dispatch_offer_revision(entry)
      revision > 0 &&
      revision <= dispatch_offer_revision(model.dispatch_offer_task) &&
      dispatch_json_text(entry, "audit_state") == "available" &&
      (try
        @task_evidence.normalize_offer_draft(
          dispatch_json_field(entry, "offer_draft"),
        )
      catch {
        _ => None
      } noraise {
        value => Some(value)
      })
      is Some(_)
    },
  )
}

///|
fn dispatch_reply_eligible(model : Model) -> Bool {
  dispatch_offer_eligible(model) &&
  !model.dispatch_task_project_id.is_empty() &&
  dispatch_json_text(model.dispatch_offer_task, "projGuid") ==
  model.dispatch_task_project_id &&
  !dispatch_reply_offers(model).is_empty()
}

///|
fn dispatch_reply_history(model : Model) -> Array[Json] {
  if model.dispatch_task_actor_id.is_empty() ||
    dispatch_json_text(model.dispatch_task_commitment, "task_id") !=
    model.dispatch_task_id {
    []
  } else {
    dispatch_continuation_array(
      model.dispatch_task_commitment,
      "offer_reply_history",
    )
  }
}

///|
fn dispatch_reply_find(model : Model) -> DispatchReplyDraft? {
  model.dispatch_reply_drafts
  .filter(item => {
    item.task_id == model.dispatch_task_id &&
    item.project_id == model.dispatch_task_project_id
  })
  .get(0)
}

///|
fn dispatch_reply_operation(
  model : Model,
  task : String,
  key : String,
) -> DispatchReplyDraft? {
  model.dispatch_reply_drafts
  .filter(item => item.task_id == task && item.operation_key == key)
  .get(0)
}

///|
fn dispatch_reply_seed(model : Model) -> DispatchReplyDraft {
  {
    task_id: model.dispatch_task_id,
    project_id: model.dispatch_task_project_id,
    value: dispatch_reply_empty(),
    base_revision: dispatch_offer_revision(model.dispatch_offer_task),
    state: "editing",
    operation_key: "",
    operation_reply: None,
    operation_revision: 0,
    saved_revision: 0,
    note: "尚未保存。请记录已经收到的回复，并明确选择对应方案及依据。",
  }
}

///|
fn dispatch_reply_unlock(
  model : Model,
  task : String,
  project : String,
) -> Model {
  if model.dispatch_task_id == task &&
    model.dispatch_task_project_id == project &&
    model.dispatch_task_pending_action == "offer-reply" {
    { ..model, dispatch_task_pending_action: "", }
  } else {
    model
  }
}

///|
fn dispatch_reply_put(model : Model, draft : DispatchReplyDraft) -> Model {
  let drafts = model.dispatch_reply_drafts.filter(item => {
    !(item.task_id == draft.task_id && item.project_id == draft.project_id)
  })
  drafts.push(draft)
  let next = { ..model, dispatch_reply_drafts: drafts, }
  if !["saving", "sending", "recovering"].contains(draft.state) {
    dispatch_reply_unlock(next, draft.task_id, draft.project_id)
  } else {
    next
  }
}

///|
fn dispatch_reply_changed(
  emit : @rabbita.Emit[Msg],
  model : Model,
  draft : DispatchReplyDraft,
) -> (Cmd, Model) {
  let next = dispatch_reply_put(model, draft)
  (dispatch_reply_persist(emit, next, "", ""), next)
}

///|
fn dispatch_reply_edit(value : Json, field : String, text : String) -> Json {
  let fields = Map::from_array(
    match value {
      Object(old) => old.to_array()
      _ => []
    },
  )
  if [
      "respondent", "received_at", "summary", "source_reference", "correction_reason",
    ].contains(field) {
    fields[field] = Json::string(text)
  } else if field == "kind" &&
    ["", "interested", "changes_requested", "declined", "other"].contains(text) {
    fields[field] = Json::string(text)
  } else if field == "evidence_kind" &&
    ["", "reference", "human_observation"].contains(text) {
    fields[field] = Json::string(text)
    // Switching to observation never creates or retains an invented reference.
    if text != "reference" {
      fields["source_reference"] = Json::null()
    }
  } else if field == "offer_revision" &&
    dispatch_json_text(value, "supersedes_reply_id").is_empty() {
    fields[field] = @json.parse(text) catch { _ => Json::null() }
  }
  Json::object(fields)
}

///|
fn dispatch_reply_superseded(history : Array[Json], id : String) -> Bool {
  history.any(entry => {
    dispatch_json_text(
      dispatch_json_field(entry, "offer_reply"),
      "supersedes_reply_id",
    ) ==
    id
  })
}

///|
fn dispatch_reply_validation(
  model : Model,
  draft : DispatchReplyDraft,
) -> String {
  let revision = dispatch_reply_number(draft.value, "offer_revision")
  if !dispatch_reply_offers(model).any(entry => {
      dispatch_offer_revision(entry) == revision
    }) {
    return "请选择已保存且可核对的具体方案版本。"
  }
  let id = dispatch_json_text(draft.value, "supersedes_reply_id")
  if !id.is_empty() {
    let history = dispatch_reply_history(model)
    if dispatch_reply_superseded(history, id) ||
      !history.any(entry => {
        dispatch_json_text(entry, "reply_id") == id &&
        dispatch_json_text(entry, "audit_state") == "available" &&
        dispatch_reply_number(
          dispatch_json_field(entry, "offer_reply"),
          "offer_revision",
        ) ==
        revision
      }) {
      return "原回复不可核对或已有更正。请查看正式回复历史。"
    }
  }
  ""
}

///|
fn dispatch_reply_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchReplyMsg,
) -> (Cmd, Model) {
  match action {
    Scoped(generation, message) =>
      if generation == model.dispatch_reply_generation {
        dispatch_reply_update(emit, model, message)
      } else {
        (none, model)
      }
    StorageStatus(actor, note) =>
      if actor == model.dispatch_task_actor_id {
        (none, { ..model, dispatch_reply_storage: note, })
      } else {
        (none, model)
      }
    Begin | Correct(_) => {
      if !dispatch_reply_eligible(model) {
        return (none, model)
      }
      if dispatch_reply_find(model) is Some(draft) && draft.state != "saved" {
        return (none, model)
      }
      let draft = dispatch_reply_seed(model)
      let draft = match action {
        Correct(id) => {
          let history = dispatch_reply_history(model)
          guard !id.is_empty() &&
            !dispatch_reply_superseded(history, id) &&
            history
            .filter(entry => {
              dispatch_json_text(entry, "reply_id") == id &&
              dispatch_json_text(entry, "audit_state") == "available"
            })
            .get(0)
            is Some(entry) else {
            return (none, model)
          }
          let value = @task_evidence.normalize_offer_reply(
            dispatch_json_field(entry, "offer_reply"),
          ) catch {
            _ => return (none, model)
          }
          let fields = Map::from_array(
            match value {
              Object(fields) => fields.to_array()
              _ => []
            },
          )
          fields["supersedes_reply_id"] = Json::string(id)
          fields["correction_reason"] = Json::null()
          {
            ..draft,
            value: Json::object(fields),
            note: "更正会追加新收据，原回复仍保留。请说明更正原因。",
          }
        }
        _ => draft
      }
      dispatch_reply_changed(emit, model, draft)
    }
    Edit(field, text) => {
      guard dispatch_reply_find(model) is Some(draft) &&
        draft.state == "editing" &&
        dispatch_reply_eligible(model) else {
        return (none, model)
      }
      dispatch_reply_changed(emit, model, {
        ..draft,
        value: dispatch_reply_edit(draft.value, field, text),
        note: "回复草稿仅保存在当前标签页，尚未写入正式记录。",
      })
    }
    Save => {
      guard dispatch_reply_find(model) is Some(draft) &&
        draft.state == "editing" &&
        dispatch_reply_eligible(model) else {
        return (none, model)
      }
      if draft.base_revision !=
        dispatch_offer_revision(model.dispatch_offer_task) {
        return dispatch_reply_changed(emit, model, {
          ..draft,
          state: "conflict",
          note: "任务版本已改变，草稿保留。请核对后明确使用当前任务版本。",
        })
      }
      let error = dispatch_reply_validation(model, draft)
      if !error.is_empty() {
        return dispatch_reply_changed(emit, model, { ..draft, note: error, })
      }
      let value = @task_evidence.normalize_offer_reply(draft.value) catch {
        @task_evidence.InvalidOfferReply(error) =>
          return dispatch_reply_changed(emit, model, { ..draft, note: error, })
      }
      let frozen = {
        ..draft,
        state: "saving",
        operation_key: "opc-offer-reply-" + dispatch_command_nonce(),
        operation_reply: Some(value),
        operation_revision: draft.base_revision,
        note: "先在当前标签页保留相同请求，再保存回复收据。",
      }
      let next = dispatch_reply_put(
        { ..model, dispatch_task_pending_action: "offer-reply", },
        frozen,
      )
      (
        dispatch_reply_persist(emit, next, frozen.task_id, frozen.operation_key),
        next,
      )
    }
    ReplyStored(actor, task, key, ok) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let next = {
        ..model,
        dispatch_reply_storage: if ok {
          "已保留在当前标签页"
        } else {
          "标签页保存失败，请勿刷新或关闭页面"
        },
      }
      if key.is_empty() {
        return (none, next)
      }
      guard dispatch_reply_operation(next, task, key) is Some(draft) &&
        draft.state == "saving" else {
        return (none, next)
      }
      if !ok ||
        (
          next.dispatch_task_id == task &&
          next.dispatch_task_project_id != draft.project_id
        ) {
        return (
          none,
          dispatch_reply_put(next, {
            ..draft,
            state: "uncertain",
            note: "本次未发送。请保留页面，恢复记录或重试同一请求。",
          }),
        )
      }
      (
        dispatch_reply_write(
          emit,
          actor,
          draft,
          model.dispatch_reply_generation,
        ),
        dispatch_reply_put(next, {
          ..draft,
          state: "sending",
          note: "正在保存回复，等待正式记录核对。",
        }),
      )
    }
    Written(actor, task, key, _, _) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      guard dispatch_reply_operation(model, task, key) is Some(draft) &&
        draft.state == "sending" else {
        return (none, model)
      }
      (
        dispatch_reply_read(emit, actor, draft, model.dispatch_reply_generation),
        dispatch_reply_put(model, {
          ..draft,
          state: "recovering",
          note: "正在读回正式任务并核对此次回复收据。",
        }),
      )
    }
    Recover | Retry => {
      guard dispatch_reply_find(model) is Some(draft) &&
        !draft.operation_key.is_empty() &&
        draft.operation_reply is Some(_) &&
        ["uncertain", "conflict"].contains(draft.state) else {
        return (none, model)
      }
      if action is Retry {
        if draft.state == "conflict" || !dispatch_reply_eligible(model) {
          return (none, model)
        }
        let next = dispatch_reply_put(
          { ..model, dispatch_task_pending_action: "offer-reply", },
          {
            ..draft,
            state: "saving",
            note: "只重试已保留的完全相同回复、版本和请求身份。",
          },
        )
        (
          dispatch_reply_persist(emit, next, draft.task_id, draft.operation_key),
          next,
        )
      } else {
        (
          dispatch_reply_read(
            emit,
            model.dispatch_task_actor_id,
            draft,
            model.dispatch_reply_generation,
          ),
          dispatch_reply_put(model, {
            ..draft,
            state: "recovering",
            note: "正在恢复此次回复的正式保存记录。",
          }),
        )
      }
    }
    Read(actor, task, key, status, body) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      guard dispatch_reply_operation(model, task, key) is Some(draft) &&
        draft.state == "recovering" else {
        return (none, model)
      }
      guard status == 200 &&
        dispatch_decode_snapshot(body, task) is Some(snapshot) &&
        snapshot.project_id == draft.project_id &&
        dispatch_offer_revision(snapshot.offer_task) > 0 else {
        return dispatch_reply_changed(emit, model, {
          ..draft,
          state: "uncertain",
          note: "结果尚未确认，原请求已保留。请恢复记录或明确重试同一请求。",
        })
      }
      let revision = dispatch_offer_revision(snapshot.offer_task)
      let matched = dispatch_reply_receipt_revision(
        snapshot.commitment,
        draft,
        actor,
      )
      let next = if model.dispatch_task_id == task &&
        model.dispatch_task_project_id == draft.project_id &&
        ["", "offer-reply", "load"].contains(model.dispatch_task_pending_action) {
        apply_dispatch_snapshot(model, snapshot)
      } else {
        model
      }
      if matched > 0 && matched <= revision {
        // The canonical history now owns the content; remove tab-local private copy.
        dispatch_reply_changed(emit, next, {
          ..draft,
          state: "saved",
          value: dispatch_reply_empty(),
          operation_reply: None,
          operation_key: "",
          operation_revision: 0,
          base_revision: revision,
          saved_revision: matched,
          note: "回复已保存，正式历史中的准确收据已核对。",
        })
      } else if revision != draft.operation_revision {
        dispatch_reply_changed(emit, next, {
          ..draft,
          state: "conflict",
          note: "任务版本已改变，未找到此次请求的准确收据。草稿保留，请先核对历史。",
        })
      } else {
        dispatch_reply_changed(emit, next, {
          ..draft,
          state: "uncertain",
          note: "尚未找到此次请求的准确收据。可以恢复记录，或明确重试完全相同的请求。",
        })
      }
    }
    Rebase => {
      guard dispatch_reply_find(model) is Some(draft) &&
        draft.state == "conflict" &&
        dispatch_reply_eligible(model) else {
        return (none, model)
      }
      dispatch_reply_changed(emit, model, {
        ..draft,
        state: "editing",
        base_revision: dispatch_offer_revision(model.dispatch_offer_task),
        operation_key: "",
        operation_reply: None,
        operation_revision: 0,
        note: "已使用当前任务版本，目标方案版本保持不变。请重新核对后保存。",
      })
    }
    Discard => {
      guard dispatch_reply_find(model) is Some(draft) &&
        ["editing", "saved", "conflict"].contains(draft.state) else {
        return (none, model)
      }
      let next = {
        ..model,
        dispatch_reply_drafts: model.dispatch_reply_drafts.filter(item => {
          !(item.task_id == draft.task_id && item.project_id == draft.project_id)
        }),
      }
      (dispatch_reply_persist(emit, next, "", ""), next)
    }
    ReplyRestored(actor, text) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let store : DispatchReplyStore = @json.from_json(@json.parse(text)) catch {
        _ =>
          return (
            none,
            {
              ..model,
              dispatch_reply_storage: if text.is_empty() {
                "当前标签页没有回复草稿"
              } else {
                "无法读取标签页草稿，未覆盖当前编辑"
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
          !next.dispatch_reply_drafts.any(item => {
            item.task_id == draft.task_id && item.project_id == draft.project_id
          }) {
          next = dispatch_reply_put(
            next,
            if ["saving", "sending", "recovering"].contains(draft.state) {
              {
                ..draft,
                state: "uncertain",
                note: "页面曾中断。先恢复同一请求的正式保存记录。",
              }
            } else {
              draft
            },
          )
        }
      }
      (
        none,
        {
          ..next,
          dispatch_reply_storage: "已读取当前标签页回复草稿",
        },
      )
    }
  }
}

///|
fn dispatch_reply_receipt_revision(
  commitment : Json,
  draft : DispatchReplyDraft,
  actor : String,
) -> Int {
  if dispatch_json_text(commitment, "task_id") != draft.task_id {
    return 0
  }
  guard draft.operation_reply is Some(expected) else { return 0 }
  for entry in dispatch_continuation_array(commitment, "offer_reply_history") {
    let revision = dispatch_reply_number(entry, "record_revision")
    let value = @task_evidence.normalize_offer_reply(
      dispatch_json_field(entry, "offer_reply"),
    ) catch {
      _ => continue
    }
    let id = dispatch_json_text(entry, "reply_id")
    if !id.is_empty() &&
      id == dispatch_json_text(entry, "event_id") &&
      !dispatch_json_text(entry, "audit_id").is_empty() &&
      dispatch_json_text(entry, "audit_state") == "available" &&
      dispatch_json_text(entry, "idempotency_key") == draft.operation_key &&
      dispatch_json_text(entry, "recorded_by") == actor &&
      revision == draft.operation_revision + 1 &&
      value == expected {
      return revision
    }
  }
  0
}

///|
fn dispatch_reply_after_snapshot(model : Model) -> Model {
  match dispatch_reply_find(model) {
    Some(draft) if ["saving", "sending", "recovering"].contains(draft.state) =>
      { ..model, dispatch_task_pending_action: "offer-reply", }
    _ => model
  }
}
