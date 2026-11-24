///|
// Ordinary local draft data only. Never store authority, credentials, headers,
// session cookies, or a signed request. Once attempted, fields are immutable.
struct DispatchDraft {
  id : String
  task_id : String
  idempotency_key : String
  product_id : String
  project_id : String
  product_snapshot : ProductDefinition?
  title : String
  acceptance : String
  source_reference : String?
  observed_problem : String?
  task_type : String?
  parent_task_id : String?
  offer_draft : Json?
  research_brief : @research_handoff.Brief?
  owner_id : String
  begin_date : String
  end_date : String
  workspace : String
  model : String
  state : String
  attempted : Bool
  recovery_required : Bool
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct DispatchDraftStore {
  version : Int32
  drafts : Array[DispatchDraft]
  recent_tasks : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
enum DispatchDraftMsg {
  Input(String, String)
  Resume(String)
  Park
  New
  Revise(String)
  Discard(String)
  Create
  Recover(String)
  Stored(String, String, Bool)
  Restored(String, String)
  CreateRead(String, String, Int32, String)
  RecoveryRead(String, String, Int32, String)
} derive(Debug, Eq)

///|
fn dispatch_active_draft(model : Model) -> DispatchDraft? {
  model.dispatch_drafts
  .filter(draft => draft.id == model.dispatch_draft_id)
  .get(0)
}

///|
fn dispatch_draft_by_id(model : Model, id : String) -> DispatchDraft? {
  model.dispatch_drafts.filter(draft => draft.id == id).get(0)
}

///|
fn dispatch_replace_draft(model : Model, draft : DispatchDraft) -> Model {
  let exists = model.dispatch_drafts.any(item => item.id == draft.id)
  let drafts = model.dispatch_drafts.map(item => {
    if item.id == draft.id {
      draft
    } else {
      item
    }
  })
  if !exists {
    drafts.push(draft)
  }
  { ..model, dispatch_drafts: drafts, }
}

///|
fn dispatch_remember_recent(model : Model, id : String) -> Model {
  if id.is_empty() {
    return model
  }
  // No cap: each confirmed or uncertain local task keeps its exact recovery ID.
  {
    ..model,
    dispatch_recent_tasks: [id] +
    model.dispatch_recent_tasks.filter(item => item != id),
  }
}

///|
fn dispatch_save_draft(
  emit : @rabbita.Emit[Msg],
  model : Model,
  draft : DispatchDraft,
) -> (Cmd, Model) {
  let next = dispatch_replace_draft(model, draft)
  (dispatch_persist_drafts(emit, next, ""), next)
}

///|
fn dispatch_prepare_draft(
  emit : @rabbita.Emit[Msg],
  model : Model,
  product_id : String,
  project_id : String,
  snapshot : ProductDefinition?,
  force_new : Bool,
) -> (Cmd, Model) {
  let existing = if force_new {
    None
  } else {
    dispatch_prepared_draft(model, product_id, project_id)
  }
  let draft = match existing {
    Some(draft) => draft
    None => {
      let nonce = dispatch_command_nonce()
      {
        id: "draft-" + nonce,
        task_id: "OPC-TASK-" + nonce,
        idempotency_key: "opc-dispatch-create-" + nonce,
        product_id,
        project_id,
        product_snapshot: snapshot,
        title: match snapshot {
          Some(row) => row.name + " · "
          None => ""
        },
        acceptance: "",
        source_reference: None,
        observed_problem: None,
        task_type: None,
        parent_task_id: None,
        offer_draft: None,
        research_brief: None,
        owner_id: "",
        begin_date: "",
        end_date: "",
        workspace: "",
        model: "",
        state: "editing",
        attempted: false,
        recovery_required: false,
        note: "本地草稿，尚未创建正式任务。",
      }
    }
  }
  let next = dispatch_replace_draft(
    {
      ..model,
      page: Dispatch,
      dispatch_draft_id: draft.id,
      dispatch_task_form_open: true,
      products: {
        ..model.products,
        prepared_product_id: draft.product_id,
        prepared_project_id: draft.project_id,
        prepared_product_snapshot: draft.product_snapshot,
      },
      notice: "草稿独立保存；当前正式任务和执行记录保持可恢复。",
    },
    draft,
  )
  (dispatch_persist_drafts(emit, next, ""), next)
}

///|
fn dispatch_draft_form_model(model : Model) -> Model {
  match dispatch_active_draft(model) {
    None => model
    Some(draft) =>
      {
        ..model,
        dispatch_task_title: draft.title,
        dispatch_task_acceptance: draft.acceptance,
        dispatch_task_project_id: draft.project_id,
        dispatch_task_owner_id: draft.owner_id,
        dispatch_task_begin_date: draft.begin_date,
        dispatch_task_end_date: draft.end_date,
        dispatch_task_workspace: draft.workspace,
        dispatch_task_model: draft.model,
        products: {
          ..model.products,
          prepared_product_id: draft.product_id,
          prepared_project_id: draft.project_id,
          prepared_product_snapshot: draft.product_snapshot,
        },
      }
  }
}

///|
fn dispatch_draft_validation(draft : DispatchDraft, actor : String) -> String {
  if draft.offer_draft is Some(value) {
    ignore(@task_evidence.normalize_offer_draft(value)) catch {
      @task_evidence.InvalidOfferDraft(error) => return error
    }
  }
  if draft.title.trim().is_empty() || draft.acceptance.trim().is_empty() {
    "任务名称和可检查的验收标准都是必填项。"
  } else if draft.project_id.trim().is_empty() || actor.trim().is_empty() {
    "项目范围和签名身份不能为空；网关会再次验证它们。"
  } else if draft.begin_date.is_empty() || draft.end_date.is_empty() {
    "计划开始和完成日期不能为空。"
  } else if draft.end_date < draft.begin_date {
    "计划完成日期不能早于开始日期。"
  } else {
    ""
  }
}

///|
fn dispatch_draft_session(
  emit : @rabbita.Emit[Msg],
  model : Model,
  actor : String,
) -> (Cmd, Model) {
  if actor == model.dispatch_task_actor_id && !actor.is_empty() {
    return (none, model)
  }
  // Outcome observations and retained evidence belong to this authenticated
  // tab session. Never expose them across actor changes or a sign-out.
  let reply_session = dispatch_reply_session(
    emit,
    model.dispatch_task_actor_id,
    actor,
    model.dispatch_reply_generation + 1,
  )
  let model = {
    ..model,
    dispatch_outcome_drafts: [],
    dispatch_offer_drafts: [],
    dispatch_reply_drafts: [],
    dispatch_reply_storage: "尚未保留到当前标签页",
    dispatch_reply_generation: model.dispatch_reply_generation + 1,
    dispatch_offer_task: if model.dispatch_task_actor_id.is_empty() &&
      !actor.is_empty() {
      model.dispatch_offer_task
    } else {
      Json::null()
    },
    dispatch_offer_storage: "未保存到此浏览器",
    dispatch_outcome_sequence: model.dispatch_outcome_sequence + 1,
    dispatch_lesson_handoff: {
      ..empty_dispatch_lesson_handoff(),
      request: model.dispatch_lesson_handoff.request + 1,
    },
  }
  let next = if model.dispatch_task_actor_id.is_empty() {
    { ..model, dispatch_task_actor_id: actor, }
  } else {
    // Never expose one authenticated actor's local collection to another.
    {
      ..model,
      dispatch_task_actor_id: actor,
      dispatch_task_selection: model.dispatch_task_selection + 1,
      dispatch_continuation: empty_dispatch_continuation(),
      dispatch_desk_handoff: empty_dispatch_desk_handoff(),
      dispatch_run: None,
      dispatch_task_source_context: Json::null(),
      dispatch_task_commitment: Json::null(),
      dispatch_task_pending_action: "",
      dispatch_task_stage: "loading",
      dispatch_task_report_id: "",
      dispatch_task_report_summary: "",
      dispatch_task_evidence_id: "",
      dispatch_drafts: [],
      dispatch_draft_id: "",
      dispatch_recent_tasks: [],
      dispatch_task_form_open: false,
      products: products_clear_preparation(model.products),
    }
  }
  if actor.is_empty() {
    (
      reply_session,
      {
        ..next,
        dispatch_draft_storage: "未登录，草稿仅保留在当前页面",
      },
    )
  } else {
    (
      @cmd.batch([
        reply_session,
        dispatch_offer_session(emit, actor),
        @cmd.custom_cmd(scheduler => {
          scheduler.add(
            emit(DraftAction(Restored(actor, dispatch_read_drafts(actor)))),
          )
        }),
      ]),
      next,
    )
  }
}

///|
fn dispatch_draft_update(
  emit : @rabbita.Emit[Msg],
  action : DispatchDraftMsg,
  model : Model,
) -> (Cmd, Model) {
  match action {
    Input(field, value) => {
      let draft = match dispatch_active_draft(model) {
        Some(draft) => draft
        None => return (none, model)
      }
      if draft.state != "editing" {
        return (none, model)
      }
      let next = match field {
        "title" => { ..draft, title: value, }
        "acceptance" => { ..draft, acceptance: value, }
        "source_reference" => { ..draft, source_reference: Some(value), }
        "observed_problem" => { ..draft, observed_problem: Some(value), }
        "project_id" =>
          if draft.parent_task_id.unwrap_or("").is_empty() {
            { ..draft, project_id: value, }
          } else {
            draft
          }
        "owner_id" => { ..draft, owner_id: value, }
        "workspace" => { ..draft, workspace: value, }
        "model" => { ..draft, model: value, }
        "begin_date" => { ..draft, begin_date: value, }
        "end_date" => { ..draft, end_date: value, }
        _ => draft
      }
      dispatch_save_draft(emit, model, next)
    }
    Resume(id) =>
      match dispatch_draft_by_id(model, id) {
        Some(draft) if draft.task_type == Some("key_node") =>
          update_model(emit, Navigate(Objectives), {
            ..model,
            dispatch_draft_id: id,
            dispatch_task_form_open: draft.state != "created",
            today: {
              ..model.today,
              project_id: draft.project_id,
              scope: "project",
            },
          })
        Some(draft) if draft.state != "created" =>
          (
            none,
            {
              ..model,
              page: Dispatch,
              dispatch_draft_id: id,
              dispatch_task_form_open: true,
              products: {
                ..model.products,
                prepared_product_id: draft.product_id,
                prepared_project_id: draft.project_id,
                prepared_product_snapshot: draft.product_snapshot,
              },
            },
          )
        Some(draft) =>
          open_dispatch_task(emit, {
            ..model,
            dispatch_task_open_id: draft.task_id,
          })
        None => (none, model)
      }
    Park =>
      (
        none,
        {
          ..model,
          dispatch_task_form_open: false,
          products: products_clear_preparation(model.products),
        },
      )
    New =>
      match dispatch_active_draft(model) {
        Some(draft) =>
          dispatch_prepare_draft(
            emit,
            model,
            draft.product_id,
            draft.project_id,
            draft.product_snapshot,
            true,
          )
        None => dispatch_prepare_draft(emit, model, "", "", None, true)
      }
    Revise(id) => {
      let old = match dispatch_draft_by_id(model, id) {
        Some(draft) => draft
        None => return (none, model)
      }
      if old.state != "rejected" {
        return (none, model)
      }
      let nonce = dispatch_command_nonce()
      let draft = {
        ..old,
        id: "draft-" + nonce,
        task_id: "OPC-TASK-" + nonce,
        idempotency_key: "opc-dispatch-create-" + nonce,
        state: "editing",
        attempted: false,
        recovery_required: false,
        note: "已复制为新草稿；原请求和任务 ID 保留在历史中。",
      }
      dispatch_save_draft(
        emit,
        {
          ..model,
          dispatch_draft_id: draft.id,
          dispatch_task_form_open: true,
          page: Dispatch,
        },
        draft,
      )
    }
    Discard(id) => {
      let draft = match dispatch_draft_by_id(model, id) {
        Some(draft) => draft
        None => return (none, model)
      }
      if draft.state != "editing" &&
        draft.state != "created" &&
        draft.state != "rejected" {
        return (
          none,
          {
            ..model,
            notice: "创建结果待确认。先按保留的任务 ID 恢复正式记录，再移除此本地草稿。",
          },
        )
      }
      let next = {
        ..model,
        dispatch_drafts: model.dispatch_drafts.filter(item => item.id != id),
        dispatch_draft_id: if model.dispatch_draft_id == id {
          ""
        } else {
          model.dispatch_draft_id
        },
        dispatch_task_form_open: model.dispatch_task_form_open &&
        model.dispatch_draft_id != id,
      }
      (dispatch_persist_drafts(emit, next, ""), next)
    }
    Create => {
      let draft = match dispatch_active_draft(model) {
        Some(draft) => draft
        None => return (none, model)
      }
      if draft.state == "uncertain" {
        return dispatch_draft_update(emit, Recover(draft.id), model)
      }
      if draft.state != "editing" && draft.state != "retryable" {
        return (none, model)
      }
      let error = dispatch_draft_validation(draft, model.dispatch_task_actor_id)
      if !error.is_empty() {
        return dispatch_save_draft(emit, model, { ..draft, note: error, })
      }
      let next = dispatch_remember_recent(
        dispatch_replace_draft(model, {
          ..draft,
          state: "saving",
          note: "先保留任务 ID 和创建请求，再发送正式创建。",
        }),
        draft.task_id,
      )
      (dispatch_persist_drafts(emit, next, draft.id), next)
    }
    Stored(actor, create_id, ok) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let next = {
        ..model,
        dispatch_draft_storage: if ok {
          "已保存到此浏览器"
        } else {
          "草稿未保存到此浏览器；保留当前页面并检查存储权限"
        },
      }
      if create_id.is_empty() {
        return (none, next)
      }
      let draft = match dispatch_draft_by_id(next, create_id) {
        Some(draft) => draft
        None => return (none, next)
      }
      if draft.state != "saving" {
        return (none, next)
      }
      if !ok {
        return (
          none,
          dispatch_replace_draft(next, {
            ..draft,
            state: if draft.attempted {
              "retryable"
            } else {
              "editing"
            },
            note: "本地保存失败，本次尚未发送创建。修复浏览器存储后可用同一任务 ID 重试。",
          }),
        )
      }
      (
        dispatch_create_draft(emit, draft, actor),
        dispatch_replace_draft(next, {
          ..draft,
          state: "creating",
          attempted: true,
          note: "创建请求已发送，等待正式收据。",
        }),
      )
    }
    Restored(actor, text) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let saved : DispatchDraftStore? = Some(@json.from_json(@json.parse(text))) catch {
        _ => None
      }
      let mut next = model
      let mut invalid_research = false
      match saved {
        Some(saved) if saved.version == 1 => {
          for draft in saved.drafts {
            if draft.research_brief is Some(brief) &&
              @research_handoff.decode(brief.to_json().stringify()) is Err(_) {
              invalid_research = true
              continue
            }
            if dispatch_draft_by_id(next, draft.id) is None &&
              !draft.id.is_empty() &&
              !draft.task_id.is_empty() &&
              !draft.idempotency_key.is_empty() {
              let restored = if [
                  "saving", "creating", "recovering", "retryable",
                ].contains(draft.state) {
                {
                  ..draft,
                  state: "uncertain",
                  attempted: true,
                  recovery_required: true,
                  note: "页面曾中断；先按已保留的任务 ID 恢复正式记录。",
                }
              } else {
                draft
              }
              next = dispatch_replace_draft(next, restored)
            }
          }
          for id in saved.recent_tasks {
            next = dispatch_remember_recent(next, id)
          }
        }
        _ => ()
      }
      next = {
        ..next,
        dispatch_draft_storage: if invalid_research {
          "部分草稿的研究来源版本或引用损坏，未载入这些草稿；原始浏览器记录未被改写。"
        } else if text.is_empty() || saved is Some(_) {
          "已读取此浏览器草稿"
        } else {
          "草稿记录无法读取；当前页面仍可使用正式任务链接"
        },
      }
      (none, next)
    }
    Recover(id) => {
      let draft = match dispatch_draft_by_id(model, id) {
        Some(draft) => draft
        None => return (none, model)
      }
      if !["uncertain", "retryable"].contains(draft.state) {
        return (none, model)
      }
      let next = dispatch_replace_draft(model, {
        ..draft,
        state: "recovering",
        note: "正在按原任务 ID 恢复创建结果；没有发送新的创建。",
      })
      (dispatch_recover_draft(emit, draft, model.dispatch_task_actor_id), next)
    }
    CreateRead(actor, id, status, body) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let draft = match dispatch_draft_by_id(model, id) {
        Some(draft) => draft
        None => return (none, model)
      }
      if draft.state != "creating" {
        return (none, model)
      }
      if status >= 200 &&
        status < 300 &&
        dispatch_result_text(body, "task", "task_id") == draft.task_id &&
        dispatch_result_text(body, "task", "state") == "pending" {
        dispatch_confirm_draft(emit, model, draft)
      } else if !draft.recovery_required &&
        dispatch_create_definitively_rejected(status, body) {
        dispatch_save_draft(emit, model, {
          ..draft,
          state: "rejected",
          note: "创建被拒绝：" +
          dispatch_response_error(body) +
          "。可修订为新草稿或移除此本地草稿；原任务 ID 仍可检查。",
        })
      } else {
        dispatch_save_draft(emit, model, {
          ..draft,
          state: "uncertain",
          recovery_required: true,
          note: "未确认创建结果。保留相同任务 ID 和请求；先恢复正式记录，再决定是否重试。",
        })
      }
    }
    RecoveryRead(actor, id, status, body) => {
      if actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let draft = match dispatch_draft_by_id(model, id) {
        Some(draft) => draft
        None => return (none, model)
      }
      if draft.state != "recovering" {
        return (none, model)
      }
      if status == 200 &&
        dispatch_decode_snapshot(body, draft.task_id) is Some(_) {
        dispatch_confirm_draft(emit, model, draft)
      } else {
        dispatch_save_draft(emit, model, {
          ..draft,
          state: if status == 404 {
            "retryable"
          } else {
            "uncertain"
          },
          recovery_required: true,
          note: if status == 404 {
            "正式记录尚不存在。可明确重试同一个 ID 和创建请求；不会另建任务身份。"
          } else {
            "读取结果仍未确认；请继续恢复。认证或连接错误不会触发创建。"
          },
        })
      }
    }
  }
}

