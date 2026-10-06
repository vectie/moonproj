///|
fn dispatch_offer_store(model : Model) -> String {
  ToJson::to_json(DispatchOfferStore::{
    version: 1,
    drafts: model.dispatch_offer_drafts,
  }).stringify()
}

///|
fn dispatch_offer_persist(
  emit : @rabbita.Emit[Msg],
  model : Model,
  task : String,
  key : String,
) -> Cmd {
  let actor = model.dispatch_task_actor_id
  let text = dispatch_offer_store(model)
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      emit(
        OfferAction(
          OfferStored(
            actor,
            task,
            key,
            dispatch_offer_storage_write(actor, text),
          ),
        ),
      ),
    )
  })
}

///|
extern "js" fn dispatch_offer_storage_write(
  actor : String,
  text : String,
) -> Bool =
  #| (actor,text) => { if (!actor || typeof window === 'undefined') return false; try { window.localStorage.setItem('moonproj.dispatch.offers.v1.'+encodeURIComponent(actor),text); return true; } catch (_) { return false; } }

///|
extern "js" fn dispatch_offer_storage_read(actor : String) -> String =
  #| actor => { if (!actor || typeof window === 'undefined') return ''; try { return window.localStorage.getItem('moonproj.dispatch.offers.v1.'+encodeURIComponent(actor)) || ''; } catch (_) { return 'storage-unavailable'; } }

///|
fn dispatch_offer_session(emit : @rabbita.Emit[Msg], actor : String) -> Cmd {
  if actor.is_empty() {
    return none
  }
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      emit(
        OfferAction(OfferRestored(actor, dispatch_offer_storage_read(actor))),
      ),
    )
  })
}

///|
fn dispatch_offer_update_body(
  actor : String,
  draft : DispatchOfferDraft,
) -> Json {
  {
    "idempotency_key": draft.operation_key,
    "offer_base_revision": draft.operation_revision,
    "offer_draft": draft.operation_offer.unwrap_or(Json::null()),
    "authority": {
      "active": true,
      "principal_id": "principal-opc-dispatch",
      "actor_id": actor,
      "capability": "project:task:update",
      "scope": "project:" + draft.project_id,
    },
  }
}

///|
fn dispatch_offer_write(
  emit : @rabbita.Emit[Msg],
  actor : String,
  draft : DispatchOfferDraft,
) -> Cmd {
  let body = dispatch_offer_update_body(actor, draft).stringify()
  @cmd.custom_cmd(scheduler => {
    dispatch_offer_put_request(
      "/api/company/plan/tasks/" + dispatch_url_encode(draft.task_id),
      body,
      (status, text) => {
        scheduler.add(
          emit(
            OfferAction(
              Written(actor, draft.task_id, draft.operation_key, status, text),
            ),
          ),
        )
      },
    )
  })
}

///|
extern "js" fn dispatch_offer_put_request(
  url : String,
  body : String,
  receive : (Int, String) -> Unit,
) =
  #| (url,body,receive) => { fetch(url,{method:'PUT',credentials:'same-origin',headers:{'Content-Type':'application/json',Accept:'application/json'},body}).then(response=>response.text().then(text=>receive(response.status,text))).catch(()=>receive(0,'')); }

///|
fn dispatch_offer_read(
  emit : @rabbita.Emit[Msg],
  actor : String,
  draft : DispatchOfferDraft,
) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    dispatch_offer_get_request(
      "/api/company/tasks/" + dispatch_url_encode(draft.task_id),
      (status, text) => {
        scheduler.add(
          emit(
            OfferAction(
              Read(actor, draft.task_id, draft.operation_key, status, text),
            ),
          ),
        )
      },
    )
  })
}

///|
extern "js" fn dispatch_offer_get_request(
  url : String,
  receive : (Int, String) -> Unit,
) =
  #| (url,receive) => { fetch(url,{method:'GET',credentials:'same-origin',headers:{Accept:'application/json'}}).then(response=>response.text().then(text=>receive(response.status,text))).catch(()=>receive(0,'')); }

///|
fn dispatch_offer_export(
  _emit : @rabbita.Emit[Msg],
  model : Model,
  is_local : Bool,
) -> (Cmd, Model) {
  let (value, task_id, project_id, revision) = if is_local {
    guard dispatch_active_draft(model) is Some(draft) &&
      draft.offer_draft is Some(value) else {
      return (none, model)
    }
    (value, draft.task_id, draft.project_id, 0)
  } else {
    match dispatch_offer_find(model, model.dispatch_task_id) {
      Some(draft) =>
        (
          draft.value,
          draft.task_id,
          draft.project_id,
          if draft.state == "saved" || draft.state == "historical" {
            draft.saved_revision
          } else {
            0
          },
        )
      None =>
        (
          dispatch_json_field(model.dispatch_offer_task, "offer_draft"),
          model.dispatch_task_id,
          model.dispatch_task_project_id,
          dispatch_offer_canonical_revision(model),
        )
    }
  }
  if !is_local &&
    dispatch_offer_find(model, model.dispatch_task_id) is None &&
    revision == 0 {
    return (
      none,
      {
        ..model,
        notice: "当前方案内容可查看，但缺少可核对的方案保存版本，暂不导出正式方案。",
      },
    )
  }
  let text = @task_evidence.offer_draft_markdown(
    value,
    task_id~,
    project_id~,
    revision~,
  ) catch {
    @task_evidence.InvalidOfferDraft(error) =>
      return (
        none,
        { ..model, notice: "导出前请修正方案格式：" + error, },
      )
  }
  (
    @cmd.custom_cmd(_ => dispatch_offer_download(text)),
    {
      ..model,
      notice: "已导出报价方案草稿；没有发送给客户，也没有产生合同或付款。",
    },
  )
}

///|
extern "js" fn dispatch_offer_download(text : String) =
  #| text => { const blob=new Blob([text],{type:'text/markdown;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='moonproj-offer-draft.md';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000); }