///|
fn dispatch_confirm_draft(
  emit : @rabbita.Emit[Msg],
  model : Model,
  draft : DispatchDraft,
) -> (Cmd, Model) {
  let next = dispatch_remember_recent(
    dispatch_replace_draft(model, {
      ..draft,
      state: "created",
      note: "正式任务已确认，可通过任务链接恢复。",
    }),
    draft.task_id,
  )
  if [Dispatch, Objectives].contains(model.page) &&
    model.dispatch_task_form_open &&
    model.dispatch_draft_id == draft.id {
    if draft.task_type == Some("key_node") {
      let (read, selected) = update_model(emit, Navigate(Objectives), {
        ..next,
        dispatch_task_form_open: false,
        today: { ..next.today, project_id: draft.project_id, scope: "project", },
      })
      return (
        @cmd.batch([dispatch_persist_drafts(emit, selected, ""), read]),
        selected,
      )
    }
    let (open, selected) = open_dispatch_task(emit, {
      ..next,
      dispatch_task_open_id: draft.task_id,
    })
    (@cmd.batch([dispatch_persist_drafts(emit, selected, ""), open]), selected)
  } else {
    (
      dispatch_persist_drafts(emit, next, ""),
      {
        ..next,
        notice: "正式任务 " +
        draft.task_id +
        " 已确认，当前查看位置保持不变。",
      },
    )
  }
}

///|
fn dispatch_create_definitively_rejected(status : Int32, body : String) -> Bool {
  // This exact service error occurs before a create transaction, unlike an
  // idempotency conflict. Earlier ambiguous attempts still require recovery.
  status == 400 ||
  status == 422 ||
  (
    status == 409 &&
    dispatch_response_error(body) ==
    "project-plan task requires an active project identity"
  )
}

///|
fn dispatch_prepared_draft(
  model : Model,
  product_id : String,
  project_id : String,
) -> DispatchDraft? {
  let matches = fn(draft : DispatchDraft) {
    draft.product_id == product_id &&
    draft.project_id == project_id &&
    draft.task_type != Some("key_node") &&
    draft.parent_task_id.unwrap_or("").is_empty() &&
    draft.state != "created"
  }
  match dispatch_active_draft(model) {
    Some(draft) if matches(draft) => return Some(draft)
    _ => ()
  }
  let mut recent = None
  for draft in model.dispatch_drafts {
    if matches(draft) {
      recent = Some(draft)
    }
  }
  recent
}
